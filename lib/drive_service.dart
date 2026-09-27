import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'drive_base.dart';

export 'drive_base.dart'
    show DriveItem, kImageExtensions, DriveConn, DriveBusy, DriveUploadJob;

/// "Drive" local: almacena las imágenes del admin en carpetas reales del
/// sistema (Documents/HardStreetDrive), estilo Google Drive.
class DriveService extends DriveBase {
  DriveService() {
    _init();
  }

  /// Constructor para pruebas: usa una carpeta temporal como raíz.
  @visibleForTesting
  DriveService.testRoot(Directory root) {
    _root = root;
    conn = DriveConn.online;
    refresh();
  }

  static const rootName = 'HardStreetDrive';

  /// Raíz absoluta del drive (p.ej. ...\Documents\HardStreetDrive).
  Directory? _root;
  Directory get root {
    final r = _root;
    if (r == null) {
      throw StateError('Drive aun no inicializado');
    }
    return r;
  }

  String _absolute(List<String> rel) =>
      [root.path, ...rel].join(Platform.pathSeparator);

  Future<void> _init() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final driveRoot = Directory(
        [docs.path, rootName].join(Platform.pathSeparator),
      );
      if (!driveRoot.existsSync()) {
        await driveRoot.create(recursive: true);
      }
      _root = driveRoot;
      conn = DriveConn.online;
      await refresh();
    } catch (e) {
      error = 'No se pudo iniciar el almacenamiento: $e';
      conn = DriveConn.offline;
      notifyListeners();
    }
  }

  /// Vuelve a leer la carpeta actual y actualiza la lista.
  @override
  Future<void> refresh() async {
    if (_root == null) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final dir = Directory(_absolute(path));
      if (!dir.existsSync()) {
        // La carpeta fue borrada por fuera: regresa a la raiz.
        path = [];
        await refresh();
        return;
      }
      final entities = dir.listSync();
      final folders = <DriveItem>[];
      final files = <DriveItem>[];
      for (final e in entities) {
        final name = e.path.split(Platform.pathSeparator).last;
        if (name.startsWith('.')) continue;
        if (e is Directory) {
          folders.add(DriveItem(
            name: name,
            isFolder: true,
            modified: e.statSync().modified,
            childCount: _countChildren(e),
          ));
        } else if (e is File && hasImageExt(name)) {
          final st = e.statSync();
          files.add(DriveItem(
            name: name,
            isFolder: false,
            modified: st.modified,
            size: st.size,
          ));
        }
      }
      int byName(DriveItem a, DriveItem b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase());
      folders.sort(byName);
      files.sort(byName);
      updateItems([...folders, ...files]);
      conn = DriveConn.online;
    } catch (e) {
      error = 'No se pudo leer la carpeta: $e';
      conn = DriveConn.offline;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  int _countChildren(Directory dir) {
    try {
      return dir
          .listSync()
          .where((e) =>
              !(e.path.split(Platform.pathSeparator).last.startsWith('.')) &&
              (e is Directory ||
                  (e is File && hasImageExt(e.path))))
          .length;
    } catch (_) {
      return 0;
    }
  }

  /// Copia archivos locales a la carpeta actual, uno por trabajo con
  /// progreso (no bloquea la UI; usa el mismo panel que el modo remoto).
  @override
  Future<int> uploadFromPaths(List<String> sources) async {
    if (sources.isEmpty) return 0;
    var saved = 0;
    final dir = Directory(_absolute(path));
    for (final src in sources) {
      final f = File(src);
      if (!f.existsSync()) continue;
      // Acepta rutas con / o \ mezclados (drop externo, file_selector…).
      final fileName = src.split(RegExp(r'[\\/]')).last;
      final job = DriveUploadJob(
        id: '$src-${DateTime.now().microsecondsSinceEpoch}',
        name: fileName,
        thumb: src,
        total: f.lengthSync(),
      );
      addUploadJob(job);
      try {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        // Normaliza separadores para extraer bien el nombre en cualquier OS.
        var name = _sanitize(fileName);
        var dest = File([dir.path, name].join(Platform.pathSeparator));
        var i = 1;
        final base = name.contains('.')
            ? name.substring(0, name.lastIndexOf('.'))
            : name;
        final ext =
            name.contains('.') ? name.substring(name.lastIndexOf('.')) : '';
        while (dest.existsSync()) {
          dest = File([dir.path, '$base ($i)$ext'].join(Platform.pathSeparator));
          i++;
        }
        await f.copy(dest.path);
        job.sent = job.total;
        notifyUploadProgress();
        finishUploadJob(job);
        saved++;
      } catch (e) {
        finishUploadJob(job, error: e.toString());
      }
    }
    await refresh();
    return saved;
  }

  /// Crea una subcarpeta en la ubicación actual.
  @override
  Future<void> createFolder(String name) async {
    final safe = _sanitize(name);
    if (safe.isEmpty) throw 'El nombre de la carpeta no es válido';
    final dir = Directory(_absolute([...path, safe]));
    if (dir.existsSync()) throw 'Ya existe una carpeta con ese nombre';
    await dir.create(recursive: true);
    await refresh();
  }

  /// Renombra carpeta o imagen.
  @override
  Future<void> rename(DriveItem item, String newName) async {
    var safe = _sanitize(newName);
    if (safe.isEmpty) throw 'El nombre no es válido';
    if (!item.isFolder && !hasImageExt(safe)) {
      safe = '$safe${extOf(item.name)}';
    }
    final oldPath = _absolute([...path, item.name]);
    final newPath = _absolute([...path, safe]);
    if (newPath == oldPath) return;
    if (FileSystemEntity.typeSync(newPath) == FileSystemEntityType.notFound) {
      // Libre
    } else {
      throw 'Ya existe un elemento con ese nombre';
    }
    await (item.isFolder ? Directory(oldPath) : File(oldPath)).rename(newPath);
    await refresh();
  }

  @override
  Future<void> delete(DriveItem item) async {
    final p = _absolute([...path, item.name]);
    final e = item.isFolder ? Directory(p) : File(p);
    await e.delete(recursive: true);
    await refresh();
  }

  // ==================== Operaciones en lote (selección múltiple) ====================

  /// Mueve los elementos [names] de la carpeta actual a [targetPath].
  /// Evita soltar una carpeta dentro de sí misma y renombra si hay colisión.
  @override
  Future<({int moved, List<String> errors})> moveItems(
    List<String> names,
    List<String> targetPath,
  ) {
    return runBusy(DriveBusy.moving, 'Moviendo elementos…', () async {
      var moved = 0;
      final errors = <String>[];
      final targetAbs = _absolute(targetPath);

      for (final name in names) {
        final srcPath = _absolute([...path, name]);
        final isFolder =
            FileSystemEntity.typeSync(srcPath) == FileSystemEntityType.directory;

        // No mover una carpeta dentro de sí misma ni de sus subcarpetas.
        final srcNorm = '${srcPath.replaceAll('\\', '/')}/';
        final tgtNorm = '${targetAbs.replaceAll('\\', '/')}/';
        if (isFolder && tgtNorm.startsWith(srcNorm)) {
          errors.add('No puedes mover "$name" dentro de sí misma');
          continue;
        }
        // Ya está ahí
        if (path.join('/') == targetPath.join('/')) {
          errors.add('"$name" ya está en esa carpeta');
          continue;
        }

        // Renombrar si el destino ya tiene un elemento con el mismo nombre.
        var destName = name;
        var i = 1;
        final base = name.contains('.') && !isFolder
            ? name.substring(0, name.lastIndexOf('.'))
            : name;
        final ext = name.contains('.') && !isFolder
            ? name.substring(name.lastIndexOf('.'))
            : '';
        while (FileSystemEntity.typeSync(
                [targetAbs, destName].join(Platform.pathSeparator)) !=
            FileSystemEntityType.notFound) {
          destName = '$base ($i)$ext';
          i++;
        }

        try {
          await (isFolder ? Directory(srcPath) : File(srcPath))
              .rename([targetAbs, destName].join(Platform.pathSeparator));
          moved++;
        } catch (e) {
          errors.add('No se pudo mover "$name": $e');
        }
      }
      await refresh();
      return (moved: moved, errors: errors);
    });
  }

  /// Copia los elementos [names] de la carpeta actual a [targetPath]
  /// (carpetas se copian recursivamente, con renombrado si hay colisión).
  @override
  Future<({int copied, List<String> errors})> copyItems(
    List<String> names,
    List<String> targetPath,
  ) {
    return runBusy(DriveBusy.copying, 'Copiando elementos…', () async {
      var copied = 0;
      final errors = <String>[];
      final targetAbs = _absolute(targetPath);

      for (final name in names) {
        final srcPath = _absolute([...path, name]);
        final type = FileSystemEntity.typeSync(srcPath);
        final isFolder = type == FileSystemEntityType.directory;

        // Copiar una carpeta dentro de sí misma es un ciclo infinito.
        final srcNorm = '${srcPath.replaceAll('\\', '/')}/';
        final tgtNorm = '${targetAbs.replaceAll('\\', '/')}/';
        if (isFolder && tgtNorm.startsWith(srcNorm)) {
          errors.add('No puedes copiar "$name" dentro de sí misma');
          continue;
        }

        // Renombrar si hay colisión en destino.
        var destName = name;
        var i = 1;
        final base = name.contains('.') && !isFolder
            ? name.substring(0, name.lastIndexOf('.'))
            : name;
        final ext = name.contains('.') && !isFolder
            ? name.substring(name.lastIndexOf('.'))
            : '';
        while (FileSystemEntity.typeSync(
                [targetAbs, destName].join(Platform.pathSeparator)) !=
            FileSystemEntityType.notFound) {
          destName = '$base ($i)$ext';
          i++;
        }
        final destPath = [targetAbs, destName].join(Platform.pathSeparator);

        try {
          if (isFolder) {
            await _copyDirectory(Directory(srcPath), Directory(destPath));
          } else {
            await File(srcPath).copy(destPath);
          }
          copied++;
        } catch (e) {
          errors.add('No se pudo copiar "$name": $e');
        }
      }
      await refresh();
      return (copied: copied, errors: errors);
    });
  }

  Future<void> _copyDirectory(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final entity in src.list()) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name.startsWith('.')) continue;
      final newPath = [dst.path, name].join(Platform.pathSeparator);
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      } else if (entity is File && hasImageExt(name)) {
        await entity.copy(newPath);
      }
    }
  }

  /// Elimina en lote los elementos [names] de la carpeta actual.
  @override
  Future<({int deleted, List<String> errors})> deleteItems(
      List<String> names) {
    return runBusy(DriveBusy.deleting, 'Eliminando elementos…', () async {
      var deleted = 0;
      final errors = <String>[];
      for (final name in names) {
        final p = _absolute([...path, name]);
        final type = FileSystemEntity.typeSync(p);
        if (type == FileSystemEntityType.notFound) continue;
        try {
          final e = type == FileSystemEntityType.directory
              ? Directory(p)
              : File(p) as FileSystemEntity;
          await e.delete(recursive: true);
          deleted++;
        } catch (e) {
          errors.add('No se pudo eliminar "$name"');
        }
      }
      await refresh();
      return (deleted: deleted, errors: errors);
    });
  }

  String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();

  /// Nombres de subcarpetas de una ruta relativa (para el selector de destino).
  @override
  List<String> listFolders(List<String> rel) {
    final dir = Directory(_absolute(rel));
    if (!dir.existsSync()) return const [];
    final names = dir.listSync()
        .whereType<Directory>()
        .map((d) => d.path.split(Platform.pathSeparator).last)
        .where((n) => !n.startsWith('.'))
        .toList();
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  /// Ruta absoluta de un archivo/carpeta para previsualizarlo.
  @override
  String absolutePathOf(DriveItem item) => _absolute([...path, item.name]);
}

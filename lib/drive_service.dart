import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Elemento del Drive: carpeta o imagen.
@immutable
class DriveItem {
  const DriveItem({
    required this.name,
    required this.isFolder,
    this.modified,
    this.size,
    this.childCount = 0,
  });

  final String name;
  final bool isFolder;
  final DateTime? modified;
  final int? size;
  final int childCount;

  DriveItem copyWith({int? childCount}) => DriveItem(
        name: name,
        isFolder: isFolder,
        modified: modified,
        size: size,
        childCount: childCount ?? this.childCount,
      );
}

const List<String> kImageExtensions = [
  '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp',
];

/// "Drive" local: almacena las imágenes del admin en carpetas reales del
/// sistema (Documents/HardStreetDrive), estilo Google Drive.
class DriveService extends ChangeNotifier {
  DriveService() {
    _init();
  }

  /// Constructor para pruebas: usa una carpeta temporal como raíz.
  @visibleForTesting
  DriveService.testRoot(Directory root) {
    _root = root;
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

  /// Ruta relativa actual dentro del drive, p.ej. ['ReynaCoot', 'Fiesta'].
  List<String> path = [];

  String? _search;
  String? get search => _search;

  bool loading = false;
  String? error;

  List<DriveItem> _items = const [];
  List<DriveItem> get items => _items;

  bool get isReady => _root != null;

  String get locationLabel =>
      path.isEmpty ? 'Mi Drive' : path.join(' / ');

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
      await refresh();
    } catch (e) {
      error = 'No se pudo iniciar el almacenamiento: $e';
      notifyListeners();
    }
  }

  /// Vuelve a leer la carpeta actual y actualiza la lista.
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
        } else if (e is File && kImageExtensions.contains(_ext(name))) {
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
      _items = [...folders, ...files];
    } catch (e) {
      error = 'No se pudo leer la carpeta: $e';
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
                  (e is File && kImageExtensions.contains(_ext(e.path)))))
          .length;
    } catch (_) {
      return 0;
    }
  }

  String _ext(String name) {
    final i = name.lastIndexOf('.');
    return i < 0 ? '' : name.substring(i).toLowerCase();
  }

  void setSearch(String? value) {
    _search = (value == null || value.trim().isEmpty) ? null : value.trim();
    notifyListeners();
  }

  List<DriveItem> get visibleItems {
    if (_search == null) return _items;
    final q = _search!.toLowerCase();
    return _items.where((i) => i.name.toLowerCase().contains(q)).toList();
  }

  Future<void> openFolder(String name) async {
    path = [...path, name];
    setSearch(null);
    await refresh();
  }

  Future<void> openPath(List<String> segments) async {
    path = List.of(segments);
    setSearch(null);
    await refresh();
  }

  Future<void> goUp() async {
    if (path.isEmpty) return;
    path = path.sublist(0, path.length - 1);
    setSearch(null);
    await refresh();
  }

  /// Copia archivos locales (rutas absolutas) a la carpeta actual.
  Future<int> uploadFromPaths(List<String> sources) async {
    if (sources.isEmpty) return 0;
    final dir = Directory(_absolute(path));
    var saved = 0;
    for (final src in sources) {
      final f = File(src);
      if (!f.existsSync()) continue;
      // Normaliza separadores para extraer bien el nombre en cualquier OS.
      final normalized = src.replaceAll('/', Platform.pathSeparator);
      var name = normalized.split(Platform.pathSeparator).last;
      name = _sanitize(name);
      var dest = File([dir.path, name].join(Platform.pathSeparator));
      var i = 1;
      final base = name.contains('.')
          ? name.substring(0, name.lastIndexOf('.'))
          : name;
      final ext = name.contains('.') ? name.substring(name.lastIndexOf('.')) : '';
      while (dest.existsSync()) {
        dest = File([dir.path, '$base ($i)$ext'].join(Platform.pathSeparator));
        i++;
      }
      await f.copy(dest.path);
      saved++;
    }
    await refresh();
    return saved;
  }

  /// Crea una subcarpeta en la ubicación actual.
  Future<void> createFolder(String name) async {
    final safe = _sanitize(name);
    if (safe.isEmpty) throw 'El nombre de la carpeta no es válido';
    final dir = Directory(_absolute([...path, safe]));
    if (dir.existsSync()) throw 'Ya existe una carpeta con ese nombre';
    await dir.create(recursive: true);
    await refresh();
  }

  /// Renombra carpeta o imagen.
  Future<void> rename(DriveItem item, String newName) async {
    var safe = _sanitize(newName);
    if (safe.isEmpty) throw 'El nombre no es válido';
    if (!item.isFolder && !_safeHasImageExt(safe)) {
      safe = '$safe${_ext(item.name)}';
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

  Future<void> delete(DriveItem item) async {
    final p = _absolute([...path, item.name]);
    final e = item.isFolder ? Directory(p) : File(p);
    await e.delete(recursive: true);
    await refresh();
  }

  // ==================== Operaciones en lote (selección múltiple) ====================

  /// Mueve los elementos [names] de la carpeta actual a [targetPath].
 /// Evita soltar una carpeta dentro de sí misma y renombra si hay colisión.
  Future<({int moved, List<String> errors})> moveItems(
    List<String> names,
    List<String> targetPath,
  ) async {
    var moved = 0;
    final errors = <String>[];
    final targetAbs = _absolute(targetPath);

    for (final name in names) {
      final srcPath = _absolute([...path, name]);
      final isFolder = FileSystemEntity.typeSync(srcPath) == FileSystemEntityType.directory;

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
      while (FileSystemEntity.typeSync([targetAbs, destName].join(Platform.pathSeparator)) !=
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
  }

  /// Copia los elementos [names] de la carpeta actual a [targetPath]
  /// (carpetas se copian recursivamente, con renombrado si hay colisión).
  Future<({int copied, List<String> errors})> copyItems(
    List<String> names,
    List<String> targetPath,
  ) async {
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
      while (FileSystemEntity.typeSync([targetAbs, destName].join(Platform.pathSeparator)) !=
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
  }

  Future<void> _copyDirectory(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final entity in src.list()) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name.startsWith('.')) continue;
      final newPath = [dst.path, name].join(Platform.pathSeparator);
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      } else if (entity is File &&
          kImageExtensions.contains(_ext(name))) {
        await entity.copy(newPath);
      }
    }
  }

  /// Elimina en lote los elementos [names] de la carpeta actual.
  Future<({int deleted, List<String> errors})> deleteItems(
    List<String> names,
  ) async {
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
  }

  String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();

  /// Nombres de subcarpetas de una ruta relativa (para el selector de destino).
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

  bool _safeHasImageExt(String name) =>
      kImageExtensions.contains(_ext(name));

  /// Ruta absoluta de un archivo/carpeta para previsualizarlo.
  String absolutePathOf(DriveItem item) => _absolute([...path, item.name]);
}

import 'dart:async';
import 'dart:io';

import 'package:cross_file/cross_file.dart';

import 'drive_base.dart';
import 'local_share_service.dart';
import 'share_permissions.dart';

// ==================================================================
// HARD STREET ADMIN - Una carpeta COMPARTIDA, vista como el Drive
// ==================================================================
// Es el adaptador que hace que una carpeta compartida se abra con la MISMA
// pantalla del módulo Archivos: la misma cuadrícula y lista, el recuadro de
// selección, el clic derecho, arrastrar y soltar, subir, mover, renombrar,
// eliminar y el visor. En vez de duplicar todo eso en el módulo de
// compartidos, se implementa aquí el contrato [DriveBase] contra los
// endpoints /api/local/* del servidor del drive.
//
// Lo que se puede hacer NO lo decide el rol: lo decidió quien compartió la
// carpeta ([rights]). `canDo` traduce eso a las acciones del Drive:
//
//   Ver       → se puede abrir/listar
//   Descargar → download
//   Editar    → update y delete (renombrar, mover, eliminar)
//   Crear     → create (subir, nueva carpeta, copiar/pegar)
//
// Las operaciones siguen siendo del servidor: aquí solo se piden.
// ==================================================================

class SharedDrive extends DriveBase {
  SharedDrive({
    required this.service,
    required this.shareId,
    required this.label,
    required this.rights,
    this.sectionLabel,
  }) {
    conn = DriveConn.online;
  }

  final LocalShareService service;
  final int shareId;

  /// Nombre de la carpeta compartida (miga de la carpeta y encabezado).
  final String label;

  /// Nombre del MÓDULO del que se abrió ("Compartido conmigo" / "Lo que
  /// comparto"): es la miga RAÍZ y, al tocarla, se vuelve al listado.
  final String? sectionLabel;

  /// Lo que concedió quien comparte (el dueño tiene todo).
  final SharePermissions rights;

  /// Subcarpetas ya listadas (el diálogo de Mover/Copiar las pide sin red).
  final Map<String, List<String>> _folders = {};

  String _key(List<String> rel) => rel.join('/');

  @override
  bool get isRemote => true;

  @override
  String get rootLabel => sectionLabel ?? label;

  @override
  String? get crumbFolderLabel => sectionLabel == null ? null : label;

  @override
  bool canDo(String action) => switch (action) {
    'download' => rights.download,
    'update' => rights.edit,
    'delete' => rights.edit,
    'create' => rights.create,
    _ => rights.view,
  };

  @override
  String get locationLabel => path.isEmpty ? label : path.join(' / ');

  @override
  Future<void> refresh() async {
    final ticket = beginRefresh();
    loading = true;
    error = null;
    notifyListeners();
    try {
      final data = await service.list(shareId, path);
      final listing = <DriveItem>[
        for (final i in data.items)
          DriveItem(
            name: i.name,
            isFolder: i.isFolder,
            size: i.size,
            // El conteo y la fecha los manda el servidor: la tarjeta dice
            // "N elementos" de verdad (antes todas decían 0).
            modified: i.modified,
            childCount: i.childCount,
            countKnown: i.countKnown,
          ),
      ];
      _folders[_key(path)] = [
        for (final i in data.items)
          if (i.isFolder) i.name,
      ];
      conn = DriveConn.online;
      applyRefresh(ticket, listing);
    } catch (e) {
      failRefresh(_friendly(e));
      return;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Mensaje legible de un fallo del servidor (sin el "Exception: " de Dart).
  static String _friendly(Object e) {
    final s = '$e';
    return s.startsWith('Exception: ') ? s.substring(11) : s;
  }

  @override
  String absolutePathOf(DriveItem item) =>
      service.fileUrl(shareId, [...path, item.name]);

  @override
  String absolutePathIn(List<String> rel, DriveItem item) =>
      service.fileUrl(shareId, [...rel, item.name]);

  @override
  String thumbSource(DriveItem item, {int width = 320}) =>
      service.thumbUrl(shareId, [...path, item.name], width: width);

  /// El servidor saca el PRIMER FOTOGRAMA de un vídeo y la vista previa de un
  /// RAW: también enseñan miniatura en una carpeta compartida.
  @override
  bool canThumb(DriveItem item) =>
      item.kind == DriveItemKind.image ||
      item.kind == DriveItemKind.raw ||
      item.kind == DriveItemKind.video;

  @override
  String thumbSourceIn(List<String> rel, DriveItem item, {int width = 320}) =>
      service.thumbUrl(shareId, [...rel, item.name], width: width);

  @override
  String fullSource(DriveItem item, {int? previewWidth}) => previewWidth == null
      ? service.fileUrl(shareId, [...path, item.name])
      : service.thumbUrl(shareId, [...path, item.name], width: previewWidth);

  /// REPRODUCCIÓN: los vídeos grandes se ven en CALIDAD LIGERA (el servidor
  /// los reencoda a 720p al vuelo, sin bajar el original completo).
  @override
  String playSource(DriveItem item) => service.fileUrl(shareId, [
    ...path,
    item.name,
  ], light: wantsLightPlayback(item));

  @override
  List<String> listFolders(List<String> rel) => _folders[_key(rel)] ?? const [];

  @override
  Future<List<String>> listChildFolders(List<String> rel) async =>
      (await listFolderItems(rel))
          .where((i) => i.isFolder)
          .map((i) => i.name)
          .toList(growable: false);

  @override
  Future<List<DriveItem>> listFolderItems(List<String> rel) async {
    final data = await service.list(shareId, rel);
    return [
      for (final i in data.items)
        DriveItem(
          name: i.name,
          isFolder: i.isFolder,
          size: i.size,
          modified: i.modified,
          childCount: i.childCount,
          countKnown: i.countKnown,
        ),
    ];
  }

  // ==================== Escritura ====================

  @override
  Future<int> uploadFromPaths(
    List<String> sources, {
    bool overwrite = false,
  }) async {
    final batch = newUploadBatch();
    var saved = 0;
    for (final src in sources) {
      final name = src.split(RegExp(r'[\\/]')).last;
      final bytes = await File(src).readAsBytes();
      if (await _uploadOne(name, bytes, src, batch, overwrite)) saved++;
    }
    return saved;
  }

  @override
  Future<int> uploadFromFiles(
    List<XFile> sources, {
    bool overwrite = false,
  }) async {
    final batch = newUploadBatch();
    var saved = 0;
    for (final f in sources) {
      final name = f.name.isNotEmpty
          ? f.name
          : f.path.split(RegExp(r'[\\/]')).last;
      final bytes = await f.readAsBytes();
      if (await _uploadOne(name, bytes, f.path, batch, overwrite)) saved++;
    }
    return saved;
  }

  int _uploadSeq = 0;

  Future<bool> _uploadOne(
    String name,
    List<int> bytes,
    String source,
    String batch,
    bool overwrite,
  ) async {
    final job = DriveUploadJob(
      id: 'su${++_uploadSeq}-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      thumb: source,
      total: bytes.length,
      batch: batch,
    );
    addUploadJob(job);
    final ok = await runUploadWithRetries(job, () async {
      await service.uploadBytes(
        shareId,
        path,
        name,
        bytes,
        overwrite: overwrite,
      );
      job.sent = bytes.length;
      notifyUploadProgress();
    });
    if (ok) unawaited(refresh());
    return ok;
  }

  @override
  Future<void> retryUpload(String jobId) async {
    final job = uploadJobById(jobId);
    if (job == null) return;
    List<int> bytes;
    try {
      if (job.file != null) {
        bytes = await job.file!.readAsBytes();
      } else if (job.thumb.isNotEmpty) {
        bytes = await File(job.thumb).readAsBytes();
      } else {
        throw 'no se encontró el archivo original';
      }
    } catch (e) {
      finishUploadJob(job, error: '$e');
      return;
    }
    await runUploadWithRetries(job, () async {
      await service.uploadBytes(shareId, path, job.name, bytes);
      job.sent = bytes.length;
      notifyUploadProgress();
    });
    unawaited(refresh());
  }

  @override
  Future<void> createFolder(String name) async {
    await service.mkdir(shareId, path, name);
    await refresh();
  }

  @override
  Future<void> rename(DriveItem item, String newName) async {
    // Un ARCHIVO conserva su extensión: renombrar "foto.jpg" a "foto" sin más
    // la volvía invisible (parecía que el renombrado borraba el archivo) y a
    // un "video.mp4" le pegaba la extensión dos veces. Igual que en el Drive.
    var name = newName.trim();
    if (!item.isFolder && extOf(name).isEmpty) {
      name = '$name${extOf(item.name)}';
    }
    if (name.isEmpty || name == item.name) return;
    await service.rename(shareId, [...path, item.name], name);
    await refresh();
  }

  @override
  Future<void> delete(DriveItem item) => deleteItems([item.name]);

  @override
  Future<({int deleted, List<String> errors})> deleteItems(
    List<String> names,
  ) async {
    final result = await service.deleteItems(shareId, path, names);
    await refresh();
    return result;
  }

  @override
  Future<({int moved, List<String> errors})> moveItems(
    List<String> names,
    List<String> targetPath,
  ) async {
    final result = await service.transfer(
      shareId,
      move: true,
      from: path,
      names: names,
      to: targetPath,
    );
    await refresh();
    return result;
  }

  @override
  Future<({int copied, List<String> errors})> copyItems(
    List<String> names,
    List<String> targetPath,
  ) async {
    final result = await service.transfer(
      shareId,
      move: false,
      from: path,
      names: names,
      to: targetPath,
    );
    await refresh();
    return (copied: result.moved, errors: result.errors);
  }

  @override
  Future<List<String>> filterExisting(List<String> names) async {
    final here = items.map((i) => i.name).toSet();
    return [
      for (final n in names)
        if (here.contains(n)) n,
    ];
  }
}

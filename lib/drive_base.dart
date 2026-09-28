import 'dart:async';

import 'package:flutter/foundation.dart';

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

/// Estados de conexión con el servidor del drive.
enum DriveConn { checking, online, offline }

/// Operación en curso para los overlays de carga.
enum DriveBusy { none, uploading, moving, copying, deleting, downloading }

/// Cuántas subidas corren EN PARALELO (pool de trabajadores).
/// El resto espera su turno en cola, pero TODAS se ven en el panel.
const int kUploadParallel = 3;

/// Trabajo de subida individual (panel estilo Drive, progreso por archivo).
class DriveUploadJob {
  DriveUploadJob({
    required this.id,
    required this.name,
    required this.thumb,
    required this.total,
  });

  final String id;
  final String name;
  final String thumb; // ruta LOCAL del archivo fuente (miniatura)
  final int total; // bytes totales (0 = indeterminado)
  int sent = 0; // bytes enviados
  String status = 'uploading'; // uploading | done | error | cancelled
  String? error;

  /// Marcado para cancelar: el pool lo salta (en cola) o aborta el envío
  /// (en vuelo) en el siguiente bloque de bytes.
  bool cancelled = false;
}

/// Contrato común del drive (local o servidor).
abstract class DriveBase extends ChangeNotifier {
  // ---------- Estado observable ----------
  List<String> path = [];
  bool loading = false;
  String? error;
  List<DriveItem> _items = const [];
  List<DriveItem> get items => _items;

  /// Para las implementaciones: reemplaza el listado actual.
  @protected
  void updateItems(List<DriveItem> value) => _items = value;

  DriveConn conn = DriveConn.checking;
  DriveBusy busy = DriveBusy.none;
  String busyLabel = '';

  /// Subidas de la sesión (activas, terminadas y con error) — no bloquea la UI.
  final List<DriveUploadJob> uploadJobs = [];

  bool get isReady => conn != DriveConn.checking;
  String get locationLabel =>
      path.isEmpty ? 'Mi Drive' : path.join(' / ');
  String? _search;
  String? get search => _search;

  List<DriveItem> get visibleItems {
    if (_search == null) return _items;
    final q = _search!.toLowerCase();
    return _items.where((i) => i.name.toLowerCase().contains(q)).toList();
  }

  void setSearch(String? value) {
    _search = (value == null || value.trim().isEmpty) ? null : value.trim();
    notifyListeners();
  }

  // ---------- Operaciones ----------
  Future<void> refresh();
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

  /// Sube/copias los archivos. Con [overwrite] reemplaza los existentes
  /// en vez de renombrarlos.
  Future<int> uploadFromPaths(List<String> sources, {bool overwrite = false});
  Future<void> createFolder(String name);
  Future<void> rename(DriveItem item, String newName);
  Future<void> delete(DriveItem item);
  Future<({int moved, List<String> errors})> moveItems(
      List<String> names, List<String> targetPath);
  Future<({int copied, List<String> errors})> copyItems(
      List<String> names, List<String> targetPath);
  Future<({int deleted, List<String> errors})> deleteItems(List<String> names);
  List<String> listFolders(List<String> rel);
  String absolutePathOf(DriveItem item);

  /// Fuente para miniaturas: versión liviana (remota) o ruta local.
  String thumbSource(DriveItem item, {int width = 320}) =>
      absolutePathOf(item);

  /// Fuente para el visor. [previewWidth] pide una versión reducida
  /// (el visor muestra el preview al instante y la original no se baja).
  String fullSource(DriveItem item, {int? previewWidth}) =>
      absolutePathOf(item);

  // ---------- Helpers ----------

  /// Envuelve una operación marcando el estado de carga global.
  @protected
  Future<T> runBusy<T>(DriveBusy kind, String label, Future<T> Function() op) async {
    busy = kind;
    busyLabel = label;
    notifyListeners();
    try {
      return await op();
    } finally {
      busy = DriveBusy.none;
      busyLabel = '';
      notifyListeners();
    }
  }

  // ==================== Trabajos de subida (no bloqueantes) ====================

  void addUploadJob(DriveUploadJob job) {
    uploadJobs.insert(0, job);
    notifyListeners();
  }

  /// Aviso de progreso (llamar al avanzar bytes enviados).
  void notifyUploadProgress() => notifyListeners();

  void finishUploadJob(DriveUploadJob job, {String? error}) {
    job.status = error == null ? 'done' : 'error';
    job.error = error;
    if (error == null) job.sent = job.total;
    if (uploadJobs.length > 30) {
      uploadJobs.removeRange(30, uploadJobs.length);
    }
    notifyListeners();
  }

  void clearFinishedUploads() {
    uploadJobs.removeWhere((j) => j.status != 'uploading');
    notifyListeners();
  }

  // ---------- Cancelación de subidas ----------

  /// Marca un trabajo como cancelado. El pool lo salta si aún no empieza,
  /// o aborta el envío (cortando el stream) si está en vuelo.
  void cancelUpload(String jobId) {
    for (final j in uploadJobs) {
      if (j.id == jobId && j.status == 'uploading') {
        j.cancelled = true;
        notifyListeners();
        return;
      }
    }
  }

  /// Cancela TODAS las subidas activas (en cola o en vuelo).
  void cancelAllUploads() {
    var changed = false;
    for (final j in uploadJobs) {
      if (j.status == 'uploading' && !j.cancelled) {
        j.cancelled = true;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// ¿Nombres ya existen en la carpeta destino? Devuelve los que sí.
  /// (El panel lo usa para preguntar: renombrar / sobrescribir / cancelar.)
  Future<List<String>> filterExisting(List<String> names) async => const [];

  // ---------- Refresco "en vivo" durante subidas ----------

  Timer? _liveRefreshTimer;
  DateTime _lastLiveRefreshAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Refresca el listado DURANTE una subida (máx. 1 vez cada 2 s y siempre
  /// 2 s después de la última llamada): así cada foto aparece en la cuadrícula
  /// apenas se guarda, sin esperar a que termine TODO el lote.
  @protected
  void scheduleLiveRefresh() {
    final now = DateTime.now();
    if (now.difference(_lastLiveRefreshAt) >= const Duration(seconds: 2)) {
      _lastLiveRefreshAt = now;
      refresh();
      return;
    }
    _liveRefreshTimer ??= Timer(const Duration(seconds: 2), () {
      _liveRefreshTimer = null;
      _lastLiveRefreshAt = DateTime.now();
      refresh();
    });
  }

  String extOf(String name) {
    final i = name.lastIndexOf('.');
    return i < 0 ? '' : name.substring(i).toLowerCase();
  }

  bool hasImageExt(String name) => kImageExtensions.contains(extOf(name));
}

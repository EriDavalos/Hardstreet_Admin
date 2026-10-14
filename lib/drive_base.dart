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

/// Normaliza una ruta del Drive: separador siempre `/`, sin barras al
/// principio ni al final y sin `.` ni `..` (los usuarios escriben de todo).
String drivePathNormalize(String path) => path
    .replaceAll('\\', '/')
    .split('/')
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty && s != '.' && s != '..')
    .join('/');

/// ¿Dos carpetas del Drive se SOLAPAN? (son la misma, o una está dentro de la
/// otra).
///
/// Se usa para no compartirle al cliente carpetas redundantes: si ya tiene
/// compartida `ReynaCoot`, compartirle `ReynaCoot/SesionPrevia` no agrega nada
/// (vería el mismo contenido dos veces) y al revés tampoco. El backend aplica
/// esta misma regla; aquí se adelanta para no ofrecer lo que va a fallar.
bool drivePathsOverlap(String a, String b) {
  final x = drivePathNormalize(a);
  final y = drivePathNormalize(b);
  if (x.isEmpty || y.isEmpty) return false;
  if (x == y) return true;
  return x.startsWith('$y/') || y.startsWith('$x/');
}

/// Estados de conexión con el servidor del drive.
enum DriveConn { checking, online, offline }

/// Operación en curso para los overlays de carga.
enum DriveBusy { none, uploading, moving, copying, deleting, downloading }

/// Cuántas subidas corren EN PARALELO (pool de trabajadores).
/// El resto espera su turno en cola, pero TODAS se ven en el panel.
///
/// Se mantiene BAJO (2) a propósito: subir varias fotos grandes a la vez
/// por una conexión doméstica/DDNS satura el enlace y hace que algunas
/// terminen en error. Con 2 en paralelo el lote es mucho más estable.
const int kUploadParallel = 2;

/// Intentos AUTOMÁTICOS por archivo antes de marcarlo con error
/// (1 intento original + reintentos).
const int kUploadAttempts = 3;

/// Espera entre reintentos automáticos (creciente). El último valor se repite.
const List<Duration> kUploadRetryDelays = [
  Duration(milliseconds: 900),
  Duration(milliseconds: 2500),
];

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

  /// Intentos ya realizados (incluye los reintentos automáticos).
  int attempts = 0;

  /// Vuelve a "en carga" para reintentar (automático o manual) manteniendo
  /// el mismo trabajo: el panel no pierde la fila ni su miniatura local.
  void restart() {
    status = 'uploading';
    error = null;
    sent = 0;
    cancelled = false;
  }
}

/// Trabajo de DESCARGA individual (panel de transferencias, estilo Drive).
///
/// La descarga corre en segundo plano: la interfaz sigue libre y el panel
/// muestra el progreso al lado de las subidas. Si falla, el panel ofrece
/// reintentarla sin volver a elegir el destino.
class DriveDownloadJob {
  DriveDownloadJob({
    required this.id,
    required this.name,
    required this.items,
    this.targetPath,
  });

  final String id;

  /// Nombre sugerido: el del archivo (1 sola imagen) o el del ZIP.
  final String name;

  /// Elementos que se descargan (se guardan para poder reintentar).
  final List<DriveItem> items;

  /// Destino elegido en el diálogo Guardar (nativo). En web es null: el
  /// navegador guarda en su carpeta de descargas.
  final String? targetPath;

  int received = 0; // bytes recibidos
  int total = 0; // bytes totales (0 = indeterminado)
  String status = 'downloading'; // downloading | done | error
  String? error;
  bool cancelled = false;

  /// Vuelve a "descargando" para reintentar (botón del panel).
  void restart() {
    status = 'downloading';
    error = null;
    received = 0;
    total = 0;
    cancelled = false;
  }
}

/// Contrato común del drive (local o servidor).
abstract class DriveBase extends ChangeNotifier {
  // ---------- Estado observable ----------
  List<String> path = [];
  bool loading = false;
  String? error;
  List<DriveItem> _items = const [];
  List<DriveItem> get items => _items;

  // ---------- Alcance COMPARTIDO (drive del cliente) ----------
  ///
  /// Cuando el usuario es un CLIENTE, su drive se limita a las carpetas que
  /// el estudio le comparte en sus paquetes comprados:
  ///   * en la RAÍZ solo se ven esas carpetas (nada más);
  ///   * dentro de una de ellas se navega con normalidad.
  ///
  /// [scoped] = false (equipo del estudio) muestra el drive completo.
  bool scoped = false;

  /// Nombres de las carpetas RAÍZ compartidas con este usuario.
  List<String> sharedRoots = const [];

  /// ¿La carpeta actual (o la raíz) está dentro de lo compartido?
  bool get insideSharedRoots =>
      !scoped || (path.isNotEmpty && sharedRoots.contains(path.first));

  /// Listado filtrado por el alcance compartido.
  @protected
  List<DriveItem> applySharedScope(List<DriveItem> value) {
    if (!scoped) return value;
    if (path.isEmpty) {
      final allowed = sharedRoots.toSet();
      return value
          .where((i) => i.isFolder && allowed.contains(i.name))
          .toList(growable: false);
    }
    return insideSharedRoots ? value : const <DriveItem>[];
  }

  /// Para las implementaciones: reemplaza el listado actual.
  @protected
  void updateItems(List<DriveItem> value) {
    _items = applySharedScope(value);
  }

  /// Fija el alcance compartido del cliente y refresca si cambió.
  ///
  /// [roots] son carpetas raíz (se conserva el primer nivel de cada ruta).
  /// Con [isClient] = false el drive vuelve a mostrarse completo.
  Future<void> setSharedRoots(
    List<String> roots, {
    required bool isClient,
  }) async {
    final clean = <String>[];
    for (final r in roots) {
      final first = drivePathNormalize(r).split('/').firstOrNull;
      if (first != null && first.isNotEmpty && !clean.contains(first)) {
        clean.add(first);
      }
    }
    if (scoped == isClient && _sameList(sharedRoots, clean)) return;
    scoped = isClient;
    sharedRoots = clean;
    // Fuera de lo compartido: se regresa a la raíz.
    if (path.isNotEmpty && !sharedRoots.contains(path.first)) {
      path = const [];
      setSearch(null);
    }
    await refresh();
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Carpeta de la que proviene el listado que está en pantalla. La fija cada
  /// refresco EXITOSO ("" = raíz).
  String? loadedPath;

  /// Etiqueta de la carpeta actual, tal como la usa [loadedPath].
  String get pathLabel => path.join('/');

  /// Falló el refresco de la carpeta actual (servidor caído, timeout…).
  ///
  /// Se guarda el error y se descarta el listado SOLO si lo que hay en pantalla
  /// es de OTRA carpeta (no mostrar contenido que no corresponde). Si es la
  /// misma, se conserva lo último bueno: una caída momentánea —típica mientras
  /// se suben fotos y el enlace está saturado— no debe vaciar el directorio que
  /// el usuario está viendo.
  void failRefresh(String message) {
    error = message;
    conn = DriveConn.offline;
    if (loadedPath != pathLabel) {
      updateItems(const []);
      loadedPath = null;
    }
    // Avisa por sí sola: la UI tiene que enterarse del aviso aunque el
    // refresco que falló no llegue a su bloque finally.
    notifyListeners();
  }

  DriveConn conn = DriveConn.checking;
  DriveBusy busy = DriveBusy.none;
  String busyLabel = '';

  /// Subidas de la sesión (activas, terminadas y con error) — no bloquea la UI.
  final List<DriveUploadJob> uploadJobs = [];

  /// Descargas de la sesión (activas, terminadas y con error) — también en
  /// segundo plano: el panel de transferencias las muestra al lado.
  final List<DriveDownloadJob> downloadJobs = [];

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

  /// ¿Se puede abrir esa carpeta con el alcance compartido actual?
  /// En la raíz de un drive compartido solo se abren las carpetas
  /// COMPARTIDAS (nada de la raíz completa).
  bool canOpenFolderNamed(String name) =>
      !scoped || path.isNotEmpty || sharedRoots.contains(name);

  Future<void> openFolder(String name) async {
    if (!canOpenFolderNamed(name)) return;
    path = [...path, name];
    setSearch(null);
    await refresh();
  }

  Future<void> openPath(List<String> segments) async {
    // Fuera de lo compartido no se entra: se queda en la raíz (donde solo
    // se ven las carpetas compartidas).
    if (scoped && segments.isNotEmpty && !sharedRoots.contains(segments.first)) {
      if (path.isEmpty) return;
      segments = const [];
    }
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

  /// Subcarpetas DIRECTAS de [rel] sin mover la carpeta que se está viendo
  /// (lo usa el selector de carpeta del administrador del paquete).
  /// Por defecto devuelve las carpetas del listado ya cargado; las
  /// implementaciones remotas lo consultan al servidor.
  Future<List<String>> listChildFolders(List<String> rel) async =>
      items.where((i) => i.isFolder).map((i) => i.name).toList(growable: false);

  String absolutePathOf(DriveItem item);

  /// Vuelve a subir el archivo de un trabajo que quedó en error (botón
  /// "Resubir" del panel). Mantiene la misma fila del trabajo.
  Future<void> retryUpload(String jobId);

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

  /// Busca un trabajo por id.
  DriveUploadJob? uploadJobById(String jobId) {
    for (final j in uploadJobs) {
      if (j.id == jobId) return j;
    }
    return null;
  }

  /// Espera entre intentos de subida del mismo archivo. [attempt] es el
  /// número de intentos YA fallidos (1 = falló el primero).
  static Duration uploadRetryDelay(int attempt) {
    final i = (attempt - 1).clamp(0, kUploadRetryDelays.length - 1);
    return kUploadRetryDelays[i];
  }

  /// Sube/guarda un archivo con reintentos automáticos y espera creciente.
  ///
  /// [attempt] ejecuta UN intento completo (subir o copiar) y lanza excepción
  /// si falla. Devuelve true si el archivo terminó guardado. Marca el trabajo
  /// como 'done'/'error' y programa el refresco en vivo al terminar.
  @protected
  Future<bool> runUploadWithRetries(
    DriveUploadJob job,
    Future<void> Function() attempt,
  ) async {
    while (true) {
      if (job.cancelled) {
        job.status = 'cancelled';
        job.error = 'Cancelado';
        notifyUploadProgress();
        return false;
      }
      job.attempts++;
      try {
        await attempt();
        finishUploadJob(job);
        // La foto ya está guardada: muéstrala en la cuadrícula sin esperar a
        // que termine el lote completo.
        scheduleLiveRefresh();
        return true;
      } catch (e) {
        if (job.cancelled) {
          job.status = 'cancelled';
          job.error = 'Cancelado';
          notifyUploadProgress();
          return false;
        }
        if (job.attempts >= kUploadAttempts) {
          finishUploadJob(job, error: e.toString());
          return false;
        }
        // Falló pero aún hay margen: la fila sigue "en carga", vuelve a 0 %
        // y muestra el motivo mientras espera para reintentar.
        job.sent = 0;
        job.error = 'Reintentando… ($e)';
        notifyUploadProgress();
        await Future<void>.delayed(uploadRetryDelay(job.attempts));
      }
    }
  }

  void clearFinishedUploads() {
    uploadJobs.removeWhere((j) => j.status != 'uploading');
    notifyListeners();
  }

  // ==================== Trabajos de descarga (segundo plano) ====================

  /// Registra una descarga nueva (aparece YA en el panel, al 0 %).
  DriveDownloadJob startDownload(
    String name, {
    required List<DriveItem> items,
    String? targetPath,
  }) {
    final job = DriveDownloadJob(
      id: 'd${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      items: items,
      targetPath: targetPath,
    );
    downloadJobs.insert(0, job);
    if (downloadJobs.length > 30) {
      downloadJobs.removeRange(30, downloadJobs.length);
    }
    notifyListeners();
    return job;
  }

  /// Aviso de progreso de descarga (bytes recibidos).
  void notifyDownloadProgress() => notifyListeners();

  void finishDownloadJob(DriveDownloadJob job, {String? error}) {
    job.status = error == null ? 'done' : 'error';
    job.error = error;
    if (error == null) job.received = job.total;
    notifyListeners();
  }

  /// Deja un trabajo fallido listo para volver a intentarlo.
  void restartDownloadJob(DriveDownloadJob job) {
    job.restart();
    notifyListeners();
  }

  /// Cancela una descarga en curso (se corta en el siguiente bloque recibido).
  void cancelDownload(String jobId) {
    for (final j in downloadJobs) {
      if (j.id == jobId && j.status == 'downloading') {
        j.cancelled = true;
        notifyListeners();
        return;
      }
    }
  }

  void clearFinishedDownloads() {
    downloadJobs.removeWhere((j) => j.status != 'downloading');
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

  /// Refresca el listado DURANTE una subida (máx. 1 vez cada [_liveRefreshEvery]
  /// y siempre [_liveRefreshEvery] después de la última llamada): así cada foto
  /// aparece en la cuadrícula apenas se guarda, sin esperar a que termine TODO
  /// el lote. El intervalo es corto para que la foto recién subida se vea ya,
  /// pero agrupa las notificaciones para no inundar al servidor.
  static const Duration _liveRefreshEvery = Duration(milliseconds: 600);

  @protected
  void scheduleLiveRefresh() {
    final now = DateTime.now();
    if (now.difference(_lastLiveRefreshAt) >= _liveRefreshEvery) {
      _lastLiveRefreshAt = now;
      refresh();
      return;
    }
    _liveRefreshTimer ??= Timer(_liveRefreshEvery, () {
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

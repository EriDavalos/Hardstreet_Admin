import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_constants.dart';
import 'hs_api.dart' show HsSession;

/// Una carpeta compartida con el cliente, tal como se VE: [shown] es el nombre
/// con el que aparece en su Drive y [real] los segmentos REALES del Drive
/// (`XV/ReynaCoot` → se ve `ReynaCoot`, se abre `XV/ReynaCoot`).
///
/// Existe porque compartir una carpeta ANIDADA montaba antes su carpeta padre:
/// el cliente veía la `XV` del estudio (con todo lo que hubiera dentro) en vez
/// de su carpeta `ReynaCoot`.
typedef SharedRoot = ({String shown, List<String> real});

/// Elemento del Drive: carpeta o imagen.
@immutable
class DriveItem {
  const DriveItem({
    required this.name,
    required this.isFolder,
    this.modified,
    this.size,
    this.childCount = 0,
    this.countKnown = true,
  });

  final String name;
  final bool isFolder;
  final DateTime? modified;
  final int? size;
  final int childCount;

  /// ¿[childCount] es el conteo de VERDAD?
  ///
  /// En la raíz del cliente, una carpeta compartida que vive anidada en el
  /// Drive del estudio (`XV/ReynaCoot`) aparece con su nombre, pero el listado
  /// del estudio solo dice cuántos elementos hay en `XV`: el conteo de la
  /// carpeta compartida NO se puede deducir de ahí. Cuando no se sabe, esto
  /// queda en false y la tarjeta no miente con un "0 elementos".
  final bool countKnown;

  DriveItem copyWith({int? childCount, bool? countKnown}) => DriveItem(
        name: name,
        isFolder: isFolder,
        modified: modified,
        size: size,
        childCount: childCount ?? this.childCount,
        countKnown: countKnown ?? this.countKnown,
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

/// ¿[host] es "de casa"? (localhost o una IP privada). El Drive interno puede
/// estar publicado con DDNS, pero también se pruebe desde la red local.
bool _isLocalDriveHost(String host) {
  final h = host.toLowerCase();
  if (h.isEmpty) return false;
  if (h == 'localhost' || h == '127.0.0.1' || h == '::1') return true;
  if (h.endsWith('.local') || h.endsWith('.lan')) return true;
  final parts = h.split('.');
  if (parts.length != 4) return false;
  final a = int.tryParse(parts[0]);
  final b = int.tryParse(parts[1]);
  if (a == null || b == null) return false;
  if (a == 10) return true;
  if (a == 192 && b == 168) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  return false;
}

/// ¿[url] es una foto del servidor del DRIVE (el interno)?
///
/// El Drive es el ÚNICO servidor que sabe entregar una versión REDIMENSIONADA
/// de una foto (`/thumb/<ruta>?w=N`), así que hay que reconocerlo bien: cuenta
/// su host ([AppConstants.apiBase], o uno de casa) y que la ruta traiga
/// `/files/`. Una URL de CUALQUIER otro sitio no se toca nunca (se usa su
/// enlace real): antes bastaba con que la ruta llevara `/files/` y una foto de
/// fuera terminaba pidiéndose como miniatura al servidor equivocado.
bool isDriveImageUrl(String url) {
  final clean = url.trim();
  if (clean.isEmpty) return false;
  final uri = Uri.tryParse(clean);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
  if (!uri.pathSegments.contains('files')) return false;
  final host = uri.host.toLowerCase();
  final driveHost =
      (Uri.tryParse(AppConstants.apiBase)?.host ?? '').toLowerCase();
  if (driveHost.isNotEmpty && host == driveHost) return true;
  return _isLocalDriveHost(host);
}

/// Token de sesión para las URLs de imagen.
///
/// `Image.network` NO puede mandar cabeceras, así que el servidor del drive
/// acepta el token por query (`?apikey=<jwt>`) — el mismo trato que ya usan
/// las miniaturas de las carpetas compartidas. La única fuente es la sesión
/// del panel ([HsSession.token]), así vale igual en la app y en las pruebas
/// (y no depende de que alguien "instale" el token al arrancar).
String get driveImageToken => HsSession.token ?? '';

/// URL para VER una foto del contenido del sitio:
///
///   * foto del Drive interno → la versión REDIMENSIONADA del servidor
///     (`<servidor>/thumb/<ruta>?w=N`): pesa unos KB en vez de varios MB, así
///     las miniaturas del panel aparecen al instante. Lleva el token de la
///     sesión (`?apikey=`), porque el servidor del drive exige permiso de
///     lectura y una imagen no puede mandar cabeceras: sin él respondía 403 y
///     las fotos del panel no cargaban nunca;
///   * cualquier otro enlace (una foto de otro sitio, una ruta del propio
///     sitio como `images/…`) → se devuelve TAL CUAL.
String driveImagePreview(String url, {int width = 320, String? token}) {
  final clean = url.trim();
  if (!isDriveImageUrl(clean)) return clean;
  final uri = Uri.parse(clean);
  final segments = uri.pathSegments;
  final i = segments.indexOf('files');
  if (i < 0 || i == segments.length - 1) return clean;
  // La ruta se vuelve a codificar: los nombres reales pueden traer espacios,
  // acentos o `#` (y `uri.path` los entrega ya decodificados).
  final path = segments.sublist(i + 1).map(Uri.encodeComponent).join('/');
  final w = width.clamp(32, 2048);
  // El token va DESPUÉS de `w` a propósito: así la clave de caché de la
  // imagen (`width`) sigue siendo visible en la URL.
  final t = (token ?? driveImageToken).trim();
  final extra = t.isEmpty ? '' : '&apikey=${Uri.encodeQueryComponent(t)}';
  return '${uri.scheme}://${uri.authority}/thumb/$path?w=$w$extra';
}

/// El mismo criterio para la URL ORIGINAL de una foto del drive
/// (`<servidor>/files/<ruta>`), con el token al final cuando hay sesión.
String drivePhotoUrl(String url, {String? token}) {
  final clean = url.trim();
  if (!isDriveImageUrl(clean)) return clean;
  final t = (token ?? driveImageToken).trim();
  if (t.isEmpty) return clean;
  final sep = clean.contains('?') ? '&' : '?';
  return '$clean$sep'
      'apikey=${Uri.encodeQueryComponent(t)}';
}

/// Ruta RELATIVA dentro del Drive de una URL de foto, o null si la URL no es
/// una foto del Drive.
///
///   `https://servidor/files/Boda/Ana/Fiesta/01.jpg` → `Boda/Ana/Fiesta/01.jpg`
///
/// Sirve para decirle al servidor QUÉ fotos tiene que dejar ver a la web sin
/// sesión (la portada del sitio, la imagen de un paquete): se guarda la ruta,
/// no la URL, porque el token de la sesión nunca debe acabar en la web.
String? driveRelPath(String url) {
  final clean = url.trim();
  if (!isDriveImageUrl(clean)) return null;
  final uri = Uri.tryParse(clean);
  if (uri == null) return null;
  final segments = uri.pathSegments;
  final i = segments.indexOf('files');
  if (i < 0 || i >= segments.length - 1) return null;
  final rel = segments.sublist(i + 1).where((s) => s.isNotEmpty).join('/');
  return rel.isEmpty ? null : rel;
}

/// URL PÚBLICA de una foto del Drive: `<servidor>/files/<ruta>`, SIN el token
/// de sesión.
///
/// La usan los módulos que GUARDAN una foto del Drive para que la vea la web
/// (la portada del sitio, la imagen de un paquete): la página tiene que poder
/// abrirla sin iniciar sesión de nadie, así que el token no puede ir dentro.
String drivePublicUrl(String absolutePath) {
  final base = AppConstants.apiBase.replaceAll(RegExp(r'/$'), '');
  final path = absolutePath
      .split('/')
      .where((s) => s.trim().isNotEmpty)
      .map(Uri.encodeComponent)
      .join('/');
  return '$base/files/$path';
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
    this.batch = '',
  });

  final String id;
  final String name;
  final String thumb; // ruta LOCAL del archivo fuente (miniatura)
  final int total; // bytes totales (0 = indeterminado)

  /// Lote al que pertenece: todas las fotos de UNA subida comparten el mismo
  /// valor. El panel mide el progreso del LOTE ("50/100 fotos"), así que las
  /// fotos de una subida anterior no se mezclan con las de la actual.
  final String batch;
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
    this.from,
  });

  final String id;

  /// Nombre sugerido: el del archivo (1 sola imagen) o el del ZIP.
  final String name;

  /// Elementos que se descargan (se guardan para poder reintentar).
  final List<DriveItem> items;

  /// Carpeta del Drive DE LA QUE salen [items] (null = la carpeta que el drive
  /// está mostrando).
  ///
  /// Existe porque hay pantallas que navegan POR SU CUENTA sin mover el drive
  /// (el selector de fotos): si no se guardara aquí, la descarga saldría de la
  /// carpeta que el módulo Archivos tuviera abierta y bajaría OTRO archivo (o
  /// ninguno).
  final List<String>? from;

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
  /// ¿Este drive se sirve por RED (HTTP)?
  ///
  /// Importa para pintar una miniatura: un drive local (una carpeta real del
  /// equipo) se lee con `Image.file`, y uno remoto con `Image.network`. Antes
  /// se preguntaba `drive is DriveApiService`, así que un drive remoto que no
  /// hereda de esa clase (p. ej. una carpeta compartida) se pintaba como si
  /// fuera del disco: la foto NUNCA cargaba y se quedaba el marcador girando.
  bool get isRemote => true;

  // ---------- Estado observable ----------
  List<String> path = [];
  bool loading = false;
  String? error;
  List<DriveItem> _items = const [];
  List<DriveItem> get items => _items;

  // ---------- Alcance COMPARTIDO (drive del cliente) ----------
  ///
  /// Cuando el usuario es un CLIENTE, su drive se limita a las carpetas que
  /// el estudio le comparte:
  ///   * en la RAÍZ se ve UNA carpeta por cada compartido, con SU nombre;
  ///   * dentro de una compartida se navega con normalidad;
  ///   * lo demás del estudio NO existe para él: ni las carpetas hermanas.
  ///
  /// La carpeta compartida se ve por SU NOMBRE aunque viva anidada en el Drive:
  /// si se le comparte `XV/ReynaCoot`, el cliente ve la carpeta `ReynaCoot` (y
  /// dentro el contenido de `XV/ReynaCoot`) — NO la carpeta `XV` con todo lo
  /// que el estudio tenga ahí dentro. `XV` es solo el camino hacia ella y no se
  /// muestra ni se puede tocar.
  ///
  /// [scoped] = false (equipo del estudio) muestra el drive completo.
  bool scoped = false;

  /// Nombres con los que se VE cada carpeta compartida en la raíz del cliente
  /// (`XV/ReynaCoot` → `ReynaCoot`).
  List<String> sharedRoots = const [];

  /// Carpetas compartidas tal como se VEN: [shown] es el nombre visible y
  /// [real] los segmentos REALES del Drive.
  List<SharedRoot> sharedRootEntries = const [];

  /// ¿[segments] es una carpeta compartida o está DENTRO de una?
  bool isInsideShared(List<String> segments) {
    if (!scoped) return true;
    for (final e in sharedRootEntries) {
      if (_isPrefix(e.real, segments)) return true;
    }
    return false;
  }

  /// ¿[segments] lleva a alguna carpeta compartida? (es el camino hacia una:
  /// p. ej. la `XV` que contiene a `XV/ReynaCoot`). Solo se usa para no perder
  /// el hilo si el cliente ya venía navegando por ahí.
  bool _leadsToShared(List<String> segments) {
    if (!scoped) return true;
    for (final e in sharedRootEntries) {
      if (_isPrefix(segments, e.real)) return true;
    }
    return false;
  }

  /// ¿La carpeta actual (o la raíz) está dentro de lo compartido?
  bool get insideSharedRoots => !scoped || isInsideShared(path);

  /// Cuántos niveles del inicio de [path] son SOLO el camino hacia la carpeta
  /// compartida (no se muestran: el cliente no tiene por qué saber de qué
  /// carpeta del estudio salió la suya).
  int get hiddenPathPrefix {
    if (!scoped || path.isEmpty) return 0;
    for (final e in sharedRootEntries) {
      // Vale para la carpeta compartida MISMA y para lo que hay dentro: el
      // camino del estudio hacia ella (`XV`) no se muestra nunca. Antes, al
      // estar JUSTO en ella, no se ocultaba nada y el cliente leía
      // "Mi Drive > XV > ReynaCoot" en vez de "Mi Drive > ReynaCoot".
      if (_isPrefix(e.real, path)) return e.real.length - 1;
    }
    return 0;
  }

  /// Listado filtrado por el alcance compartido.
  @protected
  List<DriveItem> applySharedScope(List<DriveItem> value) {
    if (!scoped) return value;
    if (path.isEmpty) {
      // La raíz del cliente: una entrada por carpeta compartida, con SU
      // nombre, aunque la carpeta viva anidada en el Drive del estudio.
      final byName = {for (final i in value) i.name: i};
      return [
        for (final e in sharedRootEntries)
          DriveItem(
            name: e.shown,
            isFolder: true,
            modified: byName[e.real.first]?.modified,
            // El conteo del ancestro no dice nada de la carpeta compartida:
            // solo se hereda cuando la compartida ES ese primer nivel.
            childCount: e.real.length == 1
                ? (byName[e.real.first]?.childCount ?? 0)
                : (_sharedCounts[_pathKey(e.real)] ?? 0),
            // Solo se sabe con certeza si el listado del estudio la trae
            // (compartida del primer nivel) o si se preguntó su contenido.
            countKnown: e.real.length == 1 ||
                _sharedCounts.containsKey(_pathKey(e.real)),
          ),
      ];
    }
    if (isInsideShared(path)) return value;
    if (!_leadsToShared(path)) return const <DriveItem>[];
    // De camino a la carpeta compartida (p. ej. la `XV` que la contiene): solo
    // se ofrece el SIGUIENTE paso hacia ella. Lo demás de esa carpeta del
    // estudio no se ve.
    final next = <String>{};
    for (final e in sharedRootEntries) {
      if (_isPrefix(path, e.real) && e.real.length > path.length) {
        next.add(e.real[path.length]);
      }
    }
    return value
        .where((i) => i.isFolder && next.contains(i.name))
        .toList(growable: false);
  }

  /// Para las implementaciones: reemplaza el listado actual.
  @protected
  void updateItems(List<DriveItem> value) {
    _items = applySharedScope(value);
  }

  /// Fija el alcance compartido del cliente y refresca si cambió.
  ///
  /// [roots] son las carpetas compartidas con SU ruta del Drive (`XV/ReynaCoot`
  /// o `Bodas/Ana Ruiz`): cada una se muestra como una carpeta propia, con el
  /// nombre de la última parte de su ruta. Con [isClient] = false el drive
  /// vuelve a mostrarse completo.
  Future<void> setSharedRoots(
    List<String> roots, {
    required bool isClient,
  }) async {
    final entries = <SharedRoot>[];
    final used = <String>{};
    for (final r in roots) {
      final real = _segments(r);
      if (real.isEmpty) continue;
      if (entries.any((e) => _samePath(e.real, real))) continue;
      // El nombre visible es el de la carpeta compartida. Si dos compartidas
      // se llaman igual, se distingue con su carpeta padre («Coot (XV)»)
      // para que el cliente no confunda una con otra.
      var shown = real.last;
      if (used.contains(shown) && real.length > 1) {
        shown = '${real.last} (${real[real.length - 2]})';
      }
      var n = 2;
      while (used.contains(shown)) {
        shown = '${real.last} ($n)';
        n++;
      }
      used.add(shown);
      entries.add((shown: shown, real: real));
    }
    if (scoped == isClient && _sameEntries(sharedRootEntries, entries)) return;
    scoped = isClient;
    sharedRootEntries = List.unmodifiable(entries);
    sharedRoots = [for (final e in entries) e.shown];
    // Cuántos elementos hay dentro de cada compartida (para que la tarjeta del
    // cliente no diga "0 elementos" teniendo 2 dentro).
    try {
      _sharedCounts = await sharedRootCounts(sharedRootEntries);
    } catch (_) {
      _sharedCounts = const {};
    }
    // Fuera de lo compartido (ni dentro, ni de camino): se regresa a la raíz.
    if (path.isNotEmpty && !isInsideShared(path) && !_leadsToShared(path)) {
      path = const [];
      _setScreenPath(const []);
      setSearch(null);
    }
    await refresh();
  }

  /// Conteo REAL de lo que hay dentro de cada carpeta compartida.
  ///
  /// En la raíz del cliente el listado solo trae las carpetas de primer nivel
  /// del estudio, así que el contenido de una compartida ANIDADA
  /// (`XV/ReynaCoot`) hay que preguntarlo aparte. Quien pueda hacerlo (el
  /// servidor, o el disco en la versión local) lo implementa aquí; el resto
  /// deja el conteo como desconocido y la tarjeta no inventa un número.
  Future<Map<String, int>> sharedRootCounts(List<SharedRoot> entries) async =>
      const {};

  /// Conteo ya consultado de cada carpeta compartida (por su ruta real).
  Map<String, int> _sharedCounts = const {};

  static String _pathKey(List<String> segments) => segments.join('/');

  /// Segmentos de una ruta del Drive ('XV/ReynaCoot' → ['XV','ReynaCoot']).
  static List<String> _segments(String path) => drivePathNormalize(path)
      .split('/')
      .where((s) => s.isNotEmpty)
      .toList(growable: false);

  static bool _isPrefix(List<String> prefix, List<String> full) {
    if (prefix.length > full.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (prefix[i] != full[i]) return false;
    }
    return true;
  }

  static bool _samePath(List<String> a, List<String> b) =>
      _isPrefix(a, b) && a.length == b.length;

  static bool _sameEntries(List<SharedRoot> a, List<SharedRoot> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].shown != b[i].shown || !_samePath(a[i].real, b[i].real)) {
        return false;
      }
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

  // ---------- Refrescos: respuestas VIEJAS ----------
  //
  // Navegar es inmediato y la red no: si el usuario entra a una carpeta y
  // vuelve a la anterior antes de que llegue la respuesta de la primera, esa
  // respuesta YA NO SIRVE (pintaría las fotos de la carpeta que dejó, como si
  // siguieran cargando las de antes). Cada refresco lleva un TICKET —número de
  // petición + carpeta— y su resultado solo se aplica si sigue vigente.

  int _refreshSeq = 0;

  /// Últimos listados BUENOS por carpeta: al volver a una carpeta anterior se
  /// ve al instante lo que había (y el refresco lo pone al día por detrás) en
  /// vez de quedarse en blanco esperando a la red.
  final Map<String, List<DriveItem>> _listingCache = {};

  /// Cuántas carpetas se recuerdan (las más recientes).
  static const int _listingCacheMax = 8;

  /// Marca el inicio de un refresco: descarta el listado de OTRA carpeta y
  /// devuelve el ticket de esta petición. Lo llaman las implementaciones.
  @protected
  ({int seq, String path}) beginRefresh() {
    clearStaleItems();
    _refreshSeq++;
    return (seq: _refreshSeq, path: pathLabel);
  }

  /// ¿El ticket sigue vigente? (no se lanzó otro refresco después y no se
  /// cambió de carpeta). Si no, la respuesta se DESCARTA.
  @protected
  bool isCurrentRefresh(({int seq, String path}) ticket) =>
      ticket.seq == _refreshSeq && ticket.path == pathLabel;

  /// ¿Es el ÚLTIMO refresco pedido? El cargador lo apaga solo el último en
  /// terminar: así nunca se queda un girador eterno porque su petición fue
  /// reemplazada por otra.
  @protected
  bool isLatestRefresh(({int seq, String path}) ticket) =>
      ticket.seq == _refreshSeq;

  /// Aplica un refresco EXITOSO y recuerda el listado de esa carpeta.
  /// Con un ticket viejo no toca nada. Devuelve true si entró a pantalla.
  @protected
  bool applyRefresh(({int seq, String path}) ticket, List<DriveItem> listing) {
    if (!isCurrentRefresh(ticket)) return false;
    _rawListing = listing;
    updateItems(listing);
    loadedPath = pathLabel;
    _setScreenPath(path);
    _rememberListing(pathLabel, items);
    // El contenido de las compartidas vive en el servidor: se vuelve a
    // preguntar por detrás, porque el número de la tarjeta envejece en cuanto
    // el cliente sube o borra algo dentro de SU carpeta.
    if (scoped && path.isEmpty) unawaited(_refreshSharedCounts());
    return true;
  }

  /// Último listado CRUDO (sin el alcance compartido aplicado): al recontar hay
  /// que rehacer el filtro desde el original, no desde lo que ya se muestra.
  List<DriveItem> _rawListing = const [];

  bool _countingSharedRoots = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Vuelve a preguntar cuántos elementos hay DENTRO de cada compartida y
  /// repinta la raíz del cliente si el número cambió. Sin bloqueos ni ruido: si
  /// falla (o el drive ya se cerró) se conserva el conteo anterior.
  Future<void> _refreshSharedCounts() async {
    if (_countingSharedRoots || sharedRootEntries.isEmpty) return;
    final entries = sharedRootEntries;
    _countingSharedRoots = true;
    try {
      final counts = await sharedRootCounts(entries);
      if (_disposed || !scoped || path.isNotEmpty) return;
      if (_sameCounts(counts, _sharedCounts)) return;
      _sharedCounts = counts;
      updateItems(_rawListing);
      _rememberListing(pathLabel, items);
      notifyListeners();
    } catch (_) {
      // Sin dato nuevo: se queda el conteo que ya había.
    } finally {
      _countingSharedRoots = false;
    }
  }

  static bool _sameCounts(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  void _rememberListing(String path, List<DriveItem> listing) {
    _listingCache[path] = List<DriveItem>.of(listing);
    while (_listingCache.length > _listingCacheMax) {
      _listingCache.remove(_listingCache.keys.first);
    }
  }

  /// Al CAMBIAR de carpeta: fuera las fotos de la anterior —se veían mientras
  /// cargaba la nueva, como si siguieran cargando— y dentro, si ya se conoce,
  /// el listado de la carpeta nueva.
  @protected
  void clearStaleItems() {
    if (loadedPath == pathLabel) return;
    if (loadedPath != null) _rememberListing(loadedPath!, items);
    final cached = _listingCache[pathLabel];
    if (cached != null) {
      updateItems(cached);
      loadedPath = pathLabel;
      _setScreenPath(path);
      return;
    }
    updateItems(const []);
    loadedPath = null;
  }

  DriveConn conn = DriveConn.checking;
  DriveBusy busy = DriveBusy.none;
  String busyLabel = '';

  /// Subidas de la sesión (activas, terminadas y con error) — no bloquea la UI.
  final List<DriveUploadJob> uploadJobs = [];

  int _uploadBatchSeq = 0;

  /// Descargas de la sesión (activas, terminadas y con error) — también en
  /// segundo plano: el panel de transferencias las muestra al lado.
  final List<DriveDownloadJob> downloadJobs = [];

  bool get isReady => conn != DriveConn.checking;

  /// Ruta para MOSTRAR (encabezado, aviso de "suelta para subir", nombre del
  /// ZIP). En el drive del cliente no incluye el camino del estudio hacia su
  /// carpeta compartida: `XV / ReynaCoot` se muestra como `ReynaCoot`.
  String get locationLabel {
    if (path.isEmpty) return 'Mi Drive';
    final shown = path.sublist(hiddenPathPrefix.clamp(0, path.length));
    return shown.isEmpty ? 'Mi Drive' : shown.join(' / ');
  }
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
  /// COMPARTIDAS (nada de la raíz completa). Se mira el listado EN PANTALLA
  /// (`_screenPath`), que es sobre el que el usuario hace clic.
  bool canOpenFolderNamed(String name) =>
      !scoped || _screenPath.isNotEmpty || _entryShown(name) != null;

  /// La carpeta compartida que se VE con el nombre [shown] (null si ninguna).
  SharedRoot? _entryShown(String shown) {
    for (final e in sharedRootEntries) {
      if (e.shown == shown) return e;
    }
    return null;
  }

  /// Segmentos de la carpeta cuyo LISTADO está delante del usuario (el último
  /// que se pintó).
  ///
  /// De aquí parte un toque, no de [path]: si el usuario toca el listado que
  /// sigue a la vista mientras la carpeta nueva carga, el destino es el
  /// correcto. Antes se partía de [path] y el segundo toque sobre la MISMA
  /// carpeta la metía dentro de sí misma ("Mi Drive / X / X"). Se conserva
  /// aunque el listado de la carpeta nueva todavía no haya llegado (ahí no hay
  /// nada que tocar, y el doble clic se resuelve con el listado anterior).
  List<String> get _screenPath => _screenSegments;
  List<String> _screenSegments = const [];

  void _setScreenPath(List<String> segments) {
    _screenSegments = List<String>.unmodifiable(segments);
  }

  Future<void> openFolder(String name) async {
    if (!canOpenFolderNamed(name)) return;
    // A dónde lleva este toque, según lo que hay en pantalla:
    //   * raíz del cliente → la ruta REAL de esa compartida (`ReynaCoot` →
    //     `XV/ReynaCoot`), porque la compartida puede vivir anidada;
    //   * en cualquier otra carpeta → un nivel más dentro de lo que se ve.
    final screen = _screenPath;
    final target = (scoped && screen.isEmpty)
        ? (_entryShown(name)?.real ?? [name])
        : [...screen, name];
    // ¿Ya se está abriendo EXACTAMENTE esta carpeta? (el listado en pantalla
    // todavía es el de la anterior). No se pide dos veces: era lo que hacía
    // "Mi Drive / X / X" al tocar dos veces la misma carpeta.
    if (loading && loadedPath != pathLabel && _samePath(target, path)) return;
    path = List<String>.of(target);
    setSearch(null);
    await refresh();
  }

  Future<void> openPath(List<String> segments) async {
    // Fuera de lo compartido no se entra: se queda en su raíz (donde solo se
    // ven las carpetas compartidas).
    var target = List<String>.of(segments);
    if (scoped && !isInsideShared(target)) {
      if (path.isEmpty) return;
      target = <String>[];
    }
    path = target;
    setSearch(null);
    await refresh();
  }

  Future<void> goUp() async {
    if (path.isEmpty) return;
    if (scoped) {
      for (final e in sharedRootEntries) {
        if (_samePath(e.real, path)) {
          // Desde la carpeta compartida se vuelve a SU raíz (el listado de lo
          // que le comparten), no a la carpeta del estudio que la contiene.
          path = const [];
          setSearch(null);
          await refresh();
          return;
        }
      }
    }
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

  /// CONTENIDO directo de [rel] —carpetas Y archivos— sin mover la carpeta que
  /// se está viendo. Lo usa el selector de fotos/elementos del cliente ("elegir
  /// qué quiero de mi Drive para este servicio"). Por defecto devuelve lo ya
  /// cargado; las implementaciones remotas lo consultan al servidor.
  Future<List<DriveItem>> listFolderItems(List<String> rel) async =>
      List<DriveItem>.of(items);

  /// ESPACIO usado por la carpeta donde se guardan las fotos, su CUOTA
  /// configurada y lo que queda libre en el disco (lo que devuelve
  /// /api/space del servidor del drive). Por defecto no hay información: el
  /// módulo Almacenamiento lo dice en vez de inventar números.
  Future<Map<String, dynamic>?> storageInfo() async => null;

  String absolutePathOf(DriveItem item);

  /// Ruta ABSOLUTA de [item] cuando vive en la carpeta [rel], sin mover la
  /// carpeta que el drive está mostrando. La usan las pantallas que navegan por
  /// su cuenta (el selector de fotos) para leer o descargar un archivo de SU
  /// carpeta y no del archivo homónimo de otra.
  String absolutePathIn(List<String> rel, DriveItem item) => absolutePathOf(item);

  /// Vuelve a subir el archivo de un trabajo que quedó en error (botón
  /// "Resubir" del panel). Mantiene la misma fila del trabajo.
  Future<void> retryUpload(String jobId);

  /// Fuente para miniaturas: versión liviana (remota) o ruta local.
  String thumbSource(DriveItem item, {int width = 320}) =>
      absolutePathOf(item);

  /// Miniatura de [item] dentro de una carpeta CONCRETA [rel] (en segmentos),
  /// sin depender de la carpeta que el drive está mostrando ahora mismo.
  ///
  /// Existe porque hay pantallas que navegan POR SU CUENTA sin mover el drive
  /// (el selector de fotos del módulo Sitio web): pedían la miniatura del
  /// archivo homónimo en la carpeta que tuviera abierta el módulo Archivos, así
  /// que dentro de una subcarpeta no salía ninguna foto. Con el drive LOCAL
  /// había un segundo problema: `thumbSource` devuelve una ruta del disco y esa
  /// ruta se le pasaba a `Image.network` (tampoco se veía nada): por eso aquí
  /// se usa [DriveThumb], que resuelve las dos cosas.
  String thumbSourceIn(List<String> rel, DriveItem item, {int width = 320}) {
    final saved = path;
    path = List<String>.of(rel);
    try {
      return thumbSource(item, width: width);
    } finally {
      path = saved;
    }
  }

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

  /// Lote nuevo de subida: TODAS las fotos que se registren hasta el siguiente
  /// lote lo comparten (el panel cuenta "subidas / a subir" de ESE lote).
  String newUploadBatch() =>
      'b${++_uploadBatchSeq}-${DateTime.now().microsecondsSinceEpoch}';

  /// Lote más reciente con trabajos (null si no hay subidas).
  String? get currentUploadBatch =>
      uploadJobs.isEmpty ? null : uploadJobs.first.batch;

  /// Las fotos del lote más reciente: lo que el panel muestra y cuenta.
  ///
  /// Es la lista COMPLETA del lote, incluidas las que todavía esperan su turno
  /// en la cola: con 100 fotos el panel tiene que ver 100, no 30.
  List<DriveUploadJob> get currentUploadJobs {
    final batch = currentUploadBatch;
    if (batch == null || batch.isEmpty) return uploadJobs;
    return [
      for (final j in uploadJobs)
        if (j.batch == batch) j,
    ];
  }

  /// Cuántos trabajos TERMINADOS de lotes ANTERIORES se recuerdan (el lote en
  /// curso se conserva completo).
  static const int kMaxFinishedUploadJobs = 30;

  /// Suelta historial: los trabajos ya terminados de lotes anteriores.
  ///
  /// Los que están EN COLA o EN VUELO no se sueltan NUNCA (el panel muestra el
  /// lote completo y su progreso). Antes se recortaba la lista a los 30 más
  /// recientes y, al subir 100 fotos, las que esperaban turno desaparecían del
  /// panel — con ellas, el total del lote y su porcentaje.
  void _trimUploadJobs() {
    final current = currentUploadBatch;
    final stale = <int>[];
    for (var i = 0; i < uploadJobs.length; i++) {
      final j = uploadJobs[i];
      if (j.status != 'uploading' && j.batch != current) stale.add(i);
    }
    var excess = stale.length - kMaxFinishedUploadJobs;
    if (excess <= 0) return;
    // Los MÁS VIEJOS primero: los índices mayores son los últimos de la lista.
    for (final i in stale.reversed) {
      if (excess <= 0) break;
      excess--;
      uploadJobs.removeAt(i);
    }
  }

  /// Aviso de progreso (llamar al avanzar bytes enviados).
  void notifyUploadProgress() => notifyListeners();

  void finishUploadJob(DriveUploadJob job, {String? error}) {
    job.status = error == null ? 'done' : 'error';
    job.error = error;
    if (error == null) job.sent = job.total;
    _trimUploadJobs();
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
    List<String>? from,
  }) {
    final job = DriveDownloadJob(
      id: 'd${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      items: items,
      targetPath: targetPath,
      from: from == null ? null : List<String>.of(from),
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

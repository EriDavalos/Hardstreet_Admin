import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:http/http.dart' as http;

import 'app_constants.dart';
import 'app_platform.dart';
import 'download_stub.dart' if (dart.library.html) 'download_web.dart';
import 'drive_base.dart';
import 'drive_downloader.dart' show needsSaveDialog, saveToAndroidDownloads;
import 'hs_api.dart';
import 'share_permissions.dart';

// ==================================================================
// HARD STREET ADMIN - Carpetas compartidas (SOLO LECTURA)
// ==================================================================
// Un usuario del módulo "Archivos compartidos" comparte una carpeta: de SU
// COMPUTADORA (ruta absoluta, p. ej. C:\Fotos o /home/ana/fotos) o de SU DRIVE
// del servidor (ruta relativa, p. ej. Bodas/Ana Ruiz). En los dos casos se
// sirve aparte, en solo lectura, con los endpoints /api/local/* del MISMO
// servidor del Drive (`AppConstants.apiBase`): la autorización sale del
// compartido (dueño o destinatario), así el módulo navega cualquier carpeta
// compartida sin tener que saltar al módulo Archivos.
//
// Aquí solo hay LECTURA: listar, ver miniaturas/imágenes y descargar. Nunca se
// escribe en la carpeta de otra persona (el servidor tampoco ofrece escritura).
// ==================================================================

/// Un elemento (carpeta o imagen) de una carpeta local compartida.
class LocalShareItem {
  const LocalShareItem({
    required this.name,
    required this.isFolder,
    this.size,
    this.modified,
    this.childCount = 0,
    this.countKnown = true,
  });

  final String name;
  final bool isFolder;
  final int? size;

  /// Fecha de la última modificación (la manda el servidor del drive).
  final DateTime? modified;

  /// Cuántos elementos tiene DENTRO (solo carpetas).
  final int childCount;

  /// ¿[childCount] es el conteo de verdad? Un servidor viejo no lo manda.
  final bool countKnown;
}

/// Contenido de una carpeta local compartida.
class LocalShareListing {
  const LocalShareListing({required this.items});

  final List<LocalShareItem> items;

  List<LocalShareItem> get folders =>
      items.where((i) => i.isFolder).toList(growable: false);
  List<LocalShareItem> get files =>
      items.where((i) => !i.isFolder).toList(growable: false);
}

/// Estado de un compartido AHORA MISMO (lo que responde `/api/local/status`).
///
/// Es lo que permite MOSTRAR que la carpeta está funcionando (o por qué no)
/// antes de intentar abrirla: de dónde se sirve, si su dueño tiene la app
/// abierta y si el servidor del drive tiene base de datos.
class LocalShareStatus {
  const LocalShareStatus({
    required this.servedFrom,
    this.onServer = false,
    this.ownerOnline = false,
    this.localFolder = false,
    this.hasDatabase = true,
    this.reason,
    this.detail,
    this.permissions = SharePermissions.readOnly,
    this.permissionsKnown = false,
  });

  /// server (está en el servidor) | agent (computadora del dueño, app abierta)
  /// | offline (computadora del dueño, app cerrada) | unknown (no se pudo leer).
  final String servedFrom;

  /// La carpeta vive TAMBIÉN en el servidor del drive (siempre disponible).
  final bool onServer;

  /// La app del dueño está abierta ahora mismo (contesta el long polling).
  final bool ownerOnline;

  /// El compartido es una carpeta de la COMPUTADORA de quien lo comparte.
  final bool localFolder;

  /// El servidor del drive tiene base de datos configurada.
  final bool hasDatabase;

  /// Código del motivo cuando no se puede servir (`no-db`, `share-missing`…).
  final String? reason;

  /// Explicación del servidor (para mostrarla tal cual).
  final String? detail;

  /// Lo que YO puedo hacer en la carpeta (lo decide quien la comparte).
  final SharePermissions permissions;

  /// ¿El servidor MANDÓ esos permisos? (un servidor viejo no los manda, y en
  /// ese caso no se pueden usar para decidir qué ofrecer en la vista).
  final bool permissionsKnown;

  /// ¿Se puede servir? (no hay estado peor que "offline" / "unknown").
  bool get available => servedFrom == 'server' || servedFrom == 'agent';

  /// El servidor CONTESTÓ que no puede servir la carpeta: se guarda su
  /// explicación y se traduce a un motivo conocido.
  ///
  /// Sirve igual para un servidor VIEJO, que contesta 404 con el mensaje
  /// "La carpeta compartida no existe o ya no está activa": antes eso se veía
  /// como que la carpeta era el problema, cuando lo que pasó es que el
  /// compartido se dio de baja.
  factory LocalShareStatus.unavailable(String why) {
    final msg = why.trim();
    // Motivos del SERVICIO (el compartido) y motivos de la BASE de datos: son
    // problemas distintos y el panel los nombra distinto (culpar a la carpeta
    // por una base que no responde es justo el error que se está corrigiendo).
    final gone = RegExp(
      r'no existe|ya no está|no está compartida|ya no está activa|'
      r'dado de baja|no encuentra el compartido',
      caseSensitive: false,
    ).hasMatch(msg);
    final dbDown = RegExp(
      r'no pudo consultar los compartidos',
      caseSensitive: false,
    ).hasMatch(msg);
    final noDb = RegExp(
      r'base de datos|DRIVE_DB',
      caseSensitive: false,
    ).hasMatch(msg);
    // El problema es de la base SOLO si el mensaje no habla del compartido.
    final dbProblem = !gone && (dbDown || noDb);
    return LocalShareStatus(
      servedFrom: 'unavailable',
      hasDatabase: !dbProblem,
      reason: gone
          ? 'share-missing'
          : dbDown
          ? 'share-db'
          : noDb
          ? 'no-db'
          : null,
      detail: msg.isEmpty ? null : msg,
    );
  }

  static LocalShareStatus fromJson(Map<String, dynamic> m) => LocalShareStatus(
    servedFrom: '${m['servedFrom'] ?? 'unknown'}',
    onServer: m['onServer'] == true,
    ownerOnline: m['online'] == true,
    localFolder: m['local'] == true,
    hasDatabase: m['db'] != false,
    reason: m['reason'] == null ? null : '${m['reason']}',
    detail: m['detail'] == null ? null : '${m['detail']}',
    permissions: SharePermissions.fromJson(m['permissions']),
    permissionsKnown: m['permissions'] is Map,
  );

  /// Sin poder preguntar (red, servidor viejo): se intenta servir igual.
  static const LocalShareStatus unknown = LocalShareStatus(
    servedFrom: 'unknown',
  );
}

class LocalShareService {
  LocalShareService({String? baseUrl, http.Client? client})
    : base = baseUrl ?? AppConstants.apiBase,
      _client = client ?? http.Client();

  final String base;

  /// Cliente HTTP (inyectable en pruebas).
  final http.Client _client;

  /// Token de sesión (el mismo del login). El servidor del drive lo valida.
  static String get _token => HsSession.token ?? '';

  static Map<String, String> get _headers => {
    if (_token.isNotEmpty) 'Apikey': _token,
  };

  Uri _u(String p, Map<String, String> q) =>
      Uri.parse('$base$p').replace(queryParameters: q);

  /// Mensaje de error del servidor del drive (o el genérico si no lo manda):
  /// explica si la carpeta no existe, si no hay acceso, etc.
  static String _why(http.Response r, String fallback) {
    try {
      final data = jsonDecode(r.body);
      if (data is Map && data['error'] is String) {
        final msg = '${data['error']}'.trim();
        if (msg.isNotEmpty) return msg;
      }
    } catch (_) {
      // Respuesta sin JSON: se usa el mensaje genérico.
    }
    return fallback;
  }

  /// ¿De dónde se puede servir AHORA el compartido [shareId]?
  ///
  /// Responde un [LocalShareStatus]: `server` (está en el servidor), `agent`
  /// (está en la computadora del dueño y su app está abierta), `offline` (su
  /// app no está abierta) o `unknown` (no se pudo preguntar: red, servidor
  /// viejo; en ese caso se intenta servir igual, como antes).
  Future<LocalShareStatus> status(int shareId) async {
    try {
      final r = await _client
          .get(
            _u('/api/local/status', {'share': '$shareId'}),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        if (data is! Map) return LocalShareStatus.unknown;
        return LocalShareStatus.fromJson(data.cast<String, dynamic>());
      }
      // Contestó que NO puede servirla: se muestra el motivo que manda (y si
      // venía sin JSON, uno genérico con el código HTTP).
      return LocalShareStatus.unavailable(
        _why(r, 'El servidor del drive respondió HTTP ${r.statusCode}'),
      );
    } catch (_) {
      return LocalShareStatus.unknown;
    }
  }

  /// El nombre de dónde se sirve (compatibilidad: `server`/`agent`/`offline`).
  Future<String> source(int shareId) async =>
      (await status(shareId)).servedFrom;

  /// Contenido de [path] (subcarpetas de la carpeta compartida [shareId]).
  Future<LocalShareListing> list(int shareId, List<String> path) async {
    final r = await _client
        .get(
          _u('/api/local/list', {'share': '$shareId', 'path': path.join('/')}),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) {
      throw _why(r, 'No se pudo abrir la carpeta (HTTP ${r.statusCode})');
    }
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    final raw = (data['folders'] as List?) ?? const [];
    final items = <LocalShareItem>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final count = (e['childCount'] as num?)?.toInt();
      final ms = (e['modified'] as num?)?.toInt();
      items.add(
        LocalShareItem(
          name: '${e['name'] ?? ''}',
          isFolder: e['isFolder'] == true,
          size: (e['size'] as num?)?.toInt(),
          modified: ms == null || ms <= 0
              ? null
              : DateTime.fromMillisecondsSinceEpoch(ms),
          childCount: count ?? 0,
          // Sin dato, la tarjeta NO dice "0 elementos": dice que no se sabe.
          countKnown: count != null,
        ),
      );
    }
    return LocalShareListing(items: items);
  }

  /// URL de la miniatura. Lleva el token en la query porque `Image.network` no
  /// puede mandar cabeceras.
  String thumbUrl(int shareId, List<String> path, {int width = 320}) {
    final q = {
      'share': '$shareId',
      'path': path.join('/'),
      'w': '$width',
      if (_token.isNotEmpty) 'apikey': _token,
    };
    return _u('/api/local/thumb', q).toString();
  }

  /// URL del archivo original (para el visor).
  ///
  /// [light] pide la versión RECODIFICADA (calidad ligera) de un vídeo grande:
  /// el servidor lo trae por el túnel y lo reencoda a 720p al vuelo, así el
  /// reproductor empieza antes. La DESCARGA no la usa: baja el original.
  String fileUrl(int shareId, List<String> path, {bool light = false}) {
    final q = {
      'share': '$shareId',
      'path': path.join('/'),
      if (light) 'play': 'low',
      if (_token.isNotEmpty) 'apikey': _token,
    };
    return _u('/api/local/file', q).toString();
  }

  /// Descarga una imagen con el MISMO comportamiento que el resto de la app:
  /// diálogo Guardar en escritorio y carpeta Descargas en Android.
  /// Devuelve el destino (o null si el usuario canceló).
  ///
  /// El tope es MAYOR que el del servidor (4 minutos): si la carpeta vive en la
  /// computadora del dueño, la foto tiene que cruzar SU conexión, y el que
  /// tiene que explicar una demora es el servidor, no un timeout mudo aquí.
  Future<String?> download(int shareId, List<String> path, String name) async {
    final bytes = await _fileBytes(shareId, path);
    return saveSharedBytes(bytes, name);
  }

  /// Descarga una CARPETA compartida ENTERA como ZIP.
  ///
  /// El servidor del drive sirve las carpetas compartidas archivo por archivo
  /// (`/api/local/file`), así que el ZIP se arma aquí: se recorre la carpeta
  /// (y sus subcarpetas) y se guarda con el mismo diálogo/navegador/Descargas
  /// que el resto de la app. Devuelve el destino (null si el usuario canceló).
  Future<String?> downloadFolderZip(
    int shareId,
    List<String> path, {
    required String name,
  }) async {
    final bytes = await folderZipBytes(shareId, path);
    return saveSharedBytes(bytes, name);
  }

  /// Bytes del ZIP de una carpeta compartida (sin guardarlo).
  ///
  /// Vive aparte de [downloadFolderZip] para poder verificarlo sin tocar el
  /// disco del equipo.
  Future<List<int>> folderZipBytes(int shareId, List<String> path) async {
    final entries = <SharedZipEntry>[];
    Future<void> walk(List<String> rel) async {
      final listing = await list(shareId, rel);
      for (final item in listing.items) {
        final here = [...rel, item.name];
        final arcName = here.sublist(path.length).join('/');
        if (item.isFolder) {
          entries.add(SharedZipEntry('$arcName/', null));
          await walk(here);
        } else {
          entries.add(SharedZipEntry(arcName, await _fileBytes(shareId, here)));
        }
      }
    }

    await walk(path);
    if (entries.isEmpty) {
      throw 'La carpeta no tiene archivos para descargar';
    }
    // El ZIP se arma en un isolate: una carpeta grande no congela la pantalla.
    return compute(encodeSharedZip, entries);
  }

  // ==================== ESCRITURA ====================
  //
  // El servidor exige el permiso del COMPARTIDO (el dueño lo concede al
  // compartir). Aquí solo se pide; quien decide de verdad es él.

  /// Crea una carpeta dentro de [path] (permiso "Crear").
  Future<void> mkdir(int shareId, List<String> path, String name) async {
    final r = await _client
        .post(
          _u('/api/local/mkdir', {}),
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'share': shareId,
            'path': path.join('/'),
            'name': name,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw _why(r, 'No se pudo crear la carpeta (HTTP ${r.statusCode})');
    }
  }

  /// Sube un archivo a [path] (permiso "Crear"). Devuelve el nombre guardado
  /// (el servidor puede renombrarlo si ya existía y no se sobrescribe).
  Future<String> uploadBytes(
    int shareId,
    List<String> path,
    String name,
    List<int> bytes, {
    bool overwrite = false,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      _u('/api/local/upload', {
        'share': '$shareId',
        'path': path.join('/'),
        if (overwrite) 'overwrite': '1',
      }),
    );
    req.headers.addAll(_headers);
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: name));
    final streamed = await _client
        .send(req)
        .timeout(const Duration(minutes: 5));
    final r = await http.Response.fromStream(streamed);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw _why(r, 'No se pudo subir "$name" (HTTP ${r.statusCode})');
    }
    try {
      final data = jsonDecode(r.body);
      if (data is Map && data['name'] is String) return '${data['name']}';
    } catch (_) {
      // Sin JSON: se asume el nombre pedido.
    }
    return name;
  }

  /// Renombra el elemento [path] (permiso "Editar").
  Future<void> rename(int shareId, List<String> path, String newName) async {
    final r = await _client
        .patch(
          _u('/api/local/item', {}),
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'share': shareId,
            'path': path.join('/'),
            'name': newName,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw _why(r, 'No se pudo renombrar (HTTP ${r.statusCode})');
    }
  }

  /// Elimina [names] dentro de [path] (permiso "Editar").
  Future<({int deleted, List<String> errors})> deleteItems(
    int shareId,
    List<String> path,
    List<String> names,
  ) async {
    final r = await _client
        .post(
          _u('/api/local/delete', {}),
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'share': shareId,
            'path': path.join('/'),
            'names': names,
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw _why(r, 'No se pudo eliminar (HTTP ${r.statusCode})');
    }
    final data = jsonDecode(r.body) is Map
        ? (jsonDecode(r.body) as Map)
        : const {};
    return (
      deleted: (data['deleted'] as num?)?.toInt() ?? 0,
      errors: [for (final e in ((data['errors'] as List?) ?? const [])) '$e'],
    );
  }

  /// Mueve o copia [names] de [from] a [to] (editar / crear).
  Future<({int moved, List<String> errors})> transfer(
    int shareId, {
    required bool move,
    required List<String> from,
    required List<String> names,
    required List<String> to,
  }) async {
    final r = await _client
        .post(
          _u('/api/local/${move ? 'move' : 'copy'}', {}),
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'share': shareId,
            'from': from.join('/'),
            'names': names,
            'to': to.join('/'),
          }),
        )
        .timeout(const Duration(minutes: 5));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw _why(
        r,
        'No se pudo ${move ? 'mover' : 'copiar'} (HTTP ${r.statusCode})',
      );
    }
    final data = jsonDecode(r.body) is Map
        ? (jsonDecode(r.body) as Map)
        : const {};
    return (
      moved: (data[move ? 'moved' : 'copied'] as num?)?.toInt() ?? 0,
      errors: [for (final e in ((data['errors'] as List?) ?? const [])) '$e'],
    );
  }

  /// Bytes del archivo original (se descarga o se mete en un ZIP).
  Future<List<int>> _fileBytes(int shareId, List<String> path) async {
    final r = await _client
        .get(
          _u('/api/local/file', {'share': '$shareId', 'path': path.join('/')}),
          headers: _headers,
        )
        .timeout(const Duration(minutes: 5));
    if (r.statusCode != 200) {
      throw _why(r, 'No se pudo descargar (HTTP ${r.statusCode})');
    }
    return r.bodyBytes;
  }
}

/// Una entrada del ZIP de una carpeta compartida (`bytes` null = carpeta).
class SharedZipEntry {
  const SharedZipEntry(this.name, this.bytes);

  final String name;
  final List<int>? bytes;
}

/// Arma el ZIP de una carpeta compartida. Vive FUERA de la clase para poder
/// correr en `compute` (la interfaz sigue respondiendo mientras comprime).
List<int> encodeSharedZip(List<SharedZipEntry> entries) {
  final archive = Archive();
  for (final e in entries) {
    final name = e.name.replaceAll('\\', '/');
    final bytes = e.bytes;
    if (bytes == null) {
      archive.add(ArchiveFile.string(name, ''));
    } else {
      archive.add(ArchiveFile.bytes(name, bytes));
    }
  }
  return ZipEncoder().encode(archive);
}

/// Guarda bytes con el MISMO comportamiento que el resto de la app: diálogo
/// Guardar en escritorio, carpeta Descargas en Android y el navegador en web.
Future<String?> saveSharedBytes(List<int> bytes, String name) async {
  if (kIsWeb) {
    triggerBrowserDownload(bytes, name);
    return null;
  }
  if (needsSaveDialog) {
    final loc = await getSaveLocation(suggestedName: name);
    if (loc == null) return null;
    await File(loc.path).writeAsBytes(bytes);
    return loc.path;
  }
  if (isAndroidPlatform) {
    final saved = await saveToAndroidDownloads(bytes, name);
    if (saved == null) throw 'No se pudo guardar en Descargas';
    return saved;
  }
  throw 'No se pudo determinar el destino de la descarga';
}

/// Adaptador de una carpeta LOCAL compartida al contrato [DriveBase].
///
/// Sirve para que el VISOR de imágenes del módulo Archivos se pueda reutilizar
/// tal cual dentro de una carpeta compartida (mismo zoom, flechas, Esc y botón
/// de descarga): el visor pide miniaturas y originales a un drive, y aquí se
/// resuelven contra los endpoints /api/local/* del servidor del drive.
///
/// Es de SOLO LECTURA: cualquier operación de escritura lanza, porque el
/// servidor no las ofrece para estas carpetas.
class LocalShareDrive extends DriveBase {
  LocalShareDrive({
    required this.service,
    required this.shareId,
    required this.rel,
  });

  final LocalShareService service;
  final int shareId;

  /// Subcarpeta dentro de la carpeta compartida (vacío = la raíz compartida).
  final List<String> rel;

  List<String> _segments(DriveItem item) => [...rel, item.name];

  @override
  Future<void> refresh() async {}

  @override
  String absolutePathOf(DriveItem item) =>
      service.fileUrl(shareId, _segments(item));

  @override
  String thumbSource(DriveItem item, {int width = 320}) =>
      service.thumbUrl(shareId, _segments(item), width: width);

  /// Fotos, RAW y VÍDEOS: el servidor saca el primer fotograma del vídeo y la
  /// vista previa embebida del RAW.
  @override
  bool canThumb(DriveItem item) =>
      item.kind == DriveItemKind.image ||
      item.kind == DriveItemKind.raw ||
      item.kind == DriveItemKind.video;

  /// Preview del VISOR.
  ///
  /// Se le pide al servidor la versión REDIMENSIONADA (`/api/local/thumb`,
  /// que la genera una vez y la guarda en caché) en vez del original: el
  /// original puede ser una foto de 10 MB que, además, tiene que viajar desde
  /// la computadora de quien comparte si su carpeta es de su PC. Así el visor
  /// abre al instante y el original se pide sólo si se descarga.
  @override
  String fullSource(DriveItem item, {int? previewWidth}) => previewWidth == null
      ? service.fileUrl(shareId, _segments(item))
      : service.thumbUrl(shareId, _segments(item), width: previewWidth);

  /// REPRODUCCIÓN: un vídeo de más de 50 MB se ve en CALIDAD LIGERA (el
  /// servidor lo reencoda a 720p al vuelo). Descargar sigue bajando el
  /// original; esto es solo para verlo.
  @override
  String playSource(DriveItem item) => service.fileUrl(
    shareId,
    _segments(item),
    light: wantsLightPlayback(item),
  );

  @override
  List<String> listFolders(List<String> rel) => const [];

  Never _readOnly() => throw UnsupportedError(
    'Una carpeta compartida de la computadora de otra persona es de '
    'solo lectura: se puede ver y descargar, no modificar',
  );

  @override
  Future<int> uploadFromPaths(List<String> sources, {bool overwrite = false}) =>
      _readOnly();

  @override
  Future<void> createFolder(String name) => _readOnly();

  @override
  Future<void> rename(DriveItem item, String newName) => _readOnly();

  @override
  Future<void> delete(DriveItem item) => _readOnly();

  @override
  Future<({int moved, List<String> errors})> moveItems(
    List<String> names,
    List<String> targetPath,
  ) => _readOnly();

  @override
  Future<({int copied, List<String> errors})> copyItems(
    List<String> names,
    List<String> targetPath,
  ) => _readOnly();

  @override
  Future<({int deleted, List<String> errors})> deleteItems(
    List<String> names,
  ) => _readOnly();

  @override
  Future<void> retryUpload(String jobId) => _readOnly();
}

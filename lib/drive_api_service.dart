import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'app_constants.dart';
import 'drive_base.dart';
import 'drive_host.dart';
import 'hs_api.dart';

export 'drive_base.dart'
    show
        DriveBase,
        DriveItem,
        // Tipos de archivo del Drive (foto, vídeo, audio, PDF, texto…): con
        // ellos la vista decide el icono y con qué visor se abre cada archivo.
        DriveItemKind,
        driveItemKindOf,
        driveKindLabel,
        driveExtensionLabel,
        driveImagePreview,
        driveRelPath,
        kImageExtensions,
        kRawExtensions,
        kVideoExtensions,
        kAudioExtensions,
        kPdfExtensions,
        kTextExtensions,
        DriveConn,
        DriveBusy,
        DriveUploadJob,
        DriveDownloadJob;

/// Cliente del drive remoto (Node/Express en 192.168.1.72:4000).
/// Mantiene la MISMA interfaz que [DriveService] para que la UI no cambie.
///
/// AUTORIZACIÓN: todas las peticiones llevan `Apikey: <token de sesión>`.
/// El servidor del drive verifica el token (mismo JWT_SECRET que el CRUD)
/// y comprueba en la BD que el usuario tenga el permiso de la acción
/// (ver/crear/editar/eliminar/descargar). Sin token el servidor puede
/// rechazar la petición (según su configuración).
class DriveApiService extends DriveBase {
  DriveApiService({String? baseUrl}) : _fixedBase = baseUrl {
    refresh();
  }

  /// Dirección fija de las pruebas (null = la configurada en [DriveHost]).
  final String? _fixedBase;

  /// Se resuelve en cada uso: así el respaldo automático a la red local
  /// cambia las URLs sin recrear el servicio.
  String get base => _fixedBase ?? AppConstants.apiBase;

  /// Evita reintentar el respaldo más de una vez por sesión.
  static bool _fallbackTried = false;

  /// Cliente HTTP de las peticiones JSON del drive. Es INYECTABLE: las pruebas
  /// lo reemplazan por un `MockClient` para no tocar la red (mismo patrón que
  /// `HsApi.client`). Las subidas y las descargas por bloques crean su propio
  /// cliente, así que no pasan por aquí.
  static http.Client client = http.Client();

  /// Cliente de las SUBIDAS (cada lote abre el suyo y los comparte entre sus
  /// trabajadores). Es inyectable igual que [client]: sin esto, una prueba
  /// terminaría subiendo a la red de verdad.
  @visibleForTesting
  static http.Client Function() uploadClientFactory = () => http.Client();

  /// Token de sesión actual (el mismo del login contra el CRUD).
  static String get _apikey => HsSession.token ?? '';

  /// Headers de autorización para peticiones JSON/multipart.
  static Map<String, String> get _authHeaders => {
    if (_apikey.isNotEmpty) 'Apikey': _apikey,
  };

  /// Query con el token para URLs de imagen (Image.network no manda headers).
  static String get _apikeyQuery => _apikey.isEmpty ? '' : 'apikey=$_apikey';

  Uri _u(String p, [Map<String, String>? q]) =>
      Uri.parse('$base$p').replace(queryParameters: q);

  /// Conversión numérica tolerante: JS manda doubles (mtimeMs) y Dart
  /// decodifica enteros como int solo si no tienen punto decimal.
  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// Ruta URL de un archivo para previsualización (Image.network).
  /// Lleva el token en la query (?apikey=): el servidor valida permisos.
  @override
  String absolutePathOf(DriveItem item) {
    final q = _apikeyQuery;
    return '$base/files/${[...path, item.name].join('/')}'
        '${q.isEmpty ? '' : '?$q'}';
  }

  /// Versión PREVIEW para el visor: 1600px (~400-800 KB en vez de 10 MB).
  ///
  /// `/thumb` es PÚBLICO (son las imágenes del catálogo), así que aquí no se
  /// manda el token: una URL de imagen no debe llevar la sesión encima.
  @override
  String fullSource(DriveItem item, {int? previewWidth}) {
    if (previewWidth == null) return absolutePathOf(item);
    return '$base/thumb/${[...path, item.name].join('/')}'
        '?w=$previewWidth&q=80';
  }

  /// REPRODUCCIÓN en el visor: un vídeo de más de 50 MB se pide en CALIDAD
  /// LIGERA (`?play=low`). El servidor lo reencoda a 720p al vuelo y lo manda
  /// fragmentado, así empieza en segundos aunque el original sea 4K.
  @override
  String playSource(DriveItem item) {
    final url = absolutePathOf(item);
    if (!wantsLightPlayback(item)) return url;
    return '$url${url.contains('?') ? '&' : '?'}play=low';
  }

  /// Miniatura liviana generada por el servidor (JPEG pequeño, con caché).
  @override
  String thumbSource(DriveItem item, {int width = 320}) {
    return '$base/thumb/${[...path, item.name].join('/')}?w=$width';
  }

  /// El servidor del drive saca el PRIMER FOTOGRAMA de un vídeo (`/thumb` con
  /// ffmpeg) y la vista previa embebida de un RAW: ambas tarjetas enseñan
  /// miniatura, no un icono.
  @override
  bool canThumb(DriveItem item) =>
      item.kind == DriveItemKind.image ||
      item.kind == DriveItemKind.raw ||
      item.kind == DriveItemKind.video;

  /// Espacio total y ocupado del drive → GET /api/space.
  /// { usedBytes, totalBytes, freeBytes, files, folders } (total/free pueden
  /// ser null si el filesystem no expone statfs).
  Future<Map<String, dynamic>> fetchSpace() async {
    final r = await http
        .get(_u('/api/space'), headers: _authHeaders)
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// true cuando el último refresco se OMITIÓ por no haber sesión todavía.
  /// La app lo consulta para pedir el listado en cuanto entra la sesión.
  bool waitingSession = false;

  /// Publica en el servidor del drive las fotos del Drive que tiene que poder
  /// abrir la WEB SIN SESIÓN (la portada del sitio y la imagen de cada
  /// paquete).
  ///
  /// El servidor del drive exige permiso de lectura para `/files/…`, y la
  /// página pública no tiene sesión: por eso guardamos la lista de fotos
  /// publicadas y sólo ésas se sirven sin token. [scope] agrupa la lista por
  /// módulo ("sitio", "paquetes"): al enviarla se REEMPLAZA la de ese módulo,
  /// así una foto que se quitó de un paquete deja de estar publicada.
  ///
  /// Es silencioso a propósito: un servidor viejo (sin el endpoint) o sin
  /// red no debe romper el módulo que la llama; sus fotos se verán en el
  /// panel (que sí lleva token) aunque la web todavía no.
  static Future<int> publishPublicPhotos(
    String scope,
    Iterable<Object?> urls,
  ) async {
    final paths = <String>{};
    for (final u in urls) {
      final rel = driveRelPath('${u ?? ''}');
      if (rel != null) paths.add(rel);
    }
    if (_apikey.isEmpty) return 0;
    try {
      final base = AppConstants.apiBase.replaceAll(RegExp(r'/$'), '');
      final r = await client
          .post(
            Uri.parse('$base/api/public-photos'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'scope': scope,
              'paths': paths.take(2000).toList(growable: false),
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return 0;
      final data = jsonDecode(r.body);
      return data is Map ? _asInt(data['count']) ?? 0 : 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<void> refresh() async {
    // SIN sesión NO se llama al servidor. El cliente del drive se crea al
    // construir la app (antes del login o de restaurar la sesión) y su primer
    // refresco salía sin `Apikey`: el servidor lo rechaza y el módulo Archivos
    // quedaba con "No se pudo iniciar el almacenamiento" hasta que el usuario
    // recargaba. Aquí se deja en blanco y sin error (la página muestra su
    // cargador); AdminHome vuelve a pedir el listado en cuanto entra la sesión.
    if (_apikey.isEmpty) {
      waitingSession = true;
      loading = false;
      error = null;
      return;
    }
    waitingSession = false;
    // TICKET del refresco: si mientras carga el usuario se va a otra carpeta
    // (o se refresca otra vez), lo que llegue después se DESCARTA. Si no, las
    // fotos de la carpeta que se dejó aparecerían encima de la nueva.
    final ticket = beginRefresh();
    loading = true;
    error = null;
    notifyListeners();
    try {
      final r = await client
          .get(_u('/api/drive', {'path': ticket.path}), headers: _authHeaders)
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      final raw = (data['folders'] as List? ?? []);
      final folders = <DriveItem>[];
      final files = <DriveItem>[];
      for (final e in raw) {
        if (e is! Map<String, dynamic>) continue;
        final m = e;
        final modifiedMs = _asInt(m['modified']);
        final it = DriveItem(
          name: m['name']?.toString() ?? '',
          isFolder: m['isFolder'] == true,
          modified: modifiedMs != null
              ? DateTime.fromMillisecondsSinceEpoch(modifiedMs)
              : null,
          size: _asInt(m['size']),
          childCount: _asInt(m['childCount']) ?? 0,
        );
        (it.isFolder ? folders : files).add(it);
      }
      // El alcance compartido (y los conteos) los aplica [applyRefresh].
      if (!applyRefresh(ticket, [...folders, ...files])) return;
      conn = DriveConn.online;
    } catch (e) {
      if (isCurrentRefresh(ticket)) {
        // En el celular el nombre público puede responder con el certificado
        // del router (HandshakeException) o el navegador bloquearlo (Failed to
        // fetch). Antes de rendirnos probamos las direcciones de respaldo: el
        // MISMO nombre por HTTP (funciona desde internet) y la IP local.
        if (await _tryConnectionFallback(e)) {
          await refresh();
          return;
        }
        failRefresh('No se pudo conectar con el servidor ($base): $e');
      }
    } finally {
      // El girador lo apaga el ÚLTIMO refresco pedido (un refresco viejo no
      // puede dejarlo encendido para siempre).
      if (isLatestRefresh(ticket)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// Prueba las direcciones de respaldo cuando la configurada falla por red/TLS.
  ///
  /// Devuelve true si cambió a una de ellas; el llamador repite la petición.
  /// Solo se intenta con errores de CONEXIÓN (no con un 401/403 del servidor)
  /// y una vez por sesión, para no mandar al usuario a una IP que no existe.
  Future<bool> _tryConnectionFallback(Object error) async {
    if (_fixedBase != null || _fallbackTried || DriveHost.isCustom) {
      return false;
    }
    final text = error.toString().toLowerCase();
    final connectionError =
        text.contains('handshake') ||
        text.contains('certificate') ||
        text.contains('failed to fetch') ||
        text.contains('socket') ||
        text.contains('connection') ||
        text.contains('timed out') ||
        text.contains('timeout') ||
        text.contains('clientexception');
    if (!connectionError) return false;
    _fallbackTried = true;
    for (final candidate in DriveHost.fallbackCandidates) {
      try {
        final r = await http
            .get(Uri.parse('$candidate/api/health'))
            .timeout(const Duration(seconds: 3));
        if (r.statusCode == 200) {
          DriveHost.useFallback(candidate);
          return true;
        }
      } catch (_) {
        // Esta dirección no responde: se prueba la siguiente.
      }
    }
    return false;
  }

  /// ¿Nombres ya existen en la carpeta actual del servidor?
  @override
  Future<List<String>> filterExisting(List<String> names) async {
    if (names.isEmpty) return const [];
    try {
      final r = await _post('/api/check-duplicate', {
        'path': path.join('/'),
        'names': names,
      });
      return (r['duplicates'] as List? ?? []).cast<String>();
    } catch (_) {
      return const []; // si falla, dejamos subir (el server renombra solo)
    }
  }

  /// Sube cada archivo en su propia petición con progreso REAL por bytes.
  /// NO bloquea la UI: cada trabajo vive en [uploadJobs] (panel estilo Drive).
  /// Hasta [kUploadParallel] archivos suben EN PARALELO y TODOS los trabajos
  /// aparecen en el panel desde el inicio (no uno por uno).
  /// Con [overwrite] borra primero el existente con el mismo nombre.
  /// Los trabajos con `cancelled = true` se saltan o se abortan en vuelo.
  @override
  Future<int> uploadFromPaths(
    List<String> sources, {
    bool overwrite = false,
  }) async {
    if (sources.isEmpty) return 0;
    // En el navegador no hay rutas del disco: lo que llega como "ruta" es una
    // URL de Blob y `File` revienta ("Unsupported operation: _Namespace").
    // Ahí se contesta con un error claro en vez de tumbar la subida.
    if (kIsWeb) {
      throw 'En el navegador elige los archivos con el botón Subir archivos';
    }
    // 1. Registrar TODOS los trabajos primero: el panel muestra la lista
    //    completa al 0% desde el primer frame. Todos van en el MISMO lote, que
    //    es el que el panel cuenta ("50/100 fotos").
    final batch = newUploadBatch();
    final pending = <(DriveUploadJob, _UploadSource)>[];
    var i = 0;
    for (final s in sources) {
      final f = File(s);
      if (!f.existsSync()) continue;
      // Acepta rutas con / o \ mezclados (drop externo, file_selector…).
      final fileName = s.split(RegExp(r'[\\/]')).last;
      final job = DriveUploadJob(
        id: 'u${DateTime.now().microsecondsSinceEpoch}-$i',
        name: fileName,
        thumb: s, // miniatura del archivo LOCAL mientras sube
        total: f.lengthSync(),
        batch: batch,
      );
      i++;
      addUploadJob(job);
      pending.add((job, _UploadSource(path: s)));
    }
    return _runUploads(pending, overwrite: overwrite);
  }

  /// Sube fotos elegidas en el SELECTOR del sistema o del navegador.
  ///
  /// En el navegador el `XFile` apunta a un Blob (`path` = `blob:…`): sus
  /// BYTES son lo único que se puede mandar. En escritorio se usa la ruta real,
  /// igual que en [uploadFromPaths] (así una foto enorme no se carga entera en
  /// memoria para subirla).
  @override
  Future<int> uploadFromFiles(
    List<XFile> sources, {
    bool overwrite = false,
  }) async {
    if (sources.isEmpty) return 0;
    final batch = newUploadBatch();
    final pending = <(DriveUploadJob, _UploadSource)>[];
    var i = 0;
    for (final x in sources) {
      // El nombre puede venir SOLO (web) o ser la ruta completa (escritorio):
      // se toma el último segmento en los dos casos.
      final base = x.name.isNotEmpty ? x.name : x.path;
      final name = base.split(RegExp(r'[\\/]')).last;
      if (name.isEmpty) continue;
      int total = 0;
      try {
        total = await x.length();
      } catch (_) {
        // Sin tamaño: el panel lo muestra indeterminado, la subida sigue.
      }
      final job = DriveUploadJob(
        id: 'u${DateTime.now().microsecondsSinceEpoch}-$i',
        name: name,
        // En el navegador el Blob no es una ruta de disco: no hay miniatura
        // local (el panel dibuja su icono y la foto aparece al refrescar).
        thumb: kIsWeb ? '' : x.path,
        total: total,
        batch: batch,
        file: x,
      );
      i++;
      addUploadJob(job);
      pending.add((job, _UploadSource(file: x, path: kIsWeb ? null : x.path)));
    }
    return _runUploads(pending, overwrite: overwrite);
  }

  /// Pool de subidas (y reintentos) compartido por las dos entradas.
  Future<int> _runUploads(
    List<(DriveUploadJob, _UploadSource)> pending, {
    required bool overwrite,
  }) async {
    if (pending.isEmpty) return 0;
    final client = uploadClientFactory();
    var saved = 0;
    var next = 0;
    Future<void> worker() async {
      while (next < pending.length) {
        final (job, src) = pending[next++];
        // Cancelado mientras esperaba en cola: se salta.
        if (job.cancelled) {
          job.status = 'cancelled';
          job.error = 'Cancelado';
          notifyUploadProgress();
          continue;
        }
        // Formato que el Drive no guarda: se marca en el acto, sin gastar los
        // tres intentos en algo que el servidor va a rechazar siempre.
        final format = uploadFormatError(job.name);
        if (format != null) {
          finishUploadJob(job, error: format);
          continue;
        }
        // Reintentos automáticos: una subida que se corta (enlace doméstico,
        // timeout, servidor ocupado) se vuelve a intentar con espera creciente
        // en vez de quedar perdida.
        final ok = await runUploadWithRetries(job, () async {
          if (overwrite) {
            // Sobrescribir: elimina el existente y sube el nuevo.
            try {
              await _post('/api/delete', {
                'path': path.join('/'),
                'names': [job.name],
              });
            } catch (_) {
              /* si no existía, sigue */
            }
          }
          await _uploadOne(client, job, src);
        });
        if (ok) saved++;
      }
    }

    try {
      await Future.wait(List.generate(kUploadParallel, (_) => worker()));
    } finally {
      client.close();
      await refresh();
    }
    return saved;
  }

  /// A partir de este tamaño la foto va EN TROZOS.
  ///
  /// Un solo cuerpo grande lo rechaza el proxy del servidor (nginx contesta una
  /// página HTML "413 Request Entity Too Large") y, si se corta a medio camino,
  /// había que empezar la foto completa otra vez. El umbral es UN trozo: así
  /// ninguna petición lleva más de lo que ese proxy aceptó ya con las fotos
  /// grandes, y una foto mediana no gasta un intento que va a rebotar.
  @visibleForTesting
  static int chunkThreshold = 4 * 1024 * 1024;

  /// Tamaño de cada trozo (queda MUY por debajo de los límites típicos de un
  /// proxy: 1-8 MB).
  @visibleForTesting
  static int chunkSize = 4 * 1024 * 1024;

  /// Sube un archivo con barra de progreso (stream con contador de bytes).
  Future<void> _uploadOne(
    http.Client client,
    DriveUploadJob job,
    _UploadSource src,
  ) async {
    // El Drive acepta fotos, RAW y VÍDEOS (el servidor lista y sirve esos
    // formatos): cualquier otro se rechaza al instante con un motivo claro, en
    // vez de gastar los tres intentos de subida para recibir un error opaco
    // del servidor.
    final format = uploadFormatError(job.name);
    if (format != null) throw format;
    if (job.total > chunkThreshold) {
      await _uploadChunked(client, job, src);
      return;
    }
    final rejected = await _uploadMultipart(client, job, src);
    if (!rejected) return;
    // El proxy contestó 413 a una foto que iba en UNA pieza: su límite real es
    // más bajo que [chunkThreshold] (por eso unas fotos pequeñas subían y
    // otras no, según lo que pesaran). En vez de rendirse —o de repetir tres
    // veces el mismo cuerpo que el proxy va a volver a rechazar—, la foto se
    // rehace EN TROZOS, que ya saben encogerse si hace falta.
    job.sent = 0;
    notifyUploadProgress();
    // Si el tamaño no se conocía, se lee ahora: el troceado lo necesita.
    final size = job.total > 0 ? null : await _sizeOf(src);
    await _uploadChunked(client, job, src, size: size);
  }

  /// Motivo por el que una foto NO se puede subir, o `null` si su formato vale.
  ///
  /// El Drive guarda FOTOS y VÍDEOS (el servidor lista y sirve los dos); con
  /// otra extensión el archivo se quedaría guardado pero invisible (o
  /// rechazado con un error genérico).
  String? uploadFormatError(String name) {
    if (hasPhotoExt(name) || hasVideoExt(name)) return null;
    final ext = extOf(name);
    return 'Formato no admitido (${ext.isEmpty ? 'sin extensión' : ext}): '
        'se aceptan JPG, PNG, GIF, WEBP, BMP, HEIC, AVIF, TIFF, RAW '
        '(DNG, CR2, CR3…) y vídeo (MP4, MOV, MTS, M2TS, WEBM, MKV, AVI…)';
  }

  /// Tamaño real de la fuente (cuando el trabajo no lo había podido leer).
  Future<int> _sizeOf(_UploadSource src) async {
    try {
      return src.file != null
          ? await src.file!.length()
          : await File(src.path!).length();
    } catch (_) {
      return 0;
    }
  }

  /// Sube la foto en UNA petición multipart/form-data.
  ///
  /// Devuelve `true` si la petición no pasó por el proxy (413 de tamaño, o una
  /// página HTML en vez de la API): la foto hay que rehacerla en trozos.
  Future<bool> _uploadMultipart(
    http.Client client,
    DriveUploadJob job,
    _UploadSource src,
  ) async {
    final req = http.MultipartRequest('POST', _u('/api/upload'))
      ..headers.addAll(_authHeaders)
      ..fields['path'] = path.join('/')
      ..files.add(
        src.file != null
            ? http.MultipartFile.fromBytes(
                'files',
                await src.file!.readAsBytes(),
                filename: job.name,
                contentType: _mediaType(extOf(job.name)),
              )
            : await http.MultipartFile.fromPath(
                'files',
                src.path!,
                filename: job.name,
                contentType: _mediaType(extOf(job.name)),
              ),
      );

    final counted = req.finalize().transform<List<int>>(
      StreamTransformer.fromHandlers(
        handleData: (chunk, sink) {
          // Cancelación en vuelo: aborta el envío en el siguiente bloque.
          if (job.cancelled) {
            sink.addError(Exception('cancelado'));
            sink.close();
            return;
          }
          job.sent += chunk.length;
          notifyUploadProgress();
          sink.add(chunk);
        },
      ),
    );

    final streamed = http.StreamedRequest(req.method, req.url)
      ..headers.addAll(req.headers)
      ..headers.addAll(_authHeaders);
    // Bombear el cuerpo mientras la petición está en vuelo.
    final pumping = streamed.sink.addStream(counted).then((_) {
      streamed.sink.close();
    });
    try {
      final response = await client
          .send(streamed)
          .timeout(const Duration(minutes: 10));
      final body = await response.stream.bytesToString();
      if (response.statusCode != 200) {
        // Un cuerpo HTML no lo escribe el drive (siempre contesta JSON): viene
        // del proxy que hay delante. Es la señal de que UNA petición con el
        // cuerpo entero no pasa: la foto se rehace en trozos en vez de repetir
        // tres veces lo mismo. El proxy corta el cuerpo al contestar, así que
        // el bombeo se deja cerrar sin convertir eso en un fallo.
        if (response.statusCode == 413 || _looksLikeHtml(body)) {
          await pumping.catchError((_) {});
          return true;
        }
        throw 'HTTP ${response.statusCode}: '
            '${_errorOf(body, status: response.statusCode)}';
      }
      await pumping;
      return false;
    } catch (_) {
      await pumping.catchError((_) {});
      rethrow;
    }
  }

  /// Trozo más chico que se usa cuando el proxy rechaza los grandes (413).
  static const int _minChunkSize = 256 * 1024;

  /// Hasta dónde se puede encoger (con trozos configurados más chicos que el
  /// mínimo —solo en pruebas— el suelo baja con ellos).
  static int get _chunkFloor => chunkSize < _minChunkSize ? 1 : _minChunkSize;

  /// Sube una foto GRANDE en trozos y la ensambla en el servidor.
  ///
  /// Ninguno de los trozos pasa del límite del proxy (era el 413 de las fotos
  /// grandes) y, si ese límite es MÁS bajo de lo esperado, la subida se rehace
  /// con trozos cuatro veces más chicos en vez de rendirse.
  Future<void> _uploadChunked(
    http.Client client,
    DriveUploadJob job,
    _UploadSource src, {
    int? size,
  }) async {
    var pieces = chunkSize;
    while (true) {
      final tooBig = await _sendChunks(client, job, src, pieces, size: size);
      if (!tooBig) return;
      final floor = _chunkFloor;
      if (pieces <= floor) {
        throw 'El servidor rechaza hasta los trozos más chicos: revisa el '
            'límite de subida de tu proxy (client_max_body_size)';
      }
      // Se rehace la subida entera con trozos más chicos.
      final next = pieces ~/ 4;
      pieces = next < floor ? floor : next;
      job.sent = 0;
      notifyUploadProgress();
    }
  }

  /// Manda la foto troceada a [pieces] bytes y la cierra. Devuelve `true` si el
  /// servidor rechazó el tamaño (413) y hay que reintentar más chico.
  Future<bool> _sendChunks(
    http.Client client,
    DriveUploadJob job,
    _UploadSource src,
    int pieces, {
    int? size,
  }) async {
    final total = (size != null && size > 0) ? size : job.total;
    if (total <= 0) throw 'No se pudo leer el tamaño de la foto';
    final id =
        'up${DateTime.now().microsecondsSinceEpoch}'
        '${job.id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '')}';
    final count = (total + pieces - 1) ~/ pieces;
    final rel = path.join('/');
    var sent = 0;
    for (var index = 0; index < count; index++) {
      if (job.cancelled) throw 'cancelado';
      final start = index * pieces;
      final end = start + pieces > total ? total : start + pieces;
      final bytes = await src.readRange(start, end);
      final uri = _u('/api/upload/chunk', {
        'id': id,
        'index': '$index',
        'total': '$count',
        'path': rel,
        'name': job.name,
      });
      final res = await client
          .post(
            uri,
            headers: {
              ..._authHeaders,
              'Content-Type': 'application/octet-stream',
            },
            body: bytes,
          )
          .timeout(const Duration(minutes: 2));
      if (res.statusCode == 413) return true;
      if (res.statusCode != 200) {
        throw 'HTTP ${res.statusCode}: ${_errorOf(res.body)}';
      }
      sent += bytes.length;
      job.sent = sent;
      notifyUploadProgress();
    }
    final done = await client
        .post(
          _u('/api/upload/finish'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'id': id,
            'total': count,
            'path': rel,
            'name': job.name,
          }),
        )
        .timeout(const Duration(minutes: 2));
    if (done.statusCode != 200) {
      throw 'HTTP ${done.statusCode}: ${_errorOf(done.body)}';
    }
    job.sent = total;
    notifyUploadProgress();
    return false;
  }

  /// Mensaje de error del servidor (JSON `{error}`) o el cuerpo tal cual.
  ///
  /// El cuerpo puede ser una PÁGINA HTML del proxy (el "413 Request Entity Too
  /// Large" de nginx): volcarla entera en el panel no dice nada al usuario, así
  /// que se resume. El resto de cuerpos sí se muestran, recortados.
  static String _errorOf(String body, {int? status}) {
    final text = body.trim();
    try {
      final msg = (jsonDecode(text) as Map<String, dynamic>)['error'];
      if (msg is String && msg.isNotEmpty) return msg;
    } catch (_) {
      /* no era JSON del servidor */
    }
    if (_looksLikeHtml(text)) {
      return status == 413
          ? 'el proxy del servidor rechazó el tamaño (413): revisa '
                'client_max_body_size'
          : 'el proxy contestó una página HTML en vez de la API del drive';
    }
    if (text.isEmpty) return 'el servidor no respondió nada';
    return text.length > 240 ? '${text.substring(0, 240)}…' : text;
  }

  /// ¿El cuerpo es una página web (proxy/wifi con login) y no la API del drive?
  static bool _looksLikeHtml(String body) => body.trimLeft().startsWith('<');

  /// Resubir a mano un archivo que quedó con error (botón "Resubir").
  @override
  Future<void> retryUpload(String jobId) async {
    final job = uploadJobById(jobId);
    if (job == null || job.status == 'uploading') return;
    job.restart();
    job.attempts = 0;
    notifyUploadProgress();
    final client = uploadClientFactory();
    try {
      final x = job.file;
      await runUploadWithRetries(
        job,
        () => _uploadOne(
          client,
          job,
          _UploadSource(
            file: x,
            path: x == null ? job.thumb : (kIsWeb ? null : x.path),
          ),
        ),
      );
    } finally {
      client.close();
      await refresh();
    }
  }

  /// Tipo MIME que viaja en la parte multipart. El servidor guarda por
  /// extensión, pero un vídeo declarado como `image/jpeg` es incorrecto y
  /// algunos proxies lo tratan distinto.
  MediaType _mediaType(String ext) => switch (ext) {
    '.png' => MediaType('image', 'png'),
    '.gif' => MediaType('image', 'gif'),
    '.webp' => MediaType('image', 'webp'),
    '.bmp' => MediaType('image', 'bmp'),
    '.mp4' || '.m4v' => MediaType('video', 'mp4'),
    '.mov' => MediaType('video', 'quicktime'),
    '.webm' => MediaType('video', 'webm'),
    '.mkv' => MediaType('video', 'x-matroska'),
    '.avi' => MediaType('video', 'x-msvideo'),
    '.3gp' => MediaType('video', '3gpp'),
    _ => MediaType('image', 'jpeg'),
  };

  @override
  Future<void> createFolder(String name) async {
    await _post('/api/folders', {'path': path.join('/'), 'name': name});
    await refresh();
  }

  @override
  Future<void> rename(DriveItem item, String newName) async {
    // Un archivo conserva su extensión: sin esto, renombrar "foto.jpg" a
    // "foto" la dejaba invisible y a un "video.mp4" le pegaba la extensión
    // dos veces ("video.mp4.mp4").
    var name = newName.trim();
    if (!item.isFolder && extOf(name).isEmpty) {
      name = '$name${extOf(item.name)}';
    }
    if (name.isEmpty || name == item.name) return;
    await _post('/api/items', {
      'path': path.join('/'),
      'name': item.name,
      'newName': name,
    }, method: 'PATCH');
    await refresh();
  }

  @override
  Future<void> delete(DriveItem item) => deleteItems([item.name]).then((_) {});

  @override
  Future<({int moved, List<String> errors})> moveItems(
    List<String> names,
    List<String> targetPath,
  ) {
    return runBusy(DriveBusy.moving, 'Moviendo en el servidor…', () async {
      final r = await _post('/api/move', {
        'from': path,
        'names': names,
        'to': targetPath,
      });
      await refresh();
      return (
        moved: _asInt(r['moved']) ?? 0,
        errors: (r['errors'] as List? ?? []).cast<String>(),
      );
    });
  }

  @override
  Future<({int copied, List<String> errors})> copyItems(
    List<String> names,
    List<String> targetPath,
  ) {
    return runBusy(DriveBusy.copying, 'Copiando en el servidor…', () async {
      final r = await _post('/api/copy', {
        'from': path,
        'names': names,
        'to': targetPath,
      });
      await refresh();
      return (
        copied: _asInt(r['copied']) ?? 0,
        errors: (r['errors'] as List? ?? []).cast<String>(),
      );
    });
  }

  @override
  Future<({int deleted, List<String> errors})> deleteItems(List<String> names) {
    return runBusy(DriveBusy.deleting, 'Eliminando en el servidor…', () async {
      final r = await _post('/api/delete', {
        'path': path.join('/'),
        'names': names,
      });
      await refresh();
      return (
        deleted: _asInt(r['deleted']) ?? 0,
        errors: (r['errors'] as List? ?? []).cast<String>(),
      );
    });
  }

  /// Subcarpetas DIRECTAS de [rel] consultadas al servidor, SIN mover el
  /// estado del drive (la carpeta que el usuario está viendo no cambia).
  /// Lo usa el selector de carpeta del administrador del paquete.
  @override
  Future<List<String>> listChildFolders(List<String> rel) async {
    try {
      final r = await http
          .get(_u('/api/drive', {'path': rel.join('/')}), headers: _authHeaders)
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      final raw = (data['folders'] as List?) ?? const [];
      return [
        for (final e in raw)
          if (e is Map && e['isFolder'] == true) e['name']?.toString() ?? '',
      ].where((n) => n.isNotEmpty).toList(growable: false);
    } catch (e) {
      throw 'No se pudo abrir la carpeta: $e';
    }
  }

  /// ESPACIO de la carpeta de fotos consultado al servidor del drive
  /// (`/api/space`): usado, cuota configurada (`limitBytes`) y libre real.
  /// El servidor recorre el árbol, así que se le da un margen amplio.
  @override
  Future<Map<String, dynamic>?> storageInfo() async {
    final r = await http
        .get(_u('/api/space'), headers: _authHeaders)
        .timeout(const Duration(seconds: 90));
    if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
    return (jsonDecode(r.body) as Map).cast<String, dynamic>();
  }

  /// Cuántos elementos hay DENTRO de cada carpeta compartida.
  ///
  /// El listado de la raíz del cliente solo trae las carpetas de primer nivel
  /// del estudio, así que el contenido de una compartida anidada
  /// (`XV/ReynaCoot`) no se puede deducir: se pregunta al servidor, en
  /// paralelo y sin romper nada si una falla.
  @override
  Future<Map<String, int>> sharedRootCounts(List<SharedRoot> entries) async {
    final nested = entries.where((e) => e.real.length > 1).toList();
    if (nested.isEmpty) return const {};
    final out = <String, int>{};
    await Future.wait(
      nested.map((e) async {
        try {
          final items = await listFolderItems(e.real);
          out[e.real.join('/')] = items.length;
        } catch (_) {
          // Sin dato: la tarjeta no muestra conteo (mejor eso que un 0 falso).
        }
      }),
    );
    return out;
  }

  /// CONTENIDO directo de [rel] (carpetas y archivos) consultado al servidor,
  /// SIN mover el estado del drive. Lo usa el selector de fotos del cliente.
  @override
  Future<List<DriveItem>> listFolderItems(List<String> rel) async {
    try {
      // Con el cliente INYECTABLE ([client]), no con `http` global: es el mismo
      // en producción y así las pruebas pueden mirarlo sin tocar la red.
      final r = await client
          .get(_u('/api/drive', {'path': rel.join('/')}), headers: _authHeaders)
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      final raw = (data['folders'] as List?) ?? const [];
      final out = <DriveItem>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final name = e['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        out.add(
          DriveItem(
            name: name,
            isFolder: e['isFolder'] == true,
            modified: e['modified'] == null
                ? null
                : DateTime.tryParse(e['modified'].toString()),
            size: (e['size'] as num?)?.toInt(),
            childCount: (e['childCount'] as num?)?.toInt() ?? 0,
          ),
        );
      }
      return out;
    } catch (e) {
      throw 'No se pudo abrir la carpeta: $e';
    }
  }

  /// El backend no expone carpetas por HTTP para el selector: derivo la lista
  /// navegando con /api/drive de cada subcarpeta visible en la raíz pedida.
  @override
  List<String> listFolders(List<String> rel) {
    // Nota: llamado en diálogos (sin async); hacemos una versión rápida
    // basada en la última respuesta conocida cuando rel == path actual.
    if (rel.join('/') == path.join('/')) {
      return items.where((i) => i.isFolder).map((i) => i.name).toList();
    }
    // Para otras rutas el diálogo navega con openPath, que refresca items.
    return items.where((i) => i.isFolder).map((i) => i.name).toList();
  }

  /// Descarga la selección (1 archivo directo, varios/carpetas como ZIP).
  ///
  /// Va EN STREAMING: [onProgress] recibe los bytes recibidos y el total
  /// (`total = 0` si el servidor no lo anuncia), para que el panel de
  /// transferencias muestre el avance real de la descarga.
  Future<List<int>> downloadZip(
    List<String> names, {
    void Function(int received, int total)? onProgress,
    List<String>? from,
  }) async {
    // [from] = la carpeta de la que salen los nombres (null = la que el drive
    // está mostrando): el selector de fotos navega por su cuenta.
    final req = http.Request('POST', _u('/api/zip'))
      ..headers.addAll({'Content-Type': 'application/json', ..._authHeaders})
      ..body = jsonEncode({'path': (from ?? path).join('/'), 'names': names});

    final client = http.Client();
    try {
      final res = await client.send(req).timeout(const Duration(minutes: 10));
      if (res.statusCode != 200) {
        throw 'Error al generar el ZIP (${res.statusCode})';
      }
      final total = res.contentLength ?? 0;
      final sink = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      return sink.takeBytes();
    } finally {
      client.close();
    }
  }

  /// Descarga el ORIGINAL en paralelo por chunks (HTTP Range) a un archivo
  /// temporal local y devuelve el File — para el visor con zoom nítido.
  /// El archivo queda en caché de disco: reabrir es instantáneo.
  /// Si el servidor no soporta rangos, cae a descarga simple con progreso.
  Future<File> fetchOriginalChunked(
    DriveItem item, {
    void Function(double progress)? onProgress,
    int chunks = 4,

    /// Carpeta donde vive [item] (null = la que el drive muestra ahora). La
    /// usan las pantallas que navegan por su cuenta, como el selector de fotos.
    List<String>? rel,
  }) async {
    final folder = rel ?? path;
    final joined = [...folder, item.name].join('/');
    final url =
        '$base/files/$joined'
        '${_apikeyQuery.isEmpty ? '' : '?$_apikeyQuery'}';
    final relPath = joined;

    // ---- Caché de disco ----
    final cacheDir = Directory(
      [
        Directory.systemTemp.path,
        'hardstreet_cache',
      ].join(Platform.pathSeparator),
    );
    await cacheDir.create(recursive: true);
    final local = File(
      [
        cacheDir.path,
        '${_hash(url)}_${_safeName(item.name)}',
      ].join(Platform.pathSeparator),
    );
    final tmp = File('${local.path}.part');

    // HEAD: tamaño y soporte de rangos (con token: el servidor valida leer)
    final head = await http
        .head(
          _u(
            '/files/$relPath',
            _apikeyQuery.isEmpty ? null : {'apikey': _apikey},
          ),
        )
        .timeout(const Duration(seconds: 10));
    final total = int.tryParse(head.headers['content-length'] ?? '') ?? 0;
    final lastModified = head.headers['last-modified'] ?? '';
    final acceptsRanges =
        (head.headers['accept-ranges'] ?? '').contains('bytes') && total > 0;

    // ¿Ya está en caché y sin cambios en el servidor?
    final lmFile = File('${local.path}.lm');
    if (await local.exists() &&
        await local.length() == total &&
        await lmFile.exists() &&
        await lmFile.readAsString() == lastModified) {
      onProgress?.call(1);
      return local;
    }

    if (!acceptsRanges) {
      await _downloadWhole(url, tmp, total, onProgress);
    } else {
      await _downloadParallel(url, tmp, total, chunks, onProgress);
    }

    final len = await tmp.length();
    if (len != total) {
      throw 'Descarga incompleta ($len de $total bytes)';
    }
    if (await local.exists()) await local.delete();
    await tmp.rename(local.path);
    await lmFile.writeAsString(lastModified);
    onProgress?.call(1);
    return local;
  }

  Future<void> _downloadParallel(
    String url,
    File tmp,
    int total,
    int chunks,
    void Function(double)? onProgress,
  ) async {
    if (await tmp.exists()) await tmp.delete();
    await tmp.create();
    final segLen = total ~/ chunks;
    final client = http.Client();
    final received = List<int>.filled(chunks, 0);
    final pieces = List<Uint8List?>.filled(chunks, null);
    var lastNotify = 0.0;

    void report() {
      final done = received.fold<int>(0, (a, b) => a + b);
      final p = total > 0 ? done / total : 0.0;
      if (p - lastNotify >= 0.01 || p >= 1) {
        lastNotify = p;
        onProgress?.call(p.clamp(0.0, 1.0));
      }
    }

    try {
      await Future.wait(
        List.generate(chunks, (i) async {
          final start = i * segLen;
          final end = i == chunks - 1 ? total - 1 : start + segLen - 1;
          final req = http.Request('GET', Uri.parse(url))
            ..headers['Range'] = 'bytes=$start-$end'
            ..headers.addAll(_authHeaders);
          final resp = await client
              .send(req)
              .timeout(const Duration(minutes: 10));
          if (resp.statusCode != 206) {
            throw 'El servidor no soporta descarga por rangos (HTTP ${resp.statusCode})';
          }
          final builder = BytesBuilder(copy: false);
          await for (final chunk in resp.stream) {
            builder.add(chunk);
            received[i] += chunk.length;
            report();
          }
          pieces[i] = builder.takeBytes();
        }),
      );

      // Ensamblar en orden (escritura local, rápida)
      final raf = await tmp.open(mode: FileMode.write);
      try {
        for (var i = 0; i < chunks; i++) {
          final piece = pieces[i];
          if (piece == null) throw 'Chunk $i vacío';
          await raf.setPosition(startOf(i, segLen, total, chunks));
          await raf.writeFrom(piece);
        }
      } finally {
        await raf.close();
      }
    } finally {
      client.close();
    }
  }

  int startOf(int i, int segLen, int total, int chunks) =>
      i * segLen; // el último cubre el resto; posición = i*segLen

  Future<void> _downloadWhole(
    String url,
    File tmp,
    int total,
    void Function(double)? onProgress,
  ) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url))
        ..headers.addAll(_authHeaders);
      final resp = await client.send(req).timeout(const Duration(minutes: 10));
      if (resp.statusCode != 200) throw 'HTTP ${resp.statusCode}';
      final raf = await tmp.open(mode: FileMode.write);
      var done = 0;
      var lastNotify = 0.0;
      try {
        await for (final chunk in resp.stream) {
          await raf.writeFrom(chunk);
          done += chunk.length;
          final p = total > 0 ? done / total : 0.0;
          if (p - lastNotify >= 0.01 || p >= 1) {
            lastNotify = p;
            onProgress?.call(p.clamp(0.0, 1.0));
          }
        }
      } finally {
        await raf.close();
      }
    } finally {
      client.close();
    }
  }

  String _hash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(36);
  }

  String _safeName(String name) {
    final clean = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return clean.length > 40 ? clean.substring(clean.length - 40) : clean;
  }

  /// Ping manual para el módulo de estatus.
  Future<bool> ping() async {
    try {
      final r = await http
          .get(_u('/api/health'))
          .timeout(const Duration(seconds: 5));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _post(
    String p,
    Map<String, dynamic> body, {
    String method = 'POST',
  }) async {
    // El [method] se respeta DE VERDAD: antes siempre se mandaba POST y las
    // rutas que el servidor expone con otro verbo (PATCH /api/items, el de
    // renombrar) contestaban 404 "Cannot POST /api/items". Por eso renombrar
    // no funcionaba en el Drive del servidor.
    final req = http.Request(method, _u(p))
      ..body = jsonEncode(body)
      ..headers.addAll({'Content-Type': 'application/json', ..._authHeaders});
    final r = await http.Response.fromStream(
      await client.send(req).timeout(const Duration(seconds: 30)),
    );
    if (r.statusCode != 200) {
      final msg = (() {
        try {
          return (jsonDecode(r.body) as Map<String, dynamic>)['error']
                  as String? ??
              r.body;
        } catch (_) {
          return r.body;
        }
      })();
      throw msg;
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
}

/// De dónde salen los bytes de un archivo a subir.
///
/// En escritorio basta la RUTA (se lee por partes, sin cargar la foto entera);
/// en el navegador solo existe el `XFile` del selector (un Blob).
class _UploadSource {
  const _UploadSource({this.path, this.file});

  final String? path;
  final XFile? file;

  /// Bytes del rango [start, end): un trozo de la foto, no toda.
  Future<Uint8List> readRange(int start, int end) async {
    final bytes = BytesBuilder(copy: false);
    final stream = file != null
        ? file!.openRead(start, end)
        : File(path!).openRead(start, end);
    await for (final part in stream) {
      bytes.add(part);
    }
    return bytes.takeBytes();
  }
}

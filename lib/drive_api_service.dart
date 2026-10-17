import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'app_constants.dart';
import 'drive_base.dart';
import 'hs_api.dart';

export 'drive_base.dart'
    show
        DriveBase,
        DriveItem,
        driveImagePreview,
        driveRelPath,
        kImageExtensions,
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
  DriveApiService({String? baseUrl}) : base = baseUrl ?? AppConstants.apiBase {
    refresh();
  }

  final String base;

  /// Cliente HTTP de las peticiones JSON del drive. Es INYECTABLE: las pruebas
  /// lo reemplazan por un `MockClient` para no tocar la red (mismo patrón que
  /// `HsApi.client`). Las subidas y las descargas por bloques crean su propio
  /// cliente, así que no pasan por aquí.
  static http.Client client = http.Client();

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
  @override
  String fullSource(DriveItem item, {int? previewWidth}) {
    final q = _apikeyQuery;
    final tail = q.isEmpty ? '' : '&$q';
    if (previewWidth == null) return absolutePathOf(item);
    return '$base/thumb/${[...path, item.name].join('/')}'
        '?w=$previewWidth&q=80$tail';
  }

  /// Miniatura liviana generada por el servidor (JPEG pequeño, con caché).
  @override
  String thumbSource(DriveItem item, {int width = 320}) {
    final q = _apikeyQuery;
    return '$base/thumb/${[...path, item.name].join('/')}'
        '?w=$width${q.isEmpty ? '' : '&$q'}';
  }

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
    // 1. Registrar TODOS los trabajos primero: el panel muestra la lista
    //    completa al 0% desde el primer frame. Todos van en el MISMO lote, que
    //    es el que el panel cuenta ("50/100 fotos").
    final batch = newUploadBatch();
    final pending = <(DriveUploadJob, String, String)>[];
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
      pending.add((job, s, fileName));
    }
    if (pending.isEmpty) return 0;

    // 2. Subir en paralelo con un pool de N trabajadores.
    final client = http.Client();
    var saved = 0;
    var next = 0;
    Future<void> worker() async {
      while (next < pending.length) {
        final (job, s, fileName) = pending[next++];
        // Cancelado mientras esperaba en cola: se salta.
        if (job.cancelled) {
          job.status = 'cancelled';
          job.error = 'Cancelado';
          notifyUploadProgress();
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
                'names': [fileName],
              });
            } catch (_) {
              /* si no existía, sigue */
            }
          }
          await _uploadOne(client, job, s, fileName);
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

  /// Sube un archivo con barra de progreso (stream con contador de bytes).
  Future<void> _uploadOne(
    http.Client client,
    DriveUploadJob job,
    String filePath,
    String fileName,
  ) async {
    final req = http.MultipartRequest('POST', _u('/api/upload'))
      ..headers.addAll(_authHeaders)
      ..fields['path'] = path.join('/')
      ..files.add(
        await http.MultipartFile.fromPath(
          'files',
          filePath,
          filename: fileName,
          contentType: MediaType('image', _mimeSub(extOf(fileName))),
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
        final msg = (() {
          try {
            return (jsonDecode(body) as Map<String, dynamic>)['error']
                    as String? ??
                body;
          } catch (_) {
            return body;
          }
        })();
        throw 'HTTP ${response.statusCode}: $msg';
      }
      await pumping;
    } catch (_) {
      await pumping.catchError((_) {});
      rethrow;
    }
  }

  /// Resubir a mano un archivo que quedó con error (botón "Resubir").
  @override
  Future<void> retryUpload(String jobId) async {
    final job = uploadJobById(jobId);
    if (job == null || job.status == 'uploading') return;
    job.restart();
    job.attempts = 0;
    notifyUploadProgress();
    final client = http.Client();
    try {
      await runUploadWithRetries(
        job,
        () => _uploadOne(client, job, job.thumb, job.name),
      );
    } finally {
      client.close();
      await refresh();
    }
  }

  String _mimeSub(String ext) => switch (ext) {
    '.png' => 'png',
    '.gif' => 'gif',
    '.webp' => 'webp',
    '.bmp' => 'bmp',
    _ => 'jpeg',
  };

  @override
  Future<void> createFolder(String name) async {
    await _post('/api/folders', {'path': path.join('/'), 'name': name});
    await refresh();
  }

  @override
  Future<void> rename(DriveItem item, String newName) async {
    await _post('/api/items', {
      'path': path.join('/'),
      'name': item.name,
      'newName': newName,
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
    await Future.wait(nested.map((e) async {
      try {
        final items = await listFolderItems(e.real);
        out[e.real.join('/')] = items.length;
      } catch (_) {
        // Sin dato: la tarjeta no muestra conteo (mejor eso que un 0 falso).
      }
    }));
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
  }) async {
    final url = absolutePathOf(item);
    final rel = [...path, item.name].join('/');

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
          _u('/files/$rel', _apikeyQuery.isEmpty ? null : {'apikey': _apikey}),
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
    final r = await http
        .post(
          _u(p),
          body: jsonEncode(body),
          headers: {'Content-Type': 'application/json', ..._authHeaders},
        )
        .timeout(const Duration(seconds: 30));
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

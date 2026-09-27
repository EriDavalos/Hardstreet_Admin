import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'drive_base.dart';

export 'drive_base.dart'
    show DriveItem, kImageExtensions, DriveConn, DriveBusy, DriveUploadJob;

/// Cliente del drive remoto (Node/Express en 192.168.1.72:4000).
/// Mantiene la MISMA interfaz que [DriveService] para que la UI no cambie.
class DriveApiService extends DriveBase {
  DriveApiService({String? baseUrl})
    : base =
          baseUrl ??
          const String.fromEnvironment(
            'DRIVE_API',
            defaultValue: 'http://oriongo.ddns.net:4000',
          ) {
    refresh();
  }

  final String base;

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
  @override
  String absolutePathOf(DriveItem item) =>
      '$base/files/${[...path, item.name].join('/')}';

  /// Versión PREVIEW para el visor: 1600px (~400-800 KB en vez de 10 MB).
  @override
  String fullSource(DriveItem item, {int? previewWidth}) {
    if (previewWidth == null) return absolutePathOf(item);
    return '$base/thumb/${[...path, item.name].join('/')}'
        '?w=$previewWidth&q=80';
  }

  /// Miniatura liviana generada por el servidor (JPEG pequeño, con caché).
  @override
  String thumbSource(DriveItem item, {int width = 320}) =>
      '$base/thumb/${[...path, item.name].join('/')}?w=$width';

  @override
  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final r = await http
          .get(_u('/api/drive', {'path': path.join('/')}))
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
      updateItems([...folders, ...files]);
      conn = DriveConn.online;
    } catch (e) {
      error = 'No se pudo conectar con el servidor ($base): $e';
      conn = DriveConn.offline;
      updateItems(const []);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Sube cada archivo en su propia petición con progreso REAL por bytes.
  /// NO bloquea la UI: cada trabajo vive en [uploadJobs] (panel estilo Drive).
  @override
  Future<int> uploadFromPaths(List<String> sources) async {
    if (sources.isEmpty) return 0;
    var saved = 0;
    final client = http.Client();
    try {
      for (final s in sources) {
        final f = File(s);
        if (!f.existsSync()) continue;
        // Acepta rutas con / o \ mezclados (drop externo, file_selector…).
        final fileName = s.split(RegExp(r'[\\/]')).last;
        final job = DriveUploadJob(
          id: '$s-${DateTime.now().microsecondsSinceEpoch}',
          name: fileName,
          thumb: s, // miniatura del archivo LOCAL mientras sube
          total: f.lengthSync(),
        );
        addUploadJob(job);
        try {
          await _uploadOne(client, job, s, fileName);
          finishUploadJob(job);
          saved++;
        } catch (e) {
          finishUploadJob(job, error: e.toString());
        }
      }
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
          job.sent += chunk.length;
          notifyUploadProgress();
          sink.add(chunk);
        },
      ),
    );

    final streamed = http.StreamedRequest(req.method, req.url)
      ..headers.addAll(req.headers);
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
  Future<List<int>> downloadZip(List<String> names) {
    return runBusy(DriveBusy.downloading, 'Preparando descarga…', () async {
      final r = await http
          .post(
            _u('/api/zip'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'path': path.join('/'), 'names': names}),
          )
          .timeout(const Duration(minutes: 5));
      if (r.statusCode != 200)
        throw 'Error al generar el ZIP (${r.statusCode})';
      return r.bodyBytes;
    });
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

    // HEAD: tamaño y soporte de rangos
    final head = await http
        .head(_u('/files/$rel'))
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
            ..headers['Range'] = 'bytes=$start-$end';
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
      final req = http.Request('GET', Uri.parse(url));
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
          headers: {'Content-Type': 'application/json'},
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

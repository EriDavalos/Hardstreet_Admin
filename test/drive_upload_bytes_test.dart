import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/drive_api_service.dart';
import 'package:hardstreet_admin/hs_api.dart';

/// Subidas del Drive con el SELECTOR de archivos.
///
/// En el navegador un `XFile` NO tiene ruta en el disco: su `path` es una URL
/// de Blob y `dart:io` revienta al tocarla (el usuario veía
/// "Unsupported operation: _Namespace"). Por eso la subida del selector va por
/// BYTES, y las fotos grandes van EN TROZOS: un solo cuerpo de decenas de MB lo
/// rechaza el proxy del servidor con 413 (una página HTML "Request Entity Too
/// Large") y, si se corta a mitad, había que empezar la foto entera otra vez.
http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

/// Deja las subidas apuntando al cliente de prueba (en la app abren su propio
/// cliente HTTP, que sin esto saldría a la red de verdad).
void _mockUploads(MockClient mock) {
  DriveApiService.client = mock;
  DriveApiService.uploadClientFactory = () => mock;
}

void main() {
  setUp(() => HsSession.token = 'tok-test');

  tearDown(() {
    DriveApiService.client = http.Client();
    DriveApiService.uploadClientFactory = () => http.Client();
    DriveApiService.chunkThreshold = 4 * 1024 * 1024;
    DriveApiService.chunkSize = 4 * 1024 * 1024;
    HsSession.clear();
  });

  test('la foto del selector se sube por BYTES (sin tocar el disco)', () async {
    final uploads = <http.Request>[];
    _mockUploads(MockClient((r) async {
      if (r.url.path.endsWith('/api/drive')) {
        return _json({'folders': [], 'files': []});
      }
      uploads.add(r);
      return _json({'saved': 1, 'names': ['foto.jpg']});
    }));
    final drive = DriveApiService(baseUrl: 'http://drive.test');
    final bytes = Uint8List.fromList(List<int>.filled(64, 7));
    // La "ruta" NO existe en el disco (en el navegador es una URL de Blob):
    // los bytes del XFile son lo único que se puede mandar.
    final file = XFile.fromData(
      bytes,
      name: 'foto.jpg',
      path: 'no-existe/foto.jpg',
      mimeType: 'image/jpeg',
      length: bytes.length,
    );

    final saved = await drive.uploadFromFiles([file]);

    expect(saved, 1);
    final up = uploads.singleWhere((r) => r.url.path.endsWith('/api/upload'));
    expect(
      up.headers['Content-Type'],
      startsWith('multipart/form-data'),
      reason: 'sigue siendo la subida multipart de siempre',
    );
    expect(
      up.bodyBytes.length,
      greaterThan(bytes.length),
      reason: 'el cuerpo lleva los bytes de la foto (más el formulario)',
    );
    // El panel muestra el trabajo con su nombre.
    expect(drive.uploadJobs.single.name, 'foto.jpg');
    expect(drive.uploadJobs.single.status, 'done');
  });

  test('una foto GRANDE viaja en TROZOS y el servidor la arma', () async {
    DriveApiService.chunkThreshold = 8;
    DriveApiService.chunkSize = 4;
    final chunks = <int, List<int>>{};
    var finished = false;
    _mockUploads(MockClient((r) async {
      if (r.url.path.endsWith('/api/drive')) {
        return _json({'folders': [], 'files': []});
      }
      if (r.url.path.endsWith('/api/upload/chunk')) {
        chunks[int.parse(r.url.queryParameters['index']!)] = r.bodyBytes;
        return _json({'received': chunks.length, 'total': 3});
      }
      if (r.url.path.endsWith('/api/upload/finish')) {
        finished = true;
        return _json({'saved': 1, 'names': ['grande.jpg'], 'size': 10});
      }
      fail('petición inesperada: ${r.url}');
    }));
    final drive = DriveApiService(baseUrl: 'http://drive.test');
    final data = List<int>.generate(10, (i) => i + 1);
    final file = XFile.fromData(
      Uint8List.fromList(data),
      name: 'grande.jpg',
      path: 'no-existe/grande.jpg',
      length: data.length,
    );

    final saved = await drive.uploadFromFiles([file]);

    expect(saved, 1);
    expect(chunks.keys.toList()..sort(), [0, 1, 2]);
    expect(
      [for (final i in [0, 1, 2]) ...chunks[i]!],
      data,
      reason: 'los trozos juntos son la foto original, en orden',
    );
    expect(finished, isTrue, reason: 'el último paso arma la foto');
    expect(drive.uploadJobs.single.sent, 10,
        reason: 'el progreso termina en el 100% del archivo');
  });

  test('si el proxy rechaza el trozo (413), la subida se rehace más chica',
      () async {
    DriveApiService.chunkThreshold = 8;
    DriveApiService.chunkSize = 8;
    final sizes = <int>[];
    final pieces = <int>[];
    var finished = false;
    _mockUploads(MockClient((r) async {
      if (r.url.path.endsWith('/api/drive')) {
        return _json({'folders': [], 'files': []});
      }
      if (r.url.path.endsWith('/api/upload/chunk')) {
        sizes.add(r.bodyBytes.length);
        pieces.add(int.parse(r.url.queryParameters['index']!));
        // El proxy solo acepta cuerpos de 2 bytes (nginx de mentira).
        if (r.bodyBytes.length > 2) {
          return http.Response('<html>413 Request Entity Too Large</html>', 413);
        }
        return _json({'received': pieces.length, 'total': 0});
      }
      if (r.url.path.endsWith('/api/upload/finish')) {
        finished = true;
        return _json({'saved': 1, 'names': ['grande.jpg'], 'size': 12});
      }
      fail('petición inesperada: ${r.url}');
    }));
    final drive = DriveApiService(baseUrl: 'http://drive.test');
    final data = List<int>.generate(12, (i) => i);
    final file = XFile.fromData(
      Uint8List.fromList(data),
      name: 'grande.jpg',
      path: 'no-existe/grande.jpg',
      length: data.length,
    );

    final saved = await drive.uploadFromFiles([file]);

    expect(saved, 1, reason: 'la foto termina subiendo');
    expect(sizes.last, 2, reason: 'los trozos que pasan son los chicos');
    expect(finished, isTrue, reason: 'el servidor la arma al final');
    expect(drive.uploadJobs.single.sent, 12);
  });

  test('si el proxy rechaza la foto "pequeña" (413), se rehace EN TROZOS',
      () async {
    // El límite del proxy puede ser MÁS bajo que el umbral de la app: una foto
    // de 40 bytes en una sola petición recibía la página HTML del 413 y, tras
    // tres intentos idénticos, quedaba en error (aunque las grandes subían
    // bien por ir troceadas). Ahora el 413 lleva la foto al camino troceado.
    final whole = <http.Request>[];
    var chunks = 0;
    var finished = false;
    _mockUploads(MockClient((r) async {
      if (r.url.path.endsWith('/api/drive')) {
        return _json({'folders': [], 'files': []});
      }
      if (r.url.path.endsWith('/api/upload')) {
        whole.add(r);
        return http.Response(
          '<html><head><title>413 Request Entity Too Large</title></head></html>',
          413,
        );
      }
      if (r.url.path.endsWith('/api/upload/chunk')) {
        chunks++;
        return _json({'received': chunks, 'total': 1});
      }
      if (r.url.path.endsWith('/api/upload/finish')) {
        finished = true;
        return _json({'saved': 1, 'names': ['pequena.jpg'], 'size': 40});
      }
      fail('petición inesperada: ${r.url}');
    }));
    final drive = DriveApiService(baseUrl: 'http://drive.test');
    final bytes = Uint8List.fromList(List<int>.filled(40, 5));
    final file = XFile.fromData(
      bytes,
      name: 'pequena.jpg',
      path: 'no-existe/pequena.jpg',
      length: bytes.length,
    );

    final saved = await drive.uploadFromFiles([file]);

    expect(saved, 1, reason: 'la foto termina guardada');
    expect(whole, hasLength(1),
        reason: 'un solo intento entero, no los tres reintentos a ciegas');
    expect(chunks, 1, reason: 'la foto se rehace en trozos');
    expect(finished, isTrue, reason: 'el servidor la arma al final');
    expect(drive.uploadJobs.single.status, 'done');
    expect(drive.uploadJobs.single.sent, 40);
  });

  test('una página HTML del proxy (502) también lleva la foto a trozos',
      () async {
    // El cuerpo HTML no lo escribe el drive: es el proxy. Si cortó la petición
    // entera, la foto va en trozos (así también se cubre el wifi con login o el
    // túnel que devuelven su propia página en vez de un 413 limpio).
    var chunks = 0;
    var finished = false;
    _mockUploads(MockClient((r) async {
      if (r.url.path.endsWith('/api/drive')) {
        return _json({'folders': [], 'files': []});
      }
      if (r.url.path.endsWith('/api/upload')) {
        return http.Response(
          '<html><body>502 Bad Gateway</body></html>',
          502,
        );
      }
      if (r.url.path.endsWith('/api/upload/chunk')) {
        chunks++;
        return _json({'received': chunks, 'total': 1});
      }
      if (r.url.path.endsWith('/api/upload/finish')) {
        finished = true;
        return _json({'saved': 1, 'names': ['foto.jpg'], 'size': 9});
      }
      fail('petición inesperada: ${r.url}');
    }));
    final drive = DriveApiService(baseUrl: 'http://drive.test');
    final file = XFile.fromData(
      Uint8List.fromList(List<int>.filled(9, 1)),
      name: 'foto.jpg',
      path: 'no-existe/foto.jpg',
      length: 9,
    );

    final saved = await drive.uploadFromFiles([file]);

    expect(saved, 1);
    expect(chunks, 1);
    expect(finished, isTrue);
    expect(drive.uploadJobs.single.status, 'done');
  });

  test('un formato que el Drive no guarda falla al instante y con motivo',
      () async {
    final tried = <Uri>[];
    _mockUploads(MockClient((r) async {
      if (r.url.path.contains('/api/upload')) tried.add(r.url);
      return _json({'folders': [], 'files': []});
    }));
    final drive = DriveApiService(baseUrl: 'http://drive.test');
    final file = XFile.fromData(
      Uint8List.fromList([1, 2, 3]),
      name: 'contrato.pdf',
      path: 'no-existe/contrato.pdf',
      length: 3,
    );

    final saved = await drive.uploadFromFiles([file]);

    expect(saved, 0);
    final job = drive.uploadJobs.single;
    expect(job.status, 'error');
    expect(job.error, contains('Formato no admitido'),
        reason: 'el panel dice QUÉ formatos sí se admiten');
    expect(tried, isEmpty, reason: 'ni un byte al servidor');
  });

  test('resubir una foto del selector NO pide volver a elegirla', () async {
    var fails = 0;
    _mockUploads(MockClient((r) async {
      if (r.url.path.endsWith('/api/drive')) {
        return _json({'folders': [], 'files': []});
      }
      // La primera subida se cae (red/servidor); el reintento debe funcionar
      // con los mismos bytes que el usuario ya eligió.
      if (!r.url.path.endsWith('/api/upload')) {
        return _json({'saved': 0, 'names': []});
      }
      // Se caen los 3 intentos automáticos (kUploadAttempts): la foto queda
      // en error hasta que el usuario pulsa "Resubir".
      if (fails++ < 3) return http.Response('boom', 500);
      return _json({'saved': 1, 'names': ['foto.jpg']});
    }));
    final drive = DriveApiService(baseUrl: 'http://drive.test');
    final file = XFile.fromData(
      Uint8List.fromList(List<int>.filled(16, 3)),
      name: 'foto.jpg',
      path: 'no-existe/foto.jpg',
      length: 16,
    );

    // Los 3 intentos automáticos se caen: el trabajo queda en error.
    final saved = await drive.uploadFromFiles([file]);
    expect(saved, 0);
    final job = drive.uploadJobs.single;
    expect(job.status, 'error');

    // "Resubir" (el botón del panel) NO pide volver a elegir la foto: sube con
    // los mismos bytes que el usuario ya eligió.
    await drive.retryUpload(job.id);
    expect(job.status, 'done');
    expect(job.sent, 16);
  });
}

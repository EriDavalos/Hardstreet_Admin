import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/app_updater.dart';

/// NOTA: estas pruebas usan `test()` plano (NO `testWidgets`): el binding de
/// widgets intercepta TODO HttpClient y responde 400, lo que impide probar
/// la descarga real contra un servidor local.
void main() {
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('hardstreet_dl_test');
  });

  tearDownAll(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('Descarga real: progreso por chunks y archivo guardado', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final payload = List<int>.filled(4096, 42);
    server.listen((req) async {
      req.response.contentLength = payload.length;
      req.response.add(payload.sublist(0, 1024));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      req.response.add(payload.sublist(1024));
      await req.response.close();
    });
    addTearDown(() => server.close(force: true));

    final events = <(int, int)>[];
    final url =
        'http://127.0.0.1:${server.port}/downloads/desktop/app-release.exe';

    final file = await AppUpdater.download(
      url,
      onProgress: (received, total) => events.add((received, total)),
    );

    // El archivo final existe (sin .part) y tiene todo el contenido.
    expect(file.existsSync(), isTrue);
    expect(file.path.endsWith('.part'), isFalse);
    expect(await file.length(), payload.length);
    expect(
      await file.readAsBytes(),
      payload,
      reason: 'el contenido descargado debe coincidir byte a byte',
    );

    // El progreso informó el total y terminó completo.
    expect(events, isNotEmpty);
    expect(events.last.$1, payload.length);
    expect(events.last.$2, payload.length);
    // Los recibidos son monótonos crecientes.
    for (var i = 1; i < events.length; i++) {
      expect(events[i].$1 >= events[i - 1].$1, isTrue);
    }

    await file.delete();
  });

  test('Descarga real: HTTP != 200 lanza AppUpdateException', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      req.response.statusCode = 404;
      req.response.write('no existe');
      req.response.close();
    });
    addTearDown(() => server.close(force: true));

    await expectLater(
      AppUpdater.download(
        'http://127.0.0.1:${server.port}/faltante.exe',
        onProgress: (_, _) {},
      ),
      throwsA(isA<AppUpdateException>()),
    );
  });

  test('Descarga real: cancelar a mitad borra el .part', () async {
    // El servidor responde 200 con cuerpo largo pero NO lo termina nunca
    // (simula una descarga en curso). La cancelación se dispara por tiempo:
    // en loopback de Windows dart:io no entrega chunks incrementales hasta
    // cerrar la respuesta, así que no se puede esperar progreso real aquí.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      req.response.contentLength = 8192;
      req.response.add(List<int>.filled(1024, 1));
      // El cuerpo queda abierto: la app decide cancelar después.
    });
    addTearDown(() => server.close(force: true));

    final url = 'http://127.0.0.1:${server.port}/cancelable.exe';
    final future = AppUpdater.download(url, onProgress: (_, _) {});

    // Espera a que la descarga esté en curso y cancela.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    AppUpdater.cancelDownload();

    await expectLater(future, throwsA(isA<AppUpdateCancelled>()));

    // No debe quedar ni el .part ni el archivo final.
    final dir = await AppUpdater.updatesDir();
    expect(
      dir.listSync().whereType<File>().where(
        (f) => f.path.contains('cancelable'),
      ),
      isEmpty,
      reason: 'la cancelación debe limpiar el .part',
    );
  });

  test('Direcciones de respaldo: el enlace propio gana el HTTP del hub', () {
    final urls = AppUpdater.downloadCandidates(
      'https://oriongo.ddns.net/downloads/android/app-release.apk',
    );
    expect(
      urls.first,
      'https://oriongo.ddns.net/downloads/android/app-release.apk',
    );
    expect(
      urls,
      contains(
        'http://oriongo.ddns.net:4100/downloads/android/app-release.apk',
      ),
      reason: 'el hub sirve el mismo archivo por HTTP en el puerto 4100',
    );
    expect(
      urls,
      contains('http://192.168.1.72:4100/downloads/android/app-release.apk'),
      reason: 'la IP local sirve cuando el router no devuelve la conexión',
    );
  });

  test('Direcciones de respaldo: un enlace externo se respeta tal cual', () {
    expect(AppUpdater.downloadCandidates('https://ejemplo.com/x/app.apk'), [
      'https://ejemplo.com/x/app.apk',
    ]);
    // Un enlace ya HTTP no tiene nada que reintentar.
    expect(
      AppUpdater.downloadCandidates('http://oriongo.ddns.net:4100/x.apk'),
      ['http://oriongo.ddns.net:4100/x.apk'],
    );
  });

  test(
    'Descarga real: si el TLS falla, reintenta por la dirección dada',
    () async {
      // Servidor HTTP PLANO: un intento por https contra él muere en el
      // handshake (HandshakeException), igual que en el teléfono con un
      // certificado que no se puede verificar.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final payload = List<int>.filled(2048, 7);
      server.listen((req) async {
        req.response.contentLength = payload.length;
        req.response.add(payload);
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final file = await AppUpdater.download(
        'https://127.0.0.1:${server.port}/downloads/android/app-release.apk',
        fileName: 'respaldo.apk',
        onProgress: (_, _) {},
        fallbackUrls: [
          'http://127.0.0.1:${server.port}/downloads/android/app-release.apk',
        ],
      );

      expect(await file.length(), payload.length);
      await file.delete();
    },
  );

  test(
    'Descarga real: TLS fallido sin respaldo explica el certificado',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response.write('ok');
        req.response.close();
      });
      addTearDown(() => server.close(force: true));

      await expectLater(
        AppUpdater.download(
          'https://127.0.0.1:${server.port}/x.apk',
          onProgress: (_, _) {},
        ),
        throwsA(
          isA<AppUpdateException>().having(
            (e) => e.message,
            'mensaje',
            contains('certificado'),
          ),
        ),
      );
    },
  );
}

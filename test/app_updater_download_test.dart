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
    final future = AppUpdater.download(
      url,
      onProgress: (_, _) {},
    );

    // Espera a que la descarga esté en curso y cancela.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    AppUpdater.cancelDownload();

    await expectLater(future, throwsA(isA<AppUpdateCancelled>()));

    // No debe quedar ni el .part ni el archivo final.
    final dir = await AppUpdater.updatesDir();
    expect(
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('cancelable')),
      isEmpty,
      reason: 'la cancelación debe limpiar el .part',
    );
  });
}

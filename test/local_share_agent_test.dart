import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/app_settings.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/local_share_agent.dart';

/// El AGENTE de carpetas compartidas: es lo que hace que una carpeta de ESTA
/// computadora (p. ej. C:\Fotos) se pueda ver desde otros usuarios, sin abrir
/// puertos: la app pregunta al servidor si hay trabajo y contesta leyendo su
/// propio disco.
///
/// Aquí se verifica lo que puede salir mal de verdad:
///   * que NUNCA se sirva nada fuera de la carpeta compartida;
///   * que el listado y los archivos se armen como los espera el servidor;
///   * que el ciclo completo (pedir → contestar → volver a pedir) funcione.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('hs_share_');
    Directory('${tmp.path}/Bodas').createSync();
    File('${tmp.path}/Foto.JPG').writeAsBytesSync(List<int>.filled(8, 7));
    File('${tmp.path}/nota.txt').writeAsStringSync('no es imagen');
    File('${tmp.path}/.oculto.jpg').writeAsBytesSync(const [1]);
    Directory('${tmp.path}/Bodas/2026').createSync();
  });

  tearDown(() async {
    LocalShareAgent.instance.stop();
    // El switch es una PREFERENCIA persistente: cada prueba la deja apagada.
    await LocalShareAgent.instance.setManual(false);
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// El servidor no contesta (nunca): así el agente queda esperando y la prueba
  /// mira sólo el encendido/apagado del servicio, sin hablar con nadie.
  void parkAgent() {
    LocalShareAgent.instance.client = MockClient(
        (_) => Completer<http.Response>().future);
    LocalShareAgent.instance.retryDelay = const Duration(seconds: 5);
  }

  test('el switch enciende el servicio y lo deja encendido al reabrir la app',
      () async {
    final agent = LocalShareAgent.instance;
    parkAgent();

    expect(agent.serving.value, isFalse);
    expect(agent.manualOn, isFalse);

    // Encendido a mano: queda sirviendo (no sólo mientras haya una carpeta a
    // la vista) y se recuerda para la próxima vez.
    await agent.setManual(true);
    expect(agent.running, isTrue);
    expect(agent.serving.value, isTrue);
    expect(agent.manualOn, isTrue);
    expect(AppSettings.instance.shareServing, isTrue);

    // Y en la siguiente apertura, con esa preferencia, arranca solo.
    agent.stop();
    expect(agent.serving.value, isFalse);
    expect(agent.loadManualPreference(), isTrue);
    expect(agent.running, isTrue);
    expect(agent.serving.value, isTrue);

    // Apagado a mano: deja de servir y se recuerda apagado.
    await agent.setManual(false);
    expect(agent.running, isFalse);
    expect(agent.serving.value, isFalse);
    expect(agent.manualOn, isFalse);
    expect(AppSettings.instance.shareServing, isFalse);
  });

  test('encendido a mano NO se apaga aunque no queden carpetas compartidas',
      () async {
    final agent = LocalShareAgent.instance;
    parkAgent();
    await agent.setManual(true);

    // El servidor dice que este usuario no comparte ninguna carpeta de su
    // computadora: antes eso apagaba el agente; con el switch encendido, no.
    HsApi.client = MockClient((request) async => http.Response(
          jsonEncode({'ok': true, 'item': {'shared': [], 'received': []}}),
          200,
          headers: {'content-type': 'application/json'},
        ));
    await agent.syncWithShares();

    expect(agent.running, isTrue, reason: 'el switch manda');
    expect(agent.serving.value, isTrue);
  });

  test('nunca se sale de la carpeta compartida', () {
    final agent = LocalShareAgent.instance;
    final root = tmp.path.replaceAll('\\', '/');

    // Dentro: vale (y se normaliza con '/').
    expect(agent.resolveInside(root, 'Bodas/2026'), '$root/Bodas/2026');
    expect(agent.resolveInside(root, ''), root);

    // Escapes: NADA de subir de nivel, cambiar de unidad ni rutas clavadas.
    expect(() => agent.resolveInside(root, '../secreto'),
        throwsA(isA<StateError>()));
    expect(() => agent.resolveInside(root, 'Bodas/../../otro'),
        throwsA(isA<StateError>()));
    expect(() => agent.resolveInside(root, 'C:/Windows'),
        throwsA(isA<StateError>()));
    expect(() => agent.resolveInside(root, '/etc/passwd'),
        throwsA(isA<StateError>()));
    expect(() => agent.resolveInside('', 'algo'),
        throwsA(isA<StateError>()));
  });

  test('el listado trae carpetas e imágenes (y salta lo oculto)', () async {
    final reply = await LocalShareAgent.instance.describeRequest(
      op: 'list',
      root: tmp.path,
      path: '',
    );

    expect(reply.status, 200);
    final data = jsonDecode(utf8.decode(reply.bytes)) as Map<String, dynamic>;
    final items = (data['folders'] as List).cast<Map<String, dynamic>>();
    final names = items.map((e) => e['name']).toList();

    expect(names, contains('Bodas'));
    expect(names, contains('Foto.JPG'));
    expect(names, isNot(contains('nota.txt')),
        reason: 'solo imágenes, igual que el drive');
    expect(names, isNot(contains('.oculto.jpg')));

    final folder = items.firstWhere((e) => e['name'] == 'Bodas');
    expect(folder['isFolder'], isTrue);
    expect(folder['childCount'], 1, reason: 'el servidor lo usa en las tarjetas');
    final image = items.firstWhere((e) => e['name'] == 'Foto.JPG');
    expect(image['isFolder'], isFalse);
    expect(image['size'], 8);
    expect(image['modified'], isA<int>());
  });

  test('un archivo se sirve con sus bytes y su tipo', () async {
    final reply = await LocalShareAgent.instance.describeRequest(
      op: 'file',
      root: tmp.path,
      path: 'Foto.JPG',
    );
    expect(reply.status, 200);
    expect(reply.name, 'Foto.JPG');
    expect(reply.mime, 'image/jpeg');
    expect(reply.bytes.length, 8);
  });

  test('lo que ya no existe se explica y lo desconocido se rechaza', () async {
    final gone = await LocalShareAgent.instance
        .describeRequest(op: 'file', root: tmp.path, path: 'no-esta.jpg');
    expect(gone.status, 404);
    expect(gone.error, isNotEmpty);
    expect(gone.bytes, isEmpty);

    final bad = await LocalShareAgent.instance
        .describeRequest(op: 'borrar', root: tmp.path, path: 'Foto.JPG');
    expect(bad.status, 400, reason: 'el agente es de SOLO LECTURA');
  });

  test('ciclo completo: pide trabajo, contesta y vuelve a pedir', () async {
    final waited = <String>[];
    final replies = <http.Request>[];
    final agent = LocalShareAgent.instance;
    agent.retryDelay = const Duration(milliseconds: 10);

    agent.client = MockClient((request) async {
      if (request.url.path.endsWith('/api/local/agent/wait')) {
        waited.add(request.url.path);
        if (waited.length > 1) {
          // La sesión dejó de servir: el agente se detiene solo.
          return http.Response('{}', 401);
        }
        return http.Response(
          jsonEncode({
            'request': {
              'id': 'a1',
              'op': 'list',
              'root': tmp.path.replaceAll('\\', '/'),
              'path': '',
            }
          }),
          200,
        );
      }
      replies.add(request);
      expect(request.headers['Content-Type'], 'application/octet-stream',
          reason: 'el cuerpo viaja crudo, sin base64');
      final data = jsonDecode(utf8.decode(request.bodyBytes));
      expect((data['folders'] as List).map((e) => e['name']),
          contains('Foto.JPG'));
      return http.Response('{"ok":true}', 200);
    });

    agent.start();
    expect(agent.running, isTrue);

    // Se espera a que conteste (y a que se detenga al recibir el 401).
    for (var i = 0; i < 200 && agent.served == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(agent.served, 1);
    expect(replies, hasLength(1));
    expect(replies.single.url.path, endsWith('/api/local/agent/reply'));
    expect(replies.single.url.queryParameters['id'], 'a1');
    expect(replies.single.url.queryParameters['status'], '200');
    expect(agent.running, isFalse, reason: 'con 401 no sigue preguntando');
  });
}

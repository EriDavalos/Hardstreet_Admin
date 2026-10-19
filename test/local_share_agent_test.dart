import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  test('el listado trae TODO lo que hay: carpetas, fotos, vídeos y texto',
      () async {
    // Un vídeo en la carpeta del dueño: antes NO aparecía (el listado solo
    // servía imágenes) y por eso era imposible verlo desde el panel.
    File('${tmp.path}/clip.mp4').writeAsBytesSync(List<int>.filled(16, 1));

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
    expect(names, contains('nota.txt'), reason: 'el Drive ya no es solo fotos');
    expect(names, contains('clip.mp4'));
    expect(names, isNot(contains('.oculto.jpg')));

    final folder = items.firstWhere((e) => e['name'] == 'Bodas');
    expect(folder['isFolder'], isTrue);
    expect(folder['childCount'], 1, reason: 'el servidor lo usa en las tarjetas');
    final image = items.firstWhere((e) => e['name'] == 'Foto.JPG');
    expect(image['isFolder'], isFalse);
    expect(image['size'], 8);
    expect(image['modified'], isA<int>());
    expect(image['kind'], 'image');
    // El TIPO viaja con cada archivo: con él el panel pinta el icono y elige
    // el visor (reproductor para el vídeo, lectura para el texto).
    expect(items.firstWhere((e) => e['name'] == 'clip.mp4')['kind'], 'video');
    expect(items.firstWhere((e) => e['name'] == 'nota.txt')['kind'], 'text');
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

  test('un vídeo se sirve con el tipo que el reproductor necesita', () async {
    // `video/mp4` (y no el genérico) es lo que hace que el reproductor del
    // panel arranque en vez de quedarse en negro.
    File('${tmp.path}/clip.mp4').writeAsBytesSync(const [0, 1, 2, 3]);

    final reply = await LocalShareAgent.instance.describeRequest(
      op: 'file',
      root: tmp.path,
      path: 'clip.mp4',
    );

    expect(reply.status, 200);
    expect(reply.mime, 'video/mp4');
    expect(reply.bytes.length, 4);
  });

  test('la MINIATURA se reduce ANTES de mandarla (no sube el original)', () async {
    // Una foto de verdad (PNG 8x8 de un color) para poder reducirla: el
    // agente manda píxeles crudos y el servidor arma el JPEG.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAACXBIWXMAAAPoAAAD6AG1e1JrAAAA'
      'EUlEQVR4nGM4oaGBFTEMLQkAgl1GAWqNFmsAAAAASUVORK5CYII=',
    );
    File('${tmp.path}/chica.png').writeAsBytesSync(png);

    final reply = await LocalShareAgent.instance.describeRequest(
      op: 'thumb',
      root: tmp.path,
      path: 'chica.png',
      width: 4,
    );

    expect(reply.status, 200);
    expect(reply.mime, AgentReply.rawMime, reason: 'van píxeles, no el JPEG');
    expect(reply.isRawRgba, isTrue);
    expect(reply.rawWidth, 4, reason: 'se reduce al ancho pedido');
    expect(reply.rawHeight, 4, reason: 'mantiene la proporción');
    expect(
      reply.bytes.length,
      reply.rawWidth * reply.rawHeight * 4,
      reason: 'RGBA: 4 bytes por píxel',
    );

    // Si no se puede reducir (no es una imagen), se manda el original y el
    // servidor se encarga: nunca se queda sin respuesta.
    final txt = await LocalShareAgent.instance.describeRequest(
      op: 'thumb',
      root: tmp.path,
      path: 'nota.txt',
      width: 4,
    );
    expect(txt.status, 200);
    expect(txt.isRawRgba, isFalse);
    expect(txt.bytes, isNotEmpty);
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
          // El servidor del drive no reconoce la sesión.
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

    // Se espera a que conteste y a que el 401 quede EXPLICADO.
    for (var i = 0; i < 200 && agent.served == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    for (var i = 0;
        i < 200 && agent.problem.value != ShareProblem.session;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(agent.served, 1);
    expect(replies, hasLength(1));
    expect(replies.single.url.path, endsWith('/api/local/agent/reply'));
    expect(replies.single.url.queryParameters['id'], 'a1');
    expect(replies.single.url.queryParameters['status'], '200');

    // Un 401 NO apaga el servicio: el switch se queda donde el usuario lo
    // puso y la tarjeta explica el motivo (antes se apagaba solo y parecía
    // que el switch no obedecía).
    expect(agent.problem.value, ShareProblem.session);
    expect(agent.running, isTrue);
    expect(agent.serving.value, isTrue);

    // Y no es un bucle apretado: entre reintentos hay una espera.
    final before = waited.length;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(waited.length - before, lessThan(20),
        reason: 'espera entre reintentos (antes preguntaba sin parar)');

    agent.stop();
    expect(agent.running, isFalse);
    expect(agent.serving.value, isFalse);
    expect(agent.problem.value, isNull, reason: 'apagado a propósito');
  });

  test('un servidor del drive VIEJO se explica y no se golpea sin parar',
      () async {
    final waited = <String>[];
    final agent = LocalShareAgent.instance;
    agent.retryDelay = const Duration(milliseconds: 20);
    // Servidor del drive sin los endpoints del agente.
    agent.client = MockClient((request) async {
      waited.add(request.url.path);
      return http.Response('Not Found', 404);
    });

    agent.start();
    for (var i = 0;
        i < 200 && agent.problem.value != ShareProblem.oldServer;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(agent.problem.value, ShareProblem.oldServer);
    expect(agent.running, isTrue, reason: 'sigue encendido y reintentando');

    final before = waited.length;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(waited.length - before, lessThan(20),
        reason: 'con 404 se espera antes de volver a preguntar');
    agent.stop();
  });

  test('en el navegador/celular el servicio lo DICE en vez de no hacer nada',
      () async {
    final agent = LocalShareAgent.instance;
    agent.debugSupported = false;
    addTearDown(() => agent.debugSupported = null);

    final started = await agent.setManual(true);

    expect(started, isFalse, reason: 'no puede servir carpetas del equipo');
    expect(agent.running, isFalse);
    expect(agent.serving.value, isFalse);
    expect(agent.problem.value, ShareProblem.unsupported);
    expect(agent.manualOn, isFalse);
  });

  test('una respuesta grande viaja en trozos de 512 KB, en orden', () async {
    // El servidor detrás de un proxy corta los cuerpos de más de 1 MB (es el
    // valor de fábrica de Nginx). Por eso la app parte la respuesta: lo que se
    // partía en silencio era justo la miniatura grande, la vista previa y la
    // descarga de más de 1 MB.
    final bytes = Uint8List.fromList(
      List<int>.generate(1200 * 1024 + 31, (i) => i % 251),
    );
    File('${tmp.path}/grande.jpg').writeAsBytesSync(bytes);

    final pieces = LocalShareAgent.replyChunks(bytes, maxBytes: 512 * 1024);
    expect(pieces, hasLength(3));
    expect(pieces[0].length, 512 * 1024);
    expect(pieces[1].length, 512 * 1024);
    expect(pieces[2].length, bytes.length - 2 * 512 * 1024);
    expect(
      pieces.expand((p) => p).toList(),
      bytes.toList(),
      reason: 'los trozos juntos son la respuesta original, sin perder nada',
    );
    expect(
      LocalShareAgent.replyChunks(const []),
      hasLength(1),
      reason: 'una respuesta vacía sigue siendo UNA petición (last=1)',
    );

    // Y el ciclo real: el servidor pide el archivo y la app lo manda por trozos.
    final sent = <http.Request>[];
    final agent = LocalShareAgent.instance;
    agent.retryDelay = const Duration(milliseconds: 10);
    var asked = false;
    agent.client = MockClient((request) async {
      if (request.url.path.endsWith('/api/local/agent/wait')) {
        if (asked) return http.Response('', 204);
        asked = true;
        return http.Response(
          jsonEncode({
            'request': {
              'id': 'a9',
              'op': 'file',
              'root': tmp.path.replaceAll('\\', '/'),
              'path': 'grande.jpg',
            }
          }),
          200,
        );
      }
      sent.add(request);
      return http.Response('{"ok":true}', 200);
    });

    final before = agent.served;
    agent.start();
    for (var i = 0; i < 400 && agent.served == before; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(agent.served, before + 1);
    expect(sent, hasLength(3));
    expect(
      sent.map((r) => r.url.queryParameters['seq']).toList(),
      ['0', '1', '2'],
      reason: 'los trozos van en orden: el servidor los pega en ese orden',
    );
    expect(
      sent.map((r) => r.url.queryParameters['last']).toList(),
      ['0', '0', '1'],
      reason: 'sólo el último cierra la respuesta',
    );
    expect(
      sent.every((r) => r.bodyBytes.length <= 512 * 1024),
      isTrue,
      reason: 'ningún trozo pasa del límite que corta el proxy',
    );
    expect(
      sent.expand((r) => r.bodyBytes).toList(),
      bytes.toList(),
      reason: 'el servidor recibe el archivo completo',
    );
    agent.stop();
  });

  test('si el proxy rechaza un trozo (413), la app lo parte y sigue', () async {
    // Un proxy más estrecho de lo normal: deja pasar 2 KB por petición.
    const limit = 2048;
    final bytes = Uint8List.fromList(
      List<int>.generate(60000, (i) => i % 251),
    );
    File('${tmp.path}/mediana.jpg').writeAsBytesSync(bytes);

    final accepted = <http.Request>[];
    final rejected = <http.Request>[];
    final agent = LocalShareAgent.instance;
    agent.retryDelay = const Duration(milliseconds: 5);
    var asked = false;
    agent.client = MockClient((request) async {
      if (request.url.path.endsWith('/api/local/agent/wait')) {
        if (asked) return http.Response('', 204);
        asked = true;
        return http.Response(
          jsonEncode({
            'request': {
              'id': 'a12',
              'op': 'file',
              'root': tmp.path.replaceAll('\\', '/'),
              'path': 'mediana.jpg',
            }
          }),
          200,
        );
      }
      // El "proxy" no deja pasar nada de más de [limit].
      if (request.bodyBytes.length > limit) {
        rejected.add(request);
        return http.Response('La petición es demasiado grande', 413);
      }
      accepted.add(request);
      return http.Response('{"ok":true}', 200);
    });

    final before = agent.served;
    agent.start();
    for (var i = 0; i < 400 && agent.served == before; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(agent.served, before + 1, reason: 'acaba mandando TODO');
    expect(rejected, isNotEmpty, reason: 'el proxy rechazó trozos grandes');
    expect(
      accepted.every((r) => r.bodyBytes.length <= limit),
      isTrue,
      reason: 'ningún trozo aceptado pasaba del límite',
    );
    // Lo que el servidor recibe, trozo a trozo y en orden, es el archivo.
    expect(accepted.expand((r) => r.bodyBytes).toList(), bytes.toList());
    expect(
      accepted.map((r) => r.url.queryParameters['seq']).toList(),
      List<String>.generate(accepted.length, (i) => '$i'),
      reason: 'los trozos van numerados del 0 en adelante, sin huecos',
    );
    expect(
      accepted.last.url.queryParameters['last'],
      '1',
      reason: 'el último trozo (y sólo él) cierra la respuesta',
    );
    agent.stop();
  });

  test('el 204 sin trabajo no pregunta en bucle apretado', () async {
    final waited = <String>[];
    final agent = LocalShareAgent.instance;
    agent.client = MockClient((request) async {
      waited.add(request.url.path);
      return http.Response('', 204);
    });

    agent.start();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // Con un servidor que contesta 204 al instante, el agente deja respirar
    // (~1 s): en 300 ms solo pudo preguntar una vez, no cientos.
    expect(waited.length, lessThan(4));
    expect(agent.problem.value, isNull);
    agent.stop();
  });
}

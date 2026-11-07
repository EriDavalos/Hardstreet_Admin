import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/drive_api_service.dart';
import 'package:hardstreet_admin/drive_host.dart';
import 'package:hardstreet_admin/hs_api.dart';

/// El Drive tiene que hablar con el HUB, el único que une los servidores.
///
/// En el celular, el nombre público por HTTPS puede contestar UN servidor de
/// archivos: su listado responde 200 y es válido, así que la app nunca daba
/// error y se quedaba con las fotos de ese nodo («37 fotos» en vez de las 70
/// que suma el hub). Ahora, al abrir el Drive, se mira `/api/health`: si no es
/// un hub se prueba la dirección del hub (mismo nombre por HTTP en el 4100 y
/// la IP local) y se cambia a la que sí lo sea.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late http.Client previous;

  setUp(() {
    previous = DriveApiService.client;
    DriveHost.set(null);
    DriveHost.clearFallback();
    HsSession.token = 'tok-de-prueba';
  });

  tearDown(() {
    DriveApiService.client = previous;
    DriveHost.set(null);
    DriveHost.clearFallback();
    HsSession.clear();
  });

  http.Response jsonResponse(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );

  Map<String, dynamic> listing(int files) => {
    'path': <String>[],
    'folders': [
      for (var i = 0; i < files; i++)
        {'name': 'foto$i.jpg', 'isFolder': false, 'size': 1024},
    ],
  };

  Map<String, dynamic> hubHealth() => {
    'ok': true,
    'service': 'hardstreet-drive-hub',
    'nodes': [
      {'id': 1, 'name': 'Bodega', 'enabled': true, 'online': true},
      {'id': 2, 'name': 'Respaldo', 'enabled': true, 'online': true},
    ],
  };

  Future<void> waitLoaded(DriveApiService drive) async {
    for (var i = 0; i < 200 && drive.loading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test(
    'un servidor suelto se cambia por el HUB y se ven todos los nodos',
    () async {
      DriveHost.set('http://nodo.test:4000');
      DriveApiService.client = MockClient((r) async {
        if (r.url.path == '/api/health') {
          // El 443 del servidor de archivos: una sola máquina, sin `nodes`.
          if (r.url.host == 'nodo.test') {
            return jsonResponse({'ok': true, 'service': 'hardstreet-drive'});
          }
          return jsonResponse(hubHealth());
        }
        if (r.url.path == '/api/drive') {
          return jsonResponse(listing(r.url.host == 'nodo.test' ? 37 : 70));
        }
        return http.Response('no encontrado', 404);
      });

      final drive = DriveApiService();
      await waitLoaded(drive);

      // Se cambió a la dirección del hub (el mismo nombre por HTTP en el 4100).
      expect(DriveHost.base, DriveHost.publicHttp);
      expect(DriveHost.usingFallback, isTrue);
      // Y el listado es el unido: las 37 del nodo + las 33 del otro.
      expect(drive.items.length, 70);
      expect(drive.error, isNull);
    },
  );

  test(
    'si ya es el HUB no se toca la dirección ni se prueban respaldos',
    () async {
      final pedidas = <String>[];
      DriveApiService.client = MockClient((r) async {
        pedidas.add(r.url.toString());
        if (r.url.path == '/api/health') return jsonResponse(hubHealth());
        if (r.url.path == '/api/drive') return jsonResponse(listing(70));
        return http.Response('no encontrado', 404);
      });

      final drive = DriveApiService();
      await waitLoaded(drive);

      expect(DriveHost.base, DriveHost.compiled);
      expect(DriveHost.usingFallback, isFalse);
      expect(drive.items.length, 70);
      // Solo se preguntó a la dirección configurada.
      expect(pedidas.where((u) => u.endsWith('/api/health')).toList(), [
        '${DriveHost.compiled}/api/health',
      ]);
    },
  );

  test('sin hub alcanzable se sigue usando el servidor de siempre', () async {
    DriveHost.set('http://nodo.test:4000');
    DriveApiService.client = MockClient((r) async {
      if (r.url.path == '/api/health') {
        if (r.url.host == 'nodo.test') {
          return jsonResponse({'ok': true, 'service': 'hardstreet-drive'});
        }
        throw http.ClientException('sin red', r.url);
      }
      if (r.url.path == '/api/drive') return jsonResponse(listing(37));
      return http.Response('no encontrado', 404);
    });

    final drive = DriveApiService();
    await waitLoaded(drive);

    // Un Drive de un solo servidor sigue funcionando como antes.
    expect(DriveHost.base, 'http://nodo.test:4000');
    expect(DriveHost.usingFallback, isFalse);
    expect(drive.items.length, 37);
    expect(drive.error, isNull);
  });
}

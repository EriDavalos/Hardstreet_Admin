import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';

void main() {
  late List<Map<String, dynamic>> posts;
  late List<http.Request> calls;

  setUp(() {
    posts = <Map<String, dynamic>>[];
    calls = <http.Request>[];
    final previous = HsApi.client;
    addTearDown(() => HsApi.client = previous);
    HsApi.client = MockClient((request) async {
      calls.add(request);
      final headers = {'content-type': 'application/json'};
      final path = request.url.path;

      if (path.endsWith('/api/admin/notifications')) {
        if (request.method == 'POST') {
          posts.add((jsonDecode(request.body) as Map).cast<String, dynamic>());
          return http.Response(
            jsonEncode({'ok': true, 'message': 'Aviso enviado', 'sent': 2}),
            200,
            headers: headers,
          );
        }
        return http.Response(
          jsonEncode({
            'ok': true,
            'events': const [],
            'roles': const [],
            'history': const [],
          }),
          200,
          headers: headers,
        );
      }

      if (path.endsWith('/api/admin/locations')) {
        if (request.method == 'POST') {
          posts.add((jsonDecode(request.body) as Map).cast<String, dynamic>());
        }
        return http.Response(
          jsonEncode({
            'ok': true,
            'locations': [
              {
                'id': 4,
                'name': 'Hacienda San José',
                'address': 'Cota',
                'lat': 4.7,
                'lng': -74.1,
              },
            ],
          }),
          200,
          headers: headers,
        );
      }

      return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
    });
  });

  test('la regla de un evento manda evento, roles y encendido', () async {
    await HsApi.saveNotificationRule(
      eventKey: 'fotos-enviadas',
      roleIds: [3],
      enabled: false,
    );
    expect(posts.single['action'], 'save-rule');
    expect(posts.single['eventKey'], 'fotos-enviadas');
    expect(posts.single['roleIds'], [3]);
    expect(posts.single['enabled'], false);
  });

  test('el aviso manual lleva título, roles y módulo de destino', () async {
    final sent = await HsApi.sendAdminNotification(
      title: 'Entrega el viernes',
      body: 'Llega a las 10',
      roleIds: [2, 3],
      target: 'print',
    );
    expect(sent, 2);
    expect(posts.single['action'], 'send');
    expect(posts.single['roleIds'], [2, 3]);
    expect(posts.single['target'], 'print');
  });

  test('las ubicaciones guardadas se leen, se crean y se quitan', () async {
    final saved = await HsApi.savedLocations();
    expect(saved.single['name'], 'Hacienda San José');
    expect(saved.single['lat'], 4.7);

    final after = await HsApi.saveSavedLocation(
      name: 'Hacienda San José',
      lat: 4.7,
      lng: -74.1,
    );
    expect(after.single['id'], 4);
    expect(posts.single['name'], 'Hacienda San José');

    await HsApi.deleteSavedLocation(4);
    expect(calls.last.method, 'DELETE');
    expect(calls.last.url.queryParameters['id'], '4');
  });
}

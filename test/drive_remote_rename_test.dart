import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/drive_api_service.dart';

/// Renombrar en el DRIVE DEL SERVIDOR.
///
/// El servicio mandaba TODO como POST (aunque pidiera PATCH) y la ruta del
/// servidor es `PATCH /api/items`: contestaba 404 y renombrar no hacía nada.
void main() {
  test('rename manda PATCH /api/items (y conserva la extensión)', () async {
    String? method;
    String? path;
    Map<String, dynamic>? body;

    final previous = DriveApiService.client;
    DriveApiService.client = MockClient((request) async {
      method = request.method;
      path = request.url.path;
      body = request.body.isEmpty
          ? null
          : (jsonDecode(request.body) as Map).cast<String, dynamic>();
      const headers = {'content-type': 'application/json'};
      if (request.url.path == '/api/items') {
        return http.Response(
          jsonEncode({'ok': true}),
          200,
          headers: headers,
        );
      }
      // El listado de la carpeta (lo pide el refresco posterior).
      return http.Response(
        jsonEncode({'ok': true, 'folders': const []}),
        200,
        headers: headers,
      );
    });
    addTearDown(() => DriveApiService.client = previous);

    final drive = DriveApiService(baseUrl: 'http://drive.test');
    await drive.rename(
      const DriveItem(name: 'foto.jpg', isFolder: false),
      'otra',
    );

    expect(method, 'PATCH', reason: 'el servidor expone PATCH, no POST');
    expect(path, '/api/items');
    expect(body?['newName'], 'otra.jpg',
        reason: 'sin la extensión la imagen desaparece del Drive');
  });
}

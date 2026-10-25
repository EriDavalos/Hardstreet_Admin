import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/drive_api_service.dart';

/// Mover y copiar en el DRIVE DEL SERVIDOR.
///
/// Las rutas se mandaban como LISTA JSON (`from: ["Hardstreet","XV"]`). El
/// nodo lo entiende, pero el hub hacía `String(lista)` → "Hardstreet,XV" como
/// UN solo nombre: no encontraba la carpeta y mover no hacía nada (ni error).
void main() {
  late http.Client previous;

  setUp(() => previous = DriveApiService.client);
  tearDown(() => DriveApiService.client = previous);

  test('mover manda las rutas como TEXTO y devuelve cuántos movió', () async {
    Map<String, dynamic>? sent;
    DriveApiService.client = MockClient((request) async {
      const headers = {'content-type': 'application/json'};
      if (request.url.path == '/api/move') {
        sent = (jsonDecode(request.body) as Map).cast<String, dynamic>();
        return http.Response(
          jsonEncode({'moved': 1, 'errors': <String>[]}),
          200,
          headers: headers,
        );
      }
      return http.Response(
        jsonEncode({
          'folders': [
            {'name': 'XV', 'isFolder': true, 'childCount': 1},
          ],
        }),
        200,
        headers: headers,
      );
    });

    final drive = DriveApiService(baseUrl: 'http://drive.test');
    await drive.openFolder('XV');

    final res = await drive.moveItems(['foto.jpg'], ['XV', 'ValeriaCanul']);

    expect(res.moved, 1);
    expect(
      sent?['from'],
      'XV',
      reason: 'una lista JSON deja fuera a un hub que la lee como un nombre',
    );
    expect(sent?['to'], 'XV/ValeriaCanul');
    expect(sent?['names'], ['foto.jpg']);
  });

  test('copiar también manda texto y respeta la ruta de destino', () async {
    Map<String, dynamic>? sent;
    DriveApiService.client = MockClient((request) async {
      const headers = {'content-type': 'application/json'};
      if (request.url.path == '/api/copy') {
        sent = (jsonDecode(request.body) as Map).cast<String, dynamic>();
        return http.Response(
          jsonEncode({'copied': 2, 'errors': <String>[]}),
          200,
          headers: headers,
        );
      }
      return http.Response(
        jsonEncode({
          'folders': [
            {'name': 'XV', 'isFolder': true, 'childCount': 1},
          ],
        }),
        200,
        headers: headers,
      );
    });

    final drive = DriveApiService(baseUrl: 'http://drive.test');
    await drive.openFolder('XV');

    final res = await drive.copyItems(['a.jpg', 'b.jpg'], ['Boda']);

    expect(res.copied, 2);
    expect(sent?['from'], 'XV');
    expect(sent?['to'], 'Boda');
  });
}

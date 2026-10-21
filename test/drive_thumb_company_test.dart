import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/drive_api_service.dart';
import 'package:hardstreet_admin/hs_api.dart';

// ==================================================================
// MINIATURAS Y EMPRESA
// ==================================================================
// El servidor del drive resuelve las rutas DENTRO de la carpeta de la empresa
// del usuario cuando la petición trae sesión. Las miniaturas son imágenes
// (`Image.network`), así que el token va en la query: con `Apikey` de header no
// llegarían. Sin él, el listado de una empresa funcionaba pero TODAS las
// miniaturas daban 404 (la foto se buscaba en la raíz del disco).
// ==================================================================

void main() {
  setUp(() {
    HsSession.token = 'tok-test';
    DriveApiService.client = MockClient(
      (request) async => http.Response(
        jsonEncode({'path': <String>[], 'folders': <Object>[]}),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
  });

  tearDown(() {
    DriveApiService.client = http.Client();
    HsSession.clear();
  });

  test('la miniatura y el preview llevan ?apikey= (alcance por empresa)', () {
    final drive = DriveApiService(baseUrl: 'http://drive.test');
    drive.path = const ['XV', 'ReynaCoot'];
    const item = DriveItem(name: 'foto.jpg', isFolder: false, size: 1024);

    final thumb = drive.thumbSource(item, width: 320);
    expect(thumb, startsWith('http://drive.test/thumb/XV/ReynaCoot/foto.jpg'));
    expect(thumb, contains('w=320'));
    expect(
      thumb,
      contains('apikey=tok-test'),
      reason: 'sin el token el servidor busca la foto en la raíz y da 404',
    );

    final preview = drive.fullSource(item, previewWidth: 1600);
    expect(preview, contains('/thumb/XV/ReynaCoot/foto.jpg'));
    expect(preview, contains('w=1600'));
    expect(preview, contains('apikey=tok-test'));

    // El original sigue llevando el token como siempre.
    expect(drive.absolutePathOf(item), contains('apikey=tok-test'));
  });

  test('sin sesión las URLs siguen siendo válidas (sin apikey)', () {
    HsSession.clear();
    final drive = DriveApiService(baseUrl: 'http://drive.test');
    drive.path = const ['XV'];
    const item = DriveItem(name: 'foto.jpg', isFolder: false);

    final thumb = drive.thumbSource(item);
    expect(thumb, 'http://drive.test/thumb/XV/foto.jpg?w=320');
  });
}

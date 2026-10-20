import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/hs_access.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';

/// PNG 1x1 válido: los archivos del drive se decodifican de verdad.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/'
  'q842iQAAAABJRU5ErkJggg==',
);

/// Backend falso: /api/admin/permission devuelve el módulo Archivos con las
/// acciones del rol que se quiera probar.
void _installMock(List<String> actions) {
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    if (request.url.path.endsWith('/api/admin/permission')) {
      return http.Response(
        jsonEncode({
          'isAdmin': false,
          'modules': [
            {
              'key': 'drive',
              'name': 'Archivos',
              'order': 3,
              'actions': actions,
            },
          ],
        }),
        200,
        headers: headers,
      );
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Abre el Drive con el rol dado (una imagen en la raíz para poder abrir su
/// menú contextual).
Future<void> _pumpDrive(WidgetTester tester, List<String> actions) async {
  late Directory tmp;
  await tester.runAsync(() async {
    tmp = await Directory.systemTemp.createTemp('hardstreet_drive_perm');
  });
  File('${tmp.path}/una.png').writeAsBytesSync(_png);

  await tester.binding.setSurfaceSize(const Size(1280, 860));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final previous = HsApi.client;
  _installMock(actions);
  addTearDown(() {
    HsApi.client = previous;
    HsAccess.reset();
  });
  HsAccess.reset();
  // El panel carga los permisos del rol al iniciar sesión.
  await HsAccess.load();

  final drive = DriveService.testRoot(tmp);
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: DrivePage(drive: drive))),
  );
  await settle(tester);
  addTearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });
}

Future<void> _rightClick(WidgetTester tester, Finder finder) async {
  await tester.tap(finder,
      kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
  await settle(tester);
}

void main() {
  testWidgets('rol con solo "Ver": sin crear, editar, eliminar ni descargar',
      (tester) async {
    await _pumpDrive(tester, const ['read']);

    // Nada de crear: ni carpeta ni subir imágenes.
    expect(find.text('Nueva carpeta'), findsNothing);
    expect(find.text('Subir archivos'), findsNothing);

    // El menú del elemento solo ofrece abrirlo (protegido).
    await _rightClick(tester, find.text('una.png'));
    expect(find.text('Abrir'), findsOneWidget);
    expect(find.text('Descargar'), findsNothing);
    expect(find.text('Renombrar'), findsNothing);
    expect(find.text('Eliminar'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rol completo: las acciones del Drive están disponibles',
      (tester) async {
    await _pumpDrive(tester, const ['read', 'create', 'update', 'delete', 'download']);

    expect(find.text('Nueva carpeta'), findsOneWidget);
    expect(find.text('Subir archivos'), findsOneWidget);

    await _rightClick(tester, find.text('una.png'));
    expect(find.text('Descargar'), findsOneWidget);
    expect(find.text('Renombrar'), findsOneWidget);
    expect(find.text('Eliminar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

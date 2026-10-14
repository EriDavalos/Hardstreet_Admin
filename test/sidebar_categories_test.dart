import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hardstreet_admin/drive_scope.dart';
import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/hs_access.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/main.dart';

Map<String, dynamic> _mod(
  String key,
  String name, {
  required int order,
  int? categoryOrder,
  String? categoryName,
  List<String> actions = const ['read'],
}) =>
    {
      'key': key,
      'name': name,
      'order': order,
      'categoryKey': categoryName?.toLowerCase(),
      'categoryName': categoryName,
      'categoryOrder': categoryOrder,
      'actions': actions,
    };

/// Mock del backend: TODOS los módulos con su categoría/orden, EXCEPTO Roles
/// (que existe pero SIN "Ver": debe desaparecer del menú).
void _installMock() {
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;
    if (path.endsWith('/api/admin/permission')) {
      return http.Response(
        jsonEncode({
          'isAdmin': false,
          'modules': [
            _mod('dashboard', 'Dashboard', order: 1),
            _mod('drive', 'Archivos',
                order: 3, categoryOrder: 1, categoryName: 'Operación'),
            _mod('schedules', 'Agendas',
                order: 4, categoryOrder: 1, categoryName: 'Operación'),
            _mod('finance', 'Finanzas',
                order: 5, categoryOrder: 1, categoryName: 'Operación'),
            _mod('rols', 'Roles',
                order: 6,
                categoryOrder: 2,
                categoryName: 'Administración',
                actions: const []),
            _mod('users', 'Usuarios',
                order: 7, categoryOrder: 2, categoryName: 'Administración'),
            _mod('clients', 'Clientes',
                order: 8, categoryOrder: 2, categoryName: 'Administración'),
            _mod('packages', 'Paquetes',
                order: 9, categoryOrder: 2, categoryName: 'Administración'),
          ],
        }),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/my/drive')) {
      return http.Response(
        jsonEncode({'isClient': false, 'paths': const []}),
        200,
        headers: headers,
      );
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

void main() {
  testWidgets('el menú agrupa por categoría, ordena y oculta sin "Ver"',
      (tester) async {
    late Directory tmp;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('hardstreet_sidebar_test');
    });
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final previous = HsApi.client;
    _installMock();
    addTearDown(() {
      HsApi.client = previous;
      HsAccess.reset();
      tmp.deleteSync(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});
    HsAccess.reset();

    await tester.pumpWidget(
      DriveScope(
        drive: DriveService.testRoot(tmp),
        child: MaterialApp(
          home: AdminHome(
            dark: false,
            onToggleTheme: () {},
            onLogout: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );

    // Abrir el menú lateral.
    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );

    // Encabezados de categoría (de la BD) presentes y en orden.
    expect(find.text('OPERACIÓN'), findsOneWidget);
    expect(find.text('ADMINISTRACIÓN'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('OPERACIÓN')).dy,
      lessThan(tester.getTopLeft(find.text('ADMINISTRACIÓN')).dy),
      reason: 'Operación (order 1) va arriba de Administración (order 2)',
    );

    // Módulos visibles en su grupo (el texto puede repetirse en el
    // dashboard, así que basta con que aparezcan).
    expect(find.text('Archivos'), findsWidgets);
    expect(find.text('Usuarios'), findsWidgets);
    // Roles existe pero SIN "Ver": oculto del menú.
    expect(find.text('Roles'), findsNothing);

    // 'Usuarios' solo vive en el menú: cuelga DEBAJO de su encabezado de
    // categoría (Administración).
    expect(
      tester.getTopLeft(find.text('Usuarios')).dy,
      greaterThan(tester.getTopLeft(find.text('ADMINISTRACIÓN')).dy),
    );

    expect(tester.takeException(), isNull);
  });
}

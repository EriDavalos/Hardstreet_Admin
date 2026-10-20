import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/users_page.dart';

// ==================================================================
// REGLA DEL ROL MÁS ALTO + FILTROS del módulo Usuarios
// ==================================================================
// El rol Admin es el más alto: su cuenta NO se le muestra a los demás roles
// (y el backend tampoco la devuelve). Aquí se comprueba lo que ve el panel:
//   * un Empleado no ve filas Admin ni el chip de ese rol;
//   * un Admin SÍ las ve y puede filtrarlas;
//   * el filtro por rol deja a la vista solo ese rol;
//   * el formulario ofrece los roles en un COMBO BOX (sin el Admin para
//     quien no es Admin).
// ==================================================================

List<Map<String, dynamic>> get _users => [
  {
    'id': 1,
    'name': 'Ana',
    'lastname': 'Admin',
    'email': 'ana@hardstreet.com',
    'role': 'Admin',
    'roleId': 1,
  },
  {
    'id': 2,
    'name': 'Leo',
    'lastname': 'Empleado',
    'email': 'leo@hardstreet.com',
    'role': 'Empleado',
    'roleId': 2,
  },
  {
    'id': 3,
    'name': 'Rita',
    'lastname': 'Fotógrafa',
    'email': 'rita@hardstreet.com',
    'role': 'Fotógrafo',
    'roleId': 3,
  },
];

void _installMockClient() {
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;
    if (path.endsWith('/api/admin/users')) {
      return http.Response(
        jsonEncode({'users': _users}),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/admin/roles')) {
      return http.Response(
        jsonEncode({
          'roles': [
            {
              'id': 1,
              'name': 'Admin',
              'permissions': [
                {'moduleId': 1, 'permissionId': 2},
              ],
            },
            {
              'id': 2,
              'name': 'Empleado',
              'permissions': [
                {'moduleId': 1, 'permissionId': 2},
                {'moduleId': 2, 'permissionId': 2},
              ],
            },
            {'id': 3, 'name': 'Fotógrafo', 'permissions': []},
          ],
        }),
        200,
        headers: headers,
      );
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 1400);
  await tester.binding.setSurfaceSize(const Size(1200, 1400));
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: UsersPage())));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  final previous = HsApi.client;
  tearDown(() {
    HsApi.client = previous;
    HsSession.clear();
  });

  testWidgets('un Empleado no ve la cuenta Admin ni su filtro', (tester) async {
    HsSession.token = 't';
    HsSession.user = {'email': 'leo@hardstreet.com', 'role': 'Empleado'};
    _installMockClient();
    await _pump(tester);

    expect(find.text('Leo Empleado'), findsOneWidget);
    expect(
      find.text('Ana Admin'),
      findsNothing,
      reason: 'la cuenta Admin queda oculta para otros roles',
    );
    // El chip del filtro tampoco ofrece Admin.
    expect(find.textContaining('Admin ('), findsNothing);
  });

  testWidgets('un Admin sí ve la cuenta y puede filtrar por rol', (
    tester,
  ) async {
    HsSession.token = 't';
    HsSession.user = {'email': 'ana@hardstreet.com', 'role': 'Admin'};
    _installMockClient();
    await _pump(tester);

    expect(find.text('Ana Admin'), findsOneWidget);
    // Filtro: al elegir Fotógrafo solo queda esa persona (el filtro vive en
    // el módulo que abre el botón de la barra de búsqueda).
    await tester.tap(find.byKey(const ValueKey('hs-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fotógrafo').last);
    await tester.pump();
    await tester.tap(find.textContaining('Aplicar'));
    await tester.pump();
    expect(find.text('Rita Fotógrafa'), findsOneWidget);
    expect(find.text('Leo Empleado'), findsNothing);
    expect(find.text('Ana Admin'), findsNothing);
  });

  testWidgets('el rol se elige en un COMBO BOX y sin Admin para no-Admins', (
    tester,
  ) async {
    HsSession.token = 't';
    HsSession.user = {'email': 'leo@hardstreet.com', 'role': 'Empleado'};
    _installMockClient();
    await _pump(tester);

    await tester.tap(find.text('Nuevo usuario'));
    await tester.pumpAndSettle();

    // El campo del rol es un desplegable (no carpetitas sueltas).
    final combo = find.byKey(const ValueKey('user-role-select'));
    expect(combo, findsOneWidget);
    expect(find.text('Rol de la cuenta'), findsOneWidget);
    expect(find.text('Elige la carpeta del rol'), findsNothing);

    await tester.tap(combo);
    await tester.pumpAndSettle();

    // La opción del rol Admin no se ofrece a un Empleado.
    expect(find.byKey(const ValueKey('user-role-1')), findsNothing);
    expect(find.byKey(const ValueKey('user-role-2')), findsOneWidget);
    expect(find.text('Sin rol'), findsWidgets);
  });
}

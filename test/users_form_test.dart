import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/users_page.dart';

// ==================================================================
// FORMULARIO DE USUARIO: contraseña y rol
// ==================================================================
// Tres fallos que se veían en el modal:
//
//   * el botón del ojo no cambiaba nada (el campo era `late final` y
//     reasignarlo lanzaba LateInitializationError);
//   * al EDITAR se escribía una contraseña nueva y no se enviaba, así que
//     la cuenta seguía con la vieja;
//   * el rol se elegía con carpetitas; ahora es un combo box moderno.
// ==================================================================

const _user = {
  'id': 2,
  'name': 'Leo',
  'lastname': 'Empleado',
  'email': 'leo@hardstreet.com',
  'number': '600000000',
  'role': 'Empleado',
  'roleId': 2,
};

const _roles = [
  {'id': 1, 'name': 'Admin', 'permissions': []},
  {
    'id': 2,
    'name': 'Empleado',
    'permissions': [
      {'moduleId': 1, 'permissionId': 2},
    ],
  },
  {'id': 3, 'name': 'Fotógrafo', 'permissions': []},
];

Map<String, dynamic>? _lastPut;

void _installMockClient() {
  _lastPut = null;
  HsApi.client = MockClient((request) async {
    const headers = {'content-type': 'application/json'};
    final path = request.url.path;
    if (path.endsWith('/api/admin/users') && request.method == 'GET') {
      return http.Response(
        jsonEncode({
          'users': [_user],
          'roleCounts': {'Empleado': 1},
          'allTotal': 1,
          'total': 1,
          'page': 1,
          'pages': 1,
        }),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/admin/users') && request.method == 'PUT') {
      _lastPut = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({'item': _user}),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/admin/roles')) {
      return http.Response(
        jsonEncode({'roles': _roles}),
        200,
        headers: headers,
      );
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(1200, 1400),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: UsersPage())));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _openEdit(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Editar y asignar rol'));
  await tester.pumpAndSettle();
  expect(find.text('Editar usuario'), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  final previous = HsApi.client;

  setUp(() {
    HsSession.token = 't';
    HsSession.user = {'email': 'ana@hardstreet.com', 'role': 'Admin'};
    _installMockClient();
  });

  tearDown(() {
    HsApi.client = previous;
    HsSession.clear();
  });

  testWidgets('el ojo muestra y oculta la contraseña', (tester) async {
    await _pump(tester);
    await _openEdit(tester);

    TextField field() =>
        tester.widget<TextField>(find.byKey(const ValueKey('user-password')));

    expect(field().obscureText, isTrue);
    await tester.enterText(
      find.byKey(const ValueKey('user-password')),
      'clave-secreta',
    );
    await tester.tap(find.byTooltip('Mostrar'));
    await tester.pump();
    expect(field().obscureText, isFalse);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Ocultar'));
    await tester.pump();
    expect(field().obscureText, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('al editar, la contraseña nueva se envía al servidor', (
    tester,
  ) async {
    await _pump(tester);
    await _openEdit(tester);

    await tester.enterText(
      find.byKey(const ValueKey('user-password')),
      'nueva-clave-123',
    );
    // Y el rol se cambia en el combo.
    await tester.tap(find.byKey(const ValueKey('user-role-select')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('user-role-3')), findsOneWidget);
    await tester.tap(find.text('Fotógrafo'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    expect(_lastPut, isNotNull);
    expect(_lastPut!['id'], 2);
    expect(_lastPut!['password'], 'nueva-clave-123');
    expect(_lastPut!['id_role'], 3);
    expect(find.text('Editar usuario'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en el celular el formulario no desborda', (tester) async {
    await _pump(tester, size: const Size(390, 844));
    // En el celular la acción de la cabecera queda como icono.
    await tester.tap(find.byIcon(Icons.person_add_alt));
    await tester.pumpAndSettle();

    expect(find.text('Nuevo usuario'), findsWidgets);
    expect(find.byKey(const ValueKey('user-role-select')), findsOneWidget);
    expect(find.byKey(const ValueKey('user-password')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin escribir contraseña, la actual no se toca', (tester) async {
    await _pump(tester);
    await _openEdit(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre'),
      'Leonardo',
    );
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    expect(_lastPut, isNotNull);
    expect(_lastPut!.containsKey('password'), isFalse);
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/login_page.dart';

// ==================================================================
// ENTRADA AL PANEL POR ROL
// ==================================================================
// El rol SUPERADMINISTRADOR es el nivel más alto del sistema: administra todas
// las empresas. Antes el login lo rechazaba con "esta cuenta no tiene acceso al
// panel" porque la lista de roles estaba escrita a mano y no lo incluía, y
// además no contaba como administrador (no veía ni asignaba la cuenta Admin).
// ==================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // El cliente se guarda DENTRO de la prueba (crear uno real fuera de la zona
  // de test hace que flutter_test no pueda interceptarlo).
  late http.Client previous;
  setUp(() => previous = HsApi.client);
  tearDown(() {
    HsApi.client = previous;
    HsSession.clear();
  });

  test('los roles que la app atiende pueden entrar', () {
    for (final role in [
      'Admin',
      'Superadmin',
      'Colaborador',
      'Empleado',
      'Cliente',
      '  superadmin ',
    ]) {
      expect(
        HsSession.roleCanUsePanel(role),
        isTrue,
        reason: '"$role" debe poder entrar al panel',
      );
    }
  });

  test('un rol desconocido no entra (se le avisa, no se le deja a medias)', () {
    expect(HsSession.roleCanUsePanel('Fotógrafo'), isFalse);
    expect(HsSession.roleCanUsePanel(''), isFalse);
  });

  test('el Superadministrador cuenta como administrador', () {
    HsSession.user = {'role': 'Superadmin'};
    expect(HsSession.isAdmin, isTrue);

    HsSession.user = {'role': 'Admin'};
    expect(HsSession.isAdmin, isTrue);

    HsSession.user = {'role': 'Empleado'};
    expect(HsSession.isAdmin, isFalse);
  });

  testWidgets('el Superadministrador entra al panel (no dice "sin acceso")', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    HsApi.client = MockClient((request) async {
      const headers = {'content-type': 'application/json'};
      if (request.url.path.endsWith('/api/auth/login')) {
        return http.Response(
          jsonEncode({
            'token': 'token-de-prueba',
            'user': {
              'id': 1,
              'name': 'Súper',
              'lastname': 'Admin',
              'email': 'super@hardstreet.com',
              'role': 'Superadmin',
              'isSuperAdmin': true,
              'companyId': null,
              'companyName': '',
            },
          }),
          200,
          headers: headers,
        );
      }
      return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
    });

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);

    var entered = false;
    await tester.pumpWidget(
      MaterialApp(home: LoginPage(onLogin: () => entered = true)),
    );
    await tester.pump();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'super@hardstreet.com');
    await tester.enterText(fields.at(1), 'secreto');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('no tiene acceso'),
      findsNothing,
      reason: 'el rol Superadmin debe poder entrar',
    );
    expect(entered, isTrue, reason: 'el login debe continuar al panel');
    expect(HsSession.isSuperAdmin, isTrue);
    expect(HsSession.isAdmin, isTrue);
  });
}

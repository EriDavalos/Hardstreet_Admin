import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hardstreet_admin/app_settings.dart';
import 'package:hardstreet_admin/hs_access.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/settings_page.dart';

// ==================================================================
// NOMBRE Y DESCRIPCIÓN DE LOS MÓDULOS DESDE LA BASE DE DATOS
// ==================================================================
// La identidad de un módulo es `modules.module`; lo que se lee es
// `modules.name` y, debajo, `modules.description`. Renombrar o reescribir la
// descripción en la BD debe cambiar el panel sin tocar el código.
// ==================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('el nombre y la descripción salen de la BD', (tester) async {
    SharedPreferences.setMockInitialValues({
      'app.theme.mode': 'light',
      'app.accent': 'azul',
    });
    await AppSettings.instance.load();

    final previous = HsApi.client;
    HsApi.client = MockClient((request) async {
      if (request.url.path.endsWith('/api/admin/permission')) {
        return http.Response(
          jsonEncode({
            'isAdmin': false,
            'modules': [
              {
                'key': 'settings',
                'name': 'Ajustes del estudio',
                'description': 'Texto que viene de la tabla modules.',
                'order': 1,
                'actions': ['read'],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        '{}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(() {
      HsApi.client = previous;
      HsAccess.reset();
    });

    await HsAccess.load();
    expect(
      HsAccess.instance.nameOf('settings', fallback: 'Configuraciones'),
      'Ajustes del estudio',
    );
    expect(
      HsAccess.instance.descriptionOf(
        'settings',
        fallback: 'Descripción escrita en el código',
      ),
      'Texto que viene de la tabla modules.',
    );

    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SettingsPage())),
    );
    await tester.pump();

    // El encabezado del módulo usa el nombre y el texto de la BD.
    expect(find.text('Ajustes del estudio'), findsOneWidget);
    expect(find.text('Texto que viene de la tabla modules.'), findsOneWidget);
    expect(find.text('Configuraciones'), findsNothing);
  });
}

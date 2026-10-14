import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hardstreet_admin/drive_scope.dart';
import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/main.dart';
import 'package:hardstreet_admin/widgets/startup_intro.dart';

/// Cliente falso para el flujo completo: login (rol admin), permisos,
/// recordatorios y las fuentes del dashboard. Todo lo demás responde {ok}.
MockClient _installMock() {
  final client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;
    if (path.endsWith('/api/auth/login')) {
      return http.Response(
        jsonEncode({
          'token': 'tok-test',
          'user': {'id': 1, 'name': 'Ana', 'role': 'Admin'},
        }),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/admin/permission')) {
      return http.Response(
        jsonEncode({
          'isAdmin': true,
          'modules': <dynamic>[],
        }),
        200,
        headers: headers,
      );
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
  HsApi.client = client;
  return client;
}

void main() {
  testWidgets('Flujo: login -> panel Dashboard -> abrir menú -> logout',
      (WidgetTester tester) async {
    // El I/O real debe ejecutarse fuera de la zona fake-async del test.
    late Directory tmp;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('hardstreet_widget_test');
    });
    // Viewport tipo laptop para ejercitar el layout de escritorio.
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final previous = HsApi.client;
    _installMock();
    addTearDown(() => HsApi.client = previous);
    // Sin esto, SharedPreferences.getInstance() se queda colgado en el test
    // y el login nunca navega al panel.
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      DriveScope(
        drive: DriveService.testRoot(tmp),
        child: const HardStreetAdminApp(),
      ),
    );

    // 0. Animación de arranque: es lo PRIMERO que se ve (Windows y Android
    //    comparten la misma) y desaparece sola al terminar.
    expect(find.byType(StartupIntro), findsOneWidget);

    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    expect(find.byType(StartupIntro), findsNothing,
        reason: 'la animación de arranque cede el paso al contenido');

    // 1. Pantalla de login
    expect(find.text('Bienvenido'), findsOneWidget);

    // 2. Credenciales + entrar al panel (el envío vacío no navega).
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.first, 'ana@hardstreet.test');
    await tester.enterText(fields.last, 'secreto');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    // El panel aterriza en el Dashboard (sección inicial del menú).
    expect(find.text('Resumen general'), findsOneWidget);

    // 3. Abrir el menú lateral (overlay)
    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    expect(find.text('HardStreet'), findsOneWidget);
    expect(find.text('Panel de administración'), findsOneWidget);

    // 3.5. Cerrar el menú con el botón ✕ del propio sidebar
    await tester.tap(find.byTooltip('Cerrar menú'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );

    // 4. Cerrar sesión
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    expect(find.text('Bienvenido'), findsOneWidget);

    // Limpieza con I/O real.
    await tester.runAsync(() async {
      tmp.deleteSync(recursive: true);
    });
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_scope.dart';
import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/main.dart';

void main() {
  testWidgets('Flujo: login -> panel Archivos -> abrir menú -> logout',
      (WidgetTester tester) async {
    // El I/O real debe ejecutarse fuera de la zona fake-async del test.
    late Directory tmp;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('hardstreet_widget_test');
    });
    // Viewport tipo laptop para ejercitar el layout de escritorio.
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      DriveScope(
        drive: DriveService.testRoot(tmp),
        child: const HardStreetAdminApp(),
      ),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );

    // 1. Pantalla de login
    expect(find.text('Bienvenido'), findsOneWidget);

    // 2. Entrar al panel
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    expect(find.text('Mi Drive'), findsOneWidget);

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

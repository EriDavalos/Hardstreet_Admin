import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';

/// Panel inferior del Drive: ventanita de transferencias + avisos
/// (VERDE si la petición se cumplió, ROJO si marcó error), ocultable a una
/// pastilla y con reapertura por clic.
///
/// NOTA: el sembrado va en setUp: dentro de un testWidgets el I/O real
/// (crear carpetas) se queda colgado en la zona de tiempo simulado, así que
/// los flujos que se prueban aquí no esperan I/O de disco (Ctrl+C para el
/// aviso verde y un renombrado en conflicto —validación síncrona— para el
/// rojo).
void main() {
  late Directory tmp;
  late DriveService drive;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hs_activity_panel');
    drive = DriveService.testRoot(tmp);
    await drive.createFolder('Boda');
    await drive.createFolder('Reyna');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// Deja correr el I/O real y avanza las animaciones (sin pumpAndSettle:
  /// el marcador de carga tiene spinner infinito).
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('panel inferior: avisos verde/rojo, ocultar y reabrir',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DrivePage(drive: drive))),
    );
    await settle(tester);

    // Sin transferencias ni avisos: no existe la ventanita.
    expect(find.byKey(const ValueKey('activity_panel')), findsNothing);

    // ---- Petición cumplida → aviso VERDE (Ctrl+C copia la selección) ----
    await tester.tap(find.text('Boda'), kind: PointerDeviceKind.mouse);
    await settle(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);

    final panel = find.byKey(const ValueKey('activity_panel'));
    expect(panel, findsOneWidget, reason: 'el aviso abre la ventanita');
    // Ubicación: ABAJO y a la derecha de la pantalla.
    final rect = tester.getRect(panel);
    expect(rect.bottom, greaterThan(450),
        reason: 'la ventanita vive abajo, no arriba');
    expect(rect.bottom, lessThanOrEqualTo(790));
    expect(rect.right, greaterThan(950));
    expect(find.text('1 elemento copiado al portapapeles'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget,
        reason: 'el aviso cumplido se ve VERDE (check)');
    expect(find.byKey(const ValueKey('uploads_card')), findsNothing,
        reason: 'sin transferencias no hay tarjeta de subidas');

    // ---- Petición con error → aviso ROJO (renombrar sobre otro existente:
    //      la validación de `rename` es síncrona, sin I/O) ----
    await tester.tap(find.text('Reyna'),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
    await settle(tester);
    await tester.tap(find.text('Renombrar'));
    await settle(tester);
    final prompt = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(prompt, 'Boda');
    await tester.tap(find.text('Guardar'));
    await settle(tester);
    expect(find.text('Ya existe un elemento con ese nombre'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget,
        reason: 'el error se ve ROJO');

    // ---- Ocultar: queda la pastilla y el panel desaparece ----
    await tester.tap(find.byTooltip('Ocultar'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('activity_panel')), findsNothing);
    final pill = find.byKey(const ValueKey('activity_pill'));
    expect(pill, findsOneWidget);
    expect(find.textContaining('2 avisos'), findsOneWidget);

    // Un clic en la pastilla lo reabre.
    await tester.tap(pill);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('activity_panel')), findsOneWidget);

    // ---- Limpiar avisos: sin transferencias, la ventanita se va ----
    await tester.tap(find.byTooltip('Limpiar avisos'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('activity_panel')), findsNothing);
    expect(find.byKey(const ValueKey('activity_pill')), findsNothing);
  });
}

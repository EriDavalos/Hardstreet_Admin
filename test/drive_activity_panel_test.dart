import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_base.dart';
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

    // ---- Con la ventanita ABIERTA, un clic de FUERA la cierra sin tocar la
    //      cuadrícula (antes se colaba al fondo) ----
    await tester.tapAt(const Offset(60, 60));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('activity_panel')), findsNothing,
        reason: 'el clic de fuera cierra la ventanita');
    expect(find.byKey(const ValueKey('activity_pill')), findsOneWidget);
    expect(find.textContaining('1 aviso'), findsOneWidget,
        reason: 'el aviso sigue ahí, solo se plegó');

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

  /// Abre la ventanita con un aviso (copiar una carpeta = Ctrl+C).
  Future<void> abrirConAviso(WidgetTester tester) async {
    await tester.tap(find.text('Boda'), kind: PointerDeviceKind.mouse);
    await settle(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
  }

  testWidgets('tocar la ventanita NO toca lo que hay detrás', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Cuadrícula llena: hay carpetas TAMBIÉN debajo de la ventanita, que es
    // justo donde antes se colaba el clic (se abría una carpeta sin querer).
    // El I/O real va en runAsync: dentro del tiempo simulado se cuelga.
    await tester.runAsync(() async {
      for (var i = 0; i < 24; i++) {
        await drive.createFolder('Carpeta $i');
      }
    });
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DrivePage(drive: drive))),
    );
    await settle(tester);
    await abrirConAviso(tester);

    final panel = find.byKey(const ValueKey('activity_panel'));
    expect(panel, findsOneWidget);
    final rect = tester.getRect(panel);
    // El clic del aviso dejó seleccionada UNA carpeta: es la referencia.
    expect(find.text('elemento seleccionado'), findsOneWidget);

    // Toques en zonas de la ventanita que NO son un botón: el texto, los
    // márgenes y las esquinas no capturan toques por sí solos.
    for (final p in [
      rect.topLeft + const Offset(6, 6),
      Offset(rect.center.dx, rect.top + 30),
      rect.center,
      Offset(rect.right - 90, rect.top + 30),
    ]) {
      await tester.tapAt(p);
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(drive.path, isEmpty,
        reason: 'el toque no puede llegar a la cuadrícula de atrás');
    expect(find.text('elementos seleccionados'), findsNothing,
        reason: 'la cuadrícula no sumó elementos a la selección');
    expect(find.text('elemento seleccionado'), findsOneWidget,
        reason: 'la selección de atrás quedó intacta');
    expect(panel, findsOneWidget, reason: 'la ventanita sigue abierta');
    expect(find.text('1 elemento copiado al portapapeles'), findsOneWidget,
        reason: 'los toques de dentro no descartan el aviso');

    // Y un clic de FUERA la cierra sin tocar la cuadrícula: la selección y la
    // carpeta abierta quedan como estaban.
    await tester.tapAt(const Offset(60, 60));
    await tester.pump(const Duration(milliseconds: 250));
    expect(panel, findsNothing);
    expect(find.byKey(const ValueKey('activity_pill')), findsOneWidget);
    expect(drive.path, isEmpty);
    expect(find.text('elemento seleccionado'), findsOneWidget);
  });

  testWidgets('la ventanita se dibuja completa, sin desbordarse',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DrivePage(drive: drive))),
    );
    await settle(tester);
    await abrirConAviso(tester);

    // Una subida en curso y otra lista, más una descarga en curso y otra
    // terminada: la ventanita con todo junto es la que más se estrecha.
    drive.addUploadJob(DriveUploadJob(
      id: 'u1',
      name: 'boda-01.jpg',
      thumb: '',
      total: 100,
    )..sent = 40);
    drive.addUploadJob(DriveUploadJob(
      id: 'u2',
      name: 'boda-02.jpg',
      thumb: '',
      total: 100,
    )..status = 'done');
    drive.downloadJobs.add(DriveDownloadJob(
      id: 'd1',
      name: 'ReynaCoot.zip',
      items: const [DriveItem(name: 'ReynaCoot', isFolder: true)],
    )
      ..received = 30
      ..total = 100);
    drive.downloadJobs.add(DriveDownloadJob(
      id: 'd2',
      name: 'IMG_9006-Mejorado-NR.jpg',
      items: const [DriveItem(name: 'IMG_9006-Mejorado-NR.jpg', isFolder: false)],
    )
      ..received = 2048
      ..total = 2048
      ..status = 'done');
    drive.notifyDownloadProgress();
    await settle(tester);

    final panel = find.byKey(const ValueKey('activity_panel'));
    expect(panel, findsOneWidget);
    expect(find.byKey(const ValueKey('uploads_card')), findsOneWidget);
    expect(find.byKey(const ValueKey('downloads_card')), findsOneWidget);
    expect(find.text('Subiendo 2 fotos…'), findsOneWidget);
    expect(find.text('Descargando 1 archivo…'), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: 'sin desbordes de layout con todo dentro');

    // Y sigue cabiendo entera en la pantalla.
    final rect = tester.getRect(panel);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(1000));
    expect(rect.bottom, lessThanOrEqualTo(700));
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';

/// PNG 1x1 válido: los archivos del drive se pueden decodificar de verdad.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/'
  'q842iQAAAABJRU5ErkJggg==',
);

void main() {
  late Directory tmp;
  late DriveService drive;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hardstreet_multi_test');
    drive = DriveService.testRoot(tmp);
    for (final n in ['uno.png', 'dos.png', 'tres.png']) {
      final f = File([tmp.path, n].join('/'))..writeAsBytesSync(_png);
      await drive.uploadFromPaths([f.path]);
    }
    drive.clearFinishedUploads();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> mouseTap(WidgetTester tester, Finder f,
      {int buttons = kPrimaryButton}) async {
    await tester.tap(f, kind: PointerDeviceKind.mouse, buttons: buttons);
    await settle(tester);
  }

  testWidgets(
      'clic derecho con VARIOS seleccionados: solo acciones de la selección',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DrivePage(drive: drive))),
    );
    await settle(tester);

    // Selecciona dos con ratón (el segundo con Ctrl, como el explorador).
    await mouseTap(tester, find.text('uno.png'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await mouseTap(tester, find.text('dos.png'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    await mouseTap(tester, find.text('uno.png'), buttons: kSecondaryButton);

    expect(find.text('Descargar 2 seleccionadas'), findsOneWidget);
    expect(find.text('Eliminar 2 seleccionadas'), findsOneWidget);
    // Nada de acciones de un solo elemento.
    expect(find.text('Abrir'), findsNothing);
    expect(find.text('Renombrar'), findsNothing);
    expect(find.text('Descargar'), findsNothing);

    await tester.tapAt(const Offset(8, 770));
    await settle(tester);
  });
}

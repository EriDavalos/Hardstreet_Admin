import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

  // El sembrado va en setUp: dentro de un testWidgets el I/O real (crear
  // carpetas/archivos) se queda colgado en la zona de tiempo simulado.
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hardstreet_menu_test');
    drive = DriveService.testRoot(tmp);
    await drive.createFolder('SesionPrevia');
    for (final n in ['uno.png', 'dos.png', 'tres.png']) {
      final f = File([tmp.path, n].join('/'))..writeAsBytesSync(_png);
      await drive.uploadFromPaths([f.path]);
    }
    // Fuera el panel de subidas: sus textos duplicarían los nombres.
    drive.clearFinishedUploads();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// Avanza un poco el reloj Y deja correr el I/O real (listados, decodificado).
  /// No se usa pumpAndSettle: el marcador de carga tiene un spinner animado.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpDrive(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DrivePage(drive: drive))),
    );
    await settle(tester);
  }

  /// Clic de RATÓN (no táctil): así la página selecciona como escritorio.
  Future<void> mouseTap(WidgetTester tester, Finder f,
      {int buttons = kPrimaryButton}) async {
    await tester.tap(f, kind: PointerDeviceKind.mouse, buttons: buttons);
    await settle(tester);
  }

  /// Cierra el menú contextual abierto (toque en una esquina libre).
  Future<void> closeMenu(WidgetTester tester) async {
    await tester.tapAt(const Offset(8, 770));
    await settle(tester);
  }

  testWidgets(
      'clic derecho en una imagen: Abrir, Descargar, Renombrar, Eliminar',
      (tester) async {
    await pumpDrive(tester);

    await mouseTap(tester, find.text('uno.png'), buttons: kSecondaryButton);

    expect(find.text('Abrir'), findsOneWidget);
    expect(find.text('Descargar'), findsOneWidget);
    expect(find.text('Renombrar'), findsOneWidget);
    expect(find.text('Eliminar'), findsOneWidget);

    await closeMenu(tester);
  });

  testWidgets('clic derecho → Abrir entra de verdad a la carpeta',
      (tester) async {
    await pumpDrive(tester);

    await mouseTap(tester, find.text('SesionPrevia'),
        buttons: kSecondaryButton);
    await tester.tap(find.text('Abrir'));
    await settle(tester);

    // Antes el menú no hacía nada con el ratón (abría solo con táctil).
    expect(drive.path, ['SesionPrevia']);
    await closeMenu(tester);
  });
}

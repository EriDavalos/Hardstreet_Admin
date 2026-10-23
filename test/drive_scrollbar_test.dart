import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';

// ==================================================================
// ESCRITORIO: ARRASTRAR LA BARRA DE SCROLL NO SELECCIONA
// ==================================================================
// La barra de scroll vive DENTRO del contenido. Agarrarla y arrastrarla
// caía en la zona "vacía" del Drive, así que arrancaba la marquesina: se
// encendía el modo «Seleccionar» y aparecía el recuadro mientras se
// desplazaba. Ahora el borde derecho (donde está la barra) se ignora.
//
// Va en su propio archivo: el gesto de ratón deja el puntero encima de la
// vista y mezclarlo con otras pruebas de ratón del mismo archivo desestabiliza
// el runner (se cuelga en la siguiente).
// ==================================================================

/// PNG 1x1 válido: los archivos del drive se decodifican de verdad.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/'
  'q842iQAAAABJRU5ErkJggg==',
);

void main() {
  late Directory tmp;
  late DriveService drive;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hardstreet_scrollbar_test');
    drive = DriveService.testRoot(tmp);
    for (final n in ['uno.png', 'dos.png', 'tres.png', 'cuatro.png']) {
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
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('arrastrar desde la barra de scroll NO enciende la selección', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DrivePage(drive: drive))),
    );
    await settle(tester);

    // El arrastre nace en el borde derecho del contenido, donde vive la barra
    // de scroll, y se va hacia la izquierda (encima de las tarjetas).
    await tester.dragFrom(
      const Offset(1266, 520),
      const Offset(-86, -80),
      kind: PointerDeviceKind.mouse,
    );
    await settle(tester);

    expect(
      find.byKey(const ValueKey('selection-count')),
      findsNothing,
      reason: 'la barra de scroll no selecciona fotos',
    );
    expect(find.text('elementos seleccionados'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

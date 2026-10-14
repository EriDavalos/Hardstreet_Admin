import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';

/// PNG 1x1 válido: los archivos del drive se pueden decodificar de verdad.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/'
  'q842iQAAAABJRU5ErkJggg==',
);

void main() {
  late Directory root;
  late Directory src;
  late DriveService drive;

  // El sembrado va en setUp: dentro de un testWidgets el I/O real se queda
  // colgado en la zona de tiempo simulado.
  setUp(() async {
    root = await Directory.systemTemp.createTemp('hardstreet_viewer_drive');
    // Los archivos a subir viven FUERA del drive: si estuvieran dentro, la
    // subida los copiaría con "(1)" y el visor abriría la copia.
    src = await Directory.systemTemp.createTemp('hardstreet_viewer_src');
    drive = DriveService.testRoot(root);
    for (final n in ['uno.png', 'dos.png', 'tres.png']) {
      final f = File([src.path, n].join('/'))..writeAsBytesSync(_png);
      await drive.uploadFromPaths([f.path]);
    }
    drive.clearFinishedUploads();
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
    if (await src.exists()) await src.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpDrive(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DrivePage(drive: drive))),
    );
    await settle(tester);
  }

  /// Abre el visor de la imagen dada (toque, como en móvil/tablet).
  Future<void> openViewer(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await settle(tester);
  }

  /// Busca dentro del VISOR (el diálogo), no en la cuadrícula de detrás.
  Finder inViewer(Finder matching) =>
      find.descendant(of: find.byType(Dialog), matching: matching);

  testWidgets('el visor va a PANTALLA COMPLETA (sin bordes curvos), muestra '
      'la info y permite DESCARGAR desde la propia vista', (tester) async {
    await pumpDrive(tester);
    // 'dos.png' es la PRIMERA imagen de la carpeta (orden por nombre).
    await openViewer(tester, 'dos.png');

    // Pantalla completa: el diálogo llena la ventana…
    expect(find.byType(Dialog), findsOneWidget);
    expect(tester.getSize(find.byType(Dialog)), const Size(1280, 800));
    // …y la imagen NO se recorta con esquinas curvas.
    expect(inViewer(find.byType(ClipRRect)), findsNothing,
        reason: 'el visor ya no redondea la foto');

    // La info del archivo y la posición dentro de la carpeta.
    expect(inViewer(find.textContaining('1 de 3')), findsOneWidget);

    // Funciones DENTRO del visor: descargar, cerrar y zoom.
    expect(inViewer(find.byTooltip('Descargar')), findsOneWidget);
    expect(inViewer(find.byTooltip('Cerrar')), findsOneWidget);
    expect(inViewer(find.byTooltip('Acercar')), findsOneWidget);
    expect(inViewer(find.byTooltip('Alejar')), findsOneWidget);
    expect(inViewer(find.byTooltip('Ajustar a la pantalla')), findsOneWidget);
    expect(inViewer(find.byTooltip('Anterior')), findsOneWidget);
    expect(inViewer(find.byTooltip('Siguiente')), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('el visor navega con las flechas del teclado y con Cerrar',
      (tester) async {
    await pumpDrive(tester);
    await openViewer(tester, 'dos.png');

    // Flecha derecha: siguiente imagen.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(tester);
    expect(inViewer(find.textContaining('2 de 3')), findsOneWidget);

    // Flecha izquierda: regresa.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await settle(tester);
    expect(inViewer(find.textContaining('1 de 3')), findsOneWidget);

    // Esc cierra el visor.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byType(Dialog), findsNothing);

    // La cuadrícula sigue ahí, con sus 3 imágenes.
    expect(find.text('dos.png'), findsOneWidget);
    expect(find.text('tres.png'), findsOneWidget);
    expect(find.text('uno.png'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}

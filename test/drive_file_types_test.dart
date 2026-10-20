import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';
import 'package:hardstreet_admin/widgets/drive_media_viewer.dart';

// ==================================================================
// ARCHIVOS QUE NO SON FOTOS EN EL DRIVE
// ==================================================================
// El Drive listaba SOLO imágenes: un vídeo, un PDF o un ZIP que estuvieran en
// la carpeta ni aparecían. Ahora se listan todos, cada uno con su tipo, y al
// tocar uno se abre EL VISOR QUE LE CORRESPONDE:
//
//   foto        → visor de imágenes (zoom y flechas)
//   vídeo/audio → reproductor (el de este archivo se prueba en
//                 `drive_media_viewer_test.dart`)
//   PDF/texto/otro → su ficha (o el reproductor, en el caso del PDF)
//
// El navegador integrado del reproductor no existe en el entorno de pruebas:
// se inyecta un doble por `debugFilePlayerBuilder`.
// ==================================================================

/// PNG 1x1 válido: la miniatura de la foto se decodifica de verdad.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/'
  'q842iQAAAABJRU5ErkJggg==',
);

void main() {
  late Directory root;
  late Directory src;
  late DriveService drive;

  /// Lo último que el reproductor de mentira recibió (null = no se abrió).
  DriveViewTarget? played;

  const files = [
    'album-a.mp4',
    'informe.pdf',
    'notas.txt',
    'entrega.zip',
    'foto.png',
    'crudo.cr2',
  ];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hardstreet_types_drive');
    src = await Directory.systemTemp.createTemp('hardstreet_types_src');
    drive = DriveService.testRoot(root);
    File('${src.path}/album-a.mp4').writeAsBytesSync(List<int>.filled(32, 1));
    File('${src.path}/informe.pdf').writeAsBytesSync(List<int>.filled(16, 3));
    File('${src.path}/notas.txt').writeAsStringSync('hola desde el drive');
    File('${src.path}/entrega.zip').writeAsBytesSync(List<int>.filled(8, 4));
    File('${src.path}/foto.png').writeAsBytesSync(_png);
    File('${src.path}/crudo.cr2').writeAsBytesSync(List<int>.filled(64, 5));
    // El sembrado va en setUp: dentro de un testWidgets el I/O real se queda
    // colgado en la zona de tiempo simulado.
    for (final name in files) {
      await drive.uploadFromPaths(['${src.path}/$name']);
    }
    drive.clearFinishedUploads();

    played = null;
    debugFilePlayerBuilder = (context, target) {
      played = target;
      return Center(
        child: Text(
          'REPRODUCTOR ${target.item.name}',
          key: const ValueKey('fake-player'),
        ),
      );
    };
  });

  tearDown(() async {
    debugFilePlayerBuilder = null;
    // "Best effort": un archivo que se quede abierto (Windows) no debe hacer
    // fallar la prueba por la limpieza.
    try {
      if (await root.exists()) await root.delete(recursive: true);
      if (await src.exists()) await src.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpDrive(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DrivePage(drive: drive)),
      ),
    );
    await settle(tester);
  }

  /// Abre el archivo [name] con un toque (como en móvil/tablet).
  Future<void> open(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await settle(tester);
  }

  /// Cierra el visor: un diálogo abierto al terminar la prueba deja trabajo
  /// pendiente para la SIGUIENTE.
  Future<void> closeViewer(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Cerrar'));
    await settle(tester);
    expect(find.byType(Dialog), findsNothing);
  }

  Finder inDialog(Finder matching) =>
      find.descendant(of: find.byType(Dialog), matching: matching);

  testWidgets('la carpeta lista TODOS los archivos, cada uno con su tipo', (
    tester,
  ) async {
    await pumpDrive(tester);

    // Todos están (antes solo aparecía la foto).
    for (final name in files) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    // Cada uno se anuncia por su tipo: extensión en la ficha…
    expect(find.text('MP4'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('TXT'), findsOneWidget);
    expect(find.text('ZIP'), findsOneWidget);
    expect(find.text('CR2'), findsOneWidget);
    // …y el icono que le toca.
    expect(find.byIcon(Icons.movie_creation_outlined), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
    expect(find.byIcon(Icons.raw_on), findsOneWidget);
    // El vídeo lleva la señal de "esto se reproduce".
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    // Y las fotos NO piden miniatura a los archivos que no son fotos: si se
    // pidiera, el servidor contestaría con un recuadro roto.

    expect(tester.takeException(), isNull);
  });

  testWidgets('cada archivo se abre con el visor que le corresponde', (
    tester,
  ) async {
    await pumpDrive(tester);

    // --- Una FOTO: el visor de imágenes (con zoom y flechas) ---
    await open(tester, 'foto.png');
    expect(played, isNull, reason: 'una foto no pasa por el reproductor');
    expect(inDialog(find.byTooltip('Acercar')), findsOneWidget);
    await closeViewer(tester);

    // --- Un VÍDEO: el REPRODUCTOR, y con la fuente de ESE archivo ---
    await open(tester, 'album-a.mp4');
    expect(played, isNotNull);
    expect(played!.item.name, 'album-a.mp4');
    expect(played!.kind, DriveItemKind.video);
    expect(played!.source, endsWith('album-a.mp4'));
    expect(inDialog(find.byKey(const ValueKey('fake-player'))), findsOneWidget);
    expect(inDialog(find.textContaining('Vídeo · MP4')), findsOneWidget);
    expect(inDialog(find.byTooltip('Acercar')), findsNothing);
    await closeViewer(tester);

    // --- Un ZIP: no hay visor que valga, pero se dice y se puede bajar ---
    await open(tester, 'entrega.zip');
    // El tipo aparece DOS veces: en la barra de arriba y en la ficha central.
    expect(inDialog(find.textContaining('Archivo · ZIP')), findsNWidgets(2));
    expect(
      inDialog(find.textContaining('no tiene vista previa')),
      findsOneWidget,
    );
    expect(
      inDialog(find.widgetWithText(FilledButton, 'Descargar')),
      findsOneWidget,
    );
    await closeViewer(tester);

    expect(tester.takeException(), isNull);
  });

  test('los formatos de cámara/teléfono también se reconocen', () {
    // Un MTS de videocámara o un HEIC de iPhone se rechazaban al subir
    // (HTTP 415) porque no estaban en ninguna lista.
    expect(driveItemKindOf('clip.mts'), DriveItemKind.video);
    expect(driveItemKindOf('CLIP.M2TS'), DriveItemKind.video);
    expect(driveItemKindOf('insta.insv'), DriveItemKind.video);
    expect(driveItemKindOf('foto.heic'), DriveItemKind.image);
    expect(driveItemKindOf('IMG.HEIF'), DriveItemKind.image);
    expect(driveItemKindOf('retrato.avif'), DriveItemKind.image);
    expect(kVideoExtensions, contains('.mts'));
    expect(kImageExtensions, contains('.heic'));
  });
}

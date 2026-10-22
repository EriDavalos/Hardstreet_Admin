import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/app_platform.dart';
import 'package:hardstreet_admin/drive_base.dart';
import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/local_share_service.dart';
import 'package:hardstreet_admin/open_file.dart';
import 'package:hardstreet_admin/share_permissions.dart';
import 'package:hardstreet_admin/shared_drive.dart';
import 'package:hardstreet_admin/widgets/drive_media_viewer.dart';

// ==================================================================
// EL VISOR DE ARCHIVOS (vídeo, audio, texto, PDF y "no hay vista previa")
// ==================================================================
// El visor se prueba AQUÍ, abriéndolo directamente: así se comprueba lo que
// hace con cada tipo de archivo sin depender de la página del Drive. El
// reproductor real (navegador integrado) y la lectura del disco se inyectan:
// ninguno de los dos existe (ni termina nunca) dentro de un `testWidgets`.
// ==================================================================

void main() {
  group('pantalla completa: hacia dónde gira el teléfono', () {
    test('un vídeo HORIZONTAL se ve apaisado', () {
      expect(
        fullscreenOrientationsFor(horizontal: true),
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
      );
    });

    test('un vídeo VERTICAL se queda de pie', () {
      expect(fullscreenOrientationsFor(horizontal: false), [
        DeviceOrientation.portraitUp,
      ]);
    });

    test('al salir (o sin medidas) se permiten todas las posturas', () {
      expect(fullscreenOrientationsFor(horizontal: null), isNull);
    });
  });

  late Directory root;
  late DriveService drive;

  /// Lo último que el reproductor de mentira recibió.
  DriveViewTarget? played;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hardstreet_viewer_drive');
    drive = DriveService.testRoot(root);
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
    debugTextLoader = null;
    try {
      if (await root.exists()) await root.delete(recursive: true);
    } catch (_) {}
  });

  DriveItem item(String name, {int size = 2048}) =>
      DriveItem(name: name, isFolder: false, size: size);

  Finder inDialog(Finder matching) =>
      find.descendant(of: find.byType(Dialog), matching: matching);

  /// Abre el visor de [target] (y deja la playlist pedida).
  Future<void> open(
    WidgetTester tester,
    DriveItem target, {
    List<DriveItem> playlist = const [],
    Future<void> Function(DriveItem)? onDownload,
    DriveBase? source,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showDriveFileViewer(
                  context,
                  drive: source ?? drive,
                  item: target,
                  playlist: playlist,
                  onDownload: onDownload,
                ),
                child: const Text('ABRIR'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('ABRIR'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(Dialog), findsOneWidget);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(Dialog), findsNothing);
  }

  testWidgets('un VÍDEO se abre en el reproductor y pasa al siguiente de la '
      'carpeta', (tester) async {
    final a = item('album-a.mp4');
    final b = item('album-b.mp4');
    await open(tester, a, playlist: [a, b]);

    // Se le pidió al reproductor ESE archivo, con su URL lista para el
    // navegador integrado (en un drive del disco, un `file://`).
    expect(played, isNotNull);
    expect(played!.item.name, 'album-a.mp4');
    expect(played!.kind, DriveItemKind.video);
    expect(played!.source, startsWith('file://'));
    expect(played!.source, endsWith('album-a.mp4'));
    expect(inDialog(find.textContaining('Vídeo · MP4')), findsOneWidget);
    expect(inDialog(find.textContaining('1 de 2')), findsOneWidget);

    // "Siguiente": cambia de vídeo sin cerrar el reproductor.
    await tester.tap(find.byTooltip('Siguiente'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(played!.item.name, 'album-b.mp4');
    expect(inDialog(find.textContaining('2 de 2')), findsOneWidget);

    // No es el visor de fotos: aquel tiene zoom.
    expect(inDialog(find.byTooltip('Acercar')), findsNothing);
    expect(tester.takeException(), isNull);
    await close(tester);

    // Un PDF usa el mismo navegador integrado (en Android no: su WebView no
    // pinta PDFs y el visor ofrece descargarlo).
    await open(tester, item('informe.pdf'));
    if (isAndroidPlatform) {
      expect(played, isNull);
      expect(
        inDialog(find.textContaining('no tiene vista previa')),
        findsOneWidget,
      );
    } else {
      expect(played, isNotNull);
      expect(played!.kind, DriveItemKind.pdf);
      expect(played!.source, endsWith('informe.pdf'));
      expect(inDialog(find.textContaining('PDF')), findsWidgets);
    }
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('pantalla completa: oculta la barra y se sale con su botón', (
    tester,
  ) async {
    await open(tester, item('boda.mp4'));

    // La barra del visor trae su propio botón: funciona aun cuando el
    // reproductor del sistema no pueda ponerse en pantalla completa.
    await tester.tap(find.byTooltip('Pantalla completa'));
    await tester.pump();

    expect(
      find.byTooltip('Cerrar'),
      findsNothing,
      reason: 'la barra superior se oculta para que el vídeo ocupe todo',
    );
    expect(find.byTooltip('Descargar'), findsNothing);

    // Siempre hay una salida visible.
    await tester.tap(find.byTooltip('Salir de pantalla completa'));
    await tester.pump();
    expect(find.byTooltip('Cerrar'), findsOneWidget);
    expect(find.byTooltip('Pantalla completa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un TEXTO se lee dentro del panel, en solo lectura', (
    tester,
  ) async {
    DriveViewTarget? read;
    debugTextLoader = (target) async {
      read = target;
      return 'hola desde el drive\nsegunda línea';
    };

    await open(tester, item('notas.txt'));

    expect(read, isNotNull, reason: 'se lee el archivo tocado');
    expect(read!.item.name, 'notas.txt');
    expect(read!.kind, DriveItemKind.text);
    expect(inDialog(find.textContaining('Texto · TXT')), findsOneWidget);
    expect(
      inDialog(find.textContaining('hola desde el drive')),
      findsOneWidget,
    );
    // Se puede seleccionar para copiar un dato, pero es de SOLO LECTURA.
    expect(inDialog(find.byType(SelectableText)), findsOneWidget);
    expect(inDialog(find.byType(TextField)), findsNothing);
    expect(
      inDialog(find.byTooltip('Siguiente')),
      findsNothing,
      reason: 'un texto no tiene lista de reproducción',
    );

    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('un vídeo GRANDE se pide en CALIDAD LIGERA (empieza antes)', (
    tester,
  ) async {
    // Una carpeta compartida (los vídeos que se ven desde el Drive) es la que
    // puede pedir la versión reencodada: el servidor la baja por el túnel y la
    // reduce al vuelo, porque el original puede ser un 4K de 1 GB que tarde
    // minutos en empezar.
    HsSession.token = 'token-de-prueba';
    addTearDown(HsSession.clear);
    final shared = SharedDrive(
      service: LocalShareService(baseUrl: 'http://drive.test'),
      shareId: 7,
      label: 'Boda',
      rights: SharePermissions.owner,
    );

    await open(
      tester,
      item('ceremonia.mp4', size: 120 * 1024 * 1024),
      source: shared,
    );
    expect(played!.kind, DriveItemKind.video);
    expect(played!.source, contains('/api/local/file'));
    expect(
      played!.source,
      contains('play=low'),
      reason: 'un vídeo de 120 MB se reencoda para que empiece antes',
    );
    await close(tester);

    // Uno pequeño se manda tal cual: reencodar no aportaría nada.
    await open(
      tester,
      item('saludo.mp4', size: 8 * 1024 * 1024),
      source: shared,
    );
    expect(played!.source, isNot(contains('play=low')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('un archivo sin vista previa se puede DESCARGAR (y abrir con el '
      'sistema, si hay computadora)', (tester) async {
    DriveItem? downloaded;
    await open(
      tester,
      item('entrega.zip', size: 512 * 1024),
      onDownload: (it) async => downloaded = it,
    );

    expect(played, isNull, reason: 'un ZIP no se reproduce');
    expect(inDialog(find.textContaining('Archivo · ZIP')), findsNWidgets(2));
    expect(
      inDialog(find.textContaining('no tiene vista previa')),
      findsOneWidget,
    );
    expect(
      inDialog(find.textContaining('512.0 KB')),
      findsOneWidget,
      reason: 'la ficha dice cuánto pesa',
    );

    // Descargar avisa a quien abrió el visor (el módulo Archivos).
    await tester.tap(find.widgetWithText(FilledButton, 'Descargar'));
    await tester.pump();
    expect(downloaded?.name, 'entrega.zip');

    // "Abrir con el sistema" solo donde existe (Windows/macOS/Linux).
    expect(
      inDialog(find.text('Abrir con el sistema')),
      hsCanOpenWithSystem ? findsOneWidget : findsNothing,
    );

    expect(tester.takeException(), isNull);
    await close(tester);
  });
}

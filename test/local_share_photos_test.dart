import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/local_share_service.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';
import 'package:hardstreet_admin/share_permissions.dart';
import 'package:hardstreet_admin/shared_drive.dart';
import 'package:hardstreet_admin/widgets/drive_thumb.dart';

// ==================================================================
// HARD STREET ADMIN — Fotos de una carpeta COMPARTIDA
// ==================================================================
// Bug reportado: \"las imágenes no cargan\" en Archivos compartidos y \"tarda\"
// al abrirlas. Eran dos cosas:
//
//   1) el VISOR preguntaba `drive is DriveApiService` para decidir si la foto
//      se baja por red. Una carpeta compartida NO es ese drive (es su propio
//      adaptador `LocalShareDrive`), así que la foto se pintaba como si fuera
//      del disco: no había `Image.network` y quedaba el marcador girando para
//      siempre;
//   2) el visor pedía el ORIGINAL (`/api/local/file`), que puede ser una foto
//      de 10 MB y, si la carpeta está en la computadora de su dueño, tiene que
//      viajar por su app: por eso tardaba.
//
// Ahora el visor le pregunta AL DRIVE (`drive.isRemote`) y pide el preview
// redimensionado (`/api/local/thumb?...w=1600`), que el servidor genera una
// vez y guarda en caché.
// ==================================================================

LocalShareDrive sharedDrive({List<String> rel = const []}) => LocalShareDrive(
  service: LocalShareService(baseUrl: 'http://drive.test'),
  shareId: 7,
  rel: rel,
);

void main() {
  setUp(() => HsSession.token = 'token-de-prueba');
  tearDown(() => HsSession.clear());

  test('una carpeta compartida se sirve por RED (y una del equipo, no)', () {
    expect(
      sharedDrive().isRemote,
      isTrue,
      reason: 'si no, su foto se pinta como archivo local y no carga nunca',
    );
    // El drive de una carpeta real del equipo sigue leyéndose del disco.
    final local = DriveService.testRoot(
      Directory.systemTemp.createTempSync('hs_local_drive'),
    );
    expect(local.isRemote, isFalse);
  });

  test('el visor pide el PREVIEW redimensionado, no el original', () {
    final drive = sharedDrive(rel: ['Boda', 'Ana']);
    const item = DriveItem(name: 'foto.jpg', isFolder: false);

    final preview = drive.fullSource(item, previewWidth: 1600);
    expect(preview, contains('/api/local/thumb'));
    expect(preview, contains('w=1600'));
    // La ruta viaja codificada (los nombres reales traen espacios y acentos).
    expect(preview, contains('path=Boda%2FAna%2Ffoto.jpg'));
    expect(
      preview,
      isNot(contains('/api/local/file')),
      reason: 'el original puede pesar 10 MB y viajar por la app del dueño',
    );
    // El token va en la URL: una imagen no puede mandar cabeceras.
    expect(preview, contains('apikey=token-de-prueba'));

    // Al DESCARGAR sí se quiere el original.
    expect(drive.fullSource(item), contains('/api/local/file'));
    expect(drive.absolutePathOf(item), contains('/api/local/file'));
    // La miniatura de la cuadrícula, en tamaño de tarjeta.
    expect(drive.thumbSource(item, width: 480), contains('w=480'));
  });

  test(
    'un vídeo GRANDE se reproduce en CALIDAD LIGERA (y se descarga entero)',
    () {
      final drive = sharedDrive(rel: ['Boda']);
      final big = DriveItem(
        name: 'ceremonia.mp4',
        isFolder: false,
        size: 120 * 1024 * 1024,
      );
      // Verlo: el servidor lo reencoda al vuelo y el reproductor empieza antes.
      expect(drive.playSource(big), contains('/api/local/file'));
      expect(drive.playSource(big), contains('play=low'));
      // Descargarlo: SIEMPRE el original.
      expect(drive.fullSource(big), isNot(contains('play=low')));
      expect(drive.absolutePathOf(big), isNot(contains('play=low')));

      // Un vídeo pequeño no se reencoda (no aportaría nada).
      final small = DriveItem(
        name: 'saludo.mp4',
        isFolder: false,
        size: 8 * 1024 * 1024,
      );
      expect(drive.playSource(small), isNot(contains('play=low')));

      // Una foto tampoco, por grande que sea.
      final photo = DriveItem(
        name: 'portada.jpg',
        isFolder: false,
        size: 90 * 1024 * 1024,
      );
      expect(drive.playSource(photo), isNot(contains('play=low')));
    },
  );

  test('una carpeta COMPARTIDA (subida al servicio) también pide calidad '
      'ligera', () {
    final shared = SharedDrive(
      service: LocalShareService(baseUrl: 'http://drive.test'),
      shareId: 7,
      label: 'Boda',
      rights: SharePermissions.owner,
    );
    final big = DriveItem(
      name: 'fiesta.mp4',
      isFolder: false,
      size: 200 * 1024 * 1024,
    );
    expect(shared.playSource(big), contains('play=low'));
    expect(shared.fullSource(big), isNot(contains('play=low')));
  });

  testWidgets('el VISOR de una carpeta compartida sí pinta la foto (por red)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDriveImageViewer(
                context,
                drive: sharedDrive(),
                images: const [DriveItem(name: 'foto.jpg', isFolder: false)],
                initialIndex: 0,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final thumb = tester.widget<DriveThumb>(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(DriveThumb),
      ),
    );
    expect(
      thumb.isRemote,
      isTrue,
      reason: 'sin esto la foto del visor no se pedía nunca',
    );
    expect(thumb.source, contains('/api/local/thumb'));
    expect(thumb.source, contains('w=1600'));

    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';

/// PNG 1x1 válido (lo que se vería como miniatura del directorio).
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/'
  'q842iQAAAABJRU5ErkJggg==',
);

Future<Directory> _tempDrive({
  List<String> files = const [],
  List<String> folders = const [],
}) async {
  final tmp = await Directory.systemTemp.createTemp('hs_drive_refresh');
  for (final name in files) {
    File('${tmp.path}${Platform.pathSeparator}$name').writeAsBytesSync(_png);
  }
  for (final name in folders) {
    Directory('${tmp.path}${Platform.pathSeparator}$name').createSync();
  }
  return tmp;
}

Future<void> _pumpDrive(WidgetTester tester, DriveService drive) async {
  await tester.binding.setSurfaceSize(const Size(1280, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: DrivePage(drive: drive)),
    ),
  );
  // El constructor dispara refresh(): dejar terminar el I/O real.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 60)),
  );
  await tester.pump();
}

void main() {
  test('una caída momentánea no vacía la carpeta que se está viendo', () async {
    final tmp = await _tempDrive(files: ['una.png']);
    addTearDown(() => tmp.delete(recursive: true));
    final fotos = Directory('${tmp.path}${Platform.pathSeparator}Fotos')
      ..createSync();
    File('${fotos.path}${Platform.pathSeparator}dos.png')
        .writeAsBytesSync(_png);

    final drive = DriveService.testRoot(tmp);
    await drive.openFolder('Fotos');
    expect(drive.items.map((i) => i.name), contains('dos.png'));

    // El servidor no responde mientras se suben fotos.
    drive.failRefresh('No se pudo conectar con el servidor');
    expect(drive.error, isNotNull);
    expect(drive.conn, DriveConn.offline);
    expect(
      drive.items.map((i) => i.name),
      contains('dos.png'),
      reason:
          'perder el directorio por un fallo pasajero es justo lo que se '
          'reportó como "aparece en rojo un momento"',
    );

    // En OTRA carpeta sí se descarta: no mostrar contenido que no corresponde.
    drive.path = ['Otra'];
    drive.failRefresh('Sin conexión');
    expect(drive.items, isEmpty);
  });

  testWidgets('un refresco que falla deja el directorio a la vista + aviso', (
    tester,
  ) async {
    // Carpetas (no imágenes): la cuadrícula no decodifica archivos y la prueba
    // se centra en el listado, que es lo que desaparecía.
    late Directory tmp;
    await tester.runAsync(() async {
      tmp = await _tempDrive(folders: ['Boda', 'XV Años']);
    });
    addTearDown(() => tmp.delete(recursive: true));
    final drive = DriveService.testRoot(tmp);

    await _pumpDrive(tester, drive);
    expect(find.text('Boda'), findsOneWidget);

    // Falla un refresco de fondo (el enlace va saturado subiendo fotos).
    drive.failRefresh('No se pudo conectar con el servidor');
    await tester.pump();

    expect(
      find.text('Boda'),
      findsOneWidget,
      reason: 'el directorio se queda a la vista',
    );
    expect(find.text('XV Años'), findsOneWidget);
    expect(
      find.text('Sin conexión con el Drive'),
      findsNothing,
      reason: 'el panel de error bloqueante no debe reemplazar al contenido',
    );
    expect(find.text('Reintentar'), findsNothing);
    expect(find.text('Sin conexión · reintentar'), findsOneWidget);

    // Vuelve la conexión: el aviso desaparece solo.
    await drive.refresh();
    await tester.pump();
    expect(find.text('Sin conexión · reintentar'), findsNothing);
  });

  testWidgets('sin nada que mostrar, el fallo sí se explica en pantalla', (
    tester,
  ) async {
    late Directory tmp;
    await tester.runAsync(() async {
      tmp = await _tempDrive();
    });
    addTearDown(() => tmp.delete(recursive: true));
    final drive = DriveService.testRoot(tmp);

    await _pumpDrive(tester, drive);
    drive.failRefresh('No se pudo conectar con el servidor (drive): timeout');
    await tester.pump();

    // El fallo se cuenta en la CARD del servidor (no en un icono gigante).
    expect(find.text('Sin conexión con el Drive'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.textContaining('No se pudo conectar'), findsWidgets);
  });
}

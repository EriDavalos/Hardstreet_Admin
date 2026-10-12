import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';

/// PNG 1x1 válido.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/'
  'q842iQAAAABJRU5ErkJggg==',
);

void main() {
  late Directory tmp;
  late DriveService drive;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hardstreet_scroll_test');
    drive = DriveService.testRoot(tmp);
    await drive.createFolder('SesionPrevia');
    for (final n in ['uno.png', 'dos.png']) {
      final f = File([tmp.path, n].join('/'))..writeAsBytesSync(_png);
      await drive.uploadFromPaths([f.path]);
    }
    // La carpeta destino TIENE que tener "targets": con la carpeta vacía el
    // nuevo contenido sería un EmptyState y nunca habría dos scroll views
    // enganchados al mismo controlador durante la transición.
    await drive.openPath(const ['SesionPrevia']);
    final inside = File([tmp.path, 'SesionPrevia', 'adentro.png'].join('/'))
      ..writeAsBytesSync(_png);
    await drive.uploadFromPaths([inside.path]);
    await drive.openPath(const []);
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

  testWidgets(
      'entrar a una carpeta con la transición NO truena el ScrollController '
      '(attached to multiple scroll views)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DrivePage(drive: drive))),
    );
    await settle(tester);
    expect(find.text('uno.png'), findsOneWidget);
    expect(find.text('SesionPrevia'), findsOneWidget);

    // Al cambiar de carpeta el AnimatedSwitcher mantiene un instante la vista
    // ANTERIOR y la NUEVA enganchadas al MISMO ScrollController. Antes del
    // arreglo, leer `.offset` con dos adjuntos lanzaba la excepción del
    // framework justo "al cargar los targets".
    await drive.openFolder('SesionPrevia');
    await tester.pump(); // monta la vista nueva (dos scroll views a la vez)
    await tester.pump(const Duration(milliseconds: 80)); // a mitad de transición

    expect(tester.takeException(), isNull);
    expect(find.text('adentro.png'), findsOneWidget);

    await settle(tester);
    expect(drive.path, ['SesionPrevia']);
  });
}

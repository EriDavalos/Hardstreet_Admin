import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';
import 'package:hardstreet_admin/widgets/anim.dart';

/// PNG 1x1 válido: se puede decodificar de verdad.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/'
  'q842iQAAAABJRU5ErkJggg==',
);

void main() {
  late Directory tmp;
  late Directory src;
  late DriveService drive;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hardstreet_live_test');
    src = await Directory.systemTemp.createTemp('hardstreet_live_src');
    drive = DriveService.testRoot(tmp);
  });

  tearDown(() async {
    // En Windows el archivo recién copiado puede seguir tomado un instante:
    // el temporal es prescindible, así que un fallo al borrar no rompe nada.
    for (final d in [tmp, src]) {
      try {
        if (await d.exists()) await d.delete(recursive: true);
      } catch (_) {}
    }
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('la foto recién subida entra ya puesta, con su miniatura',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DrivePage(drive: drive))),
    );
    await settle(tester);

    final origen = File([src.path, 'nueva.png'].join('/'))
      ..writeAsBytesSync(_png);

    // Subida real (I/O fuera de la zona de tiempo simulado).
    await tester.runAsync(() async {
      await drive.uploadFromPaths([origen.path]);
      // Sin el panel de subidas los textos se duplicarían en el árbol.
      drive.clearFinishedUploads();
    });
    await settle(tester);

    // 1. La foto ya está en la cuadrícula.
    expect(find.text('nueva.png'), findsOneWidget);

    // 2. Y con su imagen, no un hueco: se pinta el archivo recién guardado.
    final thumbs = find.byWidgetPredicate((w) =>
        w is Image &&
        w.image is FileImage &&
        (w.image as FileImage).file.path.endsWith('nueva.png'));
    expect(thumbs, findsOneWidget);

    // 3. Nada de animación de entrada para lo que llega por una subida:
    //    la única animación es la de la imagen al bajar (y la de deslizar).
    final reveals =
        tester.widgetList<ScrollReveal>(find.byType(ScrollReveal)).toList();
    expect(reveals.where((r) => r.animate), isEmpty);

    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
  });
}

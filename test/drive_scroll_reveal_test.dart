import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';
import 'package:hardstreet_admin/widgets/anim.dart';

/// PNG 1x1 válido.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/'
  'q842iQAAAABJRU5ErkJggg==',
);

void main() {
  late Directory tmp;
  late DriveService drive;

  // El sistema de archivos se prepara FUERA del test (setUp no vive en el
  // reloj simulado de testWidgets: ahí un await de I/O nunca termina).
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hardstreet_scroll_test');
    for (var i = 0; i < 60; i++) {
      File([tmp.path, 'foto_${i.toString().padLeft(3, '0')}.png'].join('/'))
          .writeAsBytesSync(_png);
    }
    drive = DriveService.testRoot(tmp);
  });

  tearDown(() async {
    try {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    } catch (_) {
      // El temporal es prescindible.
    }
  });

  testWidgets('las tarjetas animan su entrada solo al DESLIZAR hacia abajo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DrivePage(drive: drive))),
    );
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ScrollReveal), findsWidgets);

    // 1. Al abrir la carpeta (sin desplazarse) NADA anima: lo que ya está a la
    //    vista se pinta directo.
    final antes =
        tester.widgetList<ScrollReveal>(find.byType(ScrollReveal)).toList();
    expect(antes.where((r) => r.animate), isEmpty,
        reason: 'sin desplazamiento ninguna tarjeta debe animarse');

    // 2. Al bajar (rueda del ratón, la forma real en escritorio) las tarjetas
    //    que van apareciendo entran con animación.
    final grid = find.byType(GridView);
    final scrollable = tester.state<ScrollableState>(
        find.descendant(of: grid, matching: find.byType(Scrollable)));
    for (var k = 0; k < 4; k++) {
      await tester.sendEventToBinding(PointerScrollEvent(
        position: tester.getCenter(grid),
        scrollDelta: const Offset(0, 200),
      ));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(scrollable.position.pixels, greaterThan(0),
        reason: 'la lista tuvo que desplazarse');

    final despues =
        tester.widgetList<ScrollReveal>(find.byType(ScrollReveal)).toList();
    expect(despues.where((r) => r.animate), isNotEmpty,
        reason: 'lo que aparece al deslizar debe animar su entrada');

    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)));
  });
}

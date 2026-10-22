import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';

/// PNG 1x1 válido: los archivos del drive se pueden decodificar de verdad.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/'
  'q842iQAAAABJRU5ErkJggg==',
);

// ==================================================================
// DRIVE EN EL TELÉFONO: DESLIZAR SOBRE UNA FOTO SELECCIONA
// ==================================================================
// Sostener un elemento que NO estaba seleccionado y deslizar el dedo es el
// BARRIDO: se van seleccionando todos los elementos hasta el dedo (y la lista
// se desplaza sola al llegar al borde), como en una galería.
//
// Si el elemento YA estaba seleccionado, el arrastre es el de siempre: MUEVE
// la selección. En la computadora no cambia nada.
// ==================================================================

void main() {
  late Directory tmp;
  late Directory src;
  late DriveService drive;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hardstreet_sweep_test');
    // Los originales van FUERA del drive: si no, subirlos otra vez dentro de
    // su propia carpeta crearía copias «(1)».
    src = await Directory.systemTemp.createTemp('hardstreet_sweep_src');
    drive = DriveService.testRoot(tmp);
    for (final n in ['uno.png', 'dos.png', 'tres.png', 'cuatro.png']) {
      final f = File([src.path, n].join('/'))..writeAsBytesSync(_png);
      await drive.uploadFromPaths([f.path]);
    }
    drive.clearFinishedUploads();
  });

  tearDown(() async {
    for (final d in [tmp, src]) {
      if (await d.exists()) await d.delete(recursive: true);
    }
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Consume los avisos de dibujo que deja la fuente de las pruebas (Ahem es
  /// MUCHO más ancha que la real: en un ancho de teléfono el encabezado del
  /// Drive se sale unos píxeles). No tiene nada que ver con lo que se prueba
  /// aquí, el barrido de selección.
  void drain(WidgetTester tester) {
    Object? e;
    while ((e = tester.takeException()) != null) {
      if (!e.toString().contains('overflowed')) debugPrint('EXC: $e');
    }
  }

  Future<void> pumpPhone(WidgetTester tester) async {
    // Ancho de TELÉFONO (el corte del panel está en 620): la vista compacta,
    // que es donde el dedo arrastra y barre. Se fija en `tester.view` para que
    // MediaQuery (de donde sale hsIsPhone) vea el ancho de verdad.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DrivePage(drive: drive)),
      ),
    );
    await settle(tester);
    drain(tester);
  }

  /// Cuántos elementos dice la barra de selección que hay marcados.
  String? selectionCount(WidgetTester tester) {
    final finder = find.byKey(const ValueKey('selection-count'));
    if (finder.evaluate().isEmpty) return null;
    return tester.widget<Text>(finder).data;
  }

  testWidgets('sostener y deslizar sobre una foto SIN seleccionar selecciona '
      'todo lo que queda hasta el dedo', (tester) async {
    await pumpPhone(tester);
    final first = drive.visibleItems.first.name;
    expect(find.text(first), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text(first)),
      kind: PointerDeviceKind.touch,
    );
    // Se cumple la presión larga (350 ms) sin mover el dedo.
    await tester.pump(const Duration(milliseconds: 420));
    drain(tester);
    expect(
      selectionCount(tester),
      '1',
      reason: 'sostener selecciona el elemento que se está tocando',
    );

    // Se desliza hacia abajo, donde están las demás fotos.
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 60));
    await gesture.moveBy(const Offset(0, 160));
    await tester.pump(const Duration(milliseconds: 60));

    final afterDrag = int.parse(selectionCount(tester)!);
    expect(
      afterDrag,
      greaterThan(1),
      reason: 'deslizar sobre lo no seleccionado marca el rango',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    drain(tester);

    // Nada se movió: el arrastre solo marcaba.
    expect(find.textContaining('movido'), findsNothing);
  });

  testWidgets('sostener y deslizar sobre una foto YA seleccionada arrastra '
      'para mover', (tester) async {
    await pumpPhone(tester);
    final first = drive.visibleItems.first.name;
    final second = drive.visibleItems[1].name;

    // Sostener la primera la deja seleccionada (sin deslizar: no barre más).
    var hold = await tester.startGesture(
      tester.getCenter(find.text(first)),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 420));
    await hold.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    drain(tester);
    expect(selectionCount(tester), '1');

    // Y se agrega la segunda con un toque.
    await tester.tap(find.text(second));
    await settle(tester);
    drain(tester);
    expect(selectionCount(tester), '2');

    final gesture = await tester.startGesture(
      tester.getCenter(find.text(first)),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 420));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump(const Duration(milliseconds: 60));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump(const Duration(milliseconds: 60));
    drain(tester);

    // Se levanta la SELECCIÓN (no se barre): el globo dice cuántos van.
    expect(
      find.text('2 elementos'),
      findsOneWidget,
      reason: 'arrastrar algo ya seleccionado mueve la selección',
    );
    expect(selectionCount(tester), '2');

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    drain(tester);
    expect(selectionCount(tester), '2');
  });
}

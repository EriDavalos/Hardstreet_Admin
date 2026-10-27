import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';

// ==================================================================
// ESCRITORIO: UN CLIC NO DEBE MOVER EL SCROLL
// ==================================================================
// Al hacer clic en una tarjeta (o en la zona vacía) la lista se desplazaba
// sola hacia abajo, como si se hubiera pulsado «bajar»: el clic dejaba el foco
// en la tarjeta y el framework hacía `showOnScreen` para «revelarla», así que
// la vista brincaba.
//
// Va en su propio archivo: el gesto de ratón deja el puntero encima de la vista
// y mezclarlo con otras pruebas de ratón del mismo archivo desestabiliza el
// runner (se cuelga en la siguiente).
// ==================================================================

/// PNG 1x1 válido.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/'
  'q842iQAAAABJRU5ErkJggg==',
);

void main() {
  late Directory tmp;
  late DriveService drive;

  // Los archivos se escriben ANTES de abrir el drive (el servicio lista al
  // construirse).
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hardstreet_scroll_click');
    for (var i = 0; i < 60; i++) {
      File([tmp.path, 'foto_${i.toString().padLeft(3, '0')}.png'].join('/'))
          .writeAsBytesSync(_png);
    }
    drive = DriveService.testRoot(tmp);
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

  Future<ScrollableState> open(WidgetTester tester, {bool grid = true}) async {
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrivePage(drive: drive, initialGrid: grid),
        ),
      ),
    );
    await settle(tester);
    final list = find.byType(grid ? GridView : ListView);
    return tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
  }

  /// Rueda del ratón: la forma normal de bajar en escritorio.
  Future<void> wheel(
    WidgetTester tester,
    double dy, {
    int times = 1,
    Finder? over,
  }) async {
    final target = over ?? find.byType(GridView);
    for (var k = 0; k < times; k++) {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(target),
          scrollDelta: Offset(0, dy),
        ),
      );
      await tester.pump();
    }
    await settle(tester);
  }

  /// La tarjeta del archivo [name] (llevan `GlobalKey` con su nombre).
  Finder cardOf(String name) => find.byWidgetPredicate(
    (w) => w.key != null && w.key.toString().contains('grid-$name'),
  );

  /// Las tarjetas que se ven ahora, con su rectángulo en pantalla.
  List<(String, Rect)> cards(WidgetTester tester) => [
    for (var i = 0; i < 60; i++)
      if (cardOf('foto_${i.toString().padLeft(3, '0')}.png')
          .evaluate()
          .isNotEmpty)
        (
          'foto_${i.toString().padLeft(3, '0')}.png',
          tester.getRect(cardOf('foto_${i.toString().padLeft(3, '0')}.png')),
        ),
  ];

  /// ¿El clic llegó? (con el ratón, pulsar una tarjeta la SELECCIONA: la barra
  /// de selección aparece abajo). Sin esto, una prueba que «no se mueve» no
  /// demuestra nada: podría ser que el clic no llegara a ninguna parte.
  void expectSelected(WidgetTester tester) {
    expect(
      find.textContaining('seleccionado'),
      findsWidgets,
      reason: 'el clic tiene que haber seleccionado la tarjeta',
    );
  }

  testWidgets('clic en una tarjeta ENTERA y visible NO mueve el scroll', (
    tester,
  ) async {
    final scrollable = await open(tester);
    // Baja media fila, para que queden tarjetas recortadas por abajo.
    await wheel(tester, 130);

    final before = scrollable.position.pixels;
    expect(before, greaterThan(0), reason: 'la lista tuvo que bajar');

    final grid = tester.getRect(find.byType(GridView));
    final middle = cards(tester).where((c) {
      final r = c.$2;
      return r.top > grid.top + 40 && r.bottom < grid.bottom - 40;
    });
    expect(middle, isNotEmpty, reason: 'tiene que haber tarjetas enteras');

    await tester.tapAt(middle.first.$2.center, kind: PointerDeviceKind.mouse);
    await settle(tester);
    expectSelected(tester);

    expect(
      scrollable.position.pixels,
      closeTo(before, .5),
      reason: 'el clic no puede desplazar la lista (antes: $before)',
    );
  });

  testWidgets('clic en una tarjeta RECORTADA por el borde NO mueve el scroll', (
    tester,
  ) async {
    final scrollable = await open(tester);
    await wheel(tester, 130);

    final before = scrollable.position.pixels;
    final grid = tester.getRect(find.byType(GridView));

    // La tarjeta que asoma por abajo (recortada por el borde de la lista): es
    // la que antes «se revelaba» sola y hacía saltar la vista.
    final cut = cards(tester).where((c) {
      final r = c.$2;
      return r.top < grid.bottom - 8 && r.bottom > grid.bottom + 8;
    });
    expect(cut, isNotEmpty, reason: 'tiene que haber una tarjeta a medias');
    final r = cut.first.$2;

    // Clic DENTRO de la parte visible (arriba del borde de la lista).
    await tester.tapAt(
      Offset(r.center.dx, r.top + 24),
      kind: PointerDeviceKind.mouse,
    );
    await settle(tester);
    expectSelected(tester);

    expect(
      scrollable.position.pixels,
      closeTo(before, .5),
      reason: 'un clic en el borde no puede bajar la lista (antes: $before)',
    );
  });

  testWidgets('en la VISTA DE LISTA un clic tampoco mueve el scroll', (
    tester,
  ) async {
    final scrollable = await open(tester, grid: false);
    await wheel(tester, 130, over: find.byType(ListView));

    final before = scrollable.position.pixels;
    final list = tester.getRect(find.byType(ListView));
    // Una fila que se ve ENTERA, en medio de la lista.
    final rows = tester
        .widgetList<Text>(find.textContaining('foto_'))
        .where((t) => t.data != null)
        .map((t) => tester.getRect(find.text(t.data!).first))
        .where(
          (r) =>
              r.top > list.top + 40 &&
              r.bottom < list.bottom - 40 &&
              r.height < 80,
        )
        .toList();
    expect(rows, isNotEmpty, reason: 'el listado muestra los nombres');

    await tester.tapAt(rows.first.center, kind: PointerDeviceKind.mouse);
    await settle(tester);

    expect(
      scrollable.position.pixels,
      closeTo(before, .5),
      reason: 'el clic no puede desplazar la lista (antes: $before)',
    );
  });

  testWidgets('clic en la ZONA VACÍA no mueve el scroll', (tester) async {
    final scrollable = await open(tester);
    await wheel(tester, 120, times: 3);

    final before = scrollable.position.pixels;
    final grid = tester.getRect(find.byType(GridView));

    // Zona vacía entre tarjetas o bajo la última fila: ahí arranca la
    // marquesina, no un salto de la lista.
    await tester.tapAt(
      Offset(grid.right - 220, grid.bottom - 12),
      kind: PointerDeviceKind.mouse,
    );
    await settle(tester);

    expect(
      scrollable.position.pixels,
      closeTo(before, .5),
      reason: 'la zona vacía tampoco mueve la lista (antes: $before)',
    );
    expect(tester.takeException(), isNull);
  });
}

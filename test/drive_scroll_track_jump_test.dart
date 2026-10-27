import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';
import 'package:hardstreet_admin/widgets/wheel_fix.dart';

// ==================================================================
// ESCRITORIO: EL CARRIL DE LA BARRA DE SCROLL SALTA AL PUNTO CLICADO
// ==================================================================
// Flutter (como la barra de Windows) AVANZA UNA PANTALLA hacia el lado en el
// que se hace clic en el carril: se siente como «le di para bajar» en vez de
// «ir a ese punto». El Drive pone una franja sobre el carril que gana el clic
// y salta justo ahí (ver `ScrollTrackJump`).
//
// Aquí se comprueba de verdad, con la barra que pinta Material en escritorio:
//  1. el clic deja la lista en el punto clicado (y NO una pantalla más abajo),
//  2. el clic al final del carril lleva al final de la lista,
//  3. el pulgar se sigue ARRASTRANDO como siempre.
//
// Va en su propio archivo: el gesto de ratón deja el puntero encima de la
// vista y mezclarlo con otras pruebas de ratón del mismo archivo desestabiliza
// el runner (se cuelga en la siguiente).
// ==================================================================

/// PNG 1x1 válido.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/'
  'q842iQAAAABJRU5ErkJggg==',
);

void main() {
  late Directory tmp;
  late DriveService drive;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hardstreet_track_jump');
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

  Future<ScrollPosition> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        // ESCRITORIO: es la única forma de que Material ponga la barra de
        // scroll (en Android/iOS no hay carril que saltar).
        theme: ThemeData(platform: TargetPlatform.windows),
        // El mismo comportamiento de scroll que la app.
        scrollBehavior: const HsScrollBehavior(),
        home: Scaffold(body: DrivePage(drive: drive)),
      ),
    );
    await settle(tester);
    return tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(GridView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
  }

  /// Rueda del ratón: la forma normal de bajar en escritorio (y lo que hace
  /// que la barra aparezca).
  Future<void> wheel(WidgetTester tester, double dy) async {
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(GridView)),
        scrollDelta: Offset(0, dy),
      ),
    );
    await settle(tester);
  }

  /// Área de la lista (el carril vive pegado a su borde derecho).
  Rect area(WidgetTester tester) => tester.getRect(find.byType(GridView));

  /// Punto del carril a la altura [fraction] (0 = arriba, 1 = abajo).
  Offset track(WidgetTester tester, double fraction) {
    final r = area(tester);
    // El carril ocupa los ÚLTIMOS píxeles del área: se apunta a su centro.
    return Offset(r.right - 6, r.top + r.height * fraction);
  }

  /// Un clic del ratón en [at], con el puntero ya encima (como un usuario que
  /// lleva el ratón a la barra): así la barra está visible y su propio carril
  /// también atendería el clic si nadie lo interceptara.
  Future<void> clickTrack(WidgetTester tester, Offset at) async {
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(at));
    await tester.pump(const Duration(milliseconds: 320));
    await tester.sendEventToBinding(mouse.down(at));
    await tester.sendEventToBinding(mouse.up());
    await settle(tester);
  }

  testWidgets('clic en el carril salta AL PUNTO clicado (no una pantalla)', (
    tester,
  ) async {
    final position = await open(tester);
    // Se baja un poco con la rueda: el pulgar queda arriba del todo, así que
    // el clic de más abajo es claramente «ir hacia allí».
    await wheel(tester, 140);
    final before = position.pixels;
    expect(before, greaterThan(0), reason: 'la lista tuvo que bajar');

    final max = position.maxScrollExtent;
    expect(max, greaterThan(2 * position.viewportDimension));

    final at = track(tester, .6);
    await clickTrack(tester, at);

    // Dónde caería el clic como FRACCIÓN del área (lo que se apuntó).
    final r = area(tester);
    final wanted = ((at.dy - r.top) / r.height) * max;
    expect(
      position.pixels,
      closeTo(wanted, max * .06),
      reason:
          'el clic tiene que dejar la lista EN ESE PUNTO '
          '(quedó en ${position.pixels} de $max, se apuntó a $wanted)',
    );
    // Y lo que NO puede pasar: avanzar solo una pantalla (lo de antes).
    expect(
      position.pixels,
      greaterThan(before + position.viewportDimension * 1.5),
      reason: 'un clic no puede ser «una pantalla más»',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('clic al final del carril lleva al final de la lista', (
    tester,
  ) async {
    final position = await open(tester);
    final max = position.maxScrollExtent;

    await clickTrack(tester, track(tester, .99));

    expect(position.pixels, closeTo(max, 1.0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('el pulgar se sigue ARRASTRANDO', (tester) async {
    final position = await open(tester);
    await wheel(tester, 140);
    final before = position.pixels;
    final r = area(tester);

    // Dónde está el pulgar: su centro, con la misma cuenta que pinta Material
    // (largo visible de la lista sobre el total).
    final viewport = position.viewportDimension;
    final content = position.maxScrollExtent + viewport;
    final thumb = math.max(18.0, viewport * viewport / content);
    final start = (before / position.maxScrollExtent) * (viewport - thumb);
    final thumbCenter = Offset(r.right - 6, r.top + start + thumb / 2);

    final mouse = TestPointer(2, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(thumbCenter));
    await tester.pump(const Duration(milliseconds: 320));
    await tester.sendEventToBinding(mouse.down(thumbCenter));
    await tester.pump(const Duration(milliseconds: 40));
    // Arrastrar el pulgar mueve la lista (nadie se queda el gesto).
    await tester.sendEventToBinding(mouse.move(thumbCenter + Offset(0, 90)));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.sendEventToBinding(mouse.up());
    await settle(tester);

    expect(
      position.pixels,
      greaterThan(before + 20),
      reason: 'arrastrar el pulgar tiene que bajar la lista',
    );
    expect(tester.takeException(), isNull);
  });
}

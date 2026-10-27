import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ==================================================================
// POR QUÉ EL CARRIL DEL DRIVE YA NO AVANZA UNA PANTALLA
// ==================================================================
// `ScrollTrackJump` NO toca la barra de scroll: pone una franja encima del
// carril con su propio detector. Lo que hace que el avance por pantalla del
// scrollbar no llegue a dispararse es el ORDEN de la arena de gestos: la
// franja va ARRIBA en el Stack (y `translucent`, para no tapar nada) y entra
// ANTES en la arena, así que al soltar el dedo el clic es suyo y el
// reconocedor del carril queda rechazado.
//
// Esta prueba protege ESE supuesto (hit test de arriba a abajo + arena «gana
// el primero que entró»): si una versión de Flutter lo cambiara, el carril
// volvería a avanzar una pantalla y aquí se vería el motivo.
// ==================================================================

void main() {
  testWidgets('la franja de arriba se queda el clic del contenido de abajo', (
    tester,
  ) async {
    var band = 0;
    var below = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              // Lo de abajo: el scrollable, con SU propio detector (como la
              // barra de scroll, que vive dentro del contenido).
              GestureDetector(
                onTap: () => below++,
                child: const SizedBox.expand(
                  child: ColoredBox(color: Colors.white),
                ),
              ),
              // La franja: arriba y `translucent` (ver `_TrackTap`).
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 12,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (_) => band++,
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final area = tester.getRect(find.byType(Stack).first);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    final at = Offset(area.right - 6, area.top + 100);
    await tester.sendEventToBinding(mouse.down(at));
    await tester.sendEventToBinding(mouse.up());
    await tester.pump();

    expect(band, 1, reason: 'la franja tiene que atender el clic del carril');
    expect(
      below,
      0,
      reason: 'el detector de abajo no puede quedarse el clic de la franja',
    );
  });
}

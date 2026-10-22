import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/app_platform.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';

// ==================================================================
// DRIVE EN EL CELULAR: SCROLLEAR NO ARRASTRA CARPETAS
// ==================================================================
// Las tarjetas del Drive se arrastran con [PressMoveDraggable]: hay que
// MANTENER presionado y luego mover el dedo. El gesto reconocía la presión a
// los 350 ms pasara lo que pasara, así que un scroll lento (el dedo se mueve
// unos píxeles, se detiene un instante y sigue) se convertía en un ARRASTRE:
// la carpeta se despegaba y seguía al dedo en vez de bajar la lista. Eso es
// el "al scrollear las carpetas se mueven".
//
// Además, en el TELÉFONO (la app o la web abierta en él) el arrastre SOLO
// MUEVE lo que YA estaba seleccionado. Sostener algo sin seleccionar y
// deslizar es el BARRIDO de selección (se marcan todos los elementos hasta el
// dedo y la lista se desplaza sola al llegar al borde).
//
// Aquí se ejercita el gesto sobre una lista de tarjetas de verdad (sin el
// resto del panel): scrollear tiene que mover la LISTA y no arrastrar.
// ==================================================================

Widget _harness() {
  return MaterialApp(
    home: Scaffold(
      body: ListView.builder(
        itemCount: 30,
        itemBuilder: (context, i) => PressMoveDraggable<String>(
          data: 'item-$i',
          delay: const Duration(milliseconds: 350),
          feedback: Text('Arrastrando $i'),
          child: SizedBox(
            height: 100,
            child: Center(child: Text('carpeta $i')),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('en el TELÉFONO solo arrastra lo que YA estaba seleccionado', () {
    expect(
      driveCardDragAllowed(phone: true, selected: false),
      isFalse,
      reason: 'sostener algo sin seleccionar y deslizar es SELECCIONAR',
    );
    // Ya seleccionado: el arrastre mueve, como siempre.
    expect(driveCardDragAllowed(phone: true, selected: true), isTrue);
    // En la computadora el arrastre es inmediato y sin condiciones.
    expect(driveCardDragAllowed(phone: false, selected: false), isTrue);
  });

  testWidgets('scrollear NO levanta la tarjeta', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    final position = tester
        .state<ScrollableState>(
          find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .first,
        )
        .position;
    expect(position.pixels, 0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('carpeta 0')),
    );
    // Primeros píxeles: el dedo EMPIEZA a bajar la lista (dentro del slop).
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.moveBy(const Offset(0, -6));
    // Se cumple el tiempo de "presión larga" con el dedo ya movido.
    await tester.pump(const Duration(milliseconds: 400));
    // Y el scroll continúa.
    await gesture.moveBy(const Offset(0, -140));
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      position.pixels,
      greaterThan(0),
      reason: 'el gesto era un scroll: la lista se desplaza',
    );
    expect(
      find.textContaining('Arrastrando'),
      findsNothing,
      reason: 'una tarjeta no puede despegarse mientras se scrollea',
    );
    expect(tester.takeException(), isNull);
  });
}

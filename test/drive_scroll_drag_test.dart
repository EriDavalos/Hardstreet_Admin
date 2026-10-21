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
// Además, en la WEB abierta en un TELÉFONO no se arrastra NADA: el dedo está
// para scrollear. Mover/copiar se hacen desde las acciones de la selección.
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
  test('en la WEB de un teléfono las tarjetas NO se arrastran', () {
    expect(
      driveCardDragAllowed(web: true, phone: true),
      isFalse,
      reason: 'el dedo está para scrollear, no para mover carpetas',
    );
    // El mouse de la computadora sigue arrastrando con normalidad.
    expect(driveCardDragAllowed(web: true, phone: false), isTrue);
    // La app móvil conserva su arrastre (con presión larga).
    expect(driveCardDragAllowed(web: false, phone: true), isTrue);
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

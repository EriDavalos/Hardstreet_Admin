import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/widgets/form_dialog.dart';
import 'package:hardstreet_admin/widgets/hs_modal.dart';

/// Anfitrión con un botón que abre un modal (simple o de formulario).
Widget _host({bool form = false}) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showHsModal<void>(
                context: ctx,
                builder: (inner) => form
                    ? FormDialog(
                        icon: Icons.person_outline,
                        title: 'Nuevo cliente',
                        saveLabel: 'Guardar',
                        onCancel: () => Navigator.pop(inner),
                        onSave: () => Navigator.pop(inner),
                        children: const [
                          Text('Nombre'),
                          SizedBox(height: 600),
                          Text('Notas'),
                        ],
                      )
                    : AlertDialog(
                        title: const Text('Título del modal'),
                        content: const Text('Contenido'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(inner),
                            child: const Text('Cancelar'),
                          ),
                        ],
                      ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );

/// La superficie del diálogo (su Material, no los márgenes transparentes del
/// route, que siempre ocupan la pantalla entera).
Rect _card(WidgetTester tester) => tester.getRect(
      find
          .descendant(
              of: find.byType(AlertDialog), matching: find.byType(Material))
          .first,
    );

Future<void> _setSize(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  // En pruebas, MediaQuery NO sigue al tamaño de la superficie: hay que
  // declarar la vista para que el modal vea la MISMA ventana que dibuja.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('móvil: el modal ocupa TODA la pantalla', (tester) async {
    await _setSize(tester, const Size(390, 844));
    await tester.pumpWidget(_host());
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Título del modal'), findsOneWidget);
    // La superficie del diálogo (su Material) cubre TODA la pantalla.
    expect(_card(tester).size, const Size(390, 844));
    // Sin márgenes: el contenido arranca pegado al borde de la pantalla.
    expect(
      tester.getTopLeft(find.text('Título del modal')).dx,
      lessThan(60),
      reason: 'no es una tarjeta centrada',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('móvil: el formulario es pantalla completa con las acciones al pie',
      (tester) async {
    await _setSize(tester, const Size(390, 844));
    await tester.pumpWidget(_host(form: true));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Nuevo cliente'), findsOneWidget);
    expect(
      tester.getRect(find.byType(FormDialog)).size,
      const Size(390, 844),
    );
    // El contenido es largo: el botón de guardar sigue anclado abajo (no se
    // va con el scroll) y el encabezado sigue arriba.
    expect(tester.getCenter(find.text('Guardar')).dy, greaterThan(700));
    expect(tester.getCenter(find.text('Nuevo cliente')).dy, lessThan(120));
    expect(tester.takeException(), isNull);
  });

  testWidgets('computadora: el modal sigue siendo un diálogo flotante',
      (tester) async {
    await _setSize(tester, const Size(1280, 860));
    await tester.pumpWidget(_host());
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    // Sigue siendo una tarjeta del tamaño de su contenido, centrada.
    final card = _card(tester);
    expect(card.width, lessThan(1280));
    expect(card.height, lessThan(860));
    expect(
      tester.getTopLeft(find.text('Título del modal')).dx,
      greaterThan(200),
      reason: 'el diálogo queda centrado',
    );
    expect(tester.takeException(), isNull);
  });
}

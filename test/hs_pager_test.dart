import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardstreet_admin/widgets/hs_pager.dart';

// ==================================================================
// PAGINACIÓN de los listados del panel
// ==================================================================
// Comprueba la cuenta de páginas/filas y que la barra:
//   * arranca en 30 filas por página (y ofrece 50, 100 y 200);
//   * deshabilita "anterior" en la primera página y "siguiente" en la última;
//   * avisa al listado cuando se cambia de página o de tamaño;
//   * se adapta al celular (rótulo "Página X de Y") y al escritorio.
// ==================================================================

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('HsPages', () {
    test('30 filas de fábrica y cuenta de páginas', () {
      const hs = HsPages(total: 61);
      expect(hs.pageSize, 30);
      expect(hs.pages, 3);
      expect(hs.first, 1);
      expect(hs.last, 30);
      expect(hs.canPrev, isFalse);
      expect(hs.canNext, isTrue);
    });

    test('recorta la página actual y arma el rótulo de la última', () {
      const hs = HsPages(total: 61, page: 9, pageSize: 30);
      expect(hs.current, 3); // no existe la 9: se queda en la última
      expect(hs.first, 61);
      expect(hs.last, 61);
      expect(hs.canNext, isFalse);
    });

    test('slice() devuelve solo las filas de la página', () {
      final rows = List.generate(75, (i) => i);
      const hs = HsPages(total: 75, page: 2, pageSize: 30);
      expect(hs.slice(rows), rows.sublist(30, 60));
      // Cambiar a 200 deja todo en una sola página.
      const big = HsPages(total: 75, pageSize: 200);
      expect(big.pages, 1);
      expect(big.slice(rows).length, 75);
    });

    test('lista vacía: una página, sin botones activos', () {
      const hs = HsPages(total: 0);
      expect(hs.pages, 1);
      expect(hs.first, 0);
      expect(hs.last, 0);
      expect(hs.canPrev, isFalse);
      expect(hs.canNext, isFalse);
      expect(hs.slice(const <int>[1]), isEmpty);
    });
  });

  group('HsPager', () {
    testWidgets('en la primera página "anterior" está deshabilitado', (
      tester,
    ) async {
      var page = 1;
      var size = 30;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (ctx, setState) => HsPager(
              total: 100,
              page: page,
              pageSize: size,
              onPage: (p) => setState(() => page = p),
              onPageSize: (n) => setState(() => size = n),
            ),
          ),
        ),
      );

      expect(find.text('1–30 de 100'), findsOneWidget);
      expect(find.text('30 por página'), findsOneWidget);

      // El botón de atrás no hace nada en la primera página.
      await tester.tap(find.byKey(const ValueKey('hs-pager-prev')));
      await tester.pump();
      expect(page, 1);

      // El de adelante sí.
      await tester.tap(find.byKey(const ValueKey('hs-pager-next')));
      await tester.pump();
      expect(page, 2);
      expect(find.text('31–60 de 100'), findsOneWidget);
    });

    testWidgets('en la última página "siguiente" está deshabilitado', (
      tester,
    ) async {
      var page = 4;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (ctx, setState) => HsPager(
              total: 100,
              page: page,
              pageSize: 30,
              onPage: (p) => setState(() => page = p),
              onPageSize: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('91–100 de 100'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hs-pager-next')));
      await tester.pump();
      expect(page, 4, reason: 'ya no hay página 5');
    });

    testWidgets('el selector ofrece 30, 50, 100 y 200', (tester) async {
      var size = 30;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (ctx, setState) => HsPager(
              total: 400,
              page: 1,
              pageSize: size,
              onPage: (_) {},
              onPageSize: (n) => setState(() => size = n),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('hs-pager-size')));
      await tester.pumpAndSettle();
      expect(find.text('50 filas'), findsOneWidget);
      expect(find.text('100 filas'), findsOneWidget);
      expect(find.text('200 filas'), findsOneWidget);

      await tester.tap(find.text('50 filas'));
      await tester.pumpAndSettle();
      expect(size, 50);
      expect(find.text('50 por página'), findsOneWidget);
      expect(find.text('1–50 de 400'), findsOneWidget);
    });

    testWidgets('en el celular muestra "Página X de Y" y no los números', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          HsPager(
            total: 200,
            page: 2,
            pageSize: 30,
            onPage: (_) {},
            onPageSize: (_) {},
          ),
        ),
      );
      expect(find.text('Página 2 de 7'), findsOneWidget);
      expect(find.byKey(const ValueKey('hs-pager-num-1')), findsNothing);
      // TODO en UNA fila al pie: nada de resumen arriba (ocupaba alto) y el
      // selector de tamaño a la vista, en compacto.
      expect(find.textContaining('de 200'), findsNothing);
      expect(find.text('30'), findsOneWidget);
      final label = tester.getRect(find.text('Página 2 de 7'));
      final size = tester.getRect(find.byKey(const ValueKey('hs-pager-size')));
      expect(size.center.dy, closeTo(label.center.dy, 8),
          reason: 'el tamaño va en la MISMA fila que las flechas');
    });
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/widgets/hero_photo_banner.dart';

/// Pinta una "foto" de tamaño fijo (10x10): si el banner la deja así,
/// significaría que la foto NO llena el banner. El banner debe estirarla.
Widget _photo(BuildContext context, String url) =>
    SizedBox(width: 10, height: 10, key: ValueKey('photo-$url'));

Future<void> _pump(
  WidgetTester tester, {
  required List<String> photos,
  Duration every = const Duration(seconds: 1),
  Duration fade = const Duration(milliseconds: 100),
  Future<void> Function(String url)? preload,
  ValueChanged<String>? onPhoto,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          height: 200,
          child: HeroPhotoBanner(
            photos: photos,
            builder: _photo,
            every: every,
            fade: fade,
            preload: preload,
            onPhoto: onPhoto,
          ),
        ),
      ),
    ),
  );
}

/// Fundidos que hay AHORA mismo DENTRO del banner (los de la ruta de
/// MaterialApp no cuentan).
Finder _fades() => find.descendant(
  of: find.byType(HeroPhotoBanner),
  matching: find.byType(FadeTransition),
);

/// Opacidades de esos fundidos.
List<double> _fadeOpacities(WidgetTester tester) => [
  for (final f in tester.widgetList<FadeTransition>(_fades())) f.opacity.value,
];

void main() {
  testWidgets('cada foto llena TODO el banner (vertical u horizontal)', (
    tester,
  ) async {
    await _pump(tester, photos: const ['vertical.jpg']);
    expect(
      tester.getSize(find.byKey(const ValueKey('photo-vertical.jpg'))),
      const Size(400, 200),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('al cambiar de foto la anterior sigue opaca: no hay hueco', (
    tester,
  ) async {
    await _pump(tester, photos: const ['a.jpg', 'b.jpg']);
    // Arriba ya está la capa que entrará, pero invisible: se ve la primera.
    expect(find.byKey(const ValueKey('photo-b.jpg')), findsNothing);
    expect(_fadeOpacities(tester), [0.0]);
    expect(
      tester.getSize(find.byKey(const ValueKey('photo-a.jpg')).first),
      const Size(400, 200),
    );

    // Pasa el tiempo: entra la segunda foto.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(const ValueKey('photo-a.jpg')), findsOneWidget);
    expect(find.byKey(const ValueKey('photo-b.jpg')), findsOneWidget);
    // Solo la que ENTRA está fundida; la anterior está completa (opaca).
    final opacities = _fadeOpacities(tester);
    expect(opacities, hasLength(1));
    expect(opacities.single, greaterThan(0));
    expect(opacities.single, lessThan(1));
    expect(
      tester.getSize(find.byKey(const ValueKey('photo-a.jpg')).first),
      const Size(400, 200),
    );

    // Termina el fundido: la nueva queda visible y abajo también al día.
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();
    expect(_fadeOpacities(tester), [1.0]);
    expect(find.byKey(const ValueKey('photo-b.jpg')), findsNWidgets(2));
    expect(
      tester.getSize(find.byKey(const ValueKey('photo-b.jpg')).first),
      const Size(400, 200),
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sin fotos se ve la foto del paquete (respaldo)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 200,
            child: HeroPhotoBanner(
              photos: const [],
              builder: _photo,
              background: const ColoredBox(
                key: ValueKey('respaldo'),
                color: Colors.blue,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('respaldo')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('respaldo'))),
      const Size(400, 200),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('con una sola foto no se mueve nada', (tester) async {
    await _pump(tester, photos: const ['sola.jpg']);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('photo-sola.jpg')), findsOneWidget);
    expect(_fades(), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('otra ronda de fotos vuelve a empezar por la primera', (
    tester,
  ) async {
    await _pump(tester, photos: const ['a.jpg', 'b.jpg']);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('photo-b.jpg')), findsWidgets);

    // El padre entrega una lista NUEVA (misma identidad no, mismo contenido).
    await _pump(tester, photos: const ['x.jpg', 'y.jpg']);
    // Otra ronda: se ve la primera y la capa de arriba queda vacía (invisible).
    expect(find.byKey(const ValueKey('photo-x.jpg')), findsNWidgets(2));
    expect(find.byKey(const ValueKey('photo-y.jpg')), findsNothing);
    expect(_fadeOpacities(tester), [0.0]);

    await tester.pumpWidget(const SizedBox());
  });

  // FUNDIDO SIN FOTO: si la imagen tarda en llegar (la red va lenta), el
  // banner NO debe fundir a un hueco ni enseñar la foto de golpe. Espera a
  // tenerla descargada y entonces la funde; si no llega, sigue la anterior.
  group('con precarga de fotos', () {
    testWidgets('la primera foto también entra con fundido, cuando ya llegó', (
      tester,
    ) async {
      final pending = Completer<void>();
      await _pump(
        tester,
        photos: const ['a.jpg', 'b.jpg'],
        preload: (url) => pending.future,
      );
      // Aún bajando: no se funde nada (se ve la foto del paquete de abajo).
      expect(_fadeOpacities(tester), [0.0]);

      pending.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(_fadeOpacities(tester).single, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_fadeOpacities(tester), [1.0]);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('el cambio espera a que la foto nueva esté lista', (
      tester,
    ) async {
      final pending = <String, Completer<void>>{
        'a.jpg': Completer<void>(),
        'b.jpg': Completer<void>(),
      };
      await _pump(
        tester,
        photos: const ['a.jpg', 'b.jpg'],
        preload: (url) => pending[url]!.future,
      );
      pending['a.jpg']!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(_fadeOpacities(tester), [1.0]);

      // Toca el cambio, pero 'b' todavía no ha bajado: se sigue viendo 'a'.
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('photo-b.jpg')), findsNothing);
      expect(_fadeOpacities(tester), [1.0]);

      // Llega la foto: ahora sí entra con su fundido.
      pending['b.jpg']!.complete();
      await tester.pump(); // el banner cambia de foto
      await tester.pump(); // arranca el fundido
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.byKey(const ValueKey('photo-b.jpg')), findsOneWidget);
      final opacity = _fadeOpacities(tester).single;
      expect(opacity, greaterThan(0));
      expect(opacity, lessThan(1));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('con una sola foto la entrada se funde (sin rotación)', (
      tester,
    ) async {
      final pending = Completer<void>();
      await _pump(
        tester,
        photos: const ['sola.jpg'],
        preload: (url) => pending.future,
      );
      expect(_fadeOpacities(tester), [0.0]);
      expect(find.byKey(const ValueKey('photo-sola.jpg')), findsOneWidget);

      pending.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_fadeOpacities(tester), [1.0]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('avisa qué foto se está viendo (para teñir el fondo)', (
      tester,
    ) async {
      final seen = <String>[];
      await _pump(
        tester,
        photos: const ['a.jpg', 'b.jpg'],
        preload: (url) async {},
        onPhoto: seen.add,
      );
      await tester.pump();
      expect(seen, ['a.jpg']);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(seen.last, 'b.jpg');
      await tester.pumpWidget(const SizedBox());
    });
  });
}

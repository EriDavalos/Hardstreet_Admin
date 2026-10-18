import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/widgets/brand_badge.dart';

// ==================================================================
// LA MARCA DE LA APP (barra lateral, login y pantalla de carga)
// ==================================================================
// Antes la marca era un icono de edificio dibujado con `Icons.apartment_rounded`
// en tres sitios distintos; ahora los tres enseñan el MISMO icono de la app
// (`assets/hs_icon.png`), que es el archivo con el que se generan los iconos de
// Windows, Android y el navegador. Aquí se revisa que la pieza use ese archivo
// y que el archivo EXISTA y esté declarado en pubspec (si no, en el equipo del
// usuario se vería el respaldo en vez del icono).
// ==================================================================

void main() {
  testWidgets('la marca dibuja el icono de la app (no un icono de edificio)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: BrandBadge(size: 64, radius: 20))),
      ),
    );
    await tester.pump();

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(1), reason: 'la marca es UNA imagen');
    final provider = images.single.image;
    expect(
      provider,
      isA<AssetImage>().having(
        (a) => a.assetName,
        'asset',
        BrandBadge.iconAsset,
      ),
    );
    // Nada de iconos de edificio: el icono ya no se dibuja.
    expect(find.byIcon(Icons.apartment_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('el icono existe y viaja en la app (declarado en pubspec)', () {
    expect(
      File(BrandBadge.iconAsset).existsSync(),
      isTrue,
      reason: 'falta ${BrandBadge.iconAsset}: la marca se vería de respaldo',
    );
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      pubspec,
      contains(BrandBadge.iconAsset),
      reason: 'el icono tiene que estar declarado en los assets de pubspec',
    );
  });
}

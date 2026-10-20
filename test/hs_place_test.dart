import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/hs_place.dart';
import 'package:hardstreet_admin/widgets/hs_place_picker.dart';

void main() {
  group('HsPlace (lugar de una agenda)', () {
    test('lee el nombre y las coordenadas de la agenda', () {
      final place = HsPlace.of({
        'location': 'Hacienda San José',
        'lat': 4.711,
        'lng': -74.072,
      });
      expect(place, isNotNull);
      expect(place!.name, 'Hacienda San José');
      expect(place.lat, 4.711);
      expect(place.lng, -74.072);
      expect(place.hasCoords, isTrue);
      expect(place.label, 'Hacienda San José');
    });

    test('acepta coordenadas como texto y claves alternativas', () {
      final place = HsPlace.of({
        'place': 'Salón Real',
        'latitude': '4.5',
        'longitude': '-74.1',
      });
      expect(place!.lat, 4.5);
      expect(place.lng, -74.1);
      expect(place.coordsLabel, '4.50000, -74.10000');
    });

    test('una agenda sin lugar devuelve null', () {
      expect(HsPlace.of({'location': '', 'lat': null, 'lng': null}), isNull);
      expect(HsPlace.of(const <String, dynamic>{}), isNull);
      expect(HsPlace.of(null), isNull);
    });

    test('sin nombre usa el punto del mapa como etiqueta', () {
      final place = HsPlace.of({'lat': 4.7, 'lng': -74.0});
      expect(place!.label, 'Ubicación en el mapa');
      expect(place.hasCoords, isTrue);
    });

    test('el cuerpo que va a la API lleva nombre, lat y lng', () {
      const place = HsPlace(name: '  Hacienda  ', lat: 1.5, lng: 2.5);
      expect(place.toBody(), {'location': 'Hacienda', 'lat': 1.5, 'lng': 2.5});
    });
  });

  testWidgets('HsPlaceField muestra el lugar y permite quitarlo', (
    tester,
  ) async {
    HsPlace? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HsPlaceField(
            place: const HsPlace(
              name: 'Hacienda San José',
              lat: 4.7,
              lng: -74.1,
            ),
            onChanged: (place) => changed = place,
          ),
        ),
      ),
    );

    expect(find.text('Hacienda San José'), findsOneWidget);
    expect(find.text('4.70000, -74.10000'), findsOneWidget);
    expect(find.text('Agregar lugar'), findsNothing);

    await tester.tap(find.byTooltip('Quitar lugar'));
    await tester.pump();

    expect(changed, isNull);
  });

  testWidgets('HsPlaceField sin lugar invita a agregarlo', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HsPlaceField(place: null, onChanged: (_) {})),
      ),
    );

    expect(find.text('Agregar lugar'), findsOneWidget);
    expect(
      find.text('Búscalo por nombre o márcalo en el mapa'),
      findsOneWidget,
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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

    test('lee TODAS las ubicaciones de la agenda, en orden', () {
      final places = HsPlace.allOf({
        'location': 'Hacienda San José',
        'lat': 4.711,
        'lng': -74.072,
        'locations': [
          {
            'position': 1,
            'location': 'Hacienda San José',
            'lat': 4.711,
            'lng': -74.072,
          },
          {
            'position': 2,
            'location': 'Salón Real',
            'lat': 4.8,
            'lng': -74.1,
          },
        ],
      });
      expect(places.map((p) => p.name), ['Hacienda San José', 'Salón Real']);
      expect(places[1].coordsLabel, '4.80000, -74.10000');
    });

    test('sin lista de ubicaciones cae al lugar único de la agenda', () {
      final places = HsPlace.allOf({'location': 'Salón Real'});
      expect(places, hasLength(1));
      expect(places.first.name, 'Salón Real');
      expect(HsPlace.allOf(null), isEmpty);
      expect(HsPlace.allOf(const <String, dynamic>{}), isEmpty);
    });

    test('el cuerpo de VARIAS ubicaciones descarta las vacías y conserva el '
        'orden', () {
      final body = HsPlace.listBody([
        const HsPlace(name: 'Hacienda', lat: 1, lng: 2),
        null,
        const HsPlace(name: '   '),
        const HsPlace(name: 'Salón', lat: 3, lng: 4),
      ]);
      expect(body['locations'], [
        {'location': 'Hacienda', 'lat': 1, 'lng': 2},
        {'location': 'Salón', 'lat': 3, 'lng': 4},
      ]);
      expect(HsPlace.listBody([null])['locations'], isEmpty);
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

  testWidgets('el mapa del detalle pinta TODOS los puntos, numerados', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 700,
              child: HsPlaceMapPreview(
                places: const [
                  HsPlace(
                    name: 'Hacienda San José',
                    lat: 4.711,
                    lng: -74.0721,
                  ),
                  // Sin coordenadas: no se pinta (pero conserva su número 2).
                  HsPlace(name: 'Salón Real'),
                  HsPlace(name: 'Casa', lat: 4.75, lng: -74.03),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Lugar 1: Hacienda San José'), findsOneWidget);
    expect(
      find.byTooltip('Lugar 3: Casa'),
      findsOneWidget,
      reason: 'El número es el de la agenda, no el del orden en el mapa',
    );

    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(
      map.options.initialCameraFit,
      isNotNull,
      reason: 'Con varios puntos, el encuadre los abre todos',
    );
    expect(
      map.options.interactionOptions.flags & InteractiveFlag.drag,
      isNot(0),
      reason: 'El mapa del detalle se puede mover',
    );
    expect(
      map.options.interactionOptions.flags & InteractiveFlag.pinchZoom,
      isNot(0),
      reason: 'Se puede acercar',
    );
    expect(
      tester.getSize(find.byType(HsPlaceMapPreview)).height,
      190,
      reason: 'Un poco más grande que el mini mapa anterior (132)',
    );
  });

  testWidgets('sin coordenadas el mapa del detalle no se pinta', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HsPlaceMapPreview(places: [HsPlace(name: 'Solo el nombre')]),
        ),
      ),
    );
    expect(find.byType(FlutterMap), findsNothing);
  });

  // En el celular el mapa "se movía solo": dos toques seguidos disparaban el
  // zoom de doble toque y el encuadre saltaba. Con el dedo, tocar debe marcar
  // (o no hacer nada) y arrastrar debe mover; acercar es con pinza o botones.
  testWidgets('el doble toque NO mueve el mapa del detalle', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 700,
              child: HsPlaceMapPreview(
                places: const [
                  HsPlace(
                    name: 'Hacienda San José',
                    lat: 4.711,
                    lng: -74.0721,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    MapCamera camera() =>
        MapCamera.of(tester.element(find.byType(MarkerLayer)));
    final before = camera();

    // El gesto completo, con la animación incluida (si el zoom de doble toque
    // estuviera activo, el mismo gesto sube el zoom: ver el control de mapa).
    final center = tester.getCenter(find.byType(FlutterMap));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(camera().zoom, before.zoom, reason: 'no se acerca de golpe');
    expect(camera().center, before.center, reason: 'no se mueve solo');
  });

  testWidgets('el mapa del detalle se ARRASTRA con el dedo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 700,
              child: HsPlaceMapPreview(
                places: const [
                  HsPlace(
                    name: 'Hacienda San José',
                    lat: 4.711,
                    lng: -74.0721,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    MapCamera camera() =>
        MapCamera.of(tester.element(find.byType(MarkerLayer)));
    final before = camera();

    // Arrastrar hacia la izquierda desplaza el mapa al ESTE (sube la longitud).
    await tester.drag(find.byType(FlutterMap), const Offset(-120, 0));
    await tester.pump();

    expect(camera().center.longitude, greaterThan(before.center.longitude));
  });

  testWidgets('al agregar otra ubicación el mapa muestra la ya marcada', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HsPlacesField(
              places: const [
                HsPlace(
                  name: 'Hacienda San José',
                  lat: 4.711,
                  lng: -74.0721,
                ),
                // La segunda todavía está vacía: al abrirla se ve la primera.
                null,
              ],
              onChanged: (_, _) {},
              onAdd: () {},
              onRemove: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Agregar lugar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Lugar del evento'), findsOneWidget);
    expect(
      find.byTooltip('Lugar 1: Hacienda San José'),
      findsOneWidget,
      reason: 'La ubicación ya marcada se ve en el mapa del selector',
    );
    expect(find.byType(FlutterMap), findsOneWidget);
  });
}

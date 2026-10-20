import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';

// ==================================================================
// BUSCAR LUGARES PARA LA AGENDA
// ==================================================================
// El endpoint del backend puede no estar desplegado todavía (responde 404).
// En ese caso la app busca DIRECTO en OpenStreetMap: el mapa tiene que seguir
// funcionando, no quedarse en "Error HTTP 404".
// ==================================================================

http.Response json(Object body, [int code = 200]) => http.Response(
  jsonEncode(body),
  code,
  headers: {'content-type': 'application/json'},
);

void main() {
  final urls = <String>[];

  setUp(() {
    urls.clear();
  });

  tearDown(() {
    HsApi.client = http.Client();
  });

  test('usa el backend cuando la ruta existe', () async {
    HsApi.client = MockClient((request) async {
      urls.add(request.url.toString());
      return json({
        'ok': true,
        'results': [
          {
            'name': 'Hacienda San José',
            'address': 'Hacienda San José, Cota, Colombia',
            'displayName': 'Hacienda San José, Cota, Colombia',
            'lat': 4.75,
            'lng': -74.15,
          },
        ],
      });
    });

    final places = await HsApi.searchPlaces('Hacienda San José');

    expect(places, hasLength(1));
    expect(places.first['name'], 'Hacienda San José');
    expect(places.first['lat'], 4.75);
    expect(urls.single, contains('/api/admin/geocode'));
  });

  test('si el backend responde 404, busca directo en OpenStreetMap', () async {
    HsApi.client = MockClient((request) async {
      urls.add(request.url.toString());
      final url = request.url;
      if (url.host == 'apihardstreet.vercel.app') {
        // Ruta no desplegada (lo que devuelve Vercel hoy).
        return http.Response('<html>404</html>', 404);
      }
      expect(url.host, 'nominatim.openstreetmap.org');
      if (url.path.endsWith('/search')) {
        return json([
          {
            'lat': '4.7110',
            'lon': '-74.0721',
            'display_name': 'Salón Real, Bogotá, Colombia',
            'address': {'amenity': 'Salón Real'},
            'name': 'Salón Real',
          },
          {
            'lat': '4.7200',
            'lon': '-74.0800',
            'display_name': 'Cota, Cundinamarca, Colombia',
            'address': {'town': 'Cota'},
            'name': '',
          },
        ]);
      }
      expect(url.path.endsWith('/reverse'), isTrue);
      return json({
        'lat': '4.7110',
        'lon': '-74.0721',
        'display_name': 'Hacienda San José, Cota, Colombia',
        'address': {'tourism': 'Hacienda San José'},
      });
    });

    final places = await HsApi.searchPlaces('Salón Real');
    expect(places, hasLength(2));
    expect(places.first['name'], 'Salón Real');
    expect(places.first['lat'], 4.711);
    // Sin nombre propio se usa la primera parte de la dirección.
    expect(places.last['name'], 'Cota');

    final point = await HsApi.reversePlace(4.711, -74.0721);
    expect(point, isNotNull);
    expect(point!['name'], 'Hacienda San José');
    expect(point['lat'], 4.711);
    // La segunda llamada ya no intenta el backend: va directo a OSM.
    expect(urls.where((u) => u.contains('/api/admin/geocode')), hasLength(1));
  });
}

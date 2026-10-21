// ==================================================================
// HARD STREET ADMIN - El LUGAR de una agenda
// ==================================================================
// Una agenda puede llevar DÓNDE es: el nombre que se lee (una hacienda, un
// salón, una dirección) y sus coordenadas, que son las que abren el mapa.
//
// El nombre y las coordenadas viajan en la propia agenda
// (`location`, `lat`, `lng`): así el calendario, el detalle y las tarjetas
// del panel enseñan el lugar sin una segunda llamada.
// ==================================================================
import 'open_url.dart';

/// Un lugar elegido con el mapa o buscado por nombre.
///
/// Cualquiera de las dos cosas puede faltar: una agenda vieja puede tener el
/// nombre sin coordenadas (o al revés), y ambos casos se muestran igual.
class HsPlace {
  const HsPlace({required this.name, this.lat, this.lng});

  /// Nombre visible del lugar (lo que se lee en la agenda).
  final String name;

  /// Latitud / longitud del lugar (null = no se eligió un punto en el mapa).
  final double? lat;
  final double? lng;

  bool get isEmpty => name.trim().isEmpty && !hasCoords;

  bool get hasCoords => lat != null && lng != null;

  /// Coordenadas cortas para mostrar debajo del nombre.
  String get coordsLabel =>
      hasCoords ? '${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}' : '';

  /// Lo que se pinta cuando hay lugar: el nombre o, si no hay, el punto.
  String get label {
    final n = name.trim();
    if (n.isNotEmpty) return n;
    return hasCoords ? 'Ubicación en el mapa' : '';
  }

  /// Cuerpo que espera la API de agendas.
  Map<String, dynamic> toBody() => {
    'location': name.trim(),
    'lat': lat,
    'lng': lng,
  };

  /// Lee el lugar de una agenda (o de cualquier mapa con `location`/`lat`/`lng`).
  ///
  /// Devuelve null si la agenda no tiene lugar: así los módulos solo pintan la
  /// fila del lugar cuando de verdad hay algo que enseñar.
  static HsPlace? of(Object? raw) {
    if (raw is! Map) return null;
    final name = (raw['location'] ?? raw['name'] ?? raw['place'] ?? '')
        .toString()
        .trim();
    final lat = _coord(raw['lat'] ?? raw['latitude']);
    final lng = _coord(raw['lng'] ?? raw['lon'] ?? raw['longitude']);
    if (name.isEmpty && (lat == null || lng == null)) return null;
    return HsPlace(name: name, lat: lat, lng: lng);
  }

  /// TODAS las ubicaciones de una agenda, en el orden del servidor
  /// (1, 2, 3…). Si la agenda es de antes de las ubicaciones múltiples, cae a
  /// su lugar único (`location`/`lat`/`lng`).
  static List<HsPlace> allOf(Object? raw) {
    if (raw is! Map) return const [];
    final list = <HsPlace>[];
    final many = raw['locations'];
    if (many is List) {
      for (final item in many) {
        final place = of(item);
        if (place != null) list.add(place);
      }
    }
    if (list.isEmpty) {
      final one = of(raw);
      if (one != null) list.add(one);
    }
    return list;
  }

  /// Cuerpo que espera la API para VARIAS ubicaciones: `locations` en orden
  /// (el servidor las numera). Las vacías se descartan, así la numeración
  /// queda 1, 2, 3 sin huecos.
  static Map<String, dynamic> listBody(Iterable<HsPlace?> places) => {
    'locations': [
      for (final p in places)
        if (p != null && !p.isEmpty)
          {'location': p.name.trim(), 'lat': p.lat, 'lng': p.lng},
    ],
  };

  static double? _coord(Object? raw) {
    if (raw == null) return null;
    final n = double.tryParse(raw.toString());
    if (n == null || !n.isFinite) return null;
    return n;
  }

  @override
  bool operator ==(Object other) =>
      other is HsPlace &&
      other.name == name &&
      other.lat == lat &&
      other.lng == lng;

  @override
  int get hashCode => Object.hash(name, lat, lng);

  @override
  String toString() => 'HsPlace($name, $lat, $lng)';
}

/// Resultado de abrir el selector de lugar.
///
/// - `null` en `hsShowPlacePicker` = el usuario CERRÓ sin cambiar nada.
/// - `PlaceChoice(place: null)` = el usuario QUITÓ el lugar de la agenda.
class PlaceChoice {
  const PlaceChoice(this.place);

  final HsPlace? place;
}

/// Abre el lugar en la app de mapas del equipo (Google Maps).
///
/// Con coordenadas abre el punto exacto; sin ellas busca el nombre. Es el
/// botón "Abrir mapa" del detalle de la agenda.
Future<bool> hsOpenPlace(HsPlace place) {
  final q = place.hasCoords ? '${place.lat},${place.lng}' : place.name.trim();
  if (q.isEmpty) return Future.value(false);
  return hsOpenUrl(
    'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q)}',
  );
}

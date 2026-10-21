// ==================================================================
// HARD STREET ADMIN - SELECTOR DE LUGAR (MAPA + BÚSQUEDA)
// ==================================================================
// El lugar de una agenda se elige aquí: se BUSCA por nombre (hacienda, salón,
// dirección…) o se TOCA el mapa. Funciona igual en celular, en computadora y
// en la web porque el mapa es Flutter (flutter_map + OpenStreetMap) y la
// búsqueda la resuelve el backend (`/api/admin/geocode`), nunca el navegador.
//
// Piezas:
//   hsShowPlacePicker()  abre el selector y devuelve PlaceChoice
//                        (null = cerró sin cambios, place null = quitar lugar).
//   HsPlaceField          la tarjeta del formulario ("Agregar lugar").
//   HsPlacesField        una o VARIAS ubicaciones, numeradas 1, 2, 3…
//   HsPlaceMapPreview    el mini mapa del detalle de la agenda.
//   hsOpenPlace()        abre el lugar en la app de mapas del equipo.
// ==================================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../hs_access.dart';
import '../hs_api.dart';
import '../hs_place.dart';
import '../theme.dart';
import 'hs_modal.dart';
import 'hs_toast.dart';

/// Centro de partida cuando la agenda todavía no tiene lugar (Colombia).
const LatLng _kFallbackCenter = LatLng(4.7110, -74.0721);

/// Zoom de partida: cerca cuando ya hay punto, país cuando no.
const double _kFallbackZoom = 5.4;
const double _kPlaceZoom = 16;

const String _kTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Abre el selector de lugar.
///
/// Devuelve `null` si el usuario cerró sin tocar nada y [PlaceChoice] con
/// `place: null` si quitó la ubicación de la agenda.
Future<PlaceChoice?> hsShowPlacePicker(
  BuildContext context, {
  HsPlace? initial,
}) {
  return showHsModal<PlaceChoice>(
    context: context,
    builder: (_) => _PlacePickerDialog(initial: initial),
  );
}

// ==================================================================
// SELECTOR
// ==================================================================
class _PlacePickerDialog extends StatefulWidget {
  const _PlacePickerDialog({this.initial});

  final HsPlace? initial;

  @override
  State<_PlacePickerDialog> createState() => _PlacePickerDialogState();
}

class _PlacePickerDialogState extends State<_PlacePickerDialog> {
  final MapController _map = MapController();
  final TextEditingController _search = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  Timer? _debounce;
  List<Map<String, dynamic>> _results = const [];
  bool _searching = false;
  String? _searchError;

  late HsPlace? _selected;
  late LatLng _center;
  late double _zoom;
  bool _locating = false;
  bool _nameTouched = false;

  /// UBICACIONES GUARDADAS del estudio (se reutilizan al agendar).
  List<Map<String, dynamic>> _saved = const [];

  /// ¿Se pueden quitar las ubicaciones guardadas?
  bool get _canDeleteSaved =>
      HsAccess.instance.degraded ||
      HsAccess.instance.can('schedules', 'delete');

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    _name.text = widget.initial?.name ?? '';
    final hasPoint = widget.initial?.hasCoords ?? false;
    _center = hasPoint
        ? LatLng(widget.initial!.lat!, widget.initial!.lng!)
        : _kFallbackCenter;
    _zoom = hasPoint ? _kPlaceZoom : _kFallbackZoom;
    _loadSaved();
  }

  /// Trae las ubicaciones guardadas (si el backend aún no las tiene, la
  /// lista queda vacía y el selector funciona igual).
  Future<void> _loadSaved() async {
    try {
      final list = await HsApi.savedLocations();
      if (!mounted) return;
      setState(() => _saved = list);
    } catch (_) {
      // Sin conexión o migración pendiente: sin sugerencias guardadas.
    }
  }

  /// Elige una ubicación GUARDADA (nombre + punto).
  void _useSaved(Map<String, dynamic> place) {
    final name = (place['name'] ?? '').toString();
    final lat = _coord(place['lat']);
    final lng = _coord(place['lng']);
    setState(() {
      _selected = HsPlace(name: name, lat: lat, lng: lng);
      _name.text = name;
      _nameTouched = false;
      _results = const [];
      _searchError = null;
      if (lat != null && lng != null) {
        _center = LatLng(lat, lng);
        _zoom = _kPlaceZoom;
      }
    });
    if (lat != null && lng != null) {
      _search.clear();
      _searchFocus.unfocus();
      _map.move(LatLng(lat, lng), _kPlaceZoom);
    }
  }

  /// Guarda el lugar actual para volver a usarlo al agendar otro evento.
  Future<void> _saveCurrentAsLocation() async {
    final name = _name.text.trim();
    final sel = _selected;
    if (name.isEmpty || !(sel?.hasCoords ?? false)) {
      setState(
        () => _searchError =
            'Para guardar la ubicación escribe su nombre y marca el punto.',
      );
      return;
    }
    try {
      final list = await HsApi.saveSavedLocation(
        name: name,
        lat: sel!.lat!,
        lng: sel.lng!,
      );
      if (!mounted) return;
      setState(() {
        _saved = list;
        _searchError = null;
      });
      HsToast.success('Ubicación guardada para próximas agendas');
    } catch (_) {
      // La API ya mostró el error.
    }
  }

  /// Quita una ubicación guardada (no borra las agendas que la usaron).
  Future<void> _deleteSaved(int id) async {
    try {
      final list = await HsApi.deleteSavedLocation(id);
      if (!mounted) return;
      setState(() => _saved = list);
    } catch (_) {
      // La API ya avisó.
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _map.dispose();
    _search.dispose();
    _name.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Escribe en el buscador: espera a que la persona deje de teclear y pide
  /// los lugares al backend (evita una petición por letra).
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 3) {
      setState(() {
        _results = const [];
        _searching = false;
        _searchError = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    _debounce = Timer(const Duration(milliseconds: 450), () => _searchNow(q));
  }

  Future<void> _searchNow(String q) async {
    try {
      final found = await HsApi.searchPlaces(q);
      if (!mounted || _search.text.trim() != q) return;
      setState(() {
        _results = found;
        _searching = false;
        _searchError = found.isEmpty
            ? 'No se encontraron lugares con ese nombre.'
            : null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = 'No se pudo buscar el lugar.';
      });
    }
  }

  /// Lista de sugerencias FLOTANTE sobre el mapa.
  ///
  /// Va en el Stack del mapa (no en el Column) para que el mapa conserve su
  /// tamaño y su encuadre mientras se escribe o se muestran los resultados.
  Widget _resultsOverlay(ColorScheme scheme) {
    return Positioned(
      left: 8,
      right: 8,
      top: 8,
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Container(
          constraints: const BoxConstraints(maxHeight: 220),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .55),
            ),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: _results.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: .4),
            ),
            itemBuilder: (_, i) {
              final r = _results[i];
              return ListTile(
                dense: true,
                leading: Icon(
                  Icons.place_outlined,
                  size: 19,
                  color: AppColors.brand,
                ),
                title: Text(
                  _placeName(r),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  (r['address'] ?? r['displayName'] ?? '').toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                onTap: () => _useResult(r),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Elige un resultado de la búsqueda: centra el mapa y fija el punto.
  void _useResult(Map<String, dynamic> place) {
    final lat = _coord(place['lat']);
    final lng = _coord(place['lng']);
    if (lat == null || lng == null) return;
    final name = _placeName(place);
    setState(() {
      _selected = HsPlace(name: name, lat: lat, lng: lng);
      _center = LatLng(lat, lng);
      _zoom = _kPlaceZoom;
      _results = const [];
      _searchError = null;
      _nameTouched = false;
      _name.text = name;
    });
    _search.clear();
    _searchFocus.unfocus();
    _map.move(LatLng(lat, lng), _kPlaceZoom);
  }

  /// Tocar el mapa fija el punto y, si se puede, saca el nombre del lugar.
  Future<void> _tapPoint(LatLng point) async {
    setState(() {
      _selected = HsPlace(
        name: _name.text.trim(),
        lat: point.latitude,
        lng: point.longitude,
      );
      _locating = true;
      _searchError = null;
    });
    try {
      final found = await HsApi.reversePlace(point.latitude, point.longitude);
      if (!mounted) return;
      final name = _placeName(found ?? const {});
      setState(() {
        _locating = false;
        if (name.isNotEmpty && !_nameTouched) _name.text = name;
        _selected = HsPlace(
          name: _name.text.trim(),
          lat: point.latitude,
          lng: point.longitude,
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        // Sin dirección conocida: se queda el PUNTO (el nombre viejo ya no
        // corresponde). El usuario puede escribir uno.
        if (!_nameTouched) _name.text = '';
      });
    }
  }

  void _save() {
    final name = _name.text.trim();
    final sel = _selected;
    if (name.isEmpty && !(sel?.hasCoords ?? false)) {
      setState(
        () => _searchError = 'Escribe el nombre del lugar o toca el mapa.',
      );
      return;
    }
    Navigator.of(context)
        .pop(PlaceChoice(HsPlace(name: name, lat: sel?.lat, lng: sel?.lng)));
  }

  static double? _coord(Object? raw) {
    if (raw == null) return null;
    final n = double.tryParse(raw.toString());
    return n != null && n.isFinite ? n : null;
  }

  /// Nombre corto: el del lugar o, si el backend no lo dio, la primera parte
  /// de la dirección ("Hacienda San José, Cota, …" -> "Hacienda San José").
  static String _placeName(Map<String, dynamic> place) {
    final name = (place['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final display = (place['displayName'] ?? place['address'] ?? '').toString();
    final first = display.split(',').first.trim();
    return first.isEmpty ? display.trim() : first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final phone = hsIsPhone(context);
    final size = MediaQuery.sizeOf(context);
    final surface = theme.dialogTheme.backgroundColor ?? theme.cardColor;
    final hasPoint = _selected?.hasCoords ?? false;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(scheme),
        Padding(
          padding: EdgeInsets.fromLTRB(
            phone ? 12 : 18,
            phone ? 4 : 8,
            phone ? 12 : 18,
            10,
          ),
          child: TextField(
            controller: _search,
            focusNode: _searchFocus,
            enabled: true,
            textInputAction: TextInputAction.search,
            onChanged: _onSearchChanged,
            onSubmitted: (v) {
              final q = v.trim();
              if (q.length >= 3) {
                _debounce?.cancel();
                setState(() => _searching = true);
                _searchNow(q);
              }
            },
            decoration: InputDecoration(
              hintText: 'Buscar lugar (hacienda, salón, dirección…)',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
        ),
        // MIS UBICACIONES: los lugares que el estudio ya guardó (haciendas,
        // salones, oficinas…). Se eligen con un toque en vez de buscarlos en
        // el mapa otra vez; el chip se puede quitar.
        if (_saved.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(
              phone ? 12 : 18,
              0,
              phone ? 12 : 18,
              8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.bookmarks_outlined,
                      size: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'MIS UBICACIONES',
                      style: TextStyle(
                        fontSize: 9.5,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _saved.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (_, i) {
                      final p = _saved[i];
                      final id = (p['id'] as num?)?.toInt() ?? 0;
                      return InputChip(
                        key: ValueKey('place-saved-${p['id']}'),
                        avatar: const Icon(Icons.place_outlined, size: 15),
                        label: Text(
                          (p['name'] ?? '').toString(),
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: () => _useSaved(p),
                        onDeleted: _canDeleteSaved && id > 0
                            ? () => _deleteSaved(id)
                            : null,
                        deleteIcon: const Icon(Icons.close, size: 14),
                        visualDensity: VisualDensity.compact,
                        labelStyle: const TextStyle(fontSize: 11.5),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        // Sin lugares guardados todavía: se explica cómo AGREGAR el primero
        // (basta con ponerle nombre y punto al lugar y guardarlo abajo).
        if (_saved.isEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(
              phone ? 12 : 18,
              0,
              phone ? 12 : 18,
              8,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.bookmark_add_outlined,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Aún no tienes ubicaciones guardadas: elige un lugar en el '
                    'mapa y toca «Guardar ubicación» para reusarlo en las '
                    'próximas agendas.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.3,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_searchError != null && _results.isEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(
              phone ? 16 : 22,
              0,
              phone ? 16 : 22,
              8,
            ),
            child: Text(
              _searchError!,
              style: TextStyle(
                fontSize: 12,
                color: _selected == null && _name.text.trim().isEmpty
                    ? scheme.error
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: phone ? 12 : 18),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: _center,
                      initialZoom: _zoom,
                      minZoom: 2,
                      maxZoom: 19,
                      onTap: (_, point) => _tapPoint(point),
                      interactionOptions: const InteractionOptions(
                        // Gira con dos dedos en el celular, pero sin rotación
                        // accidental (el norte siempre arriba).
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: _kTileUrl,
                        userAgentPackageName: 'com.example.hardstreet_admin',
                        maxZoom: 19,
                      ),
                      if (hasPoint)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(_selected!.lat!, _selected!.lng!),
                              width: 46,
                              height: 46,
                              alignment: Alignment.topCenter,
                              child: Icon(
                                Icons.location_on,
                                size: 42,
                                color: AppColors.brand,
                                shadows: const [
                                  Shadow(color: Colors.black38, blurRadius: 6),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  // SUGERENCIAS EN OVERLAY: se dibujan ENCIMA del mapa, no
                  // dentro del Column. Antes la lista empujaba el mapa hacia
                  // abajo y lo encogía al escribir, así que el encuadre se
                  // movía justo cuando aparecían los resultados.
                  if (_results.isNotEmpty) _resultsOverlay(scheme),
                  // Pista de uso (se va en cuanto hay un punto o mientras se
                  // muestran sugerencias, para no tapar la primera).
                  if (!hasPoint && _results.isEmpty)
                    Positioned(
                      left: 10,
                      right: 10,
                      top: 10,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surface.withValues(alpha: .93),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(
                                alpha: .5,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.touch_app_outlined,
                                size: 15,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Busca el lugar arriba o toca el mapa para marcar el punto.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // Controles de zoom: en computadora el mouse rueda, pero
                  // estos botones hacen falta en pantallas táctiles sin pinza.
                  Positioned(
                    right: 10,
                    bottom: 26,
                    child: Column(
                      children: [
                        _MapButton(
                          icon: Icons.add,
                          tooltip: 'Acercar',
                          onTap: () {
                            final z = (_map.camera.zoom + 1).clamp(2.0, 19.0);
                            _map.move(_map.camera.center, z);
                          },
                        ),
                        const SizedBox(height: 6),
                        _MapButton(
                          icon: Icons.remove,
                          tooltip: 'Alejar',
                          onTap: () {
                            final z = (_map.camera.zoom - 1).clamp(2.0, 19.0);
                            _map.move(_map.camera.center, z);
                          },
                        ),
                      ],
                    ),
                  ),
                  // Atribución obligatoria de OpenStreetMap.
                  Positioned(
                    left: 8,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .82),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        '© OpenStreetMap',
                        style: TextStyle(
                          fontSize: 9,
                          color: Color(0xFF334155),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (_locating)
                    Positioned(
                      left: 10,
                      bottom: 26,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: .93),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: .5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              'Buscando la dirección…',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(phone ? 12 : 18, 12, phone ? 12 : 18, 0),
          child: TextField(
            controller: _name,
            onChanged: (v) {
              _nameTouched = true;
              final sel = _selected;
              if (sel != null) {
                setState(
                  () =>
                      _selected = HsPlace(name: v, lat: sel.lat, lng: sel.lng),
                );
              }
            },
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nombre del lugar',
              hintText: 'Ej. Hacienda San José, Salón Real…',
              prefixIcon: Icon(Icons.place_outlined, size: 20),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(phone ? 14 : 20, 6, phone ? 14 : 20, 10),
          child: Text(
            hasPoint
                ? 'Punto marcado: ${_selected!.coordsLabel}'
                : 'Sin punto en el mapa (solo el nombre).',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ),
        _footer(scheme, phone),
      ],
    );

    if (phone) {
      return Material(
        color: surface,
        child: SafeArea(child: content),
      );
    }
    // En computadora el mapa es el protagonista: el modal ocupa CASI toda la
    // ventana (antes se quedaba en 780×660 y el mapa salía pequeño).
    final width = mathMin(size.width - 48, 1080);
    final height = mathMin(size.height - 48, 860);
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: SizedBox(width: width, height: height, child: content),
    );
  }

  double mathMin(double a, double b) => a < b ? a : b;

  Widget _header(ColorScheme scheme) {
    final phone = hsIsPhone(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(phone ? 14 : 20, phone ? 14 : 18, 8, 8),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.brand, AppColors.brandDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brand.withValues(alpha: .30),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.map_outlined,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Lugar del evento',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                Text(
                  'Búscalo por nombre o marca el punto en el mapa',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, size: 20, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _footer(ColorScheme scheme, bool phone) {
    final canClear = (widget.initial != null) || _selected != null;
    final hasPoint = _selected?.hasCoords ?? false;
    final canSave = hasPoint && _name.text.trim().isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5)),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        phone ? 14 : 20,
        10,
        phone ? 14 : 20,
        phone ? 12 : 16,
      ),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          // Guardar el lugar se ofrece SIEMPRE (aunque falte el punto) para
          // que la opción de agregar ubicaciones se vea; deshabilitado hasta
          // que haya nombre y punto, con la pista en el tooltip.
          Tooltip(
            message: canSave
                ? 'Guardar este lugar en «Mis ubicaciones»'
                : 'Escribe el nombre y marca el punto para guardarlo',
            child: OutlinedButton.icon(
              key: const ValueKey('place-save-location'),
              onPressed: canSave ? _saveCurrentAsLocation : null,
              icon: const Icon(Icons.bookmark_add_outlined, size: 17),
              label: const Text('Guardar ubicación'),
            ),
          ),
          if (canClear)
            TextButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(const PlaceChoice(null)),
              icon: const Icon(Icons.location_off_outlined, size: 17),
              label: const Text('Quitar lugar'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Usar este lugar'),
          ),
        ],
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.surface.withValues(alpha: .95),
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: .6),
              ),
            ),
            child: Icon(icon, size: 19, color: scheme.onSurface),
          ),
        ),
      ),
    );
  }
}

// ==================================================================
// CAMPO DEL FORMULARIO
// ==================================================================

/// Tarjeta del formulario de agenda para elegir el lugar.
///
/// Sin lugar se ve como un campo más ("Agregar lugar"); con lugar enseña el
/// nombre, las coordenadas y un botón para quitarlo.
class HsPlaceField extends StatelessWidget {
  const HsPlaceField({
    super.key,
    required this.place,
    required this.onChanged,
    this.enabled = true,
  });

  final HsPlace? place;
  final ValueChanged<HsPlace?> onChanged;
  final bool enabled;

  Future<void> _pick(BuildContext context) async {
    final choice = await hsShowPlacePicker(context, initial: place);
    if (choice == null) return;
    onChanged(choice.place);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = AppColors.brand;
    final hasPlace = place != null && !place!.isEmpty;
    final label = hasPlace ? place!.label : 'Agregar lugar';
    final subtitle = hasPlace
        ? (place!.hasCoords
              ? place!.coordsLabel
              : 'Solo el nombre, sin punto en el mapa')
        : 'Búscalo por nombre o márcalo en el mapa';

    return InkWell(
      onTap: enabled ? () => _pick(context) : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 10, 6, 10),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tint.withValues(alpha: .28)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(Icons.place_outlined, size: 18, color: tint),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: hasPlace ? tint : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (hasPlace && enabled)
              IconButton(
                tooltip: 'Quitar lugar',
                visualDensity: VisualDensity.compact,
                onPressed: () => onChanged(null),
                icon: Icon(
                  Icons.close,
                  size: 17,
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Varias ubicaciones en un formulario (una agenda puede tener 1, 2, 3…).
///
/// Cada una lleva su NÚMERO (el orden de la lista: al quitar una, las demás
/// se renumeran solas) y un botón para sumar otra. Las vacías se descartan al
/// guardar ([HsPlace.listBody]).
class HsPlacesField extends StatelessWidget {
  const HsPlacesField({
    super.key,
    required this.places,
    required this.onChanged,
    required this.onAdd,
    required this.onRemove,
    this.enabled = true,
    this.numberKeyPrefix = 'agenda-place',
  });

  final List<HsPlace?> places;
  final void Function(int index, HsPlace? place) onChanged;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final bool enabled;

  /// Prefijo de las llaves: `<prefijo>-<i>` (fila), `<prefijo>-number-<i>`
  /// (número) y `<prefijo>-add` (agregar otra).
  final String numberKeyPrefix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < places.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            key: ValueKey('$numberKeyPrefix-$i'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                key: ValueKey('$numberKeyPrefix-number-$i'),
                width: 26,
                height: 26,
                alignment: Alignment.center,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brand,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: HsPlaceField(
                  place: places[i],
                  enabled: enabled,
                  onChanged: (place) => onChanged(i, place),
                ),
              ),
              if (places.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 2),
                  child: IconButton(
                    tooltip: 'Quitar ubicación ${i + 1}',
                    visualDensity: VisualDensity.compact,
                    onPressed: enabled ? () => onRemove(i) : null,
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: ValueKey('$numberKeyPrefix-add'),
            onPressed: enabled ? onAdd : null,
            icon: const Icon(Icons.add_location_alt_outlined, size: 17),
            label: Text(
              places.length == 1
                  ? 'Agregar otra ubicación'
                  : 'Agregar ubicación ${places.length + 1}',
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Se numeran solas: 1, 2, 3… en el orden en que las agregas.',
          style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Mini mapa (solo lectura) para el detalle de la agenda.
///
/// Si la agenda no tiene coordenadas no se pinta nada: quien llama decide si
/// muestra el nombre solo. Tocar el mapa abre la app de mapas del equipo.
class HsPlaceMapPreview extends StatelessWidget {
  const HsPlaceMapPreview({super.key, required this.place, this.height = 132});

  final HsPlace place;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (!place.hasCoords) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final point = LatLng(place.lat!, place.lng!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: point,
                initialZoom: 15.5,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: _kTileUrl,
                  userAgentPackageName: 'com.example.hardstreet_admin',
                  maxZoom: 19,
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: Icon(
                        Icons.location_on,
                        size: 36,
                        color: AppColors.brand,
                        shadows: const [
                          Shadow(color: Colors.black38, blurRadius: 6),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              left: 6,
              bottom: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .82),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  '© OpenStreetMap',
                  style: TextStyle(
                    fontSize: 8.5,
                    color: Color(0xFF334155),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 6,
              top: 6,
              child: Material(
                color: scheme.surface.withValues(alpha: .95),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () => hsOpenPlace(place),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.open_in_new_rounded,
                          size: 13,
                          color: scheme.onSurface,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Abrir mapa',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

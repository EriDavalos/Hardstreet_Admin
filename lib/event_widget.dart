import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_platform.dart';
import 'app_settings.dart';
import 'hs_access.dart';
import 'hs_format.dart';

/// Lo que el usuario tocó EN el widget nativo.
///
/// El widget no navega solo: manda la petición a la app y ella decide. Sirve
/// tanto para abrir el DETALLE de una agenda como para el alta de evento.
@immutable
class WidgetTap {
  const WidgetTap({this.agendaId = 0, this.create = false});

  /// Id de la agenda tocada (0 = el widget no tenía id, p. ej. un aviso).
  final int agendaId;

  /// true si se tocó el botón "Agregar agenda".
  final bool create;
}

/// WIDGET de "próximos eventos" (pantalla de inicio de Android y panel de
/// escritorio de Windows).
///
/// La app —que sí tiene la sesión y los datos— calcula los próximos eventos y
/// los EMPUJA al widget nativo por un MethodChannel; el lado nativo solo
/// dibuja. Así el widget no necesita credenciales, ni red, ni permisos.
///
/// Contrato del canal `hardstreet/events_widget`:
///   update { header, visible, dark, count, canAdd,
///            events: [ {id, title, subtitle, when, time, day, showDay, at} ] }
///     `dark` = MODO de la app (claro/oscuro): el widget se pinta igual que
///     ella, no como el sistema.
///     `canAdd` = el rol puede CREAR agendas: solo entonces se ofrece el botón
///     "Agregar agenda" (el backend revalida de todos modos).
///     `id` = id de la agenda de cada evento: al tocar la fila la app abre SU
///     detalle.
///     Android: guarda los eventos y repinta los widgets colocados en el inicio.
///     Windows: crea/actualiza (o esconde) el panel flotante.
///   requestPin  → bool   (solo Android 8+: pide colocar el widget)
///   isVisible   → bool   (solo Windows: ¿el panel está a la vista?)
///   consumeTap  → {action,id}?  (solo Android: acción con la que el widget
///                lanzó la app en frío; se entrega UNA vez)
///
/// Sentido inverso (nativo → Dart): el widget AVISA qué se tocó con
/// `onWidgetTap { action: 'agenda'|'new', id }`; [requested] lo publica para
/// que el panel cambie a Agendas y la página abra el detalle o el alta.
class UpcomingEventsWidget {
  UpcomingEventsWidget._();

  /// Nombre del canal (público para poder simularlo en test/).
  static const String channelName = 'hardstreet/events_widget';

  static const MethodChannel _channel = MethodChannel(channelName);

  /// Encabezado que muestran ambos widgets.
  static const String header = 'Próximos eventos';

  static const String _kDesktopVisible = 'widget.events.desktop';

  /// ¿Esta plataforma tiene widget nativo?
  static bool get supported => isAndroidPlatform || isWindowsPlatform;

  /// ¿Hay que alimentarlo con las agendas? En Android siempre (el widget ya
  /// puede estar colocado); en Windows solo si el panel está activado.
  static bool get autoFeed =>
      isAndroidPlatform || (isWindowsPlatform && desktopVisible);

  /// ¿El panel de escritorio (Windows) está activado? (persistente)
  static bool desktopVisible = false;

  /// Últimos eventos publicados (para poder repintar sin volver a consultar).
  static List<Map<String, dynamic>> get events => _events;
  static List<Map<String, dynamic>> _events = const [];

  /// ¿El rol del usuario puede CREAR agendas? (decide el botón "+" del
  /// widget). En modo degradado no se oculta nada: el backend revalida.
  static bool get canCreateAgendas {
    final access = HsAccess.instance;
    return access.degraded ||
        access.can('schedules', 'create') ||
        access.can('Agendas', 'create');
  }

  /// Último toque hecho en el widget nativo (o null si no hay nada pendiente).
  ///
  /// Quien lo atiende lo deja en null para que no se repita: el panel lo usa
  /// para cambiar de sección y la página de Agendas para abrir el detalle.
  static final ValueNotifier<WidgetTap?> requested = ValueNotifier(null);

  /// Escucha los toques del widget nativo. Idempotente.
  static void listen() {
    if (kWeb) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onWidgetTap') _applyTap(call.arguments);
      return null;
    });
  }

  /// ¿El widget lanzó la app con una acción pendiente? (arranque en frío: el
  /// engine todavía no existía cuando llegó el Intent). Se pregunta una vez al
  /// entrar al panel.
  static Future<void> consumePending() async {
    if (kWeb) return;
    try {
      final raw = await _channel.invokeMethod<Object?>('consumeTap');
      if (raw != null) _applyTap(raw);
    } catch (_) {
      // Canal no disponible (plataforma sin widget): nada que hacer.
    }
  }

  static void _applyTap(Object? raw) {
    if (raw is! Map) return;
    requested.value = WidgetTap(
      agendaId: (raw['id'] as num?)?.toInt() ?? 0,
      create: '${raw['action']}'.toLowerCase() == 'new',
    );
  }

  /// Lee la preferencia del panel de escritorio. Idempotente.
  static Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      desktopVisible = sp.getBool(_kDesktopVisible) ?? false;
    } catch (_) {
      // Sin storage: se queda en memoria.
    }
  }

  /// Activa/desactiva el panel de escritorio y lo aplica al instante.
  static Future<void> setDesktopVisible(bool value) async {
    desktopVisible = value;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_kDesktopVisible, value);
    } catch (_) {
      // Sin storage: el cambio vale para esta ejecución.
    }
    await _push();
  }

  /// Publica los próximos eventos (agendas del panel + avisos como respaldo).
  /// No lanza: si el widget no existe o falla, la app sigue igual.
  static Future<void> publish(
    List<Map<String, dynamic>> agendas, {
    List<Map<String, dynamic>> reminders = const [],
    DateTime? now,
  }) async {
    _events = buildEvents(agendas, reminders: reminders, now: now);
    _canAdd = canCreateAgendas;
    _published = true;
    await _push();
  }

  /// El rol puede crear agendas (lo último publicado).
  static bool get canAdd => _canAdd;
  static bool _canAdd = false;

  /// Vuelve a mandar lo último publicado. Lo llama la app al cambiar el tema
  /// (claro/oscuro) o al cargar los permisos, para que el widget se repinte
  /// con el MISMO modo/permisos que ella.
  ///
  /// Si esta sesión todavía NO publicó nada, no manda nada: empujar una lista
  /// vacía borraría los eventos que el widget ya estaba mostrando (lo que
  /// publica el servicio de avisos llega en seguida, ya con los permisos).
  static Future<void> refresh() async {
    if (!_published) return;
    await _push();
  }

  /// ¿Ya se publicó al menos una vez en esta sesión?
  static bool _published = false;

  /// Solo para PRUEBAS: deja el widget como recién abierto (sin publicar).
  @visibleForTesting
  static void resetForTest() {
    _published = false;
    _events = const [];
    _canAdd = false;
    requested.value = null;
  }

  /// Vuelve a mandar lo último publicado (p. ej. al activar el panel).
  static Future<void> _push() async {
    // En web no hay widget nativo (el canal no existe).
    if (kWeb) return;
    // Se recalcula en cada empujón: al cargar los permisos (o al cambiarlos en
    // Roles) el botón "Agregar agenda" aparece/desaparece sin esperar otra
    // consulta de la agenda.
    _canAdd = canCreateAgendas;
    try {
      await _channel.invokeMethod<void>('update', {
        'header': header,
        'visible': desktopVisible,
        // El widget respeta el modo de la APP (no el del sistema).
        'dark': AppSettings.instance.dark,
        // El botón "Agregar agenda" solo se ofrece si el rol puede crear.
        'canAdd': _canAdd,
        'count': _events.length,
        'events': _events,
      });
    } catch (_) {
      // Sin implementación nativa (o canal no disponible): mejor esfuerzo.
    }
  }

  /// Pide al lanzador de Android colocar el widget (chip de confirmación).
  /// Devuelve true si el sistema aceptó la petición (o si ya estaba).
  static Future<bool> requestPin() async {
    if (!isAndroidPlatform) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPin') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// TODOS los eventos próximos, ya formateados para el widget.
  ///
  /// Se alimenta de las AGENDAS (nombre del paquete, cliente y servicio) y,
  /// cuando no hay agendas, de los AVISOS de eventos. Solo eventos futuros
  /// (con 1 hora de gracia para los que están en curso) y en orden cronológico.
  /// No hay tope: el widget muestra TODA la agenda que viene (y se puede
  /// desplazar dentro de él).
  ///
  /// Cada evento trae su DÍA para agruparlos: `day` es el encabezado
  /// ("HOY · 16 OCT") y `showDay` es true solo en el PRIMER evento de ese
  /// día, así dos eventos del mismo día comparten un solo encabezado.
  /// Público para poder verificarlo en test/.
  static List<Map<String, dynamic>> buildEvents(
    List<Map<String, dynamic>> agendas, {
    List<Map<String, dynamic>> reminders = const [],
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final found = <_Event>[];
    for (final a in agendas) {
      final at = hsParseDate(a['eventDate']);
      if (at == null) continue;
      final title = _clean(a['packageName']);
      final client = _clean(a['clientName']);
      final service = _clean(a['serviceName']);
      final subtitle = [
        if (client.isNotEmpty) client,
        if (service.isNotEmpty) service,
      ].join(' · ');
      found.add(_Event(
        at: at,
        // Id de la agenda: es lo que la app abre al tocar la fila del widget.
        id: (a['id'] as num?)?.toInt() ?? 0,
        title: title.isEmpty ? 'Evento' : title,
        subtitle: subtitle,
      ));
    }
    if (found.isEmpty) {
      for (final r in reminders) {
        final at = hsParseDate(r['eventDate']);
        if (at == null) continue;
        found.add(_Event(
          at: at,
          // Un aviso no es una agenda: sin id, tocar la fila solo abre la app.
          id: 0,
          title: _clean(r['title']).isEmpty ? 'Evento' : _clean(r['title']),
          subtitle: _clean(r['body']),
        ));
      }
    }
    // Solo lo que viene: 1 hora de gracia para no borrar un evento en curso.
    final limit = ref.subtract(const Duration(hours: 1));
    found.removeWhere((e) => e.at.isBefore(limit));
    found.sort((a, b) => a.at.compareTo(b.at));
    // Encabezado de día: se pinta SOLO cuando cambia, para que varios
    // eventos del mismo día queden debajo de UNA fecha.
    final out = <Map<String, dynamic>>[];
    var lastDay = '';
    for (final e in found) {
      final day = hsDayLabel(e.at, ref);
      out.add({
        'id': e.id,
        'title': e.title,
        'subtitle': e.subtitle,
        'when': _when(e.at),
        'time': hsTimeLabel(e.at),
        'day': day,
        'showDay': day != lastDay,
        'at': e.at.millisecondsSinceEpoch,
      });
      lastDay = day;
    }
    return out;
  }

  static String _clean(Object? v) => (v ?? '').toString().trim();

  /// Fecha/hora ABSOLUTA y corta ("25 oct · 17:30"): el widget puede estar
  /// días sin actualizarse y un "en 3 días" quedaría mintiendo.
  static String _when(DateTime d) {
    final month = kHsMonths[d.month - 1];
    final short = month.length > 3 ? month.substring(0, 3) : month;
    return '${d.day} $short · ${hsTimeLabel(d)}';
  }
}

/// Evento interno mientras se ordena/recorta la lista.
class _Event {
  _Event({
    required this.at,
    required this.title,
    required this.subtitle,
    this.id = 0,
  });

  final DateTime at;
  final String title;
  final String subtitle;

  /// Id de la agenda (0 = no aplica, p. ej. un aviso).
  final int id;
}

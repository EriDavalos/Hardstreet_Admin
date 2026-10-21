import 'dart:async';

import 'package:flutter/widgets.dart'
    show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'event_widget.dart';
import 'hs_api.dart';
import 'reminder_notifications_native.dart';

/// Servicio de AVISOS de eventos próximos (falta 1 semana / falta 1 día).
///
/// - Consulta `GET /api/reminders` en segundo plano cada [pollInterval]
///   (mientras hay sesión iniciada).
/// - Cuando llega un aviso NUEVO, dispara una notificación NATIVA (Android,
///   iOS y Windows: toast del sistema, aunque el panel esté detrás de otra
///   ventana).
/// - Mantiene `unread` y `reminders` reactivos para la campanita de la
///   top bar.
/// - Alimenta el WIDGET de "próximos eventos" (inicio de Android / panel de
///   Windows) con las agendas que vienen, aprovechando este mismo ciclo de
///   refresco.
///
/// Con la app cerrada quien consulta es el worker nativo de Android
/// (`PackageNotificationsReceiver`) o el panel en la bandeja de Windows (ver
/// `flutter_window.cpp`): cerrar la ventana ya no apaga los avisos. Los ids ya
/// mostrados se PERSISTEN ([_kNotifiedIds]) para que el worker y la app no
/// avisen dos veces del mismo evento.
///
/// Singleton simple: `RemindersService.instance`. El polling se inicia y
/// detiene desde el panel al entrar/salir de sesión.
class RemindersService extends ChangeNotifier with WidgetsBindingObserver {
  RemindersService._();
  static final RemindersService instance = RemindersService._();

  /// Cuánto espera entre consultas al servidor.
  ///
  /// 15 segundos: los avisos llegan casi al instante sin abrir una conexión
  /// permanente contra el backend (que en Vercel no la mantendría). Además se
  /// refresca al VOLVER a la app (ver [didChangeAppLifecycleState]), así que
  /// al desbloquear el teléfono o regresar a la ventana los avisos ya están.
  static const Duration pollInterval = Duration(seconds: 15);

  /// Cada cuánto se empuja el widget de próximos eventos. Es más caro (pide
  /// las agendas completas), así que no hace falta en cada consulta.
  static const Duration eventWidgetInterval = Duration(minutes: 1);
  DateTime _lastWidgetFeed = DateTime.fromMillisecondsSinceEpoch(0);

  Timer? _timer;

  /// Ids de avisos que YA se notificaron (evita repetir la notificación
  /// en cada ciclo de polling).
  ///
  /// Se PERSISTEN bajo [_kNotifiedIds]: el worker nativo de Android publica
  /// avisos con la app cerrada y escribe en LA MISMA preferencia, y al abrir
  /// la app no se debe volver a avisar de lo que el teléfono ya mostró.
  final Set<int> _notifiedIds = <int>{};
  static const _kNotifiedIds = 'app.notified.reminders';

  List<Map<String, dynamic>> _reminders = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> get reminders => _reminders;

  int _unread = 0;
  int get unread => _unread;

  bool _started = false;
  bool get started => _started;

  /// Backend de notificaciones nativas. Sustituible en pruebas para no
  /// depender de la plataforma.
  ReminderNotifier notifier = NativeReminderPlugin.instance;

  /// De dónde se leen los avisos (sustituible en pruebas).
  Future<List<Map<String, dynamic>>> Function() fetch = HsApi.reminders;

  /// Inicia el polling (seguro llamar varias veces).
  void start() {
    if (_started) return;
    _started = true;
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // Sin binding (pruebas muy tempranas): el polling funciona igual.
    }
    refresh(); // primer llenado inmediato
    _timer = Timer.periodic(pollInterval, (_) => refresh());
  }

  /// Detiene el polling (al cerrar sesión).
  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {
      // idem
    }
  }

  /// Al VOLVER a la app (o desbloquear el equipo) se pide de inmediato: así no
  /// hay que esperar al siguiente ciclo para ver un aviso nuevo.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _started) refresh();
  }

  /// Limpia todo (al cerrar sesión): la campanita no debe recordar avisos
  /// de un usuario que ya salió (ni el widget mostrar sus eventos).
  void reset() {
    stop();
    _reminders = <Map<String, dynamic>>[];
    _unread = 0;
    _notifiedIds.clear();
    _lastWidgetFeed = DateTime.fromMillisecondsSinceEpoch(0);
    // Otro usuario en el mismo equipo debe recibir SUS avisos aunque el id
    // del evento coincida.
    unawaited(_clearNotified());
    notifyListeners();
    unawaited(UpcomingEventsWidget.publish(const []));
  }

  /// Lee del disco los ids ya notificados.
  ///
  /// Se lee en CADA consulta (no una vez por sesión) porque el worker nativo
  /// de Android escribe en la MISMA preferencia mientras la app está cerrada:
  /// así, al volver, la app sabe lo que el teléfono ya avisó y no lo repite.
  Future<void> _loadNotified() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_kNotifiedIds) ?? '';
      for (final part in raw.split(',')) {
        final id = int.tryParse(part.trim());
        if (id != null) _notifiedIds.add(id);
      }
    } catch (_) {
      // Sin storage: la protección vale solo para esta ejecución.
    }
  }

  /// Guarda los ids ya notificados (los últimos 200 bastan).
  Future<void> _saveNotified() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final ids = _notifiedIds.toList()..sort();
      final keep = ids.length > 200 ? ids.sublist(ids.length - 200) : ids;
      await sp.setString(_kNotifiedIds, keep.join(','));
    } catch (_) {
      // Sin storage: se sigue sin persistir.
    }
  }

  Future<void> _clearNotified() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_kNotifiedIds);
    } catch (_) {
      // idem
    }
  }

  /// SOLO PRUEBAS: olvida el set de la sesión SIN borrar el disco (simula
  /// «se cerró y se volvió a abrir la app»).
  @visibleForTesting
  void forgetNotifiedSession() {
    _notifiedIds.clear();
  }

  /// Consulta los avisos del usuario y actualiza estado.
  /// No lanza: un fallo de red simplemente deja el estado anterior.
  Future<void> refresh() async {
    if (!_started) return;
    await _loadNotified();
    try {
      final list = await fetch();
      _reminders = list;
      _unread = list.where((r) => _isUnread(r)).length;
      notifyListeners();
      await _notifyNew(list);
      await feedEventWidget();
    } catch (_) {
      // Sin conexión: se conserva el último estado conocido.
    }
  }

  /// Mantiene al día el WIDGET de próximos eventos (inicio de Android / panel
  /// de Windows). Las agendas mandan; si no se pueden leer, se usan los avisos
  /// que ya están en memoria. No lanza nunca.
  Future<void> feedEventWidget() async {
    if (!UpcomingEventsWidget.supported) return;
    if (!UpcomingEventsWidget.autoFeed) return;
    // No en cada consulta: las agendas son más pesadas que los avisos.
    final now = DateTime.now();
    if (now.difference(_lastWidgetFeed) < eventWidgetInterval) return;
    _lastWidgetFeed = now;
    try {
      final agendas = await HsApi.agendas();
      await UpcomingEventsWidget.publish(agendas, reminders: _reminders);
    } catch (_) {
      await UpcomingEventsWidget.publish(const [], reminders: _reminders);
    }
  }

  /// Marca UN aviso como leído (optimista, luego confirma con el server).
  ///
  /// [source] = 'event' (agenda) o 'print' (envío a impresión del equipo).
  /// Para `print` se busca también por origen, porque los ids de las dos
  /// tablas pueden coincidir.
  Future<void> markRead(int id, {String source = 'event'}) async {
    bool same(Map<String, dynamic> r) =>
        _int(r['id']) == id && _sourceOf(r) == source;
    final i = _reminders.indexWhere(same);
    if (i >= 0 && _isUnread(_reminders[i])) {
      _reminders[i] = {..._reminders[i], 'isRead': 1};
      _unread = _reminders.where((r) => _isUnread(r)).length;
      notifyListeners();
    }
    try {
      await HsApi.markReminderRead(id, source: source);
    } catch (_) {
      // El server rechazó: el próximo refresh corrige el estado.
    }
  }

  /// Marca TODOS como leídos.
  Future<void> markAllRead() async {
    if (_unread == 0) return;
    // Copia NUEVA de cada aviso (no mutar en sitio) + UNA sola notificación
    // al final: notificar dentro del bucle reconstruía el diálogo con el
    // conteo inconsistente y el botón "Marcar leídos" se quedaba visible.
    _reminders = [
      for (final r in _reminders) {...r, 'isRead': 1},
    ];
    _unread = 0;
    notifyListeners();
    try {
      await HsApi.markAllRemindersRead();
    } catch (_) {
      // idem: el próximo refresh corrige.
    }
  }

  /// Dispara notificación NATIVA para los avisos que aún no se notificaron.
  /// La decisión de plataforma (Android/iOS) vive en el [notifier]: en web
  /// no hay API nativa y él mismo se omite sin romper.
  Future<void> _notifyNew(List<Map<String, dynamic>> list) async {
    final fresh = <Map<String, dynamic>>[];
    for (final r in list) {
      if (!_isUnread(r)) continue;
      final id = _int(r['id']);
      if (id == null) continue;
      // Los avisos de impresión y los del módulo Notificaciones viven en
      // otra tabla: sus ids pueden chocar con los de la agenda. Se desplazan
      // SOLO para el control de "ya notificado" (la clave que se manda a la
      // bandeja conserva el id real, que es el que luego se marca leído).
      final source = _sourceOf(r);
      final key = source == 'print'
          ? 1000000 + id
          : source == 'notification'
          ? 2000000 + id
          : id;
      if (_notifiedIds.contains(key)) continue;
      _notifiedIds.add(key);
      fresh.add(r);
    }
    if (fresh.isEmpty) return;
    try {
      await notifier.showAll(fresh);
    } catch (_) {
      // Mejor esfuerzo: la campanita sigue siendo el aviso principal.
    }
    await _saveNotified();
  }

  static bool _isUnread(Map<String, dynamic> r) => _int(r['isRead']) == 0;

  /// Origen del aviso: 'event' (agenda) o 'print' (envío a impresión).
  static String _sourceOf(Map<String, dynamic> r) =>
      (r['source'] ?? 'event').toString();

  /// Puebla el estado en PRUEBAS sin red ni polling. No usar en producción.
  void seedForTest(List<Map<String, dynamic>> list) {
    _reminders = list;
    _unread = list.where((r) => _isUnread(r)).length;
    notifyListeners();
  }

  static int? _int(dynamic v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'event_widget.dart';
import 'hs_api.dart';
import 'reminder_notifications_native.dart';

/// Servicio de AVISOS de eventos próximos (falta 1 semana / falta 1 día).
///
/// - Consulta `GET /api/reminders` en segundo plano cada [pollInterval]
///   (mientras hay sesión iniciada).
/// - Cuando llega un aviso NUEVO, dispara una notificación NATIVA en
///   Android (en Windows la campanita con badge cumple ese papel).
/// - Mantiene `unread` y `reminders` reactivos para la campanita de la
///   top bar.
/// - Alimenta el WIDGET de "próximos eventos" (inicio de Android / panel de
///   Windows) con las agendas que vienen, aprovechando este mismo ciclo de
///   refresco.
///
/// Singleton simple: `RemindersService.instance`. El polling se inicia y
/// detiene desde el panel al entrar/salir de sesión.
class RemindersService extends ChangeNotifier {
  RemindersService._();
  static final RemindersService instance = RemindersService._();

  /// Cuánto espera entre consultas al servidor.
  static const Duration pollInterval = Duration(minutes: 5);

  Timer? _timer;

  /// Ids de avisos que YA se notificaron (evita repetir la notificación
  /// en cada ciclo de polling).
  final Set<int> _notifiedIds = <int>{};

  List<Map<String, dynamic>> _reminders = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> get reminders => _reminders;

  int _unread = 0;
  int get unread => _unread;

  bool _started = false;
  bool get started => _started;

  /// Backend de notificaciones nativas. Sustituible en pruebas para no
  /// depender de la plataforma.
  ReminderNotifier notifier = NativeReminderPlugin.instance;

  /// Inicia el polling (seguro llamar varias veces).
  void start() {
    if (_started) return;
    _started = true;
    refresh(); // primer llenado inmediato
    _timer = Timer.periodic(pollInterval, (_) => refresh());
  }

  /// Detiene el polling (al cerrar sesión).
  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  /// Limpia todo (al cerrar sesión): la campanita no debe recordar avisos
  /// de un usuario que ya salió (ni el widget mostrar sus eventos).
  void reset() {
    stop();
    _reminders = <Map<String, dynamic>>[];
    _unread = 0;
    _notifiedIds.clear();
    notifyListeners();
    unawaited(UpcomingEventsWidget.publish(const []));
  }

  /// Consulta los avisos del usuario y actualiza estado.
  /// No lanza: un fallo de red simplemente deja el estado anterior.
  Future<void> refresh() async {
    if (!_started) return;
    try {
      final list = await HsApi.reminders();
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
    try {
      final agendas = await HsApi.agendas();
      await UpcomingEventsWidget.publish(agendas, reminders: _reminders);
    } catch (_) {
      await UpcomingEventsWidget.publish(const [], reminders: _reminders);
    }
  }

  /// Marca UN aviso como leído (optimista, luego confirma con el server).
  Future<void> markRead(int id) async {
    final i = _reminders.indexWhere((r) => _int(r['id']) == id);
    if (i >= 0 && _isUnread(_reminders[i])) {
      _reminders[i] = {..._reminders[i], 'isRead': 1};
      _unread = _reminders.where((r) => _isUnread(r)).length;
      notifyListeners();
    }
    try {
      await HsApi.markReminderRead(id);
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
    _reminders = [for (final r in _reminders) {...r, 'isRead': 1}];
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
      if (id == null || _notifiedIds.contains(id)) continue;
      _notifiedIds.add(id);
      fresh.add(r);
    }
    if (fresh.isEmpty) return;
    try {
      await notifier.showAll(fresh);
    } catch (_) {
      // Mejor esfuerzo: la campanita sigue siendo el aviso principal.
    }
  }

  static bool _isUnread(Map<String, dynamic> r) => _int(r['isRead']) == 0;

  /// Puebla el estado en PRUEBAS sin red ni polling. No usar en producción.
  void seedForTest(List<Map<String, dynamic>> list) {
    _reminders = list;
    _unread = list.where((r) => _isUnread(r)).length;
    notifyListeners();
  }

  static int? _int(dynamic v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));
}

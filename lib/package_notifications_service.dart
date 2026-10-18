import 'dart:async';

import 'package:flutter/widgets.dart'
    show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;
import 'package:flutter/foundation.dart';

import 'hs_api.dart';
import 'reminder_notifications_native.dart';

/// Avisos del PAQUETE del cliente (los manda el estudio desde el panel):
///
///   * «Ya puedes elegir tus fotos».
///   * «Servicio terminado».
///   * Cualquier aviso escrito por el estudio.
///
/// Los trae de `GET /api/my/notifications` cada [pollInterval] mientras hay
/// sesión. Cuando aparece uno NUEVO dispara una notificación nativa (Android;
/// en Windows/web el aviso vive en «Mi paquete»). La campanita de eventos no
/// se mezcla: estos avisos son del paquete, no de la agenda.
///
/// Sin la migración de notificaciones el endpoint devuelve una lista vacía y
/// todo sigue funcionando.
class PackageNotificationsService extends ChangeNotifier
    with WidgetsBindingObserver {
  PackageNotificationsService._();
  static final PackageNotificationsService instance =
      PackageNotificationsService._();

  /// Cada minuto es suficiente: el cliente ve el aviso al abrir «Mi paquete»
  /// y en segundo plano llega como notificación nativa.
  static const Duration pollInterval = Duration(seconds: 60);

  Timer? _timer;
  bool _started = false;

  List<Map<String, dynamic>> _items = const [];
  List<Map<String, dynamic>> get items => _items;

  int _unread = 0;
  int get unread => _unread;

  /// Ids ya notificados en esta sesión (no repetir la notificación nativa).
  final Set<int> _notified = <int>{};

  /// Backend de notificaciones nativas (sustituible en pruebas).
  NativeReminderPlugin notifier = NativeReminderPlugin.instance;

  void start() {
    if (_started) return;
    _started = true;
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // Sin binding (pruebas): el polling funciona igual.
    }
    refresh();
    _timer = Timer.periodic(pollInterval, (_) => refresh());
  }

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

  void reset() {
    stop();
    _items = const [];
    _unread = 0;
    _notified.clear();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _started) refresh();
  }

  /// Consulta los avisos. No lanza: sin red se conserva lo último.
  Future<void> refresh() async {
    if (!_started) return;
    try {
      final data = await HsApi.myNotifications();
      _items = data.items;
      _unread = data.unread;
      notifyListeners();
      await _notifyNew(data.items);
    } catch (_) {
      // Sin conexión: se conserva el último estado conocido.
    }
  }

  Future<void> _notifyNew(List<Map<String, dynamic>> list) async {
    final fresh = <Map<String, dynamic>>[];
    for (final n in list) {
      if (n['isRead'] == true) continue;
      final id = _int(n['id']);
      if (id == null || _notified.contains(id)) continue;
      _notified.add(id);
      fresh.add(n);
    }
    if (fresh.isEmpty) return;
    try {
      await notifier.showPackageAll(fresh);
    } catch (_) {
      // Mejor esfuerzo: «Mi paquete» sigue mostrando el aviso.
    }
  }

  /// Marca UN aviso como leído (optimista + confirmación del servidor).
  Future<void> markRead(int id) async {
    final i = _items.indexWhere((n) => _int(n['id']) == id);
    if (i >= 0 && _items[i]['isRead'] != true) {
      _items = [
        for (var j = 0; j < _items.length; j++)
          if (j == i) {..._items[j], 'isRead': true} else _items[j],
      ];
      _unread = _items.where((n) => n['isRead'] != true).length;
      notifyListeners();
    }
    try {
      await HsApi.markNotificationsRead(ids: [id]);
    } catch (_) {
      // El próximo refresh corrige.
    }
  }

  Future<void> markAllRead() async {
    if (_unread == 0) return;
    _items = [
      for (final n in _items) {...n, 'isRead': true},
    ];
    _unread = 0;
    notifyListeners();
    try {
      await HsApi.markNotificationsRead(all: true);
    } catch (_) {
      // idem.
    }
  }

  /// Puebla el estado en PRUEBAS (sin red ni polling).
  void seedForTest(List<Map<String, dynamic>> list) {
    _items = list;
    _unread = list.where((n) => n['isRead'] != true).length;
    notifyListeners();
  }

  static int? _int(dynamic v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));
}

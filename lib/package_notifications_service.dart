import 'dart:async';

import 'package:flutter/widgets.dart'
    show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Ids ya notificados (no repetir la notificación nativa).
  ///
  /// Se PERSISTEN: si el aviso seguía sin leer, al reabrir la app ya no se
  /// vuelve a notificar el mismo. Así «Avisar al cliente» se ve UNA vez, no
  /// otra vez en cada arranque.
  final Set<int> _notified = <int>{};
  static const _kNotifiedIds = 'app.notified.package';

  /// Backend de notificaciones nativas (sustituible en pruebas).
  PackageNotifier notifier = NativeReminderPlugin.instance;

  /// De dónde se leen los avisos (sustituible en pruebas).
  Future<({List<Map<String, dynamic>> items, int unread})> Function() fetch =
      HsApi.myNotifications;

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
    // Al cerrar sesión también se olvida lo ya notificado: otro usuario en el
    // mismo teléfono tiene que recibir SUS avisos aunque el id coincida.
    unawaited(_clearNotified());
    notifyListeners();
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
        if (id != null) _notified.add(id);
      }
    } catch (_) {
      // Sin storage: la protección vale solo para esta ejecución.
    }
  }

  /// Guarda los ids ya notificados (los últimos 200 bastan: son avisos leídos
  /// o ya mostrados; no hace falta crecer sin límite).
  Future<void> _saveNotified() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final ids = _notified.toList()..sort();
      final keep = ids.length > 200 ? ids.sublist(ids.length - 200) : ids;
      await sp.setString(_kNotifiedIds, keep.join(','));
    } catch (_) {
      // Sin storage: se sigue sin persistir.
    }
  }

  /// SOLO PRUEBAS: olvida el set de la sesión SIN borrar el disco, para
  /// simular «se cerró y se volvió a abrir la app».
  @visibleForTesting
  void forgetNotifiedSession() {
    _notified.clear();
  }

  Future<void> _clearNotified() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_kNotifiedIds);
    } catch (_) {
      // idem
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _started) refresh();
  }

  /// Consulta los avisos. No lanza: sin red se conserva lo último.
  Future<void> refresh() async {
    if (!_started) return;
    await _loadNotified();
    try {
      final data = await fetch();
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
    await _saveNotified();
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

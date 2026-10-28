import 'package:flutter/widgets.dart';

/// ¿La app está A LA VISTA o en segundo plano?
///
/// En segundo plano los sondeos de datos de los módulos se pausan; los
/// servicios de notificaciones siguen comprobando sus avisos. Al volver, la
/// vista y los datos que ya estaban cargados se conservan.
class AppAwake with WidgetsBindingObserver {
  AppAwake._();
  static final AppAwake instance = AppAwake._();

  /// true = la app está a la vista (primer plano).
  bool get awake => _awake;
  bool _awake = true;

  bool _started = false;

  /// Se llama UNA vez, al arrancar la app.
  void start() {
    if (_started) return;
    _started = true;
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // Sin binding (pruebas muy tempranas): la app se considera a la vista.
    }
  }

  /// Deja de escuchar el ciclo de vida (al cerrar la app).
  void stop() {
    if (!_started) return;
    _started = false;
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {
      // idem
    }
  }

  /// Cambió el estado de la ventana.
  ///
  /// En escritorio «inactive» es PERDER EL FOCO (otra ventana pasa al frente) y
  /// «hidden»/«paused» es estar minimizada: los dos son segundo plano. Solo
  /// «resumed» es estar a la vista.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _apply(state == AppLifecycleState.resumed);
  }

  /// SOLO PRUEBAS: simula el cambio de estado de la ventana.
  @visibleForTesting
  void debugSetAwake(bool value) => _apply(value);

  void _apply(bool value) {
    if (value == _awake) return;
    _awake = value;
  }
}

import 'package:flutter/widgets.dart';

import 'image_memory.dart';

/// ¿La app está A LA VISTA o en segundo plano?
///
/// En segundo plano —otra ventana al frente, la app minimizada o el teléfono
/// con la app fuera— el panel **no consulta nada**: lo ÚNICO que sigue
/// consultando son los servicios de notificaciones ([RemindersService] y
/// [PackageNotificationsService]), que es lo único que tiene que enterarse de
/// algo mientras nadie mira. Los demás temporizadores (la versión, el sondeo de
/// Conexión, la portada que cambia de foto) se saltan el turno.
///
/// Al pasar a segundo plano también se sueltan las IMÁGENES decodificadas
/// ([ImageMemory.clearRam]): son lo que más RAM ocupa y se pueden volver a
/// pedir. Al volver, [resumed] sube —el panel lo escucha para recargar todo— y
/// las imágenes se vuelven a pedir solas.
class AppAwake with WidgetsBindingObserver {
  AppAwake._();
  static final AppAwake instance = AppAwake._();

  /// true = la app está a la vista (primer plano).
  bool get awake => _awake;
  bool _awake = true;

  /// Sube cada vez que la app VUELVE a primer plano (el clic en la ventana).
  /// Quien lo escuche, recarga: en segundo plano los datos dejaron de llegar.
  final ValueNotifier<int> resumed = ValueNotifier<int>(0);

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
    if (value) {
      resumed.value++;
    } else {
      ImageMemory.clearRam();
    }
  }
}

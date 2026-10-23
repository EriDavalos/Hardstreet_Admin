import 'package:flutter/foundation.dart';

/// Un paso de «atrás»: devuelve `true` si ya atendió el gesto (subir de
/// carpeta, deseleccionar, cerrar una sub-vista…).
typedef BackStep = bool Function();

/// CADENA ÚNICA del botón «atrás» (Android, gesto del celular y botón del
/// navegador en la web).
///
/// Antes cada pantalla ponía su propio `PopScope`; dentro de la web el atrás
/// del navegador no pasaba por ninguno cuando el panel estaba en la raíz de un
/// módulo, así que **salía de la app**. Aquí los pasos se registran en orden de
/// montaje y se atienden del MÁS ESPECÍFICO (el último en montarse) al más
/// general: una carpeta abierta dentro de Archivos compartidos atiende antes
/// que el listado del módulo, y el panel atiende al final.
///
/// El panel (`AdminHome`) es quien instala el `PopScope` raíz y quien decide lo
/// último: volver al módulo de inicio o preguntar si se quiere salir.
class BackNav {
  BackNav._();

  static final List<BackStep> _steps = <BackStep>[];

  /// Registra un paso. Cada pantalla guarda su propia referencia (un campo)
  /// para poder quitarla al desmontarse.
  static void add(BackStep step) {
    if (!_steps.contains(step)) _steps.add(step);
  }

  static void remove(BackStep step) => _steps.remove(step);

  /// ¿Hay pantallas esperando un atrás? (Para las pruebas y diagnósticos.)
  static bool get isEmpty => _steps.isEmpty;

  /// Atiende un atrás: recorre la cadena de arriba abajo y se detiene en el
  /// primer paso que lo consuma. `false` = nadie lo atendió (el panel decide).
  static bool handle() {
    // Copia: un paso puede desmontar su pantalla y tocar la lista.
    for (final step in List<BackStep>.of(_steps.reversed)) {
      var consumed = false;
      try {
        consumed = step();
      } catch (error, stack) {
        // Un paso roto no debe tumbar la app (ni dejar el atrás sin atender).
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'hardstreet',
            context: ErrorDescription('atendiendo el botón atrás'),
          ),
        );
      }
      if (consumed) return true;
    }
    return false;
  }

  /// Solo para pruebas: deja la cadena vacía.
  @visibleForTesting
  static void resetForTest() => _steps.clear();
}

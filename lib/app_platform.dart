import 'package:flutter/foundation.dart' show kIsWeb;

import 'dart:io' if (dart.library.io) 'dart:io';

/// Detección de plataforma SEGURA para web: `Platform.isAndroid/isWindows`
/// y `Platform.environment` lanzan en Chrome (dart:io no existe ahí).
/// Usa siempre estos helpers en lugar de `Platform.*` directo.

const bool kWeb = kIsWeb;

/// Un Dart HTML no existe Platform.environment: en web devuelve vacío.
Map<String, String> get platformEnvironment =>
    kWeb ? const {} : Platform.environment;

/// ¿Corremos dentro de `flutter test`? (el WebView nativo no existe ahí).
bool get isTestEnvironment => platformEnvironment.containsKey('FLUTTER_TEST');

/// ¿Hay que desactivar el chequeo de versión (tests / web sin backend)?
bool get skipVersionCheck => kWeb || isTestEnvironment;

/// ¿Esta build corre en Android? (false en web)
bool get isAndroidPlatform => !kWeb && Platform.isAndroid;

/// ¿Esta build corre en iOS? (false en web)
bool get isIOSPlatform {
  if (kWeb) return false;
  try {
    return Platform.isIOS;
  } catch (_) {
    return false;
  }
}

/// ¿Esta build corre en Windows? (false en web)
bool get isWindowsPlatform => !kWeb && Platform.isWindows;

/// ¿El arrastre de archivos exige PRESIÓN LARGA?
/// En móvil evita mover carpetas por accidente al hacer scroll:
/// hay que mantener presionado ~350ms para empezar a arrastrar.
/// En escritorio (Windows) el arrastre sigue siendo inmediato.
bool get useLongPressDrag {
  if (kWeb) return false;
  try {
    return Platform.isAndroid || Platform.isIOS;
  } catch (_) {
    return false;
  }
}

/// ¿Se pueden ARRASTRAR las tarjetas del Drive?
///
/// En la versión WEB abierta en un TELÉFONO, NO: el dedo está para scrollear,
/// y arrastrar la carpeta en vez de bajar la lista era el problema. Mover y
/// copiar siguen disponibles desde las acciones de la selección. En la app
/// móvil (Android/iOS) se mantiene el arrastre con presión larga y en
/// escritorio es inmediato.
bool driveCardDragAllowed({required bool web, required bool phone}) =>
    !(web && phone);

/// Nombre legible de la plataforma actual (para diagnósticos).
String get platformName {
  if (kWeb) return 'web';
  try {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isIOS) return 'ios';
  } catch (_) {}
  return 'desconocida';
}

import 'package:flutter/services.dart';

import 'app_platform.dart';

/// Pantalla completa REAL de la ventana (solo Windows).
///
/// En la app de escritorio el visor no puede usar la API del navegador: el
/// WebView2 no cambia el tamaño de la VENTANA. Antes el botón solo escondía la
/// barra del panel, así que parecía que "no hacía nada". Aquí se le pide al
/// runner de Windows, que guarda el estilo y el tamaño de la ventana y la pone
/// sin bordes sobre el monitor; al salir la deja como estaba.
///
/// En Android se usa el modo inmersivo de Flutter y en web la API del
/// navegador, así que esta función no hace nada allí.
Future<void> hsSetWindowFullscreen(bool on) async {
  if (!isWindowsPlatform || isTestEnvironment) return;
  try {
    await _channel.invokeMethod<bool>('setFullscreen', on);
  } catch (_) {
    // Un .exe viejo sin el canal: se queda el modo inmersivo de siempre.
  }
}

const MethodChannel _channel = MethodChannel('hardstreet/window');

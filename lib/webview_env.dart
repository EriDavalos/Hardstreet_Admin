import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

import 'app_platform.dart';

/// Entorno de WebView2 COMPARTIDO por todo el panel.
///
/// En Windows, el WebView guarda sus datos en una carpeta junto al `.exe` si no
/// se le dice otra. En `flutter run` esa carpeta se puede escribir (está dentro
/// del build), pero cuando la app se INSTALA en `Archivos de programa` no: el
/// WebView no llega a arrancar y el reproductor de vídeo queda en negro solo en
/// el .exe instalado. Ese era el \"en pruebas funciona, en release no\".
///
/// Aquí el entorno se crea UNA vez, en una carpeta de datos del usuario que
/// siempre se puede escribir, y lo usan el visor de vídeo y la vista del sitio.
Future<WebViewEnvironment?> sharedWebViewEnvironment() {
  if (!isWindowsPlatform || isTestEnvironment) return Future.value(null);
  return _environment ??= _create();
}

Future<WebViewEnvironment?>? _environment;

Future<WebViewEnvironment?> _create() async {
  try {
    final dir = await getApplicationSupportDirectory();
    final folder = Directory('${dir.path}${Platform.pathSeparator}webview2');
    await folder.create(recursive: true);
    // Un tope: si WebView2 no contesta, el visor no puede quedarse girando
    // para siempre (se intenta el entorno de fábrica).
    return await WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(
        userDataFolder: folder.path,
        // Los vídeos del Drive tienen que arrancar SOLOS: sin esto WebView2
        // aplica la misma política que Edge y bloquea el arranque con sonido
        // hasta que el usuario toca el vídeo (se quedaba en el póster).
        additionalBrowserArguments:
            '--autoplay-policy=no-user-gesture-required',
      ),
    ).timeout(const Duration(seconds: 6));
  } catch (_) {
    // Sin entorno propio se usa el de fábrica. En una instalación normal bajo
    // Archivos de programa fallará, pero eso ya no depende de esta app.
    return null;
  }
}

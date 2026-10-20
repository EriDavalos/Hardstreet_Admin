import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// iframes ya registrados: `registerViewFactory` no admite dos veces el mismo
/// tipo de vista y el widget puede reconstruirse.
final Set<String> _registered = <String>{};

/// Reproductor HTML5 para Flutter Web.
///
/// El HTML es el mismo que usa el WebView de escritorio/Android, así que la
/// interfaz, el póster y los mensajes de error son idénticos. Se incrusta en un
/// iframe para que los controles del vídeo no compitan con los gestos del
/// panel y para poder usar `requestFullscreen`.
Widget driveWebPlayer(
  BuildContext context, {
  required String html,
  required String cacheKey,
}) {
  final viewType = 'hs-drive-player-$cacheKey';
  if (_registered.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final frame = web.HTMLIFrameElement()
        ..setAttribute('srcdoc', html)
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.background = '#0a0a0f'
        ..setAttribute(
          'allow',
          'autoplay; fullscreen; encrypted-media; picture-in-picture',
        )
        ..setAttribute('allowfullscreen', 'true');
      return frame;
    });
  }
  return HtmlElementView(viewType: viewType);
}

import 'package:url_launcher/url_launcher.dart';

/// Abre [url] con la app del sistema (navegador, Google Maps…) en Windows,
/// macOS, Linux, Android o iOS.
///
/// Antes se lanzaba `cmd /c start` en Windows: el `&` de la liga de Maps se
/// interpretaba como separador de comandos y la ubicación se perdía. En el
/// celular se intentaba `xdg-open`, que no existe en Android/iOS.
Future<bool> openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    return false;
  }
  try {
    // El sistema decide si abrir el navegador o la app de mapas instalada.
    return await launchUrl(uri);
  } catch (_) {
    return false;
  }
}

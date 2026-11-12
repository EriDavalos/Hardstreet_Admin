import 'package:web/web.dart' as web;

/// Abre [url] en una pestaña nueva del navegador.
Future<bool> openUrl(String url) async {
  if (!url.startsWith('http://') && !url.startsWith('https://')) return false;
  web.window.open(url, '_blank');
  return true;
}

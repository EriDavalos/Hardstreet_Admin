import 'open_url_io.dart' if (dart.library.js_interop) 'open_url_web.dart';

/// Abre una dirección http(s) en el navegador (o en la app que corresponda)
/// del equipo. `false` si no se pudo.
Future<bool> hsOpenUrl(String url) => openUrl(url);

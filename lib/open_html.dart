import 'open_html_io.dart'
    if (dart.library.js_interop) 'open_html_web.dart';

// ==================================================================
// VER LA TARJETA EN EL NAVEGADOR
// ==================================================================
// El diseñador genera la tarjeta como HTML (con el mismo markup y los mismos
// valores CSS que la web) y la abre en el navegador del sistema: así se ve la
// tarjeta REAL, a tamaño completo, sin meter un WebView nativo en la app (eso
// obligaba a NuGet/WebView2 en la compilación de Windows).
// ==================================================================

/// Abre [html] en el navegador del sistema. `false` si no se pudo (en la web
/// no aplica: allí se usa la vista previa nativa).
Future<bool> hsOpenHtmlInBrowser(String html) => openHtmlInBrowser(html);

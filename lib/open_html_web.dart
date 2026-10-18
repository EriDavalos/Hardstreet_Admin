// En el navegador no hay archivos temporales: la tarjeta se ve en la vista
// previa nativa (o se genera el HTML desde el diseñador del escritorio).

/// No disponible en la web.
Future<bool> openHtmlInBrowser(String html) async => false;

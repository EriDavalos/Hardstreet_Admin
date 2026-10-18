import 'site_preview_server_stub.dart'
    if (dart.library.io) 'site_preview_server_io.dart' as impl;

/// URL base del SITIO REAL empaquetado con la app, servido en loopback.
///
/// La vista previa del editor HTML abre ese sitio en un WebView: así se ve con
/// el MISMO HTML, CSS, tipografías e imágenes que la web (no una maqueta hecha
/// en Flutter). Devuelve `null` en la web (no hay `dart:io` para servir).
Future<String?> sitePreviewBaseUrl() => impl.sitePreviewBaseUrl();

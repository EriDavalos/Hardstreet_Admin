import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// ¿El navegador corre en un CELULAR o tableta?
///
/// En el teléfono (incluso si es la web) las fotos se descargan UNA POR UNA:
/// el usuario espera sus imágenes sueltas en Descargas/Galería, no un ZIP que
/// muchos navegadores móviles ni siquiera saben descomprimir.
bool isMobileBrowser() {
  final ua = web.window.navigator.userAgent.toLowerCase();
  if (ua.contains('android') || ua.contains('iphone') || ua.contains('ipod')) {
    return true;
  }
  // El iPad moderno se identifica como Mac: solo el "Mobile" lo delata.
  return ua.contains('mobile');
}

/// Descarga en el navegador (web): crea un blob y dispara <a download>.
/// Usa package:web + dart:js_interop (dart:html está deprecado).
void triggerBrowserDownload(List<int> bytes, String filename) {
  final data = Uint8List.fromList(bytes);
  final parts = <web.BlobPart>[data.toJS].toJS;
  final blob = web.Blob(
    parts,
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  // Se revoca en el siguiente ciclo: si se revoca al instante, Safari/iOS
  // cancela la descarga antes de empezar.
  Future<void>.delayed(
    const Duration(seconds: 20),
    () => web.URL.revokeObjectURL(url),
  );
}

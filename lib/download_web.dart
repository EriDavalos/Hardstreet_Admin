import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

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
  web.URL.revokeObjectURL(url);
}

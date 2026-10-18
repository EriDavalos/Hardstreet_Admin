import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

// ==================================================================
// SERVIDOR LOCAL DEL SITIO (solo en la app nativa)
// ==================================================================
// El editor HTML del módulo "Sitio web" necesita ver la sección con el MISMO
// HTML y CSS que la web. Para eso el sitio real viaja EMPAQUETADO en la app
// (`assets/site/`: index.html, index.css, index.js, gallery/assets/*.js e
// imágenes) y se sirve en un puerto loopback.
//
// El WebView abre `http://127.0.0.1:<puerto>/` y ve el sitio de verdad: las
// tipografías, las imágenes relativas (`./images/…`), las animaciones y el CSS
// completo. El panel no re-dibuja nada en Flutter.
//
// * Solo escucha en 127.0.0.1 (nadie de la red entra).
// * Solo GET/HEAD y sin `..` en la ruta (no se puede salir de los assets).
// * Se levanta una sola vez y vive lo que vive la app.
// ==================================================================

HttpServer? _server;
String? _base;

/// Levanta (una sola vez) el servidor y devuelve su URL base.
Future<String?> sitePreviewBaseUrl() async {
  if (_base != null) return _base;
  try {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.autoCompress = true;
    _server = server;
    _base = 'http://127.0.0.1:${server.port}';
    server.listen(_serve, onError: (_) {});
    return _base;
  } catch (_) {
    // Sin permiso para abrir el puerto: el editor enseñará su aviso.
    return null;
  }
}

/// Detiene el servidor (tests / cierre ordenado).
Future<void> stopSitePreviewServer() async {
  final server = _server;
  _server = null;
  _base = null;
  await server?.close(force: true);
}

const Map<String, String> _contentTypes = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.mp4': 'video/mp4',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
};

Future<void> _serve(HttpRequest req) async {
  final res = req.response;
  res.headers.set('Cache-Control', 'no-store, max-age=0');
  if (req.method != 'GET' && req.method != 'HEAD') {
    res.statusCode = HttpStatus.methodNotAllowed;
    await res.close();
    return;
  }

  var path = Uri.decodeComponent(req.uri.path);
  if (path.isEmpty || path == '/') path = '/index.html';
  // Nunca salir de la carpeta del sitio.
  if (path.contains('..') || path.contains('\\')) {
    res.statusCode = HttpStatus.notFound;
    await res.close();
    return;
  }

  final asset = 'assets/site$path';
  try {
    final data = await rootBundle.load(asset);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final dot = path.lastIndexOf('.');
    final type = dot >= 0
        ? (_contentTypes[path.substring(dot).toLowerCase()] ??
              'application/octet-stream')
        : 'application/octet-stream';
    res.headers.set(HttpHeaders.contentTypeHeader, type);
    res.contentLength = bytes.length;
    if (req.method == 'GET') res.add(bytes);
    await res.close();
  } catch (_) {
    res.statusCode = HttpStatus.notFound;
    await res.close();
  }
}

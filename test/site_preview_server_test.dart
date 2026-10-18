import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hardstreet_admin/site_preview_server_io.dart';

// ==================================================================
// SERVIDOR DE LA VISTA PREVIA (sitio real empaquetado)
// ==================================================================
// El editor HTML abre el SITIO DE VERDAD desde `assets/site/`, servido en
// loopback. Aquí se comprueba, con peticiones HTTP reales, que:
//
//   * el sitio y su CSS/JS salen con el tipo correcto (el WebView los pinta);
//   * no se puede salir de la carpeta del sitio (`..`);
//   * sólo se atiende GET/HEAD.
//
// Es la parte que se puede verificar sin abrir un WebView.
// ==================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('el sitio empaquetado se sirve en loopback', () async {
    // flutter_test intercepta HttpClient por defecto (responde 400): para
    // hablar con NUESTRO servidor local se usa el HttpClient real.
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() {
      HttpOverrides.global = previous;
      return stopSitePreviewServer();
    });

    final base = await sitePreviewBaseUrl();
    expect(base, isNotNull, reason: 'Debe abrir un puerto en 127.0.0.1');
    expect(base, startsWith('http://127.0.0.1:'));

    final client = HttpClient();
    addTearDown(client.close);

    Future<HttpClientResponse> fetch(String path, {String method = 'GET'}) async {
      final req = await client.openUrl(method, Uri.parse('$base$path'));
      return req.close();
    }

    // La portada: el HTML real, con sus secciones.
    final home = await fetch('/');
    expect(home.statusCode, 200);
    expect(home.headers.contentType?.mimeType, 'text/html');
    final html = await utf8.decodeStream(home);
    expect(html, contains('data-hs-section="hero"'));
    expect(html, contains('index.css'));
    expect(html, contains('index.js'));

    // El CSS y el JS (los pinta el WebView tal cual).
    final css = await fetch('/index.css');
    expect(css.statusCode, 200);
    expect(css.headers.contentType?.mimeType, 'text/css');
    await css.drain<void>();

    final js = await fetch('/gallery/assets/site.js');
    expect(js.statusCode, 200);
    expect(js.headers.contentType?.mimeType, 'text/javascript');
    await js.drain<void>();

    // Una imagen del sitio (las rutas relativas del HTML).
    final img = await fetch('/images/LOG.png');
    expect(img.statusCode, 200);
    expect(img.headers.contentType?.mimeType, 'image/png');
    await img.drain<void>();

    // No se sale de la carpeta del sitio.
    for (final path in ['/../pubspec.yaml', '/..%2Fpubspec.yaml', '/%2e%2e/x']) {
      final bad = await fetch(path);
      expect(bad.statusCode, 404, reason: 'No debe servir $path');
      await bad.drain<void>();
    }

    // Sólo GET/HEAD.
    final post = await fetch('/', method: 'POST');
    expect(post.statusCode, 405);
    await post.drain<void>();

    // HEAD: las cabeceras sí, el cuerpo no.
    final head = await fetch('/index.html', method: 'HEAD');
    expect(head.statusCode, 200);
    expect(head.contentLength, greaterThan(0));
    expect(await head.isEmpty, isTrue);
  });
}

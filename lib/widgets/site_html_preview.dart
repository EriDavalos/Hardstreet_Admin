import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../site_preview_server.dart';
import '../webview_env.dart';

// ==================================================================
// VISTA PREVIA REAL DEL SITIO (WebView)
// ==================================================================
// No es una maqueta de Flutter: es el SITIO DE VERDAD (index.html + index.css +
// index.js + imágenes) servido en loopback desde los assets de la app. El
// WebView lo abre, oculta las demás secciones y escribe dentro de la sección
// el HTML que se está editando. Así el panel enseña EXACTAMENTE lo que verá el
// visitante: tipografías, rejillas, animaciones, botones y fotos.
//
// También puede hacer lo contrario (`capture`): leer el innerHTML que la
// sección tiene AHORA en el sitio (con los textos y fotos ya aplicados) para
// empezar a editarlo.
// ==================================================================

/// Control remoto de la vista previa (lo usa el diálogo del editor).
class SiteHtmlPreviewController {
  _SiteHtmlPreviewState? _state;

  void _attach(_SiteHtmlPreviewState s) => _state = s;

  void _detach(_SiteHtmlPreviewState s) {
    if (_state == s) _state = null;
  }

  /// HTML actual de la sección en el sitio ('' si aún no cargó).
  Future<String?> capture() async => _state?.capture();

  Future<void> reload() async => _state?.reload();

  /// ¿Ya hay una vista montada? (para habilitar los botones)
  bool get attached => _state != null;
}

class SiteHtmlPreview extends StatefulWidget {
  const SiteHtmlPreview({
    super.key,
    required this.sectionId,
    required this.html,
    this.controller,
  });

  /// `data-hs-section` de la sección que se está editando (`hero`, `gallery-2`…).
  final String sectionId;

  /// Contenido HTML que se pinta dentro de la sección ('' = el original).
  final String html;

  final SiteHtmlPreviewController? controller;

  @override
  State<SiteHtmlPreview> createState() => _SiteHtmlPreviewState();
}

class _SiteHtmlPreviewState extends State<SiteHtmlPreview> {
  String? _base;
  String? _error;
  InAppWebViewController? _web;
  WebViewEnvironment? _env;
  bool _loaded = false;
  Timer? _late;
  int _injectSeq = 0;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _boot();
  }

  @override
  void didUpdateWidget(covariant SiteHtmlPreview old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._detach(this);
      widget.controller?._attach(this);
    }
    if (old.sectionId != widget.sectionId) {
      _loaded = false;
      reload();
    } else if (old.html != widget.html && _loaded) {
      _inject();
    }
  }

  @override
  void dispose() {
    _late?.cancel();
    widget.controller?._detach(this);
    super.dispose();
  }

  Future<void> _boot() async {
    final base = await sitePreviewBaseUrl();
    if (!mounted) return;
    if (base == null) {
      setState(() => _error =
          'Esta plataforma no puede mostrar la vista previa del sitio.');
      return;
    }
    // En Windows el WebView2 necesita una carpeta de datos ESCRIBIBLE: la de
    // junto al .exe falla cuando la app está instalada en Archivos de programa.
    // Es el MISMO entorno que usa el visor de vídeo (ver `webview_env.dart`).
    _env = await sharedWebViewEnvironment();
    if (!mounted) return;
    setState(() => _base = base);
  }

  Future<void> reload() async {
    setState(() => _loaded = false);
    await _web?.reload();
  }

  Future<String?> capture() async {
    final web = _web;
    if (web == null) return null;
    final result = await web.evaluateJavascript(source: _captureJs);
    final text = result?.toString() ?? '';
    // Algunas plataformas devuelven el valor entre comillas JSON.
    if (text.startsWith('"') && text.endsWith('"') && text.length > 1) {
      try {
        return (jsonDecode(text) as Object?)?.toString() ?? '';
      } catch (_) {
        return text;
      }
    }
    return text == 'null' ? null : text;
  }

  String get _captureJs => '''
(function(){
  var s = document.querySelector('[data-hs-section="${_esc(widget.sectionId)}"]');
  return s ? s.innerHTML : '';
})();
''';

  /// JS que deja SOLO la sección editada, con el HTML que se está escribiendo.
  String get _injectJs => '''
(function(){
  var id = ${jsonEncode(widget.sectionId)};
  var html = ${jsonEncode(widget.html)};
  var sec = document.querySelector('[data-hs-section="' + id + '"]');
  if (!sec) return 'missing';
  var style = document.getElementById('hs-edit-style');
  if (!style) {
    style = document.createElement('style');
    style.id = 'hs-edit-style';
    style.textContent = [
      'html,body{background:#0a0a0a !important;cursor:auto !important;}',
      '.navbar,.loader,.grain,.cursor-dot,.cursor-ring,.whatsapp-float{display:none !important;}',
      '.reveal,.reveal-left,.reveal-right,.reveal-up,.reveal-scale{opacity:1 !important;transform:none !important;}'
    ].join('');
    document.head.appendChild(style);
  }
  document.querySelectorAll('[data-hs-section]').forEach(function(el){
    el.style.display = el === sec ? '' : 'none';
  });
  var nav = document.getElementById('navbar');
  if (nav) nav.style.display = 'none';
  if (html) sec.innerHTML = html;
  sec.style.display = '';
  // Las animaciones de entrada se dan por vistas (el sitio usa `.active`).
  sec.querySelectorAll('.reveal,.reveal-left,.reveal-right,.reveal-up,.reveal-scale')
    .forEach(function(el){
      el.classList.add('active');
      el.style.opacity = '';
      el.style.transform = '';
    });
  var top = sec.getBoundingClientRect().top + window.scrollY;
  window.scrollTo(0, Math.max(0, top));
  return 'ok';
})();
''';

  /// Escapa comillas para meter el id en una cadena JS.
  static String _esc(String v) => v
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll("'", "\\'");

  Future<void> _inject() async {
    final web = _web;
    if (web == null) return;
    final seq = ++_injectSeq;
    try {
      // El sitio aplica su contenido DESPUÉS del `load` (consulta la API): se
      // espera a que el plan exista para que no lo pise lo guardado.
      for (var i = 0; i < 16; i++) {
        final ready = await web.evaluateJavascript(
          source: 'typeof window.HS_SITE_CONTENT !== "undefined"',
        );
        if (ready == true || ready.toString() == 'true') break;
        await Future<void>.delayed(const Duration(milliseconds: 150));
        if (!mounted || seq != _injectSeq) return;
      }
      if (!mounted || seq != _injectSeq) return;
      await web.evaluateJavascript(source: _injectJs);
      if (!mounted || seq != _injectSeq) return;
      setState(() => _loaded = true);
      // Una segunda pasada por si el sitio terminó de pintar justo después.
      _late?.cancel();
      _late = Timer(const Duration(milliseconds: 1200), () {
        if (mounted && seq == _injectSeq) _inject();
      });
    } catch (_) {
      // Si el JS falla (sitio a medio cargar), la vista queda como esté.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_error != null) {
      return _Notice(scheme: scheme, message: _error!);
    }
    final base = _base;
    if (base == null) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    return Stack(
      children: [
        InAppWebView(
          webViewEnvironment: _env,
          initialUrlRequest: URLRequest(url: WebUri('$base/')),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            transparentBackground: false,
            supportZoom: true,
          ),
          onWebViewCreated: (controller) {
            _web = controller;
          },
          onLoadStop: (controller, url) {
            _inject();
            // Red de seguridad: si el sitio tarda en pintar, se repite.
            Future<void>.delayed(const Duration(milliseconds: 2200), () {
              if (mounted) _inject();
            });
          },
          onReceivedError: (controller, request, error) {
            if (!mounted || request.isForMainFrame != true) return;
            setState(() => _error =
                'No se pudo abrir la vista previa (${error.description}).');
          },
        ),
        if (!_loaded)
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .62),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: .14)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Cargando el sitio…',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.scheme, required this.message});

  final ColorScheme scheme;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public_off_rounded, size: 34, color: scheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              'El HTML se guarda igual: la web lo mostrará al instante.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurfaceVariant.withValues(alpha: .8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

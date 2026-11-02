import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../webview_env.dart';

// ==================================================================
// VISTA PREVIA REAL DE LA INVITACIÓN (WebView)
// ==================================================================
// No es una maqueta de Flutter: es el MISMO HTML/CSS/JS que
// `buildInvitationHtml` guarda y sirve en la liga /i/<liga>. Así el editor
// enseña exactamente lo que verá el cliente: el sobre, las guirnaldas, la
// tiara, las polaroids, la cuenta regresiva, las cintas y el confeti.
//
// En pruebas y en la web se usa la versión de Flutter (no hay WebView).
// ==================================================================

class InvitationHtmlPreview extends StatefulWidget {
  const InvitationHtmlPreview({super.key, required this.html});

  /// Documento completo que se publica.
  final String html;

  @override
  State<InvitationHtmlPreview> createState() => _InvitationHtmlPreviewState();
}

class _InvitationHtmlPreviewState extends State<InvitationHtmlPreview> {
  static final WebUri _base = WebUri('https://hardstreet.com/invitacion');

  InAppWebViewController? _web;
  WebViewEnvironment? _env;
  Timer? _reload;

  @override
  void initState() {
    super.initState();
    _bootEnvironment();
  }

  /// El WebView2 de Windows necesita su carpeta de datos escribible.
  Future<void> _bootEnvironment() async {
    final env = await sharedWebViewEnvironment();
    if (mounted) setState(() => _env = env);
  }

  @override
  void didUpdateWidget(covariant InvitationHtmlPreview old) {
    super.didUpdateWidget(old);
    if (old.html == widget.html) return;
    // Mientras se escribe no se recarga en cada tecla: se espera un momento.
    _reload?.cancel();
    _reload = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _load() async {
    final web = _web;
    if (web == null) return;
    await web.loadData(
      data: widget.html,
      mimeType: 'text/html',
      encoding: 'utf-8',
      baseUrl: _base,
    );
  }

  @override
  void dispose() {
    _reload?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE8CFCD),
      child: InAppWebView(
        webViewEnvironment: _env,
        initialData: InAppWebViewInitialData(
          data: widget.html,
          mimeType: 'text/html',
          encoding: 'utf-8',
          baseUrl: _base,
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          supportZoom: false,
          disableContextMenu: true,
          transparentBackground: false,
        ),
        onWebViewCreated: (controller) => _web = controller,
      ),
    );
  }
}

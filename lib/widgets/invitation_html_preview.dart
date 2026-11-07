import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../webview_env.dart';
import 'invitation_html_editor.dart';

// ==================================================================
// VISTA PREVIA REAL DE LA INVITACIÓN (WebView)
// ==================================================================
// No es una maqueta de Flutter: es el MISMO HTML/CSS/JS que
// `buildInvitationHtml` guarda y sirve en la liga /i/<liga>. Así el editor
// enseña exactamente lo que verá el cliente: el sobre, las guirnaldas, la
// tiara, las polaroids, la cuenta regresiva, las cintas y el confeti.
//
// En el editor se inyecta una capa de CSS/JS que añade la barra de editar y
// quitar al pasar el ratón. Esa capa NO se guarda en el documento público.
//
// En pruebas y en la web se usa la versión de Flutter (no hay WebView).
// ==================================================================

class InvitationHtmlPreview extends StatefulWidget {
  const InvitationHtmlPreview({
    super.key,
    required this.html,
    this.editor = false,
    this.openAtStart = false,
    this.onEditComponent,
    this.onRemoveComponent,
    this.onMoveComponent,
  });

  /// Documento completo que se publica.
  final String html;

  /// Añade la capa de edición al documento (solo para el lienzo).
  final bool editor;

  /// En el editor, oculta la portada y abre la invitación.
  final bool openAtStart;

  final ValueChanged<String>? onEditComponent;
  final ValueChanged<String>? onRemoveComponent;

  /// `beforeKey == null` significa mover al final del flujo.
  final void Function(String key, String? beforeKey)? onMoveComponent;

  @override
  State<InvitationHtmlPreview> createState() => _InvitationHtmlPreviewState();
}

class _InvitationHtmlPreviewState extends State<InvitationHtmlPreview> {
  static final WebUri _base = WebUri('https://hardstreet.com/invitacion');

  InAppWebViewController? _web;
  WebViewEnvironment? _env;
  Timer? _reload;

  String get _document => widget.editor
      ? injectInvitationEditor(widget.html, openAtStart: widget.openAtStart)
      : widget.html;

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
    if (old.html == widget.html &&
        old.editor == widget.editor &&
        old.openAtStart == widget.openAtStart) {
      return;
    }
    // Mientras se escribe no se recarga en cada tecla: se espera un momento.
    _reload?.cancel();
    _reload = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _load() async {
    final web = _web;
    if (web == null) return;
    await web.loadData(
      data: _document,
      mimeType: 'text/html',
      encoding: 'utf-8',
      baseUrl: _base,
    );
  }

  /// Puente con la barra inyectada en el HTML real.
  void _onEditorMessage(List<dynamic> args) {
    if (args.isEmpty) return;
    final raw = args.first;
    if (raw is! Map) return;
    final data = Map<String, dynamic>.from(raw);
    final key = (data['key'] ?? '').toString().trim();
    if (key.isEmpty) return;
    final action = (data['action'] ?? '').toString();
    switch (action) {
      case 'edit':
        widget.onEditComponent?.call(key);
      case 'remove':
        widget.onRemoveComponent?.call(key);
      case 'move':
        final before = data['before']?.toString().trim();
        widget.onMoveComponent?.call(
          key,
          before == null || before.isEmpty ? null : before,
        );
    }
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
          data: _document,
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
        onWebViewCreated: (controller) {
          _web = controller;
          controller.addJavaScriptHandler(
            handlerName: 'hsEditor',
            callback: _onEditorMessage,
          );
        },
      ),
    );
  }
}

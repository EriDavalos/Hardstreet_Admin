import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'site_html_preview.dart';

// ==================================================================
// EDITOR DE HTML DE UNA SECCIÓN (módulo "Sitio web")
// ==================================================================
// Izquierda: el HTML de la sección, con botones para insertar las etiquetas
// que el sitio ya estiliza (título, etiqueta, párrafo, botón, imagen…).
// Derecha: la VISTA PREVIA REAL — el sitio empaquetado en un WebView con el
// HTML tecleado dentro de la sección (ver `site_html_preview.dart`).
//
// "Cargar HTML actual" lee del sitio lo que la sección tiene ahora mismo (con
// los textos y fotos guardados) para empezar a editarlo sin reescribirlo.
//
// Guardar: el diálogo devuelve el HTML; el módulo lo deja en su borrador y lo
// persiste con "Guardar cambios" (igual que el resto de los campos).
// ==================================================================

/// Cómo se construye la vista previa. Se puede sustituir en las pruebas (el
/// WebView nativo no existe en el entorno de tests).
typedef SiteHtmlPreviewBuilder = Widget Function(
  BuildContext context,
  SiteHtmlPreviewController controller,
  String sectionId,
  String html,
);

Future<String?> showSiteHtmlEditor(
  BuildContext context, {
  required String sectionId,
  required String sectionLabel,
  required String sectionTemplate,
  required String initialHtml,
  SiteHtmlPreviewBuilder? previewBuilder,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (_) => SiteHtmlEditorDialog(
      sectionId: sectionId,
      sectionLabel: sectionLabel,
      sectionTemplate: sectionTemplate,
      initialHtml: initialHtml,
      previewBuilder: previewBuilder,
    ),
  );
}

class SiteHtmlEditorDialog extends StatefulWidget {
  const SiteHtmlEditorDialog({
    super.key,
    required this.sectionId,
    required this.sectionLabel,
    required this.sectionTemplate,
    required this.initialHtml,
    this.previewBuilder,
  });

  final String sectionId;
  final String sectionLabel;
  final String sectionTemplate;
  final String initialHtml;
  final SiteHtmlPreviewBuilder? previewBuilder;

  @override
  State<SiteHtmlEditorDialog> createState() => _SiteHtmlEditorDialogState();
}

class _SiteHtmlEditorDialogState extends State<SiteHtmlEditorDialog> {
  late final TextEditingController _code = TextEditingController(
    text: widget.initialHtml,
  );
  final SiteHtmlPreviewController _preview = SiteHtmlPreviewController();
  late String _previewHtml = widget.initialHtml;
  Timer? _debounce;

  /// En pantallas angostas: 0 = HTML, 1 = vista previa.
  int _pane = 0;
  bool _phone = false;
  bool _capturing = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _code.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _code.removeListener(_onChanged);
    _code.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      setState(() => _previewHtml = _code.text);
    });
  }

  Future<void> _capture() async {
    if (_capturing) return;
    setState(() {
      _capturing = true;
      _status = null;
    });
    final html = await _preview.capture();
    if (!mounted) return;
    setState(() {
      _capturing = false;
      if (html == null || html.trim().isEmpty) {
        _status = 'No se pudo leer la sección del sitio. Revisa la conexión y reintenta.';
      } else {
        _code.text = html.trim();
        _status = 'HTML actual cargado. Edítalo y presiona "Usar este HTML".';
      }
    });
  }

  /// Inserta [snippet] en el cursor (o envuelve lo seleccionado con [before]).
  void _insert(String snippet, {String? before, String? after}) {
    final value = _code.value;
    final sel = value.selection;
    if (!sel.isValid) {
      _code.text += snippet;
      return;
    }
    if (before != null && !sel.isCollapsed) {
      final selected = sel.textInside(value.text);
      final out = '$before$selected${after ?? ''}';
      _code.value = value.copyWith(
        text: value.text.replaceRange(sel.start, sel.end, out),
        selection: TextSelection.collapsed(
          offset: sel.start + before.length + selected.length,
        ),
      );
      return;
    }
    final out = before != null ? '$before${after ?? ''}' : snippet;
    _code.value = value.copyWith(
      text: value.text.replaceRange(sel.start, sel.end, out),
      selection: TextSelection.collapsed(
        offset: sel.start + (before != null ? before.length : out.length),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context);
    final wide = screen.width >= 940;
    final height = (screen.height * .86).clamp(420.0, 860.0);

    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1180,
          maxHeight: height,
          minWidth: wide ? 780 : 320,
        ),
        child: Column(
          children: [
            _header(scheme),
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: .5),
            ),
            if (!wide) _paneSwitch(scheme),
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 5, child: _editorPane(scheme)),
                        VerticalDivider(
                          width: 1,
                          color: scheme.outlineVariant.withValues(alpha: .5),
                        ),
                        Expanded(flex: 6, child: _previewPane(scheme)),
                      ],
                    )
                  : IndexedStack(
                      index: _pane,
                      children: [_editorPane(scheme), _previewPane(scheme)],
                    ),
            ),
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: .5),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.brand, AppColors.brandDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.code_rounded,
              color: Colors.white,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'HTML · ${widget.sectionLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        widget.sectionId,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Se escribe DENTRO de la sección: conserva su lugar, su '
                  'visibilidad y el CSS del sitio.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar sin aplicar',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _paneSwitch(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.code_rounded, size: 16),
                  label: Text('HTML'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.visibility_outlined, size: 16),
                  label: Text('Vista previa'),
                ),
              ],
              selected: {_pane},
              onSelectionChanged: (s) => setState(() => _pane = s.first),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Panel izquierdo: el HTML
  // ---------------------------------------------------------------

  Widget _editorPane(ColorScheme scheme) {
    final hasHtml = _code.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _tool(
                'Título',
                'h2',
                () => _insert(
                  '<h2 class="section-title">Título de la sección</h2>',
                  before: '<h2 class="section-title">',
                  after: '</h2>',
                ),
              ),
              _tool(
                'Etiqueta',
                'over',
                () => _insert(
                  '<p class="section-label">Etiqueta</p>',
                  before: '<p class="section-label">',
                  after: '</p>',
                ),
              ),
              _tool(
                'Párrafo',
                'P',
                () => _insert(
                  '<p>Escribe aquí el texto.</p>',
                  before: '<p>',
                  after: '</p>',
                ),
              ),
              _tool(
                'Negrita',
                'B',
                () => _insert(
                  '<strong>texto</strong>',
                  before: '<strong>',
                  after: '</strong>',
                ),
              ),
              _tool(
                'Cursiva',
                'I',
                () => _insert('<em>texto</em>', before: '<em>', after: '</em>'),
              ),
              _tool(
                'Botón',
                'CTA',
                () => _insert(
                  '<a href="#" class="hero-cta">Botón</a>',
                  before: '<a href="#" class="hero-cta">',
                  after: '</a>',
                ),
              ),
              _tool(
                'Imagen',
                'IMG',
                () => _insert('<img src="images/banner.jpg" alt="Foto" />'),
              ),
              _tool(
                'Lista',
                'UL',
                () => _insert(
                  '<ul><li>Primer punto</li><li>Segundo punto</li></ul>',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: .28),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: .6),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: TextField(
                key: const ValueKey('site-html-code'),
                controller: _code,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.5,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(14),
                  hintText:
                      '<div class="about-grid">\n  <div class="about-text">…'
                      '</div>\n</div>',
                  hintStyle: TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _status ??
                      (hasHtml
                          ? '${_code.text.length} caracteres · reemplaza el '
                                'contenido de la sección'
                          : 'Sin HTML propio: la sección se arma con sus '
                                'campos, como siempre.'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: _status != null
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                key: const ValueKey('site-html-capture'),
                onPressed: _capturing ? null : _capture,
                icon: _capturing
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded, size: 16),
                label: const Text('Cargar HTML actual'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tool(String label, String hint, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: hint,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 30),
          textStyle: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .7)),
        ),
        child: Text(label),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Panel derecho: la vista previa real
  // ---------------------------------------------------------------

  Widget _previewPane(ColorScheme scheme) {
    final builder = widget.previewBuilder;
    final preview = builder != null
        ? builder(context, _preview, widget.sectionId, _previewHtml)
        : SiteHtmlPreview(
            sectionId: widget.sectionId,
            html: _previewHtml,
            controller: _preview,
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.visibility_outlined, size: 16),
              const SizedBox(width: 6),
              const Text(
                'Vista previa del sitio',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'real · mismo CSS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              _smallToggle(
                icon: Icons.desktop_windows_outlined,
                tooltip: 'Ancho de escritorio',
                on: !_phone,
                onTap: () => setState(() => _phone = false),
              ),
              const SizedBox(width: 4),
              _smallToggle(
                icon: Icons.smartphone_rounded,
                tooltip: 'Ancho de celular',
                on: _phone,
                onTap: () => setState(() => _phone = true),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Recargar el sitio',
                visualDensity: VisualDensity.compact,
                onPressed: _preview.reload,
                icon: const Icon(Icons.refresh_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: .6),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: _phone ? 390 : double.infinity,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: preview,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallToggle({
    required IconData icon,
    required String tooltip,
    required bool on,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on
                ? scheme.primary.withValues(alpha: .14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: on
                  ? scheme.primary.withValues(alpha: .5)
                  : scheme.outlineVariant.withValues(alpha: .5),
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: on ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _footer() {
    final hasHtml = _code.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          if (hasHtml)
            TextButton.icon(
              onPressed: () {
                _code.clear();
                setState(() => _status = null);
              },
              icon: const Icon(Icons.restart_alt_rounded, size: 16),
              label: const Text('Quitar HTML'),
            ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            key: const ValueKey('site-html-apply'),
            onPressed: () => Navigator.of(context).pop(_code.text.trim()),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(hasHtml ? 'Usar este HTML' : 'Usar el HTML del sitio'),
          ),
        ],
      ),
    );
  }
}

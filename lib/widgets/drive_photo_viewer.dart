import 'package:flutter/material.dart';

import 'drive_thumb.dart';
import 'hs_modal.dart';

// ==================================================================
// VISOR DE UNA FOTO DEL DRIVE (zoom + pantalla completa)
// ==================================================================
// Lo usan el selector de fotos y el módulo «Mis fotos» del paquete. Es el
// mismo lenguaje en celular y escritorio:
//
//   * PELLIZCA / rueda del mouse para acercar (hasta 6x), arrastre para mover.
//   * DOBLE toque: acerca al centro y otro doble toque vuelve a encajar.
//   * Botón de PANTALLA COMPLETA: en escritorio ocupa toda la ventana.
//   * En celular ya abre a pantalla completa, con los botones al alcance.
//
// La imagen se pide con el ancho real de pantalla (`width: 2200`) para que al
// acercar no se vea borrosa.
// ==================================================================

/// Abre [src] en el visor. [onToggle] (opcional) marca/desmarca la foto sin
/// cerrar; [toggleLabel] es el texto del botón.
Future<void> showDrivePhotoViewer(
  BuildContext context, {
  required String name,
  String meta = '',
  required String src,
  String originalSrc = '',
  bool isRemote = false,
  bool picked = false,
  VoidCallback? onToggle,
  String toggleLabel = 'Elegir esta foto',
}) {
  return showHsModal<void>(
    context: context,
    builder: (_) => DrivePhotoViewer(
      name: name,
      meta: meta,
      src: src,
      originalSrc: originalSrc,
      isRemote: isRemote,
      picked: picked,
      onToggle: onToggle,
      toggleLabel: toggleLabel,
    ),
  );
}

class DrivePhotoViewer extends StatefulWidget {
  const DrivePhotoViewer({
    super.key,
    required this.name,
    required this.src,
    this.originalSrc = '',
    required this.isRemote,
    this.meta = '',
    this.picked = false,
    this.onToggle,
    this.toggleLabel = 'Elegir esta foto',
  });

  final String name;
  final String meta;
  final String src;

  /// Original (sin redimensionar). Se pide DESPUÉS de que la miniatura rápida
  /// ya se ve, para abrir al instante y luego ganar detalle sin recargar.
  final String originalSrc;
  final bool isRemote;
  final bool picked;
  final VoidCallback? onToggle;
  final String toggleLabel;

  @override
  State<DrivePhotoViewer> createState() => _DrivePhotoViewerState();
}

class _DrivePhotoViewerState extends State<DrivePhotoViewer> {
  final TransformationController _zoom = TransformationController();
  late bool _picked = widget.picked;
  // La VISTA GRANDE ocupa toda la pantalla también en computadora. El selector
  // sigue siendo un diálogo aparte; solo esta vista se expande.
  bool _full = true;
  bool _showOriginal = false;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _reset() => _zoom.value = Matrix4.identity();

  void _toggleZoom(TapDownDetails details) {
    if (_zoom.value.getMaxScaleOnAxis() > 1.05) {
      _reset();
      return;
    }
    // Acerca 2.5x alrededor del punto tocado.
    final p = details.localPosition;
    _zoom.value = Matrix4.identity()
      ..translateByDouble(-p.dx * 1.5, -p.dy * 1.5, 0, 1)
      ..scaleByDouble(2.5, 2.5, 2.5, 1);
  }

  @override
  Widget build(BuildContext context) {
    final phone = hsIsPhone(context);
    final full = _full || phone;
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: full ? EdgeInsets.zero : const EdgeInsets.all(18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(full ? 0 : 18),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: full
            ? BoxConstraints.tight(size)
            : BoxConstraints(
                maxWidth: (size.width * .94).clamp(320.0, 1500.0),
                maxHeight: (size.height * .90).clamp(320.0, 980.0),
              ),
        child: Column(
          children: [
            SafeArea(bottom: false, child: _bar(full)),
            Expanded(
              child: GestureDetector(
                onDoubleTapDown: _toggleZoom,
                onDoubleTap: () {},
                child: InteractiveViewer(
                  transformationController: _zoom,
                  minScale: 1,
                  maxScale: 6,
                  panEnabled: true,
                  scaleEnabled: true,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DriveThumb(
                        key: const ValueKey('drive-photo-preview-image'),
                        source: widget.src,
                        isRemote: widget.isRemote,
                        size: double.infinity,
                        big: true,
                        contain: true,
                        rounded: false,
                        // La miniatura ya se ve: ahora sí se pide la original.
                        onReady: () {
                          if (!mounted || _showOriginal) return;
                          if (widget.originalSrc.trim().isEmpty) return;
                          setState(() => _showOriginal = true);
                        },
                      ),
                      if (_showOriginal && widget.originalSrc.trim().isNotEmpty)
                        Image.network(
                          widget.originalSrc,
                          fit: BoxFit.contain,
                          frameBuilder: (context, child, frame, sync) {
                            if (sync) return child;
                            return AnimatedOpacity(
                              opacity: frame == null ? 0 : 1,
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              child: child,
                            );
                          },
                          // Si la original falla, se queda la miniatura: nunca
                          // se tapa con un recuadro de error.
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: Row(
                  children: [
                    const Icon(Icons.pinch_rounded,
                        size: 15, color: Colors.white38),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Pellizca o usa la rueda para acercar · doble toque para '
                        'volver a encajar',
                        maxLines: 2,
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _reset,
                      style:
                          TextButton.styleFrom(foregroundColor: Colors.white70),
                      icon: const Icon(Icons.fit_screen_rounded, size: 17),
                      label: const Text('Encajar'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(bool full) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (widget.meta.isNotEmpty)
                  Text(
                    widget.meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 11.5),
                  ),
              ],
            ),
          ),
          if (widget.onToggle != null)
            TextButton.icon(
              key: const ValueKey('drive-photo-preview-toggle'),
              onPressed: () => setState(() {
                _picked = !_picked;
                widget.onToggle!();
              }),
              icon: Icon(
                _picked
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
              ),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              label: Text(_picked ? 'Quitar' : widget.toggleLabel),
            ),
          if (!full)
            IconButton(
              tooltip: 'Pantalla completa',
              onPressed: () => setState(() => _full = true),
              icon: const Icon(Icons.fullscreen_rounded, color: Colors.white70),
            ),
          if (_full && !full)
            IconButton(
              tooltip: 'Salir de pantalla completa',
              onPressed: () => setState(() => _full = false),
              icon: const Icon(Icons.fullscreen_exit_rounded,
                  color: Colors.white70),
            ),
          IconButton(
            key: const ValueKey('drive-photo-preview-close'),
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

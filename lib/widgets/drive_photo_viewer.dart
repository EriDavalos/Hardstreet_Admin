import 'dart:io';

import 'package:flutter/material.dart';

import '../app_platform.dart';
import '../drive_api_service.dart';
import '../image_memory.dart';
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
//   * Siempre a PANTALLA COMPLETA, con los controles ENCIMA de la foto en
//     paneles translúcidos (se leen sin tapar la imagen).
//   * Primero la miniatura rápida; cuando ya se ve, se pide la ORIGINAL.
//
// La original se baja por chunks a un archivo local (el mismo camino que usa
// el visor del Drive), así no se queda «cargando» un archivo enorme por red
// sin avisar: hay progreso y, al terminar, entra nítida sobre la miniatura.
// ==================================================================

/// Abre [src] en el visor. [onToggle] (opcional) marca/desmarca la foto sin
/// cerrar; [toggleLabel] es el texto del botón.
///
/// [drive] + [item] + [rel] (opcionales) permiten bajar la ORIGINAL por chunks
/// desde el servidor del Drive; sin ellos se usa [originalSrc] por red.
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
  DriveBase? drive,
  DriveItem? item,
  List<String> rel = const <String>[],
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
      drive: drive,
      item: item,
      rel: rel,
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
    this.drive,
    this.item,
    this.rel = const <String>[],
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

  /// Camino por chunks (opcional): drive + archivo + su carpeta.
  final DriveBase? drive;
  final DriveItem? item;
  final List<String> rel;

  @override
  State<DrivePhotoViewer> createState() => _DrivePhotoViewerState();
}

class _DrivePhotoViewerState extends State<DrivePhotoViewer> {
  final TransformationController _zoom = TransformationController();
  late bool _picked = widget.picked;

  bool _showOriginal = false;

  // ---- Original por chunks (detrás de la miniatura rápida) ----
  File? _fullFile;
  double _fullProgress = 0;
  bool _fullLoading = false;
  String _fullKey = '';

  @override
  void dispose() {
    _zoom.dispose();
    // Fuera de RAM; el archivo queda en caché de disco.
    if (widget.originalSrc.trim().isNotEmpty) {
      ImageMemory.evict(widget.originalSrc);
    }
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

  /// La miniatura rápida ya se ve: desde aquí se pide la original.
  void _onPreviewReady() {
    if (!mounted || _showOriginal || _fullFile != null) return;
    _loadFull();
  }

  /// Baja la ORIGINAL por chunks (nativo) o, si no se puede, la deja por red.
  Future<void> _loadFull() async {
    final drive = widget.drive;
    final item = widget.item;
    final canChunks = !kWeb && drive is DriveApiService && item != null;
    if (!canChunks) {
      if (widget.originalSrc.trim().isNotEmpty) {
        setState(() => _showOriginal = true);
      }
      return;
    }
    final api = drive;
    final key = '${widget.rel.join('/')}/${item.name}';
    if (_fullKey == key && _fullFile != null) return;
    _fullKey = key;
    setState(() {
      _fullLoading = true;
      _fullProgress = 0;
      _fullFile = null;
    });
    try {
      final f = await api.fetchOriginalChunked(
        item,
        rel: widget.rel,
        onProgress: (p) {
          if (!mounted || key != _fullKey) return;
          setState(() => _fullProgress = p);
        },
      );
      if (!mounted || key != _fullKey) return;
      setState(() {
        _fullFile = f;
        _fullLoading = false;
        _showOriginal = false;
      });
    } catch (_) {
      // El original es opcional: si falla, se intenta por red y, si tampoco,
      // la miniatura rápida se queda. Nunca se tapa con un recuadro de error.
      if (!mounted || key != _fullKey) return;
      setState(() {
        _fullLoading = false;
        _showOriginal = widget.originalSrc.trim().isNotEmpty;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints.tight(size),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ---- La foto, a pantalla completa ----
            GestureDetector(
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
                      onReady: _onPreviewReady,
                    ),
                    // Original por chunks: entra nítida sobre la miniatura.
                    if (_fullFile != null)
                      Image.file(
                        _fullFile!,
                        fit: BoxFit.contain,
                        frameBuilder: (context, child, frame, sync) {
                          if (sync) return child;
                          return AnimatedOpacity(
                            opacity: frame == null ? 0 : 1,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            child: child,
                          );
                        },
                      ),
                    // Original por red (sin chunks): respaldo con fundido.
                    if (_fullFile == null &&
                        _showOriginal &&
                        widget.originalSrc.trim().isNotEmpty)
                      Image.network(
                        widget.originalSrc,
                        fit: BoxFit.contain,
                        frameBuilder: (context, child, frame, sync) {
                          if (sync) return child;
                          return AnimatedOpacity(
                            opacity: frame == null ? 0 : 1,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            child: child,
                          );
                        },
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
            ),
            // ---- Barra superior translúcida ENCIMA de la foto ----
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: _glass(
                  margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                  child: _bar(),
                ),
              ),
            ),
            // ---- Controles de abajo, también translúcidos ----
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_fullLoading)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: _fullProgress > 0 ? _fullProgress : null,
                            minHeight: 3,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation(
                              Colors.white70,
                            ),
                          ),
                        ),
                      ),
                    _glass(
                      margin: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                      child: _bottomBar(),
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

  /// Panel translúcido: se leen las letras sin tapar la foto de debajo.
  Widget _glass({required Widget child, EdgeInsets margin = EdgeInsets.zero}) =>
      Container(
        margin: margin,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .42),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .10)),
        ),
        child: child,
      );

  Widget _bottomBar() {
    return Row(
      children: [
        const Icon(Icons.pinch_rounded, size: 15, color: Colors.white54),
        const SizedBox(width: 6),
        const Expanded(
          child: Text(
            'Pellizca o usa la rueda para acercar · doble toque para volver a '
            'encajar',
            maxLines: 2,
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ),
        TextButton.icon(
          onPressed: _reset,
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          icon: const Icon(Icons.fit_screen_rounded, size: 17),
          label: const Text('Encajar'),
        ),
      ],
    );
  }

  Widget _bar() {
    return Row(
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
        IconButton(
          key: const ValueKey('drive-photo-preview-close'),
          tooltip: 'Cerrar',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded, color: Colors.white70),
        ),
      ],
    );
  }
}

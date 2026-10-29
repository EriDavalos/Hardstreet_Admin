import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_platform.dart';
import '../drive_api_service.dart';
import '../image_memory.dart';
import 'drive_thumb.dart';
import 'hs_modal.dart';

// ==================================================================
// VISOR DE UNA FOTO DEL DRIVE (zoom + pantalla completa + GALERÍA)
// ==================================================================
// Lo usan el selector de fotos y el módulo «Mis fotos» del paquete. Es el
// mismo lenguaje en celular y escritorio:
//
//   * PELLIZCA / rueda del mouse para acercar (hasta 6x), arrastre para mover.
//   * DOBLE toque: acerca al centro y otro doble toque vuelve a encajar.
//   * MODO GALERÍA (opcional): se le pasa la LISTA de fotos y la inicial y el
//     visor deja cambiar de foto con un DESLIZAR (celular), las flechas ‹ ›
//     (click) y ← → (teclado) — el mismo lenguaje del visor del Drive. Solo
//     desliza con la foto a tamaño de pantalla: ampliada, el gesto es para
//     mover la imagen.
//   * Siempre a PANTALLA COMPLETA, con los controles ENCIMA de la foto en
//     paneles translúcidos (se leen sin tapar la imagen).
//   * Primero la miniatura rápida; cuando ya se ve, se pide la ORIGINAL.
//
// La original se baja por chunks a un archivo local (el mismo camino que usa
// el visor del Drive), así no se queda «cargando» un archivo enorme por red
// sin avisar: hay progreso y, al terminar, entra nítida sobre la miniatura.
// ==================================================================

/// Una foto del visor. El modo de UNA sola foto se mantiene con los campos
/// normales; en modo GALERÍA se pasa una lista de entradas más la inicial.
class DrivePhotoEntry {
  const DrivePhotoEntry({
    required this.name,
    this.meta = '',
    required this.src,
    this.originalSrc = '',
    this.isRemote = false,
    this.isPicked,
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

  /// ¿Está ELEGIDA ahora mismo? Se LEE en cada build (no se guarda una copia):
  /// el marcado vive en el selector y puede cambiar mientras el visor está
  /// abierto y navegando entre fotos.
  final bool Function()? isPicked;

  /// Marca/desmarca ESTA foto sin cerrar el visor (opcional).
  final VoidCallback? onToggle;

  /// Texto del botón de marcar.
  final String toggleLabel;

  /// Camino por chunks (opcional): drive + archivo + su carpeta.
  final DriveBase? drive;
  final DriveItem? item;
  final List<String> rel;
}

/// Abre [src] en el visor. [onToggle] (opcional) marca/desmarca la foto sin
/// cerrar; [toggleLabel] es el texto del botón.
///
/// [drive] + [item] + [rel] (opcionales) permiten bajar la ORIGINAL por chunks
/// desde el servidor del Drive; sin ellos se usa [originalSrc] por red.
///
/// Con [gallery] (y [initialIndex] opcional) el visor abre en MODO GALERÍA:
/// la lista da el orden en que se navega con deslizar/flechas.
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
  List<DrivePhotoEntry> gallery = const <DrivePhotoEntry>[],
  int initialIndex = 0,
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
      gallery: gallery,
      initialIndex: initialIndex,
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
    this.gallery = const <DrivePhotoEntry>[],
    this.initialIndex = 0,
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

  /// Modo GALERÍA: con 2 fotos o más se deja cambiar entre ellas (deslizar,
  /// flechas y teclado). Con una sola (o vacía) el visor de toda la vida.
  final List<DrivePhotoEntry> gallery;
  final int initialIndex;

  @override
  State<DrivePhotoViewer> createState() => _DrivePhotoViewerState();
}

class _DrivePhotoViewerState extends State<DrivePhotoViewer> {
  final TransformationController _zoom = TransformationController();

  /// Modo galería: índice de la foto visible (RECORRIENDO circularmente, como
  /// el visor del Drive: de la última se pasa a la primera y viceversa).
  late int _index = widget.initialIndex;

  /// MODO de una sola foto: lo marcado vive AQUÍ (el selector lo lee al
  /// cerrar). En galería se pregunta a la entrada de la foto visible.
  late bool _picked = widget.picked;

  bool _showOriginal = false;

  // ---- Original por chunks (detrás de la miniatura rápida) ----
  File? _fullFile;
  double _fullProgress = 0;
  bool _fullLoading = false;
  String _fullKey = '';

  /// Inicio del gesto horizontal (pointer DOWN): el visor desliza con un
  /// Listener a MouseButton abierto — así no le pelea el toque al
  /// InteractiveViewer, que se queda con el pan/zoom de siempre.
  double? _swipeStartX;

  /// ¿Hay galería (2 fotos o más) y por tanto navegación?
  bool get _hasGallery => widget.gallery.length > 1;

  /// La foto visible AHORA: en galería es una entrada de la lista; en modo de
  /// una sola foto se monta con los campos del widget.
  DrivePhotoEntry get _cur {
    if (!_hasGallery) {
      return DrivePhotoEntry(
        name: widget.name,
        meta: widget.meta,
        src: widget.src,
        originalSrc: widget.originalSrc,
        isRemote: widget.isRemote,
        drive: widget.drive,
        item: widget.item,
        rel: widget.rel,
      );
    }
    final i = _index.clamp(0, widget.gallery.length - 1);
    return widget.gallery[i];
  }

  /// ¿La foto visible está ELEGIDA? En galería se lee la entrada (fresco),
  /// en modo de una sola foto vive en [_picked].
  bool get _pickedNow =>
      _hasGallery ? (_cur.isPicked?.call() ?? false) : _picked;

  /// Marca/desmarca la foto visible.
  VoidCallback? get _toggleNow => _hasGallery ? _cur.onToggle : widget.onToggle;

  String get _toggleLabelNow =>
      _hasGallery ? _cur.toggleLabel : widget.toggleLabel;

  @override
  void initState() {
    super.initState();
    // El ORIGINAL solo se pide al ACERCAR: a tamaño de pantalla el preview ya
    // se ve nítido. Antes se bajaba el archivo entero en cuanto la miniatura
    // aparecía, así que la foto cambiaba de "baja" a "alta" calidad un rato
    // después de abrir.
    _zoom.addListener(_onZoomChanged);
    // Atajos SIN depender del foco (igual que el visor del Drive): Esc cierra
    // y ← → cambian de foto en galería.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _zoom.removeListener(_onZoomChanged);
    _zoom.dispose();
    // Fuera de RAM; el archivo queda en caché de disco.
    final original = _cur.originalSrc;
    if (original.trim().isNotEmpty) {
      ImageMemory.evict(original);
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

  /// Cambia de foto en el modo galería: el zoom y el ORIGINAL de la foto
  /// anterior NO pueden quedarse (se limpian y la nueva arranca del preview).
  void _move(int delta) {
    if (!_hasGallery || widget.gallery.isEmpty) return;
    final total = widget.gallery.length;
    var next = _index + delta;
    while (next < 0) {
      next += total;
    }
    setState(() {
      _index = next % total;
      _showOriginal = false;
      _fullFile = null;
      _fullProgress = 0;
      _fullLoading = false;
      _fullKey = '';
    });
    _zoom.value = Matrix4.identity();
  }

  /// Al ACERCAR se pide la original (detalle real al 100%).
  void _onZoomChanged() {
    if (!mounted) return;
    if (_zoom.value.getMaxScaleOnAxis() <= 1.05) return;
    if (_showOriginal || _fullFile != null || _fullLoading) return;
    _loadFull();
  }

  /// Deslizar entre fotos: solo si el gesto fue horizontal y largo (≥ 60 px)
  /// y la foto NO está ampliada. Ampliada, el dedo mueve la imagen y no
  /// cambia de foto — igual que el visor del Drive.
  void _onPointerUp(PointerEvent event) {
    final start = _swipeStartX;
    _swipeStartX = null;
    if (start == null || !_hasGallery) return;
    if (_zoom.value.getMaxScaleOnAxis() > 1.05) return;
    final dx = event.position.dx - start;
    if (dx <= -60) {
      _move(1);
    } else if (dx >= 60) {
      _move(-1);
    }
  }

  /// Atajos del visor: ← → cambian de foto (solo con galería) y Esc cierra.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return true;
    }
    if (!_hasGallery) return false;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _move(1);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _move(-1);
      return true;
    }
    return false;
  }

  /// Baja la ORIGINAL por chunks (nativo) o, si no se puede, la deja por red.
  /// En modo galería la foto que se baja es `_cur` (no la del widget): el key
  /// con carpeta+nombre deja INVALIDA la descarga si el usuario cambia de
  /// foto a mitad y el resultado de la descarga vieja se descarta.
  Future<void> _loadFull() async {
    final entry = _cur;
    final item = entry.item;
    final drive = entry.drive;
    final canChunks = !kWeb && drive is DriveApiService && item != null;
    if (!canChunks) {
      if (entry.originalSrc.trim().isNotEmpty) {
        setState(() => _showOriginal = true);
      }
      return;
    }
    final key = '${entry.rel.join('/')}/${item.name}';
    if (_fullKey == key && _fullFile != null) return;
    final api = drive;
    _fullKey = key;
    setState(() {
      _fullLoading = true;
      _fullProgress = 0;
      _fullFile = null;
    });
    try {
      final f = await api.fetchOriginalChunked(
        item,
        rel: entry.rel,
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
        _showOriginal = entry.originalSrc.trim().isNotEmpty;
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
            // ---- La foto, a pantalla completa (con deslizar en galería) ----
            Listener(
              behavior: HitTestBehavior.deferToChild,
              onPointerDown: (e) => _swipeStartX = e.position.dx,
              onPointerUp: _onPointerUp,
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
                        source: _cur.src,
                        isRemote: _cur.isRemote,
                        size: double.infinity,
                        big: true,
                        contain: true,
                        rounded: false,
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
                          _cur.originalSrc.trim().isNotEmpty)
                        Image.network(
                          _cur.originalSrc,
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
            ),
            // ---- Flechas ‹ › de la galería (visible en TODO plataforma:
            //      en laptop se dan CLICK y en celular el deslizar manda) ----
            if (_hasGallery) ...[
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _navArrow(
                    Icons.chevron_left_rounded,
                    tooltip: 'Anterior',
                    onPressed: () => _move(-1),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _navArrow(
                    Icons.chevron_right_rounded,
                    tooltip: 'Siguiente',
                    onPressed: () => _move(1),
                  ),
                ),
              ),
            ],
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

  /// Botón de flecha del borde (galería): rueda translúcida, como los
  /// controles de la pantalla.
  Widget _navArrow(
    IconData icon, {
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      key: ValueKey(tooltip),
      onPressed: onPressed,
      color: Colors.white70,
      iconSize: 38,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: .38),
        shape: const CircleBorder(),
      ),
      icon: Icon(icon),
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
        Expanded(
          child: Text(
            _hasGallery
                ? 'Desliza o usa las flechas para cambiar de foto · pellizca '
                    'para acercar'
                : 'Pellizca o usa la rueda para acercar · doble toque para '
                    'volver a encajar',
            maxLines: 2,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
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
    final entry = _cur;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (entry.meta.isNotEmpty)
                Text(
                  entry.meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 11.5),
                ),
            ],
          ),
        ),
        // Contador «3 / 12» de la galería: dónde está el usuario sin pillar
        // espacio a la foto.
        if (_hasGallery)
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8),
            child: Text(
              '${_index + 1} / ${widget.gallery.length}',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        if (_toggleNow != null)
          TextButton.icon(
            key: const ValueKey('drive-photo-preview-toggle'),
            onPressed: () => setState(() {
              // En modo de una sola foto el marcado vive aquí; en galería lo
              // dice la entrada (el lector `_pickedNow` relee en cada build).
              if (!_hasGallery) _picked = !_picked;
              _toggleNow!();
            }),
            icon: Icon(
              _pickedNow
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 18,
            ),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            label: Text(_pickedNow ? 'Quitar' : _toggleLabelNow),
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

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../print_models.dart';
import '../theme.dart';

// ==================================================================
// VISTA PREVIA DEL RECORTE (estilo Lightroom)
// ==================================================================
// * `PrintFrame` pinta UNA foto ya recortada al formato con su borde.
// * `PrintCropDialog` deja mover el encuadre, ESTIRARLO desde los bordes o
//   las esquinas, acercar con la rueda y girar entre horizontal y vertical.
//   Aquí NO se pinta el borde blanco de impresión: se ve solo la foto y el
//   marco de selección, para que no se confundan.
// ==================================================================

/// Rectángulo de destino (con la proporción del formato) dentro del widget.
Rect printFrameRect(Size size, double ratio) {
  if (size.width <= 0 || size.height <= 0 || ratio <= 0) return Rect.zero;
  var w = size.width;
  var h = w / ratio;
  if (h > size.height) {
    h = size.height;
    w = h * ratio;
  }
  return Rect.fromCenter(center: size.center(Offset.zero), width: w, height: h);
}

/// Recorta [src] a la proporción [ratio] manteniendo el centro.
Rect fitPrintRect(Rect src, double ratio) {
  if (ratio <= 0 || src.width <= 0 || src.height <= 0) return src;
  var w = src.width;
  var h = src.height;
  if (w / h > ratio) {
    w = h * ratio;
  } else {
    h = w / ratio;
  }
  return Rect.fromCenter(center: src.center, width: w, height: h);
}

/// Pinta la foto recortada + borde dentro de [dst].
void paintPrintFrame(
  Canvas canvas,
  ui.Image image,
  Rect dst, {
  required PrintFormat format,
  required PrintCrop crop,
  required double borderPercent,
  bool grid = false,
  Color gridColor = Colors.white54,
}) {
  final imageSize = Size(image.width.toDouble(), image.height.toDouble());
  final src = crop.sourceRect(imageSize, crop.ratioFor(format, imageSize));
  if (src.width < 1 || src.height < 1) return;
  canvas.drawRect(dst, Paint()..color = Colors.white);
  final px = borderGeometry(src, borderPercent).pixels;
  final scale = dst.width / src.width;
  final inner = dst.deflate(px * scale);
  if (inner.width <= 0 || inner.height <= 0) return;
  final sub = fitPrintRect(src, inner.width / inner.height);
  canvas.drawImageRect(
    image,
    sub,
    inner,
    Paint()..filterQuality = FilterQuality.medium,
  );
  if (grid) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = inner.left + inner.width * i / 3;
      final y = inner.top + inner.height * i / 3;
      canvas.drawLine(Offset(x, inner.top), Offset(x, inner.bottom), paint);
      canvas.drawLine(Offset(inner.left, y), Offset(inner.right, y), paint);
    }
  }
}

/// Cuadro de la foto ya recortada (con borde), con la imagen precargada.
class PrintFrame extends StatelessWidget {
  const PrintFrame({
    super.key,
    required this.image,
    required this.format,
    required this.crop,
    this.borderPercent = 0,
    this.grid = false,
  });

  final ui.Image image;
  final PrintFormat format;
  final PrintCrop crop;
  final double borderPercent;
  final bool grid;

  @override
  Widget build(BuildContext context) {
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    return AspectRatio(
      // La proporción depende de la ORIENTACIÓN de la foto (horizontal por
      // defecto si la foto es apaisada), no solo del formato.
      aspectRatio: crop.ratioFor(format, imageSize),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CustomPaint(
          painter: _FramePainter(
            image: image,
            format: format,
            crop: crop,
            borderPercent: borderPercent,
            grid: grid,
          ),
        ),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter({
    required this.image,
    required this.format,
    required this.crop,
    required this.borderPercent,
    required this.grid,
  });

  final ui.Image image;
  final PrintFormat format;
  final PrintCrop crop;
  final double borderPercent;
  final bool grid;

  @override
  void paint(Canvas canvas, Size size) {
    paintPrintFrame(
      canvas,
      image,
      Offset.zero & size,
      format: format,
      crop: crop,
      borderPercent: borderPercent,
      grid: grid,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.image != image ||
      old.format.id != format.id ||
      old.crop != crop ||
      old.borderPercent != borderPercent ||
      old.grid != grid;
}

/// Diálogo para AJUSTAR el recorte de una foto.
///
/// Arrastra para mover, estira desde los bordes/esquinas con cualquier botón
/// del mouse y usa la rueda para acercar. El botón de orientación cambia el
/// recorte entre horizontal y vertical (por defecto sigue a la foto).
Future<PrintCrop?> showPrintCropDialog(
  BuildContext context, {
  required ui.Image image,
  required PrintFormat format,
  required PrintCrop initial,
}) {
  return showDialog<PrintCrop>(
    context: context,
    // Clic fuera = cerrar sin cambiar el encuadre (regla de los modales).
    barrierDismissible: true,
    builder: (_) =>
        _PrintCropDialog(image: image, format: format, initial: initial),
  );
}

enum _CropHandle {
  move,
  left,
  right,
  top,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

class _PrintCropDialog extends StatefulWidget {
  const _PrintCropDialog({
    required this.image,
    required this.format,
    required this.initial,
  });

  final ui.Image image;
  final PrintFormat format;
  final PrintCrop initial;

  @override
  State<_PrintCropDialog> createState() => _PrintCropDialogState();
}

class _PrintCropDialogState extends State<_PrintCropDialog> {
  late PrintCrop _crop = widget.initial;
  late bool _landscape =
      widget.initial.landscape ??
      (widget.image.width >= widget.image.height);

  /// Imagen "contain" dentro del lienzo: se calcula al pintar y se guarda para
  /// convertir el arrastre en coordenadas de la foto.
  Rect _imageRect = Rect.zero;

  _CropHandle? _drag;
  int? _dragPointer;
  Offset _lastPoint = Offset.zero;
  MouseCursor _cursor = SystemMouseCursors.grab;

  Size get _imageSize =>
      Size(widget.image.width.toDouble(), widget.image.height.toDouble());

  double get _ratio => _crop.ratioFor(widget.format, _imageSize);

  Rect? _cropRectInWidget() {
    if (_imageRect.width <= 0 || _imageRect.height <= 0) return null;
    final src = _crop.sourceRect(_imageSize, _ratio);
    final scale = _imageRect.width / _imageSize.width;
    return Rect.fromLTWH(
      _imageRect.left + src.left * scale,
      _imageRect.top + src.top * scale,
      src.width * scale,
      src.height * scale,
    );
  }

  _CropHandle? _handleAt(Offset p) {
    if (!_imageRect.contains(p)) return null;
    final rect = _cropRectInWidget();
    if (rect == null || rect.isEmpty) return _CropHandle.move;
    const edge = 24.0;
    final near = rect.inflate(edge);
    if (!near.contains(p)) return _CropHandle.move;

    final left = (p.dx - rect.left).abs() <= edge;
    final right = (p.dx - rect.right).abs() <= edge;
    final top = (p.dy - rect.top).abs() <= edge;
    final bottom = (p.dy - rect.bottom).abs() <= edge;

    if (left && top) return _CropHandle.topLeft;
    if (right && top) return _CropHandle.topRight;
    if (left && bottom) return _CropHandle.bottomLeft;
    if (right && bottom) return _CropHandle.bottomRight;
    if (left) return _CropHandle.left;
    if (right) return _CropHandle.right;
    if (top) return _CropHandle.top;
    if (bottom) return _CropHandle.bottom;
    return _CropHandle.move;
  }

  MouseCursor _cursorFor(_CropHandle? handle) {
    if (handle == null) return SystemMouseCursors.basic;
    if (_drag != null && handle == _CropHandle.move) {
      return SystemMouseCursors.grabbing;
    }
    return switch (handle) {
      _CropHandle.move => SystemMouseCursors.grab,
      _CropHandle.left ||
      _CropHandle.right => SystemMouseCursors.resizeLeftRight,
      _CropHandle.top ||
      _CropHandle.bottom => SystemMouseCursors.resizeUpDown,
      _CropHandle.topLeft ||
      _CropHandle.bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
      _CropHandle.topRight ||
      _CropHandle.bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
    };
  }

  void _onHover(PointerHoverEvent e) {
    final cursor = _cursorFor(_handleAt(e.localPosition));
    if (cursor != _cursor) setState(() => _cursor = cursor);
  }

  void _onDown(PointerDownEvent e) {
    final handle = _handleAt(e.localPosition);
    if (handle == null) return;
    // Cualquier botón del mouse sirve para arrastrar/estirar.
    setState(() {
      _drag = handle;
      _dragPointer = e.pointer;
      _lastPoint = e.localPosition;
      _cursor = _cursorFor(handle);
    });
  }

  void _onMove(PointerMoveEvent e) {
    if (_dragPointer != e.pointer || _drag == null) return;
    final delta = e.localPosition - _lastPoint;
    _lastPoint = e.localPosition;
    if (delta == Offset.zero) return;
    if (_drag == _CropHandle.move) {
      _move(delta);
    } else {
      _resize(_drag!, delta);
    }
  }

  void _endDrag(PointerEvent e) {
    if (_dragPointer != e.pointer) return;
    setState(() {
      _drag = null;
      _dragPointer = null;
      _cursor = _cursorFor(_handleAt(e.localPosition));
    });
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || _imageRect.isEmpty) return;
    // Rueda del mouse: acerca/aleja el recorte.
    final factor = math.exp(-e.scrollDelta.dy * 0.0015);
    _setZoom(_crop.zoom * factor);
  }

  void _setZoom(double value) {
    setState(
      () => _crop = _crop.copyWith(
        zoom: value.clamp(1.0, 4.0),
        landscape: _landscape,
      ),
    );
  }

  void _move(Offset delta) {
    if (_imageRect.width <= 0) return;
    final image = _imageSize;
    final dx = delta.dx / _imageRect.width * image.width;
    final dy = delta.dy / _imageRect.height * image.height;
    setState(() {
      _crop = _crop.copyWith(
        focusX: _crop.focusX + dx / image.width,
        focusY: _crop.focusY + dy / image.height,
        landscape: _landscape,
      );
    });
  }

  /// Estira el recorte desde el borde/esquina agarrado.
  ///
  /// El recorte mantiene SIEMPRE la proporción elegida: al arrastrar una
  /// esquina crecen (o se encogen) los dos lados a la vez. El lado opuesto
  /// queda fijo, como en Lightroom.
  void _resize(_CropHandle handle, Offset delta) {
    if (_imageRect.width <= 0) return;
    final image = _imageSize;
    final ratio = _ratio;
    if (ratio <= 0) return;

    final src = _crop.sourceRect(image, ratio);
    final maxSrc = const PrintCrop(zoom: 1).sourceRect(image, ratio);
    final scale = _imageRect.width / image.width;
    final dx = delta.dx / scale;
    final dy = delta.dy / scale;

    final movesLeft =
        handle == _CropHandle.left ||
        handle == _CropHandle.topLeft ||
        handle == _CropHandle.bottomLeft;
    final movesRight =
        handle == _CropHandle.right ||
        handle == _CropHandle.topRight ||
        handle == _CropHandle.bottomRight;
    final movesTop =
        handle == _CropHandle.top ||
        handle == _CropHandle.topLeft ||
        handle == _CropHandle.topRight;
    final movesBottom =
        handle == _CropHandle.bottom ||
        handle == _CropHandle.bottomLeft ||
        handle == _CropHandle.bottomRight;

    double? fromX;
    if (movesLeft) fromX = src.right - (src.left + dx);
    if (movesRight) fromX = (src.right + dx) - src.left;

    double? fromY;
    if (movesTop) fromY = (src.bottom - (src.top + dy)) * ratio;
    if (movesBottom) fromY = ((src.bottom + dy) - src.top) * ratio;

    double width;
    if (fromX == null) {
      width = fromY!;
    } else if (fromY == null) {
      width = fromX;
    } else {
      // Esquina: manda el movimiento más grande, así se puede estirar tanto
      // en horizontal como en vertical.
      width = dx.abs() >= dy.abs() ? fromX : fromY;
    }
    width = width.clamp(maxSrc.width / 4, maxSrc.width);
    final height = width / ratio;

    double left;
    if (movesLeft) {
      left = src.right - width;
    } else if (movesRight) {
      left = src.left;
    } else {
      left = src.center.dx - width / 2;
    }
    double top;
    if (movesTop) {
      top = src.bottom - height;
    } else if (movesBottom) {
      top = src.top;
    } else {
      top = src.center.dy - height / 2;
    }

    left = left.clamp(0.0, math.max(0.0, image.width - width));
    top = top.clamp(0.0, math.max(0.0, image.height - height));

    final zoom = (maxSrc.width / width).clamp(1.0, 4.0);
    setState(() {
      _crop = _crop.copyWith(
        zoom: zoom,
        focusX: (left + width / 2) / image.width,
        focusY: (top + height / 2) / image.height,
        landscape: _landscape,
      );
    });
  }

  /// Cambia el recorte entre horizontal y vertical conservando el encuadre.
  void _toggleOrientation() {
    setState(() {
      _landscape = !_landscape;
      _crop = _crop.copyWith(landscape: _landscape);
    });
  }

  void _center() {
    setState(() {
      _crop = PrintCrop(landscape: _landscape);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 560;

    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1000,
          maxHeight: size.height - 40,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
              child: Row(
                children: [
                  Icon(Icons.crop_rotate_rounded, color: AppColors.brand),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ajustar recorte',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Arrastra para mover · estira desde los bordes o '
                          'esquinas · rueda para acercar · formato '
                          '${widget.format.name}',
                          maxLines: 2,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.3,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (compact)
                    IconButton(
                      tooltip: _landscape
                          ? 'Recorte vertical'
                          : 'Recorte horizontal',
                      onPressed: _toggleOrientation,
                      icon: const Icon(
                        Icons.rotate_90_degrees_ccw_rounded,
                        size: 20,
                      ),
                    )
                  else
                    TextButton.icon(
                      onPressed: _toggleOrientation,
                      icon: const Icon(
                        Icons.rotate_90_degrees_ccw_rounded,
                        size: 17,
                      ),
                      label: Text(_landscape ? 'Horizontal' : 'Vertical'),
                    ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: const Color(0xFF0C0C12),
                child: LayoutBuilder(
                  builder: (context, box) {
                    return MouseRegion(
                      cursor: _cursor,
                      onHover: _onHover,
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: _onDown,
                        onPointerMove: _onMove,
                        onPointerUp: _endDrag,
                        onPointerCancel: _endDrag,
                        onPointerSignal: _onSignal,
                        child: CustomPaint(
                          key: const ValueKey('print-crop-canvas'),
                          size: Size(box.maxWidth, box.maxHeight),
                          painter: _CropEditorPainter(
                            image: widget.image,
                            ratio: _ratio,
                            crop: _crop,
                            onImageRect: (r) => _imageRect = r,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 2),
              child: Row(
                children: [
                  Icon(
                    Icons.zoom_out_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  Expanded(
                    child: Slider(
                      value: _crop.zoom.clamp(1.0, 4.0),
                      min: 1,
                      max: 4,
                      divisions: 30,
                      label: '${_crop.zoom.toStringAsFixed(1)}×',
                      onChanged: _setZoom,
                    ),
                  ),
                  Icon(
                    Icons.zoom_in_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _center,
                    child: const Text('Centrar'),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(
                      _crop.copyWith(landscape: _landscape),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Listo'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropEditorPainter extends CustomPainter {
  _CropEditorPainter({
    required this.image,
    required this.ratio,
    required this.crop,
    required this.onImageRect,
  });

  final ui.Image image;
  final double ratio;
  final PrintCrop crop;
  final ValueChanged<Rect> onImageRect;

  @override
  void paint(Canvas canvas, Size size) {
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final fit = applyBoxFit(BoxFit.contain, imageSize, size);
    final dstSize = fit.destination;
    final imgRect = Alignment.center.inscribe(dstSize, Offset.zero & size);
    onImageRect(imgRect);

    // Foto completa.
    canvas.drawImageRect(
      image,
      Offset.zero & imageSize,
      imgRect,
      Paint()..filterQuality = FilterQuality.medium,
    );

    final scale = imgRect.width / imageSize.width;
    final src = crop.sourceRect(imageSize, ratio);
    final cropRect = Rect.fromLTWH(
      imgRect.left + src.left * scale,
      imgRect.top + src.top * scale,
      src.width * scale,
      src.height * scale,
    );

    // Oscurece lo que NO se imprime.
    final shade = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRect(cropRect),
    );
    canvas.drawPath(
      shade,
      Paint()..color = Colors.black.withValues(alpha: .62),
    );

    // Rejilla de tercios y marco del recorte. El borde BLANCO de impresión no
    // se pinta aquí a propósito: en este paso solo se ve la foto.
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .38)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = cropRect.left + cropRect.width * i / 3;
      final y = cropRect.top + cropRect.height * i / 3;
      canvas.drawLine(
        Offset(x, cropRect.top),
        Offset(x, cropRect.bottom),
        grid,
      );
      canvas.drawLine(
        Offset(cropRect.left, y),
        Offset(cropRect.right, y),
        grid,
      );
    }
    canvas.drawRect(
      cropRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.brand,
    );
    // Asas: esquinas y puntos medios de los lados.
    _corner(canvas, cropRect.topLeft, const Offset(1, 1));
    _corner(canvas, cropRect.topRight, const Offset(-1, 1));
    _corner(canvas, cropRect.bottomLeft, const Offset(1, -1));
    _corner(canvas, cropRect.bottomRight, const Offset(-1, -1));
    _side(canvas, Offset(cropRect.center.dx, cropRect.top));
    _side(canvas, Offset(cropRect.center.dx, cropRect.bottom));
    _side(canvas, Offset(cropRect.left, cropRect.center.dy));
    _side(canvas, Offset(cropRect.right, cropRect.center.dy));
  }

  void _corner(Canvas canvas, Offset at, Offset dir) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(at, at + Offset(14 * dir.dx, 0), paint);
    canvas.drawLine(at, at + Offset(0, 14 * dir.dy), paint);
  }

  void _side(Canvas canvas, Offset at) {
    canvas.drawCircle(
      at,
      3.5,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_CropEditorPainter old) =>
      old.image != image ||
      old.crop != crop ||
      old.ratio != ratio;
}

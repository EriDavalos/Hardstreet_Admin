import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../image_memory.dart';

/// Miniatura del Drive. Resuelve local (File) o remota (Image.network) y está
/// pensada para que la cuadrícula NUNCA muestre un recuadro vacío:
///
/// * Mientras el servidor prepara/entrega la imagen se ve un marcador
///   (esqueleto + spinner), no un hueco en blanco.
/// * La foto entra con un fundido SOLO cuando llega el frame descargado (esa
///   es la \"animación de bajada\"). Si ya estaba en la caché de RAM, aparece
///   al instante, sin animación.
/// * Si la descarga falla, reintenta sola un par de veces (sacando de la
///   caché la entrada fallida) y, como último recurso, muestra la copia
///   LOCAL del archivo recién subido ([localPreview]) en vez de un hueco.
/// * Si aun así no hay imagen, deja un icono tocable para reintentar a mano.
class DriveThumb extends StatefulWidget {
  const DriveThumb({
    super.key,
    required this.source,
    required this.isRemote,
    this.localPreview,
    this.size = 40,
    this.big = false,
    this.contain = false,
    this.rounded = true,
  });

  /// URL (drive remoto) o ruta absoluta (drive local) de la miniatura.
  final String source;
  final bool isRemote;

  /// Ruta local del archivo recién subido (job.thumb): se muestra al
  /// instante mientras el servidor genera su miniatura.
  final String? localPreview;

  final double size;

  /// Tarjeta grande (cuadrícula/visor): usa el ancho completo y un marcador
  /// más visible. En miniaturas pequeñas el marcador es un icono discreto.
  final bool big;

  /// true = la imagen se ajusta sin recortar (visor).
  final bool contain;

  /// true = esquinas redondeadas (tarjetas). El VISOR la pone en false: la
  /// foto se ve a pantalla completa, sin bordes curvos.
  final bool rounded;

  /// Reintentos automáticos de descarga antes de darla por fallida.
  static const int maxRetries = 3;

  /// Espera entre reintentos (creciente). El último valor se repite.
  static const List<Duration> retryDelays = [
    Duration(milliseconds: 600),
    Duration(milliseconds: 1500),
    Duration(milliseconds: 3000),
  ];

  @override
  State<DriveThumb> createState() => _DriveThumbState();
}

class _DriveThumbState extends State<DriveThumb> {
  /// Aumenta en cada reintento: fuerza una nueva resolución de la imagen.
  int _attempt = 0;
  int _retries = 0;
  bool _failed = false; // agotó reintentos (o el visor pidió parar)
  bool _errorScheduled = false; // evita programar el reintento dos veces
  bool _ready = false; // hay imagen visible: se oculta el marcador
  Timer? _timer;

  @override
  void didUpdateWidget(covariant DriveThumb old) {
    super.didUpdateWidget(old);
    // Otro archivo en la misma celda: reinicia todo el estado de carga.
    if (old.source != widget.source || old.localPreview != widget.localPreview) {
      _timer?.cancel();
      _timer = null;
      _attempt = 0;
      _retries = 0;
      _failed = false;
      _errorScheduled = false;
      _ready = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _hasLocal {
    final p = widget.localPreview;
    if (p == null || p.isEmpty) return false;
    try {
      return File(p).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// La descarga falló: reintenta con espera creciente; si se agotan los
  /// intentos deja el estado \"toca para reintentar\".
  void _onRemoteError() {
    if (!mounted || _errorScheduled) return;
    _errorScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _errorScheduled = false;
      if (_retries >= DriveThumb.maxRetries) {
        setState(() => _failed = true);
        return;
      }
      final delay = DriveThumb.retryDelays[
          _retries.clamp(0, DriveThumb.retryDelays.length - 1)];
      _retries++;
      _timer?.cancel();
      _timer = Timer(delay, () {
        if (!mounted) return;
        // Una carga fallida queda cacheada: hay que sacarla antes de reintentar.
        ImageMemory.evict(widget.source);
        setState(() {
          _attempt++;
          _failed = false;
        });
      });
    });
  }

  /// Reintento manual (toque sobre el icono de error).
  void _retryManually() {
    _timer?.cancel();
    _timer = null;
    ImageMemory.evict(widget.source);
    setState(() {
      _retries = 0;
      _failed = false;
      _attempt++;
    });
  }

  /// Marca que ya hay imagen en pantalla (tras el primer frame) para quitar
  /// el marcador. Se hace fuera del build (post-frame) por seguridad.
  void _markReady() {
    if (_ready) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_ready) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fit = widget.contain ? BoxFit.contain : BoxFit.cover;
    // Resolución de decodificación: las miniaturas pequeñas no necesitan más.
    final px = widget.big ? null : (widget.size * MediaQuery.devicePixelRatioOf(context)).round().clamp(32, 1024);
    final hasLocal = _hasLocal;

    final layers = <Widget>[
      if (hasLocal)
        Image.file(
          File(widget.localPreview!),
          fit: fit,
          cacheWidth: px,
          // La copia local aparece de inmediato (sin fundido): es la foto que
          // el usuario acaba de subir y debe verse \"ahí mismo\".
          frameBuilder: (c, child, frame, sync) {
            if (sync || frame != null) {
              _markReady();
              return child;
            }
            return const SizedBox.shrink();
          },
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      if (widget.isRemote && !_failed)
        Image.network(
          widget.source,
          key: ValueKey('thumb-${widget.source}#$_attempt'),
          fit: fit,
          cacheWidth: px,
          frameBuilder: (c, child, frame, sync) {
            // Ya venía de la caché (sincrónico): mostrar directo, sin animar.
            if (sync) {
              _markReady();
              return child;
            }
            if (frame != null) _markReady();
            // Aparición suave: el fundido ES la animación de \"bajar\" la
            // imagen del servidor. Mientras no hay frame queda invisible y se
            // ve el marcador de abajo.
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOut,
              child: child,
            );
          },
          errorBuilder: (_, _, _) {
            _onRemoteError();
            // Sin imagen: se ve el marcador (o el icono de reintentar).
            return const SizedBox.shrink();
          },
        ),
    ];

    // Marcador: solo por debajo de la imagen y solo hasta que hay imagen.
    final Widget content = Stack(
      fit: StackFit.expand,
      children: [
        if (!_ready && !hasLocal) _placeholder(scheme, failed: _failed),
        ...layers,
      ],
    );

    if (widget.big) {
      if (!widget.rounded) return content;
      return ClipRRect(borderRadius: BorderRadius.circular(13), child: content);
    }
    return Container(
      width: widget.size,
      height: widget.size,
      color: scheme.surfaceContainerHighest.withValues(alpha: .5),
      child: content,
    );
  }

  /// Marcador de \"cargando\" (o de error reintentable). Evita el recuadro
  /// vacío mientras la imagen viaja desde el servidor.
  Widget _placeholder(ColorScheme scheme, {required bool failed}) {
    if (failed) {
      final iconSize = widget.big ? 34.0 : widget.size * .5;
      return InkWell(
        onTap: _retryManually,
        child: Tooltip(
          message: 'No se pudo cargar. Toca para reintentar',
          child: Center(
            child: Icon(
              Icons.refresh_rounded,
              size: iconSize,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    if (widget.big) {
      return Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: scheme.primary.withValues(alpha: .55),
          ),
        ),
      );
    }
    return Center(
      child: Icon(
        Icons.image_outlined,
        size: widget.size * .48,
        color: scheme.onSurfaceVariant.withValues(alpha: .7),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Aparición ESCALONADA (fade + deslizamiento hacia arriba) para listas y
/// cuadrículas: cada elemento entra con un pequeño retraso según su índice,
/// estilo Google Drive / apps modernas.
///
/// Uso en un itemBuilder:
///   return StaggeredItem(index: i, child: MiTile(...));
///
/// La animación NO se repite en rebuilds (selección, hover…) porque el
/// Tween no cambia; solo entra cuando el elemento se crea (aparece en
/// pantalla o cambia la carpeta).
class StaggeredItem extends StatelessWidget {
  const StaggeredItem({
    super.key,
    required this.child,
    this.index = 0,
    this.enabled = true,
  });

  final Widget child;

  /// Posición del elemento en la lista (0, 1, 2…): define el retraso.
  final int index;

  /// false = sin animación (se muestra directo). Útil al reciclar elementos
  /// fuera de la entrada inicial.
  final bool enabled;

  static const Duration _perItem = Duration(milliseconds: 40);
  static const Duration _maxDelay = Duration(milliseconds: 400);
  static const Duration _run = Duration(milliseconds: 300);

  Duration get _delay {
    final d = _perItem * (index < 0 ? 0 : index);
    return d > _maxDelay ? _maxDelay : d;
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final dur = _run + _delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: dur,
      curve: Interval(
        (_delay.inMilliseconds / dur.inMilliseconds).clamp(0.0, 0.95),
        1.0,
        curve: Curves.easeOutCubic,
      ),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 14),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Entrada individual: fade + deslizamiento hacia arriba.
/// Para títulos, tarjetas y secciones sueltas.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.distance = 16,
    this.duration = const Duration(milliseconds: 340),
  });

  final Widget child;
  final int delayMs;
  final double distance;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final dur = duration + Duration(milliseconds: delayMs);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: dur,
      curve: Interval(
        (delayMs / dur.inMilliseconds).clamp(0.0, 0.95),
        1.0,
        curve: Curves.easeOutCubic,
      ),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * distance),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Escala + fade para iconos/avatares destacados (estados vacíos, éxito…).
class PopIn extends StatelessWidget {
  const PopIn({super.key, required this.child, this.delayMs = 0});

  final Widget child;
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    final dur = const Duration(milliseconds: 380) + Duration(milliseconds: delayMs);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: dur,
      curve: Interval(
        (delayMs / dur.inMilliseconds).clamp(0.0, 0.95),
        1.0,
        curve: Curves.easeOutBack,
      ),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: .6 + .4 * t, child: child),
      ),
      child: child,
    );
  }
}

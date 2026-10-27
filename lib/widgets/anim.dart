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

/// Entrada de una tarjeta que aparece AL DESLIZAR.
///
/// A diferencia de [StaggeredItem] (que anima TODA la cuadrícula al abrir la
/// carpeta), esta se decide UNA vez, cuando la celda se construye:
///
/// * [animate] = true → la celda entra con fade + deslizamiento (es una que
///   apareció al bajar por la lista).
/// * [animate] = false → se pinta directa, sin animación (ya estaba a la
///   vista al abrir la carpeta).
///
/// El valor se captura en el primer build: los rebuilds posteriores (selección,
/// hover…) no vuelven a animar nada.
class ScrollReveal extends StatefulWidget {
  const ScrollReveal({
    super.key,
    required this.child,
    this.animate = true,
    this.distance = 14,
    this.duration = const Duration(milliseconds: 320),
  });

  final Widget child;

  /// Solo true cuando la celda nace DESPUÉS de que el usuario bajó.
  final bool animate;
  final double distance;
  final Duration duration;

  @override
  State<ScrollReveal> createState() => _ScrollRevealState();
}

class _ScrollRevealState extends State<ScrollReveal> {
  /// Se resuelve en el primer build (lazy `late`): no cambia en rebuilds.
  late final bool _animate = widget.animate;

  @override
  Widget build(BuildContext context) {
    if (!_animate) return widget.child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * widget.distance),
          child: child,
        ),
      ),
      child: widget.child,
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

/// ARO DE ATENCIÓN para un botón que el usuario DEBE tocar («Elegir fotos»,
/// «Enviar a impresión»…).
///
/// El botón se queda EXACTAMENTE como está —mismo tamaño, mismo sitio, mismo
/// color, sin crecer— y lo que se añade es un aro de su color dibujado POR
/// FUERA de él, que respira despacio: se abre un poco y su color sube y baja
/// (un ciclo completo ≈ 2,4 s).
///
/// El aro se PINTA, no ocupa espacio: no añade `Padding` ni `Transform`, así que
/// el botón sigue midiendo y colocándose igual dentro de un `SizedBox`, un
/// `Expanded` o una fila: nada se descuadra ni se monta sobre el botón vecino.
///
/// Con [enabled] = false se pinta el hijo tal cual (botón normal): el mismo
/// widget sirve para los estados en los que ya NO toca pulsarlo. Con «reducir
/// animaciones» del sistema el aro sigue saliendo, pero quieto: el paso
/// pendiente se sigue viendo aunque no haya animación.
class AttentionRing extends StatefulWidget {
  const AttentionRing({
    super.key,
    required this.child,
    this.enabled = true,
    this.color,
    this.radius = 10,
    this.gap = 3,
    this.width = 2,
    this.period = const Duration(milliseconds: 1200),
  });

  final Widget child;

  /// ¿Es el TURNO del usuario? false = botón normal, sin aro.
  final bool enabled;

  /// Color del aro; por defecto el color principal del tema.
  final Color? color;

  /// Radio del botón, para que el aro lo copie (los del tema usan 10).
  final double radius;

  /// Separación entre el botón y el aro cuando está recogido.
  final double gap;

  /// Grosor del aro.
  final double width;

  /// Cuánto dura una ida del latido (la vuelta tarda lo mismo).
  final Duration period;

  @override
  State<AttentionRing> createState() => _AttentionRingState();
}

class _AttentionRingState extends State<AttentionRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  /// «Reducir animaciones» del sistema: aro quieto (accesibilidad).
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(AttentionRing old) {
    super.didUpdateWidget(old);
    if (old.period != widget.period) _c.duration = widget.period;
    _sync();
  }

  /// Arranca o para el latido según el turno y las preferencias del sistema.
  void _sync() {
    final on = widget.enabled && !_reduced;
    if (on && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!on && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    AttentionRingPainter painter(double t) => AttentionRingPainter(
      color: color,
      radius: widget.radius,
      gap: widget.gap,
      width: widget.width,
      t: t,
    );
    // Aro quieto a media altura: se ve igual, sin moverse.
    if (_reduced) {
      return CustomPaint(painter: painter(.6), child: widget.child);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => CustomPaint(
        painter: painter(Curves.easeInOut.transform(_c.value)),
        willChange: true,
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Aro redondeado que se dibuja POR FUERA de la caja del botón (el botón queda
/// intacto: el aro no ocupa espacio en el layout, solo se pinta alrededor).
///
/// [t] va de 0 —recogido y tenue— a 1 —abierto, separado y con todo el color—.
class AttentionRingPainter extends CustomPainter {
  const AttentionRingPainter({
    required this.color,
    required this.radius,
    required this.gap,
    required this.width,
    required this.t,
  });

  final Color color;
  final double radius;
  final double gap;
  final double width;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final out = gap + 1.5 * t;
    final rect = Rect.fromLTWH(
      -out,
      -out,
      size.width + out * 2,
      size.height + out * 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color.withValues(alpha: .45 + .5 * t);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius + out)),
      paint,
    );
  }

  @override
  bool shouldRepaint(AttentionRingPainter old) =>
      old.t != t ||
      old.color != color ||
      old.radius != radius ||
      old.gap != gap ||
      old.width != width;
}

/// Escala + fade para iconos/avatares destacados (estados vacíos, éxito…).
class PopIn extends StatelessWidget {
  const PopIn({super.key, required this.child, this.delayMs = 0});

  final Widget child;
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    final dur =
        const Duration(milliseconds: 380) + Duration(milliseconds: delayMs);
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

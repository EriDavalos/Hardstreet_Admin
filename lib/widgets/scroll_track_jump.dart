import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Un CLIC en el carril de la barra de scroll SALTA al punto donde se hizo clic.
///
/// En Flutter el carril (y en Windows cualquier barra, como en el explorador)
/// AVANZA UNA PANTALLA hacia el lado en el que se hizo clic
/// ([RawScrollbarState.handleTrackTapDown] lanza un `ScrollIntent` de tipo
/// `page`), así que el clic se siente como «le di para bajar» en vez de «ir a
/// ese punto».
///
/// Aquí se pone una FRANJA justo encima del carril con su propio detector de
/// toques. Al ser el detector MÁS INTERNO entra primero en la arena de gestos y
/// gana el clic, así que el avance por pantalla del scrollbar nunca llega a
/// dispararse.
///
/// - El clic fuera del pulgar deja el pulgar CENTRADO en el punto clicado (los
///   extremos quedan topados por el propio rango de la lista).
/// - El clic SOBRE el pulgar no mueve nada: el pulgar se ARRASTRA como
///   siempre (el arrastre gana la arena al primer píxel de movimiento, así que
///   agarrar el pulgar sigue funcionando igual).
/// - La franja es `translucent`: la rueda del ratón, el arrastre y todo lo que
///   hay al lado del carril siguen llegando donde llegaban.
/// - En el TELÉFONO no hay barra (Material no la pone en Android/iOS), así que
///   la franja ni se pone: ahí el borde derecho es contenido, no carril.
class ScrollTrackJump extends StatelessWidget {
  const ScrollTrackJump({
    super.key,
    required this.controller,
    required this.child,
  });

  /// El controlador del scroll de [child]: de ahí sale la posición actual.
  final ScrollController controller;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Sin barra de scroll no hay carril que saltar (y el borde derecho es
    // contenido: poner la franja ahí se comería un clic de verdad).
    if (!_hasScrollbar(context)) return child;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final padding = MediaQuery.paddingOf(context);
    // La franja mide EXACTAMENTE el carril: el grosor del pulgar más su margen
    // de cada lado (mismos valores con los que lo pinta `ScrollbarPainter`).
    final theme = ScrollbarTheme.of(context);
    final width =
        (theme.thickness?.resolve(const <WidgetState>{}) ?? _thickness) +
        2 * (theme.crossAxisMargin ?? _margin) +
        (rtl ? padding.left : padding.right);
    return Stack(
      // `passthrough`: lo que hay dentro recibe las MISMAS medidas que antes,
      // así la franja no cambia el acomodo de la lista.
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned(
          right: rtl ? null : 0,
          left: rtl ? 0 : null,
          top: 0,
          bottom: 0,
          width: width,
          child: _TrackTap(controller: controller),
        ),
      ],
    );
  }

  /// ¿Esta plataforma pinta la barra de scroll? Es la misma condición con la
  /// que [MaterialScrollBehavior] decide envolver el scrollable.
  static bool _hasScrollbar(BuildContext context) {
    switch (Theme.of(context).platform) {
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.iOS:
        return false;
    }
  }
}

/// Grosor del pulgar por defecto (el de Material: `_kScrollbarThickness`).
const double _thickness = 8;

/// Margen del carril por defecto en escritorio (`_kScrollbarMargin`).
const double _margin = 2;

/// Largo mínimo del pulgar (`_kScrollbarMinLength`).
const double _minThumb = 18;

/// La franja del carril: un detector de toques que traduce el clic en un salto.
class _TrackTap extends StatelessWidget {
  const _TrackTap({required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // `translucent` (y no el `deferToChild` de siempre): el toque llega aquí
      // Y sigue de largo hacia el scrollable, que es el que sabe de la rueda,
      // del arrastre y de las tarjetas de al lado.
      behavior: HitTestBehavior.translucent,
      // En el TAP (no en el `tapDown`): presionar el pulgar para agarrarlo no
      // puede mover nada por sí solo.
      onTapUp: (details) => _jump(context, details.localPosition),
      child: const SizedBox.expand(),
    );
  }

  /// Salta a donde se hizo clic en el carril.
  void _jump(BuildContext context, Offset local) {
    final position = _position();
    if (position == null) return;
    final track = _Track.of(context, position);
    if (track == null) return;
    // Un clic sobre el pulgar no mueve nada: de ahí se agarra para arrastrar.
    if (track.holdsThumb(local.dy)) return;
    final target = track.offsetAt(local.dy);
    if (target == position.pixels) return;
    position.jumpTo(target);
  }

  /// La posición del scroll, si se puede leer.
  ///
  /// Tiene que estar en UNA sola vista: durante el cambio de carpeta el Drive
  /// mantiene dos a la vez (la transición de 220 ms) y ahí no hay nada que
  /// saltar —igual que el propio scrollbar, que en ese momento tampoco atiende
  /// el carril.
  ScrollPosition? _position() {
    if (!controller.hasClients) return null;
    final positions = controller.positions;
    if (positions.length != 1) return null;
    final position = positions.single;
    return position.hasContentDimensions ? position : null;
  }
}

/// Geometría del carril, con los MISMOS números con los que lo pinta
/// `ScrollbarPainter` (relleno, márgenes, largo del pulgar): así el salto cae
/// donde está el pulgar de verdad y no donde uno imagina que está.
class _Track {
  const _Track({
    required this.leading,
    required this.traversable,
    required this.thumb,
    required this.pixels,
    required this.min,
    required this.extent,
    required this.reversed,
  });

  /// Dónde arranca el carril (relleno del sistema + margen).
  final double leading;

  /// Largo que puede recorrer el pulgar.
  final double traversable;

  /// Largo del pulgar.
  final double thumb;

  /// Posición actual de la lista y rango por el que se mueve.
  final double pixels;
  final double min;
  final double extent;

  /// Eje invertido (de abajo a arriba): el pulgar crece al revés.
  final bool reversed;

  /// null cuando no hay nada que desplazar (lista corta) o no se puede leer.
  static _Track? of(BuildContext context, ScrollMetrics metrics) {
    final extent = metrics.maxScrollExtent - metrics.minScrollExtent;
    if (extent <= 0) return null;
    final theme = ScrollbarTheme.of(context);
    final padding = MediaQuery.paddingOf(context);
    final margin = theme.mainAxisMargin ?? 0;
    final traversable =
        metrics.viewportDimension - padding.vertical - 2 * margin;
    if (traversable <= 0) return null;
    // Cuánto se ve de la lista: es lo que mide el pulgar (igual que hace
    // `ScrollbarPainter._setThumbExtent`), con el largo mínimo del tema.
    final content = extent + metrics.viewportDimension - padding.vertical;
    final visible = content > 0
        ? ((metrics.extentInside - padding.vertical) / content).clamp(0.0, 1.0)
        : 1.0;
    final minThumb = math.min(theme.minThumbLength ?? _minThumb, traversable);
    return _Track(
      leading: padding.top + margin,
      traversable: traversable,
      thumb: (traversable * visible).clamp(minThumb, traversable),
      pixels: metrics.pixels,
      min: metrics.minScrollExtent,
      extent: extent,
      reversed:
          metrics.axisDirection == AxisDirection.up ||
          metrics.axisDirection == AxisDirection.left,
    );
  }

  /// Dónde arranca el pulgar dentro del carril.
  double get _thumbStart {
    final past = ((pixels - min) / extent).clamp(0.0, 1.0);
    return leading + (reversed ? 1 - past : past) * (traversable - thumb);
  }

  /// ¿El clic cayó sobre el pulgar? (de ahí se agarra para arrastrar)
  bool holdsThumb(double y) {
    final start = _thumbStart;
    return y >= start && y <= start + thumb;
  }

  /// Posición de la lista que deja el PULGAR CENTRADO en [y] (lo que se clicó
  /// queda donde quedó el pulgar) y topada al rango real de la lista.
  double offsetAt(double y) {
    final movable = traversable - thumb;
    if (movable <= 0) return min;
    final raw = ((y - leading - thumb / 2) / movable).clamp(0.0, 1.0);
    final past = reversed ? 1 - raw : raw;
    return min + past * extent;
  }
}

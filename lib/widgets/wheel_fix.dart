import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

// ==================================================================
// RUEDA DEL RATÓN: corrección global.
// En Windows ciertos drivers/mouse envían la rueda VERTICAL como delta
// horizontal (dx ≠ 0, dy = 0). Flutter solo rueda con dy (o con dx si la
// lista es horizontal), así que la rueda "no hace nada" y el usuario
// necesita Shift para que el evento llegue en el eje Y.
//
// Esta ScrollBehavior se inyecta en MaterialApp y envuelve el chrome de
// TODOS los scrollables: cuando el evento trae SOLO eje X, lo registra en
// el pointerSignalResolver y lo traduce a un avance vertical sobre el
// MISMO controller del scrollable. Los eventos con dy ≠ 0 (rueda normal)
// y el Shift se ignoran aquí: los resuelve el propio Scrollable como
// siempre (su Listener está más hacia adentro, así que registra primero).
// ==================================================================

/// ScrollBehavior global de la app (ver [MaterialApp.scrollBehavior]).
class HsScrollBehavior extends MaterialScrollBehavior {
  const HsScrollBehavior();

  @override
  Widget buildScrollbar(
      BuildContext context, Widget child, ScrollableDetails details) {
    final withScrollbar = super.buildScrollbar(context, child, details);
    final controller = details.controller;
    if (controller == null) return withScrollbar;
    return _HorizontalWheelFallback(
      controller: controller,
      reversed: details.direction == AxisDirection.up ||
          details.direction == AxisDirection.left,
      child: withScrollbar,
    );
  }
}

/// Envuelve el contenido de un scrollable y reclama los eventos de rueda
/// que traen SOLO eje horizontal (dx), moviendo el controller por su eje.
class _HorizontalWheelFallback extends StatefulWidget {
  const _HorizontalWheelFallback({
    required this.controller,
    required this.reversed,
    required this.child,
  });

  final ScrollController controller;

  /// true cuando el eje del scrollable está invertido (misma regla que
  /// `axisDirectionIsReversed` de Flutter, sin depender de rendering).
  final bool reversed;

  final Widget child;

  @override
  State<_HorizontalWheelFallback> createState() =>
      _HorizontalWheelFallbackState();
}

class _HorizontalWheelFallbackState extends State<_HorizontalWheelFallback> {
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final d = event.scrollDelta;
    // dy ≠ 0: rueda normal (o shift) → el Scrollable ya la resuelve.
    // dx == 0: nada que traducir.
    if (d.dy != 0 || d.dx == 0) return;

    final controller = widget.controller;
    if (!controller.hasClients) return;
    final position = controller.position;
    // Misma semántica que un avance vertical: +dx = hacia abajo (invertido
    // si el eje del scrollable está reversed, como hace el Scrollable).
    final delta = widget.reversed ? -d.dx : d.dx;
    final target = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target == position.pixels) return;

    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!mounted || !controller.hasClients) return;
      controller.jumpTo(target);
      event.respond(allowPlatformDefault: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: _onPointerSignal,
      child: widget.child,
    );
  }
}

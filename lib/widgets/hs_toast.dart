import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Tipo de aviso: define el color y el icono de la notificación.
///   success → verde  (la operación salió bien)
///   error   → rojo   (la operación falló)
///   info    → azul   (aviso neutro de la propia app)
enum HsToastKind { success, error, info }

/// Un aviso ya emitido, listo para pintarse.
class HsToastEvent {
  const HsToastEvent({
    required this.id,
    required this.message,
    required this.kind,
    this.details,
  });

  final int id;
  final String message;
  final HsToastKind kind;

  /// Detalle extra que manda el backend (`details`): el motivo concreto del
  /// error (qué permiso falta, qué campo está mal…).
  final String? details;
}

/// Notificaciones LATERALES de la app (esquina superior derecha).
///
/// Nada de SnackBars abajo: el aviso entra deslizándose por el costado, en
/// VERDE si la operación salió bien y en ROJO si falló. El texto lo pone el
/// BACKEND (`{ code, message, item }` / `{ code, message, details }`), así que
/// todos los módulos avisan exactamente igual.
///
/// El dibujado vive en [HsToastHost] (dentro de MaterialApp), así que el aviso
/// queda por encima de todo, diálogos incluidos. Si no hay host montado —por
/// ejemplo al probar una página suelta— los avisos se descartan sin ruido.
class HsToast {
  HsToast._();

  /// Cuánto tiempo permanece cada aviso en pantalla.
  static Duration duration = const Duration(seconds: 4);

  static final StreamController<HsToastEvent> _events =
      StreamController<HsToastEvent>.broadcast();
  static int _seq = 0;

  /// Stream que escucha [HsToastHost].
  static Stream<HsToastEvent> get events => _events.stream;

  /// Operación exitosa (verde).
  static void success(String message, {String? details}) =>
      _emit(HsToastKind.success, message, details);

  /// Operación fallida (rojo).
  static void error(String message, {String? details}) =>
      _emit(HsToastKind.error, message, details);

  /// Aviso neutro de la interfaz (azul).
  static void info(String message, {String? details}) =>
      _emit(HsToastKind.info, message, details);

  static void _emit(HsToastKind kind, String message, String? details) {
    final text = _clean(message);
    if (text.isEmpty) return;
    final detail = _clean(details ?? '');
    _events.add(HsToastEvent(
      id: ++_seq,
      message: text,
      kind: kind,
      // Un detalle vacío o idéntico al mensaje no se repite.
      details: (detail.isEmpty || detail == text) ? null : detail,
    ));
  }

  /// Los mensajes del backend llegan en una sola línea legible.
  static String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Capa donde se dibujan los avisos. Se coloca en el `builder` de MaterialApp,
/// por lo que flota POR ENCIMA del navegador (y de los diálogos abiertos).
class HsToastHost extends StatefulWidget {
  const HsToastHost({super.key, required this.child});

  final Widget child;

  @override
  State<HsToastHost> createState() => _HsToastHostState();
}

class _HsToastHostState extends State<HsToastHost> {
  final List<HsToastEvent> _toasts = [];
  final Map<int, Timer> _timers = {};
  StreamSubscription<HsToastEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = HsToast.events.listen(_onToast);
  }

  @override
  void dispose() {
    // Cancelar SIEMPRE: un Timer vivo haría fallar las pruebas de widgets.
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _sub?.cancel();
    super.dispose();
  }

  void _onToast(HsToastEvent e) {
    if (!mounted) return;
    setState(() {
      // Como mucho 4 avisos a la vez: el más viejo se va.
      while (_toasts.length >= 4) {
        final old = _toasts.removeAt(0);
        _timers.remove(old.id)?.cancel();
      }
      _toasts.add(e);
    });
    _timers[e.id] = Timer(HsToast.duration, () {
      _timers.remove(e.id);
      if (!mounted) return;
      setState(() => _toasts.removeWhere((t) => t.id == e.id));
    });
  }

  void _dismiss(HsToastEvent e) {
    _timers.remove(e.id)?.cancel();
    if (mounted) setState(() => _toasts.removeWhere((t) => t.id == e.id));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_toasts.isNotEmpty)
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final t in _toasts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _HsToastCard(
                            key: ValueKey<int>(t.id),
                            event: t,
                            onClose: () => _dismiss(t),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Tarjeta del aviso: acento de color, icono y (si el backend lo manda) el
/// detalle bajo el mensaje.
class _HsToastCard extends StatefulWidget {
  const _HsToastCard({super.key, required this.event, required this.onClose});

  final HsToastEvent event;
  final VoidCallback onClose;

  @override
  State<_HsToastCard> createState() => _HsToastCardState();
}

class _HsToastCardState extends State<_HsToastCard> {
  /// Entrada: aparece deslizándose desde el costado (sin AnimationController,
  /// que en las pruebas deja animaciones pendientes).
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (color, icon) = switch (widget.event.kind) {
      HsToastKind.success => (const Color(0xFF10B981), Icons.check_circle_rounded),
      HsToastKind.error => (const Color(0xFFEF4444), Icons.error_rounded),
      HsToastKind.info => (AppColors.brand, Icons.info_rounded),
    };

    return AnimatedSlide(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      offset: _shown ? Offset.zero : const Offset(1, 0),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: _shown ? 1 : 0,
        child: Material(
          color: isDark ? AppColors.cardDark : Colors.white,
          elevation: 0,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.cardDark : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: .45)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? .45 : .10),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Franja de color: identifica el resultado de un vistazo.
                    Container(width: 4, color: color),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 11, 6, 11),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(icon, size: 20, color: color),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.event.message,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      height: 1.25,
                                    ),
                                  ),
                                  if (widget.event.details != null) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      widget.event.details!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.3,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            // Sin `tooltip`: la capa de avisos vive POR ENCIMA
                            // del navegador y no hay Overlay para mostrarlo.
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              iconSize: 16,
                              onPressed: widget.onClose,
                              icon: Icon(
                                Icons.close_rounded,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

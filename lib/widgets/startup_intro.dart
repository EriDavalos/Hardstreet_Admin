import 'package:flutter/material.dart';

import '../theme.dart';
import 'brand_badge.dart';

/// Animación de ARRANQUE de la app (misma en Windows y en Android).
///
/// Es la primera pieza que se ve: el fondo del tema activo, la marca que entra
/// con un rebote suave, el nombre que se asienta y una barra fina que se llena.
/// Al terminar avisa con [onDone] y el panel hace un fundido cruzado hacia el
/// contenido, así que arrancar la app se siente continuo (nunca hay un salto
/// seco ni una pantalla en blanco de por medio).
///
/// Se dibuja con el TEMA ACTIVO (claro/oscuro), no con el del sistema: igual
/// que el widget de eventos, la app manda.
class StartupIntro extends StatefulWidget {
  const StartupIntro({super.key, required this.onDone, this.duration});

  /// Se llama UNA vez, al terminar la animación.
  final VoidCallback onDone;

  /// Duración total (se acorta en pruebas).
  final Duration? duration;

  /// Duración por defecto: suficiente para que se lea la marca, corta como para
  /// no hacer esperar.
  static const Duration defaultDuration = Duration(milliseconds: 1550);

  @override
  State<StartupIntro> createState() => _StartupIntroState();
}

class _StartupIntroState extends State<StartupIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration ?? StartupIntro.defaultDuration,
  );

  /// Marca: entra con rebote (easeOutBack) y un poco de escala.
  late final Animation<double> _logo = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, .42, curve: Curves.easeOutBack),
  );

  /// Nombre de la app: aparece y se "asienta" (letter spacing).
  late final Animation<double> _title = CurvedAnimation(
    parent: _c,
    curve: const Interval(.16, .56, curve: Curves.easeOutCubic),
  );

  /// Bajada ("Panel de administración").
  late final Animation<double> _subtitle = CurvedAnimation(
    parent: _c,
    curve: const Interval(.30, .68, curve: Curves.easeOutCubic),
  );

  /// Barra de progreso.
  late final Animation<double> _bar = CurvedAnimation(
    parent: _c,
    curve: const Interval(.34, .9, curve: Curves.easeOutCubic),
  );

  /// Fundido final hacia el contenido real.
  late final Animation<double> _exit = CurvedAnimation(
    parent: _c,
    curve: const Interval(.88, 1, curve: Curves.easeIn),
  );

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onDone();
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    // Mismo fondo que el panel: el fundido cruzado no deja costura.
    final background = dark ? const Color(0xFF0C111C) : const Color(0xFFF7F9FC);

    return Scaffold(
      backgroundColor: background,
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final logo = _logo.value;
          return Opacity(
            opacity: (1 - _exit.value).clamp(0.0, 1.0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Halo de la marca (respira con la entrada del logo).
                Center(
                  child: Container(
                    width: 320,
                    height: 320,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.brand.withValues(alpha: .16 * logo),
                          AppColors.brand.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ---- Marca ----
                      Opacity(
                        opacity: logo.clamp(0.0, 1.0),
                        child: Transform.scale(
                          // El rebote puede pasarse de 1: se dibuja sin recortes.
                          scale: .55 + .45 * logo,
                          child: const BrandBadge(size: 96, radius: 28),
                        ),
                      ),
                      const SizedBox(height: 22),
                      // ---- Nombre ----
                      Opacity(
                        opacity: _title.value.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, (1 - _title.value) * 14),
                          child: Text(
                            'HardStreet',
                            style: TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                              letterSpacing: 6 - 4.6 * _title.value,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Opacity(
                        opacity: _subtitle.value.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, (1 - _subtitle.value) * 10),
                          child: Text(
                            'Panel de administración',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 34),
                      // ---- Barra de progreso ----
                      Opacity(
                        opacity: _bar.value.clamp(0.0, 1.0),
                        child: Container(
                          width: 168,
                          height: 4,
                          decoration: BoxDecoration(
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: .18,
                            ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: _bar.value.clamp(0.0, 1.0),
                              child: Container(
                                height: 4,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.brand,
                                      AppColors.brandDark,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

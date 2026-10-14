import 'package:flutter/material.dart';

import '../theme.dart';
import 'anim.dart';

/// Paleta dorada de la marca (idéntica a la web: --gold / --gold-light) y el
/// fondo oscuro del "flyer" con el que se representan los paquetes.
class HsGold {
  HsGold._();

  static const gold = Color(0xFFC9A96E);
  static const goldLight = Color(0xFFF0D48A);
  static const dark = Color(0xFF0B0E17);
}

/// Look diferenciado por TIER: cada paquete se pinta según su nivel
/// (Premium = oro sobre negro, Gold = ámbar cálido, Basic = acero frío)
/// para que se distinga de un vistazo en tarjetas, fichas y selectores.
class HsTierLook {
  const HsTierLook({
    required this.accent,
    required this.accentSoft,
    required this.dark,
    required this.gradient,
    this.premium = false,
  });

  /// Acento principal (borde, precio, badges, barras).
  final Color accent;

  /// Acento claro, para degradados y texto sobre el flyer oscuro.
  final Color accentSoft;

  /// Fondo base oscuro del flyer.
  final Color dark;

  /// Degradado de fondo del flyer.
  final Gradient gradient;

  /// true solo para Premium (borde más marcado y Extras de brillo).
  final bool premium;

  static HsTierLook of(String tier) {
    switch (tier.trim().toLowerCase()) {
      case 'premium':
        return const HsTierLook(
          accent: Color(0xFFC9A96E),
          accentSoft: Color(0xFFF0D48A),
          dark: Color(0xFF0B0E17),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E1708), Color(0xFF0B0E17)],
          ),
          premium: true,
        );
      case 'gold':
        return const HsTierLook(
          accent: Color(0xFFD9A441),
          accentSoft: Color(0xFFF2C66B),
          dark: Color(0xFF120E05),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1206), Color(0xFF0E0A03)],
          ),
        );
      case 'basic':
      default:
        return const HsTierLook(
          accent: Color(0xFF8FB0D4),
          accentSoft: Color(0xFFB9D0E6),
          dark: Color(0xFF0B111A),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF101A28), Color(0xFF0A0F17)],
          ),
        );
    }
  }
}

/// Emoji representativo de la categoría del paquete (mismo criterio que la
/// web y el módulo Paquetes).
String hsCategoryIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('boda')) return '💍';
  if (n.contains('xv')) return '👑';
  if (n.contains('bautizo')) return '🕊️';
  if (n.contains('gradu')) return '🎓';
  if (n.contains('comercial')) return '💼';
  return '📷';
}

/// Tarjeta con icono, título, descripción y botón principal.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.onPrimary,
    this.primaryLabel,
    this.accent = false,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onPrimary;
  final String? primaryLabel;
  final bool accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accent
                    ? scheme.primary.withValues(alpha: .12)
                    : scheme.surfaceContainerHighest.withValues(alpha: .6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accent ? scheme.primary : scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
            ),
            if (primaryLabel != null) ...[
              const Spacer(),
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onPrimary, child: Text(primaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Píldora de estadística del encabezado (flat): icono en círculo tintado +
/// texto. La animación de entrada la maneja el [PageContainer] (escalonada).
class StatPill extends StatelessWidget {
  const StatPill({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 12, 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 13, color: scheme.primary),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Círculo decorativo plano (geometría de fondo del hero).
Widget _decoCircle(double d, Color c) => Container(
      width: d,
      height: d,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );

/// Barra de acento animada bajo el título: crece de 0 a su ancho con un
/// pequeño retraso (dinamismo de entrada, estilo editorial).
class _AccentBar extends StatelessWidget {
  const _AccentBar();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: const Interval(.25, 1, curve: Curves.easeOutCubic),
      builder: (context, t, _) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(top: 10),
          width: 48 * t,
          height: 4,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                scheme.primary,
                scheme.primary.withValues(alpha: .30),
              ],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// Encabezado HERO de cada módulo: tarjeta plana con degradado sutil,
/// círculos geométricos de fondo, icono con anillo (escala animada), título
/// con barra de acento, descripción, píldoras de estadísticas escalonadas
/// y acciones (botones) que bajan a fila propia en móvil.
///
/// DISEÑO PLANO: nada de sombras; profundidad por capas de tinte y borde.
class PageContainer extends StatelessWidget {
  const PageContainer({
    super.key,
    required this.title,
    required this.description,
    required this.child,
    this.actions,
    this.icon,
    this.stats = const [],
    this.expand = false,
  });

  final String title;
  final String description;
  final Widget child;

  /// Botones principales (crear, refrescar...). En móvil van en otra fila,
  /// a lo ancho y con el mismo peso visual entre sí.
  final List<Widget>? actions;

  /// Icono del avatar del módulo (null = sin avatar).
  final IconData? icon;

  /// Datos de contexto: 1-3 píldoras (conteos, estado del módulo).
  final List<StatPill> stats;

  /// true = el contenido LLENA el alto restante de la pantalla y la página NO
  /// hace scroll: úsalo en módulos que deben caber exactos (p. ej. el
  /// calendario de Agendas). El hijo debe adaptarse a una altura acotada.
  final bool expand;

  /// Semente estable para variar el ángulo del degradado por módulo
  /// (deriva del texto: mismo módulo → mismo diseño siempre).
  static int _seed(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 620;
    final flip = _seed(title).isOdd;
    final hasActions = actions?.isNotEmpty ?? false;

    final hero = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 18 : 22),
        // Degradado MUY sutil del color de marca: capa plana, no sombra.
        gradient: LinearGradient(
          begin: flip ? Alignment.bottomRight : Alignment.topLeft,
          end: flip ? Alignment.topLeft : Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: .08),
            scheme.primary.withValues(alpha: .015),
          ],
        ),
        border: Border.all(color: scheme.primary.withValues(alpha: .16)),
      ),
      child: Stack(
        children: [
          // Geometría decorativa plana (esquinas recortadas por el clip).
          Positioned(right: -36, top: -48, child: _decoCircle(150, scheme.primary.withValues(alpha: .05))),
          Positioned(right: 52, bottom: -60, child: _decoCircle(120, scheme.primary.withValues(alpha: .045))),
          Positioned(left: -50, bottom: -70, child: _decoCircle(130, scheme.primary.withValues(alpha: .03))),
          Padding(
            padding: EdgeInsets.all(compact ? 16 : 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (icon != null) ...[
                      // Icono con ANILLO: doble círculo plano + PopIn.
                      PopIn(
                        child: Container(
                          padding: const EdgeInsets.all(3.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: scheme.primary.withValues(alpha: .28),
                            ),
                          ),
                          child: Container(
                            width: compact ? 48 : 56,
                            height: compact ? 48 : 56,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [AppColors.brand, AppColors.brandDark],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Icon(icon,
                                color: Colors.white, size: compact ? 24 : 27),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                    color: scheme.onSurfaceVariant, height: 1.3),
                          ),
                          const _AccentBar(),
                        ],
                      ),
                    ),
                    // En escritorio las acciones van a la derecha del título,
                    // con aire ENTRE ellas (en celular horizontal los dos
                    // botones de Finanzas quedaban pegados, sin separación).
                    if (!compact && hasActions) ...[
                      const SizedBox(width: 16),
                      for (var i = 0; i < actions!.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        actions![i],
                      ],
                    ],
                  ],
                ),
                // Píldoras de estadísticas con entrada ESCALONADA.
                if (stats.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < stats.length; i++)
                        PopIn(delayMs: 140 + i * 70, child: stats[i]),
                    ],
                  ),
                ],
                // En móvil las acciones bajan a fila propia, a LO ANCHO. Si
                // no cabe una al lado de la otra (etiquetas largas, como en
                // Finanzas), cada botón va en su propia línea a todo ancho:
                // mejor una pila legible que etiquetas recortadas.
                if (compact && hasActions) ...[
                  const SizedBox(height: 14),
                  // En teléfono el padding por defecto de los botones (24 px
                  // por lado) se come el ancho y las etiquetas quedan a
                  // medias: aquí van con menos holgura horizontal.
                  Theme(
                    data: Theme.of(context).copyWith(
                      filledButtonTheme: FilledButtonThemeData(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                      outlinedButtonTheme: OutlinedButtonThemeData(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                      textButtonTheme: TextButtonThemeData(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                    child: LayoutBuilder(builder: (context, box) {
                      final n = actions!.length;
                      final each = (box.maxWidth - 10 * (n - 1)) / n;
                      if (each < 230) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final a in actions!) ...[
                              a,
                              if (a != actions!.last)
                                const SizedBox(height: 10),
                            ],
                          ],
                        );
                      }
                      return Row(
                        children: [
                          for (final a in actions!) ...[
                            Expanded(child: a),
                            if (a != actions!.last) const SizedBox(width: 10),
                          ],
                        ],
                      );
                    }),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    final padding =
        EdgeInsets.fromLTRB(compact ? 16 : 24, 18, compact ? 16 : 24, 24);

    // Modo "llenar pantalla": la página ocupa exactamente el alto disponible
    // (sin scroll) y el contenido se estira en el espacio restante.
    if (expand) {
      return Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FadeSlideIn(child: hero),
            const SizedBox(height: 18),
            Expanded(child: FadeSlideIn(delayMs: 90, child: child)),
          ],
        ),
      );
    }

    return ListView(
      padding: padding,
      children: [
        FadeSlideIn(child: hero),
        const SizedBox(height: 20),
        FadeSlideIn(delayMs: 90, child: child),
      ],
    );
  }
}

/// Skeleton de carga moderno (efecto shimmer con el tinte del tema):
/// sustituye al CircularProgressIndicator en las páginas de lista.
class ListSkeleton extends StatefulWidget {
  const ListSkeleton({super.key, this.lines = 4, this.cardHeight = 74});

  final int lines;
  final double cardHeight;

  @override
  State<ListSkeleton> createState() => _ListSkeletonState();
}

class _ListSkeletonState extends State<ListSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest.withValues(alpha: .55);
    final hi = scheme.surfaceContainerHighest;
    return Column(
      children: [
        for (var i = 0; i < widget.lines; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = (_c.value + i * .18) % 1;
              return Container(
                height: widget.cardHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    begin: Alignment(-1 + 2 * t, 0),
                    end: Alignment(0 + 2 * t, 0),
                    colors: [base, hi, base],
                    stops: const [0, .5, 1],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

/// Estado vacío reutilizable.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopIn(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .6),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 34, color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              FadeSlideIn(
                delayMs: 120,
                child: FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

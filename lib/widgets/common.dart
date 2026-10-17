import 'package:flutter/material.dart';

import '../theme.dart';
import 'anim.dart';
import 'hs_modal.dart';

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
  const StatPill({
    super.key,
    required this.icon,
    required this.label,
    this.dense = false,
  });

  final IconData icon;
  final String label;

  /// Móvil: la píldora va más chica (letra y aire menores) para no robar
  /// alto a la información del módulo.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: dense
          ? const EdgeInsets.fromLTRB(6, 4, 10, 4)
          : const EdgeInsets.fromLTRB(8, 5, 12, 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dense ? 19 : 22,
            height: dense ? 19 : 22,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                size: dense ? 11.5 : 13, color: scheme.primary),
          ),
          SizedBox(width: dense ? 6 : 7),
          Text(
            label,
            style: TextStyle(
              fontSize: dense ? 11.5 : 12.5,
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
    this.actionsInline = false,
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

  /// Móvil: mantiene los botones en UNA fila (se desliza de lado si no caben)
  /// en vez de apilarlos. Para módulos donde el alto es escaso y la
  /// información de abajo importa más (Finanzas), no para todos.
  final bool actionsInline;

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
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  // En el CELULAR la letra del héroe baja un
                                  // punto (y medio el texto): la tarjeta de
                                  // presentación se veía enorme.
                                  fontSize: compact ? 19 : null,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  height: compact ? 1.25 : 1.3,
                                  fontSize: compact ? 12.5 : null,
                                ),
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
                // Píldoras de estadísticas con entrada ESCALONADA. En MÓVIL van
                // en UNA sola fila que se desliza de lado (como en Finanzas):
                // antes el [Wrap] las apilaba en varios renglones y se comía el
                // alto de la información de abajo. En escritorio siguen
                // envueltas, que ahí sobra ancho.
                if (stats.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  if (compact)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(right: 2),
                      child: Row(
                        children: [
                          for (var i = 0; i < stats.length; i++) ...[
                            // Móvil: las píldoras van compactas (letra y aire
                            // menores) para que quepan varias sin robarte
                            // espacio a la información del módulo.
                            PopIn(
                              delayMs: 140 + i * 70,
                              child: StatPill(
                                icon: stats[i].icon,
                                label: stats[i].label,
                                dense: true,
                              ),
                            ),
                            if (i != stats.length - 1)
                              const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < stats.length; i++)
                          PopIn(delayMs: 140 + i * 70, child: stats[i]),
                      ],
                    ),
                ],
                // En móvil las acciones bajan a fila propia, a LO ANCHO y en
                // UNA sola fila que se desliza de lado (los botones no se
                // apilan ni se recortan): así el héroe conserva poco alto y la
                // información de abajo tiene la pantalla.
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
                    // En el teléfono los botones van SIEMPRE en UNA fila que se
                    // desliza de lado: apilados se comían el alto de la
                    // información de abajo (que es lo que el usuario viene a
                    // ver). [actionsInline] se conserva por compatibilidad, pero
                    // ya es el comportamiento por defecto en móvil.
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(right: 2),
                      child: Row(
                        children: [
                          for (final a in actions!) ...[
                            a,
                            if (a != actions!.last) const SizedBox(width: 10),
                          ],
                        ],
                      ),
                    ),
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

// ==================================================================
// Acciones del panel (encabezados y filas de lista)
// ==================================================================

/// Acción principal del encabezado de un módulo ("Nuevo cliente", "Nuevo
/// evento", "Actualizar", "Agregar movimiento"…).
///
/// * **Computadora**: el botón de siempre (icono + texto).
/// * **Celular**: un botón de IMAGEN —solo el icono, en un círculo tintado—
///   con el texto como tooltip. Así las acciones del héroe no compiten por el
///   ancho ni empujan la información del módulo hacia abajo.
class HsActionButton extends StatelessWidget {
  const HsActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.primary = true,
    this.tint,
  });

  final IconData icon;

  /// Texto del botón (en celular pasa a ser el tooltip).
  final String label;
  final VoidCallback? onPressed;

  /// true = acción principal (rellena, en el azul de la marca).
  final bool primary;

  /// Color propio de la acción (p. ej. el ahorro en verde azulado).
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = tint ?? scheme.primary;
    final phone = MediaQuery.sizeOf(context).width < kHsPhoneWidth;

    if (!phone) {
      return primary
          ? FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 18),
              label: Text(label),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color.withValues(alpha: .55)),
              ),
              icon: Icon(icon, size: 18),
              label: Text(label),
            );
    }

    // Celular: botón de imagen (solo el icono). El texto va como tooltip del
    // propio botón (una sola vez: envolverlo en otro Tooltip duplicaba el
    // globo y el nodo de accesibilidad).
    return primary
        ? IconButton.filled(
            onPressed: onPressed,
            tooltip: label,
            style: IconButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
            ),
            icon: Icon(icon, size: 20),
          )
        : IconButton.outlined(
            onPressed: onPressed,
            tooltip: label,
            style: IconButton.styleFrom(
              foregroundColor: color,
              side: BorderSide(color: color.withValues(alpha: .55)),
            ),
            icon: Icon(icon, size: 20),
          );
  }
}

/// Una opción del menú "⋮" de una fila ([HsRowMenu]).
class HsMenuAction {
  const HsMenuAction({
    required this.icon,
    required this.label,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;
}

/// ¿La pantalla es de TELÉFONO? Las filas de lista guardan sus acciones en
/// el menú "⋮" ([HsRowMenu]) solo en ese caso; en escritorio se conservan
/// los botones de siempre.
bool hsRowCompact(BuildContext context) =>
    MediaQuery.sizeOf(context).width < kHsPhoneWidth;

/// Los botones de una fila de lista agrupados en el menú "⋮".
///
/// Es el patrón del directorio de clientes, aplicado a todos los módulos en
/// el CELULAR: en una pantalla angosta los iconos "Editar / Eliminar…" no
/// caben junto al texto, así que se guardan aquí. Si ninguna opción está
/// disponible (falta de permisos), el menú NO se dibuja.
class HsRowMenu extends StatelessWidget {
  const HsRowMenu({super.key, required this.actions});

  final List<HsMenuAction> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = actions.where((a) => a.onTap != null).toList();
    if (enabled.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<HsMenuAction>(
      tooltip: 'Acciones',
      icon: Icon(Icons.more_vert_rounded,
          size: 20, color: scheme.onSurfaceVariant),
      onSelected: (a) => a.onTap?.call(),
      itemBuilder: (context) => [
        for (final a in enabled)
          PopupMenuItem<HsMenuAction>(
            value: a,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(a.icon,
                  size: 20, color: a.destructive ? scheme.error : null),
              title: Text(
                a.label,
                style: a.destructive ? TextStyle(color: scheme.error) : null,
              ),
            ),
          ),
      ],
    );
  }
}

/// Emoji de una categoría del catálogo (Boda 💍, XV Años 👑…).
///
/// Es el mismo rótulo que usa la web en la cabecera de cada tarjeta de
/// paquete: así el módulo Paquetes, la galería de Categorías y la página
/// hablan el mismo idioma (la web lo saca de `packages_categories.icon`, y
/// cuando viene vacío usa el nombre, como aquí).
String hsCategoryEmoji(String name) {
  final n = name.toLowerCase();
  if (n.contains('boda')) return '💍';
  if (n.contains('xv')) return '👑';
  if (n.contains('bautizo')) return '🕊️';
  if (n.contains('gradu')) return '🎓';
  if (n.contains('comercial')) return '💼';
  if (n.contains('famil')) return '👨‍👩‍👧';
  if (n.contains('matern')) return '🤰';
  if (n.contains('retrato')) return '📸';
  return '📷';
}

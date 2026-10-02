import 'package:flutter/material.dart';

import '../theme.dart';

/// Shell de la app: sidebar flotante que se desliza sobre el contenido
/// (no reduce el área visible), con scrim en móvil y desktop.
class AdminShell extends StatelessWidget {
  const AdminShell({
    super.key,
    required this.title,
    required this.selectedIndex,
    required this.onSelect,
    required this.destinations,
    required this.body,
    this.updateBanner,
    required this.dark,
    required this.onToggleTheme,
    required this.onToggleSidebar,
    required this.sidebarOpen,
    required this.userMenu,
    this.isCompact = false,
  });

  final String title;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final List<AdminDestination> destinations;
  final Widget body;

  /// Banner opcional de "actualización disponible" bajo la barra superior.
  final Widget? updateBanner;
  final bool dark;
  final VoidCallback onToggleTheme;
  final VoidCallback onToggleSidebar;
  final bool sidebarOpen;
  final Widget? userMenu;

  /// En pantallas angostas (celular) se usan controles compactos.
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // SafeArea: en MÓVIL el contenido empieza DEBAJO de la barra de
      // notificaciones (antes la app dibujaba a pantalla completa y la
      // top bar quedaba detrás del status bar).
      body: SafeArea(
        bottom: false,
        child: Stack(
        children: [
          // ===== Contenido (siempre ocupa todo) =====
          Column(
            children: [
              _TopBar(
                dark: dark,
                isCompact: isCompact,
                onToggleTheme: onToggleTheme,
                onToggleSidebar: onToggleSidebar,
                userMenu: userMenu,
              ),
              Divider(height: 1, color: Theme.of(context).dividerTheme.color),
              ?updateBanner,
              Expanded(
                // Transición fluida al cambiar de módulo: el contenido
                // anterior se desvanece mientras el nuevo entra deslizándose.
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, .02),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(title),
                    child: body,
                  ),
                ),
              ),
            ],
          ),
          // ===== Scrim =====
          AnimatedIgnorePointer(
            ignoring: !sidebarOpen,
            child: AnimatedOpacity(
              opacity: sidebarOpen ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: GestureDetector(
                onTap: onToggleSidebar,
                child: Container(color: Colors.black.withValues(alpha: .45)),
              ),
            ),
          ),
          // ===== Sidebar flotante =====
          AnimatedSlide(
            offset: sidebarOpen ? Offset.zero : const Offset(-1.05, 0),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: SizedBox(
              height: double.infinity,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isCompact ? 8 : 12, 10, 0, 10,
                ),
                child: Material(
                  color: isDark ? AppColors.sidebarDark : AppColors.sidebarLight,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  elevation: isDark ? 0 : 6,
                  shadowColor: Colors.black.withValues(alpha: .25),
                  child: SizedBox(
                    width: 264,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Marca
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 18, 12, 4),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [AppColors.brand, AppColors.brandDark],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: const Icon(
                                  Icons.apartment_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'HardStreet',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w800),
                                    ),
                                    Text(
                                      'Panel de administración',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                            fontSize: 11,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Cerrar menú',
                                visualDensity: VisualDensity.compact,
                                onPressed: onToggleSidebar,
                                icon: const Icon(Icons.close, size: 20),
                              ),
                            ],
          ),
                        ),
                        const SizedBox(height: 8),
                        // Navegación
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            children: [
                              for (var i = 0; i < destinations.length; i++)
                                _NavItem(
                                  destination: destinations[i],
                                  selected: i == selectedIndex,
                                  onTap: () => onSelect(i),
                                ),
                            ],
                          ),
                        ),
                        // Pie
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: userMenu ?? const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

/// Evita que el scrim capture taps cuando está invisible.
class AnimatedIgnorePointer extends StatelessWidget {
  const AnimatedIgnorePointer({
    super.key,
    required this.ignoring,
    required this.child,
  });

  final bool ignoring;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(ignoring: ignoring, child: child);
  }
}

class AdminDestination {
  const AdminDestination({
    required this.icon,
    required this.label,
    this.header,
  });

  final IconData icon;
  final String label;
  final String? header;

  static const headerNone = '__none__';
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AdminDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final header = destination.header;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null && header != AdminDestination.headerNone)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 16, 8, 6),
            child: Text(
              header.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Material(
            color: selected
                ? scheme.primary.withValues(alpha: .14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(
                  children: [
                    Icon(
                      destination.icon,
                      size: 20,
                      color: selected ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        destination.label,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected
                              ? scheme.primary
                              : scheme.onSurface.withValues(alpha: .85),
                        ),
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

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.dark,
    required this.isCompact,
    required this.onToggleTheme,
    required this.onToggleSidebar,
    this.userMenu,
  });

  final bool dark;
  final bool isCompact;
  final VoidCallback onToggleTheme;
  final VoidCallback onToggleSidebar;
  final Widget? userMenu;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 4 : 12),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Menú',
            onPressed: onToggleSidebar,
            icon: const Icon(Icons.menu),
          ),
          const Spacer(),
          IconButton(
            tooltip: dark ? 'Modo claro' : 'Modo oscuro',
            onPressed: onToggleTheme,
            icon: Icon(
              dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
          ),
          ?userMenu,
        ],
      ),
    );
  }
}

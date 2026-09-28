import 'package:flutter/material.dart';

import '../widgets/anim.dart';
import '../widgets/common.dart';

/// Ítems del menú de administración (aún no disponibles).
class AdminSection {
  const AdminSection(this.title, this.description, this.icon);

  final String title;
  final String description;
  final IconData icon;
}

const adminSections = [
  AdminSection(
    'Usuarios',
    'Administra cuentas, roles y permisos del equipo.',
    Icons.people_alt_rounded,
  ),
  AdminSection(
    'Clientes',
    'Directorio de clientes, su historial y paquetes.',
    Icons.badge_rounded,
  ),
  AdminSection(
    'Configuraciones',
    'Preferencias del sistema, catálogos e integraciones.',
    Icons.settings_rounded,
  ),
  AdminSection(
    'Reportes',
    'Métricas y reportes de la operación.',
    Icons.assessment_rounded,
  ),
];

/// Página genérica "Próximamente" para módulos no disponibles.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({super.key, required this.title, this.section});

  final String title;
  final AdminSection? section;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PageContainer(
      title: title,
      description:
          'Este módulo todavía no está disponible. Estamos trabajando en ello.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PopIn(
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.primary.withValues(alpha: .25)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: .14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      section?.icon ?? Icons.construction_rounded,
                      color: scheme.primary,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Próximamente',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    section?.description ??
                        'Módulo en desarrollo del panel de administración.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Lo que viene en el panel',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = (constraints.maxWidth / 260).floor().clamp(1, 4);
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  for (var i = 0; i < adminSections.length; i++)
                    StaggeredItem(
                      index: i,
                      child: SectionCard(
                        icon: adminSections[i].icon,
                        title: adminSections[i].title,
                        description: adminSections[i].description,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Placeholder del Dashboard con métricas y contadores animados.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PageContainer(
      title: 'Dashboard',
      description: 'Resumen general de la operación (datos de ejemplo).',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = (constraints.maxWidth / 240).floor().clamp(1, 4);
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.9,
                children: [
                  StaggeredItem(
                    index: 0,
                    child: _StatCard(
                      icon: Icons.people_alt_rounded,
                      label: 'Usuarios activos',
                      value: '12',
                      tint: scheme.primary,
                    ),
                  ),
                  StaggeredItem(
                    index: 1,
                    child: _StatCard(
                      icon: Icons.badge_rounded,
                      label: 'Clientes',
                      value: '48',
                      tint: const Color(0xFF8B5CF6),
                    ),
                  ),
                  StaggeredItem(
                    index: 2,
                    child: _StatCard(
                      icon: Icons.photo_library_rounded,
                      label: 'Imágenes en el Drive',
                      value: '—',
                      tint: const Color(0xFF10B981),
                    ),
                  ),
                  StaggeredItem(
                    index: 3,
                    child: _StatCard(
                      icon: Icons.folder_rounded,
                      label: 'Carpetas',
                      value: '—',
                      tint: const Color(0xFFF59E0B),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          StaggeredItem(
            index: 4,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    PopIn(
                      child: Icon(Icons.insights_rounded,
                          size: 40, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Métricas en camino',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Cuando los módulos de administración estén conectados, aquí verás actividad, crecimiento y reportes en tiempo real.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: tint.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: tint, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Contador animado: los números "corren" al entrar (0 → valor).
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, _) {
                      final n = int.tryParse(value);
                      return Text(
                        n == null ? value : '${(n * t).round()}',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      );
                    },
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../hs_access.dart';
import '../hs_api.dart';
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
      icon: Icons.construction_rounded,
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

/// DASHBOARD: página INICIAL del panel. Resumen real (usuarios, clientes y
/// catálogo desde la API) + accesos rápidos a los módulos con permiso.
/// `onNavigate('drive' | 'packages' | 'clients' | 'roles')` lo resuelve
/// AdminHome para cambiar de sección (solo si el usuario puede verla).
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, this.onNavigate});

  final ValueChanged<String>? onNavigate;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _users = const [];
  List<Map<String, dynamic>> _clients = const [];
  List<Map<String, dynamic>> _packages = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // Cada fuente falla en silencio: el dashboard muestra lo que pueda.
    List<Map<String, dynamic>> users = const [];
    List<Map<String, dynamic>> clients = const [];
    List<Map<String, dynamic>> packages = const [];
    var failures = 0;
    try {
      users = await HsApi.adminUsers();
    } catch (_) {
      failures++;
    }
    try {
      clients = await HsApi.clients();
    } catch (_) {
      failures++;
    }
    try {
      packages = await HsApi.adminPackages();
    } catch (_) {
      failures++;
    }
    if (!mounted) return;
    setState(() {
      _users = users;
      _clients = clients;
      _packages = packages;
      _error = failures >= 3
          ? 'No se pudo conectar con el servidor para cargar el resumen.'
          : null;
      _loading = false;
    });
  }

  String _money(num v) {
    final s = v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
    final parts = s.split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
    return 'MXN \$$intPart${parts.length > 1 ? '.${parts[1]}' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 620;
    final catalogValue = _packages.fold<num>(
        0, (a, p) => a + ((p['price'] as num?) ?? 0));

    return PageContainer(
      title: 'Dashboard',
      description: 'Resumen general de la operación.',
      icon: Icons.space_dashboard_rounded,
      stats: [
        StatPill(
            icon: Icons.people_alt_outlined,
            label: '${_users.length} usuarios internos'),
        StatPill(
            icon: Icons.badge_outlined, label: '${_clients.length} clientes'),
        StatPill(
            icon: Icons.card_giftcard_outlined,
            label: '${_packages.length} paquetes'),
      ],
      child: RefreshIndicator(
        onRefresh: _load,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(Icons.cloud_off_outlined,
                          size: 36, color: scheme.error),
                      const SizedBox(height: 10),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_loading)
              const ListSkeleton(lines: 3, cardHeight: 92)
            else ...[
              // ===== Métricas =====
              LayoutBuilder(builder: (context, box) {
                final cols = box.maxWidth < 480
                    ? 2
                    : box.maxWidth < 760
                        ? 2
                        : 4;
                return GridView.count(
                  crossAxisCount: cols,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  // En 2 columnas (móvil) la tarjeta es más cuadrada.
                  childAspectRatio: cols == 2 ? 1.55 : 1.9,
                  children: [
                    StaggeredItem(
                      index: 0,
                      child: _StatCard(
                        icon: Icons.people_alt_rounded,
                        label: 'Usuarios internos',
                        value: '${_users.length}',
                        tint: scheme.primary,
                      ),
                    ),
                    StaggeredItem(
                      index: 1,
                      child: _StatCard(
                        icon: Icons.badge_rounded,
                        label: 'Clientes',
                        value: '${_clients.length}',
                        tint: const Color(0xFF8B5CF6),
                      ),
                    ),
                    StaggeredItem(
                      index: 2,
                      child: _StatCard(
                        icon: Icons.card_giftcard_rounded,
                        label: 'Paquetes en catálogo',
                        value: '${_packages.length}',
                        tint: const Color(0xFF10B981),
                      ),
                    ),
                    StaggeredItem(
                      index: 3,
                      child: _StatCard(
                        icon: Icons.payments_rounded,
                        label: 'Valor del catálogo',
                        value: _money(catalogValue),
                        tint: const Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                );
              }),
              const SizedBox(height: 16),
              // ===== Accesos rápidos (según permisos del usuario) =====
              Text(
                'Accesos rápidos',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(builder: (context, box) {
                final shortcuts = <_Shortcut>[];
                bool can(String module) =>
                    HsAccess.instance.degraded ||
                    HsAccess.instance.canSee(module);
                if (can('Archivos')) {
                  shortcuts.add(const _Shortcut(
                      'Archivos', 'Organiza carpetas y fotos',
                      Icons.folder_copy_outlined, 'drive'));
                }
                if (can('Clientes')) {
                  shortcuts.add(const _Shortcut(
                      'Clientes', 'Directorio y paquetes',
                      Icons.badge_outlined, 'clients'));
                }
                if (can('Paquetes')) {
                  shortcuts.add(const _Shortcut(
                      'Paquetes', 'Diseña los paquetes de la web',
                      Icons.card_giftcard_outlined, 'packages'));
                }
                if (can('Roles')) {
                  shortcuts.add(const _Shortcut(
                      'Roles', 'Permisos por módulo',
                      Icons.admin_panel_settings_outlined, 'roles'));
                }
                final cols = box.maxWidth < 480 ? 2 : 4;
                return GridView.count(
                  crossAxisCount: cols,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: cols == 2 ? 1.35 : 1.9,
                  children: [
                    for (var i = 0; i < shortcuts.length; i++)
                      StaggeredItem(
                        index: i + 4,
                        child: _ShortcutTile(
                          shortcut: shortcuts[i],
                          onTap: () => widget.onNavigate?.call(shortcuts[i].key),
                        ),
                      ),
                  ],
                );
              }),
              const SizedBox(height: 16),
              // ===== Clientes recientes =====
              if (_clients.isNotEmpty) ...[
                Text(
                  'Clientes recientes',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0;
                          i < _clients.take(compact ? 3 : 5).length;
                          i++) ...[
                        if (i > 0)
                          Divider(
                              height: 1,
                              color: Theme.of(context).dividerTheme.color),
                        StaggeredItem(
                          index: i + 8,
                          child: _DashboardClientRow(
                              client: _clients[i]),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Definición de un acceso rápido del dashboard.
class _Shortcut {
  const _Shortcut(this.label, this.sub, this.icon, this.key);
  final String label;
  final String sub;
  final IconData icon;
  final String key;
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({required this.shortcut, required this.onTap});

  final _Shortcut shortcut;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(shortcut.icon, size: 22, color: scheme.primary),
              const SizedBox(height: 8),
              Text(
                shortcut.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
              Flexible(
                child: Text(
                  shortcut.sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fila compacta de cliente para el dashboard.
class _DashboardClientRow extends StatelessWidget {
  const _DashboardClientRow({required this.client});

  final Map<String, dynamic> client;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name =
        '${client['name'] ?? ''} ${client['lastname'] ?? ''}'.trim().trim();
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    final pkgCount = (client['packagesCount'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: .14),
            child: Text(
              initial,
              style: const TextStyle(
                color: Color(0xFF8B5CF6),
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name.isEmpty ? (client['email'] ?? '').toString() : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: pkgCount > 0
                  ? const Color(0xFF8B5CF6).withValues(alpha: .12)
                  : scheme.surfaceContainerHighest.withValues(alpha: .7),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$pkgCount paquete${pkgCount == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: pkgCount > 0
                    ? const Color(0xFF8B5CF6)
                    : scheme.onSurfaceVariant,
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
                        n == null
                            ? value
                            : (n == 0
                                ? value // valor no numérico (dinero): tal cual
                                : '${(n * t).round()}'),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
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

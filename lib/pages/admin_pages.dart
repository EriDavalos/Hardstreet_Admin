import 'package:flutter/material.dart';

import '../hs_access.dart';
import '../hs_api.dart';
import '../hs_format.dart';
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

/// DASHBOARD: página INICIAL del panel. Resumen ORDENADO de la operación con
/// todas las fuentes que ya tenemos (usuarios internos, clientes, catálogo y
/// agendas) y accesos rápidos a los módulos con permiso.
/// `onNavigate('drive' | 'agendas' | 'packages' | 'clients' | 'roles')` lo
/// resuelve AdminHome para cambiar de sección (solo si puede verla).
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
  List<Map<String, dynamic>> _agendas = const [];

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
    // Cada fuente falla en silencio: el dashboard muestra todo lo que sí cargó.
    var users = const <Map<String, dynamic>>[];
    var clients = const <Map<String, dynamic>>[];
    var packages = const <Map<String, dynamic>>[];
    var agendas = const <Map<String, dynamic>>[];
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
    try {
      agendas = await HsApi.agendas();
    } catch (_) {
      // Agendas es opcional: si falla, el resto del resumen sigue útil.
    }
    if (!mounted) return;
    setState(() {
      _users = users;
      _clients = clients;
      _packages = packages;
      _agendas = agendas;
      _error = failures >= 3
          ? 'No se pudo conectar con el servidor para cargar el resumen.'
          : null;
      _loading = false;
    });
  }

  bool _canSee(String module) =>
      HsAccess.instance.degraded || HsAccess.instance.canSee(module);

  /// Agendas futuras, ordenadas de la más próxima a la más lejana.
  List<Map<String, dynamic>> get _upcomingAgendas {
    final now = DateTime.now();
    final out = _agendas.where((a) {
      final d = hsParseDate(a['eventDate']);
      return d != null && d.isAfter(now);
    }).toList()
      ..sort((a, b) => '${a['eventDate']}'.compareTo('${b['eventDate']}'));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 620;
    final catalogValue =
        _packages.fold<num>(0, (a, p) => a + ((p['price'] as num?) ?? 0));
    final upcoming = _upcomingAgendas;

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
              _errorCard(scheme)
            else if (_loading)
              const ListSkeleton(lines: 3, cardHeight: 96)
            else ...[
              const _SectionHeader(
                  icon: Icons.insights_outlined, label: 'Resumen general'),
              const SizedBox(height: 10),
              _metrics(scheme, catalogValue, upcoming.length),
              const SizedBox(height: 22),
              const _SectionHeader(
                  icon: Icons.event_available_outlined,
                  label: 'Próximos eventos'),
              const SizedBox(height: 10),
              _upcomingCard(scheme, upcoming),
              const SizedBox(height: 22),
              const _SectionHeader(
                  icon: Icons.bolt_outlined, label: 'Accesos rápidos'),
              const SizedBox(height: 10),
              _shortcuts(),
              if (_clients.isNotEmpty) ...[
                const SizedBox(height: 22),
                const _SectionHeader(
                    icon: Icons.badge_outlined, label: 'Clientes recientes'),
                const SizedBox(height: 10),
                _recentClients(compact),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _errorCard(ColorScheme scheme) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.cloud_off_outlined, size: 36, color: scheme.error),
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
      );

  /// Métricas clave: 2 columnas en móvil, hasta 5 en pantallas anchas.
  Widget _metrics(ColorScheme scheme, num catalogValue, int upcomingCount) {
    final metrics = <_Metric>[
      _Metric('Usuarios internos', '${_users.length}',
          Icons.people_alt_rounded, scheme.primary),
      _Metric('Clientes', '${_clients.length}', Icons.badge_rounded,
          const Color(0xFF8B5CF6)),
      _Metric('Paquetes en catálogo', '${_packages.length}',
          Icons.card_giftcard_rounded, const Color(0xFF10B981)),
      _Metric('Valor del catálogo', hsMoney(catalogValue),
          Icons.payments_rounded, const Color(0xFFF59E0B)),
      _Metric('Agendas próximas', '$upcomingCount',
          Icons.event_available_rounded, const Color(0xFF3B82F6)),
    ];
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth < 520
          ? 2
          : box.maxWidth < 900
              ? 3
              : metrics.length.clamp(3, 5);
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: cols == 2 ? 1.5 : 2.0,
        children: [
          for (var i = 0; i < metrics.length; i++)
            StaggeredItem(index: i, child: _MetricCard(metric: metrics[i])),
        ],
      );
    });
  }

  Widget _upcomingCard(
      ColorScheme scheme, List<Map<String, dynamic>> upcoming) {
    if (upcoming.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(Icons.event_busy_outlined,
                  size: 26, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No hay eventos próximos. Crea agendas desde los paquetes '
                  'del cliente.',
                  style:
                      TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final shown = upcoming.take(4).toList();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: Theme.of(context).dividerColor),
            StaggeredItem(index: i, child: _UpcomingRow(agenda: shown[i])),
          ],
        ],
      ),
    );
  }

  Widget _shortcuts() {
    final shortcuts = <_Shortcut>[
      if (_canSee('Archivos'))
        const _Shortcut('Archivos', 'Carpetas y fotos',
            Icons.folder_copy_outlined, 'drive'),
      if (_canSee('Agendas'))
        const _Shortcut('Agendas', 'Eventos agendados',
            Icons.event_available_outlined, 'agendas'),
      if (_canSee('Clientes'))
        const _Shortcut('Clientes', 'Directorio y paquetes',
            Icons.badge_outlined, 'clients'),
      if (_canSee('Paquetes'))
        const _Shortcut('Paquetes', 'Catálogo de la web',
            Icons.card_giftcard_outlined, 'packages'),
      if (_canSee('Roles'))
        const _Shortcut('Roles', 'Permisos por módulo',
            Icons.admin_panel_settings_outlined, 'roles'),
    ];
    if (shortcuts.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth < 520 ? 2 : 4;
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: cols == 2 ? 1.4 : 1.95,
        children: [
          for (var i = 0; i < shortcuts.length; i++)
            StaggeredItem(
              index: i,
              child: _ShortcutTile(
                shortcut: shortcuts[i],
                onTap: () => widget.onNavigate?.call(shortcuts[i].key),
              ),
            ),
        ],
      );
    });
  }

  Widget _recentClients(bool compact) {
    final shown = _clients.take(compact ? 4 : 6).toList();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: Theme.of(context).dividerColor),
            StaggeredItem(
                index: i, child: _DashboardClientRow(client: shown[i])),
          ],
        ],
      ),
    );
  }
}

/// Encabezado de sección del dashboard.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

/// Definición de una métrica del resumen.
class _Metric {
  const _Metric(this.label, this.value, this.icon, this.tint);

  final String label;
  final String value;
  final IconData icon;
  final Color tint;
}

/// Tarjeta de métrica: icono tintado + valor grande y etiqueta.
class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: metric.tint.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(metric.icon, color: metric.tint, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      metric.value,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 17),
                    ),
                  ),
                  Text(
                    metric.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5, color: scheme.onSurfaceVariant),
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

/// Fila de un próximo evento: fecha tintada, cliente y servicio · paquete.
class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({required this.agenda});

  final Map<String, dynamic> agenda;

  static const _palette = [
    Color(0xFF8B5CF6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFF3B82F6),
    Color(0xFFEF4444),
    Color(0xFF14B8A6),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = hsParseDate(agenda['eventDate']);
    final sid = (agenda['serviceId'] as num?)?.toInt();
    final color =
        sid == null ? scheme.primary : _palette[sid.abs() % _palette.length];
    final client = (agenda['clientName'] ?? '').toString().trim();
    final service = (agenda['serviceName'] ?? '').toString().trim();
    final package = (agenda['packageName'] ?? '').toString().trim();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 46,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Column(
              children: [
                Text(
                  date == null ? '--' : '${date.day}',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15, color: color),
                ),
                Text(
                  date == null ? '' : kHsMonths[date.month - 1].substring(0, 3),
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700, color: color),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.isEmpty ? 'Sin cliente' : client,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (service.isNotEmpty) service,
                    if (package.isNotEmpty) package,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (date != null)
            Text(
              hsTimeLabel(date),
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 12.5, color: color),
            ),
        ],
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
                  style:
                      TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
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
    final email = (client['email'] ?? '').toString().trim();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: scheme.primaryContainer,
            child: Text(
              initial,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Sin nombre' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$pkgCount paq.',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

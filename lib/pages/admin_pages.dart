import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../drive_api_service.dart';
import '../finance_data.dart';
import '../hs_access.dart';
import '../hs_api.dart';
import '../hs_format.dart';
import '../widgets/anim.dart';
import '../widgets/common.dart';
import '../widgets/finance_chart.dart';

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
  const DashboardPage({super.key, this.onNavigate, this.drive});

  final ValueChanged<String>? onNavigate;

  /// Drive de la app (opcional): si es el drive REMOTO se consulta el
  /// espacio total/ocupado para la tarjeta "Espacio del drive".
  final DriveBase? drive;

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
  Map<String, dynamic>? _space;

  /// Finanzas del negocio (opcional: sin permiso o sin conexión, el resto del
  /// resumen sigue siendo útil).
  FinanceData? _finance;

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
    // Espacio del drive (solo drive remoto): opcional como todo el resto.
    Map<String, dynamic>? space;
    final apiDrive = widget.drive;
    if (apiDrive is DriveApiService) {
      try {
        space = await apiDrive.fetchSpace();
      } catch (_) {
        // Sin conexión al drive: la tarjeta simplemente no aparece.
      }
    }
    // Finanzas (ganancias, gastos, ahorro): también best effort.
    FinanceData? finance;
    try {
      finance = FinanceData.fromJson(await HsApi.finance());
    } catch (_) {
      // Sin permiso sobre Finanzas o sin conexión: no se muestra la sección.
    }
    if (!mounted) return;
    setState(() {
      _users = users;
      _clients = clients;
      _packages = packages;
      _agendas = agendas;
      _space = space;
      _finance = finance;
      _error = failures >= 3
          ? 'No se pudo conectar con el servidor para cargar el resumen.'
          : null;
      _loading = false;
    });
  }

  bool _canSee(String module) =>
      HsAccess.instance.degraded || HsAccess.instance.canSee(module);

  /// Además de los permisos, un módulo que el backend aún no registra
  /// (migración pendiente) se muestra: si no, una función nueva desaparecería
  /// del panel hasta aplicar el SQL.
  bool _showModule(String module) =>
      _canSee(module) || !HsAccess.instance.knows(module);

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
              if (_finance != null) ...[
                const SizedBox(height: 22),
                const _SectionHeader(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Finanzas'),
                const SizedBox(height: 10),
                _financeSection(scheme, _finance!),
              ],
              const SizedBox(height: 22),
              const _SectionHeader(
                  icon: Icons.bar_chart_rounded, label: 'Distribución'),
              const SizedBox(height: 10),
              _charts(scheme),
              if (_space != null) ...[
                const SizedBox(height: 12),
                _spaceCard(scheme, _space!),
              ],
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

  /// FINANZAS del negocio: el dinero en cuadros horizontales + la gráfica de
  /// los últimos meses (lo que entró contra lo que salió).
  Widget _financeSection(ColorScheme scheme, FinanceData f) {
    final t = f.totals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FinanceKpiGrid(
          currency: f.currency,
          kpis: [
            FinanceKpi(
              label: 'Ganancias',
              amount: t.ganancias,
              icon: Icons.payments_outlined,
              tint: FinanceColors.green,
              note: 'Abonos cobrados',
            ),
            FinanceKpi(
              label: 'Por cobrar',
              amount: t.porCobrar,
              icon: Icons.hourglass_bottom_rounded,
              tint: FinanceColors.amber,
            ),
            FinanceKpi(
              label: 'Disponible',
              amount: t.disponible,
              icon: Icons.savings_outlined,
              tint: FinanceColors.green,
            ),
            FinanceKpi(
              label: 'Ahorro',
              amount: t.ahorro,
              icon: Icons.lock_outline_rounded,
              tint: FinanceColors.teal,
            ),
            FinanceKpi(
              label: 'Gastos',
              amount: t.gastado,
              icon: Icons.trending_down,
              tint: FinanceColors.red,
              note: 'Con inversiones',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.show_chart_rounded,
                        size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Últimos 6 meses',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      'Entró vs. salió',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FinanceMonthBars(months: f.months, height: 130),
                const SizedBox(height: 14),
                const FinanceLegend(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Gráficas compactas (sin exceso): donut de paquetes por PLAN y
  /// barras de los paquetes más caros del catálogo.
  Widget _charts(ColorScheme scheme) {
    return LayoutBuilder(builder: (context, box) {
      final donut = Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _TierDonut(packages: _packages),
        ),
      );
      final bars = Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _PriceBars(packages: _packages),
        ),
      );
      if (box.maxWidth < 720) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [donut, const SizedBox(height: 12), bars],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: donut),
          const SizedBox(width: 12),
          Expanded(child: bars),
        ],
      );
    });
  }

  /// Formato legible de bytes (B / KB / MB / GB).
  static String _fmtBytes(num bytes) {
    const kb = 1024.0;
    const mb = kb * 1024;
    const gb = mb * 1024;
    final b = bytes.toDouble();
    if (b >= gb) return '${(b / gb).toStringAsFixed(1)} GB';
    if (b >= mb) return '${(b / mb).toStringAsFixed(1)} MB';
    if (b >= kb) return '${(b / kb).toStringAsFixed(1)} KB';
    return '${b.round()} B';
  }

  /// Tarjeta "Espacio del drive": ocupado vs. total + conteo de archivos.
  Widget _spaceCard(ColorScheme scheme, Map<String, dynamic> space) {
    final used = (space['usedBytes'] as num?) ?? 0;
    final total = space['totalBytes'] as num?;
    final files = (space['files'] as num?) ?? 0;
    final folders = (space['folders'] as num?) ?? 0;
    final pct =
        (total != null && total > 0) ? (used / total).clamp(0.0, 1.0) : null;
    const green = Color(0xFF10B981);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: green.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.storage_outlined, color: green),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Espacio del drive',
                      style:
                          TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    '${_fmtBytes(used)}${total != null ? ' de ${_fmtBytes(total)}' : ''} ocupados · $files archivos · $folders carpetas',
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: scheme.onSurfaceVariant),
                  ),
                  if (pct != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 7,
                        color: green,
                        backgroundColor: green.withValues(alpha: .14),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
      if (_showModule('Finanzas'))
        const _Shortcut('Finanzas', 'Ganancias y ahorro',
            Icons.account_balance_wallet_outlined, 'finance'),
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

// ===================== Gráficas del dashboard =====================

/// Donut: paquetes del catálogo agrupados por PLAN (tier).
/// Datos 100% tolerantes: si el backend no manda tier, van a "Sin plan".
class _TierDonut extends StatelessWidget {
  const _TierDonut({required this.packages});

  final List<Map<String, dynamic>> packages;

  static const _palette = <Color>[
    Color(0xFF8B5CF6), // violeta
    Color(0xFF3B82F6), // azul
    Color(0xFFF59E0B), // ámbar
    Color(0xFF10B981), // verde
    Color(0xFFEC4899), // rosa
  ];

  static String tierOf(Map<String, dynamic> p) {
    final raw = p['tierName'] ?? p['tier'] ?? '';
    final name = raw is Map ? (raw['name'] ?? '').toString() : raw.toString();
    final t = name.trim();
    return t.isEmpty ? 'Sin plan' : t;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (packages.isEmpty) {
      return Text(
        'Aún no hay paquetes en el catálogo.',
        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
      );
    }
    final counts = <String, int>{};
    for (final p in packages) {
      final k = tierOf(p);
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final colors = <String, Color>{};
    for (var i = 0; i < entries.length; i++) {
      colors[entries[i].key] = _palette[i % _palette.length];
    }
    final total = packages.length;

    return Row(
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: CustomPaint(
            painter: _DonutPainter(
              values: [for (final e in entries) e.value / total],
              colors: [for (final e in entries) colors[e.key]!],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colors[e.key],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          e.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        '${e.value} · ${((e.value / total) * 100).round()}%',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Pintor del donut (arcos con separación mínima y centro limpio).
class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.values, required this.colors});

  final List<double> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.shortestSide / 2;
    // Aro de fondo (visible cuando un plan no tiene paquetes).
    canvas.drawCircle(
      center,
      radius * 0.83,
      Paint()..color = const Color(0xFF8B5CF6).withValues(alpha: .10),
    );
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = (values[i] * 2 * math.pi - 0.03).clamp(0.0, 2 * math.pi);
      if (sweep <= 0) continue;
      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.30
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect.deflate(paint.strokeWidth / 2), start, sweep, false, paint);
      start += values[i] * 2 * math.pi;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.values != values || old.colors != colors;
}

/// Barras horizontales: los paquetes más caros del catálogo (top 4).
class _PriceBars extends StatelessWidget {
  const _PriceBars({required this.packages});

  final List<Map<String, dynamic>> packages;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (packages.isEmpty) {
      return Text(
        'Aún no hay paquetes en el catálogo.',
        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
      );
    }
    final sorted = [...packages]
      ..sort((a, b) => (((b['price'] as num?) ?? 0))
          .compareTo(((a['price'] as num?) ?? 0)));
    final top = sorted.take(4).toList();
    final max = ((top.first['price'] as num?) ?? 0).toDouble();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < top.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  (top[i]['name'] ?? 'Paquete').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                hsMoney(((top[i]['price'] as num?) ?? 0)),
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: scheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Container(
            height: 7,
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              widthFactor: max <= 0
                  ? 0
                  : (((top[i]['price'] as num?) ?? 0) / max)
                      .clamp(0.02, 1.0),
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [scheme.primary, scheme.primary.withValues(alpha: .6)],
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

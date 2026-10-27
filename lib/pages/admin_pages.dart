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
import '../widgets/notifications_card.dart';

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
  const ComingSoonPage({
    super.key,
    required this.title,
    this.section,
    this.module,
  });

  final String title;
  final AdminSection? section;

  /// Clave en `modules.module`: de ahí salen el nombre y la descripción.
  final String? module;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PageContainer(
      module: module,
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
                border: Border.all(
                  color: scheme.primary.withValues(alpha: .25),
                ),
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
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    section?.description ??
                        'Módulo en desarrollo del panel de administración.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Lo que viene en el panel',
            style: Theme.of(context).textTheme.titleMedium
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

  /// ¿Siguen en camino las fuentes OPCIONALES (finanzas y espacio del drive)?
  ///
  /// Mientras lo estén, sus tarjetas se pintan EN SU SITIO con un esqueleto de
  /// carga. Antes no existían hasta que llegaba el dato, así que aparecían de
  /// golpe y la pantalla se reacomodaba sola.
  bool _extrasLoading = false;

  /// ¿Hay un drive remoto al que preguntarle el espacio? Si no, no se reserva
  /// sitio para esa línea (nunca llegaría).
  bool get _spaceExpected => widget.drive is DriveApiService;

  /// ¿Se pinta la tarjeta de Finanzas? Se reserva mientras carga (si el rol
  /// puede verlas); si al final no hay dato, se retira.
  bool get _showFinance =>
      _finance != null || (_extrasLoading && _showModule('finance'));

  /// ¿Ya se pintó el tablero alguna vez? En un REFRESCO no se vuelve al
  /// esqueleto: las tarjetas se quedan con lo anterior hasta que llega lo
  /// nuevo (antes desaparecía todo y volvía, que es justo lo que se notaba).
  bool _hasBoard = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _extrasLoading = true;
    });
    // Las cuatro fuentes del resumen van A LA VEZ. Antes se pedían una detrás
    // de otra, así que el tablero esperaba la SUMA de las cuatro respuestas
    // (con red lenta, varios segundos de esqueletos). Cada una falla en
    // silencio: el dashboard muestra todo lo que sí cargó.
    final answers = await Future.wait([
      _tryList(HsApi.adminUsers),
      _tryList(HsApi.clients),
      _tryList(HsApi.adminPackages),
      _tryList(HsApi.agendas),
    ]);
    // Agendas es opcional: solo cuentan los fallos de las tres primeras.
    final failures = answers.take(3).where((a) => !a.ok).length;
    if (!mounted) return;
    setState(() {
      _users = answers[0].data;
      _clients = answers[1].data;
      _packages = answers[2].data;
      _agendas = answers[3].data;
      _error = failures >= 3
          ? 'No se pudo conectar con el servidor para cargar el resumen.'
          : null;
      _loading = false;
      _hasBoard = true;
    });
    // Lo opcional (finanzas y espacio del drive) va DESPUÉS y en paralelo: no
    // retrasa el resumen; sus tarjetas ya están en pantalla, cargando.
    await _loadExtras();
  }

  /// Una fuente del resumen: si falla se queda vacía y se avisa con `ok`.
  Future<({List<Map<String, dynamic>> data, bool ok})> _tryList(
    Future<List<Map<String, dynamic>>> Function() fetch,
  ) async {
    try {
      return (data: await fetch(), ok: true);
    } catch (_) {
      return (data: const <Map<String, dynamic>>[], ok: false);
    }
  }

  /// Finanzas y espacio del drive: opcionales y en paralelo con todo lo demás.
  Future<void> _loadExtras() async {
    final drive = widget.drive;
    final results = await Future.wait([
      if (drive is DriveApiService)
        _tryMap(drive.fetchSpace)
      else
        Future<Map<String, dynamic>?>.value(null),
      _tryMap(HsApi.finance),
    ]);
    if (!mounted) return;
    final finance = results[1];
    setState(() {
      _space = results[0];
      // Sin permiso sobre Finanzas o sin conexión: no se muestra la sección.
      if (finance != null) _finance = FinanceData.fromJson(finance);
      _extrasLoading = false;
    });
  }

  Future<Map<String, dynamic>?> _tryMap(
    Future<Map<String, dynamic>> Function() fetch,
  ) async {
    try {
      return await fetch();
    } catch (_) {
      return null;
    }
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
    final out =
        _agendas.where((a) {
            final d = hsParseDate(a['eventDate']);
            return d != null && d.isAfter(now);
          }).toList()
          ..sort((a, b) => '${a['eventDate']}'.compareTo('${b['eventDate']}'));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 620;
    // TABLERO sin scroll: en ventanas anchas todo el resumen cabe en la vista
    // (tres columnas en tarjetas compactas). En pantallas angostas se usa el
    // acomodo en una columna con scroll, que es lo único que cabe.
    final wide = size.width >= 1000;
    final catalogValue = _packages.fold<num>(
      0,
      (a, p) => a + ((p['price'] as num?) ?? 0),
    );
    final upcoming = _upcomingAgendas;

    return PageContainer(
      module: 'dashboard',
      title: 'Dashboard',
      description: wide
          ? 'Todo el resumen en una sola vista, sin bajar.'
          : 'Resumen general de la operación.',
      icon: Icons.space_dashboard_rounded,
      expand: wide,
      // En el tablero los conteos ya viven en la tira de métricas: repetirlos
      // en el encabezado solo robaba alto (y obligaba a bajar).
      stats: wide
          ? const <StatPill>[]
          : [
              StatPill(
                icon: Icons.people_alt_outlined,
                label: '${_users.length} usuarios internos',
              ),
              StatPill(
                icon: Icons.badge_outlined,
                label: '${_clients.length} clientes',
              ),
              StatPill(
                icon: Icons.card_giftcard_outlined,
                label: '${_packages.length} paquetes',
              ),
            ],
      child: RefreshIndicator(
        onRefresh: _load,
        child: _error != null
            ? _errorCard(scheme)
            : _loading && !_hasBoard
            ? const ListSkeleton(lines: 3, cardHeight: 96)
            : wide
            ? _board(scheme, catalogValue, upcoming)
            : _scrollSections(scheme, catalogValue, upcoming, compact),
      ),
    );
  }

  /// Acomodo en UNA columna con scroll (pantallas angostas): el de siempre.
  Widget _scrollSections(
    ColorScheme scheme,
    num catalogValue,
    List<Map<String, dynamic>> upcoming,
    bool compact,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(
          icon: Icons.insights_outlined,
          label: 'Resumen general',
        ),
        const SizedBox(height: 10),
        // En el CELULAR el resumen va en cuadros COMPACTOS (una línea cada uno,
        // 2-3 por fila): las tarjetas grandes se veían desordenadas y robaban
        // media pantalla. En tablet se conserva la rejilla de siempre.
        if (compact)
          _metricStrip(scheme, catalogValue, upcoming.length)
        else
          _metrics(scheme, catalogValue, upcoming.length),
        if (_showFinance) ...[
          const SizedBox(height: 22),
          const _SectionHeader(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Finanzas',
          ),
          const SizedBox(height: 10),
          // Mientras carga, la tarjeta está en su sitio con el esqueleto: no
          // aparece de golpe al terminar.
          _finance == null
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: ListSkeleton(lines: 2, cardHeight: 52),
                  ),
                )
              : _financeSection(scheme, _finance!),
        ],
        const SizedBox(height: 22),
        const _SectionHeader(
          icon: Icons.bar_chart_rounded,
          label: 'Distribución',
        ),
        const SizedBox(height: 10),
        _charts(scheme),
        if (_space != null || (_extrasLoading && _spaceExpected)) ...[
          const SizedBox(height: 12),
          _space == null
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: ListSkeleton(lines: 1, cardHeight: 14),
                  ),
                )
              : _spaceCard(scheme, _space!),
        ],
        const SizedBox(height: 22),
        const _SectionHeader(
          icon: Icons.event_available_outlined,
          label: 'Próximos eventos',
        ),
        const SizedBox(height: 10),
        _upcomingCard(scheme, upcoming),
        // Widget de NOTIFICACIONES: solo aparece cuando hay avisos, así el
        // tablero no se alarga de más.
        const SizedBox(height: 12),
        const NotificationsPanel(limit: 4),
        const SizedBox(height: 22),
        const _SectionHeader(
          icon: Icons.bolt_outlined,
          label: 'Accesos rápidos',
        ),
        const SizedBox(height: 10),
        _shortcuts(),
        if (_clients.isNotEmpty) ...[
          const SizedBox(height: 22),
          const _SectionHeader(
            icon: Icons.badge_outlined,
            label: 'Clientes recientes',
          ),
          const SizedBox(height: 10),
          _recentClients(compact),
        ],
      ],
    );
  }

  // ------------------- Tablero sin scroll (escritorio) -------------------

  /// Tres columnas que llenan el alto disponible: la página NO scrollea y, si
  /// una columna tiene más contenido del que cabe, scrollea SOLO ella.
  Widget _board(
    ColorScheme scheme,
    num catalogValue,
    List<Map<String, dynamic>> upcoming,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 4,
          child: _boardColumn([
            _panel(
              icon: Icons.insights_outlined,
              label: 'Resumen general',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _metricStrip(scheme, catalogValue, upcoming.length),
                  if (_space != null || (_extrasLoading && _spaceExpected)) ...[
                    const SizedBox(height: 8),
                    _space == null
                        ? const ListSkeleton(lines: 1, cardHeight: 12)
                        : _spaceLine(scheme, _space!),
                  ],
                ],
              ),
            ),
            if (_showFinance) ...[
              const SizedBox(height: 10),
              _panel(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Finanzas',
                // Mientras carga, la tarjeta ya está aquí con el esqueleto.
                child: _finance == null
                    ? const ListSkeleton(lines: 2, cardHeight: 52)
                    : _financeSection(
                        scheme,
                        _finance!,
                        bare: true,
                        chartHeight: 84,
                      ),
              ),
            ],
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: _boardColumn([
            _panel(
              icon: Icons.event_available_outlined,
              label: 'Próximos eventos',
              child: _upcomingRows(scheme, upcoming),
            ),
            if (_clients.isNotEmpty) ...[
              const SizedBox(height: 10),
              _panel(
                icon: Icons.badge_outlined,
                label: 'Clientes recientes',
                child: _clientRows(),
              ),
            ],
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: _boardColumn([
            _panel(
              icon: Icons.bar_chart_rounded,
              label: 'Distribución',
              child: _charts(scheme, bare: true),
            ),
            // El panel de avisos se pinta solo si HAY avisos: así el tablero
            // de escritorio sigue cabiendo entero cuando no hay nada nuevo.
            const NotificationsPanel(limit: 2, compact: true),
            const SizedBox(height: 10),
            _panel(
              icon: Icons.bolt_outlined,
              label: 'Accesos rápidos',
              child: _shortcuts(dense: true),
            ),
          ]),
        ),
      ],
    );
  }

  /// Una columna del tablero: si su contenido no cabe, scrollea por dentro.
  Widget _boardColumn(List<Widget> children) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  /// Tarjeta del tablero: encabezado de sección + contenido compacto.
  Widget _panel({
    required IconData icon,
    required String label,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(icon: icon, label: label),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  /// Tira de métricas COMPACTA (una sola línea de tarjetas bajas): cabe sin
  /// obligar a bajar en el tablero.
  Widget _metricStrip(ColorScheme scheme, num catalogValue, int upcomingCount) {
    final metrics = <_Metric>[
      _Metric(
        'Usuarios internos',
        '${_users.length}',
        Icons.people_alt_rounded,
        scheme.primary,
      ),
      _Metric(
        'Clientes',
        '${_clients.length}',
        Icons.badge_rounded,
        const Color(0xFF2F6BFF),
      ),
      _Metric(
        'En catálogo',
        '${_packages.length}',
        Icons.card_giftcard_rounded,
        const Color(0xFF2F6BFF),
      ),
      _Metric(
        'Valor del catálogo',
        hsMoney(catalogValue),
        Icons.payments_rounded,
        const Color(0xFFF59E0B),
      ),
      _Metric(
        'Agendas próximas',
        '$upcomingCount',
        Icons.event_available_rounded,
        const Color(0xFF3B82F6),
      ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final cols = w < 380
            ? 2
            : w < 620
            ? 3
            : 5;
        const gap = 8.0;
        final tileW = (w - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < metrics.length; i++)
              SizedBox(
                width: tileW,
                child: StaggeredItem(
                  index: i,
                  child: _MiniMetricCard(metric: metrics[i]),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Eventos próximos SIN la tarjeta exterior (el tablero ya es una tarjeta).
  /// Van AGRUPADOS POR DÍA: arriba la fecha y debajo los eventos de ese día
  /// (un mismo día puede tener dos o más).
  Widget _upcomingRows(
    ColorScheme scheme,
    List<Map<String, dynamic>> upcoming,
  ) {
    if (upcoming.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No hay eventos próximos. Crea agendas desde los paquetes del '
          'cliente.',
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
      );
    }
    final shown = upcoming.take(6).toList();
    final groups = _groupedByDay(shown);
    var index = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in groups) ...[
          StaggeredItem(
            index: index++,
            child: _UpcomingDayHeader(label: g.label),
          ),
          for (var i = 0; i < g.agendas.length; i++) ...[
            StaggeredItem(
              index: index++,
              child: _UpcomingRow(agenda: g.agendas[i]),
            ),
            if (!(g == groups.last && i == g.agendas.length - 1))
              Divider(
                height: 1,
                indent: 14,
                color: Theme.of(context).dividerColor,
              ),
          ],
        ],
      ],
    );
  }

  /// Agrupa los eventos (ya ordenados por fecha) por DÍA, con su etiqueta
  /// ("HOY · 16 OCT", "MAÑANA · 17 OCT", "VIE 18 OCT").
  List<_UpcomingGroup> _groupedByDay(List<Map<String, dynamic>> agendas) {
    final groups = <_UpcomingGroup>[];
    for (final a in agendas) {
      final date = hsParseDate(a['eventDate']);
      final label = date == null ? 'SIN FECHA' : hsDayLabel(date);
      if (groups.isEmpty || groups.last.label != label) {
        groups.add(_UpcomingGroup(label, []));
      }
      groups.last.agendas.add(a);
    }
    return groups;
  }

  /// Clientes recientes SIN la tarjeta exterior.
  Widget _clientRows() {
    final shown = _clients.take(5).toList();
    return Column(
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) Divider(height: 1, color: Theme.of(context).dividerColor),
          StaggeredItem(
            index: i,
            child: _DashboardClientRow(client: shown[i]),
          ),
        ],
      ],
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
      _Metric(
        'Usuarios internos',
        '${_users.length}',
        Icons.people_alt_rounded,
        scheme.primary,
      ),
      _Metric(
        'Clientes',
        '${_clients.length}',
        Icons.badge_rounded,
        const Color(0xFF2F6BFF),
      ),
      _Metric(
        'Paquetes en catálogo',
        '${_packages.length}',
        Icons.card_giftcard_rounded,
        const Color(0xFF2F6BFF),
      ),
      _Metric(
        'Valor del catálogo',
        hsMoney(catalogValue),
        Icons.payments_rounded,
        const Color(0xFFF59E0B),
      ),
      _Metric(
        'Agendas próximas',
        '$upcomingCount',
        Icons.event_available_rounded,
        const Color(0xFF3B82F6),
      ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
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
              StaggeredItem(
                index: i,
                child: _MetricCard(metric: metrics[i]),
              ),
          ],
        );
      },
    );
  }

  /// FINANZAS del negocio: el dinero en cuadros horizontales + la gráfica de
  /// los últimos meses (lo que entró contra lo que salió).
  /// [bare] = sin tarjeta propia (el tablero ya pinta una).
  Widget _financeSection(
    ColorScheme scheme,
    FinanceData f, {
    bool bare = false,
    double chartHeight = 130,
  }) {
    final t = f.totals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FinanceKpiGrid(
          currency: f.currency,
          // En el tablero (sin tarjeta propia) los cuadros van en UNA fila:
          // el alto es lo escaso y así no obliga a bajar.
          columns: bare ? 4 : null,
          kpis: [
            FinanceKpi(
              label: 'Ganancias',
              amount: t.ganancias,
              icon: Icons.payments_outlined,
              tint: FinanceColors.positive,
              note: 'Abonos cobrados',
            ),
            FinanceKpi(
              label: 'Disponible',
              amount: t.disponible,
              icon: Icons.savings_outlined,
              tint: FinanceColors.positive,
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
        _chartBox(scheme, f, chartHeight, bare: bare),
      ],
    );
  }

  Widget _chartBox(
    ColorScheme scheme,
    FinanceData f,
    double height, {
    required bool bare,
  }) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.show_chart_rounded, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Últimos 6 meses',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              'Entró vs. salió',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FinanceMonthBars(months: f.months, height: height),
        const SizedBox(height: 12),
        const FinanceLegend(),
      ],
    );
    if (bare) return content;
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: content),
    );
  }

  /// Gráficas compactas (sin exceso): donut de paquetes por PLAN y
  /// barras de los paquetes más caros del catálogo.
  Widget _charts(ColorScheme scheme, {bool bare = false}) {
    return LayoutBuilder(
      builder: (context, box) {
        Widget wrap(Widget child) => bare
            ? Padding(padding: const EdgeInsets.all(4), child: child)
            : Card(
                child: Padding(padding: const EdgeInsets.all(16), child: child),
              );
        final donut = wrap(_TierDonut(packages: _packages));
        final bars = wrap(_PriceBars(packages: _packages));
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
      },
    );
  }

  /// Espacio del drive en UNA línea (versión de tablero de [_spaceCard]).
  Widget _spaceLine(ColorScheme scheme, Map<String, dynamic> space) {
    final used = (space['usedBytes'] as num?) ?? 0;
    // Se muestra la CUOTA de la carpeta (180 GB por defecto), no el tamaño
    // del disco: es el límite que maneja el estudio.
    final quota = space['limitBytes'] as num?;
    final total = quota ?? (space['totalBytes'] as num?);
    final files = (space['files'] as num?) ?? 0;
    final folders = (space['folders'] as num?) ?? 0;
    final pct = (total != null && total > 0)
        ? (used / total).clamp(0.0, 1.0)
        : null;
    const green = Color(0xFF2F6BFF);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: green.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: green.withValues(alpha: .22)),
      ),
      child: Row(
        children: [
          const Icon(Icons.storage_outlined, size: 15, color: green),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '${_fmtBytes(used)}${total != null ? ' de ${_fmtBytes(total)}' : ''}'
              '${quota != null ? ' de cuota' : ''}'
              ' · $files archivos · $folders carpetas',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ),
          if (pct != null) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 54,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 6,
                  color: green,
                  backgroundColor: green.withValues(alpha: .16),
                ),
              ),
            ),
          ],
        ],
      ),
    );
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

  /// Tarjeta "Espacio del drive": ocupado vs. la CUOTA + conteo de archivos.
  Widget _spaceCard(ColorScheme scheme, Map<String, dynamic> space) {
    final used = (space['usedBytes'] as num?) ?? 0;
    // La barra se mide contra la CUOTA (180 GB), no contra el disco completo.
    final quota = space['limitBytes'] as num?;
    final total = quota ?? (space['totalBytes'] as num?);
    final files = (space['files'] as num?) ?? 0;
    final folders = (space['folders'] as num?) ?? 0;
    final pct = (total != null && total > 0)
        ? (used / total).clamp(0.0, 1.0)
        : null;
    const green = Color(0xFF2F6BFF);
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
                  const Text(
                    'Espacio del drive',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_fmtBytes(used)}${total != null ? ' de ${_fmtBytes(total)}' : ''}'
                    '${quota != null ? ' de cuota' : ''}'
                    ' · $files archivos · $folders carpetas',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: scheme.onSurfaceVariant,
                    ),
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
    ColorScheme scheme,
    List<Map<String, dynamic>> upcoming,
  ) {
    if (upcoming.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(
                Icons.event_busy_outlined,
                size: 26,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No hay eventos próximos. Crea agendas desde los paquetes '
                  'del cliente.',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final shown = upcoming.take(4).toList();
    final groups = _groupedByDay(shown);
    var index = 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final g in groups) ...[
            StaggeredItem(
              index: index++,
              child: _UpcomingDayHeader(label: g.label),
            ),
            for (var i = 0; i < g.agendas.length; i++) ...[
              StaggeredItem(
                index: index++,
                child: _UpcomingRow(agenda: g.agendas[i]),
              ),
              if (!(g == groups.last && i == g.agendas.length - 1))
                Divider(
                  height: 1,
                  indent: 14,
                  color: Theme.of(context).dividerColor,
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _shortcuts({bool dense = false}) {
    final shortcuts = <_Shortcut>[
      if (_canSee('Archivos'))
        const _Shortcut(
          'Archivos',
          'Carpetas y fotos',
          Icons.folder_copy_outlined,
          'drive',
        ),
      if (_canSee('Agendas'))
        const _Shortcut(
          'Agendas',
          'Eventos agendados',
          Icons.event_available_outlined,
          'agendas',
        ),
      if (_showModule('Finanzas'))
        const _Shortcut(
          'Finanzas',
          'Ganancias y ahorro',
          Icons.account_balance_wallet_outlined,
          'finance',
        ),
      if (_canSee('Clientes'))
        const _Shortcut(
          'Clientes',
          'Directorio y paquetes',
          Icons.badge_outlined,
          'clients',
        ),
      if (_canSee('Paquetes'))
        const _Shortcut(
          'Paquetes',
          'Catálogo de la web',
          Icons.card_giftcard_outlined,
          'packages',
        ),
      if (_canSee('Roles'))
        const _Shortcut(
          'Roles',
          'Permisos por módulo',
          Icons.admin_panel_settings_outlined,
          'roles',
        ),
    ];
    if (shortcuts.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        // En el tablero los accesos van COMPACTOS (3 por fila) para no comer
        // alto; en el acomodo con scroll se quedan como siempre.
        final cols = dense
            ? (box.maxWidth < 300 ? 2 : 3)
            : (box.maxWidth < 520 ? 2 : 4);
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: dense
              ? (cols == 2 ? 1.35 : 1.05)
              : (cols == 2 ? 1.4 : 1.95),
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
      },
    );
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
              index: i,
              child: _DashboardClientRow(client: shown[i]),
            ),
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
        // El encabezado puede estar en una columna angosta del tablero: el
        // texto se adapta al ancho disponible en vez de desbordar la tarjeta.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
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
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  Text(
                    metric.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
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

/// Métrica COMPACTA del tablero (una línea, alto fijo): así la tira de
/// indicadores no obliga a bajar en el dashboard.
class _MiniMetricCard extends StatelessWidget {
  const _MiniMetricCard({required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: metric.tint.withValues(alpha: .26)),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: metric.tint.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(metric.icon, color: metric.tint, size: 14),
          ),
          const SizedBox(width: 8),
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
                    maxLines: 1,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: metric.tint,
                    ),
                  ),
                ),
                Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Día de un grupo de eventos próximos (etiqueta + sus agendas).
class _UpcomingGroup {
  const _UpcomingGroup(this.label, this.agendas);

  /// Etiqueta del día: `HOY · 16 OCT`, `MAÑANA · 17 OCT`, `VIE 18 OCT`.
  final String label;
  final List<Map<String, dynamic>> agendas;
}

/// Encabezado de FECHA sobre un grupo de eventos del mismo día.
class _UpcomingDayHeader extends StatelessWidget {
  const _UpcomingDayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isToday = label.startsWith('HOY');
    final color = isToday ? scheme.primary : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
      child: Row(
        children: [
          Icon(Icons.calendar_today_rounded, size: 11, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                letterSpacing: .6,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: .45),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de un próximo evento: hora tintada, cliente y servicio · paquete.
/// La FECHA vive en el encabezado del día ([_UpcomingDayHeader]); aquí va la
/// hora, que es lo que importa al leer los eventos de ese día.

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({required this.agenda});

  final Map<String, dynamic> agenda;

  static const _palette = [
    Color(0xFF2F6BFF),
    Color(0xFF2F6BFF),
    Color(0xFFF59E0B),
    Color(0xFF3B82F6),
    Color(0xFFEF4444),
    Color(0xFF2F6BFF),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = hsParseDate(agenda['eventDate']);
    final sid = (agenda['serviceId'] as num?)?.toInt();
    final color = sid == null
        ? scheme.primary
        : _palette[sid.abs() % _palette.length];
    final client = (agenda['clientName'] ?? '').toString().trim();
    final service = (agenda['serviceName'] ?? '').toString().trim();
    final package = (agenda['packageName'] ?? '').toString().trim();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          Container(
            width: 46,
            padding: const EdgeInsets.symmetric(vertical: 5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              date == null ? '--:--' : hsTimeLabel(date),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                color: color,
              ),
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
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
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
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
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
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              Flexible(
                child: Text(
                  shortcut.sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
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
    final name = '${client['name'] ?? ''} ${client['lastname'] ?? ''}'
        .trim()
        .trim();
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
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
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
    Color(0xFF2F6BFF), // turquesa
    Color(0xFF3B82F6), // azul
    Color(0xFFF59E0B), // ámbar
    Color(0xFF2F6BFF), // verde
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
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${e.value} · ${((e.value / total) * 100).round()}%',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                        ),
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
      Paint()..color = const Color(0xFF2F6BFF).withValues(alpha: .10),
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
      canvas.drawArc(
        rect.deflate(paint.strokeWidth / 2),
        start,
        sweep,
        false,
        paint,
      );
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
      ..sort(
        (a, b) => (((b['price'] as num?) ?? 0)).compareTo(
          ((a['price'] as num?) ?? 0),
        ),
      );
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
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                hsMoney(((top[i]['price'] as num?) ?? 0)),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
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
                  : (((top[i]['price'] as num?) ?? 0) / max).clamp(0.02, 1.0),
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      scheme.primary,
                      scheme.primary.withValues(alpha: .6),
                    ],
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

import 'package:flutter/material.dart';

import '../finance_data.dart';
import '../hs_access.dart';
import '../hs_api.dart';
import '../hs_format.dart';
import '../widgets/common.dart';
import '../widgets/finance_chart.dart';
import '../widgets/form_dialog.dart';
import '../widgets/hs_toast.dart';

// ==================================================================
// MÓDULO FINANZAS
//
// Una vista moderna con TRES pestañas:
//
//   * RESUMEN      el DINERO ACTUAL (abonado + abono externo - gastos -
//                  inversión - ahorro - pagos) y la tabla del movimiento
//                  del dinero: abonado, gastos, inversión, ahorro, por
//                  cobrar y abono externo. Abajo, la gráfica de los
//                  últimos meses y los movimientos recientes.
//   * POR PAQUETE  esa misma información separada por paquete (los
//                  paquetes gratis SIN movimiento no aparecen).
//   * PAGOS        todo lo pagado a cada colaborador y empleado: total
//                  histórico, cuántos pagos y en qué paquetes.
//
// Los pagos a colaboradores/empleados SÍ salen del dinero actual (antes se
// trataban como un "gasto invisible").
// ==================================================================

/// Etiqueta / icono / color de cada tipo de movimiento (mismo lenguaje que el
/// administrador del paquete del cliente).
String _kindLabel(String kind) => switch (kind) {
  'abono' => 'Abonos',
  'abono_externo' => 'Abonos externos',
  'inversion' => 'Inversiones',
  'ahorro' => 'Ahorro',
  'pago' => 'Pagos',
  _ => 'Gastos',
};

IconData _kindIcon(String kind) => switch (kind) {
  'abono' => Icons.payments_outlined,
  'abono_externo' => Icons.account_balance_wallet_outlined,
  'inversion' => Icons.trending_up,
  'ahorro' => Icons.savings_rounded,
  'pago' => Icons.handshake_outlined,
  _ => Icons.trending_down,
};

Color _kindColor(String kind) => switch (kind) {
  'abono' => FinanceColors.positive,
  'abono_externo' => FinanceColors.blue,
  'inversion' => FinanceColors.investment,
  'ahorro' => FinanceColors.teal,
  'pago' => FinanceColors.amber,
  _ => FinanceColors.red,
};

/// Tipos que se pueden REGISTRAR desde Finanzas. Los abonos entran por el
/// paquete y los pagos se reparten desde el administrador del paquete (ahí se
/// elige a quién), así que aquí no se ofrecen.
const List<String> _kEditableKinds = [
  'gasto',
  'inversion',
  'ahorro',
  'abono_externo',
];

/// Iniciales de un nombre (avatar de las personas).
String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
}

class FinancePage extends StatefulWidget {
  const FinancePage({super.key});

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  bool _loading = true;
  String? _error;
  FinanceData _data = const FinanceData();

  /// 0 = Resumen, 1 = Por paquete, 2 = Pagos.
  int _tab = 0;

  /// Búsqueda de la pestaña "Por paquete".
  String _packageQuery = '';

  /// Filas expandidas (paquetes y personas).
  final Set<String> _open = <String>{};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await HsApi.finance();
      if (!mounted) return;
      setState(() {
        _data = FinanceData.fromJson(raw);
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar las finanzas';
        _loading = false;
      });
    }
  }

  bool get _canSave =>
      HsAccess.instance.degraded || HsAccess.instance.can('Finanzas', 'update');

  void _toggle(String key) {
    setState(() {
      if (!_open.add(key)) _open.remove(key);
    });
  }

  /// Paquetes que pasan la búsqueda de la pestaña "Por paquete".
  List<FinancePackage> get _visiblePackages {
    final q = _packageQuery.trim().toLowerCase();
    if (q.isEmpty) return _data.packages;
    return _data.packages
        .where((p) => '${p.name} ${p.clientName}'.toLowerCase().contains(q))
        .toList(growable: false);
  }

  /// Abre el diálogo para REGISTRAR un movimiento (gasto, inversión, ahorro
  /// o abono externo). Sin paquete el movimiento es GENERAL (del negocio).
  Future<void> _addMovement({
    FinancePackage? package,
    String kind = 'gasto',
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _FinanceMovementDialog(
        packages: _data.packages,
        currency: _data.currency,
        totals: _data.totals,
        initial: package,
        kind: kind,
      ),
    );
    if (saved == true) {
      HsToast.info(
        package == null
            ? 'Movimiento general registrado'
            : 'Movimiento registrado en ${package.name}',
      );
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _data.totals;
    final currency = _data.currency;
    final narrow = MediaQuery.sizeOf(context).width < 620;

    return PageContainer(
      module: 'finance',
      title: 'Finanzas',
      description: narrow
          ? 'El dinero actual, por paquete y por persona.'
          : 'El dinero actual del negocio: abonado, salidas, ahorro y pagos, '
                'con el detalle por paquete y por persona.',
      icon: Icons.account_balance_wallet_outlined,
      onRefresh: _reload,
      actionsInline: true,
      stats: [
        StatPill(
          icon: Icons.account_balance_wallet_rounded,
          label: 'Actual ${hsMoney(t.dineroActual, currency)}',
        ),
        StatPill(
          icon: Icons.hourglass_bottom_rounded,
          label: 'Por cobrar ${hsMoney(t.porCobrar, currency)}',
        ),
        StatPill(
          icon: Icons.handshake_outlined,
          label: 'Pagado a personas ${hsMoney(t.pagos, currency)}',
        ),
      ],
      actions: [
        if (_canSave)
          HsActionButton(
            onPressed: () => _addMovement(kind: 'gasto'),
            icon: Icons.add,
            label: narrow ? 'Movimiento' : 'Registrar movimiento',
          ),
      ],
      child: _body(Theme.of(context).colorScheme, t, currency),
    );
  }

  Widget _body(ColorScheme scheme, FinanceTotals t, String currency) {
    if (_loading) return const ListSkeleton(lines: 3, cardHeight: 104);
    if (_error != null) return _errorCard(scheme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tabs(scheme),
        const SizedBox(height: 16),
        switch (_tab) {
          1 => _packagesTab(scheme, currency),
          2 => _paymentsTab(scheme, currency),
          _ => _summaryTab(scheme, t, currency),
        },
      ],
    );
  }

  // ---------------------------------------------------------------
  // Pestañas
  // ---------------------------------------------------------------

  Widget _tabs(ColorScheme scheme) {
    const tabs = <(String, IconData)>[
      ('Resumen', Icons.dashboard_outlined),
      ('Por paquete', Icons.inventory_2_outlined),
      ('Pagos', Icons.handshake_outlined),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _TabPill(
              key: ValueKey('finance-tab-$i'),
              label: tabs[i].$1,
              icon: tabs[i].$2,
              selected: _tab == i,
              onTap: () => setState(() => _tab = i),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Resumen
  // ---------------------------------------------------------------

  Widget _summaryTab(ColorScheme scheme, FinanceTotals t, String currency) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _currentMoneyCard(scheme, t, currency),
        const SizedBox(height: 14),
        _moneyTable(scheme, t, currency),
        const SizedBox(height: 14),
        _chartCard(scheme),
        const SizedBox(height: 14),
        _recentMovementsCard(scheme, currency),
      ],
    );
  }

  /// La tarjeta grande del dinero que se tiene HOY, con la fórmula a la vista.
  Widget _currentMoneyCard(
    ColorScheme scheme,
    FinanceTotals t,
    String currency,
  ) {
    final positive = t.dineroActual >= 0;
    final tint = positive ? FinanceColors.positive : FinanceColors.red;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tint.withValues(alpha: .16), tint.withValues(alpha: .035)],
        ),
        border: Border.all(color: tint.withValues(alpha: .32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 18,
                  color: tint,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'DINERO ACTUAL',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: .8,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'HOY',
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: .5,
                    fontWeight: FontWeight.w800,
                    color: tint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              hsMoney(t.dineroActual, currency),
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -.5,
                color: tint,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Abonado + abono externo − gastos − inversión − ahorro − pagos',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MiniStat(
                label: 'Abonado',
                value: hsMoney(t.ganancias, currency),
                tint: FinanceColors.positive,
                icon: Icons.payments_outlined,
              ),
              _MiniStat(
                label: 'Por cobrar',
                value: hsMoney(t.porCobrar, currency),
                tint: FinanceColors.amber,
                icon: Icons.hourglass_bottom_rounded,
              ),
              _MiniStat(
                label: 'Pagos a personas',
                value: hsMoney(t.pagos, currency),
                tint: _kindColor('pago'),
                icon: Icons.handshake_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// La TABLA del movimiento del dinero: cada concepto con su monto y una
  /// barra proporcional (dinámica, animada al abrir la vista).
  Widget _moneyTable(ColorScheme scheme, FinanceTotals t, String currency) {
    final rows = <_MoneyRow>[
      _MoneyRow(
        label: 'Abonado',
        note: 'Cobrado a los clientes',
        amount: t.ganancias,
        icon: _kindIcon('abono'),
        tint: FinanceColors.positive,
      ),
      _MoneyRow(
        label: 'Abono externo',
        note: 'Dinero extra que entra',
        amount: t.abonoExterno,
        icon: _kindIcon('abono_externo'),
        tint: FinanceColors.blue,
      ),
      _MoneyRow(
        label: 'Gastos',
        note: 'Todos los gastos de la empresa',
        amount: t.gastos,
        icon: _kindIcon('gasto'),
        tint: FinanceColors.red,
      ),
      _MoneyRow(
        label: 'Inversión',
        note: 'Todas las inversiones de la empresa',
        amount: t.inversiones,
        icon: _kindIcon('inversion'),
        tint: FinanceColors.investment,
      ),
      _MoneyRow(
        label: 'Ahorro',
        note: 'Lo que se tiene apartado',
        amount: t.ahorro,
        icon: _kindIcon('ahorro'),
        tint: FinanceColors.teal,
      ),
      _MoneyRow(
        label: 'Pagos',
        note: 'Pagado a colaboradores y empleados',
        amount: t.pagos,
        icon: _kindIcon('pago'),
        tint: _kindColor('pago'),
        onTap: () => setState(() => _tab = 2),
      ),
      _MoneyRow(
        label: 'Por cobrar',
        note: 'Falta por cobrar de los paquetes',
        amount: t.porCobrar,
        icon: Icons.hourglass_bottom_rounded,
        tint: FinanceColors.amber,
      ),
    ];
    num top = 0;
    for (final r in rows) {
      if (r.amount.abs() > top) top = r.amount.abs();
    }
    if (top <= 0) top = 1;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.table_rows_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Movimiento del dinero',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  'Toca Pagos para el detalle',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final r in rows)
              _MoneyBarRow(
                row: r,
                currency: currency,
                share: r.amount.abs() / top,
              ),
            Divider(
              height: 18,
              color: scheme.outlineVariant.withValues(alpha: .5),
            ),
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 17,
                  color: t.dineroActual >= 0
                      ? FinanceColors.positive
                      : FinanceColors.red,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'DINERO ACTUAL',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: .6,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  hsMoney(t.dineroActual, currency),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: t.dineroActual >= 0
                        ? FinanceColors.positive
                        : FinanceColors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chartCard(ColorScheme scheme) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Últimos 6 meses',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FinanceMonthBars(months: _data.months, height: 130),
          const SizedBox(height: 12),
          const FinanceLegend(),
        ],
      ),
    ),
  );

  Widget _recentMovementsCard(ColorScheme scheme, String currency) {
    final moves = _data.movements.take(6).toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Movimientos recientes',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (moves.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Todavía no hay movimientos registrados.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final m in moves) _movementLine(scheme, m, currency),
          ],
        ),
      ),
    );
  }

  /// Una línea de movimiento: concepto, destinatario/paquete, fecha y monto.
  Widget _movementLine(ColorScheme scheme, FinanceMovement m, String currency) {
    final when = hsParseDate(m.created);
    final where = m.packageName.isEmpty
        ? m.clientName
        : (m.clientName.isEmpty
              ? m.packageName
              : '${m.packageName} · ${m.clientName}');
    final detail = [
      if (m.kind == 'pago' && m.userName.trim().isNotEmpty)
        '→ ${m.userName.trim()}',
      if (m.description.trim().isNotEmpty) m.description.trim(),
      if (where.isNotEmpty) where,
      if (when != null) hsShortDate(when),
    ].join('  ·  ');
    final color = _kindColor(m.kind);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(_kindIcon(m.kind), size: 13, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              detail.isEmpty ? _kindLabel(m.kind) : detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            hsMoney(m.amount, currency),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Por paquete
  // ---------------------------------------------------------------

  Widget _packagesTab(ColorScheme scheme, String currency) {
    final visible = _visiblePackages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _packageQuery = v),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Buscar paquete o cliente…',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_data.packages.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: EmptyState(
                icon: Icons.inventory_2_outlined,
                title: 'Sin paquetes con movimiento',
                message:
                    'Aquí aparecen los paquetes con dinero o movimientos. '
                    'Los paquetes gratis sin abonos ni gastos se omiten.',
              ),
            ),
          )
        else if (visible.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Ningún paquete coincide con la búsqueda.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, box) => box.maxWidth >= 900
                ? _packageTable(scheme, visible, currency)
                : _packageCards(scheme, visible, currency),
          ),
      ],
    );
  }

  String _packageKey(int id) => 'pkg:$id';

  Widget _packageTable(
    ColorScheme scheme,
    List<FinancePackage> rows,
    String currency,
  ) {
    const conceptW = 230.0;
    const cellW = 96.0;
    // Ancho EXACTO de la tabla: dentro del scroll horizontal el alto es
    // intrínseco y el ancho debe ser acotado (si no, `double.infinity` del
    // desglose no tendría contra qué medirse).
    const tableW = 14 + conceptW + cellW * 8 + 14;
    Widget head(String label) => SizedBox(
      width: cellW,
      child: Text(
        label,
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 9,
          letterSpacing: .3,
          fontWeight: FontWeight.w800,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableW,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                color: scheme.surfaceContainerHighest.withValues(alpha: .3),
                child: Row(
                  children: [
                    SizedBox(
                      width: conceptW,
                      child: Text(
                        'PAQUETE',
                        style: TextStyle(
                          fontSize: 9,
                          letterSpacing: .4,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    head('ABONADO'),
                    head('GASTOS'),
                    head('INVERSIÓN'),
                    head('AHORRO'),
                    head('POR COBRAR'),
                    head('EXTERNO'),
                    head('PAGOS'),
                    head('ACTUAL'),
                  ],
                ),
              ),
              for (final p in rows) _packageTableRow(scheme, p, currency),
            ],
          ),
        ),
      ),
    );
  }

  Widget _packageTableRow(
    ColorScheme scheme,
    FinancePackage p,
    String currency,
  ) {
    const conceptW = 230.0;
    const cellW = 96.0;
    final key = _packageKey(p.id);
    final open = _open.contains(key);
    Widget cell(String text, Color color) => SizedBox(
      width: cellW,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            text,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ),
    );
    return Column(
      children: [
        InkWell(
          onTap: () => _toggle(key),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Row(
              children: [
                SizedBox(
                  width: conceptW,
                  child: Row(
                    children: [
                      AnimatedRotation(
                        turns: open ? .25 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 17,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 15,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name.isEmpty ? 'Paquete' : p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              p.clientName.isEmpty ? '—' : p.clientName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                cell(
                  hsMoney(p.paid, currency),
                  p.paid > 0 ? FinanceColors.positive : scheme.onSurfaceVariant,
                ),
                cell(
                  hsMoney(p.gastos, currency),
                  p.gastos > 0 ? FinanceColors.red : scheme.onSurfaceVariant,
                ),
                cell(
                  hsMoney(p.inversiones, currency),
                  p.inversiones > 0
                      ? FinanceColors.investment
                      : scheme.onSurfaceVariant,
                ),
                cell(
                  hsMoney(p.ahorro, currency),
                  p.ahorro > 0 ? FinanceColors.teal : scheme.onSurfaceVariant,
                ),
                cell(
                  hsMoney(p.balance, currency),
                  p.balance > 0 ? FinanceColors.amber : scheme.onSurfaceVariant,
                ),
                cell(
                  hsMoney(p.abonoExterno, currency),
                  p.abonoExterno > 0
                      ? FinanceColors.blue
                      : scheme.onSurfaceVariant,
                ),
                cell(
                  hsMoney(p.pagos, currency),
                  p.pagos > 0 ? _kindColor('pago') : scheme.onSurfaceVariant,
                ),
                cell(
                  hsMoney(p.disponible, currency),
                  p.disponible >= 0
                      ? FinanceColors.positive
                      : FinanceColors.red,
                ),
              ],
            ),
          ),
        ),
        if (open)
          Container(
            width: double.infinity,
            color: scheme.surfaceContainerHighest.withValues(alpha: .22),
            padding: const EdgeInsets.fromLTRB(28, 10, 14, 14),
            child: _packageDetail(scheme, p, currency),
          ),
        Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: .35)),
      ],
    );
  }

  Widget _packageCards(
    ColorScheme scheme,
    List<FinancePackage> rows,
    String currency,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in rows) ...[
          _packageCard(scheme, p, currency),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _packageCard(ColorScheme scheme, FinancePackage p, String currency) {
    final key = _packageKey(p.id);
    final open = _open.contains(key);
    final tint = p.disponible >= 0 ? FinanceColors.positive : FinanceColors.red;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _toggle(key),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          Icons.inventory_2_outlined,
                          size: 18,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name.isEmpty ? 'Paquete' : p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              p.clientName.isEmpty ? '—' : p.clientName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            hsMoney(p.disponible, currency),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: tint,
                            ),
                          ),
                          Text(
                            'Actual',
                            style: TextStyle(
                              fontSize: 9.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      AnimatedRotation(
                        turns: open ? .25 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MiniStat(
                        label: 'Abonado',
                        value: hsMoney(p.paid, currency),
                        tint: FinanceColors.positive,
                        icon: Icons.payments_outlined,
                      ),
                      _MiniStat(
                        label: 'Gastos',
                        value: hsMoney(p.gastos, currency),
                        tint: FinanceColors.red,
                        icon: Icons.trending_down,
                      ),
                      _MiniStat(
                        label: 'Inversión',
                        value: hsMoney(p.inversiones, currency),
                        tint: FinanceColors.investment,
                        icon: Icons.trending_up,
                      ),
                      _MiniStat(
                        label: 'Ahorro',
                        value: hsMoney(p.ahorro, currency),
                        tint: FinanceColors.teal,
                        icon: Icons.savings_rounded,
                      ),
                      _MiniStat(
                        label: 'Por cobrar',
                        value: hsMoney(p.balance, currency),
                        tint: FinanceColors.amber,
                        icon: Icons.hourglass_bottom_rounded,
                      ),
                      _MiniStat(
                        label: 'Externo',
                        value: hsMoney(p.abonoExterno, currency),
                        tint: FinanceColors.blue,
                        icon: Icons.account_balance_wallet_outlined,
                      ),
                      if (p.pagos > 0)
                        _MiniStat(
                          label: 'Pagos',
                          value: hsMoney(p.pagos, currency),
                          tint: _kindColor('pago'),
                          icon: Icons.handshake_outlined,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Container(
              color: scheme.surfaceContainerHighest.withValues(alpha: .22),
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: _packageDetail(scheme, p, currency),
            ),
        ],
      ),
    );
  }

  Widget _packageDetail(ColorScheme scheme, FinancePackage p, String currency) {
    final moves = _data.movementsOf(p.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _DetailPill('Abonado', p.paid, FinanceColors.positive, currency),
            _DetailPill('Por cobrar', p.balance, FinanceColors.amber, currency),
            _DetailPill('Gastos', p.gastos, FinanceColors.red, currency),
            _DetailPill(
              'Inversión',
              p.inversiones,
              FinanceColors.investment,
              currency,
            ),
            _DetailPill('Ahorro', p.ahorro, FinanceColors.teal, currency),
            _DetailPill(
              'Abono externo',
              p.abonoExterno,
              FinanceColors.blue,
              currency,
            ),
            if (p.pagos > 0)
              _DetailPill('Pagos', p.pagos, _kindColor('pago'), currency),
            _DetailPill(
              'Dinero actual',
              p.disponible,
              p.disponible >= 0 ? FinanceColors.positive : FinanceColors.red,
              currency,
            ),
          ],
        ),
        if (_canSave) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _addMovement(kind: 'ahorro', package: p),
                icon: const Icon(Icons.savings_outlined, size: 16),
                label: const Text('Abonar al ahorro'),
              ),
              OutlinedButton.icon(
                onPressed: () => _addMovement(kind: 'gasto', package: p),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Agregar movimiento'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        if (moves.isEmpty)
          Text(
            'Sin movimientos registrados en este paquete.',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          )
        else ...[
          Text(
            'MOVIMIENTOS DEL PAQUETE',
            style: TextStyle(
              fontSize: 9.5,
              letterSpacing: .5,
              fontWeight: FontWeight.w800,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          for (final m in moves.take(6)) _movementLine(scheme, m, currency),
          if (moves.length > 6)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'y ${moves.length - 6} más…',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------
  // Pagos a personas
  // ---------------------------------------------------------------

  Widget _paymentsTab(ColorScheme scheme, String currency) {
    final payees = _data.payees;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: _kindColor('pago').withValues(alpha: .10),
            border: Border.all(
              color: _kindColor('pago').withValues(alpha: .30),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _kindColor('pago').withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.handshake_outlined,
                  size: 20,
                  color: _kindColor('pago'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TOTAL PAGADO A PERSONAS',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: .6,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        hsMoney(_data.totalPagos, currency),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: _kindColor('pago'),
                        ),
                      ),
                    ),
                    Text(
                      payees.length == 1
                          ? 'En 1 persona'
                          : 'En ${payees.length} personas',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (payees.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: EmptyState(
                icon: Icons.handshake_outlined,
                title: 'Sin pagos a personas',
                message:
                    'Cuando se reparta un pago a colaboradores o empleados '
                    'desde el paquete de un cliente, aquí verás a cada quien '
                    'con su total.',
              ),
            ),
          )
        else
          for (final p in payees) ...[
            _payeeCard(scheme, p, currency),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _payeeCard(ColorScheme scheme, FinancePayee p, String currency) {
    final key = 'payee:${p.userId}';
    final open = _open.contains(key);
    final moves = _data.paymentsOf(p.userId);
    final tint = _kindColor('pago');
    final when = hsParseDate(p.lastPaid);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: moves.isEmpty ? null : () => _toggle(key),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: tint.withValues(alpha: .16),
                    child: Text(
                      _initials(p.label),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: tint,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          [
                            if (p.roleName.trim().isNotEmpty) p.roleName.trim(),
                            '${p.count} pago${p.count == 1 ? '' : 's'}',
                            '${p.packageCount} paquete'
                                '${p.packageCount == 1 ? '' : 's'}',
                            if (when != null) 'último ${hsShortDate(when)}',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    hsMoney(p.total, currency),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: tint,
                    ),
                  ),
                  if (moves.isNotEmpty)
                    AnimatedRotation(
                      turns: open ? .25 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (open && moves.isNotEmpty)
            Container(
              width: double.infinity,
              color: scheme.surfaceContainerHighest.withValues(alpha: .22),
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'PAGOS RECIBIDOS',
                    style: TextStyle(
                      fontSize: 9.5,
                      letterSpacing: .5,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final m in moves.take(12))
                    _paymentLine(scheme, m, currency),
                  if (moves.length > 12)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'y ${moves.length - 12} más…',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _paymentLine(ColorScheme scheme, FinancePayment m, String currency) {
    final when = hsParseDate(m.created);
    final where = m.packageName.isEmpty
        ? m.clientName
        : (m.clientName.isEmpty
              ? m.packageName
              : '${m.packageName} · ${m.clientName}');
    final detail = [
      if (where.isNotEmpty) where,
      if (m.description.trim().isNotEmpty) m.description.trim(),
      if (when != null) hsShortDate(when),
    ].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.handshake_outlined, size: 13, color: _kindColor('pago')),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              detail.isEmpty ? 'Pago' : detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            hsMoney(m.amount, currency),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: _kindColor('pago'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(ColorScheme scheme) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.cloud_off_outlined, size: 40, color: scheme.error),
          const SizedBox(height: 10),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _reload,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    ),
  );
}

// ==================================================================
// Piezas de la vista
// ==================================================================

/// Pestaña (píldora) del módulo.
class _TabPill extends StatelessWidget {
  const _TabPill({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: .12)
          : scheme.surfaceContainerHighest.withValues(alpha: .35),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: .45)
                  : scheme.outlineVariant.withValues(alpha: .45),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: tint),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: tint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una fila de la tabla del dinero.
class _MoneyRow {
  const _MoneyRow({
    required this.label,
    required this.note,
    required this.amount,
    required this.icon,
    required this.tint,
    this.onTap,
  });

  final String label;
  final String note;
  final num amount;
  final IconData icon;
  final Color tint;
  final VoidCallback? onTap;
}

/// Fila con su monto y una barra proporcional animada.
class _MoneyBarRow extends StatelessWidget {
  const _MoneyBarRow({
    required this.row,
    required this.currency,
    required this.share,
  });

  final _MoneyRow row;
  final String currency;
  final double share;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(row.icon, size: 15, color: row.tint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  row.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                hsMoney(row.amount, currency),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: row.tint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: Text(
                  row.note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 5,
                    color: scheme.surfaceContainerHighest.withValues(alpha: .7),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: share.clamp(0.0, 1.0)),
                      duration: const Duration(milliseconds: 520),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: v,
                        heightFactor: 1,
                        child: Container(color: row.tint),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (row.onTap == null) return content;
    return InkWell(
      onTap: row.onTap,
      borderRadius: BorderRadius.circular(10),
      child: content,
    );
  }
}

/// Cuadro compacto de un dato (etiqueta + monto).
class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.tint,
    required this.icon,
  });

  final String label;
  final String value;
  final Color tint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: tint.withValues(alpha: .25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tint),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: tint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Píldora "Concepto monto" del desglose de un paquete.
class _DetailPill extends StatelessWidget {
  const _DetailPill(this.label, this.amount, this.tint, this.currency);

  final String label;
  final num amount;
  final Color tint;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tint.withValues(alpha: .25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            hsMoney(amount, currency),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: tint,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================================================================
// Registrar un movimiento desde Finanzas
// (gasto / inversión / ahorro / abono externo; el ahorro se puede capturar
//  como cantidad o como PORCENTAJE del dinero actual)
// ==================================================================

class _FinanceMovementDialog extends StatefulWidget {
  const _FinanceMovementDialog({
    required this.packages,
    required this.currency,
    required this.totals,
    this.initial,
    this.kind = 'gasto',
  });

  final List<FinancePackage> packages;
  final String currency;

  /// Totales del negocio: el `disponible` general es la base del ahorro en
  /// porcentaje cuando el movimiento NO se atribuye a un paquete.
  final FinanceTotals totals;
  final FinancePackage? initial;

  /// Tipo preseleccionado.
  final String kind;

  @override
  State<_FinanceMovementDialog> createState() => _FinanceMovementDialogState();
}

class _FinanceMovementDialogState extends State<_FinanceMovementDialog> {
  /// 0 = movimiento GENERAL (del negocio, sin paquete).
  late int _packageId = widget.initial?.id ?? 0;
  late String _kind = widget.kind;
  String _mode = 'monto';
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _percent = TextEditingController();
  final TextEditingController _concept = TextEditingController();
  bool _saving = false;
  String? _error;

  /// El paquete elegido, o null si el movimiento es general.
  FinancePackage? get _package {
    if (_packageId == 0) return null;
    for (final p in widget.packages) {
      if (p.id == _packageId) return p;
    }
    return null;
  }

  bool get _isSavings => _kind == 'ahorro';
  bool get _byPercent => _isSavings && _mode == 'porcentaje';

  /// Base del ahorro en porcentaje: el dinero actual del paquete elegido o,
  /// si el movimiento es general, el del negocio.
  num get _baseDisponible => _package?.disponible ?? widget.totals.dineroActual;
  bool get _baseIsGeneral => _package == null;

  num get _percentValue =>
      num.tryParse(_percent.text.replaceAll(',', '').trim()) ?? 0;

  /// Monto final: el capturado o el porcentaje aplicado al disponible.
  num get _resolved {
    if (!_byPercent) {
      return num.tryParse(_amount.text.replaceAll(',', '').trim()) ?? 0;
    }
    final value = _baseDisponible * _percentValue / 100;
    return (value * 100).roundToDouble() / 100;
  }

  static String _clean(num v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _amount.dispose();
    _percent.dispose();
    _concept.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final amount = _resolved;
    if (amount <= 0) {
      setState(
        () => _error = _byPercent
            ? 'El porcentaje debe dar un monto mayor a 0'
            : 'Escribe un monto mayor a 0',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final note = _concept.text.trim();
    final description = _byPercent
        ? [
            if (note.isNotEmpty) note,
            '${_clean(_percentValue)} % del disponible',
          ].join(' · ')
        : note;
    try {
      await HsApi.addFinanceMovement(
        purchasedPackageId: _packageId == 0 ? null : _packageId,
        kind: _kind,
        amount: amount,
        description: description,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _saving = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo registrar el movimiento';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _kindColor(_kind);
    final amount = _resolved;
    return FormDialog(
      icon: _kindIcon(_kind),
      title: _isSavings ? 'Abonar al ahorro' : 'Registrar movimiento',
      subtitle: _baseIsGeneral
          ? 'Movimiento GENERAL del negocio (no toca ningún paquete)'
          : 'Se registra en el paquete elegido y actualiza sus totales',
      saving: _saving,
      error: _error,
      saveLabel: _isSavings ? 'Abonar' : 'Registrar',
      maxWidth: 470,
      onCancel: () => Navigator.of(context).pop(false),
      onSave: _save,
      children: [
        FormSection(
          label: 'Paquete (opcional)',
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: '¿A qué pertenece?',
              prefixIcon: Icon(Icons.storefront_outlined, size: 20),
              helperText: 'Déjalo en "General" para no atribuirlo a un paquete',
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                isExpanded: true,
                isDense: true,
                value: _packageId,
                items: [
                  const DropdownMenuItem(
                    value: 0,
                    child: Text(
                      'General (todo el negocio)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  for (final p in widget.packages)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(
                        p.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                        if (v != null) _packageId = v;
                      }),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        FormSection(
          label: 'Tipo de movimiento',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final kind in _kEditableKinds)
                ChoiceChip(
                  label: Text(_kindLabel(kind)),
                  avatar: Icon(
                    _kindIcon(kind),
                    size: 15,
                    color: _kindColor(kind),
                  ),
                  selected: _kind == kind,
                  onSelected: _saving
                      ? null
                      : (_) => setState(() {
                          _kind = kind;
                          if (!_isSavings) _mode = 'monto';
                        }),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: .30)),
          ),
          child: Row(
            children: [
              Icon(
                _baseIsGeneral
                    ? Icons.storefront_outlined
                    : Icons.account_balance_wallet_outlined,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _baseIsGeneral
                      ? 'Dinero actual del negocio (abonado + externo − gastos '
                            '− inversión − ahorro − pagos)'
                      : 'Dinero actual del paquete',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                hsMoney(_baseDisponible, widget.currency),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        if (_isSavings) ...[
          const SizedBox(height: 12),
          FormSection(
            label: _baseIsGeneral
                ? '¿Cómo se captura el ahorro del negocio?'
                : '¿Cómo se captura el ahorro?',
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment(
                  value: 'monto',
                  icon: Icon(Icons.attach_money, size: 16),
                  label: Text('Cantidad'),
                ),
                ButtonSegment(
                  value: 'porcentaje',
                  icon: Icon(Icons.percent, size: 16),
                  label: Text('Porcentaje'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _saving
                  ? null
                  : (s) => setState(() => _mode = s.first),
            ),
          ),
        ],
        const SizedBox(height: 14),
        if (_byPercent) ...[
          FormSection(
            label: _baseIsGeneral
                ? 'Porcentaje del dinero actual general'
                : 'Porcentaje del dinero actual',
            child: TextField(
              controller: _percent,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Porcentaje',
                suffixText: '%',
                prefixIcon: Icon(Icons.percent, size: 20),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.calculate_outlined, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _baseIsGeneral
                        ? 'Se ahorrarán del negocio'
                        : 'Se ahorrarán',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  hsMoney(amount, widget.currency),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ] else
          FormSection(
            label: 'Monto',
            child: TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Monto',
                prefixIcon: Icon(Icons.attach_money, size: 20),
              ),
            ),
          ),
        const SizedBox(height: 14),
        FormSection(
          label: 'Concepto',
          child: TextField(
            controller: _concept,
            minLines: 2,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Descripción',
              hintText: 'Ej. Renta del estudio, pago de proveedor…',
              alignLabelWithHint: true,
            ),
          ),
        ),
      ],
    );
  }
}

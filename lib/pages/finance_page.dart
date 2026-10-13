import 'package:flutter/material.dart';

import '../finance_data.dart';
import '../hs_access.dart';
import '../hs_api.dart';
import '../hs_format.dart';
import '../widgets/anim.dart';
import '../widgets/common.dart';
import '../widgets/finance_chart.dart';
import '../widgets/form_dialog.dart';

/// Módulo FINANZAS: todo lo monetario del negocio en un solo lugar.
///
/// - **Ganancias** (abonos cobrados), **por cobrar**, **disponible**,
///   **inversiones**, **gastos** y **abono externo**.
/// - **Ahorro**: el total apartado y, sobre todo, la acción de **abonar al
///   ahorro** de un paquete (por cantidad o por porcentaje del disponible).
/// - **Gráfica** de los últimos meses: lo que entró contra lo que salió.
/// - **Por paquete**: el dinero de cada paquete activo, con su cliente.
class FinancePage extends StatefulWidget {
  const FinancePage({super.key});

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  bool _loading = true;
  String? _error;
  FinanceData _data = const FinanceData();

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

  /// Abre el diálogo para destinar dinero al AHORRO de un paquete.
  Future<void> _addSavings({FinancePackage? package}) async {
    if (_data.packages.isEmpty) {
      _snack('Todavía no hay paquetes activos para ahorrar');
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SavingsDialog(
        packages: _data.packages,
        currency: _data.currency,
        initial: package,
      ),
    );
    if (saved == true) await _reload();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = _data.totals;
    final currency = _data.currency;

    return PageContainer(
      title: 'Finanzas',
      description: 'Ganancias, inversiones, gastos y ahorro de todos los '
          'paquetes, con su gráfica por mes.',
      icon: Icons.account_balance_wallet_outlined,
      stats: [
        StatPill(
            icon: Icons.trending_up_rounded,
            label: 'Ganado ${hsMoney(t.ganancias, currency)}'),
        StatPill(
            icon: Icons.savings_outlined,
            label: 'Ahorro ${hsMoney(t.ahorro, currency)}'),
        StatPill(
            icon: Icons.trending_down_rounded,
            label: 'Gastado ${hsMoney(t.gastado, currency)}'),
      ],
      actions: [
        if (_canSave)
          FilledButton.icon(
            onPressed: () => _addSavings(),
            icon: const Icon(Icons.savings_outlined, size: 18),
            label: const Text('Abonar al ahorro'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading)
            const ListSkeleton(lines: 4, cardHeight: 92)
          else if (_error != null)
            _errorCard(scheme)
          else ..._content(scheme, t, currency),
        ],
      ),
    );
  }

  List<Widget> _content(ColorScheme scheme, FinanceTotals t, String currency) {
    final packages = _data.packages;
    return [
      const _Header(
          icon: Icons.account_balance_outlined, label: 'Resumen del dinero'),
      const SizedBox(height: 10),
      FinanceKpiGrid(
        currency: currency,
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
            note: 'Saldo de ${hsMoney(t.facturado, currency)}',
          ),
          FinanceKpi(
            label: 'Disponible',
            amount: t.disponible,
            icon: Icons.savings_outlined,
            tint: FinanceColors.green,
            note: 'Ganado - gastado',
          ),
          FinanceKpi(
            label: 'Ahorro',
            amount: t.ahorro,
            icon: Icons.lock_outline_rounded,
            tint: FinanceColors.teal,
            note: 'Apartado',
          ),
          FinanceKpi(
            label: 'Inversiones',
            amount: t.inversiones,
            icon: Icons.trending_up,
            tint: FinanceColors.violet,
          ),
          FinanceKpi(
            label: 'Gastos',
            amount: t.gastos,
            icon: Icons.trending_down,
            tint: FinanceColors.red,
          ),
          FinanceKpi(
            label: 'Abono externo',
            amount: t.abonoExterno,
            icon: Icons.account_balance_wallet_outlined,
            tint: FinanceColors.blue,
          ),
        ],
      ),
      const SizedBox(height: 22),
      const _Header(icon: Icons.bar_chart_rounded, label: 'Últimos 6 meses'),
      const SizedBox(height: 10),
      FadeSlideIn(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FinanceMonthBars(months: _data.months),
                const SizedBox(height: 14),
                const FinanceLegend(),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 22),
      const _Header(icon: Icons.savings_rounded, label: 'Ahorro'),
      const SizedBox(height: 10),
      _savingsCard(scheme, t, currency, packages),
      const SizedBox(height: 22),
      const _Header(icon: Icons.inventory_2_outlined, label: 'Por paquete'),
      const SizedBox(height: 10),
      if (packages.isEmpty)
        const EmptyState(
          icon: Icons.inventory_2_outlined,
          title: 'Sin paquetes activos',
          message: 'Cuando un cliente compre un paquete, aquí verás su dinero: '
              'abonos, disponible, ahorro, gastos e inversiones.',
        )
      else
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < packages.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, color: Theme.of(context).dividerColor),
                StaggeredItem(
                  index: i,
                  child: _PackageMoneyRow(
                    package: packages[i],
                    currency: currency,
                    onSave: _canSave
                        ? () => _addSavings(package: packages[i])
                        : null,
                  ),
                ),
              ],
            ],
          ),
        ),
    ];
  }

  /// Tarjeta del AHORRO: total + acción principal + cómo se calcula.
  Widget _savingsCard(
    ColorScheme scheme,
    FinanceTotals t,
    String currency,
    List<FinancePackage> packages,
  ) {
    const teal = FinanceColors.teal;
    final conAhorro = packages.where((p) => p.ahorro > 0).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: teal.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.savings_rounded, color: teal),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ahorro apartado',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                      Text(
                        hsMoney(t.ahorro, currency),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: teal,
                        ),
                      ),
                      Text(
                        conAhorro == 1
                            ? 'En 1 paquete'
                            : 'En $conAhorro paquetes',
                        style: TextStyle(
                            fontSize: 11.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (_canSave)
                  FilledButton.tonalIcon(
                    onPressed: () => _addSavings(),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Abonar'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: teal.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: teal.withValues(alpha: .25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 15, color: teal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'El ahorro se toma del DISPONIBLE del paquete '
                      '(abonado - gastado) y puedes capturarlo como cantidad '
                      'o como porcentaje.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: scheme.onSurfaceVariant,
                      ),
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

/// Encabezado de sección del módulo.
class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

/// Fila del dinero de UN paquete: cliente/paquete arriba y, abajo, los montos
/// en píldoras horizontales que se envuelven si no caben.
class _PackageMoneyRow extends StatelessWidget {
  const _PackageMoneyRow({
    required this.package,
    required this.currency,
    this.onSave,
  });

  final FinancePackage package;
  final String currency;

  /// null = sin permiso para abonar al ahorro.
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = package.name.isEmpty ? 'Paquete' : package.name;
    final client = package.clientName;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.inventory_2_outlined,
                size: 19, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
                if (client.isNotEmpty)
                  Text(
                    client,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5, color: scheme.onSurfaceVariant),
                  ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Pill('Ganado', package.paid, FinanceColors.green, currency),
                    _Pill('Por cobrar', package.balance, FinanceColors.amber,
                        currency),
                    _Pill('Disponible', package.disponible,
                        FinanceColors.green, currency),
                    _Pill('Ahorro', package.ahorro, FinanceColors.teal,
                        currency),
                    _Pill('Gastos', package.gastos, FinanceColors.red, currency),
                    _Pill('Inversión', package.inversiones,
                        FinanceColors.violet, currency),
                  ],
                ),
              ],
            ),
          ),
          if (onSave != null)
            IconButton(
              tooltip: 'Abonar al ahorro',
              onPressed: onSave,
              icon: const Icon(Icons.savings_outlined, size: 20),
            ),
        ],
      ),
    );
  }
}

/// Píldora "Etiqueta monto" de un paquete.
class _Pill extends StatelessWidget {
  const _Pill(this.label, this.amount, this.tint, this.currency);

  final String label;
  final num amount;
  final Color tint;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tint.withValues(alpha: .22)),
      ),
      // Flexible + ellipsis: la píldora se encoge dentro de su línea en vez
      // de desbordar cuando el panel es angosto.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              '$label ',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
// Abonar al AHORRO de un paquete (cantidad o porcentaje del disponible)
// ==================================================================

class _SavingsDialog extends StatefulWidget {
  const _SavingsDialog({
    required this.packages,
    required this.currency,
    this.initial,
  });

  final List<FinancePackage> packages;
  final String currency;
  final FinancePackage? initial;

  @override
  State<_SavingsDialog> createState() => _SavingsDialogState();
}

class _SavingsDialogState extends State<_SavingsDialog> {
  late int _packageId = widget.initial?.id ?? widget.packages.first.id;
  String _mode = 'monto';
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _percent = TextEditingController();
  final TextEditingController _concept = TextEditingController();
  bool _saving = false;
  String? _error;

  FinancePackage get _package =>
      widget.packages.firstWhere((p) => p.id == _packageId,
          orElse: () => widget.packages.first);

  num get _percentValue =>
      num.tryParse(_percent.text.replaceAll(',', '').trim()) ?? 0;

  /// Monto final: el capturado o el porcentaje aplicado al disponible.
  num get _resolved {
    if (_mode != 'porcentaje') {
      return num.tryParse(_amount.text.replaceAll(',', '').trim()) ?? 0;
    }
    final value = _package.disponible * _percentValue / 100;
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
      setState(() => _error = _mode == 'porcentaje'
          ? 'El porcentaje debe dar un monto mayor a 0'
          : 'Escribe un monto mayor a 0');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final note = _concept.text.trim();
    final description = _mode == 'porcentaje'
        ? [
            if (note.isNotEmpty) note,
            '${_clean(_percentValue)} % del disponible',
          ].join(' · ')
        : note;
    try {
      await HsApi.addSavings(
        purchasedPackageId: _packageId,
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
          _error = 'No se pudo abonar al ahorro';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pkg = _package;
    const teal = FinanceColors.teal;
    final amount = _resolved;
    return FormDialog(
      icon: Icons.savings_rounded,
      title: 'Abonar al ahorro',
      subtitle: 'Se aparta del disponible del paquete',
      saving: _saving,
      error: _error,
      saveLabel: 'Abonar',
      maxWidth: 470,
      onCancel: () => Navigator.of(context).pop(false),
      onSave: _save,
      children: [
        FormSection(
          label: 'Paquete',
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Paquete',
              prefixIcon: Icon(Icons.inventory_2_outlined, size: 20),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                isExpanded: true,
                isDense: true,
                value: _packageId,
                items: [
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
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: teal.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: teal.withValues(alpha: .30)),
          ),
          child: Row(
            children: [
              const Icon(Icons.savings_outlined, size: 16, color: teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Disponible del paquete (abonado - gastado)',
                  style:
                      TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
              ),
              Text(
                hsMoney(pkg.disponible, widget.currency),
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w800, color: teal),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FormSection(
          label: '¿Cómo se captura el ahorro?',
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
            onSelectionChanged:
                _saving ? null : (s) => setState(() => _mode = s.first),
          ),
        ),
        const SizedBox(height: 14),
        if (_mode == 'porcentaje') ...[
          FormSection(
            label: 'Porcentaje del disponible',
            child: TextField(
              controller: _percent,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
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
              color: teal.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.calculate_outlined, size: 16, color: teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Se ahorrarán',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ),
                Text(
                  hsMoney(amount, widget.currency),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800, color: teal),
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
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
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
              hintText: 'Ej. Ahorro del mes, fondo de equipo…',
              alignLabelWithHint: true,
            ),
          ),
        ),
      ],
    );
  }
}

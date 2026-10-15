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
// Todo el dinero del negocio en UNA pantalla bien distribuida:
//   * Arriba, la tira de totales (cuadros horizontales).
//   * Abajo, la TABLA con el dinero de cada paquete y de cada tipo de
//     movimiento. La página NO hace scroll: en escritorio la tabla y la
//     gráfica van en dos columnas y solo la tabla scrollea por dentro; en
//     pantallas angostas todo vive en una sola zona con scroll propio.
//
// La tabla expande cada fila:
//   * Paquete    → su resumen (cobrado, por cobrar, ganado, ahorro, gastos,
//                  inversión, abono externo), sus movimientos y sus acciones.
//   * Movimiento → se desglosa según su tipo, registro por registro.
//
// "Ganado" es el DISPONIBLE de los datos (abonado - gastado - ahorro +
// abono externo): es el dinero que de verdad queda.
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
      'abono' => FinanceColors.green,
      'abono_externo' => FinanceColors.blue,
      'inversion' => FinanceColors.violet,
      'ahorro' => FinanceColors.teal,
      'pago' => FinanceColors.amber,
      _ => FinanceColors.red,
    };

/// Tipos de movimiento que se listan como filas de la tabla (en orden).
/// Los PAGOS van al final y con la etiqueta que aclara que son un registro:
/// no se descuentan del paquete.
const List<String> _kKindRows = [
  'abono',
  'gasto',
  'inversion',
  'ahorro',
  'abono_externo',
  'pago',
];

/// Fila especial de la tabla: los movimientos del NEGOCIO (sin paquete).
const String _kGeneralRow = 'general';

/// Alto MÍNIMO que necesita la tarjeta de la tabla (encabezado + una fila)
/// para no recortarse. Por debajo de esto la vista de escritorio deja de usar
/// las dos columnas: en una ventana baja el bloque de totales se comía el
/// espacio y la tabla desbordaba la pantalla.
const double _kTableMinHeight = 210;

/// Alto aproximado que ocupa el bloque del resumen del dinero (todos los
/// cuadros en una lista vertical). Se usa para decidir si el resumen y la
/// tabla CABEN juntos en la ventana; si no, todo baja a una zona con scroll.
/// Es a propósito algo holgado: en una ventana mediana es preferible
/// desplazar un poco a que algo se recorte.
const double _kSummaryHeight = 420;

class FinancePage extends StatefulWidget {
  const FinancePage({super.key});

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  bool _loading = true;
  String? _error;
  FinanceData _data = const FinanceData();

  /// Claves de las filas EXPANDIDAS de la tabla ('pkg:10', 'kind:gasto'…).
  final Set<String> _open = <String>{};

  /// Móvil: los cuadros de totales se pueden MINIMIZAR para dejarle la
  /// pantalla a la tabla de "Dinero por paquete y movimiento".
  bool _kpisOpen = true;

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

  /// Abre el diálogo para REGISTRAR un movimiento.
  ///
  /// SIN [package] el movimiento es GENERAL (del negocio): el módulo ya no
  /// obliga a elegir un paquete. El paquete solo se elige si se quiere
  /// atribuir el gasto/ahorro a un paquete del cliente.
  Future<void> _addMovement({
    FinancePackage? package,
    String kind = 'ahorro',
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FinanceMovementDialog(
        packages: _data.packages,
        currency: _data.currency,
        totals: _data.totals,
        initial: package,
        kind: kind,
      ),
    );
    if (saved == true) {
      _snack(package == null
          ? 'Movimiento general registrado'
          : 'Movimiento registrado en ${package.name}');
      await _reload();
    }
  }

  /// Aviso neutro de la interfaz (el éxito/error lo avisa la capa de API
  /// con el mensaje del backend).
  void _snack(String msg) => HsToast.info(msg);

  /// Píldoras de detalle en UNA sola fila, deslizable de lado. En el teléfono
  /// el [Wrap] las apilaba en tres renglones y se comía el espacio de la
  /// información; así todo el desglose vive en un renglón.
  Widget _pillsRow(List<Widget> pills) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 2),
        child: Row(
          children: [
            for (final p in pills) ...[
              p,
              const SizedBox(width: 8),
            ],
          ],
        ),
      );

  /// Botones de acción del desglose, también en UNA fila (se desliza si no
  /// caben) en vez de apilarse uno por renglón.
  Widget _buttonsRow(List<Widget> buttons) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 2),
        child: Row(
          children: [
            for (final b in buttons) ...[
              b,
              const SizedBox(width: 8),
            ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = _data.totals;
    final currency = _data.currency;
    // En el teléfono la descripción larga del héroe se come media pantalla:
    // ahí va una más corta para que el dinero empiece antes.
    final narrow = MediaQuery.sizeOf(context).width < 620;

    return PageContainer(
      title: 'Finanzas',
      description: narrow
          ? 'Cada paquete y cada movimiento, con su desglose.'
          : 'El dinero en una tabla: cada paquete y cada tipo de '
              'movimiento, con su desglose al expandir.',
      icon: Icons.account_balance_wallet_outlined,
      // Sin scroll de página: la tabla scrollea por dentro.
      expand: true,
      // En el teléfono los dos botones van en UNA fila (se desliza si no
      // caben): apilados se comían el alto de la tabla.
      actionsInline: true,
      stats: [
        StatPill(
            icon: Icons.savings_outlined,
            label: 'Ganado ${hsMoney(t.disponible, currency)}'),
        StatPill(
            icon: Icons.lock_outline_rounded,
            label: 'Ahorro ${hsMoney(t.ahorro, currency)}'),
        StatPill(
            icon: Icons.trending_down_rounded,
            label: 'Salidas ${hsMoney(t.gastado, currency)}'),
      ],
      actions: [
        if (_canSave) ...[
          // Son DOS acciones distintas y no se mezclan: el movimiento
          // (gasto/inversión/abono externo/ahorro general) va como acción
          // principal y aparte, con su propio color, el ahorro.
          HsActionButton(
            onPressed: () => _addMovement(kind: 'gasto'),
            icon: Icons.add,
            // En el teléfono la etiqueta completa no cabe en el botón y
            // quedaba a medias: ahí va la versión corta.
            label: narrow ? 'Nuevo movimiento' : 'Agregar movimiento',
          ),
          HsActionButton(
            primary: false,
            tint: FinanceColors.teal,
            onPressed: () => _addMovement(kind: 'ahorro'),
            icon: Icons.savings_outlined,
            label: 'Abonar al ahorro',
          ),
        ],
      ],
      child: _body(Theme.of(context).colorScheme, t, currency),
    );
  }

  // ---------------------------------------------------------------
  // Cuerpo
  // ---------------------------------------------------------------

  Widget _body(ColorScheme scheme, FinanceTotals t, String currency) {
    if (_loading) return const ListSkeleton(lines: 3, cardHeight: 104);
    if (_error != null) return _errorCard(scheme);
    // Mismo umbral del héroe: en el teléfono el resumen va apilado.
    final narrow = MediaQuery.sizeOf(context).width < 620;

    // MÓVIL: TODO en una sola zona con scroll —el resumen del dinero ARRIBA,
    // junto con la tabla— para poder bajar y ver más información. El bloque
    // se puede MINIMIZAR con el botón del encabezado.
    if (narrow) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _kpiHeader(scheme, t),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _kpisOpen
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      // Los grupos se apilan (una columna): en el teléfono es lo
                      // único que deja leer las etiquetas completas.
                      child: _MoneySummary(
                        totals: t,
                        currency: currency,
                        showNotes: false,
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            _tableCard(scheme, currency, inline: true),
            const SizedBox(height: 14),
            _chartCard(scheme),
            const SizedBox(height: 14),
            _savingsCard(scheme, t, currency),
          ],
        ),
      );
    }

    // ESCRITORIO: el resumen del dinero TAMBIÉN se puede minimizar. Es un
    // bloque alto (los cuatro grupos en fila) y cuando se está trabajando con
    // la tabla de abajo estorba: minimizado, el encabezado queda en UNA línea
    // y la tabla y la gráfica se reparten toda la pantalla.
    // ESCRITORIO: el resumen del dinero TAMBIÉN se puede minimizar. Es un
    // bloque alto (los cuatro grupos en fila) y cuando se está trabajando con
    // la tabla de abajo estorba: minimizado, el encabezado queda en UNA línea
    // y la tabla y la gráfica se reparten toda la pantalla.
    //
    // El reparto se decide por el ALTO disponible, no solo por el ancho: los
    // bloques de arriba (encabezado + resumen) tienen alto propio y, si no
    // caben junto con la tabla, todo baja a UNA zona con scroll en vez de
    // recortarse.
    return LayoutBuilder(builder: (context, box) {
      const header = 48.0; // encabezado del resumen + su separación
      final summary = _kpisOpen ? _kSummaryHeight : 0.0;
      final caben = box.maxWidth >= 980 &&
          box.maxHeight >= header + summary + _kTableMinHeight;

      // Resumen arriba: encabezado + (si está abierto) los cuatro grupos.
      final top = <Widget>[
        _kpiHeader(scheme, t, showEarned: false),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _kpisOpen
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _MoneySummary(totals: t, currency: currency),
                )
              : const SizedBox(width: double.infinity),
        ),
      ];

      // Cabe: el resumen queda fijo arriba y abajo la tabla | gráfica + ahorro
      // se reparten el resto del alto (sin scroll de página).
      if (caben) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...top,
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 3, child: _tableCard(scheme, currency)),
                  const SizedBox(width: 14),
                  Expanded(flex: 2, child: _sideColumn(scheme, t, currency)),
                ],
              ),
            ),
          ],
        );
      }

      // Angosto o bajo: todo en UNA zona con scroll (la página no crece y cada
      // pieza conserva su espacio; nada se recorta).
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...top,
            _tableCard(scheme, currency, inline: true),
            const SizedBox(height: 14),
            _chartCard(scheme),
            const SizedBox(height: 14),
            _savingsCard(scheme, t, currency),
          ],
        ),
      );
    });
  }

  /// Encabezado del bloque de cuadros: título + botón para minimizar/mostrar
  /// (así la tabla gana toda la pantalla cuando se quiere trabajar con ella).
  ///
  /// Se usa en móvil y en escritorio. En escritorio el "Ganado" del extremo
  /// se omite ([showEarned] = false): ese número ya va en la píldora de la
  /// cabecera y repetirlo sería ruido.
  Widget _kpiHeader(ColorScheme scheme, FinanceTotals t,
      {bool showEarned = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet_outlined,
              size: 16, color: scheme.primary),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Resumen del dinero',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_kpisOpen && showEarned)
            Text(
              'Ganado ${hsMoney(t.disponible)}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: FinanceColors.green,
              ),
            ),
          const SizedBox(width: 4),
          Tooltip(
            message: _kpisOpen ? 'Minimizar los cuadros' : 'Mostrar los cuadros',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _kpisOpen = !_kpisOpen),
              icon: AnimatedRotation(
                turns: _kpisOpen ? 0 : .5,
                duration: const Duration(milliseconds: 180),
                child: Icon(Icons.keyboard_arrow_up_rounded,
                    size: 20, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Columna lateral (escritorio): la gráfica por mes y el ahorro.
  Widget _sideColumn(ColorScheme scheme, FinanceTotals t, String currency) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _chartCard(scheme),
          const SizedBox(height: 14),
          _savingsCard(scheme, t, currency),
        ],
      ),
    );
  }

  Widget _chartCard(ColorScheme scheme) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.bar_chart_rounded,
                      size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Últimos 6 meses',
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FinanceMonthBars(months: _data.months, height: 120),
              const SizedBox(height: 12),
              const FinanceLegend(),
            ],
          ),
        ),
      );

  /// Tarjeta del AHORRO: su total y el botón para apartar más.
  /// En pantallas angostas el botón baja a su propia línea: así el monto no
  /// se queda con 100 px y termina partido en dos renglones.
  Widget _savingsCard(ColorScheme scheme, FinanceTotals t, String currency) {
    const teal = FinanceColors.teal;
    final conAhorro = _data.packages.where((p) => p.ahorro > 0).length;
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ahorro apartado',
          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
        ),
        Text(
          hsMoney(t.ahorro, currency),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: teal,
          ),
        ),
        Text(
          conAhorro == 1 ? 'En 1 paquete' : 'En $conAhorro paquetes',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
    );
    final button = _canSave
        ? FilledButton.tonalIcon(
            onPressed: () => _addMovement(kind: 'ahorro'),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Abonar'),
          )
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(builder: (context, box) {
          final header = Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: teal.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.savings_rounded, color: teal, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: texts),
            ],
          );
          if (button != null && box.maxWidth < 480) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                header,
                const SizedBox(height: 12),
                button,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: header),
              if (button != null) ...[
                const SizedBox(width: 12),
                button,
              ],
            ],
          );
        }),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Tabla
  // ---------------------------------------------------------------

  /// La tarjeta de la tabla. [inline] = sin lista propia (la usa la vista
  /// angosta, que mete todo en una sola zona con scroll).
  Widget _tableCard(ColorScheme scheme, String currency,
      {bool inline = false}) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 620;
          final head = <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Row(
                children: [
                  Icon(Icons.table_chart_outlined,
                      size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Dinero por paquete y movimiento',
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(
                'Toca una fila para desglosarla. El "Ganado" de cada paquete '
                'es su disponible.',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ),
            Divider(height: 1, color: Theme.of(context).dividerColor),
            _headRow(scheme, wide),
            Divider(height: 1, color: Theme.of(context).dividerColor),
          ];
          final rows = _tableRows(scheme, wide, currency);
          if (inline) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [...head, ...rows],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...head,
              // Scroll NO vago: se construyen todas las filas aunque la
              // tarjeta tenga poco alto (así el desglose y las acciones de
              // cada fila están listos al alcanzarlas con el scroll).
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: rows,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _tableRows(ColorScheme scheme, bool wide, String currency) => [
        _groupHead(scheme, 'PAQUETES', Icons.inventory_2_outlined),
        if (_data.packages.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              'Todavía no hay paquetes activos.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          )
        else
          for (final p in _data.packages)
            _packageRow(scheme, p, wide, currency),
        const SizedBox(height: 6),
        _groupHead(scheme, 'MOVIMIENTOS', Icons.receipt_long_outlined),
        // El dinero del negocio (sin paquete) va PRIMERO y aparte: es el que
        // se registra con "Agregar movimiento" sin elegir paquete.
        if (_data.generalMovements.isNotEmpty || !_data.general.isEmpty)
          _generalRow(scheme, wide, currency),
        for (final kind in _kKindRows) _kindRow(scheme, kind, wide, currency),
        const SizedBox(height: 8),
      ];

  /// Fila de los movimientos GENERALES (sin paquete): el dinero del negocio
  /// que no se atribuye a ningún paquete del cliente.
  Widget _generalRow(ColorScheme scheme, bool wide, String currency) {
    const key = 'kind:$_kGeneralRow';
    final open = _open.contains(key);
    final g = _data.general;
    final moves = _data.generalMovements;
    final neto = g.neto;
    final color = neto < 0 ? FinanceColors.red : FinanceColors.green;
    return Column(
      children: [
        InkWell(
          onTap: () => _toggle(key),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 0, 7),
            child: Row(
              children: [
                Expanded(
                  flex: wide ? 5 : 7,
                  child: Row(
                    children: [
                      AnimatedRotation(
                        turns: open ? .25 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(Icons.chevron_right_rounded,
                            size: 18, color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.storefront_outlined,
                          size: 16, color: FinanceColors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'General (sin paquete)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: wide ? 12.5 : 12,
                                  fontWeight: FontWeight.w700),
                            ),
                            Text(
                              moves.isEmpty
                                  ? 'Movimientos del negocio'
                                  : '${moves.length} movimiento'
                                      '${moves.length == 1 ? '' : 's'} del negocio',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _amountCell(
                  neto < 0
                      ? '−${hsMoney(neto.abs(), currency)}'
                      : hsMoney(neto, currency),
                  color,
                ),
                if (wide)
                  _amountCell(
                    g.ahorro > 0
                        ? hsMoney(g.ahorro, currency)
                        : '—',
                    g.ahorro > 0
                        ? FinanceColors.teal
                        : scheme.onSurfaceVariant,
                  ),
                if (wide)
                  _amountCell(
                    g.salidas > 0
                        ? hsMoney(g.salidas, currency)
                        : '—',
                    g.salidas > 0 ? FinanceColors.red : scheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
        if (open)
          Container(
            width: double.infinity,
            color: scheme.surfaceContainerHighest.withValues(alpha: .22),
            padding: const EdgeInsets.fromLTRB(34, 10, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _pillsRow([
                  _DetailPill('Gastos', g.gastos, FinanceColors.red, currency),
                  _DetailPill('Inversión', g.inversiones, FinanceColors.violet,
                      currency),
                  _DetailPill('Ahorro', g.ahorro, FinanceColors.teal, currency),
                  _DetailPill('Abono externo', g.abonoExterno,
                      FinanceColors.blue, currency),
                ]),
                if (_canSave) ...[
                  const SizedBox(height: 10),
                  _buttonsRow([
                      FilledButton.icon(
                        onPressed: () => _addMovement(kind: 'gasto'),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Agregar movimiento general'),
                      ),
                  ]),
                ],
                const SizedBox(height: 10),
                if (moves.isEmpty)
                  Text(
                    'Sin movimientos generales registrados.',
                    style:
                        TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                  )
                else
                  for (final m in moves.take(8))
                    _movementLine(scheme, m, currency),
              ],
            ),
          ),
        Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: .35)),
      ],
    );
  }

  /// Cabecera de columnas. Los anchos (flex) coinciden con [_packageRow] y
  /// [_kindRow]: en la vista ANGOSTA solo hay dos columnas (concepto y
  /// monto), así que las salidas viajan dentro del renglón y todo se alinea.
  Widget _headRow(ColorScheme scheme, bool wide) {
    final conceptFlex = wide ? 5 : 7;
    Widget head(String label, int flex) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              label.toUpperCase(),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                letterSpacing: .4,
                fontWeight: FontWeight.w800,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 7, 0, 7),
      child: Row(
        children: [
          Expanded(
            flex: conceptFlex,
            child: Text(
              'CONCEPTO',
              style: TextStyle(
                fontSize: 9.5,
                letterSpacing: .4,
                fontWeight: FontWeight.w800,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          head('Monto', 3),
          if (wide) head('Ahorro', 3),
          if (wide) head('Salidas', 3),
        ],
      ),
    );
  }

  /// Separador de grupo dentro de la tabla.
  Widget _groupHead(ColorScheme scheme, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Row(
        children: [
          Icon(icon, size: 13, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              letterSpacing: .7,
              fontWeight: FontWeight.w800,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(color: scheme.outlineVariant.withValues(alpha: .5)),
          ),
        ],
      ),
    );
  }

  /// Fila de UN paquete (se expande para ver su desglose).
  Widget _packageRow(
      ColorScheme scheme, FinancePackage p, bool wide, String currency) {
    final key = 'pkg:${p.id}';
    final open = _open.contains(key);
    return Column(
      children: [
        InkWell(
          onTap: () => _toggle(key),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 0, 7),
            child: Row(
              children: [
                Expanded(
                  flex: wide ? 5 : 7,
                  child: Row(
                    children: [
                      AnimatedRotation(
                        turns: open ? .25 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(Icons.chevron_right_rounded,
                            size: 18, color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.inventory_2_outlined,
                          size: 16, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name.isEmpty ? 'Paquete' : p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: wide ? 12.5 : 12,
                                  fontWeight: FontWeight.w700),
                            ),
                            Text(
                              p.clientName.isEmpty ? '—' : p.clientName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // GANADO = el disponible del paquete.
                _amountCell(
                    hsMoney(p.disponible, currency), FinanceColors.green),
                if (wide)
                  _amountCell(
                      hsMoney(p.ahorro, currency), FinanceColors.teal),
                if (wide)
                  _amountCell(hsMoney(p.salidas, currency), FinanceColors.red),
              ],
            ),
          ),
        ),
        if (open)
          Container(
            width: double.infinity,
            color: scheme.surfaceContainerHighest.withValues(alpha: .22),
            padding: const EdgeInsets.fromLTRB(34, 10, 14, 14),
            child: _packageDetail(scheme, p, currency),
          ),
        Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: .35)),
      ],
    );
  }

  /// Desglose de UN paquete: su dinero por concepto, sus movimientos y sus
  /// acciones.
  Widget _packageDetail(ColorScheme scheme, FinancePackage p, String currency) {
    final moves = _data.movementsOf(p.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Los detalles van en UNA fila que se desliza: en el teléfono ya no
        // roban media pantalla en tres renglones.
        _pillsRow([
          _DetailPill('Cobrado', p.paid, FinanceColors.green, currency),
          _DetailPill('Por cobrar', p.balance, FinanceColors.amber, currency),
          _DetailPill('Ganado (disponible)', p.disponible,
              FinanceColors.green, currency),
          _DetailPill('Ahorro', p.ahorro, FinanceColors.teal, currency),
          _DetailPill('Gastos', p.gastos, FinanceColors.red, currency),
          _DetailPill(
              'Inversión', p.inversiones, FinanceColors.violet, currency),
          _DetailPill(
              'Abono externo', p.abonoExterno, FinanceColors.blue, currency),
          if (p.pagos > 0)
            _DetailPill('Pagos (solo registro)', p.pagos, FinanceColors.amber,
                currency),
          _DetailPill('Ganancia estimada', p.gananciaEstimada,
              FinanceColors.teal, currency),
        ]),
        if (_canSave) ...[
          const SizedBox(height: 12),
          _buttonsRow([
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
          ]),
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
          for (final m in moves.take(8)) _movementLine(scheme, m, currency),
          if (moves.length > 8)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'y ${moves.length - 8} más…',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ],
    );
  }

  /// Fila de UN tipo de movimiento. Al expandir se desglosa según su tipo:
  /// cada registro con su paquete, su fecha y su monto.
  Widget _kindRow(ColorScheme scheme, String kind, bool wide, String currency) {
    final key = 'kind:$kind';
    final open = _open.contains(key);
    final moves = _data.movementsOfKind(kind);
    final total = _kindTotal(kind);
    final color = _kindColor(kind);
    // Gastos e inversión son salidas; el ahorro se aparta; los abonos (y los
    // externos) son dinero que entra.
    final esSalida = kind == 'gasto' || kind == 'inversion';
    final monto = total > 0
        ? (esSalida ? '−${hsMoney(total, currency)}' : hsMoney(total, currency))
        : '—';
    return Column(
      children: [
        InkWell(
          onTap: () => _toggle(key),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 0, 7),
            child: Row(
              children: [
                Expanded(
                  flex: wide ? 5 : 7,
                  child: Row(
                    children: [
                      AnimatedRotation(
                        turns: open ? .25 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(Icons.chevron_right_rounded,
                            size: 18, color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 6),
                      Icon(_kindIcon(kind), size: 16, color: color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _kindLabel(kind),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: wide ? 12.5 : 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                _amountCell(
                    monto, total > 0 ? color : scheme.onSurfaceVariant),
                if (wide)
                  _amountCell(
                    kind == 'ahorro' && total > 0
                        ? hsMoney(total, currency)
                        : '—',
                    kind == 'ahorro' && total > 0
                        ? FinanceColors.teal
                        : scheme.onSurfaceVariant,
                  ),
                if (wide)
                  _amountCell(
                    esSalida && total > 0 ? hsMoney(total, currency) : '—',
                    esSalida && total > 0 ? color : scheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
        if (open)
          Container(
            width: double.infinity,
            color: scheme.surfaceContainerHighest.withValues(alpha: .22),
            padding: const EdgeInsets.fromLTRB(34, 10, 14, 14),
            child: moves.isEmpty
                ? Text(
                    'Sin registros de "${_kindLabel(kind)}".',
                    style: TextStyle(
                        fontSize: 11.5, color: scheme.onSurfaceVariant),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final m in moves.take(12))
                        _movementLine(scheme, m, currency),
                      if (moves.length > 12)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'y ${moves.length - 12} más…',
                            style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
          ),
        Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: .35)),
      ],
    );
  }

  /// Total de un tipo (los abonos salen de `ganancias`).
  num _kindTotal(String kind) {
    final t = _data.totals;
    return switch (kind) {
      'abono' => t.ganancias,
      'ahorro' => t.ahorro,
      'inversion' => t.inversiones,
      'abono_externo' => t.abonoExterno,
      'pago' => t.pagos,
      _ => t.gastos,
    };
  }

  /// Una línea de movimiento: concepto, paquete/cliente, fecha y monto.
  Widget _movementLine(
      ColorScheme scheme, FinanceMovement m, String currency) {
    final when = hsParseDate(m.created);
    final where = m.packageName.isEmpty
        ? m.clientName
        : (m.clientName.isEmpty
            ? m.packageName
            : '${m.packageName} · ${m.clientName}');
    final detail = [
      if (m.userName.trim().isNotEmpty) '→ ${m.userName.trim()}',
      if (m.description.trim().isNotEmpty) m.description.trim(),
      if (where.isNotEmpty) where,
      if (when != null) hsShortDate(when),
    ].join('  ·  ');
    final color = _kindColor(m.kind);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
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
          Text(
            hsMoney(m.amount, currency),
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }

  /// Celda de dinero alineada a la derecha (nunca desborda).
  Widget _amountCell(String text, Color color) => Expanded(
        flex: 3,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              text,
              maxLines: 1,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ),
      );

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
// Registrar un movimiento del paquete DESDE Finanzas
// (ahorro / gasto / inversión / abono externo; el ahorro se puede capturar
//  como cantidad o como PORCENTAJE del disponible del paquete)
// ==================================================================

class _FinanceMovementDialog extends StatefulWidget {
  const _FinanceMovementDialog({
    required this.packages,
    required this.currency,
    required this.totals,
    this.initial,
    this.kind = 'ahorro',
  });

  final List<FinancePackage> packages;
  final String currency;

  /// Totales del negocio: el `disponible` general es la base del ahorro en
  /// porcentaje cuando el movimiento NO se atribuye a un paquete.
  final FinanceTotals totals;
  final FinancePackage? initial;

  /// Tipo preseleccionado (`ahorro` por defecto).
  final String kind;

  @override
  State<_FinanceMovementDialog> createState() => _FinanceMovementDialogState();
}

class _FinanceMovementDialogState extends State<_FinanceMovementDialog> {
  /// 0 = movimiento GENERAL (del negocio, sin paquete). Es el valor por
  /// defecto: registrar un movimiento YA NO pide elegir un paquete.
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

  /// Base del ahorro en porcentaje: el disponible del paquete elegido o, si
  /// el movimiento es general, el disponible del negocio.
  num get _baseDisponible => _package?.disponible ?? widget.totals.disponible;
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
      setState(() => _error = _byPercent
          ? 'El porcentaje debe dar un monto mayor a 0'
          : 'Escribe un monto mayor a 0');
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
      title: _isSavings ? 'Abonar al ahorro' : 'Agregar movimiento',
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
        // El paquete es OPCIONAL y viene en "General": para registrar un
        // gasto del negocio no hay que elegir ningún paquete.
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
              for (final kind in _kKindRows)
                if (kind != 'abono')
                  ChoiceChip(
                    label: Text(_kindLabel(kind)),
                    avatar: Icon(_kindIcon(kind),
                        size: 15, color: _kindColor(kind)),
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
              Icon(_baseIsGeneral
                  ? Icons.storefront_outlined
                  : Icons.savings_outlined, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _baseIsGeneral
                      ? 'Disponible general del negocio (cobrado - gastado '
                          '- ahorro + abono externo)'
                      : 'Disponible del paquete (abonado - gastado - ahorro + '
                          'abono externo)',
                  style:
                      TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
              ),
              Text(
                hsMoney(_baseDisponible, widget.currency),
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w800, color: color),
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
              onSelectionChanged:
                  _saving ? null : (s) => setState(() => _mode = s.first),
            ),
          ),
        ],
        const SizedBox(height: 14),
        if (_byPercent) ...[
          FormSection(
            label: _baseIsGeneral
                ? 'Porcentaje del disponible general'
                : 'Porcentaje del disponible',
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
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ),
                Text(
                  hsMoney(amount, widget.currency),
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800, color: color),
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
              hintText: 'Ej. Ahorro del mes, renta de equipo…',
              alignLabelWithHint: true,
            ),
          ),
        ),
      ],
    );
  }
}

// ==================================================================
// Resumen del dinero: cuadros AGRUPADOS
// ==================================================================
// Antes los 10 cuadros eran una rejilla pareja y quedaba todo junto: no se
// distinguía lo que GANAS de lo que SALE. Ahora van en cuatro tarjetas
// (Lo que ganas · Cobros · Salidas · Apartado y pagos), cada una con su
// título y sus cuadros dentro.
//
//  * Ventana ancha: los cuatro grupos en UNA fila, cada uno con sus cuadros
//    apilados (el número se lee de un vistazo).
//  * Ventana angosta / teléfono: los grupos se apilan en una columna.
//
// El diseño cambia por ANCHO, nunca por alto: así el bloque tiene siempre la
// misma altura y no vuelve a comerse el espacio de la tabla de abajo.
// ==================================================================

/// Un grupo de cuadros (título + sus totales).
class _MoneyGroup {
  const _MoneyGroup(this.title, this.icon, this.tint, this.kpis);

  final String title;
  final IconData icon;
  final Color tint;
  final List<FinanceKpi> kpis;
}

class _MoneySummary extends StatelessWidget {
  const _MoneySummary({
    required this.totals,
    required this.currency,
    this.showNotes = true,
  });

  final FinanceTotals totals;
  final String currency;

  /// ¿Cada cuadro muestra su aclaración ("= Disponible", "Solo registro"…)?
  /// En el teléfono se omite: el nombre del concepto se queda con todo el
  /// ancho y nada se recorta.
  final bool showNotes;

  /// Los cuatro grupos, en el orden en que se leen: primero lo que ganas,
  /// luego lo que entra, lo que sale y al final lo apartado.
  List<_MoneyGroup> _groups() => [
        _MoneyGroup('Lo que ganas', Icons.workspace_premium_outlined,
            FinanceColors.green, [
          FinanceKpi(
            label: 'Ganado',
            amount: totals.disponible,
            icon: Icons.savings_outlined,
            tint: FinanceColors.green,
            note: '= Disponible',
          ),
          FinanceKpi(
            label: 'Ganancia real',
            amount: totals.gananciaReal,
            icon: Icons.verified_outlined,
            tint: FinanceColors.green,
            note: 'Contando los gastos',
          ),
          FinanceKpi(
            label: 'Ganancia estimada',
            amount: totals.gananciaEstimada,
            icon: Icons.insights_outlined,
            tint: FinanceColors.teal,
            note: 'Ahorro e inversión aparte',
          ),
        ]),
        _MoneyGroup('Cobros', Icons.payments_outlined, FinanceColors.green, [
          FinanceKpi(
            label: 'Cobrado',
            amount: totals.ganancias,
            icon: Icons.payments_outlined,
            tint: FinanceColors.green,
            note: 'Abonos recibidos',
          ),
          FinanceKpi(
            label: 'Por cobrar',
            amount: totals.porCobrar,
            icon: Icons.hourglass_bottom_rounded,
            tint: FinanceColors.amber,
            note: 'De ${hsMoney(totals.facturado, currency)}',
          ),
          FinanceKpi(
            label: 'Abono externo',
            amount: totals.abonoExterno,
            icon: Icons.account_balance_wallet_outlined,
            tint: FinanceColors.blue,
            note: 'Entra por fuera',
          ),
        ]),
        _MoneyGroup('Salidas', Icons.trending_down, FinanceColors.red, [
          FinanceKpi(
            label: 'Gastos',
            amount: totals.gastos,
            icon: Icons.trending_down,
            tint: FinanceColors.red,
          ),
          FinanceKpi(
            label: 'Inversión',
            amount: totals.inversiones,
            icon: Icons.trending_up,
            tint: FinanceColors.violet,
          ),
        ]),
        _MoneyGroup('Apartado y pagos', Icons.savings_outlined,
            FinanceColors.teal, [
          FinanceKpi(
            label: 'Ahorro',
            amount: totals.ahorro,
            icon: Icons.lock_outline_rounded,
            tint: FinanceColors.teal,
          ),
          FinanceKpi(
            label: 'Pagos',
            amount: totals.pagos,
            icon: Icons.handshake_outlined,
            tint: FinanceColors.amber,
            note: 'Solo registro',
          ),
        ]),
      ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groups = _groups();
    // Un SOLO bloque con TODOS los cuadros, uno por línea (en vertical) y sin
    // un recuadro por concepto: se lee como una lista, ocupa menos y no parte
    // el dinero en tarjetas.
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < groups.length; i++) ...[
              if (i > 0) const SizedBox(height: 4),
              _sectionLabel(scheme, groups[i]),
              for (final k in groups[i].kpis)
                _kpiRow(scheme, k, showNote: showNotes),
            ],
          ],
        ),
      ),
    );
  }

  /// Rótulo de una sección del resumen (Lo que ganas, Cobros…). Es solo una
  /// línea con su icono: separa sin volver a meter recuadros.
  Widget _sectionLabel(ColorScheme scheme, _MoneyGroup g) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Row(
        children: [
          Icon(g.icon, size: 12, color: g.tint),
          const SizedBox(width: 6),
          Text(
            g.title.toUpperCase(),
            style: TextStyle(
              fontSize: 9.5,
              letterSpacing: .7,
              fontWeight: FontWeight.w800,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: .5),
            ),
          ),
        ],
      ),
    );
  }

  /// Una línea del resumen: icono, concepto (con su aclaración) y el monto a
  /// la derecha. Va en UNA sola línea y sin recuadro: todos los cuadros juntos
  /// en la misma tarjeta, uno debajo del otro.
  Widget _kpiRow(ColorScheme scheme, FinanceKpi k, {required bool showNote}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(k.icon, size: 15, color: k.tint),
          const SizedBox(width: 8),
          // El concepto tiene la mayor parte del ancho (nunca se recorta); la
          // aclaración va después, más pequeña, y el dinero se ancla a la
          // derecha. En el teléfono la aclaración se omite ([showNote]=false)
          // para dejarle todo el ancho al nombre.
          // El nombre nunca sale con puntos suspensivos: si el concepto es
          // largo ("Ganancia estimada") se encoge lo justo para caber, así se
          // lee completo en vez de recortado.
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  k.label.toUpperCase(),
                  maxLines: 1,
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
          if (showNote && k.note != null) ...[
            const SizedBox(width: 8),
            Flexible(
              flex: 2,
              child: Text(
                k.note!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
          const SizedBox(width: 12),
          Text(
            hsMoney(k.amount, currency),
            style: TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w800, color: k.tint),
          ),
        ],
      ),
    );
  }
}

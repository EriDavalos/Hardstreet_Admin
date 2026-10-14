import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../finance_data.dart';
import '../hs_format.dart';

// ==================================================================
// HARD STREET ADMIN - Widgets de FINANZAS
//
// Piezas compartidas por el módulo Finanzas y el Dashboard:
//   * FinanceColors      la paleta del dinero (misma en toda la app)
//   * FinanceKpiGrid     cuadros de totales, horizontales y parejos
//   * FinanceMonthBars   gráfica de barras: lo que ENTRÓ vs. lo que SALIÓ
//   * FinanceLegend      la leyenda de colores
// Sin dependencias externas: todo se dibuja con layout de Flutter.
// ==================================================================

/// Paleta de finanzas (una sola fuente de verdad).
class FinanceColors {
  FinanceColors._();

  /// Dinero cobrado (abonos).
  static const green = Color(0xFF10B981);

  /// Gastos.
  static const red = Color(0xFFEF4444);

  /// Inversión (también es una salida, pero se pinta distinto).
  static const violet = Color(0xFF8B5CF6);

  /// Apartado en el ahorro.
  static const teal = Color(0xFF14B8A6);

  /// Pago recibido fuera del paquete.
  static const blue = Color(0xFF3B82F6);

  /// Falta por cobrar.
  static const amber = Color(0xFFF59E0B);
}

/// Un cuadro de total (etiqueta + monto + icono + color).
class FinanceKpi {
  const FinanceKpi({
    required this.label,
    required this.amount,
    required this.icon,
    required this.tint,
    this.note,
  });

  final String label;
  final num amount;
  final IconData icon;
  final Color tint;

  /// Aclaración corta bajo el monto (opcional).
  final String? note;
}

/// Cuadros de dinero en HORIZONTAL: filas parejas que se reacomodan según el
/// ancho (2 en teléfono, 3 en tablet, hasta 4 en escritorio) sin recortar
/// etiquetas ni montos.
class FinanceKpiGrid extends StatelessWidget {
  const FinanceKpiGrid({
    super.key,
    required this.kpis,
    this.currency = 'MXN',
    this.columns,
    this.minForcedWidth = 400,
  });

  final List<FinanceKpi> kpis;
  final String currency;

  /// Columnas EXACTAS deseadas (se respetan si el ancho lo permite). Sirve
  /// para poner los cuadros en UNA fila en tableros donde el alto es crítico.
  final int? columns;

  /// Ancho mínimo para respetar [columns]; por debajo se usan las columnas
  /// responsivas (2/3/4). Finanzas lo baja para caber en teléfonos angostos.
  final double minForcedWidth;

  @override
  Widget build(BuildContext context) {
    if (kpis.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final forced = columns;
      final cols = (forced != null && w >= minForcedWidth)
          ? math.min(forced, kpis.length)
          : w < 520
              ? 2
              : w < 900
                  ? 3
                  : 4;
      // Ancho de cada cuadro: (total - separaciones) / columnas. El último de
      // cada fila queda alineado a la izquierda (no se estira de más).
      const gap = 10.0;
      final tileW = (w - gap * (cols - 1)) / cols;
      // Cuadro ESTRECHO (teléfono, tablero): el icono a un lado solo deja ~30
      // px de texto y todo queda recortado. En ese caso el contenido va en
      // apilado (icono + etiqueta arriba, monto abajo) y sin la nota, que es
      // la que más ancho pide. La nota vuelve cuando el cuadro es amplio.
      final stacked = tileW < 210;
      final withNote = !stacked && tileW >= 238;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final k in kpis)
            SizedBox(
              width: tileW,
              child: Container(
                padding: stacked
                    ? const EdgeInsets.symmetric(horizontal: 8, vertical: 9)
                    : const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: k.tint.withValues(alpha: .28)),
                ),
                child: stacked
                    ? _stacked(context, k)
                    : _inline(context, k, withNote),
              ),
            ),
        ],
      );
    });
  }

  /// Cuadro APILADO: etiqueta con su icono en una línea y el monto debajo,
  /// a todo el ancho del cuadro (nada queda cortado en pantallas angostas).
  Widget _stacked(BuildContext context, FinanceKpi k) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(k.icon, size: 13, color: k.tint),
            const SizedBox(width: 5),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  k.label.toUpperCase(),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: .4,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            hsMoney(k.amount, currency),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: k.tint,
            ),
          ),
        ),
      ],
    );
  }

  /// Cuadro en HORIZONTAL: icono a la izquierda, etiqueta/monto/nota a la
  /// derecha (el de escritorio, donde hay ancho de sobra).
  Widget _inline(BuildContext context, FinanceKpi k, bool withNote) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: k.tint.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(k.icon, size: 17, color: k.tint),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                k.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: .4,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  hsMoney(k.amount, currency),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: k.tint,
                  ),
                ),
              ),
              if (withNote && k.note != null && k.note!.isNotEmpty)
                Text(
                  k.note!,
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
    );
  }
}

/// Gráfica de barras por mes: dos columnas por mes (lo que ENTRÓ y lo que
/// SALIÓ), con la escala compartida para poder comparar de un vistazo.
class FinanceMonthBars extends StatelessWidget {
  const FinanceMonthBars({
    super.key,
    required this.months,
    this.height = 148,
  });

  final List<FinanceMonth> months;
  final double height;

  /// Tope de la escala: el mes más alto.
  num get _scale {
    num top = 0;
    for (final m in months) {
      if (m.peak > top) top = m.peak;
    }
    return top <= 0 ? 1 : top;
  }

  /// Barra apilada: cada segmento es (monto, color); se dibuja de abajo
  /// hacia arriba y el conjunto queda pegado a la base.
  Widget _bar(List<(num, Color)> segments) {
    final visible = [
      for (final s in segments)
        if (s.$1 > 0) s,
    ];
    return SizedBox(
      height: height,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (value, color) in visible.reversed)
            Container(
              height: math.max(3, value / _scale * height),
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(3),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (months.isEmpty) {
      return Text(
        'Todavía no hay movimientos para graficar.',
        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
      );
    }
    final hasData = months.any((m) => m.peak > 0);
    if (!hasData) {
      return Text(
        'Sin dinero registrado en los últimos meses.',
        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final m in months)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // ENTRÓ: abonos cobrados (+ abono externo).
                        Expanded(
                          child: _bar([
                            (m.ganancias, FinanceColors.green),
                            (m.abonoExterno, FinanceColors.blue),
                          ]),
                        ),
                        const SizedBox(width: 3),
                        // SALIÓ: gastos + inversión + ahorro.
                        Expanded(
                          child: _bar([
                            (m.inversiones, FinanceColors.violet),
                            (m.gastos, FinanceColors.red),
                            (m.ahorro, FinanceColors.teal),
                          ]),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final m in months)
              Expanded(
                child: Center(
                  child: Text(
                    m.label,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Leyenda de colores de la gráfica (una sola línea, con salto si no cabe).
class FinanceLegend extends StatelessWidget {
  const FinanceLegend({super.key});

  @override
  Widget build(BuildContext context) {
    const items = <(String, Color)>[
      ('Ganancias', FinanceColors.green),
      ('Gastos', FinanceColors.red),
      ('Inversión', FinanceColors.violet),
      ('Ahorro', FinanceColors.teal),
      ('Abono externo', FinanceColors.blue),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (final (label, color) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
      ],
    );
  }
}

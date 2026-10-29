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

/// Paleta de finanzas (la ÚNICA fuente de verdad de los colores del dinero).
///
/// El mismo color se usa en el módulo Finanzas, en el tablero y en el
/// administrador de paquetes del cliente, para que un concepto se reconozca de
/// un vistazo en cualquier pantalla:
///
///   abono          VERDE      dinero que entra del cliente
///   abono externo  AZUL CLARO pago recibido fuera del paquete
///   ahorro         AZUL       dinero apartado
///   inversión      NARANJA    dinero que se mete al paquete
///   gasto          ROJO       dinero que se va
///   pagado         ÁMBAR      pagos a colaboradores y empleados
class FinanceColors {
  FinanceColors._();

  /// Abonos: dinero cobrado a los clientes. VERDE.
  static const abono = Color(0xFF16A34A);

  /// Abono externo: pago recibido fuera del paquete. Azul CLARO (un tono más
  /// claro que el azul del ahorro, para no confundirlos).
  static const abonoExterno = Color(0xFF3B82F6);

  /// Ahorro: dinero apartado. AZUL.
  static const ahorro = Color(0xFF2F6BFF);

  /// Inversión: dinero que se mete al paquete. NARANJA.
  static const inversion = Color(0xFFF97316);

  /// Gastos. ROJO.
  static const gasto = Color(0xFFEF4444);

  /// Pagos a colaboradores y empleados. ÁMBAR.
  static const pagado = Color(0xFFF59E0B);

  /// Falta por cobrar de un paquete. ÁMBAR (el mismo del dinero por entregar).
  static const porCobrar = Color(0xFFF59E0B);

  // ------------------------------------------------------------------
  // Alias históricos: mismos valores que los conceptos de arriba. Se
  // conservan para no tocar cada uso; el nombre nuevo es el que describe el
  // concepto. NUNCA darles un valor distinto al de su concepto.
  // ------------------------------------------------------------------

  /// = [abono] (también se usa para saldos a favor).
  static const positive = abono;

  /// = [gasto].
  static const red = gasto;

  /// = [inversion].
  static const investment = inversion;

  /// = [ahorro].
  static const teal = ahorro;

  /// = [abonoExterno].
  static const blue = abonoExterno;

  /// = [pagado] (y [porCobrar], que comparten tono).
  static const amber = pagado;
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

/// Cuadros de dinero en HORIZONTAL.
///
/// Dos formas según el ancho disponible:
///
///  * **Escritorio/tablet**: filas parejas que se reacomodan (2/3/4 columnas)
///    sin recortar etiquetas ni montos.
///  * **Teléfono**: un CARRUSEL —se desliza de lado— con UNA tarjeta COMPLETA
///    por pantalla (nunca dos a medias en los bordes) y sus puntos abajo para
///    saber cuántas hay. Así el dinero se lee entero y no se come el alto que
///    necesita la información de abajo.
///
/// Con [columns] fijo (tableros donde el alto es crítico) siempre se usa la
/// rejilla: ese modo no cambia.
class FinanceKpiGrid extends StatefulWidget {
  const FinanceKpiGrid({
    super.key,
    required this.kpis,
    this.currency = 'MXN',
    this.columns,
    this.minForcedWidth = 400,
    this.carouselBelow = 560,
  });

  final List<FinanceKpi> kpis;
  final String currency;

  /// Columnas EXACTAS deseadas (se respetan si el ancho lo permite). Sirve
  /// para poner los cuadros en UNA fila en tableros donde el alto es crítico.
  final int? columns;

  /// Ancho mínimo para respetar [columns]; por debajo se usan las columnas
  /// responsivas (2/3/4). Finanzas lo baja para caber en teléfonos angostos.
  final double minForcedWidth;

  /// Por debajo de este ancho (y sin [columns] fijo) los cuadros van en
  /// carrusel, de uno en uno.
  final double carouselBelow;

  @override
  State<FinanceKpiGrid> createState() => _FinanceKpiGridState();
}

class _FinanceKpiGridState extends State<FinanceKpiGrid> {
  final PageController _pages = PageController();
  int _page = 0;

  List<FinanceKpi> get kpis => widget.kpis;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kpis.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      // Teléfono: carrusel (solo cuando nadie pidió columnas exactas).
      if (widget.columns == null &&
          w < widget.carouselBelow &&
          kpis.length > 1) {
        return _carousel(scheme, w);
      }
      return _wrap(scheme, w);
    });
  }

  /// Rejilla responsiva (escritorio/tablet).
  Widget _wrap(ColorScheme scheme, double w) {
    final forced = widget.columns;
    final cols = (forced != null && w >= widget.minForcedWidth)
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
            child: _tile(scheme, k, stacked: stacked, withNote: withNote),
          ),
      ],
    );
  }

  /// Carrusel del teléfono: una tarjeta COMPLETA por pantalla, se desliza
  /// horizontalmente y abajo van los puntos (tocables) para saltar a otra.
  Widget _carousel(ColorScheme scheme, double w) {
    const gap = 10.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 94,
          child: PageView.builder(
            controller: _pages,
            itemCount: kpis.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => Padding(
              // Aire a la derecha: la tarjeta siguiente no asoma por el borde
              // (nada de dos tarjetas a medias).
              padding: const EdgeInsets.only(right: gap),
              child: _tile(scheme, kpis[i], stacked: false, withNote: true),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < kpis.length; i++)
              GestureDetector(
                onTap: () => _pages.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page
                        ? kpis[i].tint
                        : scheme.onSurfaceVariant.withValues(alpha: .3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Tarjeta de un total: plana, con el borde del color del concepto.
  Widget _tile(
    ColorScheme scheme,
    FinanceKpi k, {
    required bool stacked,
    required bool withNote,
  }) {
    return Container(
      padding: stacked
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 9)
          : const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: k.tint.withValues(alpha: .28)),
      ),
      child: stacked ? _stacked(scheme, k) : _inline(scheme, k, withNote),
    );
  }

  /// Cuadro APILADO: etiqueta con su icono en una línea y el monto debajo,
  /// a todo el ancho del cuadro (nada queda cortado en pantallas angostas).
  Widget _stacked(ColorScheme scheme, FinanceKpi k) {
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
            hsMoney(k.amount, widget.currency),
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
  /// derecha (escritorio y las tarjetas del carrusel del teléfono).
  Widget _inline(ColorScheme scheme, FinanceKpi k, bool withNote) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: k.tint.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(k.icon, size: 20, color: k.tint),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                k.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
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
                  hsMoney(k.amount, widget.currency),
                  style: TextStyle(
                    fontSize: 17,
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
                    fontSize: 10.5,
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
                            (m.ganancias, FinanceColors.positive),
                            (m.abonoExterno, FinanceColors.blue),
                          ]),
                        ),
                        const SizedBox(width: 3),
                        // SALIÓ: gastos + inversión + ahorro.
                        Expanded(
                          child: _bar([
                            (m.inversiones, FinanceColors.investment),
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
      ('Ganancias', FinanceColors.positive),
      ('Gastos', FinanceColors.red),
      ('Inversión', FinanceColors.investment),
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

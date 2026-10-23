import 'package:flutter/material.dart';

// ==================================================================
// HARD STREET ADMIN — PAGINACIÓN de los listados
// ==================================================================
// Todos los módulos muestran sus filas de 30 en 30 (se puede cambiar a 50,
// 100 o 200) y con botones para ir a la página anterior / siguiente. Los
// botones se DESHABILITAN en los extremos (no se puede ir antes de la 1 ni
// después de la última). En el celular TODO va en una sola fila al pie
// (‹ Página X de Y › y el tamaño), sin nada encima: es lo que menos alto ocupa
// y los botones quedan cómodos para el dedo.
//
// La barra vive en el PIE FIJO de la página ([PageContainer.footer]): queda
// abajo, fuera del scroll, como el pie de una tabla de escritorio. Antes iba
// al final del listado y había que bajar hasta el último dato para cambiar de
// página.
//
// El paginado lo calcula el BACKEND (`Hardstreet-Backend/lib/pagination.ts`):
// la app manda `?page=&limit=` y recibe solo esa página + `total`/`pages`. Los
// módulos con backend viejo (respuesta sin `total`) siguen paginando en
// pantalla con [HsPages].
// ==================================================================

/// Tamaños de página que ofrece la app (el primero es el de fábrica).
const List<int> kHsPageSizes = [30, 50, 100, 200];

/// Filas por página de fábrica.
const int kHsDefaultPageSize = 30;

/// Estado de paginación de un listado ya cargado.
///
/// Se usa para recortar una lista COMPLETA en pantalla (modo de respaldo de
/// los backends viejos, que no devuelven `total`) y para calcular los rótulos
/// "31–60 de 240". En los módulos con paginado del servidor la app ya recibe
/// solo la página y el total: no hay nada que recortar.
class HsPages {
  const HsPages({
    required this.total,
    this.page = 1,
    this.pageSize = kHsDefaultPageSize,
  });

  /// Filas totales (ya filtradas).
  final int total;

  /// Página actual, empezando en 1.
  final int page;

  /// Filas por página.
  final int pageSize;

  int get pages => total <= 0 ? 1 : ((total + pageSize - 1) ~/ pageSize);

  /// Página actual dentro de los límites (por si el filtro encoge la lista).
  int get current => page.clamp(1, pages);

  bool get canPrev => current > 1;
  bool get canNext => current < pages;

  /// Primera fila visible (1-based) y última, para el rótulo "31–60 de 240".
  int get first => total == 0 ? 0 : (current - 1) * pageSize + 1;
  int get last => total == 0 ? 0 : (current * pageSize).clamp(0, total);

  /// Las filas de la página actual.
  List<T> slice<T>(List<T> rows) {
    // Sin filas no hay nada que recortar (ni siquiera una página vacía).
    if (rows.isEmpty || total <= 0) return const [];
    final from = (current - 1) * pageSize;
    final to = (from + pageSize).clamp(0, rows.length);
    if (from >= rows.length) return const [];
    return rows.sublist(from, to);
  }

  HsPages copyWith({int? total, int? page, int? pageSize}) => HsPages(
    total: total ?? this.total,
    page: page ?? this.page,
    pageSize: pageSize ?? this.pageSize,
  );
}

/// Barra de paginación: "31–60 de 240 · 30 por página · ‹ 1 2 [3] 4 ›".
///
/// Se pinta al FINAL del listado. Si hay una sola página igual se ve (para
/// poder cambiar el tamaño de página), pero los botones quedan deshabilitados.
class HsPager extends StatelessWidget {
  const HsPager({
    super.key,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.onPage,
    required this.onPageSize,
    this.enabled = true,
  });

  /// Filas totales (ya filtradas).
  final int total;

  /// Página actual (1-based).
  final int page;

  /// Filas por página.
  final int pageSize;

  final ValueChanged<int> onPage;
  final ValueChanged<int> onPageSize;

  /// false mientras carga: los botones se ven, pero apagados.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hs = HsPages(total: total, page: page, pageSize: pageSize);
    final compact = MediaQuery.sizeOf(context).width < 620;
    final canPrev = enabled && hs.canPrev;
    final canNext = enabled && hs.canNext;

    final info = Text(
      total == 0 ? 'Sin resultados' : '${hs.first}–${hs.last} de $total',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
      ),
    );

    final sizeChips = _SizePicker(
      pageSize: pageSize,
      enabled: enabled,
      onChanged: onPageSize,
      compact: compact,
    );

    final arrows = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ArrowButton(
          key: const ValueKey('hs-pager-prev'),
          icon: Icons.navigate_before_rounded,
          tooltip: 'Página anterior',
          onTap: canPrev ? () => onPage(hs.current - 1) : null,
          compact: compact,
        ),
        if (compact)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Página ${hs.current} de ${hs.pages}',
              key: const ValueKey('hs-pager-label'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          )
        else
          ..._numbers(context, hs),
        _ArrowButton(
          key: const ValueKey('hs-pager-next'),
          icon: Icons.navigate_next_rounded,
          tooltip: 'Página siguiente',
          onTap: canNext ? () => onPage(hs.current + 1) : null,
          compact: compact,
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.only(top: compact ? 14 : 12, bottom: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5)),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: compact
              // CELULAR: TODO en UNA sola fila al pie —‹ Página X de Y › a la
              // izquierda y el tamaño a la derecha—. Antes había dos líneas
              // (info + tamaño arriba) y se comía el alto de la pantalla.
              ? Row(
                  children: [arrows, const Spacer(), sizeChips],
                )
              // ESCRITORIO: todo en una línea, alineado a la derecha salvo el
              // resumen, que va a la izquierda.
              : Row(
                  children: [
                    info,
                    const Spacer(),
                    sizeChips,
                    const SizedBox(width: 12),
                    arrows,
                  ],
                ),
        ),
      ),
    );
  }

  /// Números de página: primera, alrededor de la actual y última, con "…"
  /// cuando se saltan páginas. La página actual va resaltada.
  List<Widget> _numbers(BuildContext context, HsPages hs) {
    final scheme = Theme.of(context).colorScheme;
    final out = <Widget>[];
    final pages = <int>{1, hs.pages};
    for (var i = hs.current - 1; i <= hs.current + 1; i++) {
      if (i >= 1 && i <= hs.pages) pages.add(i);
    }
    final ordered = pages.toList()..sort();
    int? prev;
    for (final n in ordered) {
      if (prev != null && n - prev > 1) {
        out.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '…',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
        );
      }
      final active = n == hs.current;
      out.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: InkWell(
            key: ValueKey('hs-pager-num-$n'),
            borderRadius: BorderRadius.circular(9),
            onTap: active || !enabled ? null : () => onPage(n),
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active
                    ? scheme.primary.withValues(alpha: .16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: active
                      ? scheme.primary.withValues(alpha: .5)
                      : Colors.transparent,
                ),
              ),
              child: Text(
                '$n',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  color: active ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      );
      prev = n;
    }
    return out;
  }
}

/// Botón de flecha (34 px en escritorio, 38 en celular): no es diminuto pero
/// tampoco ocupa una franja entera.
class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.compact,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final side = compact ? 38.0 : 32.0;
    final off = onTap == null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          width: side,
          height: side,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: off ? .3 : .7),
            ),
          ),
          // Deshabilitado = apagado (no se puede cambiar de página).
          child: Icon(
            icon,
            size: compact ? 22 : 19,
            color: off
                ? scheme.onSurfaceVariant.withValues(alpha: .3)
                : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Selector de filas por página: muestra el valor actual y abre 30/50/100/200.
class _SizePicker extends StatelessWidget {
  const _SizePicker({
    required this.pageSize,
    required this.enabled,
    required this.onChanged,
    this.compact = false,
  });

  final int pageSize;
  final bool enabled;
  final ValueChanged<int> onChanged;

  /// Celular: solo el número ("30"), que es lo que cabe en la fila del pie.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<int>(
      key: const ValueKey('hs-pager-size'),
      enabled: enabled,
      tooltip: 'Filas por página',
      initialValue: pageSize,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final n in kHsPageSizes)
          PopupMenuItem<int>(
            value: n,
            child: Row(
              children: [
                Text('$n filas', style: const TextStyle(fontSize: 13)),
                const Spacer(),
                if (n == pageSize)
                  Icon(Icons.check_rounded, size: 16, color: scheme.primary),
              ],
            ),
          ),
      ],
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: enabled ? .7 : .3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              compact ? '$pageSize' : '$pageSize por página',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: enabled
                    ? scheme.onSurfaceVariant
                    : scheme.onSurfaceVariant.withValues(alpha: .35),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: enabled
                  ? scheme.onSurfaceVariant
                  : scheme.onSurfaceVariant.withValues(alpha: .35),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme.dart';
import 'hs_modal.dart';

// ==================================================================
// BARRA DE BÚSQUEDA + FILTROS (todos los módulos con datos)
// ==================================================================
// Patrón único del panel:
//
//   [ ⚙ Filtros ]  [ 🔎 Buscar…                          ✕ ]
//
// El botón de la izquierda es una imagen (icono) con un globo que dice
// cuántos filtros están activos; abre el MÓDULO DE FILTROS, un modal (pantalla
// completa en celular) con todas las opciones y sus conteos. Los filtros ya no
// viven como chips sueltos arriba del listado: se eligen en un solo lugar y,
// cuando hay alguno activo, se ve debajo como píldora removible.
// ==================================================================

/// Una opción dentro de un grupo de filtros.
class HsFilterOption {
  const HsFilterOption({
    required this.value,
    required this.label,
    this.count,
    this.icon,
    this.color,
  });

  /// Valor que se manda al servidor ('' = «Todos»).
  final String value;
  final String label;

  /// Conteo opcional (se muestra a la derecha de la etiqueta).
  final int? count;
  final IconData? icon;
  final Color? color;
}

/// Un grupo de filtros (p. ej. «Rol», «Tipo de movimiento»).
class HsFilterGroup {
  const HsFilterGroup({
    required this.id,
    required this.title,
    required this.options,
    this.help,
    this.multi = false,
  });

  final String id;
  final String title;

  /// Explicación breve de qué hace el filtro.
  final String? help;

  /// Varias opciones a la vez (por ahora todos los filtros son de una).
  final bool multi;
  final List<HsFilterOption> options;
}

/// Barra de búsqueda con su botón de filtros.
class HsSearchFilterBar extends StatefulWidget {
  const HsSearchFilterBar({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
    this.groups = const [],
    this.selected = const {},
    this.onApply,
    this.enabled = true,
    this.trailing,
    this.initial = '',
  });

  final String hint;
  final ValueChanged<String> onChanged;

  /// Controlador externo (para limpiar desde el módulo). Si no se pasa, la
  /// barra crea el suyo.
  final TextEditingController? controller;

  /// Grupos de filtros. Vacío = no se dibuja el botón.
  final List<HsFilterGroup> groups;

  /// Valores activos por grupo (`{ 'role': 'Admin' }`).
  final Map<String, String> selected;

  /// Se llama al aplicar/limpiar en el módulo de filtros.
  final void Function(Map<String, String>)? onApply;

  final bool enabled;

  /// Acción extra a la derecha (p. ej. un botón de orden).
  final Widget? trailing;

  /// Texto inicial cuando no hay [controller].
  final String initial;

  @override
  State<HsSearchFilterBar> createState() => _HsSearchFilterBarState();
}

class _HsSearchFilterBarState extends State<HsSearchFilterBar> {
  TextEditingController? _own;
  TextEditingController get _ctrl =>
      widget.controller ??
      (_own ??= TextEditingController(text: widget.initial));

  @override
  void didUpdateWidget(covariant HsSearchFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller == null &&
        oldWidget.initial != widget.initial &&
        _own != null &&
        _own!.text != widget.initial) {
      _own!.text = widget.initial;
    }
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  int get _activeCount =>
      widget.selected.values.where((v) => v.trim().isNotEmpty).length;

  Future<void> _openFilters() async {
    if (widget.groups.isEmpty) return;
    final out = await showHsModal<Map<String, String>>(
      context: context,
      builder: (_) =>
          HsFilterDialog(groups: widget.groups, selected: widget.selected),
    );
    if (out == null) return;
    widget.onApply?.call(out);
  }

  void _clearOne(String groupId) {
    final next = Map<String, String>.from(widget.selected)..[groupId] = '';
    widget.onApply?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final phone = hsIsPhone(context);
    final active = _activeCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.groups.isNotEmpty) ...[
              _FilterButton(
                badge: _activeCount,
                enabled: widget.enabled,
                onTap: _openFilters,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: TextField(
                controller: _ctrl,
                enabled: widget.enabled,
                textInputAction: TextInputAction.search,
                onChanged: (v) {
                  widget.onChanged(v);
                  setState(() {});
                },
                decoration: InputDecoration(
                  hintText: widget.hint,
                  isDense: phone,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _ctrl.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpiar búsqueda',
                          onPressed: () {
                            _ctrl.clear();
                            widget.onChanged('');
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: phone ? 11 : 13,
                  ),
                ),
              ),
            ),
            if (widget.trailing != null) ...[
              const SizedBox(width: 8),
              widget.trailing!,
            ],
          ],
        ),
        // Filtros activos: se ven (y se quitan) sin abrir el módulo.
        if (active) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final group in widget.groups)
                if ((widget.selected[group.id] ?? '').trim().isNotEmpty)
                  _ActiveFilterPill(
                    label: _labelOf(group, widget.selected[group.id]!),
                    color: group.options
                        .firstWhere(
                          (o) => o.value == widget.selected[group.id],
                          orElse: () => HsFilterOption(value: '', label: ''),
                        )
                        .color,
                    onRemove: () => _clearOne(group.id),
                  ),
              if (_activeCount > 1)
                TextButton(
                  onPressed: () => widget.onApply?.call({
                    for (final g in widget.groups) g.id: '',
                  }),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 26),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Limpiar filtros'),
                ),
            ],
          ),
        ],
      ],
    );
  }

  static String _labelOf(HsFilterGroup group, String value) {
    for (final o in group.options) {
      if (o.value == value) return o.label;
    }
    return value;
  }
}

/// Botón cuadrado del filtro, con el número de filtros activos.
class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.badge,
    required this.enabled,
    required this.onTap,
  });

  final int badge;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = badge > 0;
    return Tooltip(
      message: on ? '$badge filtros activos' : 'Filtros',
      child: Material(
        color: on
            ? AppColors.brand.withValues(alpha: .12)
            : scheme.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          key: const ValueKey('hs-filter-button'),
          borderRadius: BorderRadius.circular(11),
          onTap: enabled ? onTap : null,
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: on
                    ? AppColors.brand.withValues(alpha: .55)
                    : scheme.outlineVariant.withValues(alpha: .55),
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 21,
                  color: on ? AppColors.brand : scheme.onSurfaceVariant,
                ),
                if (on)
                  Positioned(
                    right: -7,
                    top: -7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      constraints: const BoxConstraints(minWidth: 15),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.brand,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveFilterPill extends StatelessWidget {
  const _ActiveFilterPill({
    required this.label,
    required this.onRemove,
    this.color,
  });

  final String label;
  final VoidCallback onRemove;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.brand;
    return Container(
      padding: const EdgeInsets.only(left: 9, right: 2, top: 2, bottom: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tint.withValues(alpha: .32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: tint,
            ),
          ),
          IconButton(
            tooltip: 'Quitar filtro',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            onPressed: onRemove,
            icon: Icon(Icons.close_rounded, size: 13, color: tint),
          ),
        ],
      ),
    );
  }
}

/// MÓDULO DE FILTROS: todas las opciones en un solo modal.
class HsFilterDialog extends StatefulWidget {
  const HsFilterDialog({
    super.key,
    required this.groups,
    required this.selected,
  });

  final List<HsFilterGroup> groups;
  final Map<String, String> selected;

  @override
  State<HsFilterDialog> createState() => _HsFilterDialogState();
}

class _HsFilterDialogState extends State<HsFilterDialog> {
  late Map<String, String> _draft = {
    for (final g in widget.groups) g.id: widget.selected[g.id] ?? '',
  };

  int get _count => _draft.values.where((v) => v.trim().isNotEmpty).length;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final phone = hsIsPhone(context);
    return AlertDialog(
      insetPadding: phone
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 10, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      actionsPadding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      title: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.tune_rounded, size: 19, color: AppColors.brand),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filtros',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                Text(
                  'Elige cómo quieres ver el listado',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.groups.length; i++) ...[
                if (i > 0) const SizedBox(height: 18),
                Text(
                  widget.groups[i].title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if ((widget.groups[i].help ?? '').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    widget.groups[i].help!,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.3,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                for (final o in widget.groups[i].options)
                  _FilterOptionTile(
                    option: o,
                    selected: _draft[widget.groups[i].id] == o.value,
                    onTap: () => setState(() {
                      _draft[widget.groups[i].id] = o.value;
                    }),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            _draft = {for (final g in widget.groups) g.id: ''};
          }),
          child: const Text('Limpiar'),
        ),
        const SizedBox(width: 4),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_draft),
          child: Text(_count == 0 ? 'Ver todo' : 'Aplicar ($_count)'),
        ),
      ],
    );
  }
}

class _FilterOptionTile extends StatelessWidget {
  const _FilterOptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final HsFilterOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = option.color ?? AppColors.brand;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? tint.withValues(alpha: .10)
            : scheme.surfaceContainerHighest.withValues(alpha: .28),
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: selected
                    ? tint.withValues(alpha: .65)
                    : scheme.outlineVariant.withValues(alpha: .45),
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                if (option.icon != null) ...[
                  Icon(
                    option.icon,
                    size: 17,
                    color: selected ? tint : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 9),
                ],
                Expanded(
                  child: Text(
                    option.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? tint : scheme.onSurface,
                    ),
                  ),
                ),
                if (option.count != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: (selected ? tint : scheme.onSurfaceVariant)
                          .withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${option.count}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: selected ? tint : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: selected ? tint : scheme.outlineVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

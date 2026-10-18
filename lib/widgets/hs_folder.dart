import 'package:flutter/material.dart';

// ==================================================================
// HARD STREET ADMIN — “CARPETITAS” del panel
// ==================================================================
// Piezas compartidas para presentar grupos de datos como carpetas:
//
//   * [HsFolderTile]  una carpeta para ELEGIR (el rol de un usuario);
//   * [HsFolderGroup] una carpeta que CONTIENE algo (una categoría de
//     módulos en el modal de permisos) y se abre/cierra.
//
// La forma es la de una carpeta de verdad: una pestaña arriba a la izquierda
// y el cuerpo redondeado debajo. Se pinta con widgets (sin imágenes) para que
// herede el tema y funcione igual en escritorio y en celular.
// ==================================================================

/// Carpeta SELECTABLE (rol de un usuario, opción de una lista).
///
/// La pestaña superior y el icono usan el color de acento; [selected] la
/// enciende con el color primario del tema.
class HsFolderTile extends StatelessWidget {
  const HsFolderTile({
    super.key,
    required this.label,
    required this.onTap,
    this.subtitle = '',
    this.icon = Icons.folder_rounded,
    this.selected = false,
    this.enabled = true,
    this.badge = '',
    this.width,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final String badge;

  /// Ancho fijo (null = se ajusta al contenido).
  final double? width;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = selected ? scheme.primary : scheme.onSurfaceVariant;
    final off = !enabled;

    return Opacity(
      opacity: off ? .45 : 1,
      child: MouseRegion(
        cursor: off ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: off ? null : onTap,
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pestaña de la carpeta (el detalle que la hace “carpeta”).
                Container(
                  width: 34,
                  height: 9,
                  margin: const EdgeInsets.only(left: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? scheme.primary.withValues(alpha: .85)
                        : scheme.surfaceContainerHighest,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                    border: Border.all(
                      color: selected
                          ? scheme.primary.withValues(alpha: .9)
                          : scheme.outlineVariant.withValues(alpha: .6),
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.fromLTRB(10, 9, 12, 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? scheme.primary.withValues(alpha: .10)
                        : scheme.surfaceContainerHighest.withValues(alpha: .45),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      topRight: Radius.circular(14),
                      bottomLeft: Radius.circular(14),
                      bottomRight: Radius.circular(14),
                    ),
                    border: Border.all(
                      color: selected
                          ? scheme.primary.withValues(alpha: .55)
                          : scheme.outlineVariant.withValues(alpha: .55),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18, color: tint),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: selected ? scheme.primary : null,
                              ),
                            ),
                            if (subtitle.isNotEmpty) ...[
                              const SizedBox(height: 1),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (badge.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? scheme.primary.withValues(alpha: .18)
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                      if (selected) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: scheme.primary,
                        ),
                      ],
                    ],
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

/// Carpeta que CONTIENE tarjetas (una categoría de módulos) y se abre/cierra.
///
/// El encabezado muestra cuántas acciones van marcadas del total; al plegarse
/// el contenido desaparece, pero lo elegido se conserva.
class HsFolderGroup extends StatefulWidget {
  const HsFolderGroup({
    super.key,
    required this.title,
    required this.children,
    this.subtitle = '',
    this.icon = Icons.folder_copy_rounded,
    this.selected = 0,
    this.total = 0,
    this.initiallyOpen = true,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  /// Acciones marcadas / totales, para la pastilla del encabezado.
  final int selected;
  final int total;

  final bool initiallyOpen;
  final List<Widget> children;
  final Widget? trailing;

  @override
  State<HsFolderGroup> createState() => _HsFolderGroupState();
}

class _HsFolderGroupState extends State<HsFolderGroup> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = widget.selected > 0;
    final all = widget.total > 0 && widget.selected == widget.total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pestaña de la carpeta.
        Container(
          width: 46,
          height: 10,
          margin: const EdgeInsets.only(left: 14),
          decoration: BoxDecoration(
            color: on
                ? scheme.primary.withValues(alpha: .35)
                : scheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            border: Border.all(
              color: on
                  ? scheme.primary.withValues(alpha: .45)
                  : scheme.outlineVariant.withValues(alpha: .6),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primary.withValues(alpha: on ? .07 : .03),
                scheme.surfaceContainerHighest.withValues(alpha: .25),
              ],
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
            border: Border.all(
              color: on
                  ? scheme.primary.withValues(alpha: .30)
                  : scheme.outlineVariant.withValues(alpha: .55),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(18),
                ),
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  child: Row(
                    children: [
                      Icon(
                        _open
                            ? Icons.folder_open_rounded
                            : Icons.folder_rounded,
                        size: 20,
                        color: on ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .2,
                              ),
                            ),
                            if (widget.subtitle.isNotEmpty) ...[
                              const SizedBox(height: 1),
                              Text(
                                widget.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (widget.trailing != null) widget.trailing!,
                      if (widget.total > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: on
                                ? (all
                                      ? scheme.primary.withValues(alpha: .18)
                                      : scheme.primary.withValues(alpha: .10))
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${widget.selected}/${widget.total}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: on
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 2),
                      AnimatedRotation(
                        turns: _open ? .5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // El cuerpo solo existe abierto: cerrado, el modal se acorta.
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _open
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: widget.children,
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

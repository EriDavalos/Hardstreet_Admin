import 'package:flutter/material.dart';

import '../drive_base.dart' show driveImagePreview;
import '../hs_format.dart';
import 'anim.dart';
import 'common.dart';
import 'drive_thumb.dart';

// ==================================================================
// HARD STREET ADMIN — GALERÍA DE CATEGORÍAS DEL CATÁLOGO
// ==================================================================
// La primera pantalla del módulo PAQUETES: cada categoría (Boda, XV Años,
// Bautizo…) con la foto que la representa, cuántos paquetes tiene y desde qué
// precio salen. Se abre una y se ven SUS paquetes, dentro del mismo módulo.
//
// Estas piezas vivían en un módulo aparte ("Categorías"); ahora son la PORTADA
// del catálogo, así que no hay dos lugares que mantener ni un modal por medio.
//
// El toque de mouse SUBE la tarjeta un poco (como las cards de paquetes), no la
// agranda: en una cuadrícula de portadas el zoom quedaba exagerado.
// ==================================================================

/// Una categoría con sus paquetes (lo que pinta la galería).
class CategoryGroup {
  const CategoryGroup({
    required this.id,
    required this.name,
    this.packages = const [],
  });

  final int id;
  final String name;
  final List<Map<String, dynamic>> packages;

  /// Precio más bajo de sus paquetes (0 = sin precio definido).
  num get minPrice {
    num min = 0;
    for (final p in packages) {
      final price = (p['price'] as num?) ?? 0;
      if (price <= 0) continue;
      if (min == 0 || price < min) min = price;
    }
    return min;
  }

  /// Planes (tiers) que aparecen en sus paquetes, sin repetir.
  List<String> get tiers {
    final out = <String>[];
    for (final p in packages) {
      final t = (p['tierName'] ?? '').toString().trim();
      if (t.isEmpty) continue;
      if (!out.any((x) => x.toLowerCase() == t.toLowerCase())) out.add(t);
    }
    return out;
  }

  /// Foto que representa a la categoría: la del primer paquete que tenga una.
  String? get photo {
    for (final p in packages) {
      final url = (p['urlImage'] ?? '').toString().trim();
      if (url.isNotEmpty) return url;
    }
    return null;
  }
}

/// Las categorías a mostrar: las del catálogo (en su orden) MÁS las que sólo
/// aparecen en los paquetes.
///
/// Así un paquete con una categoría que todavía no está registrada no
/// desaparece de la galería, y una categoría registrada pero sin paquetes se ve
/// igualmente (para poder asignarle uno después).
List<CategoryGroup> hsCategoryGroups({
  required List<Map<String, dynamic>> packages,
  required List<Map<String, dynamic>> categories,
}) {
  int idOf(Map<String, dynamic> pkg) => (pkg['categoryId'] as num?)?.toInt() ?? 0;
  String nameOf(Map<String, dynamic> pkg) {
    final name = (pkg['categoryName'] ?? '').toString().trim();
    return name.isEmpty ? 'Sin categoría' : name;
  }

  final seen = <int>{};
  final out = <CategoryGroup>[];
  for (final c in categories) {
    final id = (c['id'] as num?)?.toInt() ?? 0;
    if (id == 0 || !seen.add(id)) continue;
    final name = (c['name'] ?? '').toString().trim();
    out.add(
      CategoryGroup(id: id, name: name.isEmpty ? 'Sin categoría' : name),
    );
  }
  for (final p in packages) {
    final id = idOf(p);
    if (!seen.add(id)) continue;
    out.add(CategoryGroup(id: id, name: nameOf(p)));
  }
  return [
    for (final c in out)
      CategoryGroup(
        id: c.id,
        name: c.name,
        packages: packages
            .where((p) => idOf(p) == c.id)
            .toList(growable: false),
      ),
  ];
}

/// "1 paquete" o "N paquetes" (el singular se lee raro por todos lados).
String hsCountLabel(int count) =>
    count == 1 ? '1 paquete' : '$count paquetes';

/// Rótulo de un tramo de la galería.
class CategoryGalleryHead extends StatelessWidget {
  const CategoryGalleryHead({
    super.key,
    required this.scheme,
    required this.label,
    required this.hint,
  });

  final ColorScheme scheme;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 2,
            fontWeight: FontWeight.w800,
            color: scheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// Cuadrícula de portadas: las categorías y, si se pide, la de "todo el
/// catálogo" al principio.
class CategoryGalleryGrid extends StatelessWidget {
  const CategoryGalleryGrid({
    super.key,
    required this.categories,
    required this.gold,
    required this.onOpen,
    this.onOpenAll,
    this.total = 0,
    this.minPrice = 0,
  });

  final List<CategoryGroup> categories;
  final Color gold;
  final void Function(CategoryGroup) onOpen;

  /// Opción "Todo el catálogo" (se pinta la primera).
  final VoidCallback? onOpenAll;
  final int total;
  final num minPrice;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        // Portadas de ~230 px que se acomodan solas según el ancho.
        final columns = (box.maxWidth / 230).floor().clamp(1, 5);
        final items = <Widget>[
          if (onOpenAll != null)
            CategoryCoverCard(
              name: 'Todo el catálogo',
              label: 'Todos los paquetes',
              photo: null,
              icon: Icons.apps_rounded,
              price: minPrice,
              count: total,
              gold: gold,
              onTap: onOpenAll!,
            ),
          for (final c in categories)
            CategoryCoverCard(
              name: c.name,
              photo: c.photo,
              price: c.minPrice,
              count: c.packages.length,
              gold: gold,
              onTap: () => onOpen(c),
            ),
        ];
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: columns,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 1.15,
          children: [
            for (var i = 0; i < items.length; i++)
              StaggeredItem(index: i, child: items[i]),
          ],
        );
      },
    );
  }
}

/// Portada de UNA categoría (o de "todo el catálogo"): su foto, su nombre, sus
/// paquetes y desde qué precio salen.
class CategoryCoverCard extends StatelessWidget {
  const CategoryCoverCard({
    super.key,
    required this.name,
    required this.photo,
    required this.price,
    required this.count,
    required this.gold,
    required this.onTap,
    this.label,
    this.icon,
  });

  /// Nombre de la categoría (o "Todo el catálogo").
  final String name;

  /// Foto que la representa (null = ningún paquete tiene foto todavía).
  final String? photo;
  final num price;
  final int count;
  final Color gold;
  final VoidCallback onTap;

  /// Texto del pie, si no es el de siempre ("N paquetes · desde $X").
  final String? label;

  /// Icono del hueco sin foto (por defecto, el emoji de la categoría).
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return CategoryCardLift(
      onTap: onTap,
      radius: 16,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _CategoryCover(photo: photo, gold: gold, name: name, icon: icon),
          // Velo de abajo: la foto se ve y el texto se lee.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Color(0x55000000),
                  Color(0xDD000000),
                ],
                stops: [.3, .62, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: HsCountPill(
                    label: '$count',
                    icon: Icons.photo_library_outlined,
                    color: Colors.white,
                    outlined: true,
                    compact: true,
                  ),
                ),
                const Spacer(),
                Text(
                  icon != null
                      ? name.toUpperCase()
                      : '${hsCategoryEmoji(name)}  ${name.toUpperCase()}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    height: 1.15,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'serif',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label ??
                      (count == 0
                          ? 'Sin paquetes todavía'
                          : price > 0
                          ? '${hsCountLabel(count)} · desde ${hsMoney(price)}'
                          : hsCountLabel(count)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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

/// La FOTO de una categoría (o su hueco con el emoji, si ningún paquete tiene
/// foto todavía: la web, en ese caso, usa una del sitio).
class _CategoryCover extends StatelessWidget {
  const _CategoryCover({
    required this.photo,
    required this.gold,
    required this.name,
    this.icon,
  });

  final String? photo;
  final Color gold;
  final String name;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final src = photo;
    if (src == null || src.trim().isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              gold.withValues(alpha: .30),
              Colors.black.withValues(alpha: .55),
            ],
          ),
        ),
        child: Center(
          child: icon != null
              ? Icon(icon, size: 34, color: Colors.white.withValues(alpha: .9))
              : Text(
                  hsCategoryEmoji(name),
                  style: const TextStyle(fontSize: 40),
                ),
        ),
      );
    }
    return DriveThumb(
      source: driveImagePreview(src, width: 640),
      isRemote: true,
      size: double.infinity,
      big: true,
      rounded: false,
    );
  }
}

/// Etiqueta redonda de la portada (cuántos paquetes).
class HsCountPill extends StatelessWidget {
  const HsCountPill({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    this.outlined = false,
    this.compact = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool outlined;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: outlined ? Colors.black.withValues(alpha: .38) : color,
        borderRadius: BorderRadius.circular(999),
        border: outlined
            ? Border.all(color: Colors.white.withValues(alpha: .45))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: compact ? 12 : 13,
            color: outlined ? Colors.white : Colors.black87,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 10.5 : 11,
              fontWeight: FontWeight.w800,
              letterSpacing: .4,
              color: outlined ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

/// Portada que SUBE un poco y gana sombra al pasar el mouse.
///
/// Es el mismo gesto que las cards de paquetes (`WebPackageCard`) y NO agranda
/// el cuadro: el zoom de antes se veía exagerado en una cuadrícula de portadas.
class CategoryCardLift extends StatefulWidget {
  const CategoryCardLift({
    super.key,
    required this.child,
    required this.onTap,
    required this.radius,
  });

  final Widget child;
  final VoidCallback onTap;
  final double radius;

  @override
  State<CategoryCardLift> createState() => _CategoryCardLiftState();
}

class _CategoryCardLiftState extends State<CategoryCardLift> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hover ? -4 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _hover ? .34 : .18),
              blurRadius: _hover ? 26 : 12,
              offset: Offset(0, _hover ? 12 : 6),
            ),
          ],
        ),
        child: Material(
          color: scheme.surfaceContainerHighest,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(widget.radius),
          child: InkWell(
            onTap: widget.onTap,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

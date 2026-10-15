import 'package:flutter/material.dart';

import '../hs_access.dart';
import '../hs_api.dart';
import '../hs_format.dart';
import '../service_icons.dart';
import '../site_design.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/common.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/form_dialog.dart';
import '../widgets/package_designer.dart';
import '../widgets/service_form_dialog.dart';

// ==================================================================
// MÓDULO PAQUETES (antes "Catálogo"): los paquetes que la web muestra
// en "Nuestros Paquetes", con el MISMO diseño de flyer oscuro con
// acento dorado. Aquí se personalizan: nombre, subtítulo, precio,
// tier, categoría, servicios incluidos e imagen para la web.
// Backend: /api/admin/packages (requiere permiso sobre "Paquetes").
// ==================================================================

/// El look de un tier SEGÚN EL DISEÑO GUARDADO (lo mismo que aplica la web).
///
/// Antes esto salía de [HsTierLook.of] (colores fijos); ahora la paleta la
/// manda el diseñador de tarjetas, así que lo que se ve aquí es exactamente
/// lo que se ve en la página.
HsTierLook _lookFromDesign(SiteDesign design, String tier) {
  final t = design.tierOf(tier);
  final dark = hsHexColor(t.dark);
  return HsTierLook(
    accent: hsHexColor(t.accent),
    accentSoft: hsHexColor(t.accentSoft),
    dark: dark,
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [dark, dark],
    ),
    premium: tier.trim().toLowerCase() == 'premium',
  );
}

/// Icono emoji de la categoría (mismo espíritu que la web).
String _categoryIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('boda')) return '💍';
  if (n.contains('xv')) return '👑';
  if (n.contains('bautizo')) return '🕊️';
  if (n.contains('gradu')) return '🎓';
  if (n.contains('comercial')) return '💼';
  return '📷';
}

class PackagesPage extends StatefulWidget {
  const PackagesPage({super.key});

  @override
  State<PackagesPage> createState() => _PackagesPageState();
}

class _PackagesPageState extends State<PackagesPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _packages = const [];
  List<Map<String, dynamic>> _tiers = const [];
  List<Map<String, dynamic>> _categories = const [];
  List<Map<String, dynamic>> _services = const [];
  String _query = '';

  // Filtro por categoría (como la web: Todos / Boda / XV Años…).
  int? _filterCategory;

  /// Cómo se presenta el catálogo: en CARDS (el diseño de la web, por
  /// defecto) o en FILAS (más compacto, para ver y comparar muchos paquetes
  /// de un vistazo). Mismo conmutador que el Drive.
  bool _byCards = true;

  /// Diseño de las tarjetas guardado para la web (lo edita el diseñador).
  SiteDesign _design = SiteDesign.defaults;

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
      final packages = await HsApi.adminPackages();
      // Los catálogos auxiliares pueden fallar sin tumbar la página.
      SiteDesign design = _design;
      List<Map<String, dynamic>> tiers = const [];
      List<Map<String, dynamic>> categories = const [];
      List<Map<String, dynamic>> services = const [];
      try {
        tiers = await HsApi.tiers();
      } catch (_) {}
      try {
        categories = await HsApi.packageCategories();
      } catch (_) {}
      try {
        services = await HsApi.services();
      } catch (_) {}
      // El diseño de las tarjetas: si falla, se mantiene el último bueno.
      try {
        design = (await HsApi.siteDesign()).design;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _packages = packages;
        _tiers = tiers;
        _categories = categories;
        _services = services;
        _design = design;
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
        _error = 'No se pudo cargar el catálogo de paquetes';
        _loading = false;
      });
    }
  }

  Future<void> _openForm([Map<String, dynamic>? pkg]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PackageFormDialog(
        pkg: pkg,
        tiers: _tiers,
        categories: _categories,
        services: _services,
        gold: hsHexColor(_design.gold),
      ),
    );
    if (saved == true) _reload();
  }

  /// Abre el DISEÑADOR de tarjetas y guarda lo que se elija. El diseño lo
  /// aplica la web en vivo (GET /api/site), sin volver a publicar el sitio.
  Future<void> _openDesigner() async {
    final result = await showPackageDesigner(context, design: _design);
    if (result == null) return;
    try {
      await HsApi.saveSiteDesign(result);
      if (!mounted) return;
      // Solo se adopta como diseño si de verdad se guardó: si el backend
      // falla, el panel sigue mostrando (y la web sigue usando) el anterior.
      setState(() => _design = result);
    } catch (_) {
      // El backend ya avisó con la notificación roja.
    }
    _reload();
  }

  Future<void> _delete(Map<String, dynamic> pkg) async {
    final ok = await confirmDelete(
      context,
      title: '¿Eliminar paquete?',
      message:
          '"${pkg['name'] ?? ''}" dejará de aparecer en el catálogo y en la web. '
          'No se puede eliminar si ya fue asignado a un cliente.',
    );
    if (!ok) return;
    try {
      await HsApi.deletePackage((pkg['id'] as num).toInt());
    } catch (_) {
      // El backend ya avisó con la notificación roja.
    }
    _reload();
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    return _packages.where((p) {
      if (_filterCategory != null &&
          (p['categoryId'] as num?)?.toInt() != _filterCategory) {
        return false;
      }
      if (q.isEmpty) return true;
      final hay = '${p['name'] ?? ''} ${p['subtitle'] ?? ''} '
              '${p['description'] ?? ''} ${p['categoryName'] ?? ''} '
              '${p['tierName'] ?? ''}'
          .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 620;
    final catalogValue =
        _packages.fold<num>(0, (a, p) => a + ((p['price'] as num?) ?? 0));

    return PageContainer(
      title: 'Paquetes',
      description:
          'Personaliza los paquetes que la web muestra en "Nuestros Paquetes": '
          'nombre, precio, servicios incluidos e imagen.',
      icon: Icons.card_giftcard_rounded,
      stats: [
        StatPill(
            icon: Icons.inventory_2_outlined,
            label: '${_packages.length} paquetes'),
        if (_services.isNotEmpty)
          StatPill(
              icon: Icons.miscellaneous_services_outlined,
              label: '${_services.length} servicios'),
        StatPill(icon: Icons.payments_outlined, label: _money(catalogValue)),
      ],
      actions: [
        // "Crear" (create): sin el permiso, el botón no aparece.
        if (HsAccess.instance.degraded ||
            HsAccess.instance.can('Paquetes', 'create'))
          HsActionButton(
            onPressed: () => _openForm(),
            icon: Icons.add_card,
            label: 'Nuevo paquete',
          ),
        // "Diseñar" (update): abre el diseñador de las tarjetas de la web.
        if (HsAccess.instance.degraded ||
            HsAccess.instance.can('Paquetes', 'update'))
          HsActionButton(
            onPressed: _openDesigner,
            icon: Icons.style_outlined,
            label: 'Diseñar cards',
            primary: false,
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Búsqueda + conmutador de vista (cards ⇄ filas).
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, descripción o categoría…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () => setState(() => _query = ''),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: _byCards ? 'Ver como filas' : 'Ver como cards',
                child: IconButton.filledTonal(
                  onPressed: () => setState(() => _byCards = !_byCards),
                  icon: Icon(
                    _byCards
                        ? Icons.view_list_rounded
                        : Icons.grid_view_rounded,
                  ),
                ),
              ),
            ],
          ),
          // Filtros por categoría (chips estilo web) que se envuelven.
          if (_categories.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _filterChip(null, 'Todos'),
                for (final c in _categories)
                  _filterChip(
                    (c['id'] as num).toInt(),
                    (c['name'] ?? '').toString(),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          if (_loading)
            const ListSkeleton(lines: 3, cardHeight: 320)
          else if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.cloud_off_outlined,
                        size: 40, color: scheme.error),
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
            )
          else if (_filtered.isEmpty)
            const EmptyState(
              icon: Icons.card_giftcard_outlined,
              title: 'Sin paquetes',
              message:
                  'No hay paquetes que coincidan. Crea el primero con el botón '
                  '"Nuevo paquete".',
            )
          else if (!_byCards)
            // ===== Vista de FILAS: un paquete por línea, para comparar =====
            Column(
              children: [
                for (var i = 0; i < _filtered.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: StaggeredItem(
                      index: i,
                      child: _PackageRow(
                        pkg: _filtered[i],
                        design: _design,
                        canEdit: HsAccess.instance.degraded ||
                            HsAccess.instance.can('Paquetes', 'update'),
                        canDelete: HsAccess.instance.degraded ||
                            HsAccess.instance.can('Paquetes', 'delete'),
                        onEdit: () => _openForm(_filtered[i]),
                        onDelete: () => _delete(_filtered[i]),
                      ),
                    ),
                  ),
              ],
            )
          else
            LayoutBuilder(builder: (context, box) {
              final cols = box.maxWidth > 1100
                  ? 3
                  : box.maxWidth > 660
                      ? 2
                      : 1;
              return Column(
                children: [
                  for (var i = 0; i < _filtered.length; i += cols)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var j = 0; j < cols; j++) ...[
                            if (j > 0) const SizedBox(width: 14),
                            Expanded(
                              child: (i + j) < _filtered.length
                                  ? StaggeredItem(
                                      index: i + j,
                                      child: _WebPackageCard(
                                        pkg: _filtered[i + j],
                                        design: _design,
                                        canEdit: HsAccess.instance.degraded ||
                                            HsAccess.instance
                                                .can('Paquetes', 'update'),
                                        canDelete: HsAccess.instance.degraded ||
                                            HsAccess.instance
                                                .can('Paquetes', 'delete'),
                                        onEdit: () =>
                                            _openForm(_filtered[i + j]),
                                        onDelete: () =>
                                            _delete(_filtered[i + j]),
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              );
            }),
          if (compact) const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _filterChip(int? id, String label) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _filterCategory == id;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => setState(() => _filterCategory = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? hsHexColor(_design.gold).withValues(alpha: .16)
              : scheme.surfaceContainerHighest.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? hsHexColor(_design.gold).withValues(alpha: .65)
                : scheme.outlineVariant.withValues(alpha: .5),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected
                ? hsHexColor(_design.gold)
                : scheme.onSurfaceVariant,
            letterSpacing: selected ? .4 : 0,
          ),
        ),
      ),
    );
  }

  String _money(num v) {
    final s = v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
    final parts = s.split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
    return 'MXN \$$intPart${parts.length > 1 ? '.${parts[1]}' : ''}';
  }
}

/// Tarjeta de paquete con el diseño EXACTO de la web (renderPackageCard):
/// flyer oscuro con línea superior degradada dorada, badge de tier,
/// categoría con icono, nombre, subtítulo en itálica, lista de servicios
/// con iconos, precio "Desde" y CTA con borde dorado.
class _WebPackageCard extends StatefulWidget {
  const _WebPackageCard({
    required this.pkg,
    required this.design,
    required this.onEdit,
    required this.onDelete,
    required this.canEdit,
    required this.canDelete,
  });

  final Map<String, dynamic> pkg;

  /// Diseño guardado de las tarjetas: manda la paleta y qué se muestra. Es el
  /// mismo documento que aplica la web, así que el panel no "inventa" un look.
  final SiteDesign design;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool canEdit;
  final bool canDelete;

  @override
  State<_WebPackageCard> createState() => _WebPackageCardState();
}

class _WebPackageCardState extends State<_WebPackageCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final pkg = widget.pkg;
    final tier = (pkg['tierName'] ?? '').toString();
    // Cada tier tiene su propio look (Premium = oro sobre negro,
    // Gold = ámbar cálido, Basic = acero frío) para distinguirlo de un
    // vistazo. La paleta sale del DISEÑO guardado, no de valores fijos.
    final card = widget.design.card;
    final tierLook = widget.design.tierOf(tier);
    final look = _lookFromDesign(widget.design, tier);
    // El relleno del diseñador es para el ancho de la web (1 columna); aquí la
    // tarjeta vive en una rejilla, así que se escala sin perder la proporción.
    final pad = (card.padding * .62).clamp(12.0, 30.0);
    final services = ((pkg['serviceNames'] as List?) ?? const [])
        .map((s) => s.toString())
        .where((s) => s.isNotEmpty)
        .toList();
    // Cuántos servicios se listan antes de resumir en "+N más…" (0 = todos).
    final shownServices =
        card.servicesLimit <= 0 ? services.length : card.servicesLimit;
    final categoryName = (pkg['categoryName'] ?? '').toString();
    final price = (pkg['price'] as num?) ?? 0;
    final currency = (pkg['currency'] ?? 'MXN').toString();

    final s = price.toStringAsFixed(price.truncateToDouble() == price ? 0 : 2);
    final parts = s.split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
    final priceLabel = '\$$intPart${parts.length > 1 ? '.${parts[1]}' : ''}';

    final canEdit = widget.canEdit;
    final canDelete = widget.canDelete;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        // Hover (solo desktop): se eleva como .package-card:hover de la web.
        transform: Matrix4.translationValues(
            0, _hover && card.hoverLift ? -6 : 0, 0),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: look.dark,
            borderRadius: BorderRadius.circular(card.radius),
            border: Border.all(
              color: card.borderWidth <= 0
                  ? Colors.transparent
                  : look.accent.withValues(alpha: tierLook.borderAlpha),
              width: card.borderWidth,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Línea superior degradada dorada (el ::before de la web).
              if (card.lineTop)
                Container(
                  height: 2.2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        look.premium ? look.accentSoft : look.accent,
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 14, pad, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ===== Badge de tier + acciones =====
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),                          decoration: BoxDecoration(
                            gradient: tierLook.badgeFilled
                                ? LinearGradient(
                                    colors: [look.accent, look.accentSoft])
                                : null,
                            color: tierLook.badgeFilled
                                ? null
                                : look.accent.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(6),
                            border: tierLook.badgeFilled
                                ? null
                                : Border.all(
                                    color: look.accent.withValues(alpha: .35)),
                          ),
                          child: Text(
                            tier.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 2,
                              fontWeight: FontWeight.w800,
                              color: tierLook.badgeFilled
                                  ? look.dark
                                  : look.accentSoft,
                            ),
                          ),
                        ),
                        const Spacer(),
                        // CELULAR: las acciones del paquete van en el menú "⋮"
                        // (en escritorio se mantienen los botones fantasma).
                        // Sin permisos para ninguna, el menú NO se dibuja.
                        if (hsRowCompact(context))
                          HsRowMenu(
                            actions: [
                              HsMenuAction(
                                icon: Icons.tune_rounded,
                                label: 'Personalizar',
                                onTap: canEdit ? widget.onEdit : null,
                              ),
                              HsMenuAction(
                                icon: Icons.delete_outline_rounded,
                                label: 'Eliminar',
                                onTap: canDelete ? widget.onDelete : null,
                                destructive: true,
                              ),
                            ],
                          )
                        else ...[
                          if (canDelete)
                            _IconGhost(
                              icon: Icons.delete_outline_rounded,
                              onTap: widget.onDelete,
                            ),
                          if (canEdit) ...[
                            const SizedBox(width: 6),
                            _IconGhost(
                              icon: Icons.tune_rounded,
                              onTap: widget.onEdit,
                            ),
                          ],
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    // ===== Categoría con icono =====
                    if (card.showCategory)
                    Row(
                      children: [
                        Text(_categoryIcon(categoryName),
                            style: const TextStyle(fontSize: 15)),
                        const SizedBox(width: 8),
                        Text(
                          categoryName.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10.5,
                            letterSpacing: 2.2,
                            fontWeight: FontWeight.w700,
                            color: look.accent.withValues(alpha: .85),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // ===== Nombre + subtítulo (estilo web serif/itálica) =====
                    Text(
                      card.uppercaseNames
                          ? (pkg['name'] ?? '').toString().toUpperCase()
                          : (pkg['name'] ?? '').toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.2,
                        fontFamily: card.serifNames ? 'serif' : null,
                      ),
                    ),
                    if (card.showSubtitle &&
                        (pkg['subtitle'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        (pkg['subtitle'] ?? '').toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontStyle: FontStyle.italic,
                          color: Colors.white.withValues(alpha: .55),
                        ),
                      ),
                    ],
                    if ((pkg['description'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        (pkg['description'] ?? '').toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: Colors.white.withValues(alpha: .45),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: .07),
                    ),
                    const SizedBox(height: 10),
                    // ===== Servicios incluidos =====
                    if (card.showServiceCount)
                    Text(
                      '${services.length} servicio${services.length == 1 ? '' : 's'} incluido${services.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: .45),
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (card.showServices)
                      for (final name in services.take(shownServices))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_rounded,
                                size: 15,
                                color: look.accent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.35,
                                    color: Colors.white.withValues(alpha: .78),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    if (card.showServices && services.length > shownServices)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '+${services.length - shownServices} más…',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontStyle: FontStyle.italic,
                            color: Colors.white.withValues(alpha: .4),
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
              // ===== Footer: precio + CTA (fondo tintado como la web) =====
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                decoration: BoxDecoration(
                  color: look.accent.withValues(alpha: .05),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: .07),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // El precio se oculta si el diseño lo apaga; el botón del
                    // pie es la acción del PANEL (Personalizar), no el CTA de la
                    // web — ese se diseña en el diseñador.
                    if (!card.showPrice) const Spacer(),
                    if (card.showPrice)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.priceLabel,
                            style: TextStyle(
                              fontSize: 10.5,
                              letterSpacing: 1.5,
                              fontStyle: FontStyle.italic,
                              color: Colors.white.withValues(alpha: .45),
                            ),
                          ),
                          Text(
                            priceLabel,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: look.accent,
                              fontFamily: 'serif',
                            ),
                          ),
                          Text(
                            currency,
                            style: TextStyle(
                              fontSize: 10.5,
                              letterSpacing: 1.2,
                              color: Colors.white.withValues(alpha: .4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // CTA "Personalizar": borde dorado, como .pkg-cta.
                    OutlinedButton.icon(
                      onPressed: canEdit ? widget.onEdit : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: look.accentSoft,
                        side: BorderSide(
                          color: look.accent.withValues(
                              alpha: canEdit ? .75 : .25),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 11.5,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      icon: const Icon(Icons.tune_rounded, size: 15),
                      label: const Text('PERSONALIZAR'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// FILA de paquete: la versión compacta del flyer.
///
/// Mismos colores y tipografías que el card (tier, categoría, nombre y precio),
/// pero en UNA línea, para recorrer y comparar todo el catálogo de un vistazo
/// sin perder el diseño de la web.
class _PackageRow extends StatefulWidget {
  const _PackageRow({
    required this.pkg,
    required this.design,
    required this.onEdit,
    required this.onDelete,
    required this.canEdit,
    required this.canDelete,
  });

  final Map<String, dynamic> pkg;

  /// Diseño guardado de las tarjetas (la fila usa la misma paleta).
  final SiteDesign design;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool canEdit;
  final bool canDelete;

  @override
  State<_PackageRow> createState() => _PackageRowState();
}

class _PackageRowState extends State<_PackageRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final pkg = widget.pkg;
    final card = widget.design.card;
    final look =
        _lookFromDesign(widget.design, (pkg['tierName'] ?? '').toString());
    final tierAlpha = widget.design
        .tierOf((pkg['tierName'] ?? '').toString())
        .borderAlpha;
    final services = ((pkg['serviceNames'] as List?) ?? const [])
        .map((s) => s.toString())
        .where((s) => s.isNotEmpty)
        .toList();
    final categoryName = (pkg['categoryName'] ?? '').toString();
    final subtitle = (pkg['subtitle'] ?? '').toString();
    final price = (pkg['price'] as num?) ?? 0;
    final currency = (pkg['currency'] ?? 'MXN').toString();
    final priceLabel = hsMoney(price, '').trim();
    final compact = hsRowCompact(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(
            0, _hover && card.hoverLift ? -2 : 0, 0),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: look.dark,
          borderRadius: BorderRadius.circular(card.radius.clamp(6, 22)),
          border: Border.all(
            color: card.borderWidth <= 0
                ? Colors.transparent
                : look.accent.withValues(
                    alpha: _hover
                        ? tierAlpha.clamp(.2, 1)
                        : (tierAlpha * .55).clamp(.08, 1),
                  ),
            width: card.borderWidth,
          ),
        ),
        child: Row(
          children: [
            // Barra de acento del tier (la "línea" del flyer, ahora vertical).
            Container(width: 3, height: 72, color: look.accent),
            const SizedBox(width: 14),
            // Icono de la categoría.
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: look.accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: look.accent.withValues(alpha: .28)),
              ),
              child: Text(_categoryIcon(categoryName),
                  style: const TextStyle(fontSize: 17)),
            ),
            const SizedBox(width: 12),
            // Categoría + nombre + subtítulo.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (card.showCategory)
                      Flexible(
                        child: Text(
                          // La categoría va SIEMPRE en mayúsculas: así la pinta
                          // la web (.pkg-category-name); el interruptor del
                          // diseñador solo afecta al NOMBRE del paquete.
                          categoryName.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.8,
                            fontWeight: FontWeight.w700,
                            color: look.accent.withValues(alpha: .9),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: look.accent.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          (pkg['tierName'] ?? '').toString().toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w800,
                            color: look.accentSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    card.uppercaseNames
                        ? (pkg['name'] ?? '').toString().toUpperCase()
                        : (pkg['name'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontFamily: card.serifNames ? 'serif' : null,
                    ),
                  ),
                  if (card.showSubtitle && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: Colors.white.withValues(alpha: .5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Servicios incluidos (solo si hay espacio).
            if (!compact && card.showServices)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline_rounded,
                        size: 15, color: look.accent.withValues(alpha: .8)),
                    const SizedBox(width: 6),
                    Text(
                      '${services.length}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white.withValues(alpha: .8),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      services.length == 1 ? 'servicio' : 'servicios',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: .45),
                      ),
                    ),
                  ],
                ),
              ),
            // Precio (si el diseño lo apaga, no se reserva el hueco).
            if (card.showPrice)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  card.priceLabel,
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 1.2,
                    fontStyle: FontStyle.italic,
                    color: Colors.white.withValues(alpha: .45),
                  ),
                ),
                Text(
                  priceLabel,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: look.accent,
                    fontFamily: 'serif',
                  ),
                ),
                Text(
                  currency,
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 1,
                    color: Colors.white.withValues(alpha: .4),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            // Acciones (mismo criterio que el card: ⋮ en móvil).
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: compact
                  ? HsRowMenu(
                      actions: [
                        HsMenuAction(
                          icon: Icons.tune_rounded,
                          label: 'Personalizar',
                          onTap: widget.canEdit ? widget.onEdit : null,
                        ),
                        HsMenuAction(
                          icon: Icons.delete_outline_rounded,
                          label: 'Eliminar',
                          onTap: widget.canDelete ? widget.onDelete : null,
                          destructive: true,
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.canDelete)
                          _IconGhost(
                            icon: Icons.delete_outline_rounded,
                            onTap: widget.onDelete,
                          ),
                        if (widget.canEdit) ...[
                          const SizedBox(width: 6),
                          _IconGhost(
                            icon: Icons.tune_rounded,
                            onTap: widget.onEdit,
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
}

/// Botón fantasma (icono) sobre el flyer oscuro.
class _IconGhost extends StatelessWidget {
  const _IconGhost({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 17,
          color: Colors.white.withValues(alpha: .55),
        ),
      ),
    );
  }
}

/// Diálogo de alta/edición de paquete con el diseño estándar (FormDialog).
/// Aquí se PERSONALIZA el paquete: datos, precio, tier, categoría,
/// servicios incluidos (chips) e imagen para la web.
class _PackageFormDialog extends StatefulWidget {
  const _PackageFormDialog({
    this.pkg,
    required this.tiers,
    required this.categories,
    required this.services,
    required this.gold,
  });

  final Map<String, dynamic>? pkg;
  final List<Map<String, dynamic>> tiers;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> services;

  /// Dorado de la marca SEGÚN EL DISEÑO guardado (minivista previa).
  final Color gold;

  @override
  State<_PackageFormDialog> createState() => _PackageFormDialogState();
}

class _PackageFormDialogState extends State<_PackageFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _subtitle;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _urlImage;
  int? _tierId;
  int? _categoryId;
  bool _isExtern = false;
  final Set<int> _serviceIds = {};
  bool _saving = false;
  String? _error;

  /// Catálogo de servicios EDITABLE desde el diálogo (se puede agregar uno
  /// nuevo sin salir a la pestaña Servicios).
  late List<Map<String, dynamic>> _services;

  /// Filtro de la pestaña Servicios.
  final TextEditingController _serviceQuery = TextEditingController();

  /// Pestaña del diálogo: 0 = Datos, 1 = Servicios (como el administrador).
  int _tab = 0;

  bool get _editing => widget.pkg != null;

  @override
  void initState() {
    super.initState();
    final p = widget.pkg ?? const {};
    _name = TextEditingController(text: (p['name'] ?? '').toString());
    _subtitle = TextEditingController(text: (p['subtitle'] ?? '').toString());
    _description =
        TextEditingController(text: (p['description'] ?? '').toString());
    _price = TextEditingController(
      text: p['price'] == null
          ? ''
          : (p['price'] as num).toStringAsFixed(
              (p['price'] as num).truncateToDouble() == p['price'] ? 0 : 2,
            ),
    );
    _urlImage = TextEditingController(text: (p['urlImage'] ?? '').toString());
    _tierId = p['tierId'] is int ? p['tierId'] as int : null;
    _categoryId = p['categoryId'] is int ? p['categoryId'] as int : null;
    _isExtern = p['isExtern'] == true;
    for (final id in ((p['serviceIds'] as List?) ?? const [])) {
      final v = (id as num?)?.toInt();
      if (v != null) _serviceIds.add(v);
    }
    _services = List.of(widget.services);
  }

  @override
  void dispose() {
    _name.dispose();
    _subtitle.dispose();
    _description.dispose();
    _price.dispose();
    _urlImage.dispose();
    _serviceQuery.dispose();
    super.dispose();
  }

  /// Abre el diálogo de NUEVO servicio y, al crearlo, refresca el catálogo y
  /// deja seleccionado el servicio recién agregado.
  Future<void> _addService() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ServiceFormDialog(),
    );
    if (created != true || !mounted) return;
    final before = _services.map((s) => (s['id'] as num).toInt()).toSet();
    try {
      final list = await HsApi.services();
      if (!mounted) return;
      setState(() {
        _services = list;
        for (final s in list) {
          final id = (s['id'] as num).toInt();
          if (!before.contains(id)) _serviceIds.add(id);
        }
      });
    } catch (_) {
      // Sin catálogo actualizado el diálogo sigue siendo utilizable.
    }
  }

  String _tierName(int? id) {
    if (id == null) return '';
    for (final t in widget.tiers) {
      if ((t['id'] as num).toInt() == id) return (t['name'] ?? '').toString();
    }
    return '';
  }

  String _categoryName(int? id) {
    if (id == null) return '';
    for (final c in widget.categories) {
      if ((c['id'] as num).toInt() == id) return (c['name'] ?? '').toString();
    }
    return '';
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    // Si falta algo de la pestaña Datos, se regresa a ella con el motivo.
    if (name.isEmpty) {
      setState(() {
        _tab = 0;
        _error = 'Escribe el nombre del paquete';
      });
      return;
    }
    if (_tierId == null) {
      setState(() {
        _tab = 0;
        _error = 'Selecciona el tier (Premium/Gold/Basic)';
      });
      return;
    }
    if (_categoryId == null) {
      setState(() {
        _tab = 0;
        _error = 'Selecciona la categoría del paquete';
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = <String, dynamic>{
      'name': name,
      'subtitle': _subtitle.text.trim(),
      'description': _description.text.trim(),
      'price': num.tryParse(_price.text.replaceAll(',', '')) ?? 0,
      'currency': 'MXN',
      'id_tier': _tierId,
      'id_package_category': _categoryId,
      'is_extern': _isExtern,
      'url_image': _urlImage.text.trim(),
      'serviceIds': _serviceIds.toList(growable: false),
    };
    try {
      if (_editing) {
        await HsApi.updatePackage(
            {'id': (widget.pkg!['id'] as num).toInt(), ...body});
      } else {
        await HsApi.createPackage(body);
      }
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
          _error = 'No se pudo guardar el paquete';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FormDialog(
      icon: _editing ? Icons.tune_rounded : Icons.add_card,
      title: _editing ? 'Personalizar paquete' : 'Nuevo paquete',
      subtitle:
          'Este paquete aparece en la web ("Nuestros Paquetes") y se asigna a clientes.',
      saving: _saving,
      error: _error,
      saveLabel: _editing ? 'Guardar cambios' : 'Crear paquete',
      maxWidth: 560,
      onCancel: () => Navigator.of(context).pop(false),
      onSave: _save,
      children: [
        // Vista previa EN VIVO del flyer del paquete (se actualiza al
        // escribir): hace la personalización visual e intuitiva.
        _previewCard(scheme),
        const SizedBox(height: 14),
        // Pestañas HORIZONTALES (mismo lenguaje que el administrador del
        // paquete): Datos y Servicios, con el contador de seleccionados.
        Row(
          children: [
            Expanded(
              child: _FormTabButton(
                icon: Icons.tune_rounded,
                label: 'Datos',
                selected: _tab == 0,
                onTap: () => setState(() => _tab = 0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _FormTabButton(
                icon: Icons.checklist_rtl,
                label: 'Servicios',
                badge: '${_serviceIds.length}',
                selected: _tab == 1,
                onTap: () => setState(() => _tab = 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_tab == 1) ...[
          _servicesSection(scheme),
        ] else ...[
        FormSection(
          label: 'Datos del paquete',
          child: Column(
            children: [
              TextField(
                controller: _name,
                autofocus: !_editing,
                onChanged: (_) => setState(() {}),
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  prefixIcon: Icon(Icons.card_giftcard_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subtitle,
                onChanged: (_) => setState(() {}),
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Subtítulo (corto, para la tarjeta)',
                  prefixIcon: Icon(Icons.short_text, size: 20),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes, size: 20),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FormSection(
          label: 'Precio',
          child: TextField(
            controller: _price,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Precio (MXN)',
              prefixIcon: Icon(Icons.payments_outlined, size: 20),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FormSection(
          label: 'Clasificación',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _tierId,
                      decoration: const InputDecoration(
                        labelText: 'Tier',
                        prefixIcon: Icon(Icons.military_tech_outlined, size: 20),
                      ),
                      items: [
                        for (final t in widget.tiers)
                          DropdownMenuItem<int>(
                            value: (t['id'] as num).toInt(),
                            child: Text((t['name'] ?? '').toString()),
                          ),
                      ],
                      onChanged: (v) => setState(() => _tierId = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _categoryId,
                      decoration: const InputDecoration(
                        labelText: 'Categoría',
                        prefixIcon: Icon(Icons.category_outlined, size: 20),
                      ),
                      items: [
                        for (final c in widget.categories)
                          DropdownMenuItem<int>(
                            value: (c['id'] as num).toInt(),
                            child: Text((c['name'] ?? '').toString()),
                          ),
                      ],
                      onChanged: (v) => setState(() => _categoryId = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _isExtern,
                onChanged: (v) => setState(() => _isExtern = v ?? false),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Paquete externo (servicio destacado de la web)',
                  style: TextStyle(fontSize: 13.5),
                ),
                subtitle: const Text(
                  'Los externos aparecen en el carrusel "Nuestros servicios".',
                  style: TextStyle(fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FormSection(
          label: 'Imagen para la web (opcional)',
          child: TextField(
            controller: _urlImage,
            decoration: const InputDecoration(
              labelText: 'Ruta de imagen (ej. images/banner.jpg)',
              prefixIcon: Icon(Icons.image_outlined, size: 20),
            ),
          ),
        ),
        ], // fin de la pestaña Datos
      ],
    );
  }

  /// Vista previa EN VIVO del paquete: refleja lo que se escribe en el
  /// formulario (nombre, subtítulo, precio, clasificación y servicios).
  Widget _previewCard(ColorScheme scheme) {
    final name = _name.text.trim();
    final subtitle = _subtitle.text.trim();
    final price = num.tryParse(_price.text.replaceAll(',', '')) ?? 0;
    final tier = _tierName(_tierId);
    final category = _categoryName(_categoryId);
    final soft = Colors.white.withValues(alpha: .55);
    final gold = widget.gold;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1C2433), Color(0xFF0F1420)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: gold.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (tier.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                  decoration: BoxDecoration(
                    color: gold.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: gold.withValues(alpha: .5)),
                  ),
                  child: Text(
                    tier.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9.5,
                      letterSpacing: 1.3,
                      fontWeight: FontWeight.w800,
                      color: gold,
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                price > 0 ? hsMoney(price) : 'Sin precio',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: gold,
                  fontFamily: 'serif',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            name.isEmpty ? 'Nombre del paquete' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: name.isEmpty ? soft : Colors.white,
            ),
          ),
          if (subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFFB9C2D0)),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.category_outlined, size: 13, color: soft),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  category.isEmpty ? 'Sin categoría' : category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: soft),
                ),
              ),
              const SizedBox(width: 14),
              Icon(Icons.checklist_rtl, size: 13, color: soft),
              const SizedBox(width: 6),
              Text(
                '${_serviceIds.length} servicios',
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700, color: soft),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Contenido de la pestaña Servicios: buscador + AGREGAR servicio + lista
  /// seleccionable. El "Agregar" crea un servicio del catálogo sin salir.
  Widget _servicesSection(ColorScheme scheme) {
    final q = _serviceQuery.text.trim().toLowerCase();
    final list = q.isEmpty
        ? _services
        : _services.where((s) {
            final hay =
                '${s['name'] ?? ''} ${s['description'] ?? ''}'.toLowerCase();
            return hay.contains(q);
          }).toList();
    return FormSection(
      label: 'Servicios incluidos',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _serviceQuery,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Buscar servicio…',
                    prefixIcon: Icon(Icons.search, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _addService,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Agregar'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_serviceIds.length} de ${_services.length} seleccionados',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .3,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (_serviceIds.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _serviceIds.clear()),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                  ),
                  child: const Text('Limpiar',
                      style: TextStyle(fontSize: 11.5)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (_services.isEmpty)
            Text(
              'No hay servicios registrados. Usa "Agregar" para crear el '
              'primero.',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            )
          else if (list.isEmpty)
            Text(
              'Ningún servicio coincide con "$q".',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            )
          else
            // Column (no ListView): el diálogo mide intrínsecos y un viewport
            // shrink-wrap los rechaza.
            for (final s in list) _servicePickRow(s, scheme),
        ],
      ),
    );
  }

  /// Fila de la lista de servicios de la pestaña: una tarjeta VISUAL con
  /// icono, nombre, descripción y un check a la derecha.
  Widget _servicePickRow(Map<String, dynamic> s, ColorScheme scheme) {
    final id = (s['id'] as num).toInt();
    final selected = _serviceIds.contains(id);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        setState(() {
          if (!_serviceIds.add(id)) _serviceIds.remove(id);
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.brand.withValues(alpha: .10)
              : scheme.surfaceContainerHighest.withValues(alpha: .25),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.brand.withValues(alpha: .60)
                : scheme.outlineVariant.withValues(alpha: .45),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (selected ? AppColors.brand : scheme.onSurfaceVariant)
                    .withValues(alpha: selected ? .16 : .10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                serviceIconOf((s['icon'] ?? '').toString()),
                size: 19,
                color: selected ? AppColors.brand : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (s['name'] ?? 'Servicio').toString(),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  if ((s['description'] ?? '').toString().trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        (s['description'] ?? '').toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.25,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: selected ? AppColors.brand : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.brand : scheme.outlineVariant,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 15, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Botón de pestaña del diálogo (Datos / Servicios): horizontal, compacto y
/// a prueba de desbordes (escala si el ancho no alcanza).
class _FormTabButton extends StatelessWidget {
  const _FormTabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.brand.withValues(alpha: .12)
              : scheme.surfaceContainerHighest.withValues(alpha: .30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.brand.withValues(alpha: .5)
                : scheme.outlineVariant.withValues(alpha: .45),
          ),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 16,
                    color: selected
                        ? AppColors.brand
                        : scheme.onSurfaceVariant),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.brand : scheme.onSurface,
                  ),
                ),
                if (badge != null && badge != '0') ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.brand.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brand,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

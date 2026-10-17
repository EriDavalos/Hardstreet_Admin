import 'dart:async';

import 'package:flutter/material.dart';

import '../app_constants.dart';
import '../drive_api_service.dart' show DriveApiService;
import '../drive_base.dart' show driveImagePreview, drivePublicUrl;
import '../drive_scope.dart';
import '../hs_access.dart';
import '../hs_api.dart';
import '../hs_format.dart';
import '../service_icons.dart';
import '../site_design.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/category_gallery.dart';
import '../widgets/common.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/drive_photo_picker.dart';
import '../widgets/drive_thumb.dart';
import '../widgets/form_dialog.dart';
import '../widgets/hs_toast.dart';
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

/// ¿El paquete tiene foto propia (`url_image`)?
bool _hasPhoto(Map<String, dynamic> pkg) =>
    (pkg['urlImage'] ?? '').toString().trim().isNotEmpty;

/// URL con la que el PANEL pinta la foto de un paquete.
///
/// Es la MISMA foto que ve la web (`url_image`), pedida al servidor del drive
/// en tamaño de tarjeta (`/thumb/<ruta>?w=N`) y con el token de la sesión,
/// porque una imagen no puede mandar cabeceras y sin él el servidor contesta
/// 403: por eso las fotos "no cargaban" en el catálogo.
String _photoSource(Map<String, dynamic> pkg, {int width = 640}) =>
    driveImagePreview((pkg['urlImage'] ?? '').toString(), width: width);

/// Foto del paquete en BANDA (arriba de la tarjeta), igual que la web:
/// ancho completo, alto del diseño y recorte tipo `object-fit: cover`.
///
/// Sin foto queda el hueco visible con su rótulo: la web, en ese caso, usa una
/// de las fotos del sitio (el pool de `images/…`), que el panel no puede
/// abrir desde aquí.
Widget _photoBand(Map<String, dynamic> pkg, Color accent, double height) {
  if (_hasPhoto(pkg)) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: DriveThumb(
        source: _photoSource(pkg),
        isRemote: true,
        size: double.infinity,
        big: true,
        rounded: false,
      ),
    );
  }
  return Container(
    height: height,
    width: double.infinity,
    decoration: BoxDecoration(gradient: _photoFallbackGradient(accent)),
    alignment: Alignment.center,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.image_outlined,
          size: 20,
          color: accent.withValues(alpha: .9),
        ),
        const SizedBox(height: 3),
        Text(
          'Sin foto · la web usa una del sitio',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: .6,
            fontWeight: FontWeight.w700,
            color: accent.withValues(alpha: .9),
          ),
        ),
      ],
    ),
  );
}

/// El hueco (degradado) que se ve mientras NO hay foto que enseñar.
LinearGradient _photoFallbackGradient(Color accent) => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [accent.withValues(alpha: .26), Colors.black.withValues(alpha: .35)],
);

/// Miniatura de la foto del paquete, para la vista de filas.
Widget _photoThumb(Map<String, dynamic> pkg, Color accent) {
  final hasPhoto = _hasPhoto(pkg);
  return SizedBox(
    width: 46,
    height: 52,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: hasPhoto
          ? DriveThumb(
              source: _photoSource(pkg, width: 160),
              isRemote: true,
              size: double.infinity,
              big: true,
              rounded: false,
            )
          : Container(
              decoration: BoxDecoration(
                gradient: _photoFallbackGradient(accent),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.image_outlined,
                size: 17,
                color: accent.withValues(alpha: .9),
              ),
            ),
    ),
  );
}

/// Foto de FONDO en la tarjeta del catálogo, si el diseño la pide ahí.
///
/// Es EXACTAMENTE lo que emite la web: la foto a todo color con
/// `background-size: cover` y, encima, el degradado `hsPhotoFade` con la fuerza
/// del diseño (`card.imageFade`).
///
/// El degradado es NEGRO (no el color oscuro del tier): sobre la foto, un velo
/// negro es lo que hace resaltar las letras, y así el mismo diseño se ve en la
/// web (`site.js`) sin depender de la paleta de cada tier.
Widget _photoBackdrop(
  SiteCardDesign card,
  Map<String, dynamic> pkg,
  Color accent,
  Color dark,
  Widget child,
) {
  if (card.imageMode != 'bg') return child;
  return Stack(
    children: [
      Positioned.fill(
        child: _hasPhoto(pkg)
            ? DriveThumb(
                source: _photoSource(pkg),
                isRemote: true,
                size: double.infinity,
                big: true,
                rounded: false,
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: _photoFallbackGradient(accent),
                ),
              ),
      ),
      Positioned.fill(
        child: hsPhotoFadeOverlay(kPhotoFadeColor, card.imageFade),
      ),
      child,
    ],
  );
}

/// Tamaño MÁXIMO de una tarjeta de paquete (ancho × alto).
///
/// En pantallas anchas las tarjetas NO se estiran sin fin: se quedan en formato
/// de flyer (2:3) y el listado sigue leyéndose. Lo que sobra de contenido
/// (una lista de servicios muy larga) se recorta a lo alto del máximo, con el
/// pie del precio siempre a la vista.
const double kPackageCardMaxWidth = 450;
const double kPackageCardMaxHeight = 675;

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

  /// Nivel del módulo: la GALERÍA de categorías (con lo que arranca) o la
  /// lista de paquetes de UNA categoría. `_allPackages` marca la lista
  /// COMPLETA ("Todo el catálogo"), que es la otra salida de la galería.
  ///
  /// Los dos niveles viven en el MISMO módulo (antes las categorías eran un
  /// módulo aparte y sus paquetes se veían en un modal).
  bool _allPackages = false;
  int? _categoryId;

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
      // La WEB no tiene sesión: se le publican en el servidor del drive las
      // fotos de los paquetes (las que están en el Drive) para que pueda
      // abrirlas. Va sin esperar: si el servidor es viejo o no hay red, el
      // catálogo se ve igual en el panel.
      unawaited(
        DriveApiService.publishPublicPhotos(
          'paquetes',
          packages.map((p) => p['urlImage']),
        ),
      );
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
        // Al crear desde dentro de una categoría, el paquete nace EN ESA
        // categoría (no hay que volver a elegirla).
        initialCategory: pkg == null ? _activeCategory : null,
      ),
    );
    if (saved == true) _reload();
  }

  /// Crea una categoría del catálogo (p. ej. "Bautizo") desde la galería.
  Future<void> _openCategoryForm() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CategoryFormDialog(),
    );
    if (saved == true && mounted) _reload();
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

  /// ¿Se está viendo la GALERÍA de categorías?
  bool get _showsGallery => !_allPackages && _categoryId == null;

  /// Categoría cuyos paquetes se están viendo (null = "Todo el catálogo").
  int? get _activeCategory => _allPackages ? null : _categoryId;

  /// Abre los paquetes de una categoría (dentro del mismo módulo).
  void _openCategory(int id) => setState(() {
    _categoryId = id;
    _allPackages = false;
    _query = '';
  });

  /// Muestra TODO el catálogo de una vez (la opción de la galería).
  void _openAllPackages() => setState(() {
    _allPackages = true;
    _categoryId = null;
    _query = '';
  });

  /// Vuelve a la galería de categorías.
  void _backToGallery() => setState(() {
    _allPackages = false;
    _categoryId = null;
    _query = '';
  });

  /// Nombre de la categoría abierta (o "Todo el catálogo").
  String get _levelTitle {
    if (_allPackages || _categoryId == null) return 'Todo el catálogo';
    // Los paquetes sin categoría asignada salen como su propio grupo.
    if (_categoryId == 0) return 'Sin categoría';
    for (final c in _categories) {
      if ((c['id'] as num?)?.toInt() == _categoryId) {
        return (c['name'] ?? '').toString();
      }
    }
    return 'Categoría';
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    final cat = _activeCategory;
    return _packages.where((p) {
      if (cat != null && (p['categoryId'] as num?)?.toInt() != cat) {
        return false;
      }
      if (q.isEmpty) return true;
      final hay =
          '${p['name'] ?? ''} ${p['subtitle'] ?? ''} '
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
    final catalogValue = _packages.fold<num>(
      0,
      (a, p) => a + ((p['price'] as num?) ?? 0),
    );
    final gallery = _showsGallery;
    final groups = hsCategoryGroups(
      packages: _packages,
      categories: _categories,
    );
    final canCreate =
        HsAccess.instance.degraded ||
        HsAccess.instance.can('Paquetes', 'create');

    return PageContainer(
      title: 'Paquetes',
      description: gallery
          ? 'Las categorías del catálogo: abre una y ves (y editas) sus '
                'paquetes sin salir de aquí.'
          : 'Personaliza los paquetes que la web muestra en "Nuestros '
                'Paquetes": nombre, precio, servicios incluidos e imagen.',
      icon: Icons.card_giftcard_rounded,
      stats: gallery
          ? [
              StatPill(
                icon: Icons.category_outlined,
                label:
                    '${groups.length} '
                    '${groups.length == 1 ? 'categoría' : 'categorías'}',
              ),
              StatPill(
                icon: Icons.inventory_2_outlined,
                label: '${_packages.length} paquetes',
              ),
              StatPill(
                icon: Icons.image_outlined,
                label:
                    '${groups.where((c) => c.photo != null).length} con foto',
              ),
            ]
          : [
              StatPill(
                icon: Icons.inventory_2_outlined,
                label: '${_filtered.length} de ${_packages.length} paquetes',
              ),
              if (_services.isNotEmpty)
                StatPill(
                  icon: Icons.miscellaneous_services_outlined,
                  label: '${_services.length} servicios',
                ),
              StatPill(
                icon: Icons.payments_outlined,
                label: _money(catalogValue),
              ),
            ],
      actions: [
        // "Crear" (create): sin el permiso, el botón no aparece. En la GALERÍA
        // se crea una CATEGORÍA; dentro de una categoría, un PAQUETE.
        if (canCreate)
          gallery
              ? HsActionButton(
                  onPressed: _openCategoryForm,
                  icon: Icons.create_new_folder_outlined,
                  label: 'Nueva categoría',
                  primary: false,
                )
              : HsActionButton(
                  onPressed: () => _openForm(),
                  icon: Icons.add_card,
                  label: 'Nuevo paquete',
                ),
        // El DISEÑO de las cards se personaliza al INICIO del catálogo
        // (ver `_designBar`), justo encima de las tarjetas que se miran.
      ],
      child: gallery
          ? _galleryLevel(scheme, groups)
          : _packagesLevel(scheme, compact),
    );
  }

  /// Nivel 1: la GALERÍA de categorías del catálogo.
  ///
  /// Cada portada lleva su foto, cuántos paquetes tiene y desde qué precio
  /// salen; arriba va la de "Todo el catálogo" (la opción de ver todos los
  /// paquetes de una sola vez).
  Widget _galleryLevel(ColorScheme scheme, List<CategoryGroup> groups) {
    if (_loading) return const ListSkeleton(lines: 3, cardHeight: 200);
    if (_error != null) return _errorCard(scheme, _error!);

    final q = _query.trim().toLowerCase();
    final visible = q.isEmpty
        ? groups
        : groups
              .where(
                (c) =>
                    c.name.toLowerCase().contains(q) ||
                    c.packages.any(
                      (p) => '${p['name'] ?? ''}'.toLowerCase().contains(q),
                    ),
              )
              .toList(growable: false);
    if (visible.isEmpty) {
      return EmptyState(
        icon: Icons.collections_bookmark_outlined,
        title: q.isEmpty ? 'Todavía no hay categorías' : 'Sin resultados',
        message: q.isEmpty
            ? 'Las categorías salen de los paquetes del catálogo y se pueden '
                  'crear aquí mismo con "Nueva categoría".'
            : 'Ninguna categoría ni paquete coincide con "$_query".',
      );
    }

    final minPrice = _packages.fold<num>(0, (min, p) {
      final price = (p['price'] as num?) ?? 0;
      if (price <= 0) return min;
      if (min == 0 || price < min) return price;
      return min;
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Buscar por categoría o paquete…',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    onPressed: () => setState(() => _query = ''),
                    icon: const Icon(Icons.close, size: 18),
                  ),
          ),
        ),
        const SizedBox(height: 18),
        CategoryGalleryHead(
          scheme: scheme,
          label: 'Categorías',
          hint: 'Abre una portada para ver sus paquetes',
        ),
        const SizedBox(height: 10),
        CategoryGalleryGrid(
          categories: visible,
          gold: hsHexColor(_design.gold),
          total: _packages.length,
          minPrice: minPrice,
          onOpenAll: _openAllPackages,
          onOpen: (c) => _openCategory(c.id),
        ),
      ],
    );
  }

  /// Nivel 2: los paquetes de una categoría (o TODO el catálogo), con el mismo
  /// catálogo de siempre: buscador, chips, diseño de las cards y listado.
  Widget _packagesLevel(ColorScheme scheme, bool compact) {
    final canDesign = _canDesign;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Volver a la galería + en qué categoría se está.
        Row(
          children: [
            IconButton(
              tooltip: 'Volver a las categorías',
              onPressed: _backToGallery,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                _allPackages
                    ? 'Todo el catálogo'
                    : '${hsCategoryEmoji(_levelTitle)}  ${_levelTitle.toUpperCase()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .6,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
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
                  _byCards ? Icons.view_list_rounded : Icons.grid_view_rounded,
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
        // Personalizar el DISEÑO de las cards: al INICIO del catálogo, con
        // la muestra de los tiers que se están usando, para poder abrirlo
        // sin bajar toda la lista (y en las dos vistas: cards y filas).
        if (canDesign) ...[const SizedBox(height: 14), _designBar(scheme)],
        const SizedBox(height: 16),
        if (_loading)
          const ListSkeleton(lines: 3, cardHeight: 320)
        else if (_error != null)
          _errorCard(scheme, _error!)
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
                      canEdit:
                          HsAccess.instance.degraded ||
                          HsAccess.instance.can('Paquetes', 'update'),
                      canDelete:
                          HsAccess.instance.degraded ||
                          HsAccess.instance.can('Paquetes', 'delete'),
                      onEdit: () => _openForm(_filtered[i]),
                      onDelete: () => _delete(_filtered[i]),
                    ),
                  ),
                ),
            ],
          )
        else
          LayoutBuilder(
            builder: (context, box) {
              // Tarjetas de hasta [kPackageCardMaxWidth]: se acomodan solas
              // en la fila (Wrap) y NO se estiran en pantallas anchas.
              // Antes eran 1-3 columnas que crecían sin tope y en un monitor
              // grande salían flyers enormes.
              final cardW = box.maxWidth < kPackageCardMaxWidth
                  ? box.maxWidth
                  : kPackageCardMaxWidth;
              return Wrap(
                alignment: WrapAlignment.center,
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (var i = 0; i < _filtered.length; i++)
                    SizedBox(
                      width: cardW,
                      child: StaggeredItem(
                        index: i,
                        child: WebPackageCard(
                          pkg: _filtered[i],
                          design: _design,
                          canEdit:
                              HsAccess.instance.degraded ||
                              HsAccess.instance.can('Paquetes', 'update'),
                          canDelete:
                              HsAccess.instance.degraded ||
                              HsAccess.instance.can('Paquetes', 'delete'),
                          onEdit: () => _openForm(_filtered[i]),
                          onDelete: () => _delete(_filtered[i]),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        if (compact) const SizedBox(height: 8),
      ],
    );
  }

  /// Tarjeta de error con su botón de reintentar (la comparten los dos
  /// niveles del módulo).
  Widget _errorCard(ColorScheme scheme, String message) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.cloud_off_outlined, size: 40, color: scheme.error),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
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

  /// ¿Puedo personalizar el diseño de las cards? (mismo permiso que editar un
  /// paquete: el diseño es parte del módulo).
  bool get _canDesign =>
      HsAccess.instance.degraded || HsAccess.instance.can('Paquetes', 'update');

  /// Barra de DISEÑO: abre el diseñador de las cards de la web.
  ///
  /// Va al INICIO del catálogo: el botón para personalizar tiene que estar a la
  /// vista (antes vivía al final y había que bajar todo el listado para
  /// encontrarlo). Enseña de un vistazo el color de cada tier y qué se puede
  /// cambiar.
  Widget _designBar(ColorScheme scheme) {
    final gold = hsHexColor(_design.gold);
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: .35),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const ValueKey('packages-design-bar'),
        borderRadius: BorderRadius.circular(16),
        onTap: _openDesigner,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: gold.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: gold.withValues(alpha: .35)),
                ),
                child: Icon(Icons.style_outlined, size: 19, color: gold),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Diseño de las cards',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Forma, densidad, colores de cada tier y qué se muestra '
                      '(precio, servicios, botón…). Lo que se guarde aquí es lo '
                      'que ve la web.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Muestra en vivo de los colores de cada tier.
                    Row(
                      children: [
                        for (final tier in const ['basic', 'gold', 'premium'])
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: hsHexColor(
                                      _design.tierOf(tier).accent,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  kTierLabels[tier] ?? tier,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonalIcon(
                onPressed: _openDesigner,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Personalizar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(int? id, String label) {
    final scheme = Theme.of(context).colorScheme;
    // La categoría abierta es la que manda: el chip dice el estado REAL del
    // nivel ("Todos" está activo cuando se ve todo el catálogo).
    final selected = id == null ? _allPackages : _activeCategory == id;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => id == null ? _openAllPackages() : _openCategory(id),
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

/// Colores de la tarjeta de un paquete SEGÚN EL TEMA del panel.
///
/// La tarjeta imita el flyer de la web (oscuro, con el acento del tier), pero
/// el módulo también se usa en CLARO: ahí el fondo es la superficie del tema
/// con un tinte del acento y los textos son los del tema (antes se quedaba
/// oscura también en claro y desentonaba). El acento del tier se conserva —es
/// la identidad del paquete— oscurecido solo lo justo para leerse.
class _CardPalette {
  const _CardPalette({
    required this.dark,
    required this.bg,
    required this.onCard,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.accentSoft,
    required this.border,
    required this.divider,
    required this.footerBg,
    required this.badgeBg,
    required this.badgeGradient,
    required this.badgeText,
  });

  final bool dark;
  final Color bg;

  /// Texto principal de la tarjeta.
  final Color onCard;

  /// Textos secundarios (subtítulo, descripción, servicios).
  final Color muted;

  /// Etiquetas pequeñas ("Desde", moneda).
  final Color faint;

  /// Acento legible sobre [bg] (borde, precio, checks, botón).
  final Color accent;
  final Color accentSoft;
  final Color border;
  final Color divider;
  final Color footerBg;
  final Color? badgeBg;
  final LinearGradient? badgeGradient;
  final Color badgeText;
}

/// Arma la paleta de la tarjeta con el tema actual y el tier del DISEÑO.
///
/// [overPhoto] se usa cuando el texto va ENCIMA de la foto del paquete: ahí la
/// paleta es la oscura SIEMPRE (texto claro), porque el texto del tema claro se
/// perdía sobre la foto.
_CardPalette _cardPalette(
  ThemeData theme,
  HsTierLook look,
  SiteTierDesign tier, {
  bool overPhoto = false,
}) {
  final scheme = theme.colorScheme;
  final dark = overPhoto || theme.brightness == Brightness.dark;
  // Sobre el fondo claro, el acento del tier necesita un poco más de cuerpo:
  // se oscurece SOLO para textos e iconos (bordes y tintes usan el puro).
  final accent = dark
      ? look.accent
      : Color.lerp(look.accent, Colors.black, .30)!;
  final accentSoft = dark
      ? look.accentSoft
      : Color.lerp(look.accentSoft, Colors.black, .22)!;
  return _CardPalette(
    dark: dark,
    bg: dark
        ? Color.alphaBlend(look.dark.withValues(alpha: .94), scheme.surface)
        : Color.alphaBlend(look.accent.withValues(alpha: .05), scheme.surface),
    onCard: dark ? Colors.white : scheme.onSurface,
    muted: dark ? Colors.white.withValues(alpha: .58) : scheme.onSurfaceVariant,
    faint: dark
        ? Colors.white.withValues(alpha: .42)
        : scheme.onSurfaceVariant.withValues(alpha: .8),
    accent: accent,
    accentSoft: accentSoft,
    border: look.accent.withValues(
      alpha: dark ? tier.borderAlpha : (tier.borderAlpha + .18).clamp(0.0, 1.0),
    ),
    divider: dark
        ? Colors.white.withValues(alpha: .07)
        : scheme.outlineVariant.withValues(alpha: .55),
    footerBg: overPhoto
        ? Colors.black.withValues(alpha: .34)
        : look.accent.withValues(alpha: dark ? .05 : .07),
    badgeBg: tier.badgeFilled
        ? null
        : look.accent.withValues(alpha: dark ? .12 : .14),
    badgeGradient: tier.badgeFilled
        ? LinearGradient(colors: [look.accent, look.accentSoft])
        : null,
    badgeText: tier.badgeFilled ? look.dark : accentSoft,
  );
}

/// Tarjeta de paquete con la IDENTIDAD de la web (renderPackageCard): línea
/// superior degradada, badge de tier, categoría con icono, nombre serif,
/// subtítulo en itálica, servicios con checks y precio "Desde".
///
/// Dos diferencias a propósito con el flyer:
///   * los colores salen del TEMA del panel ([_CardPalette]): en claro la
///     tarjeta es clara con el acento del tier, en oscuro sigue el flyer;
///   * el pie lleva un botón "Editar" (y la tarjeta entera abre el paquete):
///     en el panel las tarjetas SON el contenido editable, y hay que verlo.
/// La TARJETA del paquete tal como la pinta la web (mismo diseño guardado).
///
/// Es pública porque la comparte la galería de Categorías: ahí se abre una
/// categoría y sus paquetes se ven con ESTA misma tarjeta, así el diseño del
/// panel y el de la página no pueden separarse.
class WebPackageCard extends StatefulWidget {
  const WebPackageCard({
    super.key,
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
  State<WebPackageCard> createState() => _WebPackageCardState();
}

class _WebPackageCardState extends State<WebPackageCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
    final shownServices = card.servicesLimit <= 0
        ? services.length
        : card.servicesLimit;
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
    // Con la foto DE FONDO, los textos van encima de la foto: la paleta se
    // vuelve oscura (texto claro) aunque el panel esté en claro.
    final overPhoto = card.imageMode == 'bg' && _hasPhoto(pkg);
    final pal = _cardPalette(theme, look, tierLook, overPhoto: overPhoto);
    final radius = BorderRadius.circular(card.radius.clamp(10.0, 24.0));

    // Tamaño MÁXIMO: la tarjeta no pasa de [kPackageCardMaxWidth] de ancho (se
    // centra lo que sobra) ni de [kPackageCardMaxHeight] de alto. `Align` afloja
    // las medidas que impone la rejilla, así el tope de ancho sí se respeta.
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: kPackageCardMaxWidth,
          maxHeight: kPackageCardMaxHeight,
        ),
        child: MouseRegion(
          cursor: canEdit ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            // Hover (solo desktop): se eleva como .package-card:hover de la web.
            transform: Matrix4.translationValues(
              0,
              _hover && card.hoverLift ? -4 : 0,
              0,
            ),
            decoration: BoxDecoration(
              borderRadius: radius,
              // Sombra suave: da profundidad sin ensuciar (más marcada en hover).
              boxShadow: card.shadow
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: pal.dark
                              ? (_hover ? .42 : .26)
                              : (_hover ? .18 : .09),
                        ),
                        blurRadius: _hover ? 28 : 14,
                        offset: Offset(0, _hover ? 12 : 6),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: pal.bg,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: radius,
                side: BorderSide(
                  color: card.borderWidth <= 0
                      ? Colors.transparent
                      : pal.border.withValues(
                          alpha: (_hover ? pal.border.a + .25 : pal.border.a)
                              .clamp(.12, 1.0),
                        ),
                  width: (_hover ? card.borderWidth + 1 : card.borderWidth)
                      .clamp(1.0, 3.0),
                ),
              ),
              child: InkWell(
                // Toda la tarjeta abre el paquete: lo primero que se entiende es
                // que estos bloques se editan. El pie repite la acción con su
                // botón, para quien prefiera un botón de verdad.
                onTap: canEdit ? widget.onEdit : null,
                child: _photoBackdrop(
                  card,
                  pkg,
                  pal.accent,
                  look.dark,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Foto del paquete en banda ARRIBA (como la web).
                      if (card.imageMode == 'top')
                        _photoBand(
                          pkg,
                          pal.accent,
                          card.imageHeight.clamp(40, 320),
                        ),
                      // Línea superior degradada dorada (el ::before de la web).
                      if (card.lineTop)
                        Container(
                          height: 2.4,
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
                      // El bloque del medio (categoría, nombre, servicios) es el que
                      // cede cuando la tarjeta llega al alto máximo: `Flexible` +
                      // un desplazable que no se mueve = lo que no cabe se recorta
                      // SIN error de desborde, y el pie del precio nunca se pierde.
                      Flexible(
                        fit: FlexFit.loose,
                        child: ClipRect(
                          child: SingleChildScrollView(
                            physics: const NeverScrollableScrollPhysics(),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(pad, 14, pad, 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // ===== Badge de tier + acciones =====
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: pal.badgeGradient,
                                          color: pal.badgeBg,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: pal.badgeGradient != null
                                              ? null
                                              : Border.all(
                                                  color: look.accent.withValues(
                                                    alpha: .35,
                                                  ),
                                                ),
                                        ),
                                        child: Text(
                                          tier.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 10,
                                            letterSpacing: 2,
                                            fontWeight: FontWeight.w800,
                                            color: pal.badgeText,
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
                                              icon: Icons.edit_rounded,
                                              label: 'Editar paquete',
                                              onTap: canEdit
                                                  ? widget.onEdit
                                                  : null,
                                            ),
                                            HsMenuAction(
                                              icon:
                                                  Icons.delete_outline_rounded,
                                              label: 'Eliminar',
                                              onTap: canDelete
                                                  ? widget.onDelete
                                                  : null,
                                              destructive: true,
                                            ),
                                          ],
                                        )
                                      else ...[
                                        if (canDelete)
                                          _IconGhost(
                                            icon: Icons.delete_outline_rounded,
                                            tooltip: 'Eliminar',
                                            color: pal.muted,
                                            onTap: widget.onDelete,
                                          ),
                                        if (canEdit) ...[
                                          const SizedBox(width: 4),
                                          _IconGhost(
                                            icon: Icons.edit_rounded,
                                            tooltip: 'Editar paquete',
                                            color: pal.accent,
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
                                        Text(
                                          hsCategoryEmoji(categoryName),
                                          style: const TextStyle(fontSize: 15),
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            categoryName.toUpperCase(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              letterSpacing: 2.2,
                                              fontWeight: FontWeight.w700,
                                              color: pal.accent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  const SizedBox(height: 10),
                                  // ===== Nombre + subtítulo (estilo web serif/itálica) =====
                                  Text(
                                    card.uppercaseNames
                                        ? (pkg['name'] ?? '')
                                              .toString()
                                              .toUpperCase()
                                        : (pkg['name'] ?? '').toString(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: pal.onCard,
                                      height: 1.2,
                                      fontFamily: card.serifNames
                                          ? 'serif'
                                          : null,
                                    ),
                                  ),
                                  if (card.showSubtitle &&
                                      (pkg['subtitle'] ?? '')
                                          .toString()
                                          .isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      (pkg['subtitle'] ?? '').toString(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontStyle: FontStyle.italic,
                                        color: pal.muted,
                                      ),
                                    ),
                                  ],
                                  if ((pkg['description'] ?? '')
                                      .toString()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      (pkg['description'] ?? '').toString(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.4,
                                        color: pal.muted,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Divider(height: 1, color: pal.divider),
                                  const SizedBox(height: 10),
                                  // ===== Servicios incluidos =====
                                  if (card.showServiceCount)
                                    Text(
                                      '${services.length} servicio${services.length == 1 ? '' : 's'} incluido${services.length == 1 ? '' : 's'}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        letterSpacing: 1.4,
                                        fontWeight: FontWeight.w700,
                                        color: pal.faint,
                                      ),
                                    ),
                                  const SizedBox(height: 6),
                                  if (card.showServices)
                                    for (final name in services.take(
                                      shownServices,
                                    ))
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.check_rounded,
                                              size: 15,
                                              color: pal.accent,
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
                                                  color: pal.onCard.withValues(
                                                    alpha: pal.dark ? .78 : .88,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  if (card.showServices &&
                                      services.length > shownServices)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        '+${services.length - shownServices} más…',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontStyle: FontStyle.italic,
                                          color: pal.faint,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 14),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // ===== Pie: precio + acción del PANEL =====
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                        decoration: BoxDecoration(
                          color: pal.footerBg,
                          border: Border(top: BorderSide(color: pal.divider)),
                        ),
                        child: Row(
                          children: [
                            // El precio se oculta si el diseño lo apaga (el precio se
                            // diseña en el diseñador, no aquí).
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
                                        color: pal.faint,
                                      ),
                                    ),
                                    Text(
                                      priceLabel,
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: pal.accent,
                                        fontFamily: 'serif',
                                      ),
                                    ),
                                    Text(
                                      currency,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        letterSpacing: 1.2,
                                        color: pal.faint,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              const Spacer(),
                            // Botón del PANEL: abre el paquete para editarlo. Se
                            // llama "Editar" (no el CTA de la web) para que quede
                            // claro que esto es un formulario, no el catálogo.
                            if (canEdit)
                              FilledButton.icon(
                                onPressed: widget.onEdit,
                                style: FilledButton.styleFrom(
                                  backgroundColor: look.accent.withValues(
                                    alpha: pal.dark ? .18 : .16,
                                  ),
                                  foregroundColor: pal.accent,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                icon: const Icon(Icons.edit_rounded, size: 16),
                                label: const Text('Editar'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
    final look = _lookFromDesign(
      widget.design,
      (pkg['tierName'] ?? '').toString(),
    );
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
    final theme = Theme.of(context);
    // Mismos colores que la tarjeta, según el tema (en claro la fila también
    // se aclara: antes se quedaba negra en modo light).
    final pal = _cardPalette(
      theme,
      look,
      widget.design.tierOf((pkg['tierName'] ?? '').toString()),
    );
    final radius = BorderRadius.circular(card.radius.clamp(10, 22));

    return MouseRegion(
      cursor: widget.canEdit ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(
          0,
          _hover && card.hoverLift ? -2 : 0,
          0,
        ),
        child: Material(
          color: pal.bg,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: card.borderWidth <= 0
                  ? Colors.transparent
                  : pal.border.withValues(
                      alpha: _hover
                          ? tierAlpha.clamp(.35, 1)
                          : (tierAlpha * .55).clamp(.10, 1),
                    ),
              width: _hover ? card.borderWidth + 1 : card.borderWidth,
            ),
          ),
          child: InkWell(
            onTap: widget.canEdit ? widget.onEdit : null,
            child: _photoBackdrop(
              card,
              pkg,
              pal.accent,
              look.dark,
              Row(
                children: [
                  // Barra de acento del tier (la "línea" del flyer, ahora vertical).
                  Container(width: 3, height: 72, color: pal.accent),
                  // La foto, cuando va en banda, también se asoma en la fila.
                  if (card.imageMode == 'top')
                    Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: _photoThumb(pkg, pal.accent),
                    ),
                  const SizedBox(width: 14),
                  // Icono de la categoría.
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: pal.accent.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: pal.accent.withValues(alpha: .28),
                      ),
                    ),
                    child: Text(
                      hsCategoryEmoji(categoryName),
                      style: const TextStyle(fontSize: 17),
                    ),
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
                                    color: pal.accent,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                gradient: pal.badgeGradient,
                                color: pal.badgeBg,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                (pkg['tierName'] ?? '')
                                    .toString()
                                    .toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w800,
                                  color: pal.badgeText,
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
                            color: pal.onCard,
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
                              color: pal.muted,
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
                          Icon(
                            Icons.check_circle_outline_rounded,
                            size: 15,
                            color: pal.accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${services.length}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: pal.onCard,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            services.length == 1 ? 'servicio' : 'servicios',
                            style: TextStyle(fontSize: 11, color: pal.muted),
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
                            color: pal.faint,
                          ),
                        ),
                        Text(
                          priceLabel,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: pal.accent,
                            fontFamily: 'serif',
                          ),
                        ),
                        Text(
                          currency,
                          style: TextStyle(
                            fontSize: 9.5,
                            letterSpacing: 1,
                            color: pal.faint,
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
                                icon: Icons.edit_rounded,
                                label: 'Editar paquete',
                                onTap: widget.canEdit ? widget.onEdit : null,
                              ),
                              HsMenuAction(
                                icon: Icons.delete_outline_rounded,
                                label: 'Eliminar',
                                onTap: widget.canDelete
                                    ? widget.onDelete
                                    : null,
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
                                  color: pal.muted,
                                  tooltip: 'Eliminar',
                                  onTap: widget.onDelete,
                                ),
                              if (widget.canEdit) ...[
                                const SizedBox(width: 4),
                                _IconGhost(
                                  icon: Icons.edit_rounded,
                                  color: pal.accent,
                                  tooltip: 'Editar paquete',
                                  onTap: widget.onEdit,
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
      ),
    );
  }
}

/// Botón fantasma (icono) de las acciones de un paquete.
///
/// El COLOR lo decide quien lo usa (la paleta de la tarjeta), para que se lea
/// igual de bien sobre el flyer oscuro que sobre la tarjeta clara del tema.
class _IconGhost extends StatelessWidget {
  const _IconGhost({
    required this.icon,
    required this.onTap,
    this.color,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Icon(
          icon,
          size: 17,
          color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
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
    this.initialCategory,
  });

  final Map<String, dynamic>? pkg;
  final List<Map<String, dynamic>> tiers;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> services;

  /// Dorado de la marca SEGÚN EL DISEÑO guardado (minivista previa).
  final Color gold;

  /// Categoría con la que nace un paquete NUEVO (la que se está viendo en el
  /// módulo). Al editar uno existente manda la del propio paquete.
  final int? initialCategory;

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
    _description = TextEditingController(
      text: (p['description'] ?? '').toString(),
    );
    _price = TextEditingController(
      text: p['price'] == null
          ? ''
          : (p['price'] as num).toStringAsFixed(
              (p['price'] as num).truncateToDouble() == p['price'] ? 0 : 2,
            ),
    );
    _urlImage = TextEditingController(text: (p['urlImage'] ?? '').toString());
    _tierId = p['tierId'] is int ? p['tierId'] as int : null;
    _categoryId = p['categoryId'] is int
        ? p['categoryId'] as int
        : (widget.pkg == null ? widget.initialCategory : null);
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
        await HsApi.updatePackage({
          'id': (widget.pkg!['id'] as num).toInt(),
          ...body,
        });
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
      subtitle: 'Este paquete aparece en la web ("Nuestros Paquetes") y se asigna a clientes.',
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
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
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
                          prefixIcon: Icon(
                            Icons.military_tech_outlined,
                            size: 20,
                          ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _urlImage,
                  decoration: const InputDecoration(
                    labelText: 'Ruta de imagen (ej. images/banner.jpg)',
                    prefixIcon: Icon(Icons.image_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // La foto se elige del DRIVE con el mismo selector de toda
                    // la app (rejilla con miniatura, vista previa y descarga)
                    // y se guarda su URL pública: es la que la web abre.
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _pickImageFromDrive,
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('Elegir una foto del Drive'),
                    ),
                    const Spacer(),
                    if (_urlImage.text.trim().isNotEmpty)
                      TextButton.icon(
                        onPressed: () => setState(() => _urlImage.text = ''),
                        icon: const Icon(Icons.close_rounded, size: 17),
                        label: const Text('Quitar'),
                      ),
                  ],
                ),
                if (_urlImage.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  // Miniatura de la foto elegida (sin `big`: el recuadro lo
                  // fija el alto de la tarjeta, no el ancho del diálogo).
                  DriveThumb(
                    source: driveImagePreview(
                      _urlImage.text.trim(),
                      width: 640,
                    ),
                    isRemote: true,
                    size: 132,
                  ),
                ],
              ],
            ),
          ),
        ], // fin de la pestaña Datos
      ],
    );
  }

  /// Elige la FOTO del paquete en el Drive (el mismo selector de toda la app) y
  /// deja su URL pública en el campo: es la que la web abre sin sesión, para el
  /// fondo de la tarjeta y los carruseles.
  Future<void> _pickImageFromDrive() async {
    final drive = DriveScope.maybeOf(context);
    if (drive == null) {
      HsToast.info('El Drive no está disponible en esta pantalla');
      return;
    }
    final picked = await showDrivePhotoPicker(
      context,
      drive: drive,
      title: 'Foto del paquete',
      subtitle:
          'La que la web usa en la tarjeta del paquete y en los '
          'carruseles.',
      confirmLabel: 'Usar esta foto',
      note:
          'Se enlaza desde el servidor del Drive '
          '(${AppConstants.apiBase}): la página la abre sin iniciar sesión.',
    );
    if (picked == null || picked.isEmpty) return;
    setState(() => _urlImage.text = drivePublicUrl(picked.first));
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 2,
                  ),
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
                style: const TextStyle(fontSize: 12, color: Color(0xFFB9C2D0)),
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
                    color: soft,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Icon(Icons.checklist_rtl, size: 13, color: soft),
              const SizedBox(width: 6),
              Text(
                '${_serviceIds.length} servicios',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: soft,
                ),
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
            final hay = '${s['name'] ?? ''} ${s['description'] ?? ''}'
                .toLowerCase();
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
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  child: const Text(
                    'Limpiar',
                    style: TextStyle(fontSize: 11.5),
                  ),
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
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
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
                Icon(
                  icon,
                  size: 16,
                  color: selected ? AppColors.brand : scheme.onSurfaceVariant,
                ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
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

/// Diálogo para CREAR una categoría del catálogo (Boda, XV Años, Bautizo…).
///
/// El icono no se pide: el panel y la web lo sacan del NOMBRE de la categoría
/// (la columna `packages_categories.icon` está reservada y no se usa), así que
/// una categoría nueva ya sale con su emoji en la galería y en la página.
class _CategoryFormDialog extends StatefulWidget {
  const _CategoryFormDialog();

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  final TextEditingController _name = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Escribe el nombre de la categoría');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await HsApi.createPackageCategory(name);
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
          _error = 'No se pudo crear la categoría';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      icon: Icons.create_new_folder_outlined,
      title: 'Nueva categoría',
      subtitle:
          'Las categorías agrupan los paquetes del catálogo (y la web las usa '
          'para filtrarlos).',
      maxWidth: 480,
      saving: _saving,
      error: _error,
      saveLabel: 'Crear categoría',
      onCancel: () => Navigator.of(context).pop(false),
      onSave: _save,
      children: [
        FormSection(
          label: 'Nombre',
          child: TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nombre de la categoría',
              hintText: 'Ej. Bautizo',
              prefixIcon: Icon(Icons.category_outlined, size: 20),
            ),
            onSubmitted: (_) => _save(),
          ),
        ),
      ],
    );
  }
}

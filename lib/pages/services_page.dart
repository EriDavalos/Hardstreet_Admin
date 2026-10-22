import 'dart:async';

import 'package:flutter/material.dart';

import '../hs_access.dart';
import '../hs_api.dart';
import '../service_icons.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/common.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/hs_pager.dart';
import '../widgets/hs_search_filter.dart';
import '../widgets/service_form_dialog.dart';

// ==================================================================
// MÓDULO SERVICIOS: el catálogo que se incluye en los paquetes.
//   - Crear / editar / eliminar servicios (icono, nombre, descripción).
//   - La liga del Drive NO se administra aquí: `url` solo vive en el paquete
//     COMPRADO del cliente (pestaña Servicios del paquete). Este catálogo es
//     solo el listado de servicios disponibles.
// Backend: /api/admin/services (permiso sobre el módulo "Servicios").
// ==================================================================

class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key});

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  bool _loading = true;
  String? _error;

  /// Filas de la PÁGINA actual (las manda el backend).
  List<Map<String, dynamic>> _services = const [];
  String _query = '';

  /// Filtro por LIGA de Drive: '' todos · 'con' con liga · 'sin' sin liga.
  String _linkFilter = '';

  // Paginación del listado (30 de fábrica; 50/100/200 en el pie).
  int _page = 1;
  int _pageSize = kHsDefaultPageSize;

  /// Total con la búsqueda/filtro puestos (lo calcula el servidor).
  int _total = 0;

  /// Conteos de los chips: todos / con liga / sin liga.
  Map<String, int> _linkCounts = const {};

  /// true = backend paginado; false = respuesta vieja (se pagina en pantalla).
  bool _serverPaged = false;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Busca en el servidor con una pequeña espera (una petición por pausa).
  void _search(String value) {
    setState(() {
      _query = value;
      _page = 1;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _reload);
  }

  /// Pide la página actual al backend (con búsqueda y filtro de liga).
  Future<void> _reload({bool reset = false}) async {
    if (reset) _page = 1;
    // Página pedida (antes de que el servidor la recorte).
    final asked = _page;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await HsApi.adminServicesPage(
        page: _page,
        limit: _pageSize,
        q: _query,
        link: _linkFilter,
      );
      if (!mounted) return;
      setState(() {
        _services = result.items;
        _serverPaged = result.serverPaged;
        _total = result.total;
        _linkCounts = {
          for (final e
              in ((result.meta['linkCounts'] as Map?) ?? const {}).entries)
            e.key.toString(): (e.value as num?)?.toInt() ?? 0,
        };
        if (result.serverPaged) _page = result.page;
        _loading = false;
        _error = null;
      });
      // La página pedida ya no existe (se borró su última fila): pide la
      // última que sí tiene datos.
      if (result.serverPaged &&
          result.items.isEmpty &&
          result.total > 0 &&
          _page > 1 &&
          _page < asked) {
        _page = result.pages;
        await _reload();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el catálogo de servicios';
        _loading = false;
      });
    }
  }

  Future<void> _openForm([Map<String, dynamic>? service]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ServiceFormDialog(service: service),
    );
    // Al CREAR se vuelve a la página 1 (el servicio nuevo queda a la vista).
    if (saved == true) _reload(reset: service == null);
  }

  Future<void> _delete(Map<String, dynamic> service) async {
    final ok = await confirmDelete(
      context,
      title: '¿Eliminar servicio?',
      message:
          '"${service['name'] ?? ''}" dejará de estar disponible para nuevos '
          'paquetes. No se borra de los paquetes que ya lo incluyen.',
    );
    if (ok != true) return;
    try {
      await HsApi.deleteService((service['id'] as num).toInt());
    } catch (_) {
      // El backend ya avisó con la notificación roja.
    }
    _reload();
  }

  /// Filas que se pintan: la página del servidor o el filtro local (backend
  /// viejo sin `total`).
  List<Map<String, dynamic>> get _visible {
    if (_serverPaged) return _services;
    final q = _query.trim().toLowerCase();
    return _services.where((s) {
      final hasLink = (s['url'] ?? '').toString().trim().isNotEmpty;
      if (_linkFilter == 'con' && !hasLink) return false;
      if (_linkFilter == 'sin' && hasLink) return false;
      if (q.isEmpty) return true;
      final hay = '${s['name'] ?? ''} ${s['description'] ?? ''}'.toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  bool _hasLink(Map<String, dynamic> s) =>
      (s['url'] ?? '').toString().trim().isNotEmpty;

  /// Total del chip "Todos" (respeta la búsqueda).
  int get _countAll =>
      _serverPaged ? (_linkCounts['all'] ?? 0) : _services.length;

  int get _countWith => _serverPaged
      ? (_linkCounts['with'] ?? 0)
      : _services.where(_hasLink).length;

  int get _countWithout => _serverPaged
      ? (_linkCounts['without'] ?? 0)
      : _services.where((s) => !_hasLink(s)).length;

  /// Opciones del módulo de filtros (el servidor resuelve `link`).
  List<HsFilterGroup> get _filterGroups => [
    HsFilterGroup(
      id: 'link',
      title: 'Carpeta del Drive',
      help:
          'La liga base del servicio se administra desde el paquete del '
          'cliente; aquí puedes filtrar cuáles ya la tienen.',
      options: [
        HsFilterOption(
          value: '',
          label: 'Todos los servicios',
          count: _countAll,
          icon: Icons.apps_rounded,
        ),
        HsFilterOption(
          value: 'con',
          label: 'Con carpeta asignada',
          count: _countWith,
          icon: Icons.folder_open_outlined,
          color: const Color(0xFF2F6BFF),
        ),
        HsFilterOption(
          value: 'sin',
          label: 'Sin carpeta',
          count: _countWithout,
          icon: Icons.folder_off_outlined,
          color: const Color(0xFFD97706),
        ),
      ],
    ),
  ];

  /// Filas de la página actual.
  List<Map<String, dynamic>> get _pageRows => _serverPaged
      ? _visible
      : HsPages(
          total: _visible.length,
          page: _page,
          pageSize: _pageSize,
        ).slice(_visible);

  /// Total que se le pasa a la barra: el del servidor o el local.
  int get _pagerTotal => _serverPaged ? _total : _visible.length;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PageContainer(
      module: 'services',
      title: 'Servicios',
      description:
          'Catálogo de servicios de los paquetes: icono, nombre, descripción y '
          'parámetros especiales (fotos y carpeta del Drive).',
      icon: Icons.miscellaneous_services_outlined,
      onRefresh: _reload,
      stats: [
        StatPill(
          icon: Icons.miscellaneous_services_outlined,
          label: '$_countAll servicios',
        ),
      ],
      actions: [
        // "Nuevo servicio" (create): sin el permiso, el botón no aparece.
        if (HsAccess.instance.degraded ||
            HsAccess.instance.can('Servicios', 'create'))
          HsActionButton(
            onPressed: () => _openForm(),
            icon: Icons.add,
            label: 'Nuevo servicio',
          ),
      ],
      // Barra de páginas como PIE FIJO (fuera del scroll).
      footer: HsPager(
        total: _pagerTotal,
        page: _page,
        pageSize: _pageSize,
        enabled: !_loading && _error == null,
        onPage: (p) {
          setState(() => _page = p);
          _reload();
        },
        onPageSize: (n) {
          setState(() {
            _pageSize = n;
            _page = 1;
          });
          _reload();
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Buscar vuelve a la primera página y consulta al servidor.
          HsSearchFilterBar(
            hint: 'Buscar por nombre o descripción…',
            onChanged: _search,
            initial: _query,
            enabled: !_loading || _query.isNotEmpty,
            groups: _filterGroups,
            selected: {'link': _linkFilter},
            onApply: (filters) {
              final next = filters['link'] ?? '';
              if (next == _linkFilter) return;
              setState(() {
                _linkFilter = next;
                _page = 1;
              });
              _reload();
            },
          ),
          const SizedBox(height: 14),
          if (_loading)
            const ListSkeleton(lines: 3, cardHeight: 130)
          else if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 40,
                      color: scheme.error,
                    ),
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
          else if (_visible.isEmpty)
            const EmptyState(
              icon: Icons.miscellaneous_services_outlined,
              title: 'Sin servicios',
              message:
                  'No hay servicios que coincidan. Crea el primero con el '
                  'botón "Nuevo servicio".',
            )
          else
            // UNA sola columna, con el mismo diseño que los demás módulos
            // (Clientes, Usuarios…): una tarjeta con filas separadas por
            // líneas. Nada de rejilla de dos columnas ni de saltar al pasar
            // el ratón: la fila entera abre el servicio.
            Builder(
              builder: (context) {
                final rows = _pageRows;
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            color: Theme.of(context).dividerColor,
                          ),
                        StaggeredItem(
                          index: i,
                          child: _ServiceRow(
                            service: rows[i],
                            canEdit:
                                HsAccess.instance.degraded ||
                                HsAccess.instance.can('Servicios', 'update'),
                            canDelete:
                                HsAccess.instance.degraded ||
                                HsAccess.instance.can('Servicios', 'delete'),
                            onEdit: () => _openForm(rows[i]),
                            onDelete: () => _delete(rows[i]),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Fila de servicio: icono, nombre, descripción y parámetros especiales.
///
/// Mismo patrón que la fila del módulo Clientes: la fila entera es el área de
/// clic (sin saltos ni sombras al pasar el ratón) y las acciones van a la
/// derecha (o al menú "⋮" cuando no caben).
class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.service,
    required this.onEdit,
    required this.onDelete,
    required this.canEdit,
    required this.canDelete,
  });

  final Map<String, dynamic> service;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool canEdit;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = service;
    final name = (s['name'] ?? '').toString();
    final description = (s['description'] ?? '').toString();
    final photosMax = (s['photosMax'] as num?)?.toInt() ?? 0;
    final allowFolder = s['allowFolder'] != false;
    final showBanner = s['showBanner'] == true && allowFolder;

    return LayoutBuilder(
      builder: (context, box) {
        // En pantallas angostas los botones no caben junto al texto: se
        // guardan en el menú "⋮" de la fila (mismo patrón que Clientes).
        final compact = box.maxWidth < 560 || hsRowCompact(context);
        final row = Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  serviceIconOf((s['icon'] ?? '').toString()),
                  size: 22,
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Servicio' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    // Parámetros especiales (los ve el estudio de un vistazo).
                    if (photosMax > 0 || showBanner || !allowFolder) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (photosMax > 0)
                            _CapabilityChip(
                              icon: Icons.photo_library_outlined,
                              label: photosMax == 1
                                  ? '1 foto'
                                  : 'Hasta $photosMax fotos',
                            ),
                          if (showBanner)
                            const _CapabilityChip(
                              icon: Icons.wallpaper_rounded,
                              label: 'Banner cliente',
                            ),
                          if (!allowFolder)
                            const _CapabilityChip(
                              icon: Icons.folder_off_outlined,
                              label: 'Sin carpeta',
                              muted: true,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // CELULAR: las acciones del servicio van en el menú "⋮" (en
              // escritorio se mantienen los dos botones de icono). Sin
              // permisos para ninguna, el menú NO se dibuja.
              if (compact)
                HsRowMenu(
                  actions: [
                    HsMenuAction(
                      icon: Icons.tune_rounded,
                      label: 'Personalizar',
                      onTap: canEdit ? onEdit : null,
                    ),
                    HsMenuAction(
                      icon: Icons.delete_outline_rounded,
                      label: 'Eliminar',
                      onTap: canDelete ? onDelete : null,
                      destructive: true,
                    ),
                  ],
                )
              else ...[
                if (canEdit)
                  IconButton(
                    tooltip: 'Personalizar',
                    visualDensity: VisualDensity.compact,
                    onPressed: onEdit,
                    icon: const Icon(Icons.tune_rounded, size: 20),
                  ),
                if (canDelete)
                  IconButton(
                    tooltip: 'Eliminar',
                    visualDensity: VisualDensity.compact,
                    onPressed: onDelete,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: scheme.error.withValues(alpha: .8),
                    ),
                  ),
                if (canEdit)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
              ],
            ],
          ),
        );

        // Sin permiso de editar la fila NO es clickeable (solo se ven las
        // acciones permitidas).
        if (!canEdit) return row;
        return Tooltip(
          message: 'Personalizar servicio',
          waitDuration: const Duration(milliseconds: 700),
          child: InkWell(onTap: onEdit, child: row),
        );
      },
    );
  }
}

/// Etiqueta pequeña de un parámetro especial del servicio.
class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({
    required this.icon,
    required this.label,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = muted ? scheme.onSurfaceVariant : AppColors.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

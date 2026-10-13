import 'package:flutter/material.dart';

import '../hs_access.dart';
import '../hs_api.dart';
import '../service_icons.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/common.dart';
import '../widgets/confirm_dialog.dart';
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
  List<Map<String, dynamic>> _services = const [];
  String _query = '';

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
      final services = await HsApi.adminServices();
      if (!mounted) return;
      setState(() {
        _services = services;
        _loading = false;
        _error = null;
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
        _error = 'No se pudo cargar el catálogo de servicios';
        _loading = false;
      });
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openForm([Map<String, dynamic>? service]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ServiceFormDialog(service: service),
    );
    if (saved == true) _reload();
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
      _snack('Servicio eliminado');
      _reload();
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo eliminar el servicio');
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _services;
    return _services.where((s) {
      final hay =
          '${s['name'] ?? ''} ${s['description'] ?? ''}'.toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PageContainer(
      title: 'Servicios',
      description:
          'Catálogo de servicios que se incluyen en los paquetes: icono, '
          'nombre y descripción.',
      icon: Icons.miscellaneous_services_outlined,
      stats: [
        StatPill(
            icon: Icons.miscellaneous_services_outlined,
            label: '${_services.length} servicios'),
      ],
      actions: [
        // "Nuevo servicio" (create): sin el permiso, el botón no aparece.
        if (HsAccess.instance.degraded ||
            HsAccess.instance.can('Servicios', 'create'))
          FilledButton.icon(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nuevo servicio'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Buscar por nombre o descripción…',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => setState(() => _query = ''),
                      icon: const Icon(Icons.close, size: 18),
                    ),
            ),
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
              icon: Icons.miscellaneous_services_outlined,
              title: 'Sin servicios',
              message:
                  'No hay servicios que coincidan. Crea el primero con el '
                  'botón "Nuevo servicio".',
            )
          else
            LayoutBuilder(builder: (context, box) {
              final cols = box.maxWidth > 1100
                  ? 2
                  : box.maxWidth > 620
                      ? 2
                      : 1;
              return Column(
                children: [
                  for (var i = 0; i < _filtered.length; i += cols)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var j = 0; j < cols; j++) ...[
                            if (j > 0) const SizedBox(width: 12),
                            Expanded(
                              child: (i + j) < _filtered.length
                                  ? StaggeredItem(
                                      index: i + j,
                                      child: _ServiceCard(
                                        service: _filtered[i + j],
                                        canEdit: HsAccess.instance.degraded ||
                                            HsAccess
                                                .instance.can('Servicios', 'update'),
                                        canDelete: HsAccess.instance.degraded ||
                                            HsAccess
                                                .instance.can('Servicios', 'delete'),
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
        ],
      ),
    );
  }
}

/// Tarjeta de servicio: icono, nombre y descripción.
class _ServiceCard extends StatefulWidget {
  const _ServiceCard({
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
  State<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<_ServiceCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = widget.service;
    final name = (s['name'] ?? '').toString();
    final description = (s['description'] ?? '').toString();

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.canEdit ? widget.onEdit : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: .28),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hover
                  ? AppColors.brand.withValues(alpha: .45)
                  : scheme.outlineVariant.withValues(alpha: .45),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w800),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 3),
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
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                children: [
                  if (widget.canEdit)
                    IconButton(
                      tooltip: 'Personalizar',
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onEdit,
                      icon: const Icon(Icons.tune_rounded, size: 18),
                    ),
                  if (widget.canDelete)
                    IconButton(
                      tooltip: 'Eliminar',
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onDelete,
                      icon: Icon(Icons.delete_outline_rounded,
                          size: 18, color: scheme.error),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


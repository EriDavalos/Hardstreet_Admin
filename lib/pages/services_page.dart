import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../hs_access.dart';
import '../hs_api.dart';
import '../service_icons.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/common.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/form_dialog.dart';

// ==================================================================
// MÓDULO SERVICIOS: el catálogo que se incluye en los paquetes.
//   - Crear / editar / eliminar servicios (icono, nombre, descripción).
//   - `url` opcional: la liga BASE del Drive afiliada al servicio. Aquí se
//     consulta y se administra; también se puede editar desde la pestaña
//     Servicios del paquete comprado del cliente.
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
      builder: (_) => _ServiceFormDialog(service: service),
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
          '${s['name'] ?? ''} ${s['description'] ?? ''} ${s['url'] ?? ''}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final withUrl =
        _services.where((s) => (s['url'] ?? '').toString().trim().isNotEmpty);
    return PageContainer(
      title: 'Servicios',
      description:
          'Catálogo de servicios que se incluyen en los paquetes: icono, '
          'nombre, descripción y la liga base del Drive (opcional).',
      icon: Icons.miscellaneous_services_outlined,
      stats: [
        StatPill(
            icon: Icons.miscellaneous_services_outlined,
            label: '${_services.length} servicios'),
        StatPill(icon: Icons.link, label: '${withUrl.length} con enlace'),
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
              hintText: 'Buscar por nombre, descripción o enlace…',
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

/// Tarjeta de servicio: icono, nombre, descripción y la liga del Drive
/// (copiable con un toque).
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

  Future<void> _copyUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Liga copiada')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = widget.service;
    final name = (s['name'] ?? '').toString();
    final description = (s['description'] ?? '').toString();
    final url = (s['url'] ?? '').toString().trim();
    final hasUrl = url.isNotEmpty;

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
                    if (hasUrl) ...[
                      const SizedBox(height: 6),
                      Tooltip(
                        message: 'Copiar liga del Drive',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => _copyUrl(url),
                          child: Row(
                            children: [
                              const Icon(Icons.link,
                                  size: 13, color: AppColors.brand),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.brand,
                                  ),
                                ),
                              ),
                            ],
                          ),
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

/// Diálogo de alta/edición de servicio: icono seleccionable, nombre,
/// descripción y la URL base del Drive (opcional).
class _ServiceFormDialog extends StatefulWidget {
  const _ServiceFormDialog({this.service});

  final Map<String, dynamic>? service;

  @override
  State<_ServiceFormDialog> createState() => _ServiceFormDialogState();
}

class _ServiceFormDialogState extends State<_ServiceFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _url;

  /// Valor guardado del icono (`material:xxx` o la ruta heredada).
  late String _icon;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.service != null;

  String get _iconKey {
    final v = _icon.trim();
    return v.startsWith('material:') ? v.substring(9) : '';
  }

  @override
  void initState() {
    super.initState();
    final s = widget.service ?? const {};
    _name = TextEditingController(text: (s['name'] ?? '').toString());
    _description = TextEditingController(text: (s['description'] ?? '').toString());
    _url = TextEditingController(text: (s['url'] ?? '').toString());
    _icon = (s['icon'] ?? '').toString();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Escribe el nombre del servicio');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = <String, dynamic>{
      'name': name,
      'description': _description.text.trim(),
      'icon': _icon.trim(),
      'url': _url.text.trim(),
    };
    try {
      if (_editing) {
        await HsApi.updateService(
            {'id': (widget.service!['id'] as num).toInt(), ...body});
      } else {
        await HsApi.createService(body);
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
          _error = 'No se pudo guardar el servicio';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      icon: _editing
          ? Icons.tune_rounded
          : Icons.miscellaneous_services_outlined,
      title: _editing ? 'Personalizar servicio' : 'Nuevo servicio',
      subtitle: 'Se usa en el catálogo y en todos los paquetes que lo '
          'incluyen.',
      maxWidth: 520,
      saving: _saving,
      error: _error,
      saveLabel: _editing ? 'Guardar cambios' : 'Crear servicio',
      onCancel: () => Navigator.of(context).pop(false),
      onSave: _save,
      children: [
        FormSection(
          label: 'Icono',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in kServiceIcons.entries)
                _IconPickTile(
                  icon: e.value,
                  selected: _iconKey == e.key,
                  onTap: () => setState(() => _icon = serviceIconValue(e.key)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FormSection(
          label: 'Nombre',
          child: TextField(
            controller: _name,
            autofocus: !_editing,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nombre del servicio',
              prefixIcon: Icon(Icons.miscellaneous_services_outlined,
                  size: 20),
            ),
          ),
        ),
        const SizedBox(height: 14),
        FormSection(
          label: 'Descripción',
          child: TextField(
            controller: _description,
            minLines: 2,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Descripción',
              hintText: 'Ej. Cobertura completa del evento…',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes, size: 20),
            ),
          ),
        ),
        const SizedBox(height: 14),
        FormSection(
          label: 'Carpeta del Drive (opcional)',
          child: TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'URL base del Drive',
              hintText: 'https://drive.google.com/drive/…',
              prefixIcon: Icon(Icons.link, size: 20),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'La liga se puede editar después desde la pestaña Servicios del '
          'paquete comprado del cliente.',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Casilla visual para elegir un icono del catálogo.
class _IconPickTile extends StatelessWidget {
  const _IconPickTile({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.brand.withValues(alpha: .14)
                : scheme.surfaceContainerHighest.withValues(alpha: .35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppColors.brand.withValues(alpha: .75)
                  : scheme.outlineVariant.withValues(alpha: .5),
            ),
          ),
          child: Icon(
            icon,
            size: 21,
            color: selected ? AppColors.brand : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

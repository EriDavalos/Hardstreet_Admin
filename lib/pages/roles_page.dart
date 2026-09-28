import 'package:flutter/material.dart';

import '../hs_api.dart';
import '../widgets/anim.dart';
import '../widgets/common.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/form_dialog.dart';

/// Módulo ROLES: CRUD + asignación de acciones por módulo.
/// El modal muestra la lista de MÓDULOS que existen en la base de datos
/// (sin submódulos/grupos) y, bajo cada módulo, sus acciones (checkboxes).
class RolesPage extends StatefulWidget {
  const RolesPage({super.key});

  @override
  State<RolesPage> createState() => _RolesPageState();
}

class _RolesPageState extends State<RolesPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _roles = const [];
  List<Map<String, dynamic>> _modules = const [];

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
      final roles = await HsApi.roles();
      List<Map<String, dynamic>> modules = const [];
      try {
        final meta = await HsApi.adminMeta();
        modules = meta.modules;
      } catch (_) {
        // Si /admin/meta falla, el CRUD de roles sigue funcionando.
      }
      if (!mounted) return;
      setState(() {
        _roles = roles;
        _modules = modules;
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
        _error = 'No se pudo cargar la lista de roles';
        _loading = false;
      });
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openForm([Map<String, dynamic>? role]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RoleFormDialog(role: role),
    );
    if (saved == true) _reload();
  }

  /// Modal de asignación de acciones por módulo.
  /// SIEMPRE abre: si los módulos no se pudieron cargar (backend sin
  /// responder, formato desconocido, sin módulos en la BD), el modal
  /// muestra su propio estado de error/reintento o la lista vacía, en
  /// lugar de solo un snack sin nada.
  Future<void> _openPermissions(Map<String, dynamic> role) async {
    // Si los módulos no se cargaron al entrar a la página (p. ej. /admin/meta
    // falló en ese momento), reintenta UNA vez antes de abrir el modal.
    if (_modules.isEmpty) {
      try {
        final meta = await HsApi.adminMeta();
        if (mounted) setState(() => _modules = meta.modules);
      } catch (_) {
        // Sigue vacío: el modal mostrará su estado "sin módulos".
      }
    }
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PermissionsDialog(role: role, modules: _modules),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(Map<String, dynamic> role) async {
    final ok = await confirmDelete(
      context,
      title: '¿Eliminar rol?',
      message:
          'El rol "${role['name'] ?? ''}" dejará de estar disponible. No se puede eliminar si hay usuarios usándolo.',
    );
    if (!ok) return;
    try {
      await HsApi.deleteRole((role['id'] as num).toInt());
      _snack('Rol eliminado');
      _reload();
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo eliminar el rol');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PageContainer(
      title: 'Roles',
      description:
          'Define a qué módulos puede entrar cada rol y qué acciones puede realizar.',
      actions: [
        FilledButton.icon(
          onPressed: () => _openForm(),
          icon: const Icon(Icons.add_moderator_outlined, size: 18),
          label: const Text('Nuevo rol'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.cloud_off_outlined, size: 40, color: scheme.error),
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
          else if (_roles.isEmpty)
            const EmptyState(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Sin roles',
              message: 'Crea el primer rol con el botón "Nuevo rol".',
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < _roles.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, color: Theme.of(context).dividerColor),
                    StaggeredItem(
                      index: i,
                      child: _RoleTile(
                        role: _roles[i],
                        onEdit: () => _openForm(_roles[i]),
                        onPermissions: () => _openPermissions(_roles[i]),
                        onDelete: () => _delete(_roles[i]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({
    required this.role,
    required this.onEdit,
    required this.onPermissions,
    required this.onDelete,
  });

  final Map<String, dynamic> role;
  final VoidCallback onEdit;
  final VoidCallback onPermissions;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = (role['name'] ?? '').toString();
    final perms = ((role['permissions'] as List?) ?? const []);
    final permCount = perms.length;
    final moduleCount = perms
        .map((p) => p is Map ? p['moduleId'] : null)
        .whereType<Object>()
        .map((v) => v.toString())
        .toSet()
        .length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: scheme.primary.withValues(alpha: .12),
            child: Text(
              name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14.5)),
                const SizedBox(height: 3),
                Text(
                  '$moduleCount ${moduleCount == 1 ? 'módulo' : 'módulos'} · '
                  '$permCount ${permCount == 1 ? 'acción' : 'acciones'}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonalIcon(
            onPressed: onPermissions,
            icon: const Icon(Icons.tune, size: 16),
            label: const Text('Acciones'),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Renombrar',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Eliminar',
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline,
                size: 20, color: scheme.error.withValues(alpha: .8)),
          ),
        ],
      ),
    );
  }
}

/// Dialogo de alta/edicion de rol (solo nombre) con el diseño estándar.
class _RoleFormDialog extends StatefulWidget {
  const _RoleFormDialog({this.role});

  final Map<String, dynamic>? role;

  @override
  State<_RoleFormDialog> createState() => _RoleFormDialogState();
}

class _RoleFormDialogState extends State<_RoleFormDialog> {
  late final TextEditingController _name;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.role != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: (widget.role?['name'] ?? '').toString());
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Escribe el nombre del rol');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_editing) {
        await HsApi.updateRole(
            {'id': (widget.role!['id'] as num).toInt(), 'name': name});
      } else {
        await HsApi.createRole({'name': name});
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
          _error = 'No se pudo guardar el rol';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      icon: _editing ? Icons.edit_rounded : Icons.add_moderator_outlined,
      title: _editing ? 'Editar rol' : 'Nuevo rol',
      subtitle: 'El nombre identifica al rol en usuarios y permisos.',
      saving: _saving,
      error: _error,
      saveLabel: _editing ? 'Guardar cambios' : 'Crear rol',
      onCancel: () => Navigator.of(context).pop(false),
      onSave: _save,
      children: [
        FormSection(
          label: 'Nombre del rol',
          child: TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Ej. Fotografía, Recepción, Edición…',
              prefixIcon: Icon(Icons.badge_outlined, size: 20),
            ),
            onSubmitted: (_) => _save(),
          ),
        ),
      ],
    );
  }
}

// ==================================================================
// Modal "Asignación de acciones": módulos planos (de la BD) + acciones
// ==================================================================

class _PermissionsDialog extends StatefulWidget {
  const _PermissionsDialog({required this.role, required this.modules});

  final Map<String, dynamic> role;
  final List<Map<String, dynamic>> modules;

  @override
  State<_PermissionsDialog> createState() => _PermissionsDialogState();
}

class _PermissionsDialogState extends State<_PermissionsDialog> {
  /// Set de "moduleId:permissionId" seleccionados.
  final Set<String> _selected = {};
  bool _saving = false;

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void initState() {
    super.initState();
    final perms = (widget.role['permissions'] as List?) ?? const [];
    for (final p in perms) {
      if (p is Map) {
        _selected.add(
          '${(p['moduleId'] ?? 0).toString()}:${(p['permissionId'] ?? 0).toString()}',
        );
      }
    }
  }

  String _k(dynamic m, dynamic p) => '${m.toString()}:${p.toString()}';

  List<Map<String, dynamic>> _actions(Map<String, dynamic> module) =>
      ((module['actions'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();

  void _toggleModule(Map<String, dynamic> module, bool? v) {
    final keys =
        _actions(module).map((a) => _k(module['id'], a['id'])).toList();
    setState(() {
      if (v ?? true) {
        _selected.addAll(keys);
      } else {
        _selected.removeAll(keys);
      }
    });
  }

  void _toggleAction(Map<String, dynamic> module, Map<String, dynamic> action,
      bool? v) {
    setState(() {
      if (v ?? false) {
        _selected.add(_k(module['id'], action['id']));
      } else {
        _selected.remove(_k(module['id'], action['id']));
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    // Agrupa por moduleId: { moduleId, permissionIds: [] }
    final byModule = <int, List<int>>{};
    for (final key in _selected) {
      final parts = key.split(':');
      final m = int.tryParse(parts[0]) ?? 0;
      final a = int.tryParse(parts[1]) ?? 0;
      if (m <= 0 || a <= 0) continue;
      byModule.putIfAbsent(m, () => []).add(a);
    }
    final permissions = byModule.entries
        .map((e) => {'moduleId': e.key, 'permissionIds': e.value})
        .toList();
    try {
      await HsApi.updateRole({
        'id': (widget.role['id'] as num).toInt(),
        'permissions': permissions,
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack(e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('No se pudo guardar los permisos');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = (widget.role['name'] ?? '').toString();

    return FormDialog(
      icon: Icons.tune,
      title: name,
      subtitle: 'Asignación de acciones por módulo',
      maxWidth: 680,
      // Altura adaptativa: en pantallas cortas el diálogo cabe completo.
      contentHeight:
          (MediaQuery.sizeOf(context).height * .5).clamp(260.0, 430.0),
      saving: _saving,
      saveLabel: _selected.isEmpty ? 'Guardar' : 'Guardar ${_selected.length} permisos',
      onCancel: () => Navigator.of(context).pop(false),
      onSave: _save,
      children: [
        SizedBox(
          height: 430,
          child: widget.modules.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.window_outlined,
                          size: 40, color: scheme.onSurfaceVariant),
                      const SizedBox(height: 12),
                      const Text(
                        'No hay módulos registrados en la base de datos',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Agrega módulos a la tabla "modules" para poder asignar acciones.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: widget.modules.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) =>
                      _ModuleCard(module: widget.modules[i], state: this),
                ),
        ),
      ],
    );
  }
}

/// Tarjeta de un módulo: checkbox tri-estado + acciones como chips-check.
class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module, required this.state});

  final Map<String, dynamic> module;
  final _PermissionsDialogState state;

  List<Map<String, dynamic>> get _actions =>
      ((module['actions'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final keys =
        _actions.map((a) => state._k(module['id'], a['id'])).toList();
    final selectedCount = keys.where(state._selected.contains).length;
    final _Check stateChk;
    if (selectedCount == 0) {
      stateChk = _Check.none;
    } else if (selectedCount == keys.length) {
      stateChk = _Check.all;
    } else {
      stateChk = _Check.some;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: selectedCount > 0
            ? scheme.primary.withValues(alpha: .05)
            : scheme.surfaceContainerHighest.withValues(alpha: .30),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selectedCount > 0
              ? scheme.primary.withValues(alpha: .35)
              : scheme.outlineVariant.withValues(alpha: .45),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Checkbox(
                tristate: true,
                visualDensity: VisualDensity.compact,
                value: switch (stateChk) {
                  _Check.all => true,
                  _Check.some => null,
                  _Check.none => false,
                },
                onChanged: (v) => state._toggleModule(module, v),
              ),
              Icon(Icons.window_outlined,
                  size: 18,
                  color: selectedCount > 0
                      ? scheme.primary
                      : scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  (module['name'] ?? '').toString(),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: selectedCount > 0
                      ? scheme.primary.withValues(alpha: .12)
                      : scheme.surfaceContainerHighest.withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$selectedCount/${_actions.length}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: selectedCount > 0
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in _actions) _ActionChip(module: module, action: a, state: state),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _Check { none, some, all }

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.module, required this.action, required this.state});

  final Map<String, dynamic> module;
  final Map<String, dynamic> action;
  final _PermissionsDialogState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final key = state._k(module['id'], action['id']);
    final checked = state._selected.contains(key);
    final color = checked ? scheme.primary : scheme.onSurfaceVariant;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => state._toggleAction(module, action, !checked),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: checked
              ? scheme.primary.withValues(alpha: .12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: checked
                ? scheme.primary.withValues(alpha: .55)
                : scheme.outlineVariant.withValues(alpha: .6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              checked ? Icons.check_box_outlined : Icons.check_box_outline_blank,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(
              (action['label'] ?? action['key'] ?? '').toString(),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: checked ? FontWeight.w700 : FontWeight.w500,
                color: checked ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

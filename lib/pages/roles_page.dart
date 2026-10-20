import 'package:flutter/material.dart';

import '../hs_access.dart';
import '../hs_api.dart';
import '../widgets/anim.dart';
import '../widgets/common.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/form_dialog.dart';
import '../widgets/hs_folder.dart';
import '../widgets/hs_pager.dart';
import '../widgets/hs_search_filter.dart';

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

  String _query = '';

  /// Filtro por permisos: '' todos · 'con' con permisos · 'sin' sin permisos.
  String _permFilter = '';

  // Paginación del listado de roles (30 de fábrica).
  int _page = 1;
  int _pageSize = kHsDefaultPageSize;

  /// Permisos del usuario logueado (módulo "Roles").
  bool get _canCreate =>
      HsAccess.instance.degraded || HsAccess.instance.can('Roles', 'create');
  bool get _canUpdate =>
      HsAccess.instance.degraded || HsAccess.instance.can('Roles', 'update');
  bool get _canDelete =>
      HsAccess.instance.degraded || HsAccess.instance.can('Roles', 'delete');

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
        _page = 1;
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

  int _permCount(Map<String, dynamic> role) =>
      ((role['permissions'] as List?) ?? const []).length;

  /// Roles que se muestran (búsqueda y filtro en memoria: son pocos).
  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    return _roles
        .where((r) {
          final perms = _permCount(r);
          if (_permFilter == 'con' && perms == 0) return false;
          if (_permFilter == 'sin' && perms > 0) return false;
          if (q.isEmpty) return true;
          return '${r['name'] ?? ''}'.toLowerCase().contains(q) ||
              '$perms'.contains(q);
        })
        .toList(growable: false);
  }

  List<HsFilterGroup> get _filterGroups {
    final con = _roles.where((r) => _permCount(r) > 0).length;
    return [
      HsFilterGroup(
        id: 'perms',
        title: 'Permisos asignados',
        help: 'Un rol sin permisos no puede entrar a ningún módulo.',
        options: [
          HsFilterOption(
            value: '',
            label: 'Todos los roles',
            count: _roles.length,
            icon: Icons.groups_rounded,
          ),
          HsFilterOption(
            value: 'con',
            label: 'Con permisos',
            count: con,
            icon: Icons.verified_user_outlined,
            color: const Color(0xFF2F6BFF),
          ),
          HsFilterOption(
            value: 'sin',
            label: 'Sin permisos',
            count: _roles.length - con,
            icon: Icons.lock_outline_rounded,
            color: const Color(0xFFD97706),
          ),
        ],
      ),
    ];
  }

  Future<void> _openForm([Map<String, dynamic>? role]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
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
      barrierDismissible: true,
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
    } catch (_) {
      // El backend ya avisó con la notificación roja.
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PageContainer(
      module: 'rols',
      title: 'Roles',
      description: 'Define a qué módulos puede entrar cada rol y qué acciones puede realizar.',
      icon: Icons.admin_panel_settings_rounded,
      onRefresh: _reload,
      stats: [
        StatPill(
          icon: Icons.workspace_premium_outlined,
          label: '${_roles.length} roles',
        ),
        if (_modules.isNotEmpty)
          StatPill(
            icon: Icons.window_outlined,
            label: '${_modules.length} módulos',
          ),
      ],
      actions: [
        // "Crear" (create): sin el permiso, el botón no aparece.
        if (_canCreate)
          HsActionButton(
            onPressed: () => _openForm(),
            icon: Icons.add_moderator_outlined,
            label: 'Nuevo rol',
          ),
      ],
      // Barra de páginas como PIE FIJO (fuera del scroll).
      footer: HsPager(
        total: _filtered.length,
        page: _page,
        pageSize: _pageSize,
        enabled: !_loading && _error == null,
        onPage: (p) => setState(() => _page = p),
        onPageSize: (n) => setState(() {
          _pageSize = n;
          _page = 1;
        }),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HsSearchFilterBar(
            hint: 'Buscar rol por nombre…',
            initial: _query,
            onChanged: (v) => setState(() {
              _query = v;
              _page = 1;
            }),
            groups: _filterGroups,
            selected: {'perms': _permFilter},
            onApply: (filters) => setState(() {
              _permFilter = filters['perms'] ?? '';
              _page = 1;
            }),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const ListSkeleton(lines: 5)
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
          else if (_filtered.isEmpty)
            EmptyState(
              icon: Icons.admin_panel_settings_outlined,
              title: _roles.isEmpty ? 'Sin roles' : 'Sin resultados',
              message: _roles.isEmpty
                  ? 'Crea el primer rol con el botón "Nuevo rol".'
                  : 'Ningún rol coincide con la búsqueda o el filtro elegido.',
            )
          else ...[
            Builder(
              builder: (context) {
                final rows = HsPages(
                  total: _filtered.length,
                  page: _page,
                  pageSize: _pageSize,
                ).slice(_filtered);
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
                          child: _RoleTile(
                            role: rows[i],
                            onEdit: _canUpdate
                                ? () => _openForm(rows[i])
                                : null,
                            onPermissions: _canUpdate
                                ? () => _openPermissions(rows[i])
                                : null,
                            onDelete: _canDelete
                                ? () => _delete(rows[i])
                                : null,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
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

  /// null = el usuario no tiene el permiso → el botón NO se muestra.
  final VoidCallback? onEdit;
  final VoidCallback? onPermissions;
  final VoidCallback? onDelete;

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
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
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
          const SizedBox(width: 8),
          // CELULAR: las tres acciones (permisos, renombrar, eliminar) viajan
          // en el menú "⋮" para no comerse el ancho de la fila. Sin ninguna
          // opción disponible por permisos, el menú NO se dibuja.
          if (hsRowCompact(context))
            HsRowMenu(
              actions: [
                HsMenuAction(
                  icon: Icons.tune,
                  label: 'Acciones y permisos',
                  onTap: onPermissions,
                ),
                HsMenuAction(
                  icon: Icons.edit_outlined,
                  label: 'Renombrar',
                  onTap: onEdit,
                ),
                HsMenuAction(
                  icon: Icons.delete_outline,
                  label: 'Eliminar',
                  onTap: onDelete,
                  destructive: true,
                ),
              ],
            )
          else ...[
            // Botón de icono (como Renombrar/Eliminar): el rótulo "Acciones"
            // ocupaba demasiado ancho en la lista.
            if (onPermissions != null)
              IconButton(
                tooltip: 'Acciones y permisos',
                onPressed: onPermissions,
                icon: Icon(Icons.tune, size: 20, color: scheme.primary),
              ),
            if (onEdit != null)
              IconButton(
                tooltip: 'Renombrar',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
            if (onDelete != null)
              IconButton(
                tooltip: 'Eliminar',
                onPressed: onDelete,
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: scheme.error.withValues(alpha: .8),
                ),
              ),
          ],
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
    _name = TextEditingController(
      text: (widget.role?['name'] ?? '').toString(),
    );
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
        await HsApi.updateRole({
          'id': (widget.role!['id'] as num).toInt(),
          'name': name,
        });
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

  /// REGLA: "Ver" (read) es la puerta del módulo — al QUITARLO se limpian
  /// también create/update/delete/download del módulo.
  void _enforceReadRule(Set<String> sel) {
    for (final key in List.of(sel)) {
      final parts = key.split(':');
      final readKey = '${parts[0]}:2';
      if (!sel.contains(readKey)) sel.remove(key);
    }
  }

  void _toggleModule(Map<String, dynamic> module, bool? v) {
    if (_saving) return;
    final keys = _actions(module)
        .map((a) => _k(module['id'], a['id']))
        .toList();
    setState(() {
      if (v ?? true) {
        _selected.addAll(keys);
      } else {
        _selected.removeAll(keys);
      }
      _enforceReadRule(_selected);
    });
  }

  void _toggleAction(
    Map<String, dynamic> module,
    Map<String, dynamic> action,
    bool? v,
  ) {
    if (_saving) return;
    setState(() {
      if (v ?? false) {
        _selected.add(_k(module['id'], action['id']));
      } else {
        _selected.remove(_k(module['id'], action['id']));
      }
      _enforceReadRule(_selected);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    // Regla de negocio ANTES de agrupar: sin "Ver" no hay más acciones.
    _enforceReadRule(_selected);
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
    } catch (_) {
      // El backend ya avisó con la notificación roja.
      if (mounted) setState(() => _saving = false);
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
      // Sin contentHeight: la lista es plana (shrinkWrap) y mide lo que
      // ocupa; el scroll del diálogo la desplaza si no cabe.
      saving: _saving,
      saveLabel: _selected.isEmpty
          ? 'Guardar'
          : 'Guardar ${_selected.length} permisos',
      onCancel: () => Navigator.of(context).pop(false),
      onSave: _save,
      children: [
        // LISTA PLANA con Column: NADA de ListView/shrinkWrap dentro de un
        // AlertDialog — el viewport obliga al framework a calcular dimensions
        // intrínsecas y crashea ("RenderShrinkWrappingViewport does not
        // support returning intrinsic dimensions"). El FormDialog ya provee
        // el ÚNICO scroll de la ventana.
        if (widget.modules.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.window_outlined,
                  size: 40,
                  color: scheme.onSurfaceVariant,
                ),
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
        else
          ..._buildModuleList(scheme),
      ],
    );
  }

  /// CATEGORÍAS como CARPETAS: cada grupo (Operación, Administración,
  /// Catálogos…) es una carpeta que se abre y se cierra, y dentro van sus
  /// módulos, también con forma de carpeta. Los módulos sueltos (Dashboard)
  /// caen en “General”.
  ///
  /// El contador de cada carpeta ("8/20") es la suma de sus módulos, así se ve
  /// de un vistazo qué grupo está tocado sin abrirlo.
  List<Widget> _buildModuleList(ColorScheme scheme) {
    final groups = <String, List<Map<String, dynamic>>>{};
    final order = <String>[];
    for (final m in widget.modules) {
      final cat = (m['categoryName'] ?? '').toString().trim();
      final key = cat.isEmpty ? 'General' : cat;
      if (!groups.containsKey(key)) {
        groups[key] = <Map<String, dynamic>>[];
        order.add(key);
      }
      groups[key]!.add(m);
    }

    final out = <Widget>[];
    for (final key in order) {
      final mods = groups[key]!;
      var selected = 0;
      var total = 0;
      for (final m in mods) {
        final acts = _actions(m);
        total += acts.length;
        selected += acts
            .where((a) => _selected.contains(_k(m['id'], a['id'])))
            .length;
      }
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: HsFolderGroup(
            key: ValueKey('perm-folder-$key'),
            title: key,
            subtitle:
                '${mods.length} ${mods.length == 1 ? 'módulo' : 'módulos'}',
            icon: _categoryIcon(key),
            selected: selected,
            total: total,
            // Se abre la carpeta que ya tiene algo marcado (o todas si hay
            // pocas): lo demás queda plegado para no perder el hilo.
            initiallyOpen: selected > 0 || order.length <= 3,
            children: [
              for (var i = 0; i < mods.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _ModuleCard(module: mods[i], state: this),
              ],
            ],
          ),
        ),
      );
    }
    return out;
  }

  /// Icono de la carpeta según el nombre de la categoría.
  IconData _categoryIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('oper')) return Icons.handyman_rounded;
    if (n.contains('admin')) return Icons.shield_rounded;
    if (n.contains('catalog')) return Icons.collections_bookmark_rounded;
    if (n.contains('finan')) return Icons.account_balance_wallet_rounded;
    if (n.contains('sitio') || n.contains('web')) return Icons.language_rounded;
    if (n.contains('archiv') || n.contains('drive')) {
      return Icons.folder_shared_rounded;
    }
    return Icons.folder_copy_rounded;
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
    final keys = _actions.map((a) => state._k(module['id'], a['id'])).toList();
    final selectedCount = keys.where(state._selected.contains).length;
    final _Check stateChk;
    if (selectedCount == 0) {
      stateChk = _Check.none;
    } else if (selectedCount == keys.length) {
      stateChk = _Check.all;
    } else {
      stateChk = _Check.some;
    }

    // Módulo como SUB-CARPETA dentro de su categoría: pestaña corta + cuerpo.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 7,
          margin: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            color: selectedCount > 0
                ? scheme.primary.withValues(alpha: .55)
                : scheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
            border: Border.all(
              color: selectedCount > 0
                  ? scheme.primary.withValues(alpha: .45)
                  : scheme.outlineVariant.withValues(alpha: .5),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: selectedCount > 0
                ? scheme.primary.withValues(alpha: .05)
                : scheme.surfaceContainerHighest.withValues(alpha: .30),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(5),
              topRight: Radius.circular(12),
              bottomLeft: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
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
                    onChanged: state._saving
                        ? null
                        : (v) => state._toggleModule(module, v),
                  ),
                  Icon(
                    selectedCount > 0
                        ? Icons.folder_rounded
                        : Icons.folder_outlined,
                    size: 18,
                    color: selectedCount > 0
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (module['name'] ?? '').toString(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: selectedCount > 0
                          ? scheme.primary.withValues(alpha: .12)
                          : scheme.surfaceContainerHighest.withValues(
                              alpha: .7,
                            ),
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
                    for (final a in _actions)
                      _ActionChip(module: module, action: a, state: state),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _Check { none, some, all }

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.module,
    required this.action,
    required this.state,
  });

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
              checked
                  ? Icons.check_box_outlined
                  : Icons.check_box_outline_blank,
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

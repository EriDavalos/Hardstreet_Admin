import 'dart:async';

import 'package:flutter/material.dart';

import '../hs_access.dart';
import '../hs_api.dart';
import '../widgets/anim.dart';
import '../widgets/common.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/form_dialog.dart';
import '../widgets/hs_pager.dart';
import '../widgets/hs_search_filter.dart';

/// Módulo USUARIOS: CRUD completo + asignación de rol.
/// Conecta con la misma API que la web (Hardstreet-Backend):
///   GET/POST/PUT/DELETE /api/admin/users  (solo rol Admin)
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  bool _loading = true;
  String? _error;

  /// Filas de la PÁGINA actual (el backend manda solo estas).
  List<Map<String, dynamic>> _users = const [];
  List<Map<String, dynamic>> _roles = const [];
  String _query = '';

  /// Filtro por ROL ('' = todos). Sale de los conteos del backend.
  String _roleFilter = '';

  // Paginación (30 de fábrica; 50/100/200 desde el pie).
  int _page = 1;
  int _pageSize = kHsDefaultPageSize;

  /// Total de filas que calculó el SERVIDOR con la búsqueda/filtros puestos.
  int _total = 0;

  /// Total sin el filtro de rol (para el chip "Todos").
  int _allTotal = 0;

  /// Conteo por rol que manda el backend (chips), respetando la búsqueda.
  Map<String, int> _roleCounts = const {};

  /// true = el backend paginó/filtró (llegó `total`); false = respuesta vieja
  /// sin metadatos y el listado pagina en pantalla como antes.
  bool _serverPaged = false;

  Timer? _debounce;

  /// REGLA DEL ROL MÁS ALTO: las cuentas Admin solo las ve un Admin.
  bool get _iAmAdmin => HsSession.isAdmin;

  static String _roleOf(Map<String, dynamic> u) =>
      (u['role'] ?? '').toString().trim().toLowerCase();

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

  /// Busca en el servidor con una pequeña espera, para no lanzar una petición
  /// por cada tecla.
  void _search(String value) {
    setState(() {
      _query = value;
      _page = 1;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _reload);
  }

  /// Pide la página actual al backend (con búsqueda y filtro de rol).
  ///
  /// [reset] vuelve a la página 1: al buscar, filtrar, crear o eliminar.
  Future<void> _reload({bool reset = false}) async {
    if (reset) _page = 1;
    // Página pedida (antes de que el servidor la recorte).
    final asked = _page;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await HsApi.adminUsersPage(
        page: _page,
        limit: _pageSize,
        q: _query,
        role: _roleFilter,
      );
      // Los roles cambian poco: se piden una sola vez (y solo si el primero
      // intento falló, se reintentan en la siguiente carga).
      var roles = _roles;
      if (roles.isEmpty) {
        try {
          roles = await HsApi.roles();
        } catch (_) {
          // los roles solo fallan si el backend es viejo: el CRUD sigue
        }
      }
      if (!mounted) return;
      setState(() {
        _users = result.items;
        _roles = roles;
        _serverPaged = result.serverPaged;
        _total = result.total;
        _allTotal = (result.meta['allTotal'] as num?)?.toInt() ?? result.total;
        _roleCounts = {
          for (final e
              in ((result.meta['roleCounts'] as Map?) ?? const {}).entries)
            e.key.toString(): (e.value as num?)?.toInt() ?? 0,
        };
        if (result.serverPaged) _page = result.page;
        _loading = false;
      });
      // Si la última fila de la última página se borró, la página pedida ya no
      // existe (el servidor devuelve las filas vacías): pide la última real.
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
        _error = 'No se pudo cargar la lista de usuarios';
        _loading = false;
      });
    }
  }

  Future<void> _openForm([Map<String, dynamic>? user]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _UserFormDialog(user: user, roles: _roles),
    );
    // Al CREAR se vuelve a la página 1 (la fila nueva queda a la vista).
    if (saved == true) _reload(reset: user == null);
  }

  Future<void> _delete(Map<String, dynamic> user) async {
    final ok = await confirmDelete(
      context,
      title: '¿Eliminar usuario?',
      message:
          '${user['name'] ?? ''} (${user['email'] ?? ''}) dejará de tener acceso. Esta acción no se puede deshacer.',
    );
    if (!ok) return;
    try {
      await HsApi.deleteUser((user['id'] as num).toInt());
    } catch (_) {
      // El backend ya avisó con la notificación roja.
    }
    _reload();
  }

  /// Roles que aparecen en el filtro.
  ///
  /// Con el backend paginado salen de los CONTEOS que manda (así aparecen
  /// roles que todavía no están en esta página); Admin solo para un Admin.
  List<String> get _filterRoles {
    final names = <String>{};
    if (_serverPaged) {
      names.addAll(_roleCounts.keys);
    } else {
      for (final u in _users) {
        final r = (u['role'] ?? '').toString().trim();
        if (r.isNotEmpty) names.add(r);
      }
    }
    final out =
        names.where((r) => _iAmAdmin || r.toLowerCase() != 'admin').toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  /// Total del chip "Todos" (respeta la búsqueda, no el rol elegido).
  int get _countAll => _serverPaged ? _allTotal : _users.length;

  int _countOfRole(String role) => _serverPaged
      ? (_roleCounts[role] ?? 0)
      : _users.where((u) => _roleOf(u) == role.toLowerCase()).length;

  /// Filas que se pintan.
  ///
  /// Con el backend nuevo son TAL CUAL la página que devolvió (ya filtró él).
  /// Con uno viejo (respuesta sin `total`) se filtra aquí, como antes.
  List<Map<String, dynamic>> get _visible {
    if (_serverPaged) return _users;
    final q = _query.trim().toLowerCase();
    final role = _roleFilter.trim().toLowerCase();
    return _users.where((u) {
      // Los Admin no se listan a quien no es Admin.
      if (!_iAmAdmin && _roleOf(u) == 'admin') return false;
      if (role.isNotEmpty && _roleOf(u) != role) return false;
      if (q.isEmpty) return true;
      final hay =
          '${u['name'] ?? ''} ${u['lastname'] ?? ''} ${u['email'] ?? ''} ${u['role'] ?? ''}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

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

  /// Opciones del módulo de filtros: los roles con su conteo.
  List<HsFilterGroup> get _filterGroups => [
    HsFilterGroup(
      id: 'role',
      title: 'Rol de la cuenta',
      help: 'El conteo respeta la búsqueda que escribas arriba.',
      options: [
        HsFilterOption(
          value: '',
          label: 'Todos los usuarios',
          count: _countAll,
          icon: Icons.groups_rounded,
        ),
        for (final r in _filterRoles)
          HsFilterOption(
            value: r,
            label: r,
            count: _countOfRole(r),
            icon: Icons.badge_outlined,
          ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PageContainer(
      module: 'users',
      title: 'Usuarios',
      description:
          'Crea, actualiza y elimina cuentas del equipo, y asígnales su rol.',
      icon: Icons.people_alt_rounded,
      onRefresh: _reload,
      stats: [
        StatPill(icon: Icons.person_outline, label: '$_countAll usuarios'),
        if (_roles.isNotEmpty)
          StatPill(
            icon: Icons.admin_panel_settings_outlined,
            label: '${_roles.length} roles',
          ),
      ],
      actions: [
        // "Crear" (create): sin el permiso, el botón no aparece.
        if (HsAccess.instance.degraded ||
            HsAccess.instance.can('Usuarios', 'create'))
          HsActionButton(
            onPressed: () => _openForm(),
            icon: Icons.person_add_alt,
            label: 'Nuevo usuario',
          ),
      ],
      // La barra de páginas queda como PIE FIJO: no se va con el último dato.
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
          // Buscar vuelve a la página 1 y consulta al servidor.
          HsSearchFilterBar(
            hint: 'Buscar por nombre, correo o rol…',
            onChanged: _search,
            initial: _query,
            groups: _filterGroups,
            selected: {'role': _roleFilter},
            onApply: (filters) {
              final next = filters['role'] ?? '';
              if (next == _roleFilter) return;
              setState(() {
                _roleFilter = next;
                _page = 1;
              });
              _reload();
            },
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
          else if (_visible.isEmpty)
            const EmptyState(
              icon: Icons.people_alt_outlined,
              title: 'Sin usuarios',
              message: 'No hay usuarios que coincidan con la búsqueda. Crea el primero con el botón "Nuevo usuario".',
            )
          else ...[
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < _pageRows.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, color: Theme.of(context).dividerColor),
                    StaggeredItem(
                      index: i,
                      child: _UserTile(
                        user: _pageRows[i], // La cuenta Admin solo la toca un Admin.
                        onEdit:
                            (_iAmAdmin || _roleOf(_pageRows[i]) != 'admin') &&
                                (HsAccess.instance.degraded ||
                                    HsAccess.instance.can('Usuarios', 'update'))
                            ? () => _openForm(_pageRows[i])
                            : null,
                        onDelete:
                            (_iAmAdmin || _roleOf(_pageRows[i]) != 'admin') &&
                                (HsAccess.instance.degraded ||
                                    HsAccess.instance.can('Usuarios', 'delete'))
                            ? () => _delete(_pageRows[i])
                            : null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> user;

  /// null = el usuario no tiene el permiso → el botón NO se muestra.
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = '${user['name'] ?? ''} ${user['lastname'] ?? ''}'
        .trim()
        .trim();
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    final role = (user['role'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: scheme.primary.withValues(alpha: .12),
            child: Text(
              initial,
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
                  name.isEmpty ? (user['email'] ?? '').toString() : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  (user['email'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: role.toLowerCase() == 'admin'
                  ? scheme.primary.withValues(alpha: .12)
                  : scheme.surfaceContainerHighest.withValues(alpha: .7),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              role.isEmpty ? 'Sin rol' : role,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: role.toLowerCase() == 'admin'
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // CELULAR: los botones de la fila van dentro del menú "⋮" (mismo
          // patrón que el directorio de clientes). Sin ninguna opción
          // disponible por permisos, el menú NO se dibuja.
          if (hsRowCompact(context))
            HsRowMenu(
              actions: [
                HsMenuAction(
                  icon: Icons.edit_outlined,
                  label: 'Editar y asignar rol',
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
            if (onEdit != null)
              IconButton(
                tooltip: 'Editar y asignar rol',
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

/// Dialogo de alta/edicion de usuario con el diseño estándar:
/// preview de avatar en vivo + secciones (datos, acceso, rol).
class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({required this.roles, this.user});

  final Map<String, dynamic>? user;
  final List<Map<String, dynamic>> roles;

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _lastname;
  late final TextEditingController _number;
  late final TextEditingController _email;
  late final TextEditingController _password;
  // NO `late final`: alternar la visibilidad reasigna el valor; con `final`
  // el botón del ojo lanzaba LateInitializationError y no hacía nada.
  bool _showPassword = false;
  int? _roleId;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.user != null;

  @override
  void initState() {
    super.initState();
    final u = widget.user ?? const {};
    _name = TextEditingController(text: (u['name'] ?? '').toString());
    _lastname = TextEditingController(text: (u['lastname'] ?? '').toString());
    _number = TextEditingController(text: (u['number'] ?? '').toString());
    _email = TextEditingController(text: (u['email'] ?? '').toString());
    _password = TextEditingController();
    _roleId = u['roleId'] is int
        ? u['roleId'] as int
        : (u['roleId'] is num ? (u['roleId'] as num).toInt() : null);
  }

  @override
  void dispose() {
    _name.dispose();
    _lastname.dispose();
    _number.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String get _initials {
    final n = _name.text.trim();
    final l = _lastname.text.trim();
    final a = n.isNotEmpty ? n.characters.first.toUpperCase() : '';
    final b = l.isNotEmpty ? l.characters.first.toUpperCase() : '';
    final out = '$a$b';
    return out.isNotEmpty ? out : (n.isNotEmpty ? n[0].toUpperCase() : '?');
  }

  String get _roleName {
    for (final r in widget.roles) {
      if ((r['id'] as num).toInt() == _roleId) {
        return (r['name'] ?? '').toString();
      }
    }
    return 'Sin rol';
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (name.isEmpty || email.isEmpty) {
      setState(() => _error = 'Nombre y correo son obligatorios');
      return;
    }
    if (!_editing && _password.text.isEmpty) {
      setState(() => _error = 'Escribe una contraseña para la cuenta nueva');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = <String, dynamic>{
      'name': name,
      'lastname': _lastname.text.trim(),
      'number': _number.text.trim(),
      'email': email,
      'id_role': _roleId,
    };
    // Al EDITAR, la contraseña solo viaja si se escribió una nueva. Antes se
    // quedaba en pantalla sin enviarse y parecía que no cambiaba.
    if (_editing && _password.text.isNotEmpty) {
      body['password'] = _password.text;
    }
    try {
      if (_editing) {
        await HsApi.updateUser({
          'id': (widget.user!['id'] as num).toInt(),
          ...body,
        });
      } else {
        await HsApi.createUser({...body, 'password': _password.text});
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
          _error = 'No se pudo guardar el usuario';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final nameField = TextField(
      controller: _name,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(
        labelText: 'Nombre',
        prefixIcon: Icon(Icons.badge_outlined, size: 20),
      ),
      onChanged: (_) => setState(() {}),
    );
    final lastnameField = TextField(
      controller: _lastname,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(
        labelText: 'Apellidos',
        prefixIcon: Icon(Icons.badge_outlined, size: 20),
      ),
      onChanged: (_) => setState(() {}),
    );
    final numberField = TextField(
      controller: _number,
      keyboardType: TextInputType.phone,
      decoration: const InputDecoration(
        labelText: 'Teléfono',
        prefixIcon: Icon(Icons.call_outlined, size: 20),
      ),
    );
    final emailField = TextField(
      controller: _email,
      keyboardType: TextInputType.emailAddress,
      decoration: const InputDecoration(
        labelText: 'Correo electrónico',
        prefixIcon: Icon(Icons.alternate_email, size: 20),
      ),
    );
    final passwordField = TextField(
      key: const ValueKey('user-password'),
      controller: _password,
      obscureText: !_showPassword,
      autofillHints: const [AutofillHints.newPassword],
      decoration: InputDecoration(
        labelText: _editing ? 'Nueva contraseña (opcional)' : 'Contraseña',
        helperText: _editing
            ? 'Déjala vacía para conservar la actual.'
            : null,
        prefixIcon: const Icon(Icons.lock_outline, size: 20),
        suffixIcon: IconButton(
          tooltip: _showPassword ? 'Ocultar' : 'Mostrar',
          onPressed: () => setState(() => _showPassword = !_showPassword),
          icon: Icon(
            _showPassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size: 20,
          ),
        ),
      ),
    );
    // ROL en COMBO BOX moderno: una sola elección, con el icono del rol, su
    // nombre y cuántos permisos trae. Debajo, un resumen en vivo de lo que
    // podrá hacer la cuenta.
    final selectedRole = _selectedRole;
    final roleField = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int?>(
          key: const ValueKey('user-role-select'),
          initialValue: _roleId,
          isExpanded: true,
          // Cada opción lleva dos líneas: con `isDense` (48 px fijos) el texto
          // se salía 11 px por abajo. Altura intrínseca y sin comprimir.
          isDense: false,
          itemHeight: null,
          borderRadius: BorderRadius.circular(14),
          dropdownColor: scheme.surfaceContainerHigh,
          icon: const Icon(Icons.expand_more_rounded),
          decoration: const InputDecoration(
            labelText: 'Rol de la cuenta',
            prefixIcon: Icon(Icons.admin_panel_settings_outlined, size: 20),
            helperText: 'Define a qué módulos puede entrar la cuenta.',
            helperMaxLines: 2,
          ),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: _RoleOption(
                icon: Icons.person_outline_rounded,
                label: 'Sin rol',
                subtitle: 'Solo cuenta, sin módulos',
              ),
            ),
            for (final r in _assignableRoles)
              DropdownMenuItem<int?>(
                key: ValueKey('user-role-${r['id']}'),
                value: (r['id'] as num).toInt(),
                child: _RoleOption(
                  icon: _roleIcon(r),
                  label: (r['name'] ?? '').toString(),
                  subtitle: _roleSubtitle(r),
                  badge: _rolePermCount(r) > 0 ? '${_rolePermCount(r)}' : '',
                ),
              ),
          ],
          onChanged: _saving
              ? null
              : (value) => setState(() => _roleId = value),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: scheme.primary.withValues(alpha: .18),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  selectedRole == null
                      ? Icons.person_outline_rounded
                      : _roleIcon(selectedRole),
                  size: 18,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _roleName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      selectedRole == null
                          ? 'La cuenta podrá entrar, pero sin acceso a módulos.'
                          : '${_roleSubtitle(selectedRole)} · este es el acceso '
                                'que tendrá la cuenta.',
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return FormDialog(
      icon: _editing ? Icons.edit_rounded : Icons.person_add_alt,
      title: _editing ? 'Editar usuario' : 'Nuevo usuario',
      subtitle: _editing
          ? 'Actualiza los datos o cambia el rol de la cuenta.'
          : 'La cuenta podrá iniciar sesión en la web y el panel según su rol.',
      saving: _saving,
      error: _error,
      saveLabel: _editing ? 'Guardar cambios' : 'Crear usuario',
      maxWidth: 520,
      onCancel: () => Navigator.of(context).pop(false),
      onSave: _save,
      children: [
        // Cabecera de preview: avatar con iniciales + nombre y rol en vivo
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                scheme.primary.withValues(alpha: .10),
                scheme.primary.withValues(alpha: .03),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.primary.withValues(alpha: .18)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2F6BFF), Color(0xFF1D4ED8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_name.text.trim()} ${_lastname.text.trim()}'
                              .trim()
                              .isEmpty
                          ? 'Nuevo usuario'
                          : '${_name.text.trim()} ${_lastname.text.trim()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _email.text.trim().isEmpty
                          ? _roleName
                          : '${_email.text.trim()}  ·  $_roleName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FormSection(
          label: 'Datos personales',
          child: _wide
              ? Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: nameField),
                        const SizedBox(width: 12),
                        Expanded(child: lastnameField),
                      ],
                    ),
                    const SizedBox(height: 12),
                    numberField,
                  ],
                )
              : Column(
                  children: [
                    nameField,
                    const SizedBox(height: 12),
                    lastnameField,
                    const SizedBox(height: 12),
                    numberField,
                  ],
                ),
        ),
        const SizedBox(height: 16),
        FormSection(
          label: 'Acceso',
          child: Column(
            children: [emailField, const SizedBox(height: 12), passwordField],
          ),
        ),
        const SizedBox(height: 16),
        FormSection(label: 'Rol', child: roleField),
      ],
    );
  }

  bool get _wide => MediaQuery.sizeOf(context).width > 560;

  /// Rol actualmente elegido (null = sin rol).
  Map<String, dynamic>? get _selectedRole {
    for (final r in _assignableRoles) {
      if ((r['id'] as num?)?.toInt() == _roleId) return r;
    }
    return null;
  }

  /// Roles que se pueden asignar desde aquí.
  ///
  /// El rol Admin es el más alto: solo un Admin puede darlo (el backend
  /// devuelve 403 si otro rol lo intenta).
  List<Map<String, dynamic>> get _assignableRoles => widget.roles
      .where(
        (r) =>
            HsSession.isAdmin ||
            (r['name'] ?? '').toString().toLowerCase() != 'admin',
      )
      .toList();

  int _rolePermCount(Map<String, dynamic> r) =>
      ((r['permissions'] as List?) ?? const []).length;

  String _roleSubtitle(Map<String, dynamic> r) {
    final n = _rolePermCount(r);
    if (n == 0) return 'Sin permisos';
    final modules = ((r['permissions'] as List?) ?? const [])
        .whereType<Map>()
        .map((p) => p['moduleId'])
        .toSet()
        .length;
    return '$modules módulos · $n acciones';
  }

  IconData _roleIcon(Map<String, dynamic> r) {
    final name = (r['name'] ?? '').toString().toLowerCase();
    if (name.contains('admin')) return Icons.shield_rounded;
    if (name.contains('client')) return Icons.people_alt_rounded;
    if (name.contains('emple')) return Icons.badge_rounded;
    if (name.contains('foto') || name.contains('video')) {
      return Icons.photo_camera_rounded;
    }
    return Icons.folder_rounded;
  }
}

/// Opción del combo de roles: icono + nombre + permisos que trae.
class _RoleOption extends StatelessWidget {
  const _RoleOption({
    required this.icon,
    required this.label,
    this.subtitle = '',
    this.badge = '',
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 16, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle.isNotEmpty)
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
          ),
        ),
        if (badge.isNotEmpty) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              badge,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

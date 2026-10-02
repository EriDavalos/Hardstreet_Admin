import 'package:flutter/material.dart';

import '../hs_access.dart';
import '../hs_api.dart';
import '../widgets/anim.dart';
import '../widgets/common.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/form_dialog.dart';

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
  List<Map<String, dynamic>> _users = const [];
  List<Map<String, dynamic>> _roles = const [];
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
      final users = await HsApi.adminUsers();
      List<Map<String, dynamic>> roles = const [];
      try {
        roles = await HsApi.roles();
      } catch (_) {
        // los roles solo fallan si el backend es viejo: el CRUD sigue
      }
      if (!mounted) return;
      setState(() {
        _users = users;
        _roles = roles;
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
        _error = 'No se pudo cargar la lista de usuarios';
        _loading = false;
      });
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openForm([Map<String, dynamic>? user]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UserFormDialog(user: user, roles: _roles),
    );
    if (saved == true) _reload();
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
      _snack('Usuario eliminado');
      _reload();
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo eliminar el usuario');
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _users;
    return _users.where((u) {
      final hay =
          '${u['name'] ?? ''} ${u['lastname'] ?? ''} ${u['email'] ?? ''} ${u['role'] ?? ''}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PageContainer(
      title: 'Usuarios',
      description:
          'Crea, actualiza y elimina cuentas del equipo, y asígnales su rol.',
      icon: Icons.people_alt_rounded,
      stats: [
        StatPill(icon: Icons.person_outline, label: '${_users.length} usuarios'),
        if (_roles.isNotEmpty)
          StatPill(
              icon: Icons.admin_panel_settings_outlined,
              label: '${_roles.length} roles'),
      ],
      actions: [
        // "Crear" (create): sin el permiso, el botón no aparece.
        if (HsAccess.instance.degraded || HsAccess.instance.can('Usuarios', 'create'))
          FilledButton.icon(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: const Text('Nuevo usuario'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Buscar por nombre, correo o rol…',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => setState(() => _query = ''),
                      icon: const Icon(Icons.close, size: 18),
                    ),
            ),
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
              icon: Icons.people_alt_outlined,
              title: 'Sin usuarios',
              message:
                  'No hay usuarios que coincidan con la búsqueda. Crea el primero con el botón "Nuevo usuario".',
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < _filtered.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, color: Theme.of(context).dividerColor),
                    StaggeredItem(
                      index: i,
                      child: _UserTile(
                        user: _filtered[i],
                        onEdit: HsAccess.instance.degraded ||
                                HsAccess.instance.can('Usuarios', 'update')
                            ? () => _openForm(_filtered[i])
                            : null,
                        onDelete: HsAccess.instance.degraded ||
                                HsAccess.instance.can('Usuarios', 'delete')
                            ? () => _delete(_filtered[i])
                            : null,
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
    final name =
        '${user['name'] ?? ''} ${user['lastname'] ?? ''}'.trim().trim();
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
              icon: Icon(Icons.delete_outline,
                  size: 20, color: scheme.error.withValues(alpha: .8)),
            ),
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
  late final bool _showPassword;
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
    _showPassword = false;
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
    try {
      if (_editing) {
        await HsApi.updateUser(
            {'id': (widget.user!['id'] as num).toInt(), ...body});
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
      controller: _password,
      obscureText: !_showPassword,
      decoration: InputDecoration(
        labelText: _editing ? 'Nueva contraseña (opcional)' : 'Contraseña',
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
    final roleField = DropdownButtonFormField<int>(
      initialValue: _roleId,
      decoration: const InputDecoration(
        labelText: 'Rol de la cuenta',
        prefixIcon: Icon(Icons.admin_panel_settings_outlined, size: 20),
      ),
      items: [
        const DropdownMenuItem<int>(
          value: null,
          child: Text('Sin rol'),
        ),
        for (final r in widget.roles)
          DropdownMenuItem<int>(
            value: (r['id'] as num).toInt(),
            child: Text((r['name'] ?? '').toString()),
          ),
      ],
      onChanged: (v) => setState(() => _roleId = v),
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
                          fontWeight: FontWeight.w800, fontSize: 14.5),
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
            children: [
              emailField,
              const SizedBox(height: 12),
              passwordField,
            ],
          ),
        ),
        const SizedBox(height: 16),
        FormSection(
          label: 'Rol',
          child: roleField,
        ),
      ],
    );
  }

  bool get _wide => MediaQuery.sizeOf(context).width > 560;
}

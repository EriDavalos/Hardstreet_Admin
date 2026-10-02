import 'package:flutter/material.dart';

import '../hs_access.dart';
import '../hs_api.dart';
import '../widgets/anim.dart';
import '../widgets/common.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/form_dialog.dart';

/// Módulo CLIENTES: usuarios con rol fijo "Client" (no se asigna rol).
/// CRUD + modal especial que muestra y administra los paquetes del cliente.
class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _clients = const [];
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
      final clients = await HsApi.clients();
      if (!mounted) return;
      setState(() {
        _clients = clients;
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
        _error = 'No se pudo cargar la lista de clientes';
        _loading = false;
      });
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openForm([Map<String, dynamic>? client]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ClientFormDialog(client: client),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(Map<String, dynamic> client) async {
    final ok = await confirmDelete(
      context,
      title: '¿Eliminar cliente?',
      message:
          '${client['name'] ?? ''} (${client['email'] ?? ''}) perderá el acceso a su galería. Sus paquetes quedarán desvinculados.',
    );
    if (!ok) return;
    try {
      await HsApi.deleteClient((client['id'] as num).toInt());
      _snack('Cliente eliminado');
      _reload();
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo eliminar el cliente');
    }
  }

  Future<void> _openPackages(Map<String, dynamic> client) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PackagesDialog(client: client),
    );
    _reload(); // el conteo pudo cambiar
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _clients;
    return _clients.where((u) {
      final hay =
          '${u['name'] ?? ''} ${u['lastname'] ?? ''} ${u['email'] ?? ''} ${u['number'] ?? ''}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PageContainer(
      title: 'Clientes',
      description:
          'Directorio de clientes (rol fijo "Client") y administración de sus paquetes.',
      icon: Icons.badge_rounded,
      stats: [
        StatPill(icon: Icons.people_outline, label: '${_clients.length} clientes'),
        StatPill(
            icon: Icons.inventory_2_outlined,
            label: '${_clients.fold<int>(0, (a, c) => a + ((c['packagesCount'] as num?)?.toInt() ?? 0))} paquetes asignados'),
      ],
      actions: [
        // "Crear" (create): sin el permiso, el botón no aparece.
        if (HsAccess.instance.degraded || HsAccess.instance.can('Clientes', 'create'))
          FilledButton.icon(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.badge_outlined, size: 18),
            label: const Text('Nuevo cliente'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Buscar por nombre, correo o teléfono…',
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
          else if (_filtered.isEmpty)
            const EmptyState(
              icon: Icons.badge_outlined,
              title: 'Sin clientes',
              message:
                  'No hay clientes que coincidan. Crea el primero con el botón "Nuevo cliente".',
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
                      child: _ClientTile(
                        client: _filtered[i],
                        onEdit: HsAccess.instance.degraded ||
                                HsAccess.instance.can('Clientes', 'update')
                            ? () => _openForm(_filtered[i])
                            : null,
                        onPackages: HsAccess.instance.degraded ||
                                HsAccess.instance.can('Clientes', 'update')
                            ? () => _openPackages(_filtered[i])
                            : null,
                        onDelete: HsAccess.instance.degraded ||
                                HsAccess.instance.can('Clientes', 'delete')
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

class _ClientTile extends StatelessWidget {
  const _ClientTile({
    required this.client,
    required this.onEdit,
    required this.onPackages,
    required this.onDelete,
  });

  final Map<String, dynamic> client;

  /// null = el usuario no tiene el permiso → el botón NO se muestra.
  final VoidCallback? onEdit;
  final VoidCallback? onPackages;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name =
        '${client['name'] ?? ''} ${client['lastname'] ?? ''}'.trim().trim();
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    final pkgCount = (client['packagesCount'] as num?)?.toInt() ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: .14),
            child: Text(
              initial,
              style: const TextStyle(
                color: Color(0xFF8B5CF6),
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
                  name.isEmpty ? (client['email'] ?? '').toString() : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  (client['email'] ?? '').toString(),
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
          // Chip de paquetes = atajo al modal de paquetes
          _PkgChip(count: pkgCount, onTap: onPackages),
          const SizedBox(width: 8),
          if (onPackages != null)
            IconButton(
              tooltip: 'Paquetes',
              onPressed: onPackages,
              icon: const Icon(Icons.card_giftcard_outlined, size: 20),
            ),
          if (onEdit != null)
            IconButton(
              tooltip: 'Editar',
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

class _PkgChip extends StatelessWidget {
  const _PkgChip({required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: count > 0
              ? const Color(0xFF8B5CF6).withValues(alpha: .12)
              : scheme.surfaceContainerHighest.withValues(alpha: .7),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 14,
              color: count > 0 ? const Color(0xFF8B5CF6) : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              '$count ${count == 1 ? 'paquete' : 'paquetes'}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color:
                    count > 0 ? const Color(0xFF8B5CF6) : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialogo de alta/edicion de cliente (rol fijo) con el diseño estándar.
class _ClientFormDialog extends StatefulWidget {
  const _ClientFormDialog({this.client});

  final Map<String, dynamic>? client;

  @override
  State<_ClientFormDialog> createState() => _ClientFormDialogState();
}

class _ClientFormDialogState extends State<_ClientFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _lastname;
  late final TextEditingController _number;
  late final TextEditingController _email;
  late final TextEditingController _password;
  bool _showPassword = false;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.client != null;

  @override
  void initState() {
    super.initState();
    final c = widget.client ?? const {};
    _name = TextEditingController(text: (c['name'] ?? '').toString());
    _lastname = TextEditingController(text: (c['lastname'] ?? '').toString());
    _number = TextEditingController(text: (c['number'] ?? '').toString());
    _email = TextEditingController(text: (c['email'] ?? '').toString());
    _password = TextEditingController();
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
      if (!_editing) 'password': _password.text,
    };
    try {
      if (_editing) {
        await HsApi.updateClient(
            {'id': (widget.client!['id'] as num).toInt(), ...body});
      } else {
        await HsApi.createClient(body);
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
          _error = 'No se pudo guardar el cliente';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const accent = Color(0xFF8B5CF6);

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
        labelText: 'Contraseña',
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

    return FormDialog(
      icon: _editing ? Icons.edit_rounded : Icons.badge_outlined,
      title: _editing ? 'Editar cliente' : 'Nuevo cliente',
      subtitle: 'El rol siempre es "Client": se asigna automáticamente.',
      saving: _saving,
      error: _error,
      saveLabel: _editing ? 'Guardar cambios' : 'Crear cliente',
      maxWidth: 520,
      onCancel: () => Navigator.of(context).pop(false),
      onSave: _save,
      children: [
        // Preview con acento morado (identidad del módulo Clientes)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: .10),
                accent.withValues(alpha: .03),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: .20)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
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
                      '${_name.text.trim()} ${_lastname.text.trim()}'.trim().isEmpty
                          ? 'Nuevo cliente'
                          : '${_name.text.trim()} ${_lastname.text.trim()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14.5),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _email.text.trim().isEmpty
                          ? 'Cliente · Hardstreet'
                          : '${_email.text.trim()}  ·  Cliente',
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
          child: MediaQuery.sizeOf(context).width > 560
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
              if (!_editing) passwordField,
            ],
          ),
        ),
      ],
    );
  }
}

// ==================================================================
// Modal "Paquetes del cliente": lista + asignar/quitar
// ==================================================================

class _PackagesDialog extends StatefulWidget {
  const _PackagesDialog({required this.client});

  final Map<String, dynamic> client;

  @override
  State<_PackagesDialog> createState() => _PackagesDialogState();
}

class _PackagesDialogState extends State<_PackagesDialog> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _purchased = const [];
  List<Map<String, dynamic>> _catalog = const [];
  bool _busy = false;

  late final int _userId = (widget.client['id'] as num).toInt();
  late final String _name =
      '${widget.client['name'] ?? ''} ${widget.client['lastname'] ?? ''}'
          .trim().trim();

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
      final data = await HsApi.clientPackages(_userId);
      if (!mounted) return;
      setState(() {
        _purchased = ((data['purchasedPackages'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _catalog = ((data['catalog'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
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
        _error = 'No se pudieron cargar los paquetes';
        _loading = false;
      });
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  String _money(num v, String currency) {
    final s = v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
    return '$currency \$${_thousands(s)}';
  }

  String _thousands(String s) {
    final parts = s.split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
    return parts.length > 1 ? '$intPart.${parts[1]}' : intPart;
  }

  Future<void> _addFromCatalog() async {
    if (_catalog.isEmpty) {
      _snack('No hay paquetes en el catálogo');
      return;
    }
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Asignar paquete del catálogo'),
        children: [
          for (final p in _catalog)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        (p['name'] ?? '').toString(),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      _money((p['price'] as num?) ?? 0,
                          (p['currency'] ?? 'MXN').toString()),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      await HsApi.addPackageFromCatalog(
        _userId,
        (picked['id'] as num).toInt(),
      );
      _snack('Paquete asignado');
      await _reload();
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo asignar el paquete');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Map<String, dynamic> pkg) async {
    final ok = await confirmDelete(
      context,
      title: '¿Quitar el paquete?',
      message:
          '"${pkg['name'] ?? ''}" dejará de aparecer en el panel del cliente.',
      confirmLabel: 'Quitar',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await HsApi.removeClientPackage(
        _userId,
        (pkg['usersPackageId'] as num).toInt(),
      );
      _snack('Paquete quitado');
      await _reload();
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo quitar el paquete');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FormDialog(
      icon: Icons.card_giftcard_outlined,
      title: 'Paquetes de $_name',
      subtitle: 'Asigna o quita los paquetes que el cliente verá en su panel.',
      // En computadora el modal se ensancha y aprovecha mejor el espacio.
      maxWidth: 640,
      footer: [
        if (!_loading && _error == null)
          OutlinedButton.icon(
            onPressed: _busy ? null : _addFromCatalog,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Asignar del catálogo'),
          ),
      ],
      onCancel: () => Navigator.of(context).pop(),
      onSave: () => Navigator.of(context).pop(),
      saveLabel: 'Listo',
      children: [
        // Altura adaptativa: en pantallas cortas (móvil horizontal) el
        // contenido se reduce para que el diálogo quepa sin desbordar.
        SizedBox(
          height: (MediaQuery.sizeOf(context).height * .45)
              .clamp(240.0, 400.0),
          child: Stack(
          children: [
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              )
            else if (_purchased.isEmpty)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inventory_2_outlined,
                        size: 40, color: scheme.onSurfaceVariant),
                    const SizedBox(height: 10),
                    const Text('Este cliente aún no tiene paquetes'),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _busy ? null : _addFromCatalog,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Asignar del catálogo'),
                    ),
                  ],
                ),
              )
            else
              // Dos columnas en computadora, una en móvil.
              LayoutBuilder(builder: (context, box) {
                final twoCols = box.maxWidth > 520;
                Widget pkgCard(Map<String, dynamic> p) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest
                            .withValues(alpha: .35),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: .4),
                        ),
                      ),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(
                          (p['name'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${_money((p['price'] as num?) ?? 0, (p['currency'] ?? 'MXN').toString())}'
                          '  ·  pagado ${_money((p['paid'] as num?) ?? 0, (p['currency'] ?? 'MXN').toString())}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                (p['status'] ?? 'Pendiente').toString(),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: 'Quitar',
                              onPressed: _busy ? null : () => _remove(p),
                              icon: Icon(Icons.remove_circle_outline,
                                  size: 20,
                                  color: scheme.error.withValues(alpha: .8)),
                            ),
                          ],
                        ),
                      ),
                    );
                final cards = [for (final p in _purchased) pkgCard(p)];
                if (twoCols) {
                  return Column(
                    children: [
                      for (var i = 0; i < cards.length; i += 2)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: cards[i]),
                            if (i + 1 < cards.length)
                              const SizedBox(width: 10),
                            if (i + 1 < cards.length)
                              Expanded(child: cards[i + 1]),
                            if (i + 1 == cards.length) const Spacer(),
                          ],
                        ),
                    ],
                  );
                }
                return Column(children: cards);
              }),
          ],
          ),
        ),
      ],
    );
  }
}

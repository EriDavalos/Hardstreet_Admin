import 'package:flutter/material.dart';

import '../hs_access.dart';
import '../hs_api.dart';
import '../hs_format.dart';
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
          // Único atajo a los paquetes del cliente: el botón con el ícono de
          // paquete abre el modal donde se administran abonos y agendas.
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
// Modal "Paquetes del cliente": administración completa
//   - Paquete comprado con precios (total / pagado / saldo)
//   - Abonos (registros con monto + concepto)
//   - Agendas por servicio (fecha y hora + descripción)
//   - Asignar / quitar paquetes del catálogo
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
  List<Map<String, dynamic>> _payments = const [];
  List<Map<String, dynamic>> _agendas = const [];
  bool _busy = false;

  late final int _userId = (widget.client['id'] as num).toInt();
  late final String _name =
      '${widget.client['name'] ?? ''} ${widget.client['lastname'] ?? ''}'
          .trim()
          .trim();

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
      // Abonos y agendas son "best effort": si el servidor todavía no tiene
      // las tablas/endpoints desplegados, el modal sigue mostrando paquetes.
      var payments = const <Map<String, dynamic>>[];
      var agendas = const <Map<String, dynamic>>[];
      try {
        payments = await HsApi.packagePayments(userId: _userId);
      } catch (_) {}
      try {
        agendas = await HsApi.agendas(userId: _userId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _purchased = ((data['purchasedPackages'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _catalog = ((data['catalog'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _payments = payments;
        _agendas = agendas;
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
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  List<Map<String, dynamic>> _paymentsOf(int id) => _payments
      .where((p) => (p['purchasedPackageId'] as num?)?.toInt() == id)
      .toList();

  List<Map<String, dynamic>> _agendasOf(int id) => _agendas
      .where((a) => (a['purchasedPackageId'] as num?)?.toInt() == id)
      .toList();

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
                      hsMoney((p['price'] as num?) ?? 0,
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

  Future<void> _abonar(Map<String, dynamic> pkg) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AbonarDialog(package: pkg),
    );
    if (saved == true) {
      _snack('Abono registrado');
      await _reload();
    }
  }

  Future<void> _manageAgendas(Map<String, dynamic> pkg) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PackageAgendasDialog(package: pkg),
    );
    await _reload();
  }

  Future<void> _removePayment(Map<String, dynamic> p) async {
    final ok = await confirmDelete(
      context,
      title: '¿Quitar el abono?',
      message: 'Se descontará del total pagado del paquete.',
      confirmLabel: 'Quitar',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await HsApi.deletePackagePayment((p['id'] as num).toInt());
      await _reload();
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo quitar el abono');
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
      subtitle: 'Paquete comprado, precios, abonos y agendas del cliente.',
      maxWidth: 700,
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
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Icon(Icons.cloud_off_outlined, size: 36, color: scheme.error),
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
          )
        else if (_purchased.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
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
        else ...[
          for (final pkg in _purchased)
            _PackageAdminCard(
              package: pkg,
              payments: _paymentsOf((pkg['id'] as num).toInt()),
              agendas: _agendasOf((pkg['id'] as num).toInt()),
              busy: _busy,
              onAbonar: () => _abonar(pkg),
              onAgendas: () => _manageAgendas(pkg),
              onRemove: () => _remove(pkg),
              onRemovePayment: _removePayment,
            ),
        ],
      ],
    );
  }
}

/// Tarjeta de un paquete comprado: precios, servicios, acciones y registros.
class _PackageAdminCard extends StatefulWidget {
  const _PackageAdminCard({
    required this.package,
    required this.payments,
    required this.agendas,
    required this.busy,
    required this.onAbonar,
    required this.onAgendas,
    required this.onRemove,
    required this.onRemovePayment,
  });

  final Map<String, dynamic> package;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> agendas;
  final bool busy;
  final VoidCallback onAbonar;
  final VoidCallback onAgendas;
  final VoidCallback onRemove;
  final ValueChanged<Map<String, dynamic>> onRemovePayment;

  @override
  State<_PackageAdminCard> createState() => _PackageAdminCardState();
}

class _PackageAdminCardState extends State<_PackageAdminCard> {
  bool _showPayments = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pkg = widget.package;
    final currency = (pkg['currency'] ?? 'MXN').toString();
    final price = (pkg['price'] as num?) ?? 0;
    final paid = (pkg['paid'] as num?) ?? 0;
    final saldo = price - paid;
    final status = (pkg['status'] ?? 'Pendiente').toString();
    final pct = price > 0 ? (paid / price).clamp(0.0, 1.0) : 0.0;
    final services = ((pkg['services'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.inventory_2_outlined,
                    size: 20, color: scheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (pkg['name'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14.5),
                    ),
                    if ((pkg['subtitle'] ?? '').toString().isNotEmpty)
                      Text(
                        (pkg['subtitle'] ?? '').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(label: status),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MoneyTile(
                    'Total', hsMoney(price, currency), scheme.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MoneyTile(
                    'Pagado', hsMoney(paid, currency), const Color(0xFF10B981)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MoneyTile(
                  'Saldo',
                  hsMoney(saldo < 0 ? 0 : saldo, currency),
                  const Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
            ),
          ),
          if (services.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in services)
                  _ServicePill(
                    name: (s['name'] ?? '').toString(),
                    status: (s['status'] ?? '').toString(),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: widget.busy ? null : widget.onAbonar,
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: const Text('Abonar'),
              ),
              OutlinedButton.icon(
                onPressed: widget.busy ? null : widget.onAgendas,
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: Text('Agendas (${widget.agendas.length})'),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _showPayments = !_showPayments),
                icon: Icon(
                  _showPayments ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
                label: Text('Registros (${widget.payments.length})'),
              ),
              TextButton.icon(
                onPressed: widget.busy ? null : widget.onRemove,
                icon: Icon(Icons.remove_circle_outline,
                    size: 18, color: scheme.error),
                label: Text('Quitar', style: TextStyle(color: scheme.error)),
              ),
            ],
          ),
          if (_showPayments) ...[
            const Divider(height: 22),
            if (widget.payments.isEmpty)
              Text(
                'Sin abonos registrados.',
                style: TextStyle(
                    fontSize: 12.5, color: scheme.onSurfaceVariant),
              )
            else
              for (final p in widget.payments) _paymentRow(p, scheme, currency),
          ],
        ],
      ),
    );
  }

  Widget _paymentRow(
      Map<String, dynamic> p, ColorScheme scheme, String currency) {
    final concept = (p['description'] ?? '').toString().trim();
    final date = hsParseDate(p['created']);
    final when = date == null ? '' : hsShortDate(date);
    final subtitle = concept.isEmpty
        ? when
        : (when.isEmpty ? concept : '$concept · $when');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: .12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.payments_outlined,
                size: 16, color: Color(0xFF10B981)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hsMoney((p['amount'] as num?) ?? 0, currency),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Quitar abono',
            visualDensity: VisualDensity.compact,
            onPressed:
                widget.busy ? null : () => widget.onRemovePayment(p),
            icon: Icon(Icons.close,
                size: 16, color: scheme.error.withValues(alpha: .8)),
          ),
        ],
      ),
    );
  }
}

/// Caja compacta de un importe (Total / Pagado / Saldo).
class _MoneyTile extends StatelessWidget {
  const _MoneyTile(this.label, this.value, this.tint);

  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              letterSpacing: .7,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 14, color: tint),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip del estado del paquete comprado.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: scheme.primary,
        ),
      ),
    );
  }
}

/// Pastilla de un servicio incluido en la compra.
class _ServicePill extends StatelessWidget {
  const _ServicePill({required this.name, this.status = ''});

  final String name;
  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = status.toLowerCase() == 'entregado';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check_circle_outline : Icons.circle_outlined,
            size: 12,
            color: done ? const Color(0xFF10B981) : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          Text(
            name,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Importe pequeño dentro de una fila (Total / Pagado / Saldo).
class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: .6,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 13, color: color),
          ),
        ),
      ],
    );
  }
}

// ==================================================================
// Abonar paquete: monto + concepto del abono
// ==================================================================

class _AbonarDialog extends StatefulWidget {
  const _AbonarDialog({required this.package});

  final Map<String, dynamic> package;

  @override
  State<_AbonarDialog> createState() => _AbonarDialogState();
}

class _AbonarDialogState extends State<_AbonarDialog> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _concept = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _concept.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final amount = num.tryParse(_amount.text.replaceAll(',', '').trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Escribe un monto mayor a 0');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await HsApi.addPackagePayment(
        purchasedPackageId: (widget.package['id'] as num).toInt(),
        amount: amount,
        description: _concept.text.trim(),
      );
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
          _error = 'No se pudo registrar el abono';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pkg = widget.package;
    final currency = (pkg['currency'] ?? 'MXN').toString();
    final price = (pkg['price'] as num?) ?? 0;
    final paid = (pkg['paid'] as num?) ?? 0;
    final saldo = price - paid;

    return FormDialog(
      icon: Icons.payments_outlined,
      title: 'Abonar paquete',
      subtitle: (pkg['name'] ?? '').toString(),
      saving: _saving,
      error: _error,
      saveLabel: 'Registrar abono',
      maxWidth: 460,
      onCancel: () => Navigator.of(context).pop(false),
      onSave: _save,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: .4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: _MiniStat(
                    'Total', hsMoney(price, currency), scheme.onSurface),
              ),
              Expanded(
                child: _MiniStat(
                    'Pagado', hsMoney(paid, currency), const Color(0xFF10B981)),
              ),
              Expanded(
                child: _MiniStat('Saldo',
                    hsMoney(saldo < 0 ? 0 : saldo, currency),
                    const Color(0xFFF59E0B)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FormSection(
          label: 'Monto del abono',
          child: TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Monto',
              prefixText: '\$ ',
              prefixIcon: Icon(Icons.attach_money, size: 20),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FormSection(
          label: 'Concepto / descripción',
          child: TextField(
            controller: _concept,
            minLines: 2,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Concepto del abono',
              hintText: 'Ej. Anticipo, pago parcial, liquidación…',
              alignLabelWithHint: true,
            ),
          ),
        ),
      ],
    );
  }
}

// ==================================================================
// Agendas del paquete comprado: crear / editar / eliminar eventos
// ==================================================================

class _PackageAgendasDialog extends StatefulWidget {
  const _PackageAgendasDialog({required this.package});

  final Map<String, dynamic> package;

  @override
  State<_PackageAgendasDialog> createState() => _PackageAgendasDialogState();
}

class _PackageAgendasDialogState extends State<_PackageAgendasDialog> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _agendas = const [];
  List<Map<String, dynamic>> _services = const [];
  bool _busy = false;

  int get _packageId => (widget.package['id'] as num).toInt();

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
      final agendas = await HsApi.agendas(purchasedPackageId: _packageId);
      // Combo de servicios: los del paquete; si no tiene, el catálogo completo.
      var services = ((widget.package['services'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      if (services.isEmpty) {
        try {
          services = await HsApi.services();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _agendas = agendas;
        _services = services;
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
        _error = 'No se pudieron cargar las agendas';
        _loading = false;
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _form([Map<String, dynamic>? agenda]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AgendaFormDialog(
        purchasedPackageId: _packageId,
        services: _services,
        agenda: agenda,
      ),
    );
    if (saved == true) await _reload();
  }

  Future<void> _delete(Map<String, dynamic> agenda) async {
    final date = hsParseDate(agenda['eventDate']);
    final ok = await confirmDelete(
      context,
      title: '¿Eliminar la agenda?',
      message: date == null
          ? 'Esta agenda se eliminará del paquete.'
          : hsDateLabel(date),
      confirmLabel: 'Eliminar',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await HsApi.deleteAgenda((agenda['id'] as num).toInt());
      await _reload();
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo eliminar la agenda');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FormDialog(
      icon: Icons.event_available_outlined,
      title: 'Agendas · ${(widget.package['name'] ?? '').toString()}',
      subtitle:
          'Eventos agendados del paquete. Puedes crear varias por servicio.',
      maxWidth: 620,
      footer: [
        if (!_loading && _error == null)
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _form(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nueva agenda'),
          ),
      ],
      onCancel: () => Navigator.of(context).pop(),
      onSave: () => Navigator.of(context).pop(),
      saveLabel: 'Listo',
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
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
        else if (_agendas.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Icon(Icons.event_busy_outlined,
                    size: 40, color: scheme.onSurfaceVariant),
                const SizedBox(height: 10),
                const Text('Este paquete aún no tiene agendas'),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _form(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Crear la primera'),
                ),
              ],
            ),
          )
        else
          for (final a in _agendas) _agendaTile(a, scheme),
      ],
    );
  }

  Widget _agendaTile(Map<String, dynamic> a, ColorScheme scheme) {
    final date = hsParseDate(a['eventDate']);
    final service = (a['serviceName'] ?? '').toString();
    final desc = (a['description'] ?? '').toString();
    final monthAbbr =
        date == null ? '' : kHsMonths[date.month - 1].substring(0, 3);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  date == null ? '--' : '${date.day}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: Color(0xFF8B5CF6)),
                ),
                Text(
                  monthAbbr,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF8B5CF6)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date == null
                      ? 'Fecha por definir'
                      : '${hsDateLabel(date)} · ${hsTimeLabel(date)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  service.isEmpty ? 'Sin servicio específico' : service,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                if (desc.isNotEmpty)
                  Text(
                    desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Editar',
            visualDensity: VisualDensity.compact,
            onPressed: _busy ? null : () => _form(a),
            icon: const Icon(Icons.edit_outlined, size: 18),
          ),
          IconButton(
            tooltip: 'Eliminar',
            visualDensity: VisualDensity.compact,
            onPressed: _busy ? null : () => _delete(a),
            icon: Icon(Icons.delete_outline,
                size: 18, color: scheme.error.withValues(alpha: .8)),
          ),
        ],
      ),
    );
  }
}

/// Alta/edición de una agenda: fecha y hora + servicio + descripción.
class _AgendaFormDialog extends StatefulWidget {
  const _AgendaFormDialog({
    required this.purchasedPackageId,
    required this.services,
    this.agenda,
  });

  final int purchasedPackageId;
  final List<Map<String, dynamic>> services;
  final Map<String, dynamic>? agenda;

  @override
  State<_AgendaFormDialog> createState() => _AgendaFormDialogState();
}

class _AgendaFormDialogState extends State<_AgendaFormDialog> {
  final TextEditingController _desc = TextEditingController();
  late DateTime _dateTime;
  int _serviceId = 0;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.agenda != null;

  @override
  void initState() {
    super.initState();
    final a = widget.agenda ?? const {};
    _desc.text = (a['description'] ?? '').toString();
    final parsed = hsParseDate(a['eventDate']);
    final now = DateTime.now();
    _dateTime = parsed ?? DateTime(now.year, now.month, now.day, now.hour + 1);
    final sid = (a['serviceId'] as num?)?.toInt() ?? 0;
    _serviceId = sid;
  }

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  int _serviceValue(Map<String, dynamic> s) =>
      ((s['serviceId'] ?? s['id']) as num?)?.toInt() ?? 0;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _dateTime = DateTime(picked.year, picked.month, picked.day,
          _dateTime.hour, _dateTime.minute);
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateTime),
    );
    if (picked == null) return;
    setState(() {
      _dateTime = DateTime(_dateTime.year, _dateTime.month, _dateTime.day,
          picked.hour, picked.minute);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = <String, dynamic>{
      'purchasedPackageId': widget.purchasedPackageId,
      'serviceId': _serviceId == 0 ? null : _serviceId,
      'eventDate': hsDateTimeValue(_dateTime),
      'description': _desc.text.trim(),
    };
    try {
      if (_editing) {
        await HsApi.updateAgenda({
          'id': (widget.agenda!['id'] as num).toInt(),
          ...body,
        });
      } else {
        await HsApi.createAgenda(body);
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
          _error = 'No se pudo guardar la agenda';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final validIds = {for (final s in widget.services) _serviceValue(s)};
    final dropdownValue = validIds.contains(_serviceId) ? _serviceId : 0;

    return FormDialog(
      icon: Icons.event_available_outlined,
      title: _editing ? 'Editar agenda' : 'Nueva agenda',
      subtitle: 'Fecha y hora, servicio y descripción del evento.',
      saving: _saving,
      error: _error,
      saveLabel: _editing ? 'Guardar cambios' : 'Crear agenda',
      maxWidth: 480,
      onCancel: () => Navigator.of(context).pop(false),
      onSave: _save,
      children: [
        FormSection(
          label: 'Fecha y hora',
          child: Row(
            children: [
              Expanded(
                child: _PickerField(
                  icon: Icons.calendar_today_outlined,
                  label: 'Fecha',
                  value: hsShortDate(_dateTime),
                  onTap: _pickDate,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PickerField(
                  icon: Icons.schedule_outlined,
                  label: 'Hora',
                  value: hsTimeLabel(_dateTime),
                  onTap: _pickTime,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FormSection(
          label: 'Servicio',
          child: DropdownButtonFormField<int>(
            initialValue: dropdownValue,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Servicio del paquete',
              prefixIcon: Icon(Icons.design_services_outlined, size: 20),
            ),
            items: [
              const DropdownMenuItem<int>(
                value: 0,
                child: Text('Sin servicio específico'),
              ),
              for (final s in widget.services)
                DropdownMenuItem<int>(
                  value: _serviceValue(s),
                  child: Text(
                    (s['name'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _serviceId = v ?? 0),
          ),
        ),
        const SizedBox(height: 16),
        FormSection(
          label: 'Descripción',
          child: TextField(
            controller: _desc,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Descripción del evento',
              hintText: 'Ej. Sesión de fotos en el jardín, ceremonia a las 6 pm…',
              alignLabelWithHint: true,
            ),
          ),
        ),
      ],
    );
  }
}

/// Campo de selección (fecha u hora) con aspecto de input.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
        ),
        child: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

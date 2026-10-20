import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../drive_base.dart';
import '../drive_scope.dart';
import '../hs_access.dart';
import '../hs_api.dart';
import '../hs_format.dart';
import '../hs_place.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/common.dart';
import '../widgets/hs_pickers.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/form_dialog.dart';
import '../widgets/hs_modal.dart';
import '../widgets/hs_pager.dart';
import '../widgets/hs_place_picker.dart';
import '../widgets/hs_search_filter.dart';
import '../widgets/hs_toast.dart';
import '../widgets/service_items_gallery.dart';

/// Estilo COMPACTO de las acciones de un servicio (dentro del administrador
/// de paquetes): en el celular los tres botones tienen que caber en UNA fila
/// horizontal, así que el aire se reduce al mínimo (solo su padding interno).
final ButtonStyle _kServiceAction = TextButton.styleFrom(
  visualDensity: VisualDensity.compact,
  padding: const EdgeInsets.symmetric(horizontal: 8),
  minimumSize: const Size(0, 32),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
);

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

  /// Filas de la PÁGINA actual (las manda el backend).
  List<Map<String, dynamic>> _clients = const [];
  String _query = '';

  /// Filtro por paquetes: '' todos · 'con' con paquetes · 'sin' sin paquetes.
  String _pkgFilter = '';

  // Paginación del directorio (30 de fábrica; 50/100/200 en el pie).
  int _page = 1;
  int _pageSize = kHsDefaultPageSize;

  /// Total de clientes con la búsqueda/filtro puestos (lo calcula el servidor).
  int _total = 0;

  /// Conteos de los chips (respetan la búsqueda): todos / con / sin paquetes.
  Map<String, int> _pkgCounts = const {};

  /// Paquetes asignados a TODOS los clientes (stat del módulo).
  int _assignedPackages = 0;

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

  /// Pide la página actual al backend (con búsqueda y filtro de paquetes).
  Future<void> _reload({bool reset = false}) async {
    if (reset) _page = 1;
    // Página pedida (antes de que el servidor la recorte).
    final asked = _page;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await HsApi.clientsPage(
        page: _page,
        limit: _pageSize,
        q: _query,
        packages: _pkgFilter,
      );
      if (!mounted) return;
      setState(() {
        _clients = result.items;
        _serverPaged = result.serverPaged;
        _total = result.total;
        _pkgCounts = {
          for (final e
              in ((result.meta['pkgCounts'] as Map?) ?? const {}).entries)
            e.key.toString(): (e.value as num?)?.toInt() ?? 0,
        };
        _assignedPackages =
            (result.meta['assignedPackages'] as num?)?.toInt() ??
            _clients.fold<int>(
              0,
              (a, c) => a + ((c['packagesCount'] as num?)?.toInt() ?? 0),
            );
        if (result.serverPaged) _page = result.page;
        _loading = false;
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
        _error = 'No se pudo cargar la lista de clientes';
        _loading = false;
      });
    }
  }

  Future<void> _openForm([Map<String, dynamic>? client]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ClientFormDialog(client: client),
    );
    // Al CREAR se vuelve a la página 1 (la fila nueva queda a la vista).
    if (saved == true) _reload(reset: client == null);
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
    } catch (_) {
      // El backend ya avisó con la notificación roja.
    }
    _reload();
  }

  Future<void> _openPackages(Map<String, dynamic> client) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ClientPackagesDialog(client: client),
    );
    _reload(); // el conteo pudo cambiar
  }

  /// Filas que se pintan: la página del servidor o el filtro local (backend
  /// viejo sin `total`).
  List<Map<String, dynamic>> get _visible {
    if (_serverPaged) return _clients;
    final q = _query.trim().toLowerCase();
    return _clients.where((u) {
      final pkgs = (u['packagesCount'] as num?)?.toInt() ?? 0;
      if (_pkgFilter == 'con' && pkgs == 0) return false;
      if (_pkgFilter == 'sin' && pkgs > 0) return false;
      if (q.isEmpty) return true;
      final hay =
          '${u['name'] ?? ''} ${u['lastname'] ?? ''} ${u['email'] ?? ''} ${u['number'] ?? ''}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  /// Total del chip "Todos" (respeta la búsqueda, no el filtro elegido).
  int get _countAll =>
      _serverPaged ? (_pkgCounts['all'] ?? 0) : _clients.length;

  int get _countWith => _serverPaged
      ? (_pkgCounts['with'] ?? 0)
      : _clients
            .where((u) => ((u['packagesCount'] as num?)?.toInt() ?? 0) > 0)
            .length;

  int get _countWithout => _serverPaged
      ? (_pkgCounts['without'] ?? 0)
      : _clients
            .where((u) => ((u['packagesCount'] as num?)?.toInt() ?? 0) == 0)
            .length;

  /// Opciones del módulo de filtros: paquetes contratados.
  List<HsFilterGroup> get _filterGroups => [
    HsFilterGroup(
      id: 'packages',
      title: 'Paquetes contratados',
      help: 'Filtra el directorio por clientes con o sin paquetes activos.',
      options: [
        HsFilterOption(
          value: '',
          label: 'Todos los clientes',
          count: _countAll,
          icon: Icons.groups_rounded,
        ),
        HsFilterOption(
          value: 'con',
          label: 'Con paquetes',
          count: _countWith,
          icon: Icons.inventory_2_outlined,
          color: const Color(0xFF2F6BFF),
        ),
        HsFilterOption(
          value: 'sin',
          label: 'Sin paquetes',
          count: _countWithout,
          icon: Icons.inventory_2_outlined,
          color: const Color(0xFFD97706),
        ),
      ],
    ),
  ];

  /// Clientes de la página actual.
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
      module: 'clients',
      title: 'Clientes',
      description: 'Directorio de clientes (rol fijo "Client") y administración de sus paquetes.',
      icon: Icons.badge_rounded,
      onRefresh: _reload,
      stats: [
        StatPill(icon: Icons.people_outline, label: '$_countAll clientes'),
        StatPill(
          icon: Icons.inventory_2_outlined,
          label: '$_assignedPackages paquetes asignados',
        ),
      ],
      actions: [
        // "Crear" (create): sin el permiso, el botón no aparece.
        if (HsAccess.instance.degraded ||
            HsAccess.instance.can('Clientes', 'create'))
          HsActionButton(
            onPressed: () => _openForm(),
            icon: Icons.badge_outlined,
            label: 'Nuevo cliente',
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
          HsSearchFilterBar(
            hint: 'Buscar por nombre, correo o teléfono…',
            onChanged: _search,
            initial: _query,
            groups: _filterGroups,
            selected: {'packages': _pkgFilter},
            onApply: (filters) {
              final next = filters['packages'] ?? '';
              if (next == _pkgFilter) return;
              setState(() {
                _pkgFilter = next;
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
              icon: Icons.badge_outlined,
              title: 'Sin clientes',
              message: 'No hay clientes que coincidan. Crea el primero con el botón "Nuevo cliente".',
            )
          else ...[
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
                          child: _ClientTile(
                            client: rows[i],
                            onEdit:
                                HsAccess.instance.degraded ||
                                    HsAccess.instance.can('Clientes', 'update')
                                ? () => _openForm(rows[i])
                                : null,
                            onPackages:
                                HsAccess.instance.degraded ||
                                    HsAccess.instance.can('Clientes', 'update')
                                ? () => _openPackages(rows[i])
                                : null,
                            onDelete:
                                HsAccess.instance.degraded ||
                                    HsAccess.instance.can('Clientes', 'delete')
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

/// Tarjeta de un cliente del directorio.
///
/// TODA la tarjeta es interactiva: un clic (o un toque) en cualquier parte
/// abre el ADMINISTRADOR DE PAQUETES del cliente (abonos, agendas,
/// movimientos). El botón "Paquetes" sigue ahí para quien lo busca, pero ya
/// no es el único camino.
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
    final name = '${client['name'] ?? ''} ${client['lastname'] ?? ''}'
        .trim()
        .trim();
    final email = (client['email'] ?? '').toString().trim();
    final number = (client['number'] ?? '').toString().trim();
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    final pkgCount = (client['packagesCount'] as num?)?.toInt() ?? 0;
    final subtitle = [
      if (email.isNotEmpty) email,
      if (number.isNotEmpty) number,
    ].join('  ·  ');

    // En pantallas angostas los botones no caben junto al texto: se guardan
    // en el menú "⋮" de la propia tarjeta.
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < 560;
        final row = Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              // Avatar con inicial: aro tenue + tinte turquesa del directorio.
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF2F6BFF).withValues(alpha: .10),
                  border: Border.all(
                    color: const Color(0xFF2F6BFF).withValues(alpha: .28),
                  ),
                ),
                child: CircleAvatar(
                  radius: 19,
                  backgroundColor: const Color(0xFF2F6BFF)
                      .withValues(alpha: .16),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Color(0xFF2F6BFF),
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty
                          ? (email.isEmpty ? 'Sin nombre' : email)
                          : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    // Sus paquetes, a la vista: es lo que se administra al
                    // tocar la tarjeta.
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _ClientChip(
                          icon: Icons.card_giftcard_outlined,
                          label: pkgCount == 1
                              ? '1 paquete'
                              : '$pkgCount paquetes',
                          tint: const Color(0xFF2F6BFF),
                        ),
                        // Ya no hay pastilla "Abrir": la tarjeta entera abre el
                        // administrador (y el menú "⋮" tiene la acción).
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (compact)
                // Menú "⋮" (el mismo patrón en todos los módulos en el celular).
                // Sin ninguna opción disponible (permisos) no se dibuja.
                HsRowMenu(
                  actions: [
                    HsMenuAction(
                      icon: Icons.card_giftcard_outlined,
                      label: 'Paquetes',
                      onTap: onPackages,
                    ),
                    HsMenuAction(
                      icon: Icons.edit_outlined,
                      label: 'Editar',
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
                // Los botones de siempre para abrir los paquetes del cliente.
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
                    icon: Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: scheme.error.withValues(alpha: .8),
                    ),
                  ),
                if (onPackages != null)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
              ],
            ],
          ),
        );

        // Sin permiso de administrar paquetes la tarjeta NO es clickeable (solo
        // se ven las acciones permitidas).
        if (onPackages == null) return row;
        return Tooltip(
          message: 'Abrir el administrador de paquetes',
          waitDuration: const Duration(milliseconds: 700),
          child: InkWell(onTap: onPackages, child: row),
        );
      },
    );
  }
}

/// Píldora diminuta de la tarjeta de cliente (paquetes / abrir).
class _ClientChip extends StatelessWidget {
  const _ClientChip({
    required this.icon,
    required this.label,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tint.withValues(alpha: .22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tint),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: tint,
              ),
            ),
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
      // La contraseña SOLO viaja si se escribió una: al editar, dejar el campo
      // vacío significa "no la toques". Antes el payload de edición ni
      // siquiera la incluía, así que cambiarla no hacía nada.
      if (_password.text.isNotEmpty) 'password': _password.text,
    };
    try {
      if (_editing) {
        await HsApi.updateClient({
          'id': (widget.client!['id'] as num).toInt(),
          ...body,
        });
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
    const accent = Color(0xFF2F6BFF);

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
        helperText: _editing ? 'Déjala vacía para conservar la actual.' : null,
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
        // Preview con acento turquesa (identidad del módulo Clientes)
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
                          ? 'Nuevo cliente'
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
              // Siempre visible: al editar también se puede cambiar la
              // contraseña (y el ojo para verla funciona en ambos modos).
              passwordField,
            ],
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
                  'Total',
                  hsMoney(price, currency),
                  scheme.onSurface,
                ),
              ),
              Expanded(
                child: _MiniStat(
                  'Pagado',
                  hsMoney(paid, currency),
                  const Color(0xFF2F6BFF),
                ),
              ),
              Expanded(
                child: _MiniStat(
                  'Saldo',
                  hsMoney(saldo < 0 ? 0 : saldo, currency),
                  const Color(0xFFF59E0B),
                ),
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
  HsPlace? _place;
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
    _place = HsPlace.of(a);
  }

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  int _serviceValue(Map<String, dynamic> s) =>
      ((s['serviceId'] ?? s['id']) as num?)?.toInt() ?? 0;

  Future<void> _pickDate() async {
    final picked = await showHsDatePicker(context, initialDate: _dateTime);
    if (picked == null) return;
    setState(() {
      _dateTime = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _dateTime.hour,
        _dateTime.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showHsTimePicker(context, initialTime: _dateTime);
    if (picked == null) return;
    setState(() {
      _dateTime = DateTime(
        _dateTime.year,
        _dateTime.month,
        _dateTime.day,
        picked.hour,
        picked.minute,
      );
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
      // El lugar viaja SIEMPRE (vacío = se quitó): así editar una agenda
      // puede borrar la ubicación, no solo cambiarla.
      ...(_place?.toBody() ?? const {'location': '', 'lat': null, 'lng': null}),
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
          // El ancho se mide por la PANTALLA: el diálogo calcula sus
          // dimensiones intrínsecas y un `LayoutBuilder` dentro de un
          // AlertDialog las hace fallar ("does not support returning
          // intrinsic dimensions").
          child: (() {
            final stack = MediaQuery.sizeOf(context).width < 380;
            final date = _PickerField(
              icon: Icons.calendar_today_outlined,
              label: 'Fecha',
              value: hsShortDate(_dateTime),
              onTap: _pickDate,
              tint: AppColors.brand,
            );
            final time = _PickerField(
              icon: Icons.schedule_outlined,
              label: 'Hora',
              value: hsTimeLabel(_dateTime),
              onTap: _pickTime,
              tint: _kTeal,
            );
            if (stack) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [date, const SizedBox(height: 10), time],
              );
            }
            return Row(
              children: [
                Expanded(child: date),
                const SizedBox(width: 10),
                Expanded(child: time),
              ],
            );
          })(),
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
          label: 'Lugar (opcional)',
          child: HsPlaceField(
            place: _place,
            enabled: !_saving,
            onChanged: (place) => setState(() => _place = place),
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
              hintText:
                  'Ej. Sesión de fotos en el jardín, ceremonia a las 6 pm…',
              alignLabelWithHint: true,
            ),
          ),
        ),
      ],
    );
  }
}

/// Campo de selección (fecha u hora): tarjeta táctil con icono tintado,
/// rótulo y valor. Se ve como una pieza de la app, no como un input prestado.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.tint,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = tint ?? AppColors.brand;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 10, 10, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .28)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      letterSpacing: .8,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.edit_calendar_outlined,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

// ==================================================================
// Modal "Paquete del cliente": administración COMPLETA y visual
//
//   * El paquete VIGENTE (el que no está terminado) se administra:
//     abonar, registrar inversión / gasto / ahorro / abono externo,
//     agendas, terminar cada servicio (con su descripción de cierre) y
//     el paquete (con validación de servicios y dinero completos).
//   * Los demás paquetes del cliente se consultan como detalle
//     (solo lectura) desde el mismo selector.
//   * La vista se estructura en TRES pestañas:
//       Servicios  · cada servicio con su estado y su cierre
//       Calendario · el mes, con agendas y servicios terminados
//       Movimientos· historial (abonos, inversiones, gastos, ahorros,
//                   abonos externos) + disponible del paquete
// ==================================================================

/// Colores de los movimientos y estados (se usan en todo el modal).
const Color _kGreen = Color(0xFF2F6BFF);
const Color _kAmber = Color(0xFFF59E0B);
const Color _kBlue = Color(0xFF3B82F6);
const Color _kRed = Color(0xFFEF4444);
const Color _kTeal = Color(0xFF2F6BFF);

/// Etiqueta / icono / color de cada tipo de movimiento.
String _moveLabel(String kind) => switch (kind) {
  'abono' => 'Abono',
  'abono_externo' => 'Abono externo',
  'inversion' => 'Inversión',
  'ahorro' => 'Ahorro',
  'pago' => 'Pago',
  _ => 'Gasto',
};

IconData _moveIcon(String kind) => switch (kind) {
  'abono' => Icons.payments_outlined,
  'abono_externo' => Icons.account_balance_wallet_outlined,
  'inversion' => Icons.trending_up,
  'ahorro' => Icons.savings_rounded,
  'pago' => Icons.handshake_outlined,
  _ => Icons.trending_down,
};

Color _moveColor(String kind) => switch (kind) {
  'abono' => _kGreen,
  'abono_externo' => _kBlue,
  'inversion' => _kTeal,
  'ahorro' => _kTeal,
  'pago' => _kAmber,
  _ => _kRed,
};

/// Tipos que ofrece el diálogo "Movimiento del paquete".
const List<String> _kMovementKinds = [
  'inversion',
  'gasto',
  'ahorro',
  'abono_externo',
  'pago',
];

/// Descripción corta de cada tipo (tarjetas de selección del diálogo).
String _moveHint(String kind) => switch (kind) {
  'inversion' => 'Dinero que se mete al paquete',
  'gasto' => 'Dinero que se gasta del paquete',
  'ahorro' => 'Dinero que se aparta del disponible',
  'abono_externo' => 'Pago recibido fuera del paquete',
  _ => 'Pago a un colaborador o empleado',
};

/// Administrador del paquete del cliente.
/// PÚBLICO para poder probarlo desde test/ (lo abre el módulo Clientes).
class ClientPackagesDialog extends StatefulWidget {
  const ClientPackagesDialog({super.key, required this.client});

  final Map<String, dynamic> client;

  @override
  State<ClientPackagesDialog> createState() => ClientPackagesDialogState();
}

class ClientPackagesDialogState extends State<ClientPackagesDialog> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _purchased = const [];
  List<Map<String, dynamic>> _catalog = const [];
  List<Map<String, dynamic>> _agendas = const [];

  /// Paquete en foco (por defecto, el vigente del cliente).
  int? _selectedId;

  /// Detalle del paquete en foco: servicios, movimientos, totales y si se
  /// puede finalizar (con el motivo cuando no).
  Map<String, dynamic>? _progress;
  String? _progressError;
  bool _loadingProgress = false;

  bool _busy = false;

  /// Envío de «Avisar al cliente» en curso. Con dos toques seguidos solo sale
  /// UN aviso: el segundo se ignora mientras el primero viaja al servidor.
  bool _notifying = false;

  /// Último servicio avisado y cuándo: pulsar dos veces el mismo botón en
  /// pocos segundos tampoco manda el aviso otra vez.
  int _lastNotifiedServiceId = 0;
  DateTime? _lastNotifiedAt;
  static const Duration _notifyCooldown = Duration(seconds: 5);

  /// Pestaña activa del detalle. `null` = aún sin elegir: en ventana
  /// angosta se abre con la ficha (presentación) y en escritorio con
  /// Servicios. En escritorio no existe la pestaña 4 (la ficha vive en la
  /// columna izquierda), así que se usa 0.
  int? _tab;

  int get _activeTab {
    final narrow = MediaQuery.sizeOf(context).width < 1020;
    final t = _tab ?? (narrow ? 4 : 0);
    return !narrow && t == 4 ? 0 : t;
  }

  /// Etapa del modal: 0 = tarjetas de los paquetes del cliente ("targets"),
  /// 1 = detalle de administración. Al tocar una tarjeta se entra con
  /// animación; la flecha del encabezado regresa al selector.
  int _stage = 0;

  /// Pestaña Movimientos: las tarjetas de dinero se pueden MINIMIZAR para
  /// dejarle la pantalla al historial.
  bool _moneyOpen = true;

  late final int _userId = (widget.client['id'] as num).toInt();
  late final String _name =
      '${widget.client['name'] ?? ''} ${widget.client['lastname'] ?? ''}'
          .trim();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  // ==================== Datos ====================

  /// Carga los paquetes del cliente (catálogo + agendas) y el detalle del
  /// paquete en foco. [silent] refresca sin tapar la vista con el spinner.
  Future<void> _reload({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await HsApi.clientPackages(_userId);
      // Agendas "best effort": sin ellas el modal sigue funcionando.
      var agendas = const <Map<String, dynamic>>[];
      try {
        agendas = await HsApi.agendas(userId: _userId);
      } catch (_) {}
      if (!mounted) return;
      final purchased = ((data['purchasedPackages'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      setState(() {
        _purchased = purchased;
        _catalog = ((data['catalog'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _agendas = agendas;
        _loading = false;
        _error = null;
        // Conserva el paquete elegido; si ya no existe, vuelve al vigente.
        final stillThere = purchased.any(
          (p) => (p['id'] as num).toInt() == _selectedId,
        );
        if (!stillThere) _selectedId = _vigenteId;
      });
      await _loadProgress();
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

  Future<void> _loadProgress() async {
    final id = _selectedId;
    if (id == null) {
      setState(() {
        _progress = null;
        _progressError = null;
        _loadingProgress = false;
      });
      return;
    }
    setState(() {
      _loadingProgress = true;
      _progressError = null;
    });
    try {
      final data = await HsApi.packageProgress(id);
      if (!mounted || _selectedId != id) return;
      setState(() {
        _progress = data;
        _loadingProgress = false;
      });
    } on ApiException catch (e) {
      if (!mounted || _selectedId != id) return;
      setState(() {
        _progress = null;
        _progressError = e.message;
        _loadingProgress = false;
      });
    } catch (_) {
      if (!mounted || _selectedId != id) return;
      setState(() {
        _progress = null;
        _progressError = 'No se pudo cargar el detalle del paquete';
        _loadingProgress = false;
      });
    }
  }

  /// Id del paquete VIGENTE: el más reciente que no está terminado.
  int? get _vigenteId {
    for (final p in _purchased) {
      if (!_isFinished(p)) return (p['id'] as num).toInt();
    }
    return null;
  }

  static bool _isFinished(Map<String, dynamic> p) =>
      (p['status'] ?? '').toString().trim().toLowerCase() == 'terminado';

  Map<String, dynamic>? get _selected {
    for (final p in _purchased) {
      if ((p['id'] as num).toInt() == _selectedId) return p;
    }
    return null;
  }

  /// ¿El paquete en foco se puede administrar? (el vigente sí; un paquete
  /// terminado o anterior se consulta como detalle).
  bool get _canAdminister {
    final p = _selected;
    if (p == null) return false;
    return !_isFinished(p) && (p['id'] as num).toInt() == _vigenteId;
  }

  /// Servicios del paquete en foco: los del detalle (con `done`/`finishedAt`)
  /// o, si el backend todavía no tiene el endpoint, los del listado.
  List<Map<String, dynamic>> get _services {
    final fromProgress = (_progress?['services'] as List?) ?? const [];
    if (fromProgress.isNotEmpty) {
      return fromProgress
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    }
    return ((_selected?['services'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .map(
          (s) => <String, dynamic>{
            ...s,
            'done': (s['status'] ?? '')
                .toString()
                .trim()
                .toLowerCase()
                .startsWith('entregado'),
            'finishedAt': null,
          },
        )
        .toList();
  }

  List<Map<String, dynamic>> get _movements =>
      (((_progress?['movements'] as List?) ?? const []))
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();

  /// A quién se le puede asignar un pago: colaboradores y empleados activos
  /// (lo determina el backend).
  List<Map<String, dynamic>> get _recipients =>
      (((_progress?['recipients'] as List?) ?? const []))
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();

  Map<String, dynamic> get _totals =>
      ((_progress?['totals'] as Map?) ?? const {}).cast<String, dynamic>();

  /// Dinero LIBRE del paquete: abonado menos gastado (gasto + inversión).
  /// Es la base con la que se calcula el ahorro en porcentaje.
  num get _disponible {
    final fromBackend = _totals['disponible'];
    if (fromBackend is num) return fromBackend;
    final abonado = (_totals['abonado'] as num?) ?? 0;
    final gastado = (_totals['gastado'] as num?) ?? 0;
    final saldo = abonado - gastado;
    return saldo < 0 ? 0 : saldo;
  }

  List<String> get _blockers =>
      (((_progress?['blockers'] as List?) ?? const []))
          .map((e) => e.toString())
          .toList();

  bool get _finishedSelected => _selected != null && _isFinished(_selected!);

  /// Agendas del paquete en foco.
  List<Map<String, dynamic>> get _agendasOfSelected => _agendas
      .where((a) => (a['purchasedPackageId'] as num?)?.toInt() == _selectedId)
      .toList();

  // ==================== Acciones ====================

  void _snack(String msg) => HsToast.info(msg);

  /// Ejecuta una operación con bloqueo y refresco del modal. El aviso verde
  /// (o rojo) lo pone la capa de API con el mensaje del backend.
  Future<bool> _run(Future<void> Function() op) async {
    if (_busy) return false;
    setState(() => _busy = true);
    var okDone = false;
    try {
      await op();
      okDone = true;
    } catch (_) {
      // El backend ya avisó con la notificación correspondiente.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (okDone) await _reload(silent: true);
    return okDone;
  }

  Future<void> _select(int id) async {
    if (_selectedId == id) return;
    setState(() {
      _selectedId = id;
      _progress = null;
      _progressError = null;
    });
    await _loadProgress();
  }

  /// Elige un paquete desde sus tarjetas y pasa a la vista de detalle.
  Future<void> _openPackage(int id) async {
    await _select(id);
    if (mounted) setState(() => _stage = 1);
  }

  /// Vuelve a las tarjetas de los paquetes del cliente.
  void _backToPicker() {
    if (_busy) return;
    setState(() => _stage = 0);
  }

  Future<void> _addFromCatalog() async {
    if (_catalog.isEmpty) {
      _snack('No hay paquetes en el catálogo');
      return;
    }
    final picked = await showHsModal<Map<String, dynamic>>(
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
                      hsMoney(
                        (p['price'] as num?) ?? 0,
                        (p['currency'] ?? 'MXN').toString(),
                      ),
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
    final id = (picked['id'] as num).toInt();
    await _run(() => HsApi.addPackageFromCatalog(_userId, id));
    // El paquete recién asignado pasa a ser el vigente: se abre solo, directo
    // al detalle (como si se hubiera tocado su tarjeta).
    final vigente = _vigenteId;
    if (vigente != null && mounted) {
      setState(() {
        _selectedId = vigente;
        _stage = 1;
      });
      await _loadProgress();
    }
  }

  Future<void> _removeFromClient(Map<String, dynamic> pkg) async {
    final ok = await confirmDelete(
      context,
      title: '¿Quitar el paquete?',
      message:
          '"${pkg['name'] ?? ''}" dejará de aparecer en el panel del cliente.',
      confirmLabel: 'Quitar',
    );
    if (ok != true) return;
    final link = (pkg['usersPackageId'] as num?)?.toInt();
    if (link == null) return;
    await _run(() => HsApi.removeClientPackage(_userId, link));
  }

  Future<void> _abonar(Map<String, dynamic> pkg) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _AbonarDialog(package: pkg),
    );
    if (saved == true) await _reload(silent: true);
  }

  /// Termina un servicio del paquete pidiendo su descripción de cierre.
  Future<void> _completeService(Map<String, dynamic> svc) async {
    final note = await _askNote(
      icon: Icons.task_alt,
      title: 'Terminar servicio',
      subtitle: (svc['name'] ?? '').toString(),
      intro:
          'Se marcará como entregado y quedará registrada la fecha de '
          'cierre con esta descripción.',
      initial: (svc['description'] ?? '').toString(),
      label: 'Cómo quedó el servicio / observaciones',
      confirmLabel: 'Dar por terminado',
    );
    if (note == null) return;
    await _run(
      () => HsApi.completePackageService(
        (svc['id'] as num).toInt(),
        description: note,
      ),
    );
  }

  Future<void> _reopenService(Map<String, dynamic> svc) async {
    if (!await _confirm(
      '¿Reabrir el servicio?',
      '"${svc['name'] ?? ''}" volverá a "En proceso" y se borrará su fecha '
          'de cierre.',
    )) {
      return;
    }
    await _run(() => HsApi.reopenPackageService((svc['id'] as num).toInt()));
  }

  /// Cambia la descripción/avance de un servicio sin terminarlo.
  Future<void> _editServiceNote(Map<String, dynamic> svc) async {
    final note = await _askNote(
      icon: Icons.edit_note,
      title: 'Avance del servicio',
      subtitle: (svc['name'] ?? '').toString(),
      intro: 'Describe el avance actual; el estado del servicio no cambia.',
      initial: (svc['description'] ?? '').toString(),
      label: 'Descripción / avance',
      confirmLabel: 'Guardar',
      allowEmpty: true,
    );
    if (note == null) return;
    await _run(
      () => HsApi.updatePackageService(
        (svc['id'] as num).toInt(),
        description: note,
      ),
    );
  }

  /// Copia al portapapeles la liga base del Drive de un servicio.
  Future<void> _copyServiceUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    _snack('Enlace copiado');
  }

  /// Edita la liga base del Drive de un servicio (opcional). Se guarda sobre
  /// el servicio del catálogo y aplica a todos los paquetes que lo usan.
  Future<void> _editServiceUrl(Map<String, dynamic> svc) async {
    final serviceId = (svc['serviceId'] as num?)?.toInt() ?? 0;
    if (serviceId == 0) {
      _snack('No se pudo identificar el servicio');
      return;
    }
    final url = await _askNote(
      icon: Icons.link,
      title: 'Carpeta del Drive',
      subtitle: (svc['name'] ?? '').toString(),
      intro:
          'Pega la liga base de la carpeta del Drive de este servicio. '
          'Déjala vacía para quitarla.',
      initial: (svc['url'] ?? '').toString(),
      label: 'URL base del Drive',
      confirmLabel: 'Guardar enlace',
      allowEmpty: true,
    );
    if (url == null) return;
    await _run(() => HsApi.updateServiceUrl(serviceId, url.trim()));
  }

  /// Comparte con el cliente una CARPETA del Drive y/o una LIGA para UN
  /// servicio DEL PAQUETE (las dos opcionales; el cliente las ve en "Mi
  /// paquete" junto a su selección de fotos).
  ///
  /// La carpeta se elige DENTRO del Drive del cliente: el selector se abre en
  /// la carpeta que YA se le comparte y no deja subir más arriba (lo de fuera
  /// no lo vería).
  Future<void> _editServiceShare(Map<String, dynamic> svc) async {
    final serviceId = (svc['id'] as num?)?.toInt() ?? 0;
    if (serviceId == 0) {
      _snack('No se pudo identificar el servicio');
      return;
    }
    // Qué permite el servicio del catálogo (el backend lo manda en el nivel
    // superior y dentro de `service`; se acepta cualquiera de los dos).
    final catalog = (svc['service'] is Map)
        ? (svc['service'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final photosMax =
        (svc['photosMax'] as num?)?.toInt() ??
        (catalog['photosMax'] as num?)?.toInt() ??
        0;
    final allowFolder =
        svc['allowFolder'] != false && catalog['allowFolder'] != false;

    final out = await showDialog<_ServiceShare>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ServiceShareDialog(
        serviceName: (svc['name'] ?? 'Servicio').toString(),
        folder: (svc['shareFolder'] ?? '').toString(),
        link: (svc['shareLink'] ?? '').toString(),
        pickPhotos: svc['pickPhotos'] == true,
        showFolder: svc['showFolder'] != false,
        photosMax: photosMax,
        allowFolder: allowFolder,
        // Sin permiso para ver el Drive no se puede abrir su selector.
        onPickFolder: HsAccess.instance.canUseDrive
            ? () => _pickDriveFolder(insideShared: true)
            : null,
      ),
    );
    if (out == null) return;
    await _run(
      () => HsApi.updateServiceShare(
        serviceId,
        folder: out.folder,
        link: out.link,
        pickPhotos: out.pickPhotos,
        showFolder: out.showFolder,
      ),
    );
  }

  /// Abre las fotos que el cliente ya eligió para ESTE servicio.
  Future<void> _viewServicePhotos(Map<String, dynamic> svc) async {
    final paths = ((svc['itemPaths'] as List?) ?? const [])
        .map((e) => e.toString())
        .where((p) => p.trim().isNotEmpty)
        .toList();
    final total = (svc['items'] as num?)?.toInt() ?? 0;
    if (paths.isEmpty && total > 0) {
      _snack('Actualiza el panel para ver las fotos elegidas');
      return;
    }
    await showServiceItemsGallery(
      context,
      serviceName: (svc['name'] ?? 'Servicio').toString(),
      folder: (svc['shareFolder'] ?? '').toString(),
      paths: paths,
    );
  }

  /// Avisa al cliente de que YA puede elegir sus fotos.
  Future<void> _notifyPhotos(Map<String, dynamic> svc) async {
    final pkg = _selected;
    final pkgId = (pkg?['id'] as num?)?.toInt() ?? 0;
    if (pkgId == 0) return;
    final name = (svc['name'] ?? 'Servicio').toString();
    final ok = await showHsModal<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Avisar al cliente'),
        content: Text(
          'Le enviaremos un aviso a «${pkg?['name'] ?? 'su paquete'}» de que '
          'la selección de fotos de "$name" ya está disponible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.notifications_active_outlined, size: 18),
            label: const Text('Enviar aviso'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final serviceId = (svc['id'] as num?)?.toInt() ?? 0;
    // UN solo envío: si el primero sigue en curso, o se acaba de mandar el
    // mismo aviso hace segundos, no se repite.
    if (_notifying) return;
    final last = _lastNotifiedAt;
    if (serviceId != 0 &&
        serviceId == _lastNotifiedServiceId &&
        last != null &&
        DateTime.now().difference(last) < _notifyCooldown) {
      return;
    }
    _notifying = true;
    try {
      // El mensaje de éxito/aviso lo pone la capa de API con el texto del
      // backend ("Aviso enviado al cliente" o "El paquete no tiene clientes
      // activos"): antes se mostraba ADEMÁS un `_snack` y salían dos avisos.
      await HsApi.notifyClient(
        purchasedPackageId: pkgId,
        serviceId: serviceId,
        kind: 'fotos-disponibles',
        title: 'Ya puedes elegir tus fotos',
        body:
            'La selección de fotos de «$name» ya está disponible en Mi paquete.',
      );
      _lastNotifiedServiceId = serviceId;
      _lastNotifiedAt = DateTime.now();
    } catch (_) {
      // La capa de API ya avisó.
    } finally {
      _notifying = false;
    }
  }

  /// Registra un movimiento (inversión, gasto, ahorro, abono externo o pago).
  /// El ahorro acepta monto o porcentaje del DISPONIBLE (abonado - gastado).
  Future<void> _addMovement() async {
    final pkg = _selected;
    if (pkg == null) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _MovementDialog(
        package: pkg,
        disponible: _disponible,
        currency: (pkg['currency'] ?? 'MXN').toString(),
        recipients: _recipients,
      ),
    );
    if (saved == true) await _reload(silent: true);
  }

  /// Edita un movimiento o un abono ya registrado. Solo el paquete VIGENTE
  /// (no finalizado) permite editar: el backend también lo valida.
  Future<void> _editMovement(Map<String, dynamic> m) async {
    final pkg = _selected;
    if (pkg == null) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _MovementDialog(
        package: pkg,
        disponible: _disponible,
        currency: (pkg['currency'] ?? 'MXN').toString(),
        movement: m,
        recipients: _recipients,
      ),
    );
    if (saved == true) await _reload(silent: true);
  }

  /// Reparte un pago del paquete entre colaboradores y empleados, en partes
  /// iguales o por numeración. Cada parte se guarda como un `pago` con su
  /// destinatario y cuenta como gasto.
  Future<void> _splitPayment() async {
    final pkg = _selected;
    if (pkg == null) return;
    final recipients = _recipients;
    if (recipients.isEmpty) {
      _snack('No hay colaboradores ni empleados activos para repartir');
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _SplitPaymentDialog(
        package: pkg,
        recipients: recipients,
        currency: (pkg['currency'] ?? 'MXN').toString(),
      ),
    );
    if (saved == true) await _reload(silent: true);
  }

  Future<void> _removeMovement(Map<String, dynamic> m) async {
    final id = (m['id'] as num).toInt();
    final source = (m['source'] ?? 'movement').toString();
    final isPayment = source == 'payment';
    if (!await _confirm(
      '¿Quitar el registro?',
      '${_moveLabel((m['kind'] ?? '').toString())} de '
          '${hsMoney((m['amount'] as num?) ?? 0)}. '
          '${isPayment ? 'Se descontará del total abonado del paquete.' : ''}',
    )) {
      return;
    }
    await _run(
      () => isPayment
          ? HsApi.deletePackagePayment(id)
          : HsApi.deletePackageMovement(id),
    );
  }

  /// Finaliza el paquete (el backend vuelve a validar servicios y dinero).
  Future<void> _finishPackage() async {
    final pkg = _selected;
    if (pkg == null) return;
    if (_blockers.isNotEmpty) {
      _snack(_blockers.first);
      return;
    }
    if (!await _confirm(
      '¿Finalizar el paquete?',
      'Todos los servicios están terminados y el pago está completo. El '
          'paquete pasará a "Terminado" y quedará como historial del cliente.',
      confirmLabel: 'Finalizar',
    )) {
      return;
    }
    await _run(() => HsApi.finishClientPackage((pkg['id'] as num).toInt()));
  }

  Future<void> _reopenPackage() async {
    final pkg = _selected;
    if (pkg == null) return;
    if (!await _confirm(
      '¿Reabrir el paquete?',
      'Volverá a poder administrarse (servicios, abonos y movimientos).',
    )) {
      return;
    }
    await _run(() => HsApi.reopenClientPackage((pkg['id'] as num).toInt()));
  }

  Future<bool> _confirm(
    String title,
    String message, {
    String confirmLabel = 'Continuar',
  }) async {
    final ok = await confirmDelete(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
    );
    return ok == true;
  }

  /// Diálogo de una descripción (cierre de servicio o avance).
  /// El controlador del texto lo posee el propio diálogo: crearlo aquí y
  /// liberarlo al volver rompía la animación de salida ("controller used
  /// after being disposed").
  Future<String?> _askNote({
    required IconData icon,
    required String title,
    required String subtitle,
    required String intro,
    required String label,
    required String confirmLabel,
    String initial = '',
    bool allowEmpty = false,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _NoteDialog(
        icon: icon,
        title: title,
        subtitle: subtitle,
        intro: intro,
        label: label,
        confirmLabel: confirmLabel,
        initial: initial,
        allowEmpty: allowEmpty,
      ),
    );
  }

  // ==================== Vista ====================
  //
  // Diseño en DOS COLUMNAS (ventanas anchas): a la izquierda la FICHA del
  // paquete — el flyer oscuro con acento dorado, igual que el catálogo de la
  // web, con su dinero, su avance y sus acciones — y a la derecha la
  // ADMINISTRACIÓN en pestañas. En ventanas angostas se apila como antes.

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width > 900;
    // En MÓVIL el administrador de paquetes ocupa TODA la pantalla: entre
    // pestañas, tarjetas y acciones necesita el espacio completo.
    final phone = hsIsPhone(context);
    // ATRÁS (botón del sistema o gesto) NO cierra el modal: si se está
    // administrando un paquete, regresa al selector de paquetes del cliente.
    return PopScope(
      canPop: _stage == 0 || _purchased.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _busy) return;
        _backToPicker();
      },
      child: Dialog(
        insetPadding: phone
            ? EdgeInsets.zero
            : EdgeInsets.symmetric(
                horizontal: wide ? 24 : 10,
                vertical: wide ? 20 : 12,
              ),
        clipBehavior: Clip.antiAlias,
        shape: phone
            ? const RoundedRectangleBorder()
            : RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: phone ? double.infinity : 1180),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Alto FIJO: el alto disponible se toma del layout real (dentro
              // de un diálogo no siempre coincide con el de la pantalla).
              final available = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : size.height * .94;
              final height = phone
                  ? available
                  : (available * .98).clamp(460.0, 920.0);
              return SizedBox(
                width: phone ? double.infinity : 1180,
                height: height,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(scheme),
                    Divider(height: 1, color: scheme.outlineVariant),
                    Expanded(child: _body(scheme)),
                    Divider(height: 1, color: scheme.outlineVariant),
                    _footer(scheme),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    final vigente = _vigenteId != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          if (_stage == 1)
            IconButton(
              tooltip: 'Todos los paquetes',
              visualDensity: VisualDensity.compact,
              onPressed: _busy ? null : _backToPicker,
              icon: Icon(
                Icons.arrow_back,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.brand, AppColors.brandDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.card_giftcard_outlined,
              color: Colors.white,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Administrador de paquetes',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                Text(
                  '${_name.isEmpty ? 'Cliente' : _name}'
                  ' · ${_purchased.length} ${_purchased.length == 1 ? 'paquete' : 'paquetes'}'
                  '${vigente ? '' : ' · sin paquete vigente'}',
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
          if (_loadingProgress)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            tooltip: 'Cerrar',
            visualDensity: VisualDensity.compact,
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, size: 20, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _footer(ColorScheme scheme) {
    final narrow = MediaQuery.sizeOf(context).width < 560;
    final actions = Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: _busy || _loading ? null : _addFromCatalog,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Asignar del catálogo'),
        ),
        if (_selected != null && _canAdminister)
          TextButton.icon(
            onPressed: _busy ? null : () => _removeFromClient(_selected!),
            icon: Icon(
              Icons.remove_circle_outline,
              size: 18,
              color: scheme.error,
            ),
            label: Text(
              'Quitar del cliente',
              style: TextStyle(color: scheme.error),
            ),
          ),
      ],
    );
    final done = FilledButton(
      onPressed: _busy ? null : () => Navigator.of(context).pop(),
      child: const Text('Listo'),
    );
    final spinner = _busy
        ? const Padding(
            padding: EdgeInsets.only(right: 12),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : const SizedBox.shrink();

    // MÓVIL: TODO en UN renglón y con botones de IMAGEN (icono + tooltip),
    // que ocupan mucho menos que las etiquetas completas.
    if (narrow) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: Row(
          children: [
            Tooltip(
              message: 'Asignar un paquete del catálogo',
              child: IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                onPressed: _busy || _loading ? null : _addFromCatalog,
                icon: const Icon(Icons.library_add_outlined, size: 20),
              ),
            ),
            if (_selected != null && _canAdminister) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Quitar el paquete del cliente',
                child: IconButton.outlined(
                  visualDensity: VisualDensity.compact,
                  onPressed: _busy ? null : () => _removeFromClient(_selected!),
                  icon: Icon(
                    Icons.remove_circle_outline,
                    size: 20,
                    color: scheme.error,
                  ),
                ),
              ),
            ],
            const Spacer(),
            if (_busy) spinner,
            FilledButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Listo'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 14, 12),
      child: Row(
        children: [
          // Los botones de la izquierda pueden partirse en dos renglones en
          // ventanas angostas (antes desbordaban el modal).
          Expanded(child: actions),
          const SizedBox(width: 8),
          if (_busy) spinner,
          done,
        ],
      ),
    );
  }

  Widget _body(ColorScheme scheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 38, color: scheme.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => _reload(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    // Etapa inicial: los paquetes del cliente como TARJETAS ("targets").
    // Al elegir uno —o tras asignar uno nuevo— se pasa al detalle con una
    // animación de escala + fundido.
    final Widget content;
    final bool picker = _stage == 0 || _purchased.isEmpty;
    if (picker) {
      content = _pickerStage(scheme);
    } else {
      final twoColumns = MediaQuery.sizeOf(context).width >= 1020;
      if (!twoColumns) {
        // MÓVIL: la presentación del paquete YA NO ocupa media pantalla: se
        // convierte en la pestaña "Paquete", junto con Servicios, Calendario,
        // Movimientos y Drive. Para cambiar de paquete se vuelve con la
        // flecha del encabezado (el selector de paquetes se quitó).
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _tabBar(scheme, withFicha: true),
            Expanded(child: _tabContent(scheme)),
          ],
        );
      } else {
        content = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 372,
              child: SingleChildScrollView(
                primary: false,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: _sidePanel(scheme),
              ),
            ),
            VerticalDivider(width: 1, color: scheme.outlineVariant),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _tabBar(scheme),
                  Expanded(child: _tabContent(scheme)),
                ],
              ),
            ),
          ],
        );
      }
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: .96, end: 1).animate(anim),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(picker ? 'picker' : 'detail'),
        child: content,
      ),
    );
  }

  // ---------- Etapa inicial: tarjetas de los paquetes ----------

  /// Los paquetes del cliente como "targets" modernos, con el lenguaje
  /// visual de la app (degradados sutiles, círculos geométricos y el acent
  /// dorado de los flyers). Al tocar uno entra al detalle con animación.
  Widget _pickerStage(ColorScheme scheme) {
    if (_purchased.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 42,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              const Text('Este cliente aún no tiene paquetes'),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _busy ? null : _addFromCatalog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Asignar del catálogo'),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
          child: _sectionLabel(
            scheme,
            'Paquetes · ${_purchased.length} en total',
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final cols = box.maxWidth > 940
                  ? 3
                  : box.maxWidth > 620
                  ? 2
                  : 1;
              const gap = 12.0;
              final cardW = (box.maxWidth - 32 - (cols - 1) * gap) / cols;
              return ListView(
                primary: false,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                children: [
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (var i = 0; i < _purchased.length; i++)
                        SizedBox(
                          width: cardW,
                          child: StaggeredItem(
                            index: i,
                            child: _PackageTargetCard(
                              pkg: _purchased[i],
                              isVigente:
                                  (_purchased[i]['id'] as num).toInt() ==
                                  _vigenteId,
                              finished: _isFinished(_purchased[i]),
                              onTap: _busy
                                  ? null
                                  : () => _openPackage(
                                      (_purchased[i]['id'] as num).toInt(),
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------- Columna izquierda: ficha del paquete ----------

  Widget _sidePanel(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // La etiqueta "Paquetes del cliente" y las pestañas para cambiar de
        // paquete se quitaron: se vuelve al selector con la flecha del
        // encabezado (ahí se ven TODOS los paquetes del cliente).
        _ficha(scheme),
      ],
    );
  }

  /// La presentación del paquete en foco: portada, dinero, avance y cierre.
  /// En escritorio vive en la columna izquierda; en móvil es la pestaña
  /// "Paquete" (junto con Servicios/Calendario/Movimientos/Drive) para que
  /// no ocupe media pantalla.
  Widget _ficha(ColorScheme scheme) {
    final pkg = _selected;
    if (pkg == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        _cover(scheme, pkg),
        const SizedBox(height: 10),
        _money(scheme, pkg),
        const SizedBox(height: 10),
        _progressBars(scheme),
        if (_blockers.isNotEmpty && _canAdminister) ...[
          const SizedBox(height: 10),
          _blockersBox(scheme),
        ],
        if (_progressError != null) ...[
          const SizedBox(height: 8),
          Text(
            'Detalle ampliado no disponible: $_progressError',
            style: TextStyle(fontSize: 11, color: scheme.error),
          ),
        ],
        const SizedBox(height: 14),
        // Abonar, Movimiento y Agendas viven en las pestañas de la
        // derecha: en la ficha solo queda el botón de cierre.
        if (_canAdminister) _finishButton() else _readOnlyBox(scheme),
      ],
    );
  }

  /// El ÚNICO botón de la ficha: finalizar (deshabilitado con bloqueos).
  Widget _finishButton() {
    final canFinish = _progress?['canFinish'] == true;
    return Tooltip(
      message: canFinish
          ? 'Cierra el paquete y lo deja en el historial del cliente'
          : 'Primero terminan todos los servicios y se completa el pago',
      child: FilledButton.icon(
        onPressed: _busy || !canFinish ? null : _finishPackage,
        icon: const Icon(Icons.flag_outlined, size: 17),
        label: const Text('Finalizar paquete'),
        style: FilledButton.styleFrom(
          backgroundColor: _kGreen,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(40),
        ),
      ),
    );
  }

  /// Aviso de solo lectura (paquete terminado o anterior) con la opción de
  /// reabrir: los botones de gestión ya no viven en la ficha.
  Widget _readOnlyBox(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: .35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .5),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.lock_outline,
                size: 15,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _finishedSelected
                      ? 'Paquete terminado: sus servicios y el pago quedaron '
                            'concluidos. Reábrelo solo para corregir algo.'
                      : 'Paquete anterior: se consulta como detalle.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.25,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_finishedSelected && _selectedId == _vigenteId) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _reopenPackage,
            icon: const Icon(Icons.lock_open_outlined, size: 17),
            label: const Text('Reabrir paquete'),
          ),
        ],
      ],
    );
  }

  Widget _sectionLabel(ColorScheme scheme, String text) {
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w800,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Divider(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: .7),
          ),
        ),
      ],
    );
  }

  /// El paquete como pieza representativa: el MISMO flyer oscuro con acento
  /// dorado del catálogo de la web (tier, categoría, nombre y precio).
  Widget _cover(ColorScheme scheme, Map<String, dynamic> pkg) {
    final data = ((_progress?['package'] as Map?) ?? const {})
        .cast<String, dynamic>();
    final name = (pkg['name'] ?? 'Paquete').toString();
    final subtitle = (pkg['subtitle'] ?? '').toString();
    final categoryName = (pkg['categoryName'] ?? '').toString();
    final tier = (pkg['tierName'] ?? '').toString();
    // Cada tier pinta la ficha con su propio look (Premium oro, Gold ámbar,
    // Basic acero) para distinguirlo de un vistazo.
    final look = HsTierLook.of(tier);
    final price = (data['price'] as num?) ?? (pkg['price'] as num?) ?? 0;
    final currency = (pkg['currency'] ?? 'MXN').toString();
    final status = (data['status'] ?? pkg['status'] ?? 'Pendiente').toString();
    final emoji = hsCategoryIcon(categoryName.isEmpty ? name : categoryName);
    final finished = _finishedSelected;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: look.gradient,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: look.accent.withValues(alpha: look.premium ? .55 : .26),
          width: look.premium ? 1.4 : 1,
        ),
      ),
      child: Stack(
        children: [
          // Marca de agua: la categoría representada en grande.
          Positioned(
            right: -10,
            bottom: -18,
            child: Opacity(
              opacity: .13,
              child: Text(emoji, style: const TextStyle(fontSize: 104)),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Línea superior degradada dorada (como en la web).
              Container(
                height: 2.2,
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (tier.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              gradient: look.premium
                                  ? LinearGradient(
                                      colors: [look.accent, look.accentSoft],
                                    )
                                  : null,
                              color: look.premium
                                  ? null
                                  : look.accent.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(6),
                              border: look.premium
                                  ? null
                                  : Border.all(
                                      color: look.accent.withValues(alpha: .35),
                                    ),
                            ),
                            child: Text(
                              tier.toUpperCase(),
                              style: TextStyle(
                                fontSize: 9.5,
                                letterSpacing: 1.6,
                                fontWeight: FontWeight.w800,
                                color: look.premium
                                    ? look.dark
                                    : look.accentSoft,
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        // Los distintivos van a la derecha y bajan de renglón
                        // si la ficha queda angosta (ventana chica o columna).
                        Expanded(
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (finished)
                                const _MiniPill(
                                  icon: Icons.lock_outline,
                                  label: 'Solo lectura',
                                  color: _kGreen,
                                ),
                              _MiniPill(
                                icon: finished
                                    ? Icons.verified_outlined
                                    : Icons.timelapse,
                                label: status,
                                color: finished ? _kGreen : HsGold.goldLight,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(emoji, style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            (categoryName.isEmpty ? 'General' : categoryName)
                                .toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.8,
                              fontWeight: FontWeight.w800,
                              color: look.accentSoft,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.25,
                            color: Colors.white.withValues(alpha: .62),
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    // Precio y distintivo: si la ficha es angosta, el
                    // distintivo baja de renglón en vez de desbordar.
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              hsMoney(price, currency),
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                color: look.accent,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: 3,
                                left: 6,
                              ),
                              child: Text(
                                'total',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: .55),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_selectedId == _vigenteId)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _kGreen.withValues(alpha: .18),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'EN ADMINISTRACIÓN',
                              style: TextStyle(
                                fontSize: 9,
                                letterSpacing: .8,
                                fontWeight: FontWeight.w800,
                                color: _kGreen,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Dinero del paquete. El TOTAL va grande en el flyer, así que aquí van
  /// los tres datos que se siguen de cerca: abonado, saldo y % pagado.
  Widget _money(ColorScheme scheme, Map<String, dynamic> pkg) {
    final data = ((_progress?['package'] as Map?) ?? const {})
        .cast<String, dynamic>();
    final currency = (pkg['currency'] ?? 'MXN').toString();
    final price = (data['price'] as num?) ?? (pkg['price'] as num?) ?? 0;
    final paid = (data['paid'] as num?) ?? (pkg['paid'] as num?) ?? 0;
    final saldo = price - paid;
    final pct = price > 0 ? (paid / price).clamp(0.0, 1.0) : 0.0;
    return Row(
      children: [
        Expanded(
          child: _MoneyTile('Abonado', hsMoney(paid, currency), _kGreen),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MoneyTile(
            'Saldo',
            hsMoney(saldo < 0 ? 0 : saldo, currency),
            _kAmber,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MoneyTile(
            'Pagado',
            '${(pct * 100).toStringAsFixed(0)} %',
            _kBlue,
          ),
        ),
      ],
    );
  }

  /// Barras de avance: pago del paquete y servicios terminados.
  Widget _progressBars(ColorScheme scheme) {
    final data = ((_progress?['package'] as Map?) ?? const {})
        .cast<String, dynamic>();
    final price = (data['price'] as num?) ?? (_selected?['price'] as num?) ?? 0;
    final paid = (data['paid'] as num?) ?? (_selected?['paid'] as num?) ?? 0;
    final pct = price > 0 ? (paid / price).clamp(0.0, 1.0) : 0.0;
    final services = _services;
    final doneCount = services.where((s) => s['done'] == true).length;
    final servicePct = services.isEmpty ? 0.0 : doneCount / services.length;
    return Column(
      children: [
        _ProgressRow(
          label: 'Pago',
          value: pct,
          color: _kGreen,
          trailing: '${(pct * 100).toStringAsFixed(0)} %',
          labelWidth: 72,
        ),
        const SizedBox(height: 6),
        _ProgressRow(
          label: 'Terminados',
          value: servicePct,
          color: HsGold.gold,
          trailing: '$doneCount/${services.length}',
          labelWidth: 72,
        ),
      ],
    );
  }

  Widget _blockersBox(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kAmber.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kAmber.withValues(alpha: .30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_outlined, size: 14, color: _kAmber),
              const SizedBox(width: 6),
              Text(
                'Para finalizar el paquete',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final b in _blockers)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 2),
              child: Text(
                '• $b',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.25,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------- Columna derecha: pestañas de administración ----------

  /// Pestañas en HORIZONTAL (una sola fila con el ancho repartido): nada de
  /// apilarlas en vertical, que solo ocupa espacio.
  ///
  /// Con [withFicha] se agrega la pestaña "Paquete" (la presentación del
  /// paquete) usada en ventana angosta; si la fila no cabe en el ancho
  /// disponible, se vuelve desplazable horizontalmente en vez de comprimir
  /// las etiquetas hasta hacerlas ilegibles.
  Widget _tabBar(ColorScheme scheme, {bool withFicha = false}) {
    final tabs = <({IconData icon, String label, int value})>[
      if (withFicha)
        (icon: Icons.card_giftcard_outlined, label: 'Paquete', value: 4),
      (icon: Icons.checklist_rtl, label: 'Servicios', value: 0),
      (icon: Icons.calendar_month_outlined, label: 'Calendario', value: 1),
      (icon: Icons.receipt_long_outlined, label: 'Movimientos', value: 2),
      (icon: Icons.folder_shared_outlined, label: 'Drive', value: 3),
    ];
    final active = _activeTab;
    final note = _finishedSelected
        ? 'Paquete terminado · consulta'
        : (!_canAdminister ? 'Paquete anterior · consulta' : null);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              Widget button(int i, {required bool flex}) {
                final w = _TabButton(
                  icon: tabs[i].icon,
                  label: tabs[i].label,
                  selected: active == tabs[i].value,
                  onTap: () => setState(() => _tab = tabs[i].value),
                );
                return flex ? Expanded(child: w) : w;
              }

              const gap = 8.0;
              // Ancho MÍNIMO razonable por pestaña (icono + texto + aire).
              double needed() {
                var total = 0.0;
                for (final t in tabs) {
                  total += 46 + t.label.length * 7.4;
                }
                return total + gap * (tabs.length - 1);
              }

              if (box.maxWidth >= needed()) {
                return Row(
                  children: [
                    for (var i = 0; i < tabs.length; i++) ...[
                      if (i > 0) const SizedBox(width: gap),
                      button(i, flex: true),
                    ],
                  ],
                );
              }
              // No cabe: scroll horizontal con cada pestaña a su ancho natural.
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < tabs.length; i++) ...[
                      if (i > 0) const SizedBox(width: gap),
                      button(i, flex: false),
                    ],
                  ],
                ),
              );
            },
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tabContent(ColorScheme scheme) {
    switch (_activeTab) {
      case 4:
        // Pestaña "Paquete" (solo en ventana angosta): la presentación.
        return SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
          child: _ficha(scheme),
        );
      case 0:
        return _servicesTab(scheme);
      case 1:
        return _calendarTab(scheme);
      case 3:
        return _driveTab(scheme);
      default:
        return _movementsTab(scheme);
    }
  }

  // ---------- Pestaña: carpetas compartidas del Drive ----------

  /// Carpetas del Drive COMPARTIDAS con el cliente de ESTE paquete (puede
  /// haber VARIAS). El cliente verá estas carpetas (y las de sus otros
  /// paquetes) en su drive; es la forma de "compartir" una parte del Drive.
  List<String> get _drivePaths {
    final pkg = _progress?['package'];
    if (pkg is! Map) return const [];
    final out = _pathsOf(pkg.cast<String, dynamic>());
    if (out.isEmpty) {
      // Backend viejo (una sola carpeta).
      final one = drivePathNormalize((pkg['drivePath'] ?? '').toString());
      if (one.isNotEmpty) out.add(one);
    }
    return out;
  }

  /// Carpetas compartidas de un paquete tal como las manda la API
  /// (`drivePaths`, con `drivePath` como respaldo de un backend viejo).
  static List<String> _pathsOf(Map<String, dynamic> pkg) {
    final out = <String>[];
    final raw = pkg['drivePaths'];
    if (raw is List) {
      for (final x in raw) {
        final path = drivePathNormalize(x.toString());
        if (path.isNotEmpty && !out.contains(path)) out.add(path);
      }
    }
    return out;
  }

  /// Rutas del Drive compartidas en los DEMÁS paquetes del cliente y en las
  /// OTRAS carpetas del paquete que se está editando (todo menos la carpeta
  /// que se va a compartir ahora).
  List<String> _otherSharedPaths() {
    final id = _selectedId;
    final out = <String>[];
    for (final p in _purchased) {
      if ((p['id'] as num?)?.toInt() == id) continue;
      out.addAll(_pathsOf(p));
      if (_pathsOf(p).isEmpty) {
        final one = drivePathNormalize((p['drivePath'] ?? '').toString());
        if (one.isNotEmpty) out.add(one);
      }
    }
    for (final path in _drivePaths) {
      if (!out.contains(path)) out.add(path);
    }
    return out;
  }

  /// La carpeta YA compartida con la que choca [path], o null si no choca
  /// (cuenta tanto lo compartido en los otros paquetes del cliente como las
  /// otras carpetas de este mismo paquete).
  ///
  /// Compartir una carpeta que está dentro de otra ya compartida (o que la
  /// contiene) no aporta nada: el cliente vería el mismo contenido dos veces.
  String? _sharedConflict(String path) {
    if (path.isEmpty) return null;
    for (final other in _otherSharedPaths()) {
      if (drivePathsOverlap(path, other)) return other;
    }
    return null;
  }

  /// Todas las carpetas ya compartidas con el cliente: las compartidas
  /// DIRECTAMENTE con él (las ve en todos sus paquetes: son su drive), las del
  /// paquete en foco y las de sus otros paquetes. Es lo que el cliente ve, y
  /// por eso es el punto de partida al compartir una carpeta de un servicio
  /// ([insideShared]): la primera es la carpeta raíz del selector.
  List<String> _allSharedPaths() {
    final out = <String>[];
    for (final p in _clientDrivePaths) {
      if (!out.contains(p)) out.add(p);
    }
    for (final p in _drivePaths) {
      if (!out.contains(p)) out.add(p);
    }
    for (final p in _otherSharedPaths()) {
      if (!out.contains(p)) out.add(p);
    }
    return out;
  }

  /// Selector de carpeta del Drive: abre [_DriveFolderPicker] y devuelve los
  /// segmentos de la carpeta elegida (null si se cancela la elección).
  ///
  /// [insideShared] = true: se elige DENTRO de lo que el cliente ya tiene
  /// compartido —ese es SU drive—, así que el selector se abre EN la carpeta
  /// compartida, muestra sus subcarpetas y no deja subir más arriba: nada
  /// antes de esa carpeta. Es lo que usa compartir la carpeta de UN SERVICIO.
  Future<List<String>?> _pickDriveFolder({bool insideShared = false}) async {
    final drive = DriveScope.maybeOf(context);
    if (drive == null) {
      _snack('El Drive no está disponible en esta pantalla');
      return null;
    }
    // El "drive" del cliente: las carpetas que YA se le comparten.
    final roots = <String>[
      if (insideShared)
        for (final p in _allSharedPaths())
          if (drivePathNormalize(p).isNotEmpty) drivePathNormalize(p),
    ];
    if (insideShared && roots.isEmpty) {
      _snack(
        'Comparte primero una carpeta con el cliente: el servicio '
        'comparte DENTRO de su Drive',
      );
      return null;
    }
    return showHsModal<List<String>>(
      context: context,
      builder: (_) => _DriveFolderPicker(
        base: insideShared ? roots.first : '',
        initial: insideShared ? const <String>[] : drive.path,
        roots: roots,
        load: drive.listChildFolders,
        // Dentro del drive del cliente NO hay solapamiento que valga: TODO lo
        // que se ofrece está dentro de lo que ya ve (compartir una subcarpeta
        // para un servicio no duplica nada en su Drive). Fuera, se avisa de
        // las carpetas que se solapan con lo ya compartido.
        conflict: insideShared
            ? (_) => null
            : (path) => _sharedConflict(drivePathNormalize(path)),
      ),
    );
  }

  // Compartir una carpeta se hace SIEMPRE al CLIENTE (_shareClientDriveFolder):
  // el Drive no depende del paquete. Solo queda el "dejar de compartir" de las
  // carpetas que pertenecen a la versión anterior (compartidas al paquete).

  Future<void> _unshareDriveFolder(String path) async {
    final id = _selectedId;
    if (id == null) return;
    await _run(
      () => HsApi.removePackageDrivePath(purchasedPackageId: id, path: path),
    );
  }

  Widget _driveTab(ColorScheme scheme) {
    if (_loadingProgress) {
      return const Center(child: CircularProgressIndicator());
    }
    // El Drive compartido NO depende del paquete: depende del CLIENTE. Lo
    // que se comparte aquí lo ve en TODOS sus paquetes (y en su Drive solo ve
    // eso). Las carpetas que quedaron compartidas "al paquete" en la versión
    // anterior siguen funcionando: se listan aparte, para poder quitarlas.
    final paths = _clientDrivePaths;
    final legacy = _drivePaths;
    final editable = _canAdminister && !_busy;
    return ListView(
      primary: false,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.primary.withValues(alpha: .22)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.folder_shared_outlined,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Aquí se le comparten carpetas del Drive AL CLIENTE: las ve '
                  'en todos sus paquetes (y su Drive solo muestra lo que se le '
                  'comparte). Puede ser más de una.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // UNA tarjeta por carpeta compartida, cada una con su botón para
        // dejar de compartirla (las demás siguen igual).
        for (final path in paths) ...[
          _clientFolderCard(scheme, path, editable),
          const SizedBox(height: 8),
        ],
        if (paths.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: .35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: .5),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_off_outlined, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sin carpetas compartidas',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'El cliente todavía no ve nada en su Drive.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        // Elegir una carpeta del Drive necesita permiso para ver el Drive: sin
        // él la opción no se dibuja (el cliente sigue viendo lo ya compartido).
        if (editable && HsAccess.instance.canUseDrive)
          FilledButton.icon(
            onPressed: _shareClientDriveFolder,
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: Text(
              paths.isEmpty
                  ? 'Compartir una carpeta del Drive'
                  : 'Compartir otra carpeta',
            ),
          )
        else if (editable)
          Text(
            'Para compartir carpetas del Drive necesitas permiso para verlo.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          )
        else
          Text(
            paths.isEmpty
                ? 'No se le comparte ninguna carpeta al cliente.'
                : 'Solo lectura: este paquete ya no se administra.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        // Carpetas de la versión anterior (compartidas AL PAQUETE): si el
        // cliente tiene más paquetes, aquí NO se ven. Se dejan a la vista solo
        // si existen, para poder quitarlas.
        if (legacy.isNotEmpty) ...[
          const SizedBox(height: 22),
          _sectionLabel(scheme, 'Solo en este paquete'),
          const SizedBox(height: 8),
          Text(
            'Estas carpetas se compartieron al paquete (versión anterior) y '
            'solo se ven aquí. Para que el cliente las vea en TODOS sus '
            'paquetes, quítalas y vuelve a compartirlas arriba.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          for (final path in legacy) ...[
            _sharedFolderCard(scheme, path, editable),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  /// Carpetas compartidas DIRECTAMENTE con el cliente de este paquete.
  List<String> get _clientDrivePaths {
    final pkg = _progress?['package'];
    if (pkg is! Map) return const [];
    final data = pkg.cast<String, dynamic>();
    final out = <String>[];
    final raw = data['clientDrivePaths'];
    if (raw is List) {
      for (final x in raw) {
        final path = drivePathNormalize(x.toString());
        if (path.isNotEmpty && !out.contains(path)) out.add(path);
      }
    }
    return out;
  }

  Future<void> _shareClientDriveFolder() async {
    final id = _selectedId;
    if (id == null) return;
    final segments = await _pickDriveFolder(insideShared: false);
    if (segments == null || segments.isEmpty) return;
    final path = segments.join('/');
    if (_clientDrivePaths.contains(path)) {
      _snack('Esa carpeta ya se comparte con el cliente');
      return;
    }
    await _run(
      () => HsApi.addClientDrivePath(purchasedPackageId: id, path: path),
    );
  }

  Future<void> _unshareClientDriveFolder(String path) async {
    final id = _selectedId;
    if (id == null) return;
    await _run(
      () => HsApi.removeClientDrivePath(purchasedPackageId: id, path: path),
    );
  }

  /// Tarjeta de UNA carpeta compartida con el CLIENTE (todos sus paquetes).
  ///
  /// Se ve en TODOS sus paquetes, así que lo que se quita es el VÍNCULO con el
  /// cliente (desvincular): el azul del panel, sin el violeta de antes y con el
  /// botón nombrado en vez de una "x".
  Widget _clientFolderCard(ColorScheme scheme, String path, bool editable) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.brand.withValues(alpha: .24)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              Icons.folder_shared_outlined,
              color: AppColors.brand,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  path,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Compartida con el cliente (todos sus paquetes).',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (editable)
            Tooltip(
              message: 'Desvincular la carpeta del cliente',
              child: TextButton.icon(
                onPressed: () => _unshareClientDriveFolder(path),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.error,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                icon: const Icon(Icons.link_off, size: 16),
                label: const Text('Desvincular'),
              ),
            ),
        ],
      ),
    );
  }

  /// Tarjeta de UNA carpeta compartida con el cliente de este paquete.
  Widget _sharedFolderCard(ColorScheme scheme, String path, bool editable) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_rounded, color: AppColors.brand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  path,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Carpeta compartida con el cliente de este paquete.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (editable)
            IconButton(
              tooltip: 'Dejar de compartir esta carpeta',
              onPressed: () => _unshareDriveFolder(path),
              icon: const Icon(Icons.link_off, size: 18),
            ),
        ],
      ),
    );
  }

  // ---------- Pestaña: servicios ----------

  Widget _servicesTab(ColorScheme scheme) {
    final services = _services;
    if (services.isEmpty) {
      return _emptyTab(
        scheme,
        Icons.checklist_rtl,
        'Este paquete no tiene servicios registrados',
      );
    }
    return ListView.builder(
      primary: false,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      itemCount: services.length,
      itemBuilder: (context, i) => _ServiceTile(
        service: services[i],
        canAdminister: _canAdminister,
        busy: _busy,
        onComplete: _completeService,
        onReopen: _reopenService,
        onNote: _editServiceNote,
        onUrl: _editServiceUrl,
        onShare: _editServiceShare,
        onCopy: _copyServiceUrl,
        onPhotos: _viewServicePhotos,
        onNotify: _notifyPhotos,
      ),
    );
  }

  // ---------- Pestaña: calendario ----------

  /// Eventos agendados del paquete como TARJETAS (el mismo diseño del botón
  /// "Agenda"), con los próximos primero. Se pueden crear, editar y eliminar.
  Widget _calendarTab(ColorScheme scheme) {
    final agendas = _agendasOfSelected.toList()
      ..sort(
        (a, b) =>
            '${a['eventDate'] ?? ''}'.compareTo('${b['eventDate'] ?? ''}'),
      );
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Row(
            children: [
              const Icon(
                Icons.event_available_outlined,
                size: 16,
                color: _kBlue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Eventos agendados',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              if (_canAdminister)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _newAgenda,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Nueva agenda'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: agendas.isEmpty
              ? _emptyTab(
                  scheme,
                  Icons.event_busy_outlined,
                  'Este paquete aún no tiene eventos agendados',
                )
              : ListView.builder(
                  primary: false,
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  itemCount: agendas.length,
                  itemBuilder: (context, i) {
                    final a = agendas[i];
                    final d = hsParseDate(a['eventDate']);
                    final past = d != null && d.isBefore(now);
                    return _AgendaEventCard(
                      agenda: a,
                      past: past,
                      onEdit: _canAdminister ? () => _editAgenda(a) : null,
                      onDelete: _canAdminister ? () => _deleteAgenda(a) : null,
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Crea una agenda del paquete en foco.
  Future<void> _newAgenda() async {
    final id = _selectedId;
    if (id == null) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) =>
          _AgendaFormDialog(purchasedPackageId: id, services: _services),
    );
    if (saved == true) await _reload(silent: true);
  }

  /// Edita una agenda existente.
  Future<void> _editAgenda(Map<String, dynamic> agenda) async {
    final id = _selectedId;
    if (id == null) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _AgendaFormDialog(
        purchasedPackageId: id,
        services: _services,
        agenda: agenda,
      ),
    );
    if (saved == true) await _reload(silent: true);
  }

  /// Elimina una agenda (con confirmación).
  Future<void> _deleteAgenda(Map<String, dynamic> agenda) async {
    final date = hsParseDate(agenda['eventDate']);
    final ok = await confirmDelete(
      context,
      title: '¿Eliminar la agenda?',
      message: date == null
          ? 'Esta agenda se eliminará del paquete.'
          : hsDateLabel(date),
      confirmLabel: 'Eliminar',
    );
    if (ok != true) return;
    await _run(() => HsApi.deleteAgenda((agenda['id'] as num).toInt()));
  }

  // ---------- Pestaña: movimientos ----------

  Widget _movementsTab(ColorScheme scheme) {
    final currency = (_selected?['currency'] ?? 'MXN').toString();
    final movements = _movements;
    final totals = _totals;
    final phone = MediaQuery.sizeOf(context).width < 560;
    final tiles = <Widget>[
      _MoneyTile('Disponible', hsMoney(_disponible, currency), _kGreen),
      _MoneyTile(
        'Ahorro',
        hsMoney((totals['ahorrado'] as num?) ?? 0, currency),
        _kTeal,
      ),
      _MoneyTile(
        'Abono externo',
        hsMoney((totals['abonoExterno'] as num?) ?? 0, currency),
        _kBlue,
      ),
      _MoneyTile(
        'Invertido',
        hsMoney((totals['invertido'] as num?) ?? 0, currency),
        _kTeal,
      ),
      _MoneyTile(
        'Gastado',
        hsMoney((totals['gastado'] as num?) ?? 0, currency),
        _kRed,
      ),
      _MoneyTile(
        'Pagado',
        hsMoney((totals['pagos'] as num?) ?? 0, currency),
        _kAmber,
      ),
    ];

    // TODO (tarjetas de dinero + botones + movimientos) vive en UN solo
    // scroll: se puede bajar por las tarjetas de información y el bloque de
    // dinero se puede MINIMIZAR para dejarle la pantalla a los movimientos.
    return ListView(
      primary: false,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      children: [
        if (_progress != null) ...[
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 15,
                color: scheme.primary,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Dinero del paquete',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (!_moneyOpen)
                Text(
                  'Disponible ${hsMoney(_disponible, currency)}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: _kGreen,
                  ),
                ),
              Tooltip(
                message: _moneyOpen
                    ? 'Minimizar las tarjetas'
                    : 'Mostrar las tarjetas',
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _moneyOpen = !_moneyOpen),
                  icon: AnimatedRotation(
                    turns: _moneyOpen ? 0 : .5,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_up_rounded,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !_moneyOpen
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 10),
                    // En el celular los cuadros van en 2 columnas legibles y
                    // bajan con el scroll; en escritorio, todos en una fila.
                    child: phone
                        ? LayoutBuilder(
                            builder: (context, box) {
                              const gap = 6.0;
                              final w = (box.maxWidth - gap) / 2;
                              return Wrap(
                                spacing: gap,
                                runSpacing: gap,
                                children: [
                                  for (final t in tiles)
                                    SizedBox(width: w, child: t),
                                ],
                              );
                            },
                          )
                        : _MoneyRow(tiles: tiles),
                  ),
          ),
        ],
        if (_canAdminister)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            // Los TRES botones van juntos, en un solo renglón (se desliza si
            // no caben) en vez de apilados uno por línea.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : () => _abonar(_selected!),
                    icon: const Icon(Icons.payments_outlined, size: 16),
                    label: const Text('Abonar'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _addMovement,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Registrar movimiento'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _splitPayment,
                    icon: const Icon(Icons.handshake_outlined, size: 16),
                    label: const Text('Repartir pago'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kAmber,
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (movements.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 26),
            child: _emptyTab(
              scheme,
              Icons.receipt_long_outlined,
              'Sin movimientos registrados. Los abonos aparecen aquí.',
            ),
          )
        else
          for (final m in movements) _movementRow(scheme, m, currency),
      ],
    );
  }

  Widget _movementRow(
    ColorScheme scheme,
    Map<String, dynamic> m,
    String currency,
  ) {
    final kind = (m['kind'] ?? 'gasto').toString();
    final color = _moveColor(kind);
    final when = hsParseDate(m['created']);
    final concept = (m['description'] ?? '').toString().trim();
    // Destinatario del pago (colaborador o empleado), cuando lo hay.
    final who = (m['userName'] ?? '').toString().trim();
    final subtitle = [
      if (who.isNotEmpty) '→ $who',
      if (concept.isNotEmpty) concept,
      if (when != null) '${hsShortDate(when)} ${hsTimeLabel(when)}',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_moveIcon(kind), size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _MiniPill(
                      icon: _moveIcon(kind),
                      label: _moveLabel(kind),
                      color: color,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      hsMoney((m['amount'] as num?) ?? 0, currency),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: color,
                      ),
                    ),
                  ],
                ),
                if (subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_canAdminister) ...[
            // Editar: solo mientras el paquete no esté finalizado.
            IconButton(
              tooltip: 'Editar registro',
              visualDensity: VisualDensity.compact,
              onPressed: _busy ? null : () => _editMovement(m),
              icon: Icon(
                Icons.edit_outlined,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ),
            IconButton(
              tooltip: 'Quitar registro',
              visualDensity: VisualDensity.compact,
              onPressed: _busy ? null : () => _removeMovement(m),
              icon: Icon(
                Icons.close,
                size: 16,
                color: scheme.error.withValues(alpha: .8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyTab(ColorScheme scheme, IconData icon, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 38, color: scheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de UN servicio del paquete.
///
/// Se toca y se EXPANDE con animación para mostrar sus opciones (nota,
/// enlace, lo compartido y la fecha de cierre). En la cabecera SIEMPRE está el
/// botón de selección rápida: **Completar servicio** (o **Reabrir** si ya se
/// entregó), así no hay que desplegar nada para cerrar un servicio.
class _ServiceTile extends StatefulWidget {
  const _ServiceTile({
    required this.service,
    required this.canAdminister,
    required this.busy,
    required this.onComplete,
    required this.onReopen,
    required this.onNote,
    required this.onUrl,
    required this.onShare,
    required this.onCopy,
    required this.onPhotos,
    required this.onNotify,
  });

  final Map<String, dynamic> service;
  final bool canAdminister;
  final bool busy;
  final ValueChanged<Map<String, dynamic>> onComplete;
  final ValueChanged<Map<String, dynamic>> onReopen;
  final ValueChanged<Map<String, dynamic>> onNote;
  final ValueChanged<Map<String, dynamic>> onUrl;
  final ValueChanged<Map<String, dynamic>> onShare;
  final ValueChanged<String> onCopy;
  final ValueChanged<Map<String, dynamic>> onPhotos;
  final ValueChanged<Map<String, dynamic>> onNotify;

  @override
  State<_ServiceTile> createState() => _ServiceTileState();
}

class _ServiceTileState extends State<_ServiceTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = widget.service;
    final done = s['done'] == true;
    final when = hsParseDate(s['finishedAt']);
    final phone = MediaQuery.sizeOf(context).width < 560;
    final color = done ? _kGreen : _kTeal;
    final desc = (s['description'] ?? '').toString().trim();
    final url = (s['url'] ?? '').toString().trim();
    final shareFolder = (s['shareFolder'] ?? '').toString().trim();
    final shareLink = (s['shareLink'] ?? '').toString().trim();
    final items = (s['items'] as num?)?.toInt() ?? 0;
    // OPCIONES que le salen al CLIENTE para este servicio (las enciende el
    // estudio al compartir): antes «elegir fotos» salía en todos.
    final pickPhotos = s['pickPhotos'] == true;
    final showFolder = s['showFolder'] != false;
    final catalog = (s['service'] is Map)
        ? (s['service'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final photosMax =
        (s['photosMax'] as num?)?.toInt() ??
        (catalog['photosMax'] as num?)?.toInt() ??
        0;
    // ¿Se puede desplegar la tarjeta? SIEMPRE que haya algo dentro: los datos
    // del servicio (nota, enlaces, lo compartido…) o, si se administra, sus
    // OPCIONES (añadir nota/enlace, compartir). Antes solo se desplegaba si el
    // servicio YA tenía datos, así que un servicio pendiente no dejaba agregar
    // su nota ni su enlace hasta terminarlo.
    final hasDetail =
        desc.isNotEmpty ||
        url.isNotEmpty ||
        shareFolder.isNotEmpty ||
        shareLink.isNotEmpty ||
        items > 0 ||
        when != null ||
        widget.canAdminister;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: done
            ? _kGreen.withValues(alpha: .07)
            : scheme.surfaceContainerHighest.withValues(alpha: .30),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: done
              ? _kGreen.withValues(alpha: .35)
              : scheme.outlineVariant.withValues(alpha: .5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            // Despliega/guarda el detalle del servicio.
            onTap: hasDetail ? () => setState(() => _open = !_open) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 10, 8, 10),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      done ? Icons.task_alt : Icons.pending_actions_outlined,
                      size: 18,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (s['name'] ?? 'Servicio').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        _MiniPill(
                          icon: done
                              ? Icons.check_circle_outline
                              : Icons.timelapse,
                          label: (s['status'] ?? 'Pendiente').toString(),
                          color: done ? _kGreen : _kAmber,
                        ),
                      ],
                    ),
                  ),
                  // SELECCIÓN RÁPIDA: cerrar (o reabrir) el servicio sin
                  // desplegar nada.
                  if (widget.canAdminister)
                    done
                        ? Tooltip(
                            message: 'Reabrir el servicio',
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: widget.busy
                                  ? null
                                  : () => widget.onReopen(s),
                              icon: const Icon(
                                Icons.undo,
                                size: 18,
                                color: _kAmber,
                              ),
                            ),
                          )
                        // Completar NO es la acción principal de la tarjeta (lo
                        // importante es ver y llenar el servicio): va como
                        // botón discreto, del mismo peso que "Asignar del
                        // catálogo" (contorno), sin el verde de antes.
                        : (phone
                              ? Tooltip(
                                  message: 'Completar servicio',
                                  child: IconButton.outlined(
                                    visualDensity: VisualDensity.compact,
                                    onPressed: widget.busy
                                        ? null
                                        : () => widget.onComplete(s),
                                    icon: const Icon(Icons.task_alt, size: 18),
                                  ),
                                )
                              : OutlinedButton.icon(
                                  onPressed: widget.busy
                                      ? null
                                      : () => widget.onComplete(s),
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  icon: const Icon(Icons.task_alt, size: 15),
                                  label: const Text('Completar servicio'),
                                )),
                  if (hasDetail)
                    AnimatedRotation(
                      turns: _open ? .5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  else
                    const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_open || !hasDetail
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(11, 0, 11, 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(
                          height: 1,
                          color: scheme.outlineVariant.withValues(alpha: .5),
                        ),
                        const SizedBox(height: 9),
                        if (desc.isNotEmpty)
                          Text(
                            desc,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        if (url.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          _serviceLink(
                            icon: Icons.link,
                            label: url,
                            tooltip: 'Copiar enlace de la carpeta',
                            onTap: () => widget.onCopy(url),
                          ),
                        ],
                        if (shareFolder.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          _serviceLink(
                            icon: Icons.folder_open_outlined,
                            label: shareFolder,
                            tooltip: 'Copiar la carpeta compartida',
                            onTap: () => widget.onCopy(shareFolder),
                          ),
                        ],
                        if (shareLink.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          _serviceLink(
                            icon: Icons.link,
                            label: shareLink,
                            tooltip: 'Copiar la liga compartida',
                            onTap: () => widget.onCopy(shareLink),
                          ),
                        ],
                        if (pickPhotos ||
                            (showFolder && shareFolder.isNotEmpty)) ...[
                          const SizedBox(height: 7),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (pickPhotos)
                                _MiniPill(
                                  icon: Icons.photo_library_outlined,
                                  label: photosMax > 0
                                      ? 'Elegir fotos · máx. $photosMax'
                                      : 'Elegir fotos',
                                  color: _kTeal,
                                ),
                              if (showFolder && shareFolder.isNotEmpty)
                                const _MiniPill(
                                  icon: Icons.folder_open_outlined,
                                  label: 'Abrir carpeta',
                                  color: _kGreen,
                                ),
                            ],
                          ),
                        ],
                        if (items > 0) ...[
                          const SizedBox(height: 7),
                          Row(
                            children: [
                              const Icon(
                                Icons.photo_library_outlined,
                                size: 13,
                                color: _kTeal,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  '$items ${items == 1 ? 'foto elegida' : 'fotos elegidas'} por el cliente',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: _kTeal,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: widget.busy
                                    ? null
                                    : () => widget.onPhotos(s),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.visibility_outlined,
                                  size: 15,
                                ),
                                label: const Text('Ver fotos'),
                              ),
                            ],
                          ),
                        ],
                        if (when != null) ...[
                          const SizedBox(height: 7),
                          Row(
                            children: [
                              const Icon(
                                Icons.event_available,
                                size: 13,
                                color: _kGreen,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  'Terminado el ${hsDateLabel(when)}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: _kGreen,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (widget.canAdminister) ...[
                          const SizedBox(height: 9),
                          _serviceActions(s),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Las opciones del servicio: en el celular se deslizan de lado (UNA fila),
  /// en escritorio caben en la tarjeta.
  Widget _serviceActions(Map<String, dynamic> s) {
    final hasShare =
        (s['shareFolder'] ?? '').toString().trim().isNotEmpty ||
        (s['shareLink'] ?? '').toString().trim().isNotEmpty;
    final hasNote = (s['description'] ?? '').toString().trim().isNotEmpty;
    final hasUrl = (s['url'] ?? '').toString().trim().isNotEmpty;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          TextButton.icon(
            onPressed: widget.busy ? null : () => widget.onNote(s),
            style: _kServiceAction,
            icon: const Icon(Icons.edit_note, size: 16),
            label: Text(hasNote ? 'Editar nota' : 'Añadir nota'),
          ),
          TextButton.icon(
            onPressed: widget.busy ? null : () => widget.onUrl(s),
            style: _kServiceAction,
            icon: const Icon(Icons.link, size: 15),
            label: Text(hasUrl ? 'Editar enlace' : 'Agregar enlace'),
          ),
          TextButton.icon(
            onPressed: widget.busy ? null : () => widget.onShare(s),
            style: _kServiceAction,
            icon: const Icon(Icons.folder_shared_outlined, size: 15),
            label: Text(hasShare ? 'Editar lo compartido' : 'Compartir'),
          ),
          if (s['pickPhotos'] == true)
            TextButton.icon(
              onPressed: widget.busy ? null : () => widget.onNotify(s),
              style: _kServiceAction,
              icon: const Icon(Icons.notifications_active_outlined, size: 15),
              label: const Text('Avisar al cliente'),
            ),
        ],
      ),
    );
  }

  Widget _serviceLink({
    required IconData icon,
    required String label,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 13, color: AppColors.brand),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brand,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta "target" del selector de paquetes: lenguaje visual de la app
/// (degradado sutil, círculos geométricos y acento dorado de los flyers),
/// con elevación al pasar el mouse. Al tocarla se abre la administración.
class _PackageTargetCard extends StatefulWidget {
  const _PackageTargetCard({
    required this.pkg,
    required this.isVigente,
    required this.finished,
    required this.onTap,
  });

  final Map<String, dynamic> pkg;
  final bool isVigente;
  final bool finished;
  final VoidCallback? onTap;

  @override
  State<_PackageTargetCard> createState() => _PackageTargetCardState();
}

class _PackageTargetCardState extends State<_PackageTargetCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pkg = widget.pkg;
    final name = (pkg['name'] ?? 'Paquete').toString();
    final subtitle = (pkg['subtitle'] ?? '').toString();
    final categoryName = (pkg['categoryName'] ?? '').toString();
    final tier = (pkg['tierName'] ?? '').toString();
    final price = (pkg['price'] as num?) ?? 0;
    final paid = (pkg['paid'] as num?) ?? 0;
    final currency = (pkg['currency'] ?? 'MXN').toString();
    final status = (pkg['status'] ?? '').toString();
    final emoji = hsCategoryIcon(categoryName.isEmpty ? name : categoryName);
    final pct = price > 0 ? (paid / price).clamp(0.0, 1.0) : 0.0;
    // Look del tier para que cada paquete se distinga en el selector.
    final look = HsTierLook.of((pkg['tierName'] ?? '').toString());
    final statusColor = widget.finished
        ? scheme.onSurfaceVariant
        : (widget.isVigente ? _kGreen : look.accent);
    final statusLabel = widget.isVigente
        ? 'En administración'
        : (widget.finished ? 'Terminado' : status);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hover ? -5 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _hover ? .16 : .07),
              blurRadius: _hover ? 18 : 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: widget.onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary.withValues(alpha: _hover ? .15 : .09),
                  scheme.primary.withValues(alpha: .025),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: widget.isVigente
                    ? look.accent.withValues(alpha: .55)
                    : scheme.outlineVariant.withValues(alpha: .7),
                width: widget.isVigente ? 1.4 : 1,
              ),
            ),
            child: Stack(
              children: [
                // Círculos geométricos: mismo lenguaje que los módulos.
                Positioned(
                  right: -34,
                  top: -46,
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary.withValues(alpha: .06),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          if (tier.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: look.accent.withValues(alpha: .14),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: look.accent.withValues(alpha: .40),
                                ),
                              ),
                              child: Text(
                                tier.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9,
                                  letterSpacing: 1.4,
                                  fontWeight: FontWeight.w800,
                                  color: look.accentSoft,
                                ),
                              ),
                            ),
                          const Spacer(),
                          if (statusLabel.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: .16),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                statusLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: statusColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(emoji, style: const TextStyle(fontSize: 17)),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              (categoryName.isEmpty ? 'General' : categoryName)
                                  .toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 9.5,
                                letterSpacing: 1.6,
                                fontWeight: FontWeight.w800,
                                color: look.accent.withValues(alpha: .85),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15.5,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontStyle: FontStyle.italic,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      // Avance de pago: barra + % (compacto).
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: pct,
                                minHeight: 6,
                                backgroundColor: scheme.surfaceContainerHighest
                                    .withValues(alpha: .6),
                                valueColor: AlwaysStoppedAnimation(
                                  widget.finished ? _kGreen : look.accent,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(pct * 100).toStringAsFixed(0)} %',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: widget.finished ? _kGreen : look.accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PRECIO',
                                  style: TextStyle(
                                    fontSize: 9,
                                    letterSpacing: 1.1,
                                    fontWeight: FontWeight.w800,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  hsMoney(price, currency),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: look.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'ABONADO',
                                style: TextStyle(
                                  fontSize: 9,
                                  letterSpacing: 1.1,
                                  fontWeight: FontWeight.w800,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                hsMoney(paid, currency),
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: _kGreen,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'Ver administración',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .3,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 15,
                            color: scheme.primary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de un EVENTO agendado del paquete: el mismo diseño que usan el
/// botón "Agenda" y la pestaña Calendario del administrador del paquete.
/// [past] atenúa los eventos ya pasados y las acciones son opcionales
/// (null = solo lectura).
class _AgendaEventCard extends StatelessWidget {
  const _AgendaEventCard({
    required this.agenda,
    this.onEdit,
    this.onDelete,
    this.past = false,
  });

  final Map<String, dynamic> agenda;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = hsParseDate(agenda['eventDate']);
    final service = (agenda['serviceName'] ?? '').toString();
    final desc = (agenda['description'] ?? '').toString();
    final place = HsPlace.of(agenda);
    final monthAbbr = date == null
        ? ''
        : kHsMonths[date.month - 1].substring(0, 3);
    final accent = past ? _kTeal.withValues(alpha: .55) : _kTeal;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(
          alpha: past ? .20 : .35,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: past ? .25 : .45)),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  date == null ? '--' : '${date.day}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: accent,
                  ),
                ),
                Text(
                  monthAbbr,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        date == null
                            ? 'Fecha por definir'
                            : '${hsDateLabel(date)} · ${hsTimeLabel(date)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (past)
                      const _MiniPill(
                        icon: Icons.history,
                        label: 'Pasado',
                        color: _kTeal,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  service.isEmpty ? 'Sin servicio específico' : service,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // LUGAR: solo si la agenda lo tiene agregado. Tocar abre el
                // mapa del equipo.
                if (place != null)
                  InkWell(
                    onTap: () => hsOpenPlace(place),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Icon(Icons.place_outlined, size: 12, color: accent),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              place.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (desc.isNotEmpty)
                  Text(
                    desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (onEdit != null)
            IconButton(
              tooltip: 'Editar',
              visualDensity: VisualDensity.compact,
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
            ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Eliminar',
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
              icon: Icon(
                Icons.delete_outline,
                size: 18,
                color: scheme.error.withValues(alpha: .8),
              ),
            ),
        ],
      ),
    );
  }
}

/// Botón de pestaña del modal (Servicios / Calendario / Movimientos).
class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          // FittedBox: la pestaña se escala si el ancho no alcanza (celular),
          // en vez de desbordar la fila.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Barra de progreso con etiqueta y valor (pago / servicios).
class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.label,
    required this.value,
    required this.color,
    required this.trailing,
    this.labelWidth = 132,
  });

  final String label;
  final double value;
  final Color color;
  final String trailing;

  /// Ancho de la etiqueta: en la ficha lateral es compacto.
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 52,
          child: Text(
            trailing,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// Pastilla pequeña de icono + texto (estados, conteos, tipos).
class _MiniPill extends StatelessWidget {
  const _MiniPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de cuadros de dinero: TODOS en una sola línea horizontal, con el
/// mismo ancho entre sí (nada de unos encima de otros).
class _MoneyRow extends StatelessWidget {
  const _MoneyRow({required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    // IntrinsicHeight: todos los cuadros comparten la altura del más alto
    // (el Row necesita altura acotada para poder estirarlos).
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(child: tiles[i]),
          ],
        ],
      ),
    );
  }
}

/// Caja compacta de un importe (Total / Abonado / Saldo / Gastado…).
/// La etiqueta puede ir en DOS líneas ("ABONO / EXTERNO") y el monto se
/// encoge dentro del ancho disponible: el cuadro nunca se desborda.
class _MoneyTile extends StatelessWidget {
  const _MoneyTile(this.label, this.value, this.tint);

  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              height: 1.15,
              letterSpacing: .2,
              fontWeight: FontWeight.w800,
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
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: tint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Importe/valor pequeño en columna (lo usa el diálogo de abonos).
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
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

// ==================================================================
// Registrar un movimiento del paquete
// (inversión / gasto / ahorro / abono externo; el abono tiene su diálogo)
//
// El AHORRO se puede capturar como MONTO o como PORCENTAJE del disponible
// (abonado - gastado): el diálogo calcula el monto equivalente en vivo.
// ==================================================================

class _MovementDialog extends StatefulWidget {
  const _MovementDialog({
    required this.package,
    this.disponible = 0,
    this.currency = 'MXN',
    this.movement,
    this.recipients = const [],
  });

  final Map<String, dynamic> package;

  /// Dinero libre del paquete (base del ahorro en porcentaje).
  final num disponible;
  final String currency;

  /// Colaboradores y empleados a los que se puede asignar un pago.
  final List<Map<String, dynamic>> recipients;

  /// Movimiento/abono a EDITAR (null = registrar uno nuevo). Cuando viene,
  /// el diálogo precarga sus datos y guarda con `editar-movimiento`.
  final Map<String, dynamic>? movement;

  @override
  State<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<_MovementDialog> {
  late String _kind = _initialKind();

  /// Modo de captura del ahorro: monto fijo o porcentaje del disponible.
  String _mode = 'monto';

  final TextEditingController _amount = TextEditingController();
  final TextEditingController _percent = TextEditingController();
  final TextEditingController _concept = TextEditingController();
  bool _saving = false;
  String? _error;

  /// Destinatario del pago (solo se usa cuando el tipo es `pago`).
  int? _recipientId;

  /// ¿Se está editando un registro existente?
  bool get _editing => widget.movement != null;

  /// Un ABONO vive en purchased_packages_payments (source 'payment'): solo se
  /// le puede cambiar monto y concepto, no el tipo.
  bool get _isPayment =>
      (widget.movement?['source'] ?? 'movement').toString() == 'payment';

  String _initialKind() {
    final m = widget.movement;
    if (m == null) return 'inversion';
    if ((m['source'] ?? 'movement').toString() == 'payment') return 'abono';
    final k = (m['kind'] ?? 'gasto').toString();
    return _kMovementKinds.contains(k) ? k : 'gasto';
  }

  @override
  void initState() {
    super.initState();
    final m = widget.movement;
    if (m != null) {
      final amount = (m['amount'] as num?) ?? 0;
      _amount.text = _clean(amount);
      _concept.text = (m['description'] ?? '').toString();
      _recipientId = (m['userId'] as num?)?.toInt();
    }
  }

  bool get _isSavings => _kind == 'ahorro';
  bool get _byPercent => _isSavings && _mode == 'porcentaje';

  num get _percentValue =>
      num.tryParse(_percent.text.replaceAll(',', '').trim()) ?? 0;

  /// Monto que se enviará al backend: el capturado o, en ahorro por
  /// porcentaje, el porcentaje aplicado al disponible (redondeado a centavos).
  num get _resolvedAmount {
    if (!_byPercent) {
      return num.tryParse(_amount.text.replaceAll(',', '').trim()) ?? 0;
    }
    final value = widget.disponible * _percentValue / 100;
    return (value * 100).roundToDouble() / 100;
  }

  @override
  void dispose() {
    _amount.dispose();
    _percent.dispose();
    _concept.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final amount = _resolvedAmount;
    if (amount <= 0) {
      setState(
        () => _error = _byPercent
            ? 'El porcentaje debe dar un monto mayor a 0'
            : 'Escribe un monto mayor a 0',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    // El ahorro por porcentaje deja constancia del % aplicado en su
    // concepto, para que el historial diga de dónde salió el monto.
    final note = _concept.text.trim();
    final description = _byPercent
        ? [
            if (note.isNotEmpty) note,
            '${_clean(_percentValue)} % del disponible',
          ].join(' · ')
        : note;
    try {
      if (_editing) {
        // El backend solo deja editar mientras el paquete no esté finalizado.
        await HsApi.editPackageMovement(
          (widget.movement!['id'] as num).toInt(),
          source: _isPayment ? 'payment' : 'movement',
          kind: _isPayment ? null : _kind,
          amount: amount,
          description: description,
        );
      } else {
        await HsApi.addPackageMovement(
          purchasedPackageId: (widget.package['id'] as num).toInt(),
          kind: _kind,
          amount: amount,
          description: description,
          userId: _kind == 'pago' ? _recipientId : null,
        );
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
          _error = 'No se pudo registrar el movimiento';
          _saving = false;
        });
      }
    }
  }

  /// Número corto para textos: "10" en vez de "10.000000".
  static String _clean(num v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _moveColor(_kind);
    final amount = _resolvedAmount;
    // Un abono edita solo monto y concepto (su tipo lo define la tabla de
    // pagos); el resto sí puede cambiar de tipo.
    final showKinds = !_isPayment;
    return FormDialog(
      icon: _editing ? Icons.edit_outlined : Icons.swap_vert,
      title: _editing
          ? (_isPayment ? 'Editar abono' : 'Editar movimiento')
          : 'Movimiento del paquete',
      subtitle: _editing
          ? 'Solo mientras el paquete no esté finalizado · '
                '${_moveLabel(_kind)}'
          : '${(widget.package['name'] ?? '').toString()} · inversión, gasto, '
                'ahorro, abono externo o pago',
      saving: _saving,
      error: _error,
      saveLabel: _editing ? 'Guardar cambios' : 'Registrar',
      maxWidth: 460,
      onCancel: () => Navigator.of(context).pop(false),
      onSave: _save,
      children: [
        if (!showKinds) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _moveColor('abono').withValues(alpha: .10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _moveColor('abono').withValues(alpha: .45),
              ),
            ),
            child: Row(
              children: [
                Icon(_moveIcon('abono'), size: 17, color: _moveColor('abono')),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Este registro es un abono: se descontará del saldo del '
                    'paquete al guardar.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        !showKinds
            ? const SizedBox.shrink()
            : FormSection(
                label: 'Tipo de movimiento',
                child: Column(
                  children: [
                    for (final kind in _kMovementKinds)
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _saving
                            ? null
                            : () => setState(() => _kind = kind),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _kind == kind
                                ? _moveColor(kind).withValues(alpha: .10)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _kind == kind
                                  ? _moveColor(kind).withValues(alpha: .55)
                                  : scheme.outlineVariant.withValues(alpha: .5),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _kind == kind
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                size: 17,
                                color: _kind == kind
                                    ? _moveColor(kind)
                                    : scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                _moveIcon(kind),
                                size: 17,
                                color: _moveColor(kind),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _moveLabel(kind),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      _moveHint(kind),
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
        const SizedBox(height: 14),
        if (showKinds && _kind == 'pago') ...[
          FormSection(
            label: '¿A quién se le paga?',
            child: widget.recipients.isEmpty
                ? Text(
                    'No hay colaboradores ni empleados activos.',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                : DropdownButtonFormField<int>(
                    initialValue: _recipientId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Colaborador o empleado',
                      prefixIcon: Icon(Icons.person_outline, size: 20),
                    ),
                    items: [
                      for (final r in widget.recipients)
                        DropdownMenuItem<int>(
                          value: (r['id'] as num).toInt(),
                          child: Text(
                            '${(r['name'] ?? '').toString()}'
                            '${(r['roleName'] ?? '').toString().isEmpty ? '' : ' · ${(r['roleName'] ?? '').toString()}'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _recipientId = v),
                  ),
          ),
          const SizedBox(height: 14),
        ],
        if (_isSavings) ...[
          // Base del ahorro en porcentaje: el disponible del paquete.
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _kTeal.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kTeal.withValues(alpha: .30)),
            ),
            child: Row(
              children: [
                const Icon(Icons.savings_rounded, size: 16, color: _kTeal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Disponible del paquete (abonado - gastado - ahorro + '
                    'abono externo)',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  hsMoney(widget.disponible, widget.currency),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: _kTeal,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FormSection(
            label: '¿Cómo se captura el ahorro?',
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment(
                  value: 'monto',
                  icon: Icon(Icons.attach_money, size: 16),
                  label: Text('Cantidad'),
                ),
                ButtonSegment(
                  value: 'porcentaje',
                  icon: Icon(Icons.percent, size: 16),
                  label: Text('Porcentaje'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _saving
                  ? null
                  : (s) => setState(() => _mode = s.first),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (_byPercent) ...[
          FormSection(
            label: 'Porcentaje del disponible',
            child: TextField(
              controller: _percent,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Porcentaje',
                suffixText: '%',
                prefixIcon: Icon(Icons.percent, size: 20),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.calculate_outlined, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Se ahorrarán',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  hsMoney(amount, widget.currency),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ] else
          FormSection(
            label: 'Monto',
            child: TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Monto',
                prefixIcon: Icon(Icons.attach_money, size: 20),
              ),
            ),
          ),
        const SizedBox(height: 14),
        FormSection(
          label: 'Concepto',
          child: TextField(
            controller: _concept,
            minLines: 2,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Descripción',
              hintText: 'Ej. Transporte, renta de equipo, ahorro del mes…',
              alignLabelWithHint: true,
            ),
          ),
        ),
      ],
    );
  }
}

// ==================================================================
// Repartir un pago entre colaboradores y empleados
// ==================================================================

/// Reparte un monto del paquete entre COLABORADORES y EMPLEADOS, en dos
/// modos: partes iguales (se escribe el total y se marca a quiénes) o por
/// numeración (un monto por persona). Cada parte se guarda como un movimiento
/// `pago` con su destinatario y cuenta como gasto.
class _SplitPaymentDialog extends StatefulWidget {
  const _SplitPaymentDialog({
    required this.package,
    required this.recipients,
    required this.currency,
  });

  final Map<String, dynamic> package;

  /// Colaboradores y empleados activos (lo determina el backend).
  final List<Map<String, dynamic>> recipients;
  final String currency;

  @override
  State<_SplitPaymentDialog> createState() => _SplitPaymentDialogState();
}

class _SplitPaymentDialogState extends State<_SplitPaymentDialog> {
  /// 'iguales' (partes iguales) o 'numeracion' (un monto por persona).
  String _mode = 'iguales';

  final TextEditingController _total = TextEditingController();
  final TextEditingController _concept = TextEditingController();
  final Set<int> _selected = {};
  final Map<int, TextEditingController> _amounts = {};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final r in widget.recipients) {
      final id = (r['id'] as num).toInt();
      _amounts[id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _total.dispose();
    _concept.dispose();
    for (final c in _amounts.values) {
      c.dispose();
    }
    super.dispose();
  }

  num _parse(String s) => num.tryParse(s.replaceAll(',', '').trim()) ?? 0;

  num get _totalValue => _parse(_total.text);

  num _amountOf(int id) => _parse(_amounts[id]?.text ?? '');

  /// Los ELEGIDOS, en el orden de la lista: solo a ellos se les paga.
  List<Map<String, dynamic>> get _chosen => widget.recipients
      .where((r) => _selected.contains((r['id'] as num).toInt()))
      .toList();

  /// Suma de los montos de los ELEGIDOS (modo por numeración).
  num get _byNumberTotal =>
      _selected.fold<num>(0, (sum, id) => sum + _amountOf(id));

  /// Lo que le toca a cada elegido en partes iguales.
  num get _perPerson => _selected.isEmpty ? 0 : _totalValue / _selected.length;

  /// Montos positivos de los ELEGIDOS (los vacíos se ignoran).
  List<Map<String, dynamic>> _numberParts() {
    final parts = <Map<String, dynamic>>[];
    for (final r in _chosen) {
      final id = (r['id'] as num).toInt();
      final amount = _amountOf(id);
      if (amount > 0) parts.add({'userId': id, 'amount': amount});
    }
    return parts;
  }

  void _toggle(int id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  /// Reparte el total escrito en partes IGUALES entre los elegidos (útil en el
  /// modo por numeración para no teclear cada monto).
  void _spreadEquals() {
    final total = _totalValue;
    if (total <= 0 || _selected.isEmpty) return;
    final base = (total / _selected.length * 100).round() / 100;
    var acumulado = 0.0;
    final ids = _selected.toList();
    setState(() {
      for (var i = 0; i < ids.length; i++) {
        final last = i == ids.length - 1;
        final amount = last ? ((total - acumulado) * 100).round() / 100 : base;
        acumulado += amount;
        _amounts[ids[i]]?.text = amount.toStringAsFixed(2);
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final pkgId = (widget.package['id'] as num).toInt();
    final description = _concept.text.trim();
    if (_selected.isEmpty) {
      setState(() => _error = 'Marca al menos una persona');
      return;
    }
    if (_mode == 'iguales') {
      if (_totalValue <= 0) {
        setState(() => _error = 'Escribe el total a repartir');
        return;
      }
    } else if (_numberParts().isEmpty) {
      setState(() => _error = 'Escribe al menos un monto mayor a 0');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_mode == 'iguales') {
        await HsApi.splitPackagePayment(
          purchasedPackageId: pkgId,
          mode: 'iguales',
          total: _totalValue,
          userIds: _selected.toList(),
          description: description,
        );
      } else {
        await HsApi.splitPackagePayment(
          purchasedPackageId: pkgId,
          mode: 'numeracion',
          parts: _numberParts(),
          description: description,
        );
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
          _error = 'No se pudo repartir el pago';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _moveColor('pago');
    final allChosen = _selected.length == widget.recipients.length;
    return FormDialog(
      icon: Icons.handshake_outlined,
      title: 'Repartir pago',
      subtitle:
          '${(widget.package['name'] ?? '').toString()} · se registra a '
          'quién se le pagó y cuánto. NO se descuenta del paquete.',
      saving: _saving,
      error: _error,
      saveLabel: 'Repartir',
      maxWidth: 520,
      onCancel: () => Navigator.of(context).pop(false),
      onSave: _save,
      children: [
        // 1) PRIMERO se eligen las personas: solo a ellas se les paga.
        FormSection(
          label: '1. Elige a quiénes se les paga',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final r in widget.recipients) _personTile(r),
              const SizedBox(height: 6),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            if (allChosen) {
                              _selected.clear();
                            } else {
                              _selected
                                ..clear()
                                ..addAll(
                                  widget.recipients.map(
                                    (r) => (r['id'] as num).toInt(),
                                  ),
                                );
                            }
                          }),
                    icon: Icon(
                      allChosen
                          ? Icons.check_box_outline_blank
                          : Icons.select_all,
                      size: 18,
                    ),
                    label: Text(allChosen ? 'Quitar todos' : 'Todos'),
                  ),
                  const Spacer(),
                  Text(
                    _selected.isEmpty
                        ? 'Nadie seleccionado'
                        : (_selected.length == 1
                              ? '1 persona'
                              : '${_selected.length} personas'),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _selected.isEmpty
                          ? scheme.onSurfaceVariant
                          : color,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_selected.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: .35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: .5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Marca arriba a quién se le reparte y luego elige cómo '
                    'repartirlo.',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          )
        else ...[
          // 2) DESPUÉS, cómo se reparte entre los elegidos.
          FormSection(
            label: '2. ¿Cómo se reparte?',
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment(
                  value: 'iguales',
                  icon: Icon(Icons.balance, size: 16),
                  label: Text('Partes iguales'),
                ),
                ButtonSegment(
                  value: 'numeracion',
                  icon: Icon(Icons.tag, size: 16),
                  label: Text('Por numeración'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _saving
                  ? null
                  : (s) => setState(() => _mode = s.first),
            ),
          ),
          const SizedBox(height: 14),
          if (_mode == 'iguales') ...[
            FormSection(
              label: 'Total a repartir',
              child: TextField(
                controller: _total,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Total',
                  prefixIcon: Icon(Icons.attach_money, size: 20),
                ),
              ),
            ),
            if (_totalValue > 0) ...[
              const SizedBox(height: 10),
              _summary(
                color,
                scheme,
                'A cada uno de los elegidos le toca',
                hsMoney(_perPerson, widget.currency),
              ),
            ],
          ] else ...[
            FormSection(
              label: 'Monto de cada elegido',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final r in _chosen) _amountRow(r),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _total,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Total (opcional)',
                      helperText:
                          'Escríbelo y toca «Repartir en partes iguales» '
                          'para llenar los montos.',
                      prefixIcon: Icon(Icons.attach_money, size: 20),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _saving || _totalValue <= 0
                          ? null
                          : _spreadEquals,
                      icon: const Icon(Icons.balance, size: 16),
                      label: const Text('Repartir en partes iguales'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _summary(
                    color,
                    scheme,
                    'Total a repartir',
                    hsMoney(_byNumberTotal, widget.currency),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          FormSection(
            label: 'Concepto (opcional)',
            child: TextField(
              controller: _concept,
              minLines: 1,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                hintText: 'Ej. Pago de la semana…',
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Fila seleccionable de una persona (con su rol).
  Widget _personTile(Map<String, dynamic> r) {
    final scheme = Theme.of(context).colorScheme;
    final color = _moveColor('pago');
    final id = (r['id'] as num).toInt();
    final picked = _selected.contains(id);
    final name = (r['name'] ?? '').toString();
    final role = (r['roleName'] ?? '').toString();
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _saving ? null : () => _toggle(id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: picked
                ? color.withValues(alpha: .10)
                : scheme.surfaceContainerHighest.withValues(alpha: .25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: picked
                  ? color.withValues(alpha: .45)
                  : scheme.outlineVariant.withValues(alpha: .5),
            ),
          ),
          child: Row(
            children: [
              Icon(
                picked
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: picked ? color : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              CircleAvatar(
                radius: 14,
                backgroundColor: color.withValues(alpha: .16),
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (role.isNotEmpty)
                      Text(
                        role,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Fila de monto de una persona ELEGIDA (modo por numeración).
  Widget _amountRow(Map<String, dynamic> r) {
    final id = (r['id'] as num).toInt();
    final name = (r['name'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 128,
            child: TextField(
              controller: _amounts[id],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                isDense: true,
                hintText: '0',
                prefixText: '\$ ',
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Recuadro resumen del dinero (con el color del pago).
  Widget _summary(
    Color color,
    ColorScheme scheme,
    String label,
    String amount,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Row(
        children: [
          Icon(Icons.calculate_outlined, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================================================================
// Descripción de un servicio (cierre o avance)
// ==================================================================

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.intro,
    required this.label,
    required this.confirmLabel,
    this.initial = '',
    this.allowEmpty = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String intro;
  final String label;
  final String confirmLabel;
  final String initial;
  final bool allowEmpty;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    if (text.isEmpty && !widget.allowEmpty) {
      setState(() => _error = 'Escribe una descripción');
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FormDialog(
      icon: widget.icon,
      title: widget.title,
      subtitle: widget.subtitle,
      error: _error,
      saveLabel: widget.confirmLabel,
      maxWidth: 460,
      onCancel: () => Navigator.of(context).pop(),
      onSave: _save,
      children: [
        Text(
          widget.intro,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.3,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        FormSection(
          label: widget.label,
          child: TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: widget.label,
              alignLabelWithHint: true,
            ),
          ),
        ),
      ],
    );
  }
}

/// Selector de carpeta del Drive con el diseño del panel: cabecera con el
/// icono, migas de pan, carpetas como tarjetas y las acciones abajo.
///
/// Devuelve los segmentos ABSOLUTOS de la carpeta elegida (null al cancelar).
///
/// Con [roots] NO vacío el selector trabaja DENTRO del drive del cliente: la
/// carpeta compartida es la RAÍZ —no hay nada antes de ella y no se puede
/// subir más arriba—, se puede cambiar entre las carpetas compartidas y las
/// que se solapan con lo ya compartido salen bloqueadas.
class _DriveFolderPicker extends StatefulWidget {
  const _DriveFolderPicker({
    required this.base,
    required this.initial,
    required this.load,
    required this.conflict,
    this.roots = const <String>[],
  });

  /// Carpeta que hace de RAÍZ ('' = el Drive completo desde su raíz).
  final String base;

  /// Ruta relativa a [base] donde se abre el selector.
  final List<String> initial;

  /// Lista las SUBcarpetas de una ruta (en segmentos ABSOLUTOS del Drive).
  final Future<List<String>> Function(List<String> path) load;

  /// ¿[absolutePath] se solapa con algo ya compartido? Devuelve con cuál.
  final String? Function(String absolutePath) conflict;

  /// Carpetas compartidas con el cliente (vacío = todo el Drive).
  final List<String> roots;

  @override
  State<_DriveFolderPicker> createState() => _DriveFolderPickerState();
}

class _DriveFolderPickerState extends State<_DriveFolderPicker> {
  late String _base = widget.base;
  late List<String> _rel = List<String>.of(widget.initial);
  List<String> _folders = const [];
  bool _loading = true;
  String? _error;

  /// ¿Se está eligiendo dentro del drive del cliente?
  bool get _scoped => widget.roots.isNotEmpty;

  /// Segmentos de una ruta ('ReynaCoot/Fiesta' → ['ReynaCoot', 'Fiesta']).
  List<String> _segments(String path) => path.isEmpty
      ? const <String>[]
      : drivePathNormalize(path).split('/').where((s) => s.isNotEmpty).toList();

  /// Ruta ABSOLUTA de la carpeta abierta ([extra] mira una subcarpeta suya).
  List<String> _absolute([List<String>? extra]) => [
    ..._segments(_base),
    ...(extra ?? _rel),
  ];

  /// Ruta absoluta de la carpeta abierta, como texto (para el solapamiento).
  String get _here => _absolute().join('/');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.load(_absolute());
      if (!mounted) return;
      setState(() {
        _folders = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _folders = const [];
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _enter(String name) {
    setState(() => _rel = [..._rel, name]);
    _load();
  }

  void _up() {
    if (_rel.isEmpty) return;
    setState(() => _rel = _rel.sublist(0, _rel.length - 1));
    _load();
  }

  /// Cambia de carpeta compartida ("drive del cliente"): se vuelve a su raíz.
  void _switchTo(String root) {
    if (root == _base) return;
    setState(() {
      _base = root;
      _rel = <String>[];
      _folders = const [];
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final phone = hsIsPhone(context);
    final conflict = widget.conflict(_here);
    // Migas: la carpeta compartida es la RAÍZ y en el Drive completo se navega
    // desde Mi Drive.
    final crumbs = <String>[
      if (_base.isEmpty) 'Mi Drive' else _segments(_base).last,
      ..._rel,
    ];
    // La raíz del Drive completo NO se comparte (sería todo el drive).
    final canPick = (_scoped || _rel.isNotEmpty) && conflict == null;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 14, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      title: _header(scheme),
      content: SizedBox(
        width: phone ? double.infinity : 430,
        height: phone ? double.infinity : 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.roots.length > 1) ...[
              _rootPicker(scheme),
              const SizedBox(height: 10),
            ],
            _crumbBar(scheme, crumbs),
            if (conflict != null) ...[
              const SizedBox(height: 8),
              _conflictNotice(scheme, conflict),
            ],
            const SizedBox(height: 10),
            Expanded(child: _body(scheme)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: canPick ? () => Navigator.pop(context, _absolute()) : null,
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Compartir esta carpeta'),
        ),
      ],
    );
  }

  /// Cabecera: icono degradado + título y aclaración de qué se puede elegir.
  Widget _header(ColorScheme scheme) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.brand, AppColors.brandDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.brand.withValues(alpha: .30),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.folder_open_outlined,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Carpeta del Drive',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              Text(
                _scoped
                    ? 'Solo lo que está dentro del Drive del cliente'
                    : 'Elige cualquier carpeta del Drive',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Cambio de carpeta compartida: solo con más de una (si hay una, esa es el
  /// drive del cliente y no hace falta elegir).
  Widget _rootPicker(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DRIVE DEL CLIENTE',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: .9,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final r in widget.roots)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: r == _base,
                    showCheckmark: false,
                    selectedColor: AppColors.brand,
                    side: BorderSide(
                      color: r == _base
                          ? AppColors.brand
                          : scheme.outlineVariant.withValues(alpha: .6),
                    ),
                    avatar: Icon(
                      Icons.folder_rounded,
                      size: 16,
                      color: r == _base ? Colors.white : AppColors.brand,
                    ),
                    label: Text(
                      drivePathNormalize(r).split('/').last,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: r == _base ? Colors.white : scheme.onSurface,
                      ),
                    ),
                    onSelected: (_) => _switchTo(r),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Migas de pan: la carpeta compartida primero y lo abierto dentro de ella.
  Widget _crumbBar(ColorScheme scheme, List<String> crumbs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.brand.withValues(alpha: .22)),
      ),
      child: Row(
        children: [
          Icon(
            _scoped ? Icons.folder_shared_outlined : Icons.home_outlined,
            size: 16,
            color: AppColors.brand,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              // La carpeta actual (la última miga) siempre a la vista.
              reverse: true,
              child: Row(
                children: [
                  for (var i = 0; i < crumbs.length; i++) ...[
                    if (i > 0)
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                    Text(
                      crumbs[i],
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: i == crumbs.length - 1
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: i == crumbs.length - 1
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Aviso de solapamiento: la carpeta está dentro de (o contiene a) algo ya
  /// compartido y por eso no se puede elegir.
  Widget _conflictNotice(ColorScheme scheme, String conflict) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.error.withValues(alpha: .35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 16, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '«$conflict» ya está compartida con este cliente y esta carpeta '
              'está dentro de aquella (o la contiene). Elige otra para no '
              'compartir dos veces lo mismo.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.3,
                color: scheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(ColorScheme scheme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: scheme.error),
        ),
      );
    }
    if (_folders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.folder_off_outlined,
                  color: scheme.onSurfaceVariant,
                  size: 26,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Esta carpeta no tiene subcarpetas.\nPuedes compartirla '
                'tal cual con el botón de abajo.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      children: [
        if (_rel.isNotEmpty) _upTile(scheme),
        for (final f in _folders) _folderTile(scheme, f),
      ],
    );
  }

  /// Subir un nivel (nunca por encima de la carpeta compartida).
  Widget _upTile(ColorScheme scheme) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _up,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: .6),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                Icons.arrow_upward,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Subir un nivel',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Una carpeta: tarjeta con su icono. Las que se solapan con lo ya
  /// compartido salen bloqueadas y dicen por qué.
  Widget _folderTile(ColorScheme scheme, String name) {
    final clash = widget.conflict(_absolute([..._rel, name]).join('/'));
    final locked = clash != null;
    final tint = locked ? scheme.error : AppColors.brand;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: locked ? null : () => _enter(name),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: .30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: locked
                ? scheme.error.withValues(alpha: .35)
                : scheme.outlineVariant.withValues(alpha: .45),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                locked ? Icons.lock_outline : Icons.folder_rounded,
                size: 18,
                color: tint,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (locked)
                    Text(
                      'Ya compartida en «$clash»',
                      maxLines: 2,
                      style: TextStyle(fontSize: 11, color: scheme.error),
                    ),
                ],
              ),
            ),
            if (!locked)
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

/// Comparte con el cliente una CARPETA del Drive y/o una LIGA para UN servicio
/// del paquete. Devuelve `(folder, link)` al guardar, o null al cancelar.
///
/// La carpeta se elige DENTRO del Drive del cliente (lo que ya tiene
/// compartido): es lo único que él ve, así que el selector se abre en esa
/// carpeta y no deja salir de ahí.
/// Lo que devuelve el diálogo de compartir de un servicio: la carpeta, la liga
/// y QUÉ opciones le salen al cliente en «Mi paquete».
class _ServiceShare {
  const _ServiceShare({
    required this.folder,
    required this.link,
    required this.pickPhotos,
    required this.showFolder,
  });

  final String folder;
  final String link;

  /// ¿El cliente puede elegir fotos de su Drive para este servicio?
  final bool pickPhotos;

  /// ¿Se le muestra «Abrir carpeta» (cuando hay carpeta compartida)?
  final bool showFolder;
}

class _ServiceShareDialog extends StatefulWidget {
  const _ServiceShareDialog({
    required this.serviceName,
    required this.folder,
    required this.link,
    required this.pickPhotos,
    required this.showFolder,
    this.photosMax = 0,
    this.allowFolder = true,
    this.onPickFolder,
  });

  final String serviceName;
  final String folder;
  final String link;

  /// Opciones que le salen al cliente para ESTE servicio.
  final bool pickPhotos;
  final bool showFolder;

  /// Parámetros del SERVICIO (catálogo): máximo de fotos (0 = no ofrece) y si
  /// usa carpeta del Drive.
  final int photosMax;
  final bool allowFolder;

  /// Abre el selector de carpetas del Drive y devuelve la ruta elegida.
  /// null = sin permiso para ver el Drive: la opción no se dibuja.
  final Future<List<String>?> Function()? onPickFolder;

  @override
  State<_ServiceShareDialog> createState() => _ServiceShareDialogState();
}

class _ServiceShareDialogState extends State<_ServiceShareDialog> {
  late final TextEditingController _link = TextEditingController(
    text: widget.link,
  );
  late String _folder = widget.folder;
  late bool _pickPhotos = widget.pickPhotos;
  late bool _showFolder = widget.showFolder;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final pick = widget.onPickFolder;
    if (pick == null) return;
    final segments = await pick();
    if (segments == null || segments.isEmpty) return;
    setState(() => _folder = segments.join('/'));
  }

  /// ¿Se puede encender «Elegir fotos»? Necesita que el servicio lo ofrezca
  /// (photosMax > 0) y una carpeta compartida (el cliente elige DENTRO de ella).
  bool get _canPickPhotos => widget.photosMax > 0 && _folder.trim().isNotEmpty;

  void _save() => Navigator.of(context).pop(
    _ServiceShare(
      folder: _folder,
      link: _link.text.trim(),
      pickPhotos: _pickPhotos && _canPickPhotos,
      showFolder:
          _showFolder && widget.allowFolder && _folder.trim().isNotEmpty,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FormDialog(
      icon: Icons.folder_shared_outlined,
      title: 'Compartir con el cliente',
      subtitle: widget.serviceName,
      saveLabel: 'Guardar',
      maxWidth: 520,
      onCancel: () => Navigator.of(context).pop(),
      onSave: _save,
      children: [
        Text(
          'Para ESTE servicio puedes compartir una carpeta del Drive del '
          'cliente, una liga, o las dos. El cliente las verá en «Mi paquete» '
          'junto a las fotos que elija del Drive.',
          style: TextStyle(
            fontSize: 12.5,
            height: 1.3,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        // Sin permiso para ver el Drive, esta sección no se dibuja (la liga y
        // las demás opciones siguen igual).
        if (widget.onPickFolder != null || _folder.isNotEmpty)
          FormSection(
            label: 'Carpeta del Drive',
            child: _folder.isEmpty ? _pickTile(scheme) : _folderCard(scheme),
          ),
        const SizedBox(height: 16),
        FormSection(
          label: 'Liga (opcional)',
          child: TextField(
            controller: _link,
            decoration: const InputDecoration(
              hintText: 'https://…',
              prefixIcon: Icon(Icons.link, size: 20),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FormSection(
          label: 'Qué ve el cliente en «Mi paquete»',
          child: Column(
            children: [
              _option(
                icon: Icons.photo_library_outlined,
                title: 'Elegir fotos',
                subtitle: widget.photosMax <= 0
                    ? 'Este servicio no lo ofrece. Actívalo en el módulo '
                          'Servicios (parámetros especiales).'
                    : _folder.isEmpty
                    ? 'Comparte primero una carpeta: el cliente elige las '
                          'fotos DENTRO de ella.'
                    : 'El cliente puede marcar hasta ${widget.photosMax} '
                          '${widget.photosMax == 1 ? 'foto' : 'fotos'} de la '
                          'carpeta compartida.',
                value: _pickPhotos && _canPickPhotos,
                enabled: _canPickPhotos,
                onChanged: (v) => setState(() => _pickPhotos = v),
              ),
              const SizedBox(height: 4),
              _option(
                icon: Icons.folder_open_outlined,
                title: 'Abrir carpeta',
                subtitle: !widget.allowFolder
                    ? 'Este servicio no usa carpeta del Drive.'
                    : _folder.isEmpty
                    ? 'Se verá cuando el servicio tenga una carpeta '
                          'compartida.'
                    : 'Acceso directo a la carpeta compartida del servicio.',
                value: _showFolder && widget.allowFolder && _folder.isNotEmpty,
                enabled: widget.allowFolder && _folder.isNotEmpty,
                onChanged: (v) => setState(() => _showFolder = v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Interruptor de una opción del cliente: icono, título y para qué sirve.
  Widget _option({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: enabled ? onChanged : null,
      secondary: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: (value ? AppColors.brand : scheme.onSurfaceVariant).withValues(
            alpha: .12,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 18,
          color: value ? AppColors.brand : scheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 11,
          height: 1.3,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// Sin carpeta elegida: una tarjeta que ABRE el selector (antes era un
  /// botón suelto con el texto cambiando de "Elegir carpeta").
  Widget _pickTile(ColorScheme scheme) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _pick,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: .25),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: .6),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.brand.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Icons.create_new_folder_outlined,
                size: 20,
                color: AppColors.brand,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Compartir una carpeta del Drive',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Dentro de lo que el cliente ya tiene compartido.',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  /// Con carpeta elegida: la ruta y su botón para DESVINCULARLA del servicio.
  Widget _folderCard(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.brand.withValues(alpha: .24)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.folder_rounded, color: AppColors.brand, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _folder,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Carpeta del Drive compartida con el servicio.',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Tooltip(
            message: 'Desvincular la carpeta del servicio',
            child: TextButton.icon(
              onPressed: () => setState(() {
                _folder = '';
                // Sin carpeta no hay dónde elegir fotos.
                _pickPhotos = false;
                _showFolder = false;
              }),
              style: TextButton.styleFrom(
                foregroundColor: scheme.error,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(Icons.link_off, size: 16),
              label: const Text('Desvincular'),
            ),
          ),
        ],
      ),
    );
  }
}

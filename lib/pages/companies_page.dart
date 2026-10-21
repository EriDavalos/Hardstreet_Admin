import 'package:flutter/material.dart';

import '../drive_base.dart';
import '../drive_scope.dart';
import '../hs_api.dart';
import '../widgets/common.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/drive_folder_picker.dart';
import '../widgets/form_dialog.dart';
import '../widgets/hs_modal.dart';
import '../widgets/hs_toast.dart';

// ==================================================================
// MÓDULO EMPRESAS (solo Superadministrador)
// ==================================================================
// Cada empresa es un estudio independiente: sus agendas, finanzas,
// impresiones, actividad, archivos, archivos compartidos, paquetes,
// servicios, roles, usuarios, clientes y sitio web son SOLO suyos.
//
// Aquí el Superadministrador:
//   * crea una empresa (nombre + carpeta raíz dentro del Drive),
//   * ve sus administradores y cuántos usuarios/clientes tiene,
//   * le asigna/corrige la carpeta raíz,
//   * entra a trabajar CON esa empresa (el resto del panel se filtra),
//   * la desactiva sin borrar sus datos.
//
// Backend: /api/admin/companies (solo el rol Superadmin).
// ==================================================================

class CompaniesPage extends StatefulWidget {
  const CompaniesPage({super.key, this.onCompanyChanged});

  /// La empresa activa del Superadministrador cambió: el panel tiene que
  /// volver a montar el módulo para pedir los datos de la nueva empresa.
  final VoidCallback? onCompanyChanged;

  @override
  State<CompaniesPage> createState() => _CompaniesPageState();
}

class _CompaniesPageState extends State<CompaniesPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _companies = const [];

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
      final list = await HsApi.companies();
      if (!mounted) return;
      setState(() {
        _companies = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  /// Abre el alta o la edición de una empresa. Devuelve true si guardó.
  Future<void> _openForm([Map<String, dynamic>? company]) async {
    final editingId = (company?['id'] as num?)?.toInt() ?? 0;
    // Carpetas que ya usa OTRA empresa: el selector las muestra bloqueadas
    // (el backend también las rechaza, aquí se avisa antes de guardar).
    final taken = <({String path, String name})>[
      for (final c in _companies)
        if ((c['id'] as num?)?.toInt() != editingId &&
            (c['folderPath'] ?? '').toString().trim().isNotEmpty)
          (
            path: (c['folderPath'] ?? '').toString().trim(),
            name: (c['name'] ?? 'otra empresa').toString(),
          ),
    ];
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CompanyFormDialog(company: company, taken: taken),
    );
    if (saved == true) _reload();
  }

  /// Trabaja CON esta empresa: el resto del panel pide solo sus datos.
  void _workHere(Map<String, dynamic> company) {
    final id = (company['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) return;
    HsApi.setActiveCompany(id);
    HsToast.success(
      'Ahora trabajas en ${company['name'] ?? 'la empresa'}',
      // OJO: no prometer que el Drive cambia de carpeta. El Superadmin ve la
      // RAÍZ del Drive (con la carpeta de cada empresa dentro); quien entra
      // con un usuario de la empresa sí queda encerrado en SU carpeta.
      details: 'Agendas, finanzas y demás módulos muestran solo sus datos.',
    );
    widget.onCompanyChanged?.call();
  }

  Future<void> _toggleActive(Map<String, dynamic> company) async {
    final id = (company['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) return;
    final active = company['active'] != false;
    if (active) {
      final ok = await confirmDelete(
        context,
        title: 'Desactivar "${company['name'] ?? 'la empresa'}"',
        message:
            'Sus datos NO se borran: deja de aparecer para trabajar y sus '
            'usuarios no podrán entrar hasta reactivarla.',
        confirmLabel: 'Desactivar',
      );
      if (ok != true) return;
    }
    try {
      await HsApi.updateCompany(id: id, active: !active);
    } catch (_) {
      // El backend ya avisó con la notificación roja.
      return;
    }
    if (!mounted) return;
    if (active && HsSession.activeCompanyId == id) {
      // Se desactivó la empresa con la que estaba trabajando: vuelve a la
      // principal (Hardstreet) para no quedarse sin contexto.
      HsApi.setActiveCompany(1);
      widget.onCompanyChanged?.call();
    }
    _reload();
  }

  int get _activeCount => _companies.where((c) => c['active'] != false).length;
  int get _userCount => _companies.fold<int>(
    0,
    (sum, c) => sum + ((c['users'] as num?)?.toInt() ?? 0),
  );
  int get _clientCount => _companies.fold<int>(
    0,
    (sum, c) => sum + ((c['clients'] as num?)?.toInt() ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeId = HsSession.activeCompanyId;

    return PageContainer(
      module: 'companies',
      title: 'Empresas',
      description:
          'Estudios del sistema. Cada uno tiene sus propios usuarios, clientes, '
          'agendas, finanzas, archivos y sitio, y su carpeta raíz en el Drive.',
      icon: Icons.apartment_outlined,
      onRefresh: _reload,
      stats: [
        StatPill(
          icon: Icons.apartment_outlined,
          label: '$_activeCount empresas',
        ),
        StatPill(icon: Icons.group_outlined, label: '$_userCount usuarios'),
        StatPill(icon: Icons.handshake_outlined, label: '$_clientCount clientes'),
      ],
      actions: [
        HsActionButton(
          onPressed: () => _openForm(),
          icon: Icons.add_business_outlined,
          label: 'Nueva empresa',
        ),
      ],
      child: _body(scheme, activeId),
    );
  }

  Widget _body(ColorScheme scheme, int? activeId) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(Icons.cloud_off_rounded, size: 40, color: scheme.error),
            const SizedBox(height: 12),
            Text(
              'No se pudieron cargar las empresas',
              style: TextStyle(fontWeight: FontWeight.w700, color: scheme.error),
            ),
            const SizedBox(height: 4),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }
    if (_companies.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 44),
        child: Column(
          children: [
            Icon(Icons.apartment_outlined,
                size: 42, color: scheme.onSurfaceVariant),
            const SizedBox(height: 10),
            const Text(
              'Todavía no hay empresas',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Crea la primera: tendrá su carpeta raíz en el Drive y sus '
              'propios usuarios, clientes y paquetes.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Nueva empresa'),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Tarjetas anchas en escritorio, una sola columna en el teléfono.
        final columns = constraints.maxWidth >= 1180
            ? 3
            : constraints.maxWidth >= 760
            ? 2
            : 1;
        final gap = 14.0;
        final width =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final c in _companies)
              SizedBox(
                width: width,
                child: _CompanyCard(
                  company: c,
                  isWorking: activeId == (c['id'] as num?)?.toInt(),
                  onEdit: () => _openForm(c),
                  onWork: () => _workHere(c),
                  onToggleActive: () => _toggleActive(c),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Tarjeta de una empresa: carpeta, administradores y conteos.
class _CompanyCard extends StatelessWidget {
  const _CompanyCard({
    required this.company,
    required this.isWorking,
    required this.onEdit,
    required this.onWork,
    required this.onToggleActive,
  });

  final Map<String, dynamic> company;
  final bool isWorking;
  final VoidCallback onEdit;
  final VoidCallback onWork;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = (company['name'] ?? '').toString().trim();
    final folder = (company['folderPath'] ?? '').toString().trim();
    final active = company['active'] != false;
    final admins = ((company['admins'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    final users = (company['users'] as num?)?.toInt() ?? 0;
    final clients = (company['clients'] as num?)?.toInt() ?? 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isWorking
              ? scheme.primary.withValues(alpha: .55)
              : scheme.outlineVariant.withValues(alpha: .6),
          width: isWorking ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.apartment_rounded,
                    size: 19, color: scheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Empresa' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    Text(
                      active ? 'Activa' : 'Inactiva',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: active ? scheme.primary : scheme.error,
                      ),
                    ),
                  ],
                ),
              ),
              if (isWorking)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Trabajando aquí',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.folder_outlined,
                  size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  folder.isEmpty ? 'Drive (raíz)' : 'Drive /$folder',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (admins.isEmpty)
            Text(
              'Sin administrador asignado',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            )
          else ...[
            Text(
              admins.length == 1 ? 'Administrador' : 'Administradores',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .4,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            for (final a in admins.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    Icon(Icons.person_outline,
                        size: 14, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        (a['name'] ?? '').toString().isEmpty
                            ? (a['email'] ?? '').toString()
                            : '${a['name']} · ${a['email']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            if (admins.length > 3)
              Text(
                '+${admins.length - 3} más',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _pill(context, '$users usuarios'),
              _pill(context, '$clients clientes'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (active)
                TextButton.icon(
                  onPressed: onWork,
                  icon: const Icon(Icons.login_rounded, size: 16),
                  label: Text(isWorking ? 'En uso' : 'Trabajar aquí'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              const Spacer(),
              IconButton(
                tooltip: 'Editar',
                visualDensity: VisualDensity.compact,
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              IconButton(
                tooltip: active ? 'Desactivar' : 'Reactivar',
                visualDensity: VisualDensity.compact,
                onPressed: onToggleActive,
                icon: Icon(
                  active
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                  size: 18,
                  color: active ? null : scheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, String text) {
    final scheme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.colorScheme.surface.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          color: scheme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Alta/edición de una empresa: nombre y carpeta raíz dentro del Drive.
class _CompanyFormDialog extends StatefulWidget {
  const _CompanyFormDialog({this.company, this.taken = const []});

  final Map<String, dynamic>? company;

  /// Carpetas del Drive que ya son de OTRA empresa (van bloqueadas).
  final List<({String path, String name})> taken;

  @override
  State<_CompanyFormDialog> createState() => _CompanyFormDialogState();
}

class _CompanyFormDialogState extends State<_CompanyFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _folder;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.company != null;

  @override
  void initState() {
    super.initState();
    final c = widget.company ?? const <String, dynamic>{};
    _name = TextEditingController(text: (c['name'] ?? '').toString());
    _folder = TextEditingController(
      text: (c['folderPath'] ?? '').toString(),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _folder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Ponle un nombre a la empresa');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final folder = _folder.text.trim();
      if (_editing) {
        await HsApi.updateCompany(
          id: (widget.company!['id'] as num).toInt(),
          name: name,
          folderPath: folder,
        );
      } else {
        await HsApi.createCompany(name: name, folderPath: folder);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  /// Elige la carpeta raíz NAVEGANDO el Drive del servidor.
  ///
  /// Antes había que escribir el nombre de la carpeta a mano (y si no existía,
  /// la empresa quedaba apuntando a una carpeta vacía). Ahora se elige la que
  /// ya existe: el Superadmin ve la raíz del Drive.
  Future<void> _pickFolder() async {
    final drive = DriveScope.maybeOf(context);
    if (drive == null) {
      setState(() => _error = 'El Drive no está disponible en esta pantalla');
      return;
    }
    // Siempre desde la RAÍZ: la carpeta guardada puede no existir (o ser de
    // otra empresa) y abrir el selector dentro de una carpeta inexistente
    // dejaba al usuario sin forma de navegar.
    final picked = await showHsModal<List<String>>(
      context: context,
      builder: (_) => DriveFolderPicker(
        base: '',
        initial: const <String>[],
        load: drive.listChildFolders,
        // La carpeta de otra empresa (o una que la contenga) no se puede
        // elegir: se verían los archivos entre empresas.
        conflict: (path) {
          for (final t in widget.taken) {
            if (drivePathsOverlap(path, t.path)) return t.name;
          }
          return null;
        },
        title: 'Carpeta raíz de la empresa',
        subtitle:
            'Elige en el Drive la carpeta que será la raíz de esta empresa. '
            'Nadie de la empresa verá nada fuera de ella.',
        confirmLabel: 'Usar esta carpeta',
        emptyHint:
            'Esta carpeta no tiene subcarpetas.\nPuedes usarla tal cual con el '
            'botón de abajo.',
      ),
    );
    if (picked == null) return;
    setState(() => _folder.text = picked.join('/'));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FormDialog(
      icon: Icons.apartment_outlined,
      title: _editing ? 'Editar empresa' : 'Nueva empresa',
      subtitle: _editing
          ? 'Nombre y carpeta raíz de la empresa.'
          : 'La empresa nace con sus propios roles base y su carpeta raíz.',
      saveLabel: _editing ? 'Guardar cambios' : 'Crear empresa',
      saving: _saving,
      error: _error,
      onCancel: () => Navigator.of(context).pop(false),
      onSave: _save,
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nombre de la empresa',
            hintText: 'Estudio Aurora',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _folder,
          decoration: InputDecoration(
            labelText: 'Carpeta raíz en el Drive',
            hintText: 'aurora',
            helperText:
                'Relativa a la raíz del Drive. Vacía = una carpeta con el '
                'nombre de la empresa.',
            helperMaxLines: 3,
            prefixIcon: const Icon(Icons.folder_outlined),
            suffixIcon: IconButton(
              key: const ValueKey('company-folder-pick'),
              tooltip: 'Elegir carpeta del Drive',
              onPressed: _saving ? null : _pickFolder,
              icon: const Icon(Icons.folder_open_outlined),
            ),
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _saving ? null : _pickFolder,
          icon: const Icon(Icons.folder_open_outlined, size: 18),
          label: const Text('Seleccionar carpeta del Drive'),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Nadie de esta empresa verá nada fuera de su carpeta: los '
                  'archivos de arriba solo los ve el Superadministrador.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

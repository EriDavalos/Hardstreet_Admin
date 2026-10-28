import 'package:flutter/material.dart';

import '../drive_base.dart' show drivePathNormalize, sameDrivePath;
import '../drive_scope.dart';
import '../hs_api.dart';
import '../theme.dart';
import 'confirm_dialog.dart';
import 'drive_folder_picker.dart';
import 'hs_modal.dart';

/// Carpetas del Drive de UN usuario: se le pueden compartir VARIAS.
///
/// Son su Drive personal: ahí están las compartidas directamente con él y las
/// de sus paquetes (cada paquete comparte UNA y se copia a su usuario). Las que
/// vienen de un paquete se muestran con su nombre.
///
/// Vive aquí (y no en una página) porque se abre desde dos módulos: Usuarios y
/// Clientes. Un cliente es un usuario de tipo cliente, así que se le administra
/// igual desde cualquiera de los dos.
class UserDriveDialog extends StatefulWidget {
  const UserDriveDialog({
    super.key,
    required this.userId,
    required this.userName,
  });

  final int userId;
  final String userName;

  @override
  State<UserDriveDialog> createState() => _UserDriveDialogState();
}

class _UserDriveDialogState extends State<UserDriveDialog> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<({String path, String packageName})> _paths = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final paths = await HsApi.userDriveFolders(widget.userId);
      if (!mounted) return;
      setState(() {
        _paths = paths;
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
        _error = 'No se pudieron cargar las carpetas del usuario';
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    if (_busy) return;
    final drive = DriveScope.maybeOf(context);
    if (drive == null) {
      setState(() => _error = 'El Drive no está disponible en esta pantalla');
      return;
    }
    final segments = await showHsModal<List<String>>(
      context: context,
      builder: (_) => DriveFolderPicker(
        base: '',
        initial: const <String>[],
        load: drive.listChildFolders,
        // Solo se bloquea la MISMA carpeta: el cliente la vería dos veces. Una
        // subcarpeta de otra ya compartida es otra carpeta y se permite.
        conflict: (path) {
          final clean = drivePathNormalize(path);
          for (final other in _paths) {
            if (sameDrivePath(clean, other.path)) return other.path;
          }
          return null;
        },
      ),
    );
    if (segments == null || segments.isEmpty) return;
    final path = segments.join('/');
    setState(() => _busy = true);
    try {
      await HsApi.addUserDriveFolder(userId: widget.userId, path: path);
      await _load();
    } catch (_) {
      // La capa de API ya avisó del error.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(({String path, String packageName}) folder) async {
    if (_busy) return;
    final who = widget.userName.isEmpty ? 'este usuario' : widget.userName;
    final ok = await confirmDelete(
      context,
      title: '¿Dejar de compartir la carpeta?',
      message: folder.packageName.isEmpty
          ? '«${folder.path}» dejará de verse en el Drive de $who.'
          : '«${folder.path}» es la carpeta del paquete '
              '«${folder.packageName}»: se le quitará a $who y ese paquete '
              'quedará sin carpeta del Drive.',
      confirmLabel: 'Quitar',
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await HsApi.removeUserDriveFolder(
        userId: widget.userId,
        path: folder.path,
      );
      await _load();
    } catch (_) {
      // idem.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // En el celular el modal ocupa TODA la pantalla: `showHsModal` ya le quita
    // los márgenes y las esquinas, así que aquí NO se impone el redondeo (se
    // veían bordes curvos que no cabían con la pantalla). Lleva ✕ arriba y el
    // botón de compartir abajo, y la lista se queda con el espacio del medio.
    if (hsIsPhone(context)) return _phoneShell(scheme);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      title: _header(scheme),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_loading && _error == null && _paths.isNotEmpty)
                _summary(scheme),
              _body(scheme),
              const SizedBox(height: 14),
              _shareButton(false),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  /// Vista de TELÉFONO: pantalla completa (sin esquinas redondeadas), ✕ en la
  /// esquina superior derecha y el botón de compartir fijo abajo.
  Widget _phoneShell(ColorScheme scheme) {
    return AlertDialog(
      shape: const RoundedRectangleBorder(),
      titlePadding: const EdgeInsets.fromLTRB(18, 16, 8, 0),
      contentPadding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      title: _header(scheme, onClose: () => Navigator.of(context).pop()),
      content: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_loading && _error == null && _paths.isNotEmpty)
            _summary(scheme),
          Expanded(child: SingleChildScrollView(child: _body(scheme))),
          const SizedBox(height: 12),
          _shareButton(true),
          const SizedBox(height: 16),
        ],
      ),
      // Cierra la ✕ de la cabecera: sin botón suelto a media pantalla.
      actions: const <Widget>[],
    );
  }

  /// La lista de carpetas (o el estado de carga, de error o vacío).
  Widget _body(ColorScheme scheme) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    if (_error != null) return _errorCard(scheme);
    if (_paths.isEmpty) return _emptyState(scheme);
    return ListView.separated(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _paths.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, i) => _folderRow(scheme, _paths[i]),
    );
  }

  /// Cabecera: icono con degradado + título y a quién pertenece el Drive.
  /// En el celular añade la ✕ para cerrar ([onClose]).
  Widget _header(ColorScheme scheme, {VoidCallback? onClose}) {
    final who = widget.userName.trim();
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
            Icons.folder_shared_outlined,
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
                'Carpetas del Drive',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              Text(
                who.isEmpty
                    ? 'Lo que esta cuenta ve en su Drive'
                    : 'Lo que $who ve en su Drive',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.25,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (onClose != null)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: IconButton(
              tooltip: 'Cerrar',
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
          ),
      ],
    );
  }

  /// Cuántas carpetas ve y cuántas vienen de un paquete (chips).
  Widget _summary(ColorScheme scheme) {
    final total = _paths.length;
    final fromPackages = _paths.where((f) => f.packageName.isNotEmpty).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _chip(
            scheme,
            icon: Icons.folder_outlined,
            label: total == 1 ? '1 carpeta' : '$total carpetas',
          ),
          if (fromPackages > 0)
            _chip(
              scheme,
              icon: Icons.inventory_2_outlined,
              label: fromPackages == 1
                  ? '1 viene de un paquete'
                  : '$fromPackages vienen de paquetes',
            ),
        ],
      ),
    );
  }

  Widget _chip(
    ColorScheme scheme, {
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.brand),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppColors.brand,
            ),
          ),
        ],
      ),
    );
  }

  /// Una carpeta compartida: tarjeta con su ruta, de dónde viene y el botón
  /// para dejar de compartirla.
  Widget _folderRow(
    ColorScheme scheme,
    ({String path, String packageName}) folder,
  ) {
    final fromPackage = folder.packageName.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .32),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              Icons.folder_rounded,
              size: 18,
              color: AppColors.brand,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  folder.path,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      fromPackage
                          ? Icons.inventory_2_outlined
                          : Icons.person_outline,
                      size: 11,
                      color: fromPackage
                          ? AppColors.brand
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        fromPackage
                            ? 'Carpeta del paquete ${folder.packageName}'
                            : 'Compartida directamente',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: fromPackage
                              ? AppColors.brand
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dejar de compartir esta carpeta',
            visualDensity: VisualDensity.compact,
            onPressed: _busy ? null : () => _remove(folder),
            icon: Icon(Icons.link_off_rounded, size: 18, color: scheme.error),
          ),
        ],
      ),
    );
  }

  /// Todavía no tiene ninguna carpeta.
  Widget _emptyState(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .30),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: .10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.folder_open_outlined,
              size: 26,
              color: AppColors.brand,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Sin carpetas todavía',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Este usuario todavía no tiene ninguna carpeta compartida.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// No se pudo cargar la lista.
  Widget _errorCard(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error.withValues(alpha: .35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 16, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
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

  /// Acción principal. En el celular ocupa todo el ancho.
  Widget _shareButton(bool phone) {
    final button = FilledButton.icon(
      onPressed: _busy ? null : _add,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.create_new_folder_outlined, size: 18),
      label: Text(
        _paths.isEmpty
            ? 'Compartir una carpeta del Drive'
            : 'Compartir otra carpeta',
      ),
    );
    return phone
        ? SizedBox(width: double.infinity, child: button)
        : Align(alignment: Alignment.centerLeft, child: button);
  }
}

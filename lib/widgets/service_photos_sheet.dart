import 'package:flutter/material.dart';

import '../drive_base.dart';
import '../hs_api.dart';
import '../theme.dart';
import 'drive_photo_picker.dart';
import 'drive_photo_viewer.dart';
import 'drive_thumb.dart';
import 'hs_modal.dart';
import 'hs_toast.dart';

// ==================================================================
// MIS FOTOS DE UN SERVICIO (cliente)
// ==================================================================
// El cliente ve y administra la selección de UN servicio:
//
//   * rejilla de las fotos ya elegidas (miniatura + nombre), con «Quitar»;
//   * «Elegir fotos» abre el selector DENTRO de la carpeta compartida del
//     servicio (no ve el resto del Drive) y con el máximo configurado;
//   * el visor tiene zoom y pantalla completa (mismo del Drive);
//   * «Guardar selección» reemplaza la lista en el servidor.
//
// En celular el modal ocupa TODA la pantalla; en escritorio es amplio (940 px)
// pero deja ver la app detrás.
// ==================================================================

/// Abre el módulo y devuelve la selección guardada (null si se canceló).
Future<List<String>?> showServicePhotosSheet(
  BuildContext context, {
  required DriveBase drive,
  required int serviceId,
  required String serviceName,
  required String folder,
  required int max,
  required List<String> initial,
  bool readOnly = false,
}) {
  return showHsModal<List<String>>(
    context: context,
    builder: (_) => ServicePhotosSheet(
      drive: drive,
      serviceId: serviceId,
      serviceName: serviceName,
      folder: folder,
      max: max,
      initial: initial,
      readOnly: readOnly,
    ),
  );
}

class ServicePhotosSheet extends StatefulWidget {
  const ServicePhotosSheet({
    super.key,
    required this.drive,
    required this.serviceId,
    required this.serviceName,
    required this.folder,
    required this.max,
    required this.initial,
    this.readOnly = false,
  });

  final DriveBase drive;
  final int serviceId;
  final String serviceName;
  final String folder;
  final int max;
  final List<String> initial;

  /// Enviado a impresión: se pueden VER las fotos pero no cambiarlas.
  final bool readOnly;

  @override
  State<ServicePhotosSheet> createState() => _ServicePhotosSheetState();
}

class _ServicePhotosSheetState extends State<ServicePhotosSheet> {
  late List<String> _paths = List<String>.of(widget.initial);
  bool _saving = false;

  bool get _changed {
    if (_paths.length != widget.initial.length) return true;
    for (var i = 0; i < _paths.length; i++) {
      if (_paths[i] != widget.initial[i]) return true;
    }
    return false;
  }

  List<String> get _folderSegments => widget.folder
      .split('/')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  String _name(String path) {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? path : parts.last;
  }

  String _src(String path, {int width = 480}) {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    final parent = parts.length > 1
        ? parts.sublist(0, parts.length - 1)
        : _folderSegments;
    final item = DriveItem(name: parts.last, isFolder: false);
    return widget.drive.thumbSourceIn(parent, item, width: width);
  }

  /// La ORIGINAL de una foto ya elegida (misma carpeta que [_src]).
  String _original(String path) {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    final parent = parts.length > 1
        ? parts.sublist(0, parts.length - 1)
        : _folderSegments;
    final item = DriveItem(name: parts.last, isFolder: false);
    return widget.drive.fullSourceIn(parent, item);
  }

  Future<void> _add() async {
    final picked = await showDrivePhotoPicker(
      context,
      drive: widget.drive,
      title: 'Elegir fotos · ${widget.serviceName}',
      subtitle: widget.max > 0
          ? 'Solo verás la carpeta compartida de este servicio. Puedes '
                'elegir hasta ${widget.max} '
                '${widget.max == 1 ? 'foto' : 'fotos'}.'
          : 'Solo verás la carpeta compartida de este servicio.',
      initialPicked: _paths,
      // La selección se hace DENTRO de la carpeta compartida del servicio.
      rootPath: _folderSegments,
      maxSelection: widget.max > 0 ? widget.max : null,
      minSelection: 0,
      allowDownload: false,
      confirmLabel: 'Agregar',
    );
    if (picked == null) return;
    setState(() => _paths = picked);
  }

  void _remove(String path) =>
      setState(() => _paths = [..._paths]..remove(path));

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final saved = await HsApi.setMyServiceItems(widget.serviceId, _paths);
      if (!mounted) return;
      HsToast.success(
        _paths.isEmpty ? 'Selección borrada' : 'Selección guardada',
        details: _paths.isEmpty
            ? null
            : widget.max > 0
            ? '${_paths.length} de ${widget.max} '
                  '${_paths.length == 1 ? 'foto' : 'fotos'}'
            : '${_paths.length} '
                  '${_paths.length == 1 ? 'foto elegida' : 'fotos elegidas'}',
      );
      Navigator.of(context).pop(saved);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = hsIsPhone(context);
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: phone ? EdgeInsets.zero : const EdgeInsets.all(22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(phone ? 0 : 20),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: phone
            ? BoxConstraints.tight(size)
            : BoxConstraints(
                maxWidth: 940,
                maxHeight: (size.height * .88).clamp(380.0, 920.0),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(scheme),
            const Divider(height: 1),
            Expanded(child: _paths.isEmpty ? _empty(scheme) : _grid(scheme)),
            _footer(scheme),
          ],
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    final done = _paths.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
      child: Row(
        children: [
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
              Icons.photo_library_outlined,
              color: Colors.white,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mis fotos · ${widget.serviceName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.readOnly
                      ? 'Estas fotos ya se enviaron a impresión. Solo puedes '
                            'verlas; si necesitas cambiarlas, pídele al estudio '
                            'que reabra el envío.'
                      : widget.max > 0
                      ? 'Elige hasta ${widget.max} '
                            '${widget.max == 1 ? 'foto' : 'fotos'}.'
                      : 'Elige las fotos que quieras.',
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.25,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: scheme.primary.withValues(alpha: .35)),
            ),
            child: Text(
              widget.max > 0
                  ? '$done de ${widget.max}'
                  : done == 1
                  ? '1 elegida'
                  : '$done elegidas',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _empty(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.brand.withValues(alpha: .10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add_photo_alternate_outlined,
                size: 34,
                color: AppColors.brand,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Todavía no has elegido fotos',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Toca «Elegir fotos» y marca las que quieras de la carpeta '
              'compartida de este servicio.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (!widget.readOnly) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const ValueKey('service-photos-add-empty'),
                onPressed: _add,
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Elegir fotos'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _grid(ColorScheme scheme) {
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisExtent: 176,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _paths.length,
      itemBuilder: (context, i) {
        final path = _paths[i];
        final src = _src(path);
        return Material(
          color: scheme.surfaceContainerHighest.withValues(alpha: .25),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: .5),
            ),
          ),
          child: InkWell(
            onTap: () => showDrivePhotoViewer(
              context,
              name: _name(path),
              meta: path,
              src: _src(path, width: 2200),
              originalSrc: _original(path),
              isRemote: _src(path).startsWith('http'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DriveThumb(
                        source: src,
                        isRemote: src.startsWith('http'),
                        big: true,
                      ),
                      if (!widget.readOnly)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: IconButton(
                            tooltip: 'Quitar de mi selección',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _remove(path),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black.withValues(
                                alpha: .42,
                              ),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(4),
                              minimumSize: const Size(30, 30),
                            ),
                            icon: const Icon(Icons.close_rounded, size: 17),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: Text(
                    _name(path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _footer(ColorScheme scheme) {
    if (widget.readOnly) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5)),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.warn),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Enviadas · ${_paths.length} '
                '${_paths.length == 1 ? 'foto' : 'fotos'}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    }
    final compact = MediaQuery.sizeOf(context).width < 620;
    final addEnabled = !(widget.max > 0 && _paths.length >= widget.max);
    final add = addEnabled ? () => _add() : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5)),
        ),
      ),
      // En CELULAR los tres botones van en UNA fila (el Wrap los partía en
      // varias líneas y quedaban desalineados). En escritorio se conserva el
      // Wrap con los textos completos.
      child: compact
          ? Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('service-photos-add'),
                    onPressed: add,
                    // «Añadir» (no «Agregar») para no confundirse con el
                    // botón «Agregar» del selector de fotos que abre encima.
                    child: Text(_paths.isEmpty ? 'Elegir' : 'Añadir'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('service-photos-save'),
                    onPressed: _saving || !_changed ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Guardar'),
                  ),
                ),
              ],
            )
          : Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                FilledButton.icon(
                  key: const ValueKey('service-photos-add'),
                  onPressed: add,
                  icon: const Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 18,
                  ),
                  label: Text(
                    _paths.isEmpty ? 'Elegir fotos' : 'Agregar fotos',
                  ),
                ),
                if (widget.max > 0 && _paths.length >= widget.max)
                  Text(
                    'Llegaste al máximo',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  key: const ValueKey('service-photos-save'),
                  onPressed: _saving || !_changed ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Guardar selección'),
                ),
              ],
            ),
    );
  }
}

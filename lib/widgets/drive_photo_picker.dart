import 'package:flutter/material.dart';

import '../drive_api_service.dart';
import '../drive_base.dart';
import '../drive_downloader.dart';
import '../hs_format.dart';
import '../theme.dart';
import 'drive_thumb.dart';
import 'hs_modal.dart';
import 'hs_toast.dart';

// ==================================================================
// SELECTOR DE FOTOS DEL DRIVE (el único de la app)
// ==================================================================
// Lo usan el Sitio web (portadas), el formulario de un PAQUETE (su foto) y el
// cliente («Mis fotos» de un servicio). Antes cada módulo tenía su propia
// lista y dos de ellos no mostraban las fotos ni las podían bajar: aquí hay
// UNA rejilla con el diseño del Drive —miniatura (`DriveThumb`), nombre sobre
// un degradado, carpetas en tarjeta, migas de pan, contador de lo elegido y
// descarga de la selección—, así que se ve igual en todas partes.
//
// Devuelve las rutas ABSOLUTAS de lo elegido (dentro del Drive) o null si se
// canceló: quien lo abre decide qué hace con ellas (una URL pública, guardar
// la selección del servicio…). Nada se mueve ni se copia de carpeta.
// ==================================================================

/// Abre el selector de fotos del Drive. Ver el comentario del archivo.
Future<List<String>?> showDrivePhotoPicker(
  BuildContext context, {
  required DriveBase drive,
  String title = 'Fotos del Drive',
  String? subtitle,
  List<String> initialPath = const <String>[],
  Iterable<String> initialPicked = const <String>[],
  String confirmLabel = 'Usar estas fotos',
  String? note,
  bool allowDownload = true,
}) =>
    showHsModal<List<String>>(
      context: context,
      builder: (_) => DrivePhotoPicker(
        drive: drive,
        title: title,
        subtitle: subtitle,
        initialPath: initialPath,
        initialPicked: initialPicked,
        confirmLabel: confirmLabel,
        note: note,
        allowDownload: allowDownload,
      ),
    );

class DrivePhotoPicker extends StatefulWidget {
  const DrivePhotoPicker({
    super.key,
    required this.drive,
    this.title = 'Fotos del Drive',
    this.subtitle,
    this.initialPath = const <String>[],
    this.initialPicked = const <String>[],
    this.confirmLabel = 'Usar estas fotos',
    this.note,
    this.allowDownload = true,
  });

  final DriveBase drive;
  final String title;
  final String? subtitle;

  /// Carpeta donde se abre (segmentos, vacío = la raíz del Drive).
  final List<String> initialPath;

  /// Rutas ABSOLUTAS ya marcadas (la selección guardada).
  final Iterable<String> initialPicked;

  final String confirmLabel;
  final String? note;
  final bool allowDownload;

  @override
  State<DrivePhotoPicker> createState() => _DrivePhotoPickerState();
}

class _DrivePhotoPickerState extends State<DrivePhotoPicker> {
  late List<String> _path = List<String>.of(widget.initialPath);
  List<DriveItem> _items = const [];

  /// Rutas ABSOLUTAS marcadas (se conservan al navegar entre carpetas).
  late final Set<String> _picked = {
    for (final p in widget.initialPicked)
      if (drivePathNormalize(p).isNotEmpty) drivePathNormalize(p),
  };

  /// Fotos ya vistas en esta sesión, por ruta absoluta, y de qué carpeta
  /// salieron: es lo que se puede descargar (para bajar un archivo hay que
  /// saber dónde está).
  final Map<String, DriveItem> _seen = {};
  final Map<String, List<String>> _where = {};

  bool _loading = true;
  String? _error;

  DriveBase get _drive => widget.drive;

  bool get _remote => _drive is DriveApiService;

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
      final items = await _drive.listFolderItems(_path);
      if (!mounted) return;
      _remember(items);
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _error = 'No se pudo abrir la carpeta: $e';
        _loading = false;
      });
    }
  }

  /// Apunta de qué carpeta sale cada foto (para poder descargarla después).
  void _remember(List<DriveItem> items) {
    for (final i in items) {
      final abs = _abs(i.name);
      _seen[abs] = i;
      _where[abs] = List<String>.of(_path);
    }
  }

  String _abs(String name) => drivePathNormalize([..._path, name].join('/'));

  void _enter(String name) {
    setState(() => _path = [..._path, name]);
    _load();
  }

  void _up() {
    if (_path.isEmpty) return;
    setState(() => _path = _path.sublist(0, _path.length - 1));
    _load();
  }

  void _toggle(DriveItem item) {
    final abs = _abs(item.name);
    setState(() {
      if (!_picked.remove(abs)) _picked.add(abs);
    });
  }

  /// Lo marcado que se puede descargar, agrupado por carpeta.
  Map<String, List<DriveItem>> get _downloadable {
    final out = <String, List<DriveItem>>{};
    for (final abs in _picked) {
      final item = _seen[abs];
      if (item == null) continue; // no se ha visto: no se sabe dónde está
      final folder = (_where[abs] ?? const <String>[]).join('/');
      out.putIfAbsent(folder, () => <DriveItem>[]).add(item);
    }
    return out;
  }

  /// Baja lo marcado (1 archivo suelto; varios en ZIP), desde SU carpeta.
  Future<void> _download() async {
    final groups = _downloadable;
    if (groups.isEmpty) return;
    var total = 0;
    for (final entry in groups.entries) {
      final folder = entry.key.isEmpty
          ? const <String>[]
          : entry.key.split('/').where((s) => s.isNotEmpty).toList();
      total += entry.value.length;
      await downloadDriveSelection(
        context,
        drive: _drive,
        items: entry.value,
        from: folder,
      );
    }
    if (total > 0) {
      HsToast.info(total == 1 ? 'Descargando 1 foto…' : 'Descargando $total fotos…');
    }
  }

  /// Ve una foto en grande sin cerrar el selector (y la marca desde ahí).
  Future<void> _preview(DriveItem item) async {
    final abs = _abs(item.name);
    await showHsModal<void>(
      context: context,
      builder: (_) => _PhotoPreview(
        name: item.name,
        meta: _metaLabel(item),
        src: _drive.thumbSourceIn(_path, item, width: 1400),
        isRemote: _remote,
        picked: _picked.contains(abs),
        onToggle: () => setState(() {
          if (!_picked.remove(abs)) _picked.add(abs);
        }),
      ),
    );
  }

  /// `1.2 MB · 26/09/2026` (lo que se ve bajo el nombre).
  String _metaLabel(DriveItem item) => [
        if (item.size != null && (item.size ?? 0) > 0) hsBytes(item.size!),
        if (item.modified != null) hsShortDate(item.modified!),
      ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final phone = hsIsPhone(context);
    final folders = [
      for (final i in _items)
        if (i.isFolder) i,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final photos = [
      for (final i in _items)
        if (!i.isFolder && _drive.hasImageExt(i.name)) i,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final count = _picked.length;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titlePadding: const EdgeInsets.fromLTRB(18, 16, 14, 0),
      contentPadding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      actionsPadding: const EdgeInsets.fromLTRB(12, 6, 14, 14),
      title: _header(scheme, count),
      content: SizedBox(
        width: phone ? double.infinity : 820,
        height: phone ? double.infinity : 540,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _crumbBar(scheme),
            if (widget.note != null) ...[
              const SizedBox(height: 8),
              _note(scheme, widget.note!),
            ],
            const SizedBox(height: 10),
            Expanded(child: _body(scheme, folders, photos)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        if (count > 0)
          TextButton(
            onPressed: () => setState(_picked.clear),
            child: const Text('Limpiar'),
          ),
        if (widget.allowDownload && _downloadable.isNotEmpty)
          TextButton.icon(
            onPressed: _download,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Descargar'),
          ),
        FilledButton.icon(
          onPressed: count == 0
              ? null
              : () => Navigator.of(context).pop(_picked.toList()..sort()),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text(widget.confirmLabel),
        ),
      ],
    );
  }

  /// Cabecera: icono degradado, título y lo elegido hasta ahora.
  Widget _header(ColorScheme scheme, int count) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
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
          child: const Icon(Icons.photo_library_outlined,
              color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              Text(
                widget.subtitle ??
                    'Elige las fotos de tu Drive. Nada se mueve de carpeta.',
                maxLines: 2,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.25,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (count > 0)
          Container(
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: scheme.primary.withValues(alpha: .35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 14, color: scheme.primary),
                const SizedBox(width: 5),
                Text(
                  count == 1 ? '1 elegida' : '$count elegidas',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Migas de pan: dónde se está, con el botón de SUBIR a la vista.
  Widget _crumbBar(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.brand.withValues(alpha: .22)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Subir un nivel',
            visualDensity: VisualDensity.compact,
            onPressed: _path.isEmpty ? null : _up,
            icon: const Icon(Icons.arrow_upward_rounded, size: 18),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true, // la carpeta actual (la última) siempre a la vista
              child: Row(
                children: [
                  Icon(Icons.home_outlined, size: 16, color: AppColors.brand),
                  for (var i = 0; i < _path.length; i++) ...[
                    Icon(Icons.chevron_right_rounded,
                        size: 15, color: scheme.onSurfaceVariant),
                    Text(
                      _path[i],
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: i == _path.length - 1
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: i == _path.length - 1
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

  Widget _note(ColorScheme scheme, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 15, color: scheme.primary),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                height: 1.3,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );

  Widget _body(ColorScheme scheme, List<DriveItem> folders, List<DriveItem> photos) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: scheme.error),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }
    if (folders.isEmpty && photos.isEmpty) {
      return Center(
        child: Text(
          'Esta carpeta no tiene fotos.',
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 6),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisExtent: 168,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: folders.length + photos.length,
      itemBuilder: (context, index) => index < folders.length
          ? _folderTile(scheme, folders[index])
          : _photoTile(scheme, photos[index - folders.length]),
    );
  }

  /// Carpeta: la tarjeta lleva dentro el icono, el nombre y sus datos.
  Widget _folderTile(ColorScheme scheme, DriveItem item) => _Tile(
        onTap: () => _enter(item.name),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                alignment: Alignment.center,
                width: double.infinity,
                color: scheme.surfaceContainerHighest.withValues(alpha: .35),
                child: Icon(Icons.folder_rounded,
                    size: 44, color: AppColors.brand.withValues(alpha: .9)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 6, 9, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700, height: 1.2),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 17, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ],
        ),
      );

  /// Foto: la miniatura manda y el nombre va ENCIMA, sobre un degradado.
  Widget _photoTile(ColorScheme scheme, DriveItem item) {
    final abs = _abs(item.name);
    return _Tile(
      key: ValueKey('drive-photo-${item.name}'),
      previewKey: ValueKey('drive-photo-preview-${item.name}'),
      picked: _picked.contains(abs),
      onTap: () => _toggle(item),
      onPreview: () => _preview(item),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DriveThumb(
            source: _drive.thumbSourceIn(_path, item, width: 480),
            isRemote: _remote,
            big: true,
          ),
          // Degradado: el nombre y la fecha se leen sobre cualquier foto.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black54, Colors.black87],
                stops: [.30, .68, 1],
              ),
            ),
          ),
          Positioned(
            left: 9,
            right: 9,
            bottom: 7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_metaLabel(item).isNotEmpty)
                  Text(
                    _metaLabel(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de la rejilla: marco, marca de ELEGIDA y botón para verla.
class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.child,
    this.picked = false,
    this.onTap,
    this.onPreview,
    this.previewKey,
  });

  final Widget child;
  final bool picked;
  final VoidCallback? onTap;
  final VoidCallback? onPreview;

  /// Llave del botón de ver en grande (para las pruebas y por si hay que
  /// llevar el foco a esa foto).
  final Key? previewKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: .25),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: picked
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: .45),
          width: picked ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (picked)
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .35),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.check_rounded,
                      size: 15, color: Colors.white),
                ),
              ),
            if (onPreview != null)
              Positioned(
                top: 2,
                right: 2,
                child: IconButton(
                  key: previewKey,
                  tooltip: 'Ver en grande',
                  visualDensity: VisualDensity.compact,
                  iconSize: 17,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: .35),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(4),
                    minimumSize: const Size(28, 28),
                  ),
                  onPressed: onPreview,
                  icon: const Icon(Icons.zoom_out_map_rounded),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Una foto en grande (para mirarla bien antes de elegirla).
class _PhotoPreview extends StatefulWidget {
  const _PhotoPreview({
    required this.name,
    required this.meta,
    required this.src,
    required this.isRemote,
    required this.picked,
    required this.onToggle,
  });

  final String name;
  final String meta;
  final String src;
  final bool isRemote;
  final bool picked;
  final VoidCallback onToggle;

  @override
  State<_PhotoPreview> createState() => _PhotoPreviewState();
}

class _PhotoPreviewState extends State<_PhotoPreview> {
  late bool _picked = widget.picked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700),
                        ),
                        if (widget.meta.isNotEmpty)
                          Text(
                            widget.meta,
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 11.5),
                          ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    key: const ValueKey('drive-photo-preview-toggle'),
                    onPressed: () => setState(() {
                      _picked = !_picked;
                      widget.onToggle();
                    }),
                    icon: Icon(
                      _picked
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 18,
                    ),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    label: Text(_picked ? 'Quitar' : 'Elegir esta foto'),
                  ),
                  IconButton(
                    key: const ValueKey('drive-photo-preview-close'),
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
            ),
            Expanded(
              child: DriveThumb(
                key: const ValueKey('drive-photo-preview-image'),
                source: widget.src,
                isRemote: widget.isRemote,
                size: double.infinity,
                big: true,
                contain: true,
                rounded: false,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Toca «Elegir esta foto» para marcarla sin cerrar el selector.',
                style: TextStyle(
                    fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: .8)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

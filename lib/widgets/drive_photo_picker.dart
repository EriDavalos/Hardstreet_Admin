import 'package:flutter/material.dart';

import '../drive_api_service.dart';
import '../drive_base.dart';
import '../drive_downloader.dart';
import '../hs_format.dart';
import '../theme.dart';
import 'drive_photo_viewer.dart';
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

  /// Máximo de fotos que se pueden marcar. `null` = sin límite; `1` = una
  /// sola (la tarjeta de un paquete, la portada de una sección…).
  int? maxSelection,

  /// Mínimo para poder confirmar (por defecto, 1).
  int minSelection = 1,

  /// Carpeta RAÍZ que no se puede abandonar (p. ej. la carpeta compartida de
  /// UN servicio). Vacío = todo el Drive. El selector abre dentro de ella y
  /// no deja subir más arriba.
  List<String> rootPath = const <String>[],
}) => showHsModal<List<String>>(
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
    maxSelection: maxSelection,
    minSelection: minSelection,
    rootPath: rootPath,
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
    this.maxSelection,
    this.minSelection = 1,
    this.rootPath = const <String>[],
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

  /// Cuántas fotos se pueden marcar: 1, una cantidad o todas (null).
  final int? maxSelection;

  /// Cuántas hacen falta para confirmar (1 por defecto).
  final int minSelection;

  /// Carpeta raíz que no se puede abandonar (vacío = todo el Drive).
  final List<String> rootPath;

  @override
  State<DrivePhotoPicker> createState() => _DrivePhotoPickerState();
}

class _DrivePhotoPickerState extends State<DrivePhotoPicker> {
  /// Raíz permitida, ya normalizada en segmentos (vacío = raíz del Drive).
  late final List<String> _root = widget.rootPath
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  late List<String> _path = _root.isNotEmpty
      ? List<String>.of(_root)
      : List<String>.of(widget.initialPath);
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
    if (!_canGoUp) return;
    setState(() => _path = _path.sublist(0, _path.length - 1));
    _load();
  }

  /// No se puede salir de la carpeta compartida del servicio.
  bool get _canGoUp => _path.length > _root.length;

  void _toggle(DriveItem item) {
    final abs = _abs(item.name);
    setState(() {
      if (_picked.remove(abs)) return;
      final max = widget.maxSelection;
      if (max != null && max > 0) {
        if (max == 1) {
          // Una sola: marcar otra REEMPLAZA la anterior (como un selector).
          _picked
            ..clear()
            ..add(abs);
          return;
        }
        if (_picked.length >= max) {
          HsToast.info(
            'Máximo $max fotos',
            details: 'Quita una para poder elegir otra.',
          );
          return;
        }
      }
      _picked.add(abs);
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

  /// Baja lo marcado desde SU carpeta: en la computadora un archivo suelto o
  /// un ZIP de la selección; en el celular, una foto por archivo (sin ZIP).
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
      HsToast.info(
        total == 1 ? 'Descargando 1 foto…' : 'Descargando $total fotos…',
      );
    }
  }

  /// Ve una foto en grande (con zoom y pantalla completa) sin cerrar el
  /// selector, y la marca desde ahí.
  Future<void> _preview(DriveItem item) async {
    final abs = _abs(item.name);
    await showDrivePhotoViewer(
      context,
      name: item.name,
      meta: _metaLabel(item),
      src: _drive.thumbSourceIn(_path, item, width: 2200),
      // La original se pide cuando la miniatura ya se ve (ver el visor).
      originalSrc: _remote ? _drive.fullSourceIn(_path, item) : '',
      isRemote: _remote,
      picked: _picked.contains(abs),
      onToggle: () => _toggle(item),
      drive: _drive,
      item: item,
      rel: List<String>.of(_path),
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
    final size = MediaQuery.sizeOf(context);
    final folders = [
      for (final i in _items)
        if (i.isFolder) i,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final photos = [
      for (final i in _items)
        if (!i.isFolder && _drive.hasImageExt(i.name)) i,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final count = _picked.length;
    // ATRÁS (botón del sistema o gesto) NO cierra el selector si se está
    // dentro de una carpeta: sube un nivel, como en el Drive. En la raíz deja
    // que el sistema cierre el modal.
    return PopScope(
      canPop: !_canGoUp,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _up();
      },
      child: AlertDialog(
        // En celular ocupa TODA la pantalla (sin márgenes ni esquinas); en
        // escritorio deja ver el panel detrás.
        insetPadding: phone
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(phone ? 0 : 22),
        ),
        titlePadding: EdgeInsets.fromLTRB(14, phone ? 10 : 16, 12, 0),
        contentPadding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        actionsPadding: const EdgeInsets.fromLTRB(8, 4, 10, 10),
        title: _header(scheme, count),
        content: SizedBox(
          // En escritorio el selector aprovecha casi toda la ventana (antes se
          // quedaba en 820×540 y sobraba espacio).
          width: phone
              ? double.infinity
              : (size.width * .88).clamp(560.0, 1120.0),
          height: phone
              ? double.infinity
              : (size.height * .72).clamp(420.0, 780.0),
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
            onPressed: count < widget.minSelection
                ? null
                : () => Navigator.of(context).pop(_picked.toList()..sort()),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(widget.confirmLabel),
          ),
        ],
      ),
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
            Icons.photo_library_outlined,
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
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                // Texto CORTO, como en «Mis fotos»: el máximo y nada más.
                // Antes añadía "de tu Drive. Nada se mueve de carpeta." y en
                // el celular ocupaba dos líneas de más.
                widget.subtitle ??
                    (widget.maxSelection == 1
                        ? 'Elige 1 foto.'
                        : widget.maxSelection != null
                        ? 'Elige hasta ${widget.maxSelection} fotos.'
                        : 'Elige las fotos.'),
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
                  widget.maxSelection == null
                      ? (count == 1 ? '1 elegida' : '$count elegidas')
                      : (count == 1 && widget.maxSelection == 1
                            ? '1 de 1'
                            : '$count de ${widget.maxSelection}'),
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
            onPressed: _canGoUp ? _up : null,
            icon: const Icon(Icons.arrow_upward_rounded, size: 18),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true, // la carpeta actual (la última) siempre a la vista
              child: Row(
                children: [
                  Icon(
                    _root.isEmpty
                        ? Icons.home_outlined
                        : Icons.folder_shared_outlined,
                    size: 16,
                    color: AppColors.brand,
                  ),
                  if (_root.isNotEmpty) ...[
                    Text(
                      _root[_root.length - 1],
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: _path.length == _root.length
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: _path.length == _root.length
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  for (var i = _root.length; i < _path.length; i++) ...[
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 15,
                      color: scheme.onSurfaceVariant,
                    ),
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

  Widget _body(
    ColorScheme scheme,
    List<DriveItem> folders,
    List<DriveItem> photos,
  ) {
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
            child: Icon(
              Icons.folder_rounded,
              size: 44,
              color: AppColors.brand.withValues(alpha: .9),
            ),
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
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 17,
                color: scheme.onSurfaceVariant,
              ),
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
                  child: const Icon(
                    Icons.check_rounded,
                    size: 15,
                    color: Colors.white,
                  ),
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

import 'package:flutter/material.dart';

import '../drive_base.dart';
import '../drive_scope.dart';
import '../theme.dart';
import 'drive_photo_viewer.dart';
import 'drive_thumb.dart';
import 'hs_modal.dart';

// ==================================================================
// FOTOS ELEGIDAS POR EL CLIENTE PARA UN SERVICIO
// ==================================================================
// El estudio las ve desde el administrador del paquete: rejilla con miniatura,
// nombre y el visor con zoom/pantalla completa. En celular el modal ocupa la
// pantalla; en escritorio es amplio pero deja ver el panel detrás.
//
// Las rutas son las que guarda `purchased_packages_services_items` (dentro de
// la carpeta compartida del servicio). Nada se mueve ni se copia.
// ==================================================================

Future<void> showServiceItemsGallery(
  BuildContext context, {
  required String serviceName,
  required String folder,
  required List<String> paths,
}) {
  return showHsModal<void>(
    context: context,
    builder: (_) => ServiceItemsGallery(
      serviceName: serviceName,
      folder: folder,
      paths: paths,
    ),
  );
}

class ServiceItemsGallery extends StatelessWidget {
  const ServiceItemsGallery({
    super.key,
    required this.serviceName,
    required this.folder,
    required this.paths,
  });

  final String serviceName;
  final String folder;
  final List<String> paths;

  String _name(String p) {
    final parts = p.split('/').where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? p : parts.last;
  }

  @override
  Widget build(BuildContext context) {
    final drive = DriveScope.maybeOf(context);
    final phone = hsIsPhone(context);
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
                maxHeight: (size.height * .88).clamp(380.0, 900.0),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.brand.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.photo_library_outlined,
                      color: AppColors.brand,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fotos elegidas · $serviceName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          paths.isEmpty
                              ? 'El cliente todavía no ha elegido fotos.'
                              : '${paths.length} ${paths.length == 1 ? 'foto elegida' : 'fotos elegidas'}'
                                    '${folder.isEmpty ? '' : ' · $folder'}',
                          maxLines: 2,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: paths.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Cuando el cliente marque sus fotos aparecerán aquí, '
                          'con su vista completa.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(14),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: phone ? 160 : 190,
                        mainAxisExtent: 170,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: paths.length,
                      itemBuilder: (context, i) =>
                          _tile(context, drive, paths[i], i, paths),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Une una ruta del paquete con lo que el visor necesita (nombre, carpeta
  /// y fuente), igual que lo usa la aparte de la miniatura.
  DrivePhotoEntry _entryOf(DriveBase? drive, String path) {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    final name = parts.isEmpty ? path : parts.last;
    final parent = parts.length > 1
        ? parts.sublist(0, parts.length - 1)
        : const <String>[];
    final item = DriveItem(name: name, isFolder: false);
    final src = drive == null
        ? ''
        : drive.thumbSourceIn(parent, item, width: 2200);
    return DrivePhotoEntry(
      name: name,
      meta: path,
      src: src,
      isRemote: src.startsWith('http'),
      drive: drive,
      item: item,
      rel: parent,
    );
  }

  Widget _tile(
    BuildContext context,
    DriveBase? drive,
    String path,
    int index,
    List<String> paths,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final name = _name(path);
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    final parent = parts.length > 1
        ? parts.sublist(0, parts.length - 1)
        : const <String>[];
    final item = DriveItem(name: name, isFolder: false);
    final src = drive == null
        ? ''
        : drive.thumbSourceIn(parent, item, width: 480);
    final remote = src.startsWith('http');
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: .25),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
      child: InkWell(
        onTap: src.isEmpty
            ? null
            : () => showDrivePhotoViewer(
                context,
                name: name,
                meta: path,
                src: drive!.thumbSourceIn(parent, item, width: 2200),
                isRemote: remote,
                // GALERÍA: la lista entera del paquete y la foto tocada, así
                // se desliza (celular) o se da click en ‹ › (laptop) para
                // cambiar de foto, igual que en el visor del Drive.
                gallery: [
                  for (final p in paths) _entryOf(drive, p),
                ],
                initialIndex: index,
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: src.isEmpty
                  ? Center(
                      child: Icon(
                        Icons.image_outlined,
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  : DriveThumb(source: src, isRemote: remote, big: true),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Text(
                name,
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
  }
}

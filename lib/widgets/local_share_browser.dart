import 'package:flutter/material.dart';

import '../local_share_service.dart';
import '../widgets/drive_thumb.dart';
import '../widgets/hs_modal.dart';
import '../widgets/hs_toast.dart';

// ==================================================================
// HARD STREET ADMIN - Navegador de una carpeta LOCAL compartida
// ==================================================================
// Ves y descargas lo que alguien comparte desde SU computadora. Es de SOLO
// LECTURA: no hay botones de subir, renombrar ni borrar (el servidor tampoco
// los ofrece para estas carpetas).
// ==================================================================

/// Abre el navegador de la carpeta local que comparte [shareId].
Future<void> showLocalShareBrowser(
  BuildContext context, {
  required int shareId,
  required String title,
  String? ownerName,
  LocalShareService? service,
}) {
  return showHsModal<void>(
    context: context,
    builder: (_) => _LocalShareBrowser(
      shareId: shareId,
      title: title,
      ownerName: ownerName,
      service: service ?? LocalShareService(),
    ),
  );
}

class _LocalShareBrowser extends StatefulWidget {
  const _LocalShareBrowser({
    required this.shareId,
    required this.title,
    required this.service,
    this.ownerName,
  });

  final int shareId;
  final String title;
  final String? ownerName;
  final LocalShareService service;

  @override
  State<_LocalShareBrowser> createState() => _LocalShareBrowserState();
}

class _LocalShareBrowserState extends State<_LocalShareBrowser> {
  List<String> _path = const [];
  List<LocalShareItem> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(const []);
  }

  Future<void> _load(List<String> path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.service.list(widget.shareId, path);
      if (!mounted) return;
      setState(() {
        _path = List.of(path);
        _items = data.items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _openItem(LocalShareItem item) {
    if (item.isFolder) {
      _load([..._path, item.name]);
      return;
    }
    _viewImage(item);
  }

  Future<void> _viewImage(LocalShareItem item) async {
    final url = widget.service.fileUrl(widget.shareId, [..._path, item.name]);
    await showHsModal<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Descargar',
                    onPressed: () => _download(item),
                    icon: const Icon(Icons.download_rounded, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                maxScale: 6,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      'No se pudo mostrar la imagen',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _download(LocalShareItem item) async {
    try {
      final where = await widget.service.download(widget.shareId, [
        ..._path,
        item.name,
      ], item.name);
      if (where == null) return;
      HsToast.success('Descargado: ${item.name}');
    } catch (e) {
      HsToast.error('No se pudo descargar "${item.name}": $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.folder_open_outlined, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (widget.ownerName != null && widget.ownerName!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 2),
              child: Text(
                'Compartida por ${widget.ownerName} · solo lectura',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Subir un nivel',
                  onPressed: _path.isEmpty ? null : () => _load(_dropLast()),
                  icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                ),
                IconButton(
                  tooltip: 'Actualizar',
                  onPressed: _loading ? null : () => _load(_path),
                  icon: const Icon(Icons.refresh, size: 18),
                ),
                Expanded(
                  child: Text(
                    _path.isEmpty ? 'Inicio' : _path.join(' / '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 26),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: scheme.error),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _load(_path),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              )
            else if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Text(
                  'Esta carpeta está vacía.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Flexible(
                // Como el Drive: carpetas y fotos van JUNTAS en la misma
                // cuadricula (antes se partian en dos tramos, primero las
                // carpetas en filas y luego las fotos).
                child: GridView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 4),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 170,
                    mainAxisExtent: 190,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _items.length,
                  itemBuilder: (_, i) => _tile(_items[i]),
                ),
              ),
          ],
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

  List<String> _dropLast() =>
      _path.isEmpty ? const [] : _path.sublist(0, _path.length - 1);

  /// Tarjeta de la cuadricula: carpeta o foto (la misma forma que el Drive).
  Widget _tile(LocalShareItem item) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openItem(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: item.isFolder
                  ? Container(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: .35,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.folder_rounded,
                        size: 40,
                        color: scheme.primary,
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        DriveThumb(
                          source: widget.service.thumbUrl(widget.shareId, [
                            ..._path,
                            item.name,
                          ]),
                          isRemote: true,
                          size: double.infinity,
                          big: true,
                          rounded: false,
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Material(
                            color: Colors.black.withValues(alpha: .45),
                            shape: const CircleBorder(),
                            child: IconButton(
                              tooltip: 'Descargar',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _download(item),
                              icon: const Icon(
                                Icons.download_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 6, 9, 8),
              child: Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.2,
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

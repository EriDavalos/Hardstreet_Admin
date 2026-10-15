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
                          fontSize: 13.5, fontWeight: FontWeight.w800),
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
      final where =
          await widget.service.download(widget.shareId, [..._path, item.name], item.name);
      if (where == null) return;
      HsToast.success('Descargado: ${item.name}');
    } catch (e) {
      HsToast.error('No se pudo descargar "${item.name}": $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final folders = _items.where((i) => i.isFolder).toList();
    final files = _items.where((i) => !i.isFolder).toList();

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
                      fontSize: 15, fontWeight: FontWeight.w800),
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
                        color: scheme.onSurfaceVariant),
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
                  style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final f in folders)
                      ListTile(
                        dense: true,
                        leading:
                            const Icon(Icons.folder_outlined, size: 20),
                        title: Text(f.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => _openItem(f),
                      ),
                    for (final img in files)
                      ListTile(
                        dense: true,
                        leading: DriveThumb(
                          source: widget.service.thumbUrl(
                              widget.shareId, [..._path, img.name]),
                          isRemote: true,
                          size: 34,
                        ),
                        title: Text(img.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => _openItem(img),
                        trailing: IconButton(
                          tooltip: 'Descargar',
                          onPressed: () => _download(img),
                          icon: const Icon(Icons.download_rounded, size: 18),
                        ),
                      ),
                  ],
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
}

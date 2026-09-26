import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerDownEvent, PointerEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyEvent, KeyDownEvent, LogicalKeyboardKey;

import '../drive_downloader.dart';
import '../drive_service.dart';
import '../widgets/common.dart';

/// Página "Archivos": drive estilo Google Drive con selección múltiple,
/// arrastrar-y-soltar y operaciones en lote (mover, copiar, eliminar).
class DrivePage extends StatefulWidget {
  const DrivePage({super.key, required this.drive});

  final DriveService drive;

  @override
  State<DrivePage> createState() => _DrivePageState();
}

class _DrivePageState extends State<DrivePage> {
  bool _grid = true;
  bool _selectMode = false;
  final Set<String> _selected = {};
  final _searchController = TextEditingController();

  // ---- Selección estilo explorador de escritorio ----
  int _anchorIndex = -1; // último clic simple, origen del rango con Shift
  PointerDeviceKind _lastPointerKind = PointerDeviceKind.mouse;
  // Doble clic manual (evita el retardo de ~300ms de onTap de GestureDetector):
  String? _lastClickItem;
  DateTime? _lastClickAt;

  // ---- Marquesina: recuadro de selección arrastrando con el ratón ----
  final _contentKey = GlobalKey();
  final Map<String, GlobalKey> _itemKeys = {};
  Offset? _marqueeStart;
  Rect? _marqueeRect;
  List<String> _lastPath = const [];

  // ---- "Suelta para subir": arrastre externo desde el explorador ----
  bool _externalDrag = false;
  final _scrollController = ScrollController();
  // Subidas recientes (registro estilo Drive: tarjeta con barras).
  final List<({String path, int size, DateTime at})> _recentUploads = [];
  // Copiar/pegar estilo explorador (Ctrl+C / Ctrl+V).
  List<String> _clipboardNames = const [];

  @override
  void initState() {
    super.initState();
    _lastPath = List.of(widget.drive.path);
    widget.drive.addListener(_onChange);
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    HardwareKeyboard.instance.removeHandler(_handleKey);
    widget.drive.removeListener(_onChange);
    _searchController.dispose();
    super.dispose();
  }

  /// Atajos de teclado (Esc / Supr / Ctrl+C / Ctrl+V).
  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!mounted) return false;
    final focus = FocusManager.instance.primaryFocus;
    // No interceptar mientras se escribe en un campo de texto.
    if (focus?.context?.findAncestorWidgetOfExactType<TextField>() != null) {
      return false;
    }
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false; // hay un diálogo abierto

    if (event.logicalKey == LogicalKeyboardKey.escape &&
        (_selectMode || _selected.isNotEmpty)) {
      _clearSelection();
      setState(() {
        _marqueeStart = null;
        _marqueeRect = null;
      });
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete && _selected.isNotEmpty) {
      _deleteItems(_selected.toList());
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyC &&
        HardwareKeyboard.instance.isControlPressed &&
        _selected.isNotEmpty) {
      setState(() => _clipboardNames = _selected.toList(growable: false));
      _snack(
          '${_clipboardNames.length} elemento${_clipboardNames.length == 1 ? '' : 's'} copiado${_clipboardNames.length == 1 ? '' : 's'} al portapapeles');
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyV &&
        HardwareKeyboard.instance.isControlPressed &&
        _clipboardNames.isNotEmpty) {
      _pasteClipboard();
      return true;
    }
    return false;
  }

  /// Ctrl+V: pega lo copiado en la carpeta actual.
  Future<void> _pasteClipboard() async {
    final names = List.of(_clipboardNames);
    final result = await widget.drive.copyItems(names, widget.drive.path);
    if (result.copied > 0) {
      _snack(
          '${result.copied} elemento${result.copied == 1 ? '' : 's'} pegado${result.copied == 1 ? '' : 's'}');
    }
    _showErrors(result.errors);
  }

  void _onChange() {
    if (!mounted) return;
    if (_lastPath.join('/') != widget.drive.path.join('/')) {
      // Cambio de carpeta: limpia selección, ancla y claves de elementos.
      _lastPath = List.of(widget.drive.path);
      _itemKeys.clear();
      _selected.clear();
      _selectMode = false;
      _anchorIndex = -1;
    }
    setState(() {});
  }

  // ==================== Selección ====================

  void _toggleSelect(String name) {
    setState(() {
      if (!_selected.add(name)) _selected.remove(name);
      if (_selected.isEmpty) _selectMode = false;
    });
  }

  void _selectAll() {
    setState(() {
      _selected
        ..clear()
        ..addAll(widget.drive.visibleItems.map((i) => i.name));
    });
  }

  void _clearSelection() {
    setState(() {
      _selected.clear();
      _selectMode = false;
    });
  }

  void _enterSelectMode(String name) {
    setState(() {
      _selectMode = true;
      _selected.add(name);
    });
  }

  /// Ancla del rango con Shift; índice dentro de [visibleItems].
  int _indexOf(String name) =>
      widget.drive.visibleItems.indexWhere((i) => i.name == name);

  /// Selección con ratón, al PRESIONAR (instantáneo, sin esperas).
  void _handleMouseSelect(DriveItem item) {
    final names = widget.drive.visibleItems.map((i) => i.name).toList();
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (shift) {
      // Rango desde el ancla (o desde el primero si no hay ancla) hasta aquí.
      final b = _indexOf(item.name);
      if (b >= 0) {
        final a =
            (_anchorIndex >= 0 && _anchorIndex < names.length) ? _anchorIndex : 0;
        final lo = a <= b ? a : b;
        final hi = a <= b ? b : a;
        _selectMode = true;
        _selected
          ..clear()
          ..addAll(names.sublist(lo, hi + 1));
        setState(() {});
        return;
      }
    }
    _anchorIndex = _indexOf(item.name);
    if (ctrl) {
      _anchorIndex = _indexOf(item.name);
      _selectMode = true;
      setState(() => _toggleSelect(item.name));
      return;
    }
    // Ya está seleccionado: NO colapsar al presionar, para que arrastrar
    // lleve TODO el grupo (como el explorador de Windows; para dejar solo
    // este elemento, clic en zona vacía y luego clic en él).
    if (_selected.contains(item.name)) return;
    _anchorIndex = _indexOf(item.name);
    _selectMode = true;
    _selected
      ..clear()
      ..add(item.name);
    setState(() {});
  }

  /// Tap del InkWell: SOLO táctil (el ratón ya seleccionó al presionar).
  void _onCardTap(DriveItem item) {
    if (_lastPointerKind == PointerDeviceKind.touch) {
      if (_selectMode) {
        _toggleSelect(item.name);
      } else {
        _open(item);
      }
    }
  }

  // ==================== Marquesina (recuadro de selección) ====================

  void _onContentPointerDown(PointerDownEvent event) {
    _lastPointerKind = event.kind;
    if (event.kind != PointerDeviceKind.mouse || event.buttons != 1) return;
    final box =
        _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(event.position);
    final size = box.size;
    if (local.dx < 0 || local.dy < 0 || local.dx > size.width) return;
    // ¿El pulsó empezó sobre una tarjeta?
    String? hitName;
    for (final entry in _itemKeys.entries) {
      final b = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (b == null || !b.attached) continue;
      if ((b.localToGlobal(Offset.zero) & b.size).contains(event.position)) {
        hitName = entry.key;
        break;
      }
    }
    if (hitName != null) {
      // Doble clic manual: segundo pulsó sobre la misma tarjeta en <400ms.
      final now = DateTime.now();
      final isDouble = hitName == _lastClickItem &&
          _lastClickAt != null &&
          now.difference(_lastClickAt!) < const Duration(milliseconds: 400);
      _lastClickItem = hitName;
      _lastClickAt = now;
      for (final i in widget.drive.visibleItems) {
        if (i.name == hitName) {
          if (isDouble) {
            _open(i); // doble clic: abrir carpeta / visor
          } else {
            _handleMouseSelect(i); // selección instantánea al presionar
          }
          break;
        }
      }
      return;
    }
    _lastClickItem = null;
    // El área vacía (entre tarjetas y bajo la última fila) inicia marquesina.
    _marqueeStart = local;
    _marqueeBase = _selected.toSet();
  }

  Set<String> _marqueeBase = {};

  void _onContentPointerMove(PointerEvent event) {
    if (_marqueeStart == null) return;
    if (event.kind != PointerDeviceKind.mouse) return;
    final box =
        _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(event.position);
    final size = box.size;
    final clamped = Offset(local.dx.clamp(0.0, size.width),
        local.dy.clamp(-200.0, double.infinity));
    final rect = Rect.fromPoints(_marqueeStart!, clamped);
    if (rect.width.abs() < 4 && rect.height.abs() < 4) return;
    setState(() => _marqueeRect = rect);

    // ¿Qué tarjetas intersectan el recuadro?
    final hit = <String>{};
    for (final entry in _itemKeys.entries) {
      final b = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (b == null || !b.attached) continue;
      final itemRect = box.globalToLocal(b.localToGlobal(Offset.zero)) & b.size;
      if (itemRect.overlaps(rect)) hit.add(entry.key);
    }
    setState(() {
      _selected
        ..clear()
        ..addAll(_marqueeBase)
        ..addAll(hit);
    });
    if (_selected.isNotEmpty) _selectMode = true;
  }

  void _onContentPointerUp(PointerEvent event) {
    if (_marqueeStart == null) return;
    final drewMarquee = _marqueeRect != null;
    setState(() {
      _marqueeStart = null;
      _marqueeRect = null;
      _marqueeBase = {};
      // Clic en zona vacía sin arrastrar: deselecciona todo.
      if (!drewMarquee && _selected.isNotEmpty) {
        _selected.clear();
        _selectMode = false;
        _anchorIndex = -1;
      }
    });
  }

  /// Ejecuta una acción de la barra de selección reportando errores.
  Future<void> _guarded(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  // ==================== "Suelta para subir" ====================

  Future<void> _handleExternalDrop(DropDoneDetails details) async {
    _lastClickItem = null;
    setState(() => _externalDrag = false);
    final paths = details.files
        .where((f) => kImageExtensions.contains(
            f.name.contains('.')
                ? f.name.substring(f.name.lastIndexOf('.')).toLowerCase()
                : ''))
        .map((f) => f.path)
        .toList();
    if (paths.isEmpty) {
      _snack('Solo se pueden subir imágenes (jpg, png, gif, webp, bmp)',
          error: true);
      return;
    }
    final saved = await widget.drive.uploadFromPaths(paths);
    setState(() {
      for (final p in paths.take(saved)) {
        final f = File(p);
        _recentUploads.insert(
          0,
          (
            path: p,
            size: f.existsSync() ? f.lengthSync() : 0,
            at: DateTime.now(),
          ),
        );
      }
      if (_recentUploads.length > 12) {
        _recentUploads.removeRange(12, _recentUploads.length);
      }
    });
    _snack('$saved imagen${saved == 1 ? '' : 'es'} subida${saved == 1 ? '' : 's'} a "${widget.drive.locationLabel}"');
  }

  /// Tarjeta flotante estilo Drive con el registro de subidas.
  Widget? get _recentUploadsPanel {
    if (_recentUploads.isEmpty) return null;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width < 620 ? 14 : 24, 10,
          MediaQuery.sizeOf(context).width < 620 ? 14 : 24, 0),
      child: Align(
        alignment: Alignment.centerRight,
        child: Material(
          elevation: 10,
          shadowColor: Colors.black.withValues(alpha: .25),
          borderRadius: BorderRadius.circular(16),
          color: scheme.surface,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 260),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_done_outlined,
                          size: 18, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_recentUploads.length} subida${_recentUploads.length == 1 ? '' : 's'} completada${_recentUploads.length == 1 ? '' : 's'}',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => setState(_recentUploads.clear),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: _recentUploads.length,
                    itemBuilder: (context, i) {
                      final u = _recentUploads[i];
                      return ListTile(
                        dense: true,
                        minLeadingWidth: 0,
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.file(
                            File(u.path),
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              width: 40,
                              height: 40,
                              color: scheme.surfaceContainerHighest,
                              child:
                                  const Icon(Icons.image_outlined, size: 20),
                            ),
                          ),
                        ),
                        title: Text(
                          u.path.split(Platform.pathSeparator).last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${_sizeLabel(u.size)} · subida #${_recentUploads.length - i}',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== Mensajes ====================

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  void _showErrors(List<String> errors) {
    if (errors.isEmpty) return;
    _snack(errors.first, error: true);
  }

  // ==================== Acciones ====================

  Future<void> _upload() async {
    try {
      const typeGroup = XTypeGroup(
        label: 'Imágenes',
        extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'],
      );
      final files = await openFiles(acceptedTypeGroups: [typeGroup]);
      final paths = files.map((f) => f.path).toList();
      final saved = await widget.drive.uploadFromPaths(paths);
      _snack(saved == 0
          ? 'No se seleccionaron imágenes'
          : '$saved imagen${saved == 1 ? '' : 'es'} subida${saved == 1 ? '' : 's'}');
    } catch (e) {
      _snack('No se pudo subir: $e', error: true);
    }
  }

  Future<void> _newFolder() async {
    final name = await _promptText(
      title: 'Nueva carpeta',
      label: 'Nombre de la carpeta',
      hint: 'Ej. ReynaCoot',
    );
    if (name == null) return;
    try {
      await widget.drive.createFolder(name);
      _snack('Carpeta "$name" creada');
    } catch (e) {
      _snack('$e', error: true);
    }
  }

  Future<void> _rename(DriveItem item) async {
    final name = await _promptText(
      title: item.isFolder ? 'Renombrar carpeta' : 'Renombrar imagen',
      label: 'Nuevo nombre',
      initial: item.name,
    );
    if (name == null || name == item.name) return;
    try {
      await widget.drive.rename(item, name);
      _snack('Renombrado a "$name"');
    } catch (e) {
      _snack('$e', error: true);
    }
  }

  Future<void> _delete(DriveItem item) => _deleteItems([item.name]);

  Future<void> _deleteItems(List<String> names) async {
    if (names.isEmpty) return; // Supr sin selección: nada que hacer.
    final plural = names.length > 1;
    final folder = widget.drive.locationLabel;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.error.withValues(alpha: .10),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.delete_outline, color: scheme.error, size: 26),
          ),
          title: Text(plural
              ? '¿Eliminar ${names.length} elementos?'
              : '¿Eliminar "${names.first}"?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                plural
                    ? 'Se eliminarán ${names.length} elementos de la carpeta actual. Esta acción no se puede deshacer.'
                    : 'Se eliminará "${names.first}". Esta acción no se puede deshacer.',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              // Chip de carpeta origen, como en el diálogo de Drive.
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_rounded,
                        size: 16, color: scheme.primary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        folder,
                        style: TextStyle(
                            fontSize: 12.5, color: scheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.delete_outline, size: 17),
              label: const Text('Eliminar'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    final result = await widget.drive.deleteItems(names);
    _clearSelection();
    if (result.deleted > 0) {
      _snack('${result.deleted} elemento${result.deleted == 1 ? '' : 's'} eliminado${result.deleted == 1 ? '' : 's'}');
    }
    _showErrors(result.errors);
  }

  /// Diálogo con navegador de carpetas para elegir destino de mover/copiar.
  Future<List<String>?> _pickDestination({required bool move}) async {
    final drive = widget.drive;
    var current = List.of(drive.path);
    var confirmed = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final folders = drive.listFolders(current);
          final atRoot = current.isEmpty;
          // Una carpeta no puede soltarse dentro de sí misma: si el destino
          // actual es una de las carpetas seleccionadas, bloquear confirmar.
          final isInvalid = _selected.contains(current.lastOrNull);

          return AlertDialog(
            title: Text(move ? 'Mover a...' : 'Copiar a...'),
            content: SizedBox(
              width: 380,
              height: 320,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Ruta actual
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: .5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      ['Mi Drive', ...current].join('  /  '),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: folders.isEmpty
                        ? Center(
                            child: Text(
                              'Sin subcarpetas aquí',
                              style: TextStyle(
                                color: Theme.of(ctx)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          )
                        : ListView(
                            children: [
                              if (!atRoot)
                                ListTile(
                                  leading: const Icon(Icons.arrow_upward),
                                  title: const Text('..'),
                                  dense: true,
                                  onTap: () => setDialogState(() {
                                    current = current.sublist(
                                        0, current.length - 1);
                                  }),
                                ),
                              for (final f in folders)
                                ListTile(
                                  leading: Icon(
                                    Icons.folder_rounded,
                                    color: Theme.of(ctx).colorScheme.primary,
                                  ),
                                  title: Text(f),
                                  dense: true,
                                  onTap: () => setDialogState(() {
                                    current = [...current, f];
                                  }),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: isInvalid
                    ? null
                    : () {
                        confirmed = true;
                        Navigator.pop(ctx);
                      },
                child: Text(move ? 'Mover aquí' : 'Copiar aquí'),
              ),
            ],
          );
        },
      ),
    );
    return confirmed ? current : null;
  }

  Future<void> _moveSelected(List<String> targetPath) async {
    final names = _selected.toList(growable: false);
    final result = await widget.drive.moveItems(names, targetPath);
    _clearSelection();
    if (result.moved > 0) {
      _snack('${result.moved} elemento${result.moved == 1 ? '' : 's'} movido${result.moved == 1 ? '' : 's'}');
    }
    _showErrors(result.errors);
  }

  Future<void> _copySelected(List<String> targetPath) async {
    final names = _selected.toList(growable: false);
    final result = await widget.drive.copyItems(names, targetPath);
    _clearSelection();
    if (result.copied > 0) {
      _snack('${result.copied} elemento${result.copied == 1 ? '' : 's'} copiado${result.copied == 1 ? '' : 's'}');
    }
    _showErrors(result.errors);
  }

  // ==================== Navegación / drag targets ====================

  void _open(DriveItem item) {
    if (item.isFolder) {
      _clearSelection();
      widget.drive.openFolder(item.name);
    } else {
      _openViewer(item);
    }
  }

  void _openViewer(DriveItem item) {
    final images = widget.drive.visibleItems
        .where((i) => !i.isFolder)
        .toList(growable: false);
    final index = images.indexWhere((i) => i.name == item.name);
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _ImageViewerDialog(
        drive: widget.drive,
        images: images,
        initialIndex: index < 0 ? 0 : index,
      ),
    );
  }

  void _onItemTap(DriveItem item) => _onCardTap(item);

  /// Soltó algo sobre un elemento (carpeta o imagen).
  void _onItemDrop(DriveItem target, DragTargetDetails<Object> details) {
    final payload = details.data;
    List<String> names;
    if (payload is SelectionPayload) {
      names = payload.names;
    } else {
      return;
    }
    if (!target.isFolder) {
      _snack('Solo puedes soltar sobre una carpeta', error: true);
      return;
    }
    // Excluir la propia carpeta destino de la selección.
    names = names.where((n) => n != target.name).toList(growable: false);
    if (names.isEmpty) return;
    _doMove(names, [...widget.drive.path, target.name]);
  }

  Future<void> _doMove(List<String> names, List<String> targetPath) async {
    final result = await widget.drive.moveItems(names, targetPath);
    _clearSelection();
    if (result.moved > 0) {
      _snack('${result.moved} elemento${result.moved == 1 ? '' : 's'} movido${result.moved == 1 ? '' : 's'} a "${targetPath.last}"');
    }
    _showErrors(result.errors);
  }

  // ==================== Diálogos auxiliares ====================

  Future<String?> _promptText({
    required String title,
    required String label,
    String? initial,
    String? hint,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label, hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    final drive = widget.drive;
    final scheme = Theme.of(context).colorScheme;
    final isCompact = MediaQuery.sizeOf(context).width < 620;
    final hPad = isCompact ? 14.0 : 24.0;

    if (!drive.isReady && drive.error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'No se pudo iniciar el almacenamiento',
        message: drive.error!,
      );
    }

    final imagesCount = drive.items.where((i) => !i.isFolder).length;
    final foldersCount = drive.items.where((i) => i.isFolder).length;

    // Desplazamiento del área de contenido dentro del Stack (header arriba):
    // la marquesina se dibuja en coords del Stack pero se calcula en coords
    // del contenido, así que hay que sumarle este offset.
    var marqueeOffset = Offset.zero;
    final contentBox =
        _contentKey.currentContext?.findRenderObject() as RenderBox?;
    final stackBox = context.findRenderObject() as RenderBox?;
    if (contentBox != null &&
        stackBox != null &&
        contentBox.attached &&
        stackBox.attached) {
      marqueeOffset =
          contentBox.localToGlobal(Offset.zero, ancestor: stackBox);
    }

    return DropTarget(
      onDragEntered: (_) {
        // Al arrastrar desde el explorador, sube la vista al inicio para
        // que se vea la zona de destino de inmediato.
        if (_scrollController.hasClients && _scrollController.offset > 0) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
          );
        }
        setState(() => _externalDrag = true);
      },
      onDragExited: (_) => setState(() => _externalDrag = false),
      onDragDone: _handleExternalDrop,
      child: Listener(
      onPointerDown: _onContentPointerDown,
      onPointerMove: _onContentPointerMove,
      onPointerUp: _onContentPointerUp,
      onPointerCancel: _onContentPointerUp,      child: Stack(
      children: [
        Column(
          children: [
            // ===== Header hero (barra fija con scroll interior) =====
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mi Drive',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              drive.locationLabel == 'Mi Drive'
                                  ? 'Raíz del almacenamiento'
                                  : drive.locationLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      if (isCompact) ...[
                        _RoundAction(
                          icon: Icons.create_new_folder_outlined,
                          tooltip: 'Nueva carpeta',
                          onTap: _newFolder,
                        ),
                        const SizedBox(width: 8),
                        _RoundAction(
                          icon: Icons.refresh,
                          tooltip: 'Actualizar',
                          onTap: drive.refresh,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: drive.setSearch,
                          decoration: const InputDecoration(
                            hintText: 'Buscar en esta carpeta',
                            prefixIcon: Icon(Icons.search, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Tooltip(
                        message:
                            _grid ? 'Vista de lista' : 'Vista de cuadrícula',
                        child: IconButton.filledTonal(
                          onPressed: () =>
                              setState(() => _grid = !_grid),
                          icon: Icon(
                            _grid
                                ? Icons.view_list_rounded
                                : Icons.grid_view_rounded,
                          ),
                        ),
                      ),
                      if (!isCompact) ...[
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: _newFolder,
                          icon: const Icon(
                            Icons.create_new_folder_outlined,
                            size: 18,
                          ),
                          label: const Text('Nueva carpeta'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: _upload,
                          icon: const Icon(Icons.upload_file, size: 18),
                          label: const Text('Subir imágenes'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // ===== Breadcrumbs (drop target para mover a esa carpeta) =====
            if (drive.path.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _Breadcrumbs(drive: drive, onDropMove: _doMove),
                ),
              ),
            // ===== Subidas recientes (si hay) =====
            ?_recentUploadsPanel,
            // ===== Accesos rápidos (solo raíz) =====
            if (drive.path.isEmpty &&
                !drive.loading &&
                drive.visibleItems.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final f
                          in drive.items.where((i) => i.isFolder).take(6))
                        ActionChip(
                          avatar: Icon(
                            Icons.folder_rounded,
                            size: 16,
                            color: scheme.primary,
                          ),
                          label: Text(f.name),
                          onPressed: () => widget.drive.openFolder(f.name),
                        ),
                    ],
                  ),
                ),
              ),
            // ===== Barra de estado =====
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 6),
              child: Row(
                children: [
                  _CountPill(
                    icon: Icons.folder_rounded,
                    label: '$foldersCount carpetas',
                  ),
                  const SizedBox(width: 8),
                  _CountPill(
                    icon: Icons.image_outlined,
                    label: '$imagesCount imágenes',
                  ),
                  if (drive.search != null) ...[
                    const SizedBox(width: 8),
                    _CountPill(
                      icon: Icons.filter_alt,
                      label: 'filtro: "${drive.search}"',
                    ),
                  ],
                  const Spacer(),
                  if (!_selectMode && drive.visibleItems.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectMode = true;
                          if (_selected.isEmpty) {
                            _selected.add(drive.visibleItems.first.name);
                            _anchorIndex = 0;
                          }
                        });
                      },
                      icon: const Icon(Icons.checklist, size: 18),
                      label: const Text('Seleccionar'),
                    ),
                ],
              ),
            ),
            // ===== Contenido =====
            Expanded(
              child: drive.loading && drive.items.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : drive.error != null
                      ? EmptyState(
                          icon: Icons.folder_off_outlined,
                          title: 'Error',
                          message: drive.error!,
                          actionLabel: 'Reintentar',
                          onAction: drive.refresh,
                        )
                      : drive.visibleItems.isEmpty
                          ? EmptyState(
                              icon: Icons.folder_open_rounded,
                              title: drive.search != null
                                  ? 'Sin resultados'
                                  : 'Esta carpeta está vacía',
                              message:
                                  'Sube imágenes o crea una carpeta para organizar tu contenido.',
                              actionLabel: 'Subir imágenes',
                              onAction: _upload,
                            )
                          : (_grid
                              ? _GridContent(
                                  key: _contentKey,
                                  drive: drive,
                                  compact: isCompact,
                                  selected: _selected,
                                  selectMode: _selectMode,
                                  onOpen: _onItemTap,
                                  onLongPress: (item) =>
                                      _enterSelectMode(item.name),
                                  onToggleSelect: _toggleSelect,
                                  onRename: _rename,
                                  onDelete: _delete,
                                  onDrop: _onItemDrop,
                                  itemKeys: _itemKeys,
                                  onTapSelect: _onCardTap,
                                  scrollController: _scrollController,
                                )
                              : _ListContent(
                                  key: _contentKey,
                                  drive: drive,
                                  compact: isCompact,
                                  selected: _selected,
                                  selectMode: _selectMode,
                                  onOpen: _onItemTap,
                                  onLongPress: (item) =>
                                      _enterSelectMode(item.name),
                                  onToggleSelect: _toggleSelect,
                                  onRename: _rename,
                                  onDelete: _delete,
                                  onDrop: _onItemDrop,
                                  itemKeys: _itemKeys,
                                  onTapSelect: _onCardTap,
                                  scrollController: _scrollController,
                                )),
            ),
          ],
        ),
        // ===== Recuadro de selección (marquesina) =====
        if (_marqueeRect != null)
          Positioned.fromRect(
            rect: _marqueeRect!.shift(marqueeOffset),
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .12),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: .8),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        // ===== Overlay "Suelta para subir" =====
        if (_externalDrag)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: scheme.primary.withValues(alpha: .10),
                child: Center(
                  child: AnimatedScale(
                    scale: 1,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 20),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: scheme.primary.withValues(alpha: .45),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.upload_rounded,
                              color: Colors.white, size: 34),
                          const SizedBox(height: 8),
                          const Text(
                            'Suelta para subir',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Se subirán a "${drive.locationLabel}"',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .85),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        // ===== Barra de acciones de selección =====
        // Solo existe cuando hay selección: sin estado oculto que robe clics.
        if (_selectMode && _selected.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _SelectionBar(
              count: _selected.length,
              compact: isCompact,
              onClear: _clearSelection,
              onSelectAll: _selectAll,
              onMove: () => _guarded(() async {
                final dest = await _pickDestination(move: true);
                if (dest != null) await _moveSelected(dest);
              }),
              onCopy: () => _guarded(() async {
                final dest = await _pickDestination(move: false);
                if (dest != null) await _copySelected(dest);
              }),
              onDownload: () => _guarded(() async {
                final items = widget.drive.items
                    .where((i) => _selected.contains(i.name))
                    .toList();
                await downloadDriveSelection(
                  context,
                  drive: widget.drive,
                  items: items,
                );
              }),
              onDelete: () => _guarded(
                  () => _deleteItems(_selected.toList())),
            ),
          ),
        // ===== Tarjeta FIJA de subidas recientes (arriba a la derecha) =====
        Positioned(
          top: 6,
          right: hPad,
          child: IgnorePointer(
            ignoring: _recentUploads.isEmpty,
            child: _recentUploadsPanel ?? const SizedBox.shrink(),
          ),
        ),
      ],
      ),
      ),
    );
  }
}

/// Payload de arrastre: uno o varios elementos.
class SelectionPayload {
  SelectionPayload(this.names);
  final List<String> names;
}

/// Botón circular compacto para móvil.
class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 20),
    );
  }
}

/// Píldora de conteo para la barra de estado.
class _CountPill extends StatelessWidget {
  const _CountPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [            Icon(icon, size: 13, color: scheme.primary),
          const SizedBox(width: 5),
          Text(
            label,
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

// ===================== Barra de selección =====================

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.compact,
    required this.onClear,
    required this.onSelectAll,
    required this.onMove,
    required this.onCopy,
    required this.onDelete,
    required this.onDownload,
  });

  final int count;
  final bool compact;
  final VoidCallback onClear;
  final VoidCallback onSelectAll;
  final VoidCallback onMove;
  final VoidCallback onCopy;
  final VoidCallback onDelete;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Material(
              elevation: 12,
              shadowColor: scheme.primary.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(20),
              color: scheme.primary,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 8 : 14,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Cancelar selección',
                      onPressed: onClear,
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                    const SizedBox(width: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        count == 1
                            ? 'elemento seleccionado'
                            : 'elementos seleccionados',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .95),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: onSelectAll,
                      style: TextButton.styleFrom(
                        foregroundColor:
                            Colors.white.withValues(alpha: .92),
                      ),
                      child: const Text('Todos'),
                    ),
                    const SizedBox(width: 2),
                    _BarAction(
                      tooltip: 'Mover a...',
                      icon: Icons.drive_file_move_outline,
                      onPressed: onMove,
                    ),
                    _BarAction(
                      tooltip: 'Copiar a...',
                      icon: Icons.copy_all_outlined,
                      onPressed: onCopy,
                    ),
                    _BarAction(
                      tooltip: 'Descargar',
                      icon: Icons.download_rounded,
                      onPressed: onDownload,
                    ),
                    _BarAction(
                      tooltip: 'Eliminar',
                      icon: Icons.delete_outline,
                      onPressed: onDelete,
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }
}

/// Botón de acción de la barra de selección con hover suave.
class _BarAction extends StatelessWidget {
  const _BarAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      hoverColor: Colors.white.withValues(alpha: .18),
      icon: Icon(icon, color: Colors.white, size: 22),
    );
  }
}

// ===================== Breadcrumbs =====================

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.drive, required this.onDropMove});

  final DriveService drive;
  final void Function(List<String> names, List<String> targetPath) onDropMove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final separator = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Icon(
        Icons.chevron_right,
        size: 18,
        color: scheme.onSurfaceVariant.withValues(alpha: .55),
      ),
    );

    Widget crumb(
      String label,
      VoidCallback onTap, {
      bool current = false,
      List<String> target = const [],
    }) {
      final t = target;
      return DragTarget<Object>(
        onWillAcceptWithDetails: (_) => !current,
        onAcceptWithDetails: (details) {
          final payload = details.data;
          List<String> names;
          if (payload is SelectionPayload) {
            names = payload.names;
          } else {
            return;
          }
          onDropMove(names, t);
        },
        builder: (context, candidate, rejected) {
          final hovering = candidate.isNotEmpty;
          return InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: hovering
                    ? scheme.primary.withValues(alpha: .15)
                    : current
                        ? scheme.primary.withValues(alpha: .08)
                        : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: current ? FontWeight.w800 : FontWeight.w600,
                        color: current
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
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

    final children = <Widget>[
      crumb(
        'Mi Drive',
        () => drive.openPath(const []),
        current: drive.path.isEmpty,
        target: const [],
      ),
    ];
    for (var i = 0; i < drive.path.length; i++) {
      children.add(separator);
      final t = drive.path.sublist(0, i + 1);
      children.add(
        crumb(
          drive.path[i],
          () => drive.openPath(t),
          current: i == drive.path.length - 1,
          target: t,
        ),
      );
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

// ===================== Grid =====================

class _GridContent extends StatelessWidget {
  const _GridContent({
    super.key,
    required this.drive,
    required this.compact,
    required this.selected,
    required this.selectMode,
    required this.onOpen,
    required this.onLongPress,
    required this.onToggleSelect,
    required this.onRename,
    required this.onDelete,
    required this.onDrop,
    required this.itemKeys,
    required this.onTapSelect,
    required this.scrollController,
  });

  final DriveService drive;
  final bool compact;
  final Set<String> selected;
  final bool selectMode;
  final ValueChanged<DriveItem> onOpen;
  final ValueChanged<DriveItem> onLongPress;
  final ValueChanged<String> onToggleSelect;
  final ValueChanged<DriveItem> onRename;
  final ValueChanged<DriveItem> onDelete;
  final void Function(DriveItem target, DragTargetDetails<Object> details)
      onDrop;
  final Map<String, GlobalKey> itemKeys;
  final ValueChanged<DriveItem> onTapSelect;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final items = drive.visibleItems;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final minCard = compact ? 150.0 : 190.0;
        final crossCount = (width / minCard).floor().clamp(2, 8);
        return GridView.builder(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(
              compact ? 14 : 24, 4, compact ? 14 : 24, compact ? 150 : 110),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.86,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final item = items[i];
            final key = itemKeys.putIfAbsent(
                item.name, () => GlobalKey(debugLabel: 'grid-${item.name}'));
            return _GridItem(
              key: key,
              item: item,
              drive: drive,
              isSelected: selected.contains(item.name),
              selectMode: selectMode,
              onOpen: () => onOpen(item),
              onLongPress: () => onLongPress(item),
              onToggleSelect: () => onToggleSelect(item.name),
              onRename: () => onRename(item),
              onDelete: () => onDelete(item),
              onDrop: (details) => onDrop(item, details),
              onTapSelect: () => onTapSelect(item),
              selectedNames: selected.toList(growable: false),
            );
          },
        );
      },
    );
  }
}

/// Tarjeta genérica de grid: carpeta o imagen, con selección y drag&drop.
class _GridItem extends StatelessWidget {
  const _GridItem({
    super.key,
    required this.item,
    required this.drive,
    required this.isSelected,
    required this.selectMode,
    required this.onOpen,
    required this.onLongPress,
    required this.onToggleSelect,
    required this.onRename,
    required this.onDelete,
    required this.onDrop,
    required this.onTapSelect,
    required this.selectedNames,
  });

  final DriveItem item;
  final DriveService drive;
  final bool isSelected;
  final bool selectMode;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;
  final VoidCallback onToggleSelect;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final void Function(DragTargetDetails<Object> details) onDrop;
  final VoidCallback onTapSelect;
  final List<String> selectedNames;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canDrop = item.isFolder;

    return Draggable<Object>(
      data: isSelected && selectedNames.length > 1
          ? SelectionPayload(selectedNames)
          : SelectionPayload([item.name]),
      feedback: _DragFeedback(
        label: item.name,
        isFolder: item.isFolder,
        count: isSelected && selectedNames.length > 1
            ? selectedNames.length
            : 1,
      ),
      childWhenDragging: Opacity(opacity: .45, child: _card(scheme, context)),
      onDragStarted: () {
        // Si arrastras un elemento seleccionado en modo selección,
        // se arrastra toda la selección (el data ya lo decide).
      },
      dragAnchorStrategy: pointerDragAnchorStrategy,
      child: DragTarget<Object>(
        onWillAcceptWithDetails: (details) =>
            canDrop && details.data is! DriveItem,
        onAcceptWithDetails: onDrop,
        builder: (context, candidate, rejected) {
          final hovering = candidate.isNotEmpty && canDrop;
          return _card(
            scheme,
            context,
            hovering: hovering,
          );
        },
      ),
    );
  }

  Widget _card(ColorScheme scheme, BuildContext context,
      {bool hovering = false}) {
    return _Hover(
      builder: (context, mouseHover) {
        final hovered = mouseHover || hovering;
        return Stack(
          children: [
            Positioned.fill(
              child: InkWell(
                onTap: onTapSelect,
                onLongPress: onLongPress,
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? scheme.primary
                          : hovered
                              ? scheme.primary.withValues(alpha: .45)
                              : Colors.transparent,
                      width: 2.5,
                    ),
                    color: isSelected
                        ? scheme.primary.withValues(alpha: .14)
                        : hovered
                            ? scheme.primary.withValues(alpha: .05)
                            : null,
                    boxShadow: [
                      if (isSelected)
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: .30),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        )
                      else if (hovered)
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .14),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13.5),
                    child: item.isFolder
                        ? _FolderCard(
                            item: item,
                            onOpen: onOpen,
                            onLongPress: onLongPress,
                            onRename: onRename,
                            onDelete: onDelete,
                          )
                        : _ImageCard(
                            item: item,
                            drive: drive,
                            onOpen: onOpen,
                            onLongPress: onLongPress,
                            onRename: onRename,
                            onDelete: onDelete,
                          ),
                  ),
                ),
              ),
            ),
            // Insignia con el NÚMERO DE ORDEN del elemento (1, 2, 3...) —
            // solo cuando hay varios seleccionados.
            if (isSelected && selectedNames.length > 1)
              Positioned(
                top: 6,
                right: 6,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: .4, end: 1),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  builder: (context, s, child) =>
                      Transform.scale(scale: s, child: child),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: .5),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      '${selectedNames.indexOf(item.name) + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Envoltorio que indica si el mouse está encima del hijo.
class _Hover extends StatefulWidget {
  const _Hover({required this.builder});

  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(context, _hovered),
    );
  }
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({
    required this.label,
    required this.isFolder,
    this.count = 1,
  });

  final String label;
  final bool isFolder;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(10),
      color: scheme.primary,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isFolder && count == 1
                  ? Icons.folder_rounded
                  : Icons.image_outlined,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                count > 1 ? '$count elementos' : label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({
    required this.item,
    required this.onOpen,
    required this.onLongPress,
    required this.onRename,
    required this.onDelete,
  });

  final DriveItem item;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.primary.withValues(alpha: .24),
                    scheme.primary.withValues(alpha: .07),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.folder_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const Spacer(),
                  _ItemMenu(onRename: onRename, onDelete: onDelete),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.childCount} elemento${item.childCount == 1 ? '' : 's'}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageCard extends StatelessWidget {
  const _ImageCard({
    required this.item,
    required this.drive,
    required this.onOpen,
    required this.onLongPress,
    required this.onRename,
    required this.onDelete,
  });

  final DriveItem item;
  final DriveService drive;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = drive.absolutePathOf(item);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Center(
                        child: Icon(Icons.broken_image_outlined, size: 32),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _OverlayMenu(
                        onRename: onRename,
                        onDelete: onDelete,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _metaLabel(item),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                            color: scheme.onSurfaceVariant, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemMenu extends StatelessWidget {
  const _ItemMenu({required this.onRename, required this.onDelete});

  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Opciones',
      padding: EdgeInsets.zero,
      splashRadius: 18,
      icon: Icon(
        Icons.more_vert,
        size: 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onSelected: (v) {
        if (v == 'rename') onRename();
        if (v == 'delete') onDelete();
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'rename', child: Text('Renombrar')),
        PopupMenuItem(value: 'delete', child: Text('Eliminar')),
      ],
    );
  }
}

class _OverlayMenu extends StatelessWidget {
  const _OverlayMenu({required this.onRename, required this.onDelete});

  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
      child: PopupMenuButton<String>(
        tooltip: 'Opciones',
        padding: EdgeInsets.zero,
        splashRadius: 18,
        icon: const Icon(Icons.more_vert, size: 18, color: Colors.white),
        onSelected: (v) {
          if (v == 'rename') onRename();
          if (v == 'delete') onDelete();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: Text('Renombrar')),
          PopupMenuItem(value: 'delete', child: Text('Eliminar')),
        ],
      ),
    );
  }
}

// ===================== List =====================

class _ListContent extends StatelessWidget {
  const _ListContent({
    super.key,
    required this.drive,
    required this.compact,
    required this.selected,
    required this.selectMode,
    required this.onOpen,
    required this.onLongPress,
    required this.onToggleSelect,
    required this.onRename,
    required this.onDelete,
    required this.onDrop,
    required this.itemKeys,
    required this.onTapSelect,
    required this.scrollController,
  });

  final DriveService drive;
  final bool compact;
  final Set<String> selected;
  final bool selectMode;
  final ValueChanged<DriveItem> onOpen;
  final ValueChanged<DriveItem> onLongPress;
  final ValueChanged<String> onToggleSelect;
  final ValueChanged<DriveItem> onRename;
  final ValueChanged<DriveItem> onDelete;
  final void Function(DriveItem target, DragTargetDetails<Object> details)
      onDrop;
  final Map<String, GlobalKey> itemKeys;
  final ValueChanged<DriveItem> onTapSelect;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = drive.visibleItems;
    final headerStyle = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(
            color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700);

    final dividerColor = Theme.of(context).dividerTheme.color ??
        scheme.outlineVariant.withValues(alpha: .5);
    return Card(
      margin: EdgeInsets.fromLTRB(
          compact ? 14 : 24, 4, compact ? 14 : 24, compact ? 150 : 110),
      child: Column(
        children: [
          if (!compact)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const SizedBox(width: 40),
                  Expanded(child: Text('Nombre', style: headerStyle)),
                  SizedBox(
                    width: 140,
                    child: Text('Modificado', style: headerStyle),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text('Tamaño', style: headerStyle),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
          Divider(height: 1, color: dividerColor),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                final key = itemKeys.putIfAbsent(
                    item.name, () => GlobalKey(debugLabel: 'row-${item.name}'));
                return _ListRow(
                  key: key,
                  item: item,
                  drive: drive,
                  compact: compact,
                  isSelected: selected.contains(item.name),
                  selectMode: selectMode,
                  onOpen: () => onOpen(item),
                  onLongPress: () => onLongPress(item),
                  onToggleSelect: () => onToggleSelect(item.name),
                  onRename: () => onRename(item),
                  onDelete: () => onDelete(item),
                  onDrop: (details) => onDrop(item, details),
                  onTapSelect: () => onTapSelect(item),
                  selectedNames: selected.toList(growable: false),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    super.key,
    required this.item,
    required this.drive,
    required this.compact,
    required this.isSelected,
    required this.selectMode,
    required this.onOpen,
    required this.onLongPress,
    required this.onToggleSelect,
    required this.onRename,
    required this.onDelete,
    required this.onDrop,
    required this.onTapSelect,
    required this.selectedNames,
  });

  final DriveItem item;
  final DriveService drive;
  final bool compact;
  final bool isSelected;
  final bool selectMode;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;
  final VoidCallback onToggleSelect;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final void Function(DragTargetDetails<Object> details) onDrop;
  final VoidCallback onTapSelect;
  final List<String> selectedNames;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canDrop = item.isFolder;

    return Draggable<Object>(
      data: isSelected && selectedNames.length > 1
          ? SelectionPayload(selectedNames)
          : SelectionPayload([item.name]),
      feedback: _DragFeedback(
        label: item.name,
        isFolder: item.isFolder,
        count: isSelected && selectedNames.length > 1
            ? selectedNames.length
            : 1,
      ),
      childWhenDragging: Opacity(opacity: .45, child: _row(scheme, context)),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      child: DragTarget<Object>(
        onWillAcceptWithDetails: (details) =>
            canDrop && details.data is! DriveItem,
        onAcceptWithDetails: onDrop,
        builder: (context, candidate, rejected) {
          final hovering = candidate.isNotEmpty && canDrop;
          return _row(scheme, context, hovering: hovering);
        },
      ),
    );
  }

  Widget _row(ColorScheme scheme, BuildContext context,
      {bool hovering = false}) {
    final path = drive.absolutePathOf(item);
    return InkWell(
      onTap: onTapSelect,
      onLongPress: onLongPress,
      hoverColor: scheme.primary.withValues(alpha: .07),
      highlightColor: scheme.primary.withValues(alpha: .10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primary.withValues(alpha: .16)
              : hovering
                  ? scheme.primary.withValues(alpha: .14)
                  : null,
          border: Border(
            left: BorderSide(
              width: 3.5,
              color: isSelected ? scheme.primary : Colors.transparent,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        child: Row(
          children: [
            // Icono o miniatura
            SizedBox(
                width: 40,
                height: 40,
                child: item.isFolder
                    ? Icon(
                        Icons.folder_rounded,
                        color: scheme.primary,
                        size: 26,
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          File(path),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.image_outlined,
                            size: 22,
                          ),
                        ),
                      ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ),
            if (!compact) ...[
              SizedBox(
                width: 140,
                child: Text(
                  _dateLabel(item.modified),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              SizedBox(
                width: 90,
                child: Text(
                  item.isFolder ? '—' : _sizeLabel(item.size ?? 0),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            if (isSelected && selectedNames.length > 1) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${selectedNames.indexOf(item.name) + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            SizedBox(
              width: 40,
              child: _ItemMenu(onRename: onRename, onDelete: onDelete),
            ),
          ],
        ),
      ),
    );
  }
}

// ===================== Helpers de formato =====================

String _dateLabel(DateTime? d) {
  if (d == null) return '—';
  const months = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

String _sizeLabel(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _metaLabel(DriveItem item) {
  final parts = <String>[];
  if (item.size != null) parts.add(_sizeLabel(item.size!));
  final d = item.modified;
  if (d != null) parts.add(_dateLabel(d));
  return parts.join(' · ');
}

// ===================== Visor de imágenes =====================

class _ImageViewerDialog extends StatefulWidget {
  const _ImageViewerDialog({
    required this.drive,
    required this.images,
    required this.initialIndex,
  });

  final DriveService drive;
  final List<DriveItem> images;
  final int initialIndex;

  @override
  State<_ImageViewerDialog> createState() => _ImageViewerDialogState();
}

class _ImageViewerDialogState extends State<_ImageViewerDialog> {
  late int _index = widget.initialIndex;

  void _move(int delta) {
    final next = (_index + delta) % widget.images.length;
    setState(() => _index = next < 0 ? next + widget.images.length : next);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.images[_index];
    final path = widget.drive.absolutePathOf(item);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: InteractiveViewer(
              maxScale: 5,
              child: Center(
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white70,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    item.name,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
          if (widget.images.length > 1) ...[
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(24),
                  child: IconButton(
                    icon:
                        const Icon(Icons.chevron_left, color: Colors.white),
                    onPressed: () => _move(-1),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(24),
                  child: IconButton(
                    icon:
                        const Icon(Icons.chevron_right, color: Colors.white),
                    onPressed: () => _move(1),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

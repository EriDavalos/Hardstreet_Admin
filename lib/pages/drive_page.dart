import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart'
    show
        GestureDisposition,
        GestureMultiDragStartCallback,
        MultiDragGestureRecognizer,
        MultiDragPointerState,
        PointerDeviceKind,
        PointerDownEvent,
        PointerEvent,
        computeHitSlop;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, HapticFeedback, KeyEvent, KeyDownEvent, LogicalKeyboardKey;

import '../../app_constants.dart';
import '../../app_platform.dart';
import '../../drive_api_service.dart';
import '../../drive_base.dart';
import '../../drive_downloader.dart';
import '../../image_memory.dart';
import '../../widgets/anim.dart';
import '../../widgets/common.dart';
import '../../widgets/confirm_dialog.dart';

// ===================== Drag estilo Google Drive (móvil) =====================

/// Estado por-dedo: espera la presión larga y SOLO arranca el arrastre si el
/// dedo SE MUEVE (igual que Google Drive). Suelta sin mover → el tap/long-
/// press normal del InkWell gana → SELECCIONA.
///
/// La variante oficial [LongPressDraggable] arranca el drag al cumplirse el
/// delay AUNQUE el dedo esté quieto: eso "robaba" el gesto y la selección
/// por presión larga nunca ocurría.
class _PressMovePointerState extends MultiDragPointerState {
  _PressMovePointerState(
    super.initialPosition,
    this.delay,
    super.kind,
    super.gestureSettings,
  ) {
    _timer = Timer(delay, _delayPassed);
  }

  final Duration delay;

  Timer? _timer;
  GestureMultiDragStartCallback? _starter;

  /// El dedo se movió más allá del slop ANTES del delay → NO es drag:
  /// se rechaza y el gesto queda libre (scroll del grid).
  void _reject() {
    _timer?.cancel();
    _timer = null;
    resolve(GestureDisposition.rejected);
  }

  /// Se cumplió el delay SIN salida del dedo: listo para arrastrar. Si el
  /// reconocedor ya ganó la arena, arranca AHORA; si no, espera a que la
  /// arena lo acepte (al primer movimiento relevante).
  void _delayPassed() {
    _timer = null;
    final starter = _starter;
    if (starter != null) {
      _starter = null;
      starter(initialPosition);
    }
    // Con _starter == null esperamos accepted() (ver abajo).
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    if (_timer == null) {
      // Presión cumplida y arena ganada: iniciar el arrastre.
      starter(initialPosition);
    } else {
      // Aún esperando el delay: guardar y arrancar en _delayPassed.
      _starter = starter;
    }
  }

  @override
  void checkForResolutionAfterMove() {
    if (pendingDelta == null) return;
    final slop =
        computeHitSlop(kind, gestureSettings).clamp(8.0, 24.0).toDouble();
    if (_timer != null) {
      // AÚN en la espera: movimiento grande = scroll intencional → rechazar.
      if (pendingDelta!.distance > slop) _reject();
      return;
    }
    // Presión cumplida (timer en null): CUALQUIER movimiento extra arranca
    // el drag. pendingDelta acumula lo recorrido durante la presión.
    if (pendingDelta!.distance > slop) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

/// Reconoce: mantener presionado [delay] y DESPUÉS mover el dedo para
/// arrastrar. Reemplaza a LongPressDraggable en móvil.
class PressMoveMultiDragGestureRecognizer
    extends MultiDragGestureRecognizer {
  PressMoveMultiDragGestureRecognizer({
    super.debugOwner,
    super.allowedButtonsFilter,
    this.delay = const Duration(milliseconds: 350),
  });

  /// Duración de la presión antes de habilitar el arrastre.
  final Duration delay;

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) {
    return _PressMovePointerState(
      event.position,
      delay,
      event.kind,
      gestureSettings,
    );
  }

  @override
  String get debugDescription => 'press-and-move drag';
}

/// Envoltorio de arrastre para MÓVIL: presión larga SIN mover = selección
/// (el onLongPress del InkWell ocurre normal); presión larga + mover dedo =
/// arrastrar (mismo feedback que Draggable).
/// Subclase de [Draggable] igual que lo hace [LongPressDraggable]: cambia
/// SOLO el reconocedor de gestos.
class PressMoveDraggable<T extends Object> extends Draggable<T> {
  const PressMoveDraggable({
    super.key,
    required super.child,
    required super.feedback,
    required super.data,
    this.delay = const Duration(milliseconds: 350),
    super.childWhenDragging,
    super.dragAnchorStrategy,
  });

  /// Duración de la presión antes de habilitar el arrastre.
  final Duration delay;

  @override
  MultiDragGestureRecognizer createRecognizer(
      GestureMultiDragStartCallback onStart) {
    return PressMoveMultiDragGestureRecognizer(delay: delay)
      ..onStart = (Offset position) {
        final drag = onStart(position);
        if (drag != null) HapticFeedback.selectionClick();
        return drag;
      };
  }
}

/// Página "Archivos": drive estilo Google Drive con selección múltiple,
/// arrastrar-y-soltar y operaciones en lote (mover, copiar, eliminar).
class DrivePage extends StatefulWidget {
  const DrivePage({super.key, required this.drive});

  final DriveBase drive;

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
      // Cambio de carpeta: limpia selección/ancla/claves y evicta SOLO las
      // miniaturas de la carpeta anterior. (NO clearRam(): borrar toda la
      // caché invalida también los previews en vuelo y al regresar se veía
      // un buen rato de imágenes recargándose.)
      if (widget.drive is DriveApiService) {
        final api = widget.drive as DriveApiService;
        for (final it in widget.drive.items) {
          if (!it.isFolder) ImageMemory.evict(api.thumbSource(it));
        }
      }
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

  /// Ejecuta una acción reportando errores; devuelve null si falló.
  Future<T?> _guarded<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      _snack('Error: $e', error: true);
      return null;
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
    await _startUpload(paths);
  }

  /// Flujo completo de subida: detecta duplicados → pregunta qué hacer →
  /// sube (renombrando o sobrescribiendo) o cancela.
  Future<void> _startUpload(List<String> paths) async {
    // Nombres de los archivos a subir (acepta / o \ mezclados).
    String nameOf(String p) => p.split(RegExp(r'[\\/]')).last;
    List<String> dups;
    try {
      dups = await widget.drive
          .filterExisting(paths.map(nameOf).toList());
    } catch (_) {
      dups = const [];
    }
    var overwrite = false;
    if (dups.isNotEmpty) {
      final action = await _askDuplicateAction(dups);
      if (action == null) {
        _snack('Subida cancelada');
        return; // usuario canceló todo el lote
      }
      overwrite = action;
    }
    final saved = await _guarded(
        () => widget.drive.uploadFromPaths(paths, overwrite: overwrite));
    if (saved == null) return; // el error ya se mostró
    if (saved > 0) {
      _snack('$saved imagen${saved == 1 ? '' : 'es'} subida${saved == 1 ? '' : 's'} a "${widget.drive.locationLabel}"');
    }
  }

  /// Modal: ¿renombrar, sobrescribir o cancelar los duplicados?
  /// Devuelve true = sobrescribir, false = renombrar, null = cancelar.
  Future<bool?> _askDuplicateAction(List<String> dups) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Duplicados',
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, _, _) {
        final scheme = Theme.of(ctx).colorScheme;
        final preview = dups.length > 3
            ? '${dups.take(3).join(', ')} y ${dups.length - 3} más'
            : dups.join(', ');
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22)),
              contentPadding:
                  const EdgeInsets.fromLTRB(24, 24, 24, 12),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: .10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.copy_all_rounded,
                        color: scheme.primary, size: 26),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    dups.length == 1
                        ? 'El archivo ya existe'
                        : '${dups.length} archivos ya existen',
                    textAlign: TextAlign.center,
                    style: Theme.of(ctx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    preview,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '¿Qué quieres hacer con los duplicados?',
                    textAlign: TextAlign.center,
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.save_as_rounded, size: 17),
                      label: const Text('Sobrescribir'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(ctx, false),
                      icon: const Icon(Icons.auto_awesome_motion_rounded,
                          size: 17),
                      label: const Text('Mantener ambos (renombrar)'),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    child: const Text('Cancelar subida'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, _, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: .92, end: 1).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
          child: child,
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
      if (paths.isEmpty) {
        _snack('No se seleccionaron imágenes');
        return;
      }
      await _startUpload(paths);
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
    // Confirmación moderna y compacta (con transición de entrada).
    final ok = await confirmDelete(
      context,
      title: plural
          ? '¿Eliminar ${names.length} elementos?'
          : '¿Eliminar "${names.first}"?',
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
            // ===== Ruta actual (SOLO computadora: en el celular no se ve
            // bien y sobra; allí basta el botón "Atrás") =====
            if (!isCompact && drive.path.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _Breadcrumbs(drive: drive, onDropMove: _doMove),
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
                          : AnimatedSwitcher(
                              // Transición suave al cambiar de carpeta (o de
                              // vista): la anterior se desvanece mientras la
                              // nueva entra — sin esperar "en blanco".
                              // El GlobalKey vive AQUÍ (no en el contenido)
                              // para no duplicarse durante la transición.
                              key: _contentKey,
                              duration: const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeIn,
                              child: KeyedSubtree(
                                key: ValueKey(
                                    'content-${drive.path.join('/')}-${_grid ? 'g' : 'l'}'),
                                child: (_grid
                                    ? _GridContent(
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
                            ),
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
        // ===== Overlay de operación en curso (carga global) =====
        // ===== Carga NO bloqueante: subidas estilo Drive =====
        // (las subidas usan su propio panel con progreso por archivo;
        //  las demás operaciones muestran un spinner discreto, sin velo)
        if (drive.busy != DriveBusy.none &&
            drive.busy != DriveBusy.uploading)
          Positioned(
            top: 6,
            left: hPad,
            child: _BusyChip(label: drive.busyLabel),
          ),
        // ===== Panel de subidas estilo Drive (arriba a la derecha) =====
        if (drive.uploadJobs.isNotEmpty)
          Positioned(
            top: 6,
            right: hPad,
            child: _UploadsCard(drive: drive),
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

  final DriveBase drive;
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

  final DriveBase drive;
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
            // Entrada escalonada estilo Google Drive (fade + slide).
            return StaggeredItem(
              index: i,
              child: _GridItem(
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
              ),
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
  final DriveBase drive;
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

    // En MÓVIL el arrastre exige presión larga (~350ms): así el scroll no
    // mueve carpetas por accidente. En escritorio sigue siendo inmediato.
    final Widget Function(Widget child) buildDraggable = useLongPressDrag
        ? (child) => PressMoveDraggable<Object>(
            delay: AppConstants.longPressDragDelay,
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
            childWhenDragging: Opacity(opacity: .45, child: child),
            dragAnchorStrategy: pointerDragAnchorStrategy,
            child: child,
          )
        : (child) => Draggable<Object>(
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
            childWhenDragging: Opacity(opacity: .45, child: child),
            onDragStarted: () {
              // Si arrastras un elemento seleccionado en modo selección,
              // se arrastra toda la selección (el data ya lo decide).
            },
            dragAnchorStrategy: pointerDragAnchorStrategy,
            child: child,
          );
    return buildDraggable(
      DragTarget<Object>(
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
                // CLICK DERECHO: menú contextual (Abrir/Renombrar/Eliminar).
                onSecondaryTapUp: (details) => _showDriveItemContextMenu(
                  context,
                  details.globalPosition,
                  item: item,
                  onOpen: onOpen,
                  onRename: onRename,
                  onDelete: onDelete,
                ),
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
        // CLICK DERECHO: menú contextual.
        onSecondaryTapUp: (details) => _showDriveItemContextMenu(
          context,
          details.globalPosition,
          item: item,
          onOpen: onOpen,
          onRename: onRename,
          onDelete: onDelete,
        ),
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
  final DriveBase drive;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final src = drive.thumbSource(item, width: 480);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        onLongPress: onLongPress,
        // CLICK DERECHO: menú contextual.
        onSecondaryTapUp: (details) => _showDriveItemContextMenu(
          context,
          details.globalPosition,
          item: item,
          onOpen: onOpen,
          onRename: onRename,
          onDelete: onDelete,
        ),
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
                    _DriveThumb(
                      source: src,
                      isRemote: drive is DriveApiService,
                      size: double.infinity,
                      big: true,
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

/// Menú contextual de un ítem del drive (CLICK DERECHO en escritorio:
/// Abrir / Renombrar / Eliminar). [position] es en coordenadas globales.
Future<void> _showDriveItemContextMenu(
  BuildContext context,
  Offset position, {
  required DriveItem item,
  required VoidCallback onOpen,
  required VoidCallback onRename,
  required VoidCallback onDelete,
}) async {
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox?;
  final action = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      overlay?.size.width ?? position.dx,
      overlay?.size.height ?? position.dy,
    ),
    items: [
      const PopupMenuItem(
        value: 'open',
        height: 40,
        child: Row(children: [
          Icon(Icons.open_in_new_rounded, size: 17),
          SizedBox(width: 10),
          Text('Abrir'),
        ]),
      ),
      const PopupMenuItem(
        value: 'rename',
        height: 40,
        child: Row(children: [
          Icon(Icons.drive_file_rename_outline, size: 17),
          SizedBox(width: 10),
          Text('Renombrar'),
        ]),
      ),
      const PopupMenuItem(
        value: 'delete',
        height: 40,
        child: Row(children: [
          Icon(Icons.delete_outline, size: 17),
          SizedBox(width: 10),
          Text('Eliminar'),
        ]),
      ),
    ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'open':
      onOpen();
    case 'rename':
      onRename();
    case 'delete':
      onDelete();
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

  final DriveBase drive;
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
                // Entrada escalonada estilo Google Drive (fade + slide).
                return StaggeredItem(
                  index: i,
                  child: _ListRow(
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
                  ),
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
  final DriveBase drive;
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

    // En MÓVIL el arrastre exige presión larga (~350ms); en escritorio, inmediato.
    final Widget Function(Widget child) buildDraggable = useLongPressDrag
        ? (child) => PressMoveDraggable<Object>(
            delay: AppConstants.longPressDragDelay,
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
            childWhenDragging: Opacity(opacity: .45, child: child),
            dragAnchorStrategy: pointerDragAnchorStrategy,
            child: child,
          )
        : (child) => Draggable<Object>(
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
            childWhenDragging: Opacity(opacity: .45, child: child),
            dragAnchorStrategy: pointerDragAnchorStrategy,
            child: child,
          );
    return buildDraggable(
      DragTarget<Object>(
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
    final src = drive.thumbSource(item, width: 120);
    return InkWell(
      onTap: onTapSelect,
      onLongPress: onLongPress,
      // CLICK DERECHO: menú contextual.
      onSecondaryTapUp: (details) => _showDriveItemContextMenu(
        context,
        details.globalPosition,
        item: item,
        onOpen: onOpen,
        onRename: onRename,
        onDelete: onDelete,
      ),
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
                        child: _DriveThumb(
                          source: src,
                          isRemote: drive is DriveApiService,
                          size: 40,
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

  final DriveBase drive;
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
    _preloadNeighbors();
    _loadFull();
  }

  @override
  void initState() {
    super.initState();
    // Precarga las fotos vecinas para navegar sin esperas.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadNeighbors();
      _loadFull();
    });
  }

  @override
  void dispose() {
    // Al cerrar el visor: fuera el original de RAM (queda en caché de disco).
    final isRemote = widget.drive is DriveApiService;
    if (isRemote) {
      final api = widget.drive as DriveApiService;
      ImageMemory.evict(api.absolutePathOf(widget.images[_index]));
    } else {
      PaintingBinding.instance.imageCache.clear();
    }
    super.dispose();
  }

  // ---- Original por chunks detrás del preview ----
  File? _fullFile;
  double _fullProgress = 0;
  bool _fullLoading = false;
  String _fullKey = '';

  Future<void> _loadFull() async {
    final item = widget.images[_index];
    // El original por chunks usa File/caché de disco: solo en nativo.
    if (kWeb || item.isFolder || widget.drive is! DriveApiService) return;
    final api = widget.drive as DriveApiService;
    final key = api.absolutePathOf(item);
    if (_fullKey == key && _fullFile != null) return; // ya está
    _fullKey = key;
    _fullLoading = true;
    _fullProgress = 0;
    _fullFile = null;
    if (mounted) setState(() {});
    try {
      final f = await api.fetchOriginalChunked(item, onProgress: (p) {
        if (!mounted || key != _fullKey) return;
        _fullProgress = p;
        setState(() {});
      });
      if (!mounted || key != _fullKey) return;
      setState(() {
        _fullFile = f;
        _fullLoading = false;
      });
    } catch (_) {
      // El preview sigue siendo visible; el original es opcional.
      if (mounted && key == _fullKey) {
        setState(() => _fullLoading = false);
      }
    }
  }

  /// Baja a caché de red los previews (1600px) de la foto actual ±2.
  void _preloadNeighbors() {
    if (widget.drive is! DriveApiService) return;
    final api = widget.drive as DriveApiService;
    for (var d = -2; d <= 2; d++) {
      final i = (_index + d) % widget.images.length;
      if (i < 0) continue;
      final item = widget.images[i];
      if (item.isFolder) continue;
      precacheImage(
        NetworkImage(api.fullSource(item, previewWidth: 1600)),
        context,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.images[_index];
    final isRemote = widget.drive is DriveApiService;
    // Preview 1600px: baja ~0.5 MB en vez de los 10 MB del original.
    final src = widget.drive.fullSource(item, previewWidth: 1600);
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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 1) Preview ligero: se ve AL INSTANTE.
                    _DriveThumb(
                      source: src,
                      isRemote: isRemote,
                      size: double.infinity,
                      big: true,
                      contain: true,
                    ),
                    // 2) Original por chunks: aparece encima (nítido) al
                    //    completar, con transición suave.
                    if (_fullFile != null)
                      Image.file(
                        _fullFile!,
                        fit: BoxFit.contain,
                        frameBuilder: (c, child, frame, sync) =>
                            AnimatedOpacity(
                          opacity: frame == null ? 0 : 1,
                          duration: const Duration(milliseconds: 250),
                          child: child,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Progreso discreto de la descarga del original.
          if (_fullLoading)
            Positioned(
              left: 40,
              right: 40,
              bottom: 14,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _fullProgress > 0 ? _fullProgress : null,
                  minHeight: 4,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(Colors.white70),
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

// ===================== Subidas estilo Drive (progreso por archivo) =====================

/// Chip discreto para operaciones que no son subida (mover, copiar, etc.).
class _BusyChip extends StatelessWidget {
  const _BusyChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: .2),
      borderRadius: BorderRadius.circular(24),
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Panel flotante estilo Google Drive: cada archivo sube INDEPENDIENTE,
/// con miniatura, barra de progreso y % — sin bloquear la pantalla.
/// Escucha al drive DIRECTAMENTE (AnimatedBuilder sobre el ChangeNotifier)
/// para refrescar en tiempo real con cada bloque de bytes que avanza.
class _UploadsCard extends StatelessWidget {
  const _UploadsCard({required this.drive});

  final DriveBase drive;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: drive,
      builder: (context, _) => _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final jobs = drive.uploadJobs;
    // Conteos SIEMPRE visibles: en carga / completadas / con error.
    final active = jobs.where((j) => j.status == 'uploading').length;
    final done = jobs.where((j) => j.status == 'done').length;
    final failed = jobs.where((j) => j.status == 'error').length;
    // Progreso GLOBAL: bytes enviados vs. totales de los archivos en carga.
    final totalBytes = jobs.fold<int>(
        0, (a, j) => j.status == 'uploading' ? a + j.total : a);
    final sentBytes = jobs.fold<int>(
        0, (a, j) => j.status == 'uploading' ? a + j.sent : a);
    final globalPct =
        totalBytes > 0 ? (sentBytes / totalBytes).clamp(0.0, 1.0) : null;
    return Material(
      key: const ValueKey('uploads_card'),
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: .25),
      borderRadius: BorderRadius.circular(16),
      color: scheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 340),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
              child: Row(
                children: [
                  Icon(
                    active > 0
                        ? Icons.cloud_upload_outlined
                        : failed > 0
                            ? Icons.error_outline
                            : Icons.cloud_done_outlined,
                    size: 18,
                    color: active == 0 && failed > 0
                        ? scheme.error
                        : scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          active > 0
                              ? 'Subiendo ${jobs.length} '
                                  '${jobs.length == 1 ? 'foto' : 'fotos'}…'
                              : failed > 0
                                  ? '$done completada${done == 1 ? '' : 's'} · '
                                      '$failed con error${failed == 1 ? '' : 's'}'
                                  : '${jobs.length} subida${jobs.length == 1 ? '' : 's'} '
                                      'completada${jobs.length == 1 ? '' : 's'}',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (active > 0)
                          Text(
                            '$done completada${done == 1 ? '' : 's'}'
                            '${failed > 0 ? ' · $failed con error${failed == 1 ? '' : 's'}' : ''}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (active > 0)
                    TextButton.icon(
                      onPressed: drive.cancelAllUploads,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.cancel_outlined, size: 15),
                      label: const Text('Cancelar todo',
                          style: TextStyle(fontSize: 12)),
                    )
                  else
                    IconButton(
                      tooltip: 'Limpiar',
                      onPressed: drive.clearFinishedUploads,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                ],
              ),
            ),
            // Barra de progreso GLOBAL (todos los archivos en carga).
            if (active > 0 && globalPct != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: globalPct,
                          minHeight: 4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(globalPct * 100).toStringAsFixed(0)} %',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: jobs.length,
                itemBuilder: (context, i) {
                  final job = jobs[i];
                  return UploadJobTile(
                    job: job,
                    onCancel: job.status == 'uploading'
                        ? () => drive.cancelUpload(job.id)
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Miniatura que resuelve local (File) o remota (Image.network) según el drive.
/// Decodifica a baja resolución (cacheWidth/cacheHeight) para listar rápido.
class _DriveThumb extends StatelessWidget {
  const _DriveThumb({
    required this.source,
    required this.isRemote,
    this.size = 40,
    this.big = false,
    this.contain = false,
  });

  final String source;
  final bool isRemote;
  final double size;
  final bool big;
  final bool contain;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final ImageErrorWidgetBuilder error = big
        ? (_, _, _) => const Center(
              child: Icon(Icons.broken_image_outlined, size: 40),
            )
        : (_, _, _) => Icon(
              Icons.image_outlined,
              size: size * .5,
              color: scheme.onSurfaceVariant,
            );
    final fit = contain ? BoxFit.contain : BoxFit.cover;
    // Resolución de decodificación: miniaturas pequeñas; visor usa todo.
    final cachePx = big ? null : (size * dpr).round();
    Widget image;
    if (isRemote) {
      image = Image.network(
        source,
        width: big ? null : size,
        height: big ? null : size,
        fit: fit,
        cacheWidth: cachePx,
        errorBuilder: error,
        frameBuilder: (c, child, frame, sync) {
          // Ya venía del caché (sincrónico): mostrar directo, sin animar.
          if (sync) return child;
          // Aparición suave: visible SOLO cuando ya hay frame decodificado.
          // (El target SIEMPRE es 1; antes quedaba en 0 y las fotos de red
          // se veían invisibles hasta recargar con scroll.)
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            child: child,
          );
        },
      );
    } else {
      image = Image.file(
        File(source),
        width: big ? null : size,
        height: big ? null : size,
        fit: fit,
        cacheWidth: cachePx,
        errorBuilder: error,
      );
    }
    if (big) return ClipRRect(borderRadius: BorderRadius.circular(13), child: image);
    return Container(
      width: size,
      height: size,
      color: scheme.surfaceContainerHighest.withValues(alpha: .5),
      child: image,
    );
  }
}

/// Tarjeta de un trabajo de subida (miniatura + nombre + progreso).
/// PÚBLICA para poder probarla desde test/.
class UploadJobTile extends StatelessWidget {
  const UploadJobTile({super.key, required this.job, this.onCancel});

  final DriveUploadJob job;

  /// Si no es null, muestra el botón ✕ para cancelar esta subida.
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = job.total > 0 ? (job.sent / job.total).clamp(0.0, 1.0) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        children: [
          _DriveThumb(
            source: job.thumb,
            isRemote: false, // miniatura del archivo LOCAL
            size: 42,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                if (job.status == 'uploading')
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        pct == null ? '…' : '${(pct * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                      if (onCancel != null) ...[
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: IconButton(
                            tooltip: 'Cancelar',
                            padding: EdgeInsets.zero,
                            iconSize: 14,
                            onPressed: onCancel,
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                      ],
                    ],
                  )
                else if (job.status == 'cancelled')
                  Row(
                    children: [
                      Icon(Icons.cancel_outlined,
                          size: 14, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 5),
                      Text(
                        'Cancelada',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  )
                else if (job.status == 'done')
                  Row(
                    children: [
                      Icon(Icons.check_circle,
                          size: 14, color: scheme.primary),
                      const SizedBox(width: 5),
                      Text(
                        _sizeLabel(job.total),
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  )
                else
                  Expanded(
                    child: Text(
                      'Error: ${job.error ?? 'desconocido'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

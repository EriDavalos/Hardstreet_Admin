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
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        HardwareKeyboard,
        HapticFeedback,
        KeyEvent,
        KeyDownEvent,
        LogicalKeyboardKey;

import '../../app_constants.dart';
import '../../app_platform.dart';
import '../../drive_api_service.dart';
import '../../drive_downloader.dart';
import '../../image_memory.dart';
import '../../theme.dart';
import '../../widgets/anim.dart';
import '../../widgets/common.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/drive_file_visuals.dart';
import '../../widgets/drive_media_viewer.dart';
import '../../widgets/drive_thumb.dart';
import '../../widgets/hs_modal.dart';

/// Permiso del módulo Archivos ("drive" en la BD) para el rol logueado.
///
/// El widget solo OCULTA lo que el rol no puede hacer: si no tiene `create` no
/// hay "Nueva carpeta" ni "Subir archivos"; sin `update` no hay renombrar ni
/// mover; sin `delete` no hay eliminar; sin `download` no se puede sacar una
/// imagen. En modo degradado (el backend no respondió) se muestra todo, igual
/// que en el resto del panel, para no dejar la sección inservible.
bool _driveCan(DriveBase drive, String action) => drive.canDo(action);

// ============ Lecturas seguras del ScrollController compartido ============
//
// El AnimatedSwitcher del contenido mantiene un instante la carpeta/vista
// ANTERIOR y la NUEVA a la vez, y ambas se enganchan al MISMO controlador.
// Con dos scroll views adjuntos, `.offset` y `.animateTo` lanzan:
//   ScrollController attached to multiple scroll views.
// (justo "al cargar los targets" del drive). Estas lecturas devuelven 0 o
// no hacen nada durante esos 220 ms de transición.
extension SafeScrollX on ScrollController {
  /// true si el controlador está en UN solo scroll view (o en ninguno).
  bool get isSafe => positions.length <= 1;

  /// Offset actual, o 0 cuando no se puede leer (transición en curso).
  double get safeOffset => positions.length == 1 ? positions.single.pixels : 0;
}

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
    this.onHoldSelect,
    super.kind,
    super.gestureSettings,
  ) {
    _timer = Timer(delay, _delayPassed);
  }

  final Duration delay;

  /// Se dispara al cumplirse la presión (sin mover el dedo): marca el
  /// elemento como SELECCIONADO antes de que el arrastre arranque.
  final void Function()? onHoldSelect;

  Timer? _timer;
  GestureMultiDragStartCallback? _starter;
  bool _disposed = false;

  /// El dedo se movió más allá del slop ANTES del delay → NO es drag:
  /// se rechaza y el gesto queda libre (scroll del grid).
  void _reject() {
    _timer?.cancel();
    _timer = null;
    resolve(GestureDisposition.rejected);
  }

  /// Se cumplió el delay SIN salida del dedo: SELECCIONA el elemento (mismo
  /// efecto que la presión larga) y gana la arena de gestos; el arrastre
  /// arranca en el siguiente frame, ya con la selección actualizada. Así:
  /// sostener = seleccionar y quedar listo para arrastrar LA SELECCIÓN
  /// (mover el dedo arrastra el grupo; soltar sin mover deja la selección).
  void _delayPassed() {
    _timer = null;
    onHoldSelect?.call();
    // Gana la arena AHORA: el tap del InkWell queda rechazado (no desmarca
    // lo recién seleccionado al soltar) y accepted() programa el arranque.
    resolve(GestureDisposition.accepted);
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    if (_disposed) return;
    if (_timer == null) {
      // Presión cumplida: esperar UN frame para que el setState de la
      // selección reconstruya el widget y el payload del drag incluya a
      // TODO el grupo seleccionado (no solo el elemento presionado).
      _starter = starter;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final s = _starter;
        if (s != null && !_disposed) {
          _starter = null;
          s(initialPosition);
        }
      });
    } else {
      // Aún esperando el delay: guardar y arrancar en _delayPassed.
      _starter = starter;
    }
  }

  @override
  void checkForResolutionAfterMove() {
    if (pendingDelta == null) return;
    final slop = computeHitSlop(
      kind,
      gestureSettings,
    ).clamp(8.0, 24.0).toDouble();
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
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

/// Reconoce: mantener presionado [delay] y DESPUÉS mover el dedo para
/// arrastrar. Reemplaza a LongPressDraggable en móvil.
class PressMoveMultiDragGestureRecognizer extends MultiDragGestureRecognizer {
  PressMoveMultiDragGestureRecognizer({
    super.debugOwner,
    super.allowedButtonsFilter,
    this.delay = const Duration(milliseconds: 350),
    this.onHoldSelect,
  });

  /// Duración de la presión antes de habilitar el arrastre.
  final Duration delay;

  /// Selección al cumplirse la presión (ver [_PressMovePointerState]).
  final void Function()? onHoldSelect;

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) {
    return _PressMovePointerState(
      event.position,
      delay,
      onHoldSelect,
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
    this.onHoldSelect,
    super.childWhenDragging,
    super.dragAnchorStrategy,
  });

  /// Duración de la presión antes de habilitar el arrastre.
  final Duration delay;

  /// Al cumplirse la presión se invoca UNA vez: selecciona el elemento
  /// para que el arrastre lleve toda la selección.
  final VoidCallback? onHoldSelect;

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) {
    return PressMoveMultiDragGestureRecognizer(
        delay: delay,
        onHoldSelect: onHoldSelect,
      )
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
  const DrivePage({
    super.key,
    required this.drive,
    this.title = 'Mi Drive',
    this.subtitle,
    this.onBack,
    this.backTooltip = 'Volver',
    this.onRootTap,
    this.initialGrid = true,
  });

  final DriveBase drive;

  /// Título del encabezado. El Drive normal dice "Mi Drive"; una carpeta
  /// compartida abierta desde su módulo usa el nombre del compartido.
  final String title;

  /// Texto bajo el título cuando se está en la raíz (si es null, el de
  /// siempre).
  final String? subtitle;

  /// Si no es null, se dibuja una flecha para volver (el Drive normal no la
  /// lleva: es una sección del menú).
  final VoidCallback? onBack;
  final String backTooltip;

  /// Qué hace la MIGA RAÍZ al tocarla. Por defecto vuelve a la raíz de ESTE
  /// drive; el módulo de Archivos compartidos lo usa para volver a su listado
  /// (la raíz de ese drive es el propio módulo).
  final VoidCallback? onRootTap;

  /// Vista con la que se abre (cuadrícula o lista): el módulo de Archivos
  /// compartidos le pasa la que el usuario tenía puesta en el listado.
  final bool initialGrid;

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

  // ---- Panel inferior de actividad ---------------------------------
  // Avisos de operaciones (éxito en VERDE, error en ROJO) que viven en la
  // ventanita inferior derecha junto a subidas y descargas. Se puede
  // ocultar (minimizar) y se reabre solo cuando llega un aviso nuevo.
  final List<_DriveNotice> _notices = [];
  bool _panelOpen = true;

  // ---- Fotos recién subidas --------------------------------------------
  // Copia LOCAL (ruta de origen) por nombre: la cuadrícula la muestra al
  // instante mientras el servidor genera la miniatura, así la foto aparece
  // "ahí mismo" y no como un recuadro vacío.
  final Map<String, String> _localPreviews = {};
  // Nombres que YA existían cuando empezó el lote de subida.
  final Set<String> _preUploadNames = {};
  // Entrada escalonada SOLO para el contenido con el que se abre la carpeta;
  // lo que aparece después (una subida recién terminada) se muestra directo.
  final Set<String> _seenNames = {};
  final Set<String> _noEntrance = {};
  bool _folderLoaded = false;

  @override
  void initState() {
    super.initState();
    _grid = widget.initialGrid;
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
    if (route != null && !route.isCurrent)
      return false; // hay un diálogo abierto

    if (event.logicalKey == LogicalKeyboardKey.escape &&
        (_selectMode || _selected.isNotEmpty)) {
      _clearSelection();
      setState(() {
        _marqueeStart = null;
        _marqueeRect = null;
      });
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete &&
        _selected.isNotEmpty &&
        _driveCan(widget.drive, 'delete')) {
      _deleteItems(_selected.toList());
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyC &&
        HardwareKeyboard.instance.isControlPressed &&
        _selected.isNotEmpty) {
      setState(() => _clipboardNames = _selected.toList(growable: false));
      _snack(
        '${_clipboardNames.length} elemento${_clipboardNames.length == 1 ? '' : 's'} copiado${_clipboardNames.length == 1 ? '' : 's'} al portapapeles',
      );
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyV &&
        HardwareKeyboard.instance.isControlPressed &&
        _clipboardNames.isNotEmpty &&
        _driveCan(widget.drive, 'create')) {
      _pasteClipboard();
      return true;
    }
    return false;
  }

  /// Ctrl+V: pega lo copiado en la carpeta actual.
  Future<void> _pasteClipboard() async {
    if (!_driveCan(widget.drive, 'create')) {
      _snack('Tu rol no puede agregar archivos al Drive', error: true);
      return;
    }
    final names = List.of(_clipboardNames);
    final result = await _guarded(
      () => widget.drive.copyItems(names, widget.drive.path),
    );
    if (result == null) return;
    if (result.copied > 0) {
      _snack(
        '${result.copied} elemento${result.copied == 1 ? '' : 's'} pegado${result.copied == 1 ? '' : 's'}',
      );
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
      _localPreviews.clear();
      _preUploadNames.clear();
      _seenNames.clear();
      _noEntrance.clear();
      _folderLoaded = false;
    }
    _trackEntrance();
    _registerLocalPreviews();
    setState(() {});
  }

  /// Decide qué elementos llevan animación de entrada.
  ///
  /// El primer listado de cada carpeta entra escalonado (efecto de apertura).
  /// Lo que aparece DESPUÉS —una foto recién subida— se muestra ya puesto,
  /// sin fundido: la única animación que se ve es la de la imagen al bajar.
  void _trackEntrance() {
    final drive = widget.drive;
    if (drive.loading) return;
    final names = drive.visibleItems.map((i) => i.name);
    if (!_folderLoaded) {
      _seenNames.addAll(names);
      _folderLoaded = true;
      return;
    }
    // Todo lo que aparece DESPUÉS de la carga inicial (una foto recién subida)
    // se muestra ya puesto: la única animación que se ve es la de la imagen al
    // bajar del servidor.
    for (final n in names) {
      if (_seenNames.add(n)) _noEntrance.add(n);
    }
  }

  /// Asocia a cada trabajo terminado la COPIA LOCAL de su archivo para que la
  /// cuadrícula la pinte al instante. Solo si el nombre no existía antes de
  /// subir: si el servidor lo renombró por colisión, simplemente no se usa
  /// (nunca se muestra una foto bajo el nombre de otra).
  void _registerLocalPreviews() {
    for (final job in widget.drive.uploadJobs) {
      if (job.status != 'done' || job.thumb.isEmpty) continue;
      if (_preUploadNames.contains(job.name)) continue;
      _localPreviews[job.name] = job.thumb;
    }
  }

  /// Elementos del drive que están seleccionados (en orden de la cuadrícula).
  List<DriveItem> _selectedItems() => widget.drive.items
      .where((i) => _selected.contains(i.name))
      .toList(growable: false);

  /// Descarga la lista dada: 1 archivo suelto; varios (o carpetas) en ZIP.
  Future<void> _downloadItems(List<DriveItem> items) => _guarded(() async {
    // Candado de respaldo: cualquier camino que se me escape en la UI
    // (visor, menús, panel de descargas) queda cortado aquí.
    if (!_driveCan(widget.drive, 'download')) {
      _snack('Tu rol no puede descargar archivos del Drive', error: true);
      return;
    }
    await downloadDriveSelection(context, drive: widget.drive, items: items);
  });

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
        final a = (_anchorIndex >= 0 && _anchorIndex < names.length)
            ? _anchorIndex
            : 0;
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
    final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
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
      final isDouble =
          hitName == _lastClickItem &&
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
    final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(event.position);
    final size = box.size;
    final clamped = Offset(
      local.dx.clamp(0.0, size.width),
      local.dy.clamp(-200.0, double.infinity),
    );
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
    if (!_driveCan(widget.drive, 'create')) {
      _snack('Tu rol no puede subir archivos al Drive', error: true);
      return;
    }
    final files = details.files
        .where((f) => widget.drive.hasUploadExt(f.name))
        .toList();
    if (files.isEmpty) {
      _snack(
        'Solo se pueden subir fotos (jpg, png, gif, webp, bmp), RAW '
        '(dng, cr2, cr3…) o vídeos (mp4, mov, webm…)',
        error: true,
      );
      return;
    }
    // En el navegador lo soltado son BLOBS (sin ruta en el disco): se suben sus
    // bytes, igual que con el selector.
    await _startUpload([
      for (final f in files) f.path,
    ], files: kIsWeb ? files : null);
  }

  /// Flujo completo de subida: detecta duplicados → pregunta qué hacer →
  /// sube (renombrando o sobrescribiendo) o cancela.
  Future<void> _startUpload(List<String> paths, {List<XFile>? files}) async {
    // Nombres de los archivos a subir (acepta / o \ mezclados). En el
    // navegador la "ruta" es un Blob, así que el nombre lo trae el XFile.
    String nameOf(String p) => p.split(RegExp(r'[\\/]')).last;
    String nameOfFile(XFile f) => nameOf(f.name.isNotEmpty ? f.name : f.path);
    // Lo que YA está en la carpeta: lo que suene igual no podrá asociarse a
    // una miniatura local (podría ser otro archivo).
    for (final it in widget.drive.items) {
      _preUploadNames.add(it.name);
    }
    List<String> dups;
    try {
      dups = await widget.drive.filterExisting([
        if (files != null)
          for (final f in files) nameOfFile(f)
        else
          for (final p in paths) nameOf(p),
      ]);
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
      () => files != null
          ? widget.drive.uploadFromFiles(files, overwrite: overwrite)
          : widget.drive.uploadFromPaths(paths, overwrite: overwrite),
    );
    if (saved == null) return; // el error ya se mostró
    // Que las fotos recién subidas se vean YA con su copia local.
    _registerLocalPreviews();
    final pending = widget.drive.uploadJobs
        .where((j) => j.status == 'error')
        .length;
    final errTail = pending > 0
        ? ' · $pending con error (puedes resubirla${pending == 1 ? '' : 's'} desde el panel)'
        : '';
    if (saved > 0) {
      final what = saved == 1 ? 'archivo subido' : 'archivos subidos';
      _snack('$saved $what a "${widget.drive.locationLabel}"$errTail');
    }
  }

  /// Modal: ¿renombrar, sobrescribir o cancelar los duplicados?
  /// Devuelve true = sobrescribir, false = renombrar, null = cancelar.
  Future<bool?> _askDuplicateAction(List<String> dups) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
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
                borderRadius: BorderRadius.circular(22),
              ),
              contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: .10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.copy_all_rounded,
                      color: scheme.primary,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    dups.length == 1
                        ? 'El archivo ya existe'
                        : '${dups.length} archivos ya existen',
                    textAlign: TextAlign.center,
                    style: Theme.of(ctx).textTheme.titleMedium
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
                      icon: const Icon(
                        Icons.auto_awesome_motion_rounded,
                        size: 17,
                      ),
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
          scale: Tween<double>(
            begin: .92,
            end: 1,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
          child: child,
        ),
      ),
    );
  }

  // ==================== Mensajes ====================

  /// Aviso al PANEL inferior de actividad (verde = cumplió, rojo = error).
  /// El panel se reabre solo si estaba oculto.
  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _notices.insert(0, _DriveNotice(message, error));
      if (_notices.length > 40) _notices.removeLast();
      _panelOpen = true;
    });
  }

  void _showErrors(List<String> errors) {
    if (errors.isEmpty) return;
    _snack(errors.first, error: true);
  }

  // ==================== Acciones ====================

  Future<void> _upload() async {
    try {
      // El selector debe enseñar FOTOS Y VÍDEOS en TODAS las plataformas:
      // Windows/escritorio usa `extensions`, Android usa `mimeTypes`, Apple
      // usa `uniformTypeIdentifiers` y la web `webWildCards`. Antes solo iban
      // las extensiones, y en las plataformas que no las leen el diálogo se
      // quedaba con las imágenes (un vídeo ni siquiera se podía elegir).
      const typeGroup = XTypeGroup(
        label: 'Fotos y vídeos',
        extensions: [
          // Fotos normales (+ HEIC/HEIF del iPhone y AVIF/TIFF de cámara).
          'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp',
          'heic', 'heif', 'avif', 'tif', 'tiff',
          // RAW de cámara (el servidor les extrae su vista previa).
          'dng', 'cr2', 'cr3', 'crw', 'nef', 'nrw', 'arw', 'srf', 'sr2',
          'raf', 'rw2', 'orf', 'pef', 'srw', 'raw', 'rwl', 'dcr', 'kdc',
          '3fr', 'erf', 'mef', 'mos', 'mrw', 'x3f', 'iiq',
          // Vídeos: el Drive los lista, los reproduce y los sube igual que
          // las fotos (en trozos si son grandes).
          'mp4', 'm4v', 'mov', 'webm', 'mkv', 'avi', '3gp', 'wmv', 'mpeg',
          'mpg', 'ogv',
          // Cámaras de video: AVCHD (MTS/M2TS), DV, FLV, Insta360/DJI.
          'mts', 'm2ts', 'm2v', 'flv', 'vob', 'mp2', 'mxf', 'insv', 'lrv',
        ],
        mimeTypes: ['image/*', 'video/*'],
        uniformTypeIdentifiers: ['public.image', 'public.movie'],
        webWildCards: ['image/*', 'video/*'],
      );
      final files = await openFiles(acceptedTypeGroups: [typeGroup]);
      if (files.isEmpty) {
        _snack('No se seleccionaron archivos');
        return;
      }
      // Se pasan los XFile (no solo su ruta): en el navegador la ruta es un
      // Blob y la subida tiene que ir por bytes.
      await _startUpload(files.map((f) => f.path).toList(), files: files);
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
      title: item.isFolder ? 'Renombrar carpeta' : 'Renombrar archivo',
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
    final result = await _guarded(() => widget.drive.deleteItems(names));
    _clearSelection();
    if (result == null) return;
    if (result.deleted > 0) {
      _snack(
        '${result.deleted} elemento${result.deleted == 1 ? '' : 's'} eliminado${result.deleted == 1 ? '' : 's'}',
      );
    }
    _showErrors(result.errors);
  }

  /// Diálogo con navegador de carpetas para elegir destino de mover/copiar.
  Future<List<String>?> _pickDestination({required bool move}) async {
    final drive = widget.drive;
    var current = List.of(drive.path);
    var confirmed = false;

    await showHsModal<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final folders = drive.listFolders(current);
          final atRoot = current.isEmpty;
          // En móvil el selector usa todo el alto disponible.
          final phone = hsIsPhone(ctx);
          // Una carpeta no puede soltarse dentro de sí misma: si el destino
          // actual es una de las carpetas seleccionadas, bloquear confirmar.
          final isInvalid = _selected.contains(current.lastOrNull);

          return AlertDialog(
            title: Text(move ? 'Mover a...' : 'Copiar a...'),
            content: SizedBox(
              width: phone ? double.infinity : 380,
              height: phone ? double.infinity : 320,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Ruta actual
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest
                          .withValues(alpha: .5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      [drive.rootLabel, ...current].join('  /  '),
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
                                      0,
                                      current.length - 1,
                                    );
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
    final result = await _guarded(
      () => widget.drive.moveItems(names, targetPath),
    );
    _clearSelection();
    if (result == null) return;
    if (result.moved > 0) {
      _snack(
        '${result.moved} elemento${result.moved == 1 ? '' : 's'} movido${result.moved == 1 ? '' : 's'}',
      );
    }
    _showErrors(result.errors);
  }

  Future<void> _copySelected(List<String> targetPath) async {
    final names = _selected.toList(growable: false);
    final result = await _guarded(
      () => widget.drive.copyItems(names, targetPath),
    );
    _clearSelection();
    if (result == null) return;
    if (result.copied > 0) {
      _snack(
        '${result.copied} elemento${result.copied == 1 ? '' : 's'} copiado${result.copied == 1 ? '' : 's'}',
      );
    }
    _showErrors(result.errors);
  }

  // ==================== Navegación / drag targets ====================

  void _open(DriveItem item) {
    if (item.isFolder) {
      // Un toque mientras la carpeta anterior SIGUE cargando se atiende: este
      // freno dejaba el Drive sin responder a entrar en NINGUNA carpeta hasta
      // que terminara la carga en curso (con muchas miniaturas en camino, un
      // buen rato). Que el toque sea sobre un elemento del listado que se ve
      // lo garantiza `DriveBase.openFolder` —navega desde la carpeta del
      // listado en pantalla—, así que ya no hace falta: era él el que
      // provocaba "Mi Drive / X / X".
      _clearSelection();
      widget.drive.openFolder(item.name);
    } else {
      _openViewer(item);
    }
  }

  /// Abre el archivo tocado con EL VISOR QUE LE CORRESPONDE.
  ///
  /// Antes se pasaba cualquiera a `showDriveImageViewer` y, al tocar un vídeo
  /// o un PDF, quedaba una pantalla negra: el visor solo entiende de fotos.
  /// Ahora la carpeta decide:
  ///
  ///   * FOTO   → visor de imágenes (zoom, flechas, descarga).
  ///   * VÍDEO/AUDIO → reproductor, pudiendo pasar al siguiente de la carpeta.
  ///   * PDF/TEXTO/OTROS → su ficha del visor de archivos (texto, PDF o
  ///     descargar/abrir con el sistema).
  void _openViewer(DriveItem item) {
    final files = widget.drive.visibleItems
        .where((i) => !i.isFolder)
        .toList(growable: false);
    // Descargar SIN salir del visor. Sin permiso de descarga, el visor ni
    // siquiera muestra el botón.
    final onDownload = _driveCan(widget.drive, 'download')
        ? (DriveItem it) => _downloadItems([it])
        : null;
    // FOTOS (también RAW): el visor de imágenes. Un TIFF/CR3 se ve con la
    // vista previa que genera el servidor, no con el original.
    if (item.isPhoto) {
      final photos = files.where((i) => i.isPhoto).toList(growable: false);
      final index = photos.indexWhere((i) => i.name == item.name);
      showDriveImageViewer(
        context,
        drive: widget.drive,
        images: photos,
        initialIndex: index < 0 ? 0 : index,
        onDownload: onDownload,
      );
      return;
    }
    // Un vídeo o una canción se abren con la LISTA de los que hay en la
    // carpeta: así se pasa al siguiente sin cerrar el reproductor.
    final list = item.isPlayable
        ? files.where((i) => i.isPlayable).toList(growable: false)
        : <DriveItem>[item];
    final index = list.indexWhere((i) => i.name == item.name);
    showDriveFileViewer(
      context,
      drive: widget.drive,
      item: item,
      playlist: list.isEmpty ? [item] : list,
      initialIndex: index < 0 ? 0 : index,
      onDownload: onDownload,
    );
  }

  void _onItemTap(DriveItem item) => _onCardTap(item);

  /// Menú contextual (CLIC DERECHO).
  ///
  /// * Un solo elemento: Abrir / Descargar / Renombrar / Eliminar.
  /// * Varios seleccionados (clic derecho sobre uno de ellos): SOLO
  ///   Descargar/Eliminar la SELECCIÓN — así no hay duda de sobre qué actúa.
  Future<void> _openItemMenu(DriveItem item, Offset position) async {
    final many = _selected.length > 1 && _selected.contains(item.name);
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    // Etiqueta flexible: los textos largos ("Descargar 12 seleccionadas") se
    // recortan con puntos suspensivos en vez de desbordar el menú.
    PopupMenuItem<String> entry(String value, IconData icon, String label) =>
        PopupMenuItem<String>(
          value: value,
          height: 40,
          child: Row(
            children: [
              Icon(icon, size: 17),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay?.size.width ?? position.dx,
        overlay?.size.height ?? position.dy,
      ),
      constraints: const BoxConstraints(minWidth: 210, maxWidth: 340),
      // Solo lo que el rol puede hacer: el menú no ofrece acciones que el
      // backend rechazaría.
      items: many
          ? [
              if (_driveCan(widget.drive, 'download'))
                entry(
                  'download-many',
                  Icons.download_rounded,
                  'Descargar ${_selected.length} seleccionadas',
                ),
              if (_driveCan(widget.drive, 'delete'))
                entry(
                  'delete-many',
                  Icons.delete_outline,
                  'Eliminar ${_selected.length} seleccionadas',
                ),
            ]
          : [
              entry('open', Icons.open_in_new_rounded, 'Abrir'),
              if (_driveCan(widget.drive, 'download'))
                entry('download', Icons.download_rounded, 'Descargar'),
              if (_driveCan(widget.drive, 'update'))
                entry('rename', Icons.drive_file_rename_outline, 'Renombrar'),
              if (_driveCan(widget.drive, 'delete'))
                entry('delete', Icons.delete_outline, 'Eliminar'),
            ],
    );
    if (action == null || !mounted) return;
    if (!_mountedCanAct(action)) return;
    switch (action) {
      case 'open':
        // Abrir de verdad: _onCardTap ignora el ratón (solo selecciona), así
        // que el menú llama directo a la apertura.
        _open(item);
      case 'download':
        _downloadItems([item]);
      case 'rename':
        _rename(item);
      case 'delete':
        _delete(item);
      case 'download-many':
        _downloadItems(_selectedItems());
      case 'delete-many':
        _deleteItems(_selected.toList());
    }
  }

  /// ¿El rol todavía puede ejecutar [action]? (doble comprobación al vuelo:
  /// los permisos pueden recargarse mientras el menú está abierto).
  bool _mountedCanAct(String action) {
    final need = switch (action) {
      'download' || 'download-many' => 'download',
      'rename' => 'update',
      'delete' || 'delete-many' => 'delete',
      _ => null,
    };
    if (need == null) return true; // Abrir solo necesita poder ver.
    if (_driveCan(widget.drive, need)) return true;
    _snack('Tu rol no tiene permitido eso en el Drive', error: true);
    return false;
  }

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
    // Mover es editar: sin permiso, el arrastre no hace nada.
    if (!_driveCan(widget.drive, 'update')) {
      _snack('Tu rol no puede mover archivos del Drive', error: true);
      return;
    }
    // Excluir la propia carpeta destino de la selección.
    names = names.where((n) => n != target.name).toList(growable: false);
    if (names.isEmpty) return;
    _doMove(names, [...widget.drive.path, target.name]);
  }

  Future<void> _doMove(List<String> names, List<String> targetPath) async {
    // Si el servidor rechaza el movimiento (permiso del compartido, la app del
    // dueño cerrada, red…) hay que DECIRLO: antes la excepción se perdía y
    // arrastrar y soltar parecía no hacer nada.
    final result = await _guarded(
      () => widget.drive.moveItems(names, targetPath),
    );
    _clearSelection();
    if (result == null) return;
    if (result.moved > 0) {
      _snack(
        '${result.moved} elemento${result.moved == 1 ? '' : 's'} movido${result.moved == 1 ? '' : 's'} a "${targetPath.isEmpty ? widget.drive.rootLabel : targetPath.last}"',
      );
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
    return showHsModal<String>(
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
      marqueeOffset = contentBox.localToGlobal(Offset.zero, ancestor: stackBox);
    }

    // Botón "atrás" del SISTEMA (Android): mientras no estemos en la raíz del
    // drive, NO cierra la app — vuelve a la carpeta padre. En la raíz el
    // sistema procede con normalidad (minimiza la app), salvo cuando la página
    // es parte de otra (una carpeta compartida abierta dentro del módulo
    // Archivos compartidos): ahí [onBack] vuelve al listado.
    return PopScope(
      canPop: drive.path.isEmpty && widget.onBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (drive.path.isNotEmpty) {
          widget.drive.goUp();
        } else {
          widget.onBack?.call();
        }
      },
      child: DropTarget(
        onDragEntered: (_) {
          // Al arrastrar desde el explorador, sube la vista al inicio para
          // que se vea la zona de destino de inmediato.
          if (_scrollController.isSafe && _scrollController.safeOffset > 0) {
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
        child: Stack(
          children: [
            // El Listener va DENTRO del Stack y envuelve SOLO el contenido: las
            // ventanas flotantes (actividad, barra de selección) quedan por encima
            // y sus clics ya no se cuelan al fondo —antes, tocar la ventanita de
            // actividad también seleccionaba tarjetas y hasta abría carpetas de
            // detrás, y arrastrar en ella dibujaba la marquesina.
            Listener(
              onPointerDown: _onContentPointerDown,
              onPointerMove: _onContentPointerMove,
              onPointerUp: _onContentPointerUp,
              onPointerCancel: _onContentPointerUp,
              child: Column(
                children: [
                  // ===== Header hero: tarjeta plana con degradado sutil y
                  // círculos geométricos (mismo lenguaje visual que los módulos) ==
                  Padding(
                    padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 0),
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          isCompact ? 18 : 22,
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            scheme.primary.withValues(alpha: .08),
                            scheme.primary.withValues(alpha: .015),
                          ],
                        ),
                        border: Border.all(
                          color: scheme.primary.withValues(alpha: .16),
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            right: -40,
                            top: -52,
                            child: Container(
                              width: 150,
                              height: 150,
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: .05),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          Positioned(
                            left: -46,
                            bottom: -64,
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: .035),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(isCompact ? 16 : 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    PopIn(
                                      child: Container(
                                        padding: const EdgeInsets.all(3.5),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: scheme.primary.withValues(
                                              alpha: .28,
                                            ),
                                          ),
                                        ),
                                        child: Container(
                                          width: isCompact ? 48 : 54,
                                          height: isCompact ? 48 : 54,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: LinearGradient(
                                              colors: [
                                                AppColors.brand,
                                                AppColors.brandDark,
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.folder_copy_outlined,
                                            color: Colors.white,
                                            size: isCompact ? 24 : 26,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              if (widget.onBack != null) ...[
                                                IconButton(
                                                  tooltip: widget.backTooltip,
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  onPressed: widget.onBack,
                                                  icon: const Icon(
                                                    Icons.arrow_back_rounded,
                                                    size: 20,
                                                  ),
                                                ),
                                                const SizedBox(width: 2),
                                              ],
                                              Flexible(
                                                child: Text(
                                                  widget.title,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .headlineSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            drive.path.isEmpty ||
                                                    drive.locationLabel ==
                                                        'Mi Drive'
                                                ? (widget.subtitle ??
                                                      'Raíz del almacenamiento')
                                                : drive.locationLabel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Crear (carpeta/subir) solo con permiso: las
                                    // acciones que el rol no tiene NO se dibujan.
                                    if (!isCompact) ...[
                                      if (_driveCan(
                                        widget.drive,
                                        'create',
                                      )) ...[
                                        const SizedBox(width: 16),
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
                                          icon: const Icon(
                                            Icons.upload_file,
                                            size: 18,
                                          ),
                                          label: const Text('Subir archivos'),
                                        ),
                                      ],
                                    ] else ...[
                                      if (_driveCan(
                                        widget.drive,
                                        'create',
                                      )) ...[
                                        _RoundAction(
                                          icon:
                                              Icons.create_new_folder_outlined,
                                          tooltip: 'Nueva carpeta',
                                          onTap: _newFolder,
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      // Sin botón de recargar: en la app se
                                      // recarga deslizando hacia abajo (en el
                                      // escritorio, cada acción ya refresca).
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _searchController,
                                        onChanged: drive.setSearch,
                                        decoration: const InputDecoration(
                                          hintText: 'Buscar en esta carpeta',
                                          prefixIcon: Icon(
                                            Icons.search,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Tooltip(
                                      message: _grid
                                          ? 'Vista de lista'
                                          : 'Vista de cuadrícula',
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
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // ===== Ruta actual: "Mi Drive > PerlaMolina > ..." (también en
                  // móvil, donde sirve para saltar a cualquier carpeta padre) =====
                  //
                  // En una carpeta COMPARTIDA la ruta se dibuja también en la raíz
                  // (`onRootTap != null`): la primera miga es el MÓDULO del que se
                  // abrió y, al tocarla, se vuelve a su listado.
                  if (drive.path.isNotEmpty || widget.onRootTap != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _Breadcrumbs(
                          drive: drive,
                          onDropMove: _doMove,
                          onRootTap: widget.onRootTap,
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
                        // Aviso discreto: si un refresco falló se conserva el listado
                        // en pantalla, pero se dice que puede estar viejo (antes se
                        // reemplazaba el directorio entero por "Error").
                        if (drive.error != null) ...[
                          _CountPill(
                            icon: Icons.cloud_off_outlined,
                            label: 'Sin conexión · reintentar',
                            color: scheme.error,
                            onTap: drive.refresh,
                          ),
                          const SizedBox(width: 8),
                        ],
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
                    // En el celular se recarga DESLIZANDO hacia abajo (ya no hay
                    // botón de recargar en el encabezado).
                    child: RefreshIndicator(
                      onRefresh: drive.refresh,
                      child: drive.loading && drive.items.isEmpty
                          ? const Center(child: CircularProgressIndicator())
                          // El panel bloqueante solo cuando NO hay nada que mostrar:
                          // si ya se ve una carpeta, se queda a la vista.
                          : drive.error != null && drive.items.isEmpty
                          ? EmptyState(
                              icon: Icons.folder_off_outlined,
                              title: 'Error',
                              message: drive.error!,
                              actionLabel: 'Reintentar',
                              onAction: drive.refresh,
                            )
                          : drive.visibleItems.isEmpty
                          ? EmptyState(
                              icon: drive.scoped && drive.path.isEmpty
                                  ? Icons.folder_off_outlined
                                  : Icons.folder_open_rounded,
                              title: drive.search != null
                                  ? 'Sin resultados'
                                  : drive.scoped && drive.path.isEmpty
                                  ? 'Aún no se te comparte ninguna carpeta'
                                  : 'Esta carpeta está vacía',
                              message: drive.search != null
                                  ? 'No hay coincidencias en esta carpeta.'
                                  : drive.scoped && drive.path.isEmpty
                                  ? 'Tu fotógrafo todavía no compartió carpetas '
                                        'contigo. En cuanto las asigne a tus '
                                        'paquetes, aparecerán aquí.'
                                  : 'Sube fotos o vídeos, o crea una carpeta para organizar tu contenido.',
                              // Sin permiso de crear, la tarjeta vacía invita
                              // pero no ofrece el botón.
                              actionLabel:
                                  drive.scoped && drive.path.isEmpty ||
                                      !_driveCan(widget.drive, 'create')
                                  ? null
                                  : 'Subir archivos',
                              onAction:
                                  drive.scoped && drive.path.isEmpty ||
                                      !_driveCan(widget.drive, 'create')
                                  ? null
                                  : _upload,
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
                                  'content-${drive.path.join('/')}-${_grid ? 'g' : 'l'}',
                                ),
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
                                        onContextMenu: _openItemMenu,
                                        onDownload: (item) =>
                                            _downloadItems([item]),
                                        localPreviews: _localPreviews,
                                        noEntrance: _noEntrance,
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
                                        onContextMenu: _openItemMenu,
                                        onDownload: (item) =>
                                            _downloadItems([item]),
                                        localPreviews: _localPreviews,
                                        noEntrance: _noEntrance,
                                        scrollController: _scrollController,
                                      )),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
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
                            horizontal: 28,
                            vertical: 20,
                          ),
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
                              const Icon(
                                Icons.upload_rounded,
                                color: Colors.white,
                                size: 34,
                              ),
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
            // ===== Capa de fuera de la ventanita de actividad =====
            // Con la ventanita ABIERTA se pone delante del contenido (la misma
            // idea que el panel de la campanita de avisos): un clic de FUERA la
            // cierra y NUNCA llega a la cuadrícula —antes, tocar alrededor de la
            // ventanita seleccionaba o abría las fotos de detrás. Va por DEBAJO de
            // la barra de selección para que esa barra siga funcionando.
            if (_panelOpen &&
                (drive.uploadJobs.isNotEmpty ||
                    drive.downloadJobs.isNotEmpty ||
                    _notices.isNotEmpty))
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _panelOpen = false),
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
                  can: drive.canDo,
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
                  onDownload: () => _downloadItems(_selectedItems()),
                  onDelete: () =>
                      _guarded(() => _deleteItems(_selected.toList())),
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
            // ===== Panel inferior de transferencias y avisos (ocultable) =====
            // Subidas, descargas y notificaciones (verde/rojo) viven juntos en
            // una ventanita abajo a la derecha, con botón para minimizarla.
            if (drive.uploadJobs.isNotEmpty ||
                drive.downloadJobs.isNotEmpty ||
                _notices.isNotEmpty)
              Positioned(
                right: hPad,
                bottom: (_selectMode && _selected.isNotEmpty) ? 74 : 10,
                child: _ActivityPanel(
                  open: _panelOpen,
                  drive: drive,
                  notices: _notices,
                  onToggle: () => setState(() => _panelOpen = !_panelOpen),
                  onClearNotices: () => setState(() => _notices.clear()),
                  onDismissNotice: (i) => setState(() {
                    if (i >= 0 && i < _notices.length) _notices.removeAt(i);
                  }),
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
  const _CountPill({
    required this.icon,
    required this.label,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;

  /// Tinte del icono (por defecto, el primario del tema).
  final Color? color;

  /// Si no es null, la píldora es tocable (p. ej. para reintentar).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color ?? scheme.primary),
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
    if (onTap == null) return pill;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: pill,
    );
  }
}

// ===================== Barra de selección =====================

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.can,
    required this.count,
    required this.compact,
    required this.onClear,
    required this.onSelectAll,
    required this.onMove,
    required this.onCopy,
    required this.onDelete,
    required this.onDownload,
  });

  /// Permisos del drive que se está viendo.
  final bool Function(String action) can;
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
                    horizontal: 10,
                    vertical: 4,
                  ),
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
                    foregroundColor: Colors.white.withValues(alpha: .92),
                  ),
                  child: const Text('Todos'),
                ),
                const SizedBox(width: 2),
                // Cada acción exige su permiso (rol del Drive, o lo que
                // dio el dueño de una carpeta compartida).
                if (can('update'))
                  _BarAction(
                    tooltip: 'Mover a...',
                    icon: Icons.drive_file_move_outline,
                    onPressed: onMove,
                  ),
                if (can('create'))
                  _BarAction(
                    tooltip: 'Copiar a...',
                    icon: Icons.copy_all_outlined,
                    onPressed: onCopy,
                  ),
                if (can('download'))
                  _BarAction(
                    tooltip: 'Descargar',
                    icon: Icons.download_rounded,
                    onPressed: onDownload,
                  ),
                if (can('delete'))
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

class _Breadcrumbs extends StatefulWidget {
  const _Breadcrumbs({
    required this.drive,
    required this.onDropMove,
    this.onRootTap,
  });

  final DriveBase drive;
  final void Function(List<String> names, List<String> targetPath) onDropMove;

  /// Tocar la miga RAÍZ (null = volver a la raíz del drive).
  final VoidCallback? onRootTap;

  @override
  State<_Breadcrumbs> createState() => _BreadcrumbsState();
}

class _BreadcrumbsState extends State<_Breadcrumbs> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _jumpToEnd();
  }

  @override
  void didUpdateWidget(covariant _Breadcrumbs old) {
    super.didUpdateWidget(old);
    if (old.drive.path.join('/') != widget.drive.path.join('/')) {
      _jumpToEnd();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Al entrar a una carpeta se enseña SU miga (el final), no el principio:
  /// con una ruta larga lo que importa es dónde estás, y hacia atrás se
  /// desliza. Antes las migas usaban Wrap y, cuando no cabían, bajaban a una
  /// segunda línea y empujaban todo el contenido.
  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  /// Acorta un nombre largo sin perder el principio ni el final
  /// ("SesionPreviaDeLaBodaDeAna" → "SesionPre…aDeAna").
  static String _short(String s, {int max = 24}) {
    if (s.length <= max) return s;
    final head = (max * .55).floor();
    final tail = max - head - 1;
    return '${s.substring(0, head)}…${s.substring(s.length - tail)}';
  }

  @override
  Widget build(BuildContext context) {
    final drive = widget.drive;
    final onDropMove = widget.onDropMove;
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
                      _short(label, max: current ? 32 : 24),
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

    // El cliente NO ve el camino hacia su carpeta compartida: si vive anidada
    // (`XV/ReynaCoot`), las migas saltan la carpeta del estudio que la contiene
    // y quedan «Mi Drive > ReynaCoot» (la raíz del cliente es donde están SUS
    // carpetas compartidas), no «Mi Drive > XV > ReynaCoot».
    final hidden = drive.hiddenPathPrefix;
    final children = <Widget>[];
    children.add(
      crumb(
        drive.rootLabel,
        widget.onRootTap ?? () => drive.openPath(const []),
        current: drive.path.isEmpty && drive.crumbFolderLabel == null,
        target: const [],
      ),
    );
    // La carpeta en sí (solo en una COMPARTIDA: `rootLabel` es el módulo y
    // esta miga es la carpeta, para poder volver a su contenido desde una
    // subcarpeta sin salir del módulo).
    final folderCrumb = drive.crumbFolderLabel;
    if (folderCrumb != null) {
      children.add(separator);
      children.add(
        crumb(
          folderCrumb,
          () => drive.openPath(const []),
          current: drive.path.isEmpty,
          target: const [],
        ),
      );
    }
    for (var i = hidden; i < drive.path.length; i++) {
      if (children.isNotEmpty) children.add(separator);
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
    // UNA SOLA LÍNEA con desplazamiento horizontal: una ruta profunda ya no
    // "se va para abajo" ni empuja el contenido. Cada miga se acorta y el
    // conjunto se desliza; al cambiar de carpeta se muestra su extremo.
    return SizedBox(
      height: 34,
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: false,
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
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
    required this.onContextMenu,
    required this.onDownload,
    required this.localPreviews,
    required this.noEntrance,
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

  /// Clic derecho: menú contextual del elemento (posición global).
  final void Function(DriveItem item, Offset position) onContextMenu;
  final ValueChanged<DriveItem> onDownload;

  /// Copia local de las fotos recién subidas (nombre -> ruta), para pintarlas
  /// al instante mientras el servidor prepara la miniatura.
  final Map<String, String> localPreviews;

  /// Nombres que NO deben animar su entrada (recién aparecidos por una subida).
  final Set<String> noEntrance;
  final ScrollController scrollController;

  /// ¿El usuario ya bajó? Las tarjetas que se construyen al desplazarse nacen
  /// con animación; las que ya estaban a la vista al abrir la carpeta, no
  /// (antes se animaba TODA la cuadrícula de golpe, que es justo lo que se
  /// quiere evitar).
  bool get _scrolledDown =>
      scrollController.isSafe && scrollController.safeOffset > 8;

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
          // Siempre desplazable: sin esto, con pocos elementos el gesto de
          // recargar (deslizar hacia abajo) no se dispara.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            compact ? 14 : 24,
            4,
            compact ? 14 : 24,
            compact ? 150 : 110,
          ),
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
              item.name,
              () => GlobalKey(debugLabel: 'grid-${item.name}'),
            );
            // Entrada al DESLIZAR: la tarjeta que aparece al bajar entra con
            // fade + deslizamiento; lo ya visible (y una foto recién subida)
            // se pinta directo.
            return ScrollReveal(
              animate: _scrolledDown && !noEntrance.contains(item.name),
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
                onContextMenu: (pos) => onContextMenu(item, pos),
                onDownload: () => onDownload(item),
                localPreview: localPreviews[item.name],
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
    required this.onContextMenu,
    required this.onDownload,
    this.localPreview,
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
  final void Function(Offset position) onContextMenu;
  final VoidCallback onDownload;

  /// Copia local del archivo si acaba de subirse (se ve al instante).
  final String? localPreview;
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
            onHoldSelect: onLongPress,
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
          return _card(scheme, context, hovering: hovering);
        },
      ),
    );
  }

  Widget _card(
    ColorScheme scheme,
    BuildContext context, {
    bool hovering = false,
  }) {
    return _Hover(
      builder: (context, mouseHover) {
        final hovered = mouseHover || hovering;
        return Stack(
          children: [
            Positioned.fill(
              child: InkWell(
                onTap: onTapSelect,
                onLongPress: onLongPress,
                // CLICK DERECHO: menú contextual (Abrir/Descargar/…).
                onSecondaryTapUp: (details) =>
                    onContextMenu(details.globalPosition),
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
                    // Diseño PLANO: sin sombras; el estado se comunica con
                    // borde y tinte de color.
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13.5),
                    child: item.isFolder
                        ? _FolderCard(
                            item: item,
                            can: drive.canDo,
                            onOpen: onOpen,
                            onLongPress: onLongPress,
                            onRename: onRename,
                            onDelete: onDelete,
                            onContextMenu: onContextMenu,
                            onDownload: onDownload,
                          )
                        : _FileCard(
                            item: item,
                            drive: drive,
                            onOpen: onOpen,
                            onLongPress: onLongPress,
                            onRename: onRename,
                            onDelete: onDelete,
                            onContextMenu: onContextMenu,
                            onDownload: onDownload,
                            localPreview: localPreview,
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
                      horizontal: 7,
                      vertical: 3,
                    ),
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
    required this.can,
    required this.onOpen,
    required this.onLongPress,
    required this.onRename,
    required this.onDelete,
    required this.onContextMenu,
    required this.onDownload,
  });

  final DriveItem item;
  final bool Function(String action) can;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final void Function(Offset position) onContextMenu;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        onLongPress: onLongPress,
        // CLICK DERECHO: menú contextual.
        onSecondaryTapUp: (details) => onContextMenu(details.globalPosition),
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
                  _ItemMenu(
                    can: can,
                    onOpen: onOpen,
                    onRename: onRename,
                    onDelete: onDelete,
                    onDownload: onDownload,
                  ),
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
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  // Sin conteo de verdad (una compartida anidada que el
                  // listado de la raíz no puede contar) no se inventa un
                  // "0 elementos": se dice que está compartida.
                  Text(
                    !item.countKnown
                        ? 'Carpeta compartida'
                        : '${item.childCount} '
                              'elemento${item.childCount == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.bodySmall
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

/// Tarjeta de un ARCHIVO del Drive: la foto se ve (miniatura) y todo lo demás
/// muestra su tipo con un icono y su extensión (un vídeo, un PDF, un ZIP).
///
/// Antes esta tarjeta pedía una MINIATURA para cualquier archivo: al abrir una
/// carpeta con vídeos, cada uno pedía su "miniatura" al servidor (que solo sabe
/// de imágenes) y quedaban recuadros rotos.
class _FileCard extends StatelessWidget {
  const _FileCard({
    required this.item,
    required this.drive,
    required this.onOpen,
    required this.onLongPress,
    required this.onRename,
    required this.onDelete,
    required this.onContextMenu,
    required this.onDownload,
    this.localPreview,
  });

  final DriveItem item;
  final DriveBase drive;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final void Function(Offset position) onContextMenu;
  final VoidCallback onDownload;
  final String? localPreview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // La miniatura la tiene lo que el drive sabe generar: las FOTOS siempre y
    // los VÍDEOS (el servidor les saca el primer fotograma). Un PDF o un ZIP no
    // tienen quién se la haga, así que enseñan el icono de su tipo.
    final hasThumb = drive.canThumb(item);
    final src = hasThumb ? drive.thumbSource(item, width: 480) : '';
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        onLongPress: onLongPress,
        // CLICK DERECHO: menú contextual.
        onSecondaryTapUp: (details) => onContextMenu(details.globalPosition),
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasThumb)
                      DriveThumb(
                        source: src,
                        // El drive dice si sirve por RED (una carpeta
                        // compartida también, aunque no sea el del servidor).
                        isRemote: drive.isRemote,
                        localPreview: localPreview,
                        size: double.infinity,
                        big: true,
                        // Si la miniatura no llega (el servidor no tiene
                        // ffmpeg, o el vídeo no se deja abrir) se ve el icono
                        // de su tipo, nunca un recuadro roto.
                        fallback: _FileTile(item: item),
                      )
                    else
                      _FileTile(item: item),
                    // Un vídeo o una canción se anuncian como tales: con el
                    // icono del tipo no se sabe si hay que tocar para que
                    // suene.
                    if (item.isPlayable)
                      const Positioned(left: 8, bottom: 8, child: _PlayBadge()),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _OverlayMenu(
                        can: drive.canDo,
                        onOpen: onOpen,
                        onRename: onRename,
                        onDelete: onDelete,
                        onDownload: onDownload,
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
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _metaLabel(item),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
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

/// Recuadro de un archivo que NO es una foto: el icono de su tipo sobre un
/// tinte suave, más su extensión (MP4, PDF, ZIP…).
class _FileTile extends StatelessWidget {
  const _FileTile({required this.item, this.big = true});

  final DriveItem item;

  /// Tarjeta grande (cuadrícula) o mini icono (fila del listado).
  final bool big;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = driveKindColor(item.kind, scheme);
    final ext = driveExtensionLabel(item.name);
    return Container(
      color: color.withValues(alpha: big ? .12 : .10),
      alignment: Alignment.center,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Icon(
              driveKindIcon(item.kind),
              size: big ? 46 : 22,
              color: color,
            ),
          ),
          if (big && ext.isNotEmpty)
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .22),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  ext,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .4,
                    color: color,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Señal de "esto se reproduce": vídeo o audio.
class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .55),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.play_arrow_rounded,
        size: 20,
        color: Colors.white,
      ),
    );
  }
}

class _ItemMenu extends StatelessWidget {
  const _ItemMenu({
    required this.can,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
    required this.onDownload,
  });

  /// Permisos del drive que se está viendo (rol en Archivos, o los que dio
  /// el dueño de una carpeta compartida).
  final bool Function(String action) can;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    // Solo las acciones que el rol tiene. VER va siempre (si el elemento se
    // está viendo, se puede abrir); sin las demás, el menú queda con "Ver".
    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem(value: 'open', child: Text('Ver')),
      if (can('download'))
        const PopupMenuItem(value: 'download', child: Text('Descargar')),
      if (can('update'))
        const PopupMenuItem(value: 'rename', child: Text('Renombrar')),
      if (can('delete'))
        const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
    ];
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
        if (v == 'open') onOpen();
        if (v == 'download') onDownload();
        if (v == 'rename') onRename();
        if (v == 'delete') onDelete();
      },
      itemBuilder: (_) => items,
    );
  }
}

class _OverlayMenu extends StatelessWidget {
  const _OverlayMenu({
    required this.can,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
    required this.onDownload,
  });

  final bool Function(String action) can;

  /// Ver el elemento (abrir la carpeta o el visor de la foto).
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    // Igual que arriba: VER siempre, y las demás según los permisos.
    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem(value: 'open', child: Text('Ver')),
      if (can('download'))
        const PopupMenuItem(value: 'download', child: Text('Descargar')),
      if (can('update'))
        const PopupMenuItem(value: 'rename', child: Text('Renombrar')),
      if (can('delete'))
        const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
    ];
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
      child: PopupMenuButton<String>(
        tooltip: 'Opciones',
        padding: EdgeInsets.zero,
        splashRadius: 18,
        icon: const Icon(Icons.more_vert, size: 18, color: Colors.white),
        onSelected: (v) {
          if (v == 'open') onOpen();
          if (v == 'download') onDownload();
          if (v == 'rename') onRename();
          if (v == 'delete') onDelete();
        },
        itemBuilder: (_) => items,
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
    required this.onContextMenu,
    required this.onDownload,
    required this.localPreviews,
    required this.noEntrance,
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
  final void Function(DriveItem item, Offset position) onContextMenu;
  final ValueChanged<DriveItem> onDownload;
  final Map<String, String> localPreviews;
  final Set<String> noEntrance;
  final ScrollController scrollController;

  /// Ver [_GridBody._scrolledDown]: las filas que aparecen al bajar animan su
  /// entrada; las que ya estaban a la vista se pintan directas.
  bool get _scrolledDown =>
      scrollController.isSafe && scrollController.safeOffset > 8;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = drive.visibleItems;
    final headerStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700);

    final dividerColor =
        Theme.of(context).dividerTheme.color ??
        scheme.outlineVariant.withValues(alpha: .5);
    return Card(
      margin: EdgeInsets.fromLTRB(
        compact ? 14 : 24,
        4,
        compact ? 14 : 24,
        compact ? 150 : 110,
      ),
      child: Column(
        children: [
          if (!compact)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                final key = itemKeys.putIfAbsent(
                  item.name,
                  () => GlobalKey(debugLabel: 'row-${item.name}'),
                );
                // Igual que en la cuadrícula: anima solo lo que llega al bajar.
                return ScrollReveal(
                  animate: _scrolledDown && !noEntrance.contains(item.name),
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
                    onContextMenu: (pos) => onContextMenu(item, pos),
                    onDownload: () => onDownload(item),
                    localPreview: localPreviews[item.name],
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
    required this.onContextMenu,
    required this.onDownload,
    this.localPreview,
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
  final void Function(Offset position) onContextMenu;
  final VoidCallback onDownload;
  final String? localPreview;
  final List<String> selectedNames;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canDrop = item.isFolder;

    // En MÓVIL el arrastre exige presión larga (~350ms); en escritorio, inmediato.
    final Widget Function(Widget child) buildDraggable = useLongPressDrag
        ? (child) => PressMoveDraggable<Object>(
            delay: AppConstants.longPressDragDelay,
            onHoldSelect: onLongPress,
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

  Widget _row(
    ColorScheme scheme,
    BuildContext context, {
    bool hovering = false,
  }) {
    // La miniatura solo tiene sentido en una FOTO.
    final hasThumb = drive.canThumb(item);
    final src = hasThumb ? drive.thumbSource(item, width: 120) : '';
    return InkWell(
      onTap: onTapSelect,
      onLongPress: onLongPress,
      // CLICK DERECHO: menú contextual.
      onSecondaryTapUp: (details) => onContextMenu(details.globalPosition),
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
                  ? Icon(Icons.folder_rounded, color: scheme.primary, size: 26)
                  : hasThumb
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: DriveThumb(
                        source: src,
                        isRemote: drive.isRemote,
                        localPreview: localPreview,
                        size: 40,
                        fallback: _FileTile(item: item, big: false),
                      ),
                    )
                  // Un PDF o un ZIP no tienen miniatura: su icono dice de un
                  // vistazo qué es.
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: _FileTile(item: item, big: false),
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
              // Tipo (igual que la cuadrícula: una carpeta se distingue de una
              // foto también en la fila).
              SizedBox(
                width: 76,
                child: Text(
                  driveKindLabel(item.kind),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
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
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
              child: _ItemMenu(
                can: drive.canDo,
                onOpen: onOpen,
                onRename: onRename,
                onDelete: onDelete,
                onDownload: onDownload,
              ),
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
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
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

/// Abre el VISOR de imágenes del Drive (pantalla completa, con zoom, flechas,
/// Esc y botón de descarga).
///
/// Es PÚBLICO para poder reutilizarlo en carpetas que no son del Drive: el
/// módulo "Archivos compartidos" lo usa con sus carpetas LOCALES (a través de
/// un [DriveBase] adaptador), y así una carpeta compartida se ve y se descarga
/// EXACTAMENTE igual que el Drive.
Future<void> showDriveImageViewer(
  BuildContext context, {
  required DriveBase drive,
  required List<DriveItem> images,
  required int initialIndex,
  Future<void> Function(DriveItem item)? onDownload,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => _ImageViewerDialog(
      drive: drive,
      images: images,
      initialIndex: initialIndex,
      onDownload: onDownload,
    ),
  );
}

class _ImageViewerDialog extends StatefulWidget {
  const _ImageViewerDialog({
    required this.drive,
    required this.images,
    required this.initialIndex,
    this.onDownload,
  });

  final DriveBase drive;
  final List<DriveItem> images;
  final int initialIndex;

  /// Descarga la imagen que se está viendo (opcional: sin permiso no se
  /// muestra el botón).
  final Future<void> Function(DriveItem item)? onDownload;

  @override
  State<_ImageViewerDialog> createState() => _ImageViewerDialogState();
}

class _ImageViewerDialogState extends State<_ImageViewerDialog> {
  late int _index = widget.initialIndex;

  /// Zoom del visor (los botones del borde derecho y el gesto lo comparten).
  final TransformationController _zoom = TransformationController();

  void _move(int delta) {
    final next = (_index + delta) % widget.images.length;
    setState(() {
      _index = next < 0 ? next + widget.images.length : next;
      _previewReady = false;
    });
    _zoom.value = Matrix4.identity();
    _preloadNeighbors();
    _loadFull();
  }

  /// Acerca o aleja la imagen (mantiene el centro).
  void _zoomBy(double factor) {
    _zoom.value = _zoom.value.clone()..scaleByDouble(factor, factor, factor, 1);
  }

  @override
  void initState() {
    super.initState();
    // Flechas/Esc SIN depender del foco: igual que los atajos de la propia
    // página del Drive (así funciona aunque el foco esté en un botón).
    HardwareKeyboard.instance.addHandler(_onKey);
    // Precarga las fotos vecinas para navegar sin esperas.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadNeighbors();
      _loadFull();
    });
  }

  /// Atajos del visor: ← → cambian de foto y Esc lo cierra.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _move(1);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _move(-1);
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _zoom.dispose();
    // Al cerrar el visor: fuera el original de RAM (queda en caché de disco).
    if (widget.drive.isRemote) {
      ImageMemory.evict(widget.drive.absolutePathOf(widget.images[_index]));
    } else {
      PaintingBinding.instance.imageCache.clear();
    }
    super.dispose();
  }

  // ---- Original por chunks detrás del preview ----
  File? _fullFile;

  /// Original por RED (carpetas compartidas): entra encima del preview.
  String _fullUrl = '';
  double _fullProgress = 0;
  bool _fullLoading = false;
  String _fullKey = '';

  /// La miniatura rápida ya se ve: desde aquí se puede pedir la original.
  bool _previewReady = false;

  Future<void> _loadFull() async {
    final item = widget.images[_index];
    if (item.isFolder) return;
    final drive = widget.drive;
    final key = drive.fullSource(item);
    if (_fullKey == key && (_fullFile != null || _fullUrl.isNotEmpty)) {
      return; // ya está
    }
    _fullKey = key;
    // RAW/TIFF/HEIC: el original NO se puede pintar en la app. La vista
    // previa del servidor (`/thumb`, ya en JPEG) se queda como imagen buena;
    // bajar 40 MB de CR3 solo dejaría el visor en negro.
    if (item.needsServerPreview) {
      _fullLoading = false;
      _fullFile = null;
      _fullUrl = '';
      return;
    }
    // El original por chunks (File + caché de disco) es del servidor del
    // Drive. Una CARPETA COMPARTIDA se sirve por red (su dueño o el servidor
    // del compartido): ahí se muestra la original como URL y, cuando carga,
    // entra nítida sobre la miniatura. En el Drive LOCAL el archivo está en
    // disco: se abre directo.
    if (kWeb) return;
    if (drive is! DriveApiService) {
      // Carpeta compartida (por red): la original es su URL. Un Drive LOCAL
      // no necesita nada más: el preview ya lee el archivo del disco y abrir
      // otro Image.file dejaría el archivo bloqueado.
      if (drive.isRemote) {
        setState(() {
          _fullUrl = key;
          _fullFile = null;
        });
      }
      return;
    }
    final api = drive;
    _fullLoading = true;
    _fullProgress = 0;
    _fullFile = null;
    _fullUrl = '';
    if (mounted) setState(() {});
    try {
      final f = await api.fetchOriginalChunked(
        item,
        onProgress: (p) {
          if (!mounted || key != _fullKey) return;
          _fullProgress = p;
          setState(() {});
        },
      );
      if (!mounted || key != _fullKey) return;
      setState(() {
        _fullFile = f;
        _fullLoading = false;
      });
    } catch (_) {
      // El preview sigue siendo visible; el original es opcional. Se intenta
      // por red (la URL lleva el token en la query) antes de rendirse.
      if (mounted && key == _fullKey) {
        setState(() {
          _fullLoading = false;
          _fullUrl = key;
        });
      }
    }
  }

  /// Baja a caché de red los previews (1600px) de la foto actual ±2.
  ///
  /// Vale para CUALQUIER drive por red (también una carpeta compartida), no
  /// sólo el del servidor: hace falta que la foto siguiente se vea sin esperar
  /// y, en una carpeta compartida, el original puede tener que venir de la
  /// computadora de su dueño (lento): mejor tener el preview listo antes.
  void _preloadNeighbors() {
    final drive = widget.drive;
    if (!drive.isRemote) return;
    for (var d = -2; d <= 2; d++) {
      final i = (_index + d) % widget.images.length;
      if (i < 0) continue;
      final item = widget.images[i];
      if (item.isFolder) continue;
      // Sin `onError`: un preview que no se pueda bajar es sólo una
      // optimización perdida (la foto de verdad tiene su propio reintento en
      // la tarjeta), así que no debe ensuciar el registro ni la pantalla.
      precacheImage(
        NetworkImage(
          drive.fullSource(
            item,
            previewWidth: item.needsServerPreview ? 2048 : 1600,
          ),
        ),
        context,
        onError: (_, _) {},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.images[_index];
    final isRemote = widget.drive.isRemote;
    // Preview 1600px: baja ~0.5 MB en vez de los 10 MB del original. Los RAW
    // y formatos que la app no decodifica se piden un poco más grandes (siguen
    // siendo una vista previa, no el archivo de la cámara).
    final src = widget.drive.fullSource(
      item,
      previewWidth: item.needsServerPreview ? 2048 : 1600,
    );
    final total = widget.images.length;
    // Pantalla COMPLETA y sin bordes curvos: el visor es una superficie
    // limpia sobre negro, con la info y las acciones encima de la foto.
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            transformationController: _zoom,
            maxScale: 6,
            child: Center(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 1) Preview ligero: se ve AL INSTANTE.
                  DriveThumb(
                    source: src,
                    isRemote: isRemote,
                    size: double.infinity,
                    big: true,
                    contain: true,
                    // A pantalla completa NO se redondean las esquinas.
                    rounded: false,
                    onReady: () {
                      if (!mounted || _previewReady) return;
                      setState(() => _previewReady = true);
                    },
                  ),
                  // 2) Original por chunks: aparece encima (nítido) al
                  //    completar, con transición suave.
                  if (_fullFile != null)
                    Image.file(
                      _fullFile!,
                      fit: BoxFit.contain,
                      frameBuilder: (c, child, frame, sync) => AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: const Duration(milliseconds: 250),
                        child: child,
                      ),
                    )
                  // 2b) Original por RED: en una carpeta COMPARTIDA (su dueño
                  //     o el servidor del compartido) y, como respaldo, si la
                  //     descarga por chunks falla. Si también falla, queda el
                  //     preview.
                  else if (_fullUrl.isNotEmpty)
                    Image.network(
                      _fullUrl,
                      fit: BoxFit.contain,
                      frameBuilder: (c, child, frame, sync) {
                        if (sync) return child;
                        return AnimatedOpacity(
                          opacity: frame == null ? 0 : 1,
                          duration: const Duration(milliseconds: 200),
                          child: child,
                        );
                      },
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                ],
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
          // Barra superior: nombre, peso y posición + las acciones
          // (descargar / cerrar) DENTRO del propio visor.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 10, 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            [
                              if (_metaLabel(item).isNotEmpty) _metaLabel(item),
                              if (total > 1) '${_index + 1} de $total',
                            ].join(' · '),
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.onDownload != null)
                      _ViewerAction(
                        icon: Icons.download_rounded,
                        tooltip: 'Descargar',
                        onTap: () => widget.onDownload!(item),
                      ),
                    const SizedBox(width: 8),
                    _ViewerAction(
                      icon: Icons.close_rounded,
                      tooltip: 'Cerrar',
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Zoom: además del gesto/rueda, botones explícitos.
          Positioned(
            right: 10,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ViewerAction(
                  icon: Icons.add,
                  tooltip: 'Acercar',
                  onTap: () => _zoomBy(1.4),
                ),
                const SizedBox(height: 8),
                _ViewerAction(
                  icon: Icons.remove,
                  tooltip: 'Alejar',
                  onTap: () => _zoomBy(1 / 1.4),
                ),
                const SizedBox(height: 8),
                _ViewerAction(
                  icon: Icons.fit_screen_outlined,
                  tooltip: 'Ajustar a la pantalla',
                  onTap: () => _zoom.value = Matrix4.identity(),
                ),
              ],
            ),
          ),
          if (widget.images.length > 1) ...[
            Positioned(
              left: 10,
              top: 0,
              bottom: 0,
              child: Center(
                child: _ViewerAction(
                  icon: Icons.chevron_left,
                  tooltip: 'Anterior',
                  onTap: () => _move(-1),
                ),
              ),
            ),
            Positioned(
              right: 10,
              top: 0,
              bottom: 0,
              child: Center(
                child: _ViewerAction(
                  icon: Icons.chevron_right,
                  tooltip: 'Siguiente',
                  onTap: () => _move(1),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Botón redondo semitransparente del visor de imágenes.
class _ViewerAction extends StatelessWidget {
  const _ViewerAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .12),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        iconSize: 20,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, color: Colors.white),
        onPressed: onTap,
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
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
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
/// Aviso del panel inferior de actividad: texto + si marcó error
/// (rojo) o se cumplió (verde).
class _DriveNotice {
  _DriveNotice(this.text, this.error);
  final String text;
  final bool error;
}

/// Ventanita inferior derecha del Drive: transferencias (subidas y
/// descargas) JUNTO CON los avisos de notificación (verde/rojo). Se puede
/// ocultar (minimiza a una pastilla) y se reabre con un clic o solo al
/// llegar un aviso nuevo.
class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({
    required this.open,
    required this.drive,
    required this.notices,
    required this.onToggle,
    required this.onClearNotices,
    this.onDismissNotice,
  });

  final bool open;
  final DriveBase drive;
  final List<_DriveNotice> notices;
  final VoidCallback onToggle;
  final VoidCallback onClearNotices;

  /// Quita UN aviso (el de la posición dada).
  final ValueChanged<int>? onDismissNotice;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Las fotos del LOTE en curso (no el historial de otros lotes).
    final uploadJobs = drive.currentUploadJobs;
    final uploads = uploadJobs.length;
    final downloads = drive.downloadJobs.length;

    // ---- Oculta: pastilla compacta para volver a abrirla ----
    if (!open) {
      final parts = [
        if (uploads > 0) '$uploads foto${uploads == 1 ? '' : 's'}',
        if (downloads > 0) '$downloads descarga${downloads == 1 ? '' : 's'}',
        if (notices.isNotEmpty)
          '${notices.length} aviso${notices.length == 1 ? '' : 's'}',
      ];
      return Material(
        key: const ValueKey('activity_pill'),
        elevation: 10,
        shadowColor: Colors.black.withValues(alpha: .28),
        borderRadius: BorderRadius.circular(999),
        color: scheme.surface,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.bolt_rounded,
                    size: 13,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  parts.join(' · '),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.unfold_more_rounded,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Resumen del encabezado. Se cuida de no repetir EXACTAMENTE los textos
    // de progreso ("1/2 fotos", "50% subidas"): cada cosa se dice una vez.
    final resumen = [
      if (notices.isNotEmpty)
        '${notices.length} aviso${notices.length == 1 ? '' : 's'}',
      if (uploads > 0) '$uploads foto${uploads == 1 ? '' : 's'}',
      if (downloads > 0) '$downloads descarga${downloads == 1 ? '' : 's'}',
    ].join(' · ');

    final screenH = MediaQuery.sizeOf(context).height;
    // El panel ABSORBE el puntero en TODA su superficie: sin esto, el clic
    // atravesaba el hueco que queda entre los widgets (un texto o un margen no
    // capturan toques) y caía en la cuadrícula de atrás, así que tocar la
    // ventanita seleccionaba fotos sin querer.
    return Listener(
      behavior: HitTestBehavior.opaque,
      child: Material(
        key: const ValueKey('activity_panel'),
        elevation: 18,
        shadowColor: Colors.black.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        color: scheme.surface,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .5),
            ),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 400,
              maxHeight: screenH * .58,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(scheme, resumen),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Avisos PRIMERO: son lo más nuevo y el panel se abre
                        // solito cuando llegan.
                        if (notices.isNotEmpty) _noticesSection(scheme),
                        if (uploads > 0) ...[
                          if (notices.isNotEmpty) const SizedBox(height: 10),
                          _UploadsCard(drive: drive),
                        ],
                        if (downloads > 0) ...[
                          if (notices.isNotEmpty || uploads > 0)
                            const SizedBox(height: 10),
                          _DownloadsCard(drive: drive),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Encabezado del panel: icono, título, resumen en vivo y acciones.
  Widget _header(ColorScheme scheme, String resumen) {
    // Punto EN VIVO: solo cuando hay algo transfiriéndose ahora mismo.
    final working =
        drive.uploadJobs.any((j) => j.status == 'uploading') ||
        drive.downloadJobs.any((j) => j.status == 'downloading');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: .14),
            scheme.primary.withValues(alpha: .01),
          ],
        ),
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .45),
          ),
        ),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: .28),
                  ),
                ),
                child: Icon(
                  Icons.notifications_active_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
              ),
              if (working)
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Color(0xFF2F6BFF),
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.surface, width: 1.6),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      'Actividad',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (working) ...[
                      const SizedBox(width: 6),
                      Text(
                        'en curso',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2F6BFF).withValues(alpha: .95),
                        ),
                      ),
                    ],
                  ],
                ),
                if (resumen.isNotEmpty)
                  Text(
                    resumen,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (notices.isNotEmpty)
            IconButton(
              tooltip: 'Limpiar avisos',
              visualDensity: VisualDensity.compact,
              onPressed: onClearNotices,
              icon: Icon(
                Icons.delete_sweep_outlined,
                size: 19,
                color: scheme.onSurfaceVariant,
              ),
            ),
          IconButton(
            tooltip: 'Ocultar',
            visualDensity: VisualDensity.compact,
            onPressed: onToggle,
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 22,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Lista de avisos: cada uno en su recuadro, ROJO si falló y VERDE si se
  /// cumplió, con su botón para quitarlo de la lista.
  Widget _noticesSection(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < notices.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _NoticeRow(
            notice: notices[i],
            onDismiss: onDismissNotice == null
                ? null
                : () => onDismissNotice!(i),
          ),
        ],
      ],
    );
  }
}

/// Un aviso del panel: recuadro tintado (verde/rojo), icono, texto y ✕ para
/// descartarlo sin borrar los demás.
class _NoticeRow extends StatelessWidget {
  const _NoticeRow({required this.notice, this.onDismiss});

  final _DriveNotice notice;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // VERDE = salió bien, ROJO = falló. Antes el éxito también era azul y en
    // el panel de actividad no se distinguía de un aviso neutro.
    final color = notice.error ? scheme.error : const Color(0xFF16A34A);
    return Container(
      padding: EdgeInsets.fromLTRB(10, 8, onDismiss == null ? 10 : 2, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              notice.error ? Icons.error_outline : Icons.check_circle_outline,
              size: 16,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              notice.text,
              style: TextStyle(
                fontSize: 12.3,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: notice.error ? scheme.error : scheme.onSurface,
              ),
            ),
          ),
          if (onDismiss != null)
            SizedBox(
              width: 28,
              height: 26,
              child: IconButton(
                tooltip: 'Descartar aviso',
                padding: EdgeInsets.zero,
                iconSize: 15,
                onPressed: onDismiss,
                icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bloque de la ventanita: título con su icono, un subtítulo opcional y el
/// contenido, todo dentro del MISMO marco. Antes cada bloque era una tarjeta
/// con su sombra dentro de la tarjeta grande y se veía recargado.
class _PanelSection extends StatelessWidget {
  const _PanelSection({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 8, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .30),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 15, color: scheme.primary),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.6,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 7),
          child,
        ],
      ),
    );
  }
}

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
    // SOLO el lote más reciente: las fotos de una subida anterior no se mezclan
    // con las de la actual, y las que esperan turno en la cola cuentan como
    // "a subir" (con 100 fotos el panel muestra las 100).
    final jobs = drive.currentUploadJobs;
    // Conteos SIEMPRE visibles: en carga / completadas / con error.
    final active = jobs.where((j) => j.status == 'uploading').length;
    final done = jobs.where((j) => j.status == 'done').length;
    final failed = jobs.where((j) => j.status == 'error').length;
    // Progreso del LOTE: FOTOS subidas / fotos a subir ("50/100 fotos"), que es
    // lo que se quiere saber al cargar un montón de archivos: los bytes de cada
    // foto no dicen cuántas faltan.
    final total = jobs.length;
    final globalPct = total > 0 ? (done / total).clamp(0.0, 1.0) : null;
    return _PanelSection(
      key: const ValueKey('uploads_card'),
      icon: active > 0
          ? Icons.cloud_upload_outlined
          : failed > 0
          ? Icons.error_outline
          : Icons.cloud_done_outlined,
      title: active > 0
          ? 'Subiendo $total ${total == 1 ? 'foto' : 'fotos'}…'
          : failed > 0
          ? '$done completada${done == 1 ? '' : 's'} · '
                '$failed con error${failed == 1 ? '' : 's'}'
          : '$total subida${total == 1 ? '' : 's'} '
                'completada${total == 1 ? '' : 's'}',
      subtitle: active > 0
          ? '$done de $total fotos'
                '${failed > 0 ? ' · $failed con error${failed == 1 ? '' : 's'}' : ''}'
          : null,
      action: active > 0
          ? TextButton.icon(
              onPressed: drive.cancelAllUploads,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.cancel_outlined, size: 15),
              label: const Text(
                'Cancelar todo',
                style: TextStyle(fontSize: 12),
              ),
            )
          : IconButton(
              tooltip: 'Limpiar',
              visualDensity: VisualDensity.compact,
              onPressed: drive.clearFinishedUploads,
              icon: const Icon(Icons.close, size: 18),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barra de progreso del LOTE: fotos subidas / fotos a subir.
          if (globalPct != null)
            Row(
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
                  '${(globalPct * 100).toStringAsFixed(0)}% subidas',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$done/$total fotos',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 4),
          for (final job in jobs)
            UploadJobTile(
              job: job,
              onCancel: job.status == 'uploading'
                  ? () => drive.cancelUpload(job.id)
                  : null,
              onRetry: job.status == 'error'
                  ? () => drive.retryUpload(job.id)
                  : null,
            ),
        ],
      ),
    );
  }
}

/// Tarjeta de un trabajo de subida (miniatura + nombre + progreso).
/// PÚBLICA para poder probarla desde test/.
class UploadJobTile extends StatelessWidget {
  const UploadJobTile({
    super.key,
    required this.job,
    this.onCancel,
    this.onRetry,
  });

  final DriveUploadJob job;

  /// Si no es null, muestra el botón ✕ para cancelar esta subida.
  final VoidCallback? onCancel;

  /// Si no es null, muestra el botón "Resubir" cuando la subida falló.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = job.total > 0 ? (job.sent / job.total).clamp(0.0, 1.0) : null;
    final failed = job.status == 'error';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.fromLTRB(8, 8, 6, 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (failed ? scheme.error : scheme.outlineVariant).withValues(
            alpha: failed ? .45 : .35,
          ),
        ),
      ),
      child: Row(
        children: [
          DriveThumb(
            source: job.thumb,
            isRemote: false, // miniatura del archivo LOCAL
            size: 40,
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
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                if (job.status == 'uploading')
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                            pct == null
                                ? '…'
                                : '${(pct * 100).toStringAsFixed(0)}%',
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
                      ),
                      // Reintento automático en curso: se avisa para que no
                      // parezca que la subida se quedó parada en 0 %.
                      if (job.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            job.error!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  )
                else if (job.status == 'cancelled')
                  Row(
                    children: [
                      Icon(
                        Icons.cancel_outlined,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
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
                      Icon(Icons.check_circle, size: 14, color: scheme.primary),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Error: ${job.error ?? 'desconocido'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: scheme.error),
                        ),
                      ),
                      // Volver a intentar el archivo que falló, sin repetir
                      // todo el lote.
                      if (onRetry != null)
                        TextButton.icon(
                          onPressed: onRetry,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                          ),
                          icon: const Icon(Icons.refresh_rounded, size: 14),
                          label: const Text(
                            'Resubir',
                            style: TextStyle(fontSize: 11.5),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Panel de DESCARGAS en segundo plano (arriba a la derecha, junto al de
/// subidas). Escucha al drive directamente para refrescar el progreso real.
class _DownloadsCard extends StatelessWidget {
  const _DownloadsCard({required this.drive});

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
    final jobs = drive.downloadJobs;
    final active = jobs.where((j) => j.status == 'downloading').length;
    final done = jobs.where((j) => j.status == 'done').length;
    final failed = jobs.where((j) => j.status == 'error').length;
    final totalBytes = jobs.fold<int>(
      0,
      (a, j) => j.status == 'downloading' ? a + j.total : a,
    );
    final gotBytes = jobs.fold<int>(
      0,
      (a, j) => j.status == 'downloading' ? a + j.received : a,
    );
    final globalPct = totalBytes > 0
        ? (gotBytes / totalBytes).clamp(0.0, 1.0)
        : null;

    return _PanelSection(
      key: const ValueKey('downloads_card'),
      icon: active > 0
          ? Icons.downloading_outlined
          : failed > 0
          ? Icons.error_outline
          : Icons.download_done_outlined,
      title: active > 0
          ? 'Descargando $active ${active == 1 ? 'archivo' : 'archivos'}…'
          : failed > 0
          ? '$done lista${done == 1 ? '' : 's'} · '
                '$failed con error${failed == 1 ? '' : 'es'}'
          : '$done descarga${done == 1 ? '' : 's'} '
                'completada${done == 1 ? '' : 's'}',
      subtitle: active > 0 && globalPct != null
          ? '${(globalPct * 100).toStringAsFixed(0)} % en curso'
          : null,
      action: active > 0
          ? TextButton.icon(
              onPressed: () {
                for (final j in jobs) {
                  drive.cancelDownload(j.id);
                }
              },
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.cancel_outlined, size: 15),
              label: const Text('Cancelar', style: TextStyle(fontSize: 12)),
            )
          : IconButton(
              tooltip: 'Limpiar',
              visualDensity: VisualDensity.compact,
              onPressed: drive.clearFinishedDownloads,
              icon: const Icon(Icons.close, size: 18),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (active > 0)
            Row(
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
                  globalPct == null
                      ? '…'
                      : '${(globalPct * 100).toStringAsFixed(0)} %',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          for (final job in jobs)
            DownloadJobTile(
              job: job,
              onCancel: job.status == 'downloading'
                  ? () => drive.cancelDownload(job.id)
                  : null,
              onRetry: job.status == 'error'
                  ? () => retryDriveDownload(context, drive, job)
                  : null,
            ),
        ],
      ),
    );
  }
}

/// Tarjeta de una descarga (nombre + barra de progreso). PÚBLICA para test/.
class DownloadJobTile extends StatelessWidget {
  const DownloadJobTile({
    super.key,
    required this.job,
    this.onCancel,
    this.onRetry,
  });

  final DriveDownloadJob job;

  /// Si no es null, muestra ✕ para cancelar esta descarga.
  final VoidCallback? onCancel;

  /// Si no es null, muestra "Reintentar" cuando la descarga falló.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = job.total > 0
        ? (job.received / job.total).clamp(0.0, 1.0)
        : null;
    final failed = job.status == 'error';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.fromLTRB(8, 8, 6, 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (failed ? scheme.error : scheme.outlineVariant).withValues(
            alpha: failed ? .45 : .35,
          ),
        ),
      ),
      child: Row(
        children: [
          // Cuadro del tipo de archivo (una descarga no siempre es una foto
          // que se pueda mirar: un ZIP no tiene miniatura).
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: scheme.primary.withValues(alpha: .18)),
            ),
            child: Icon(
              job.name.toLowerCase().endsWith('.zip')
                  ? Icons.folder_zip_outlined
                  : Icons.image_outlined,
              size: 19,
              color: scheme.primary.withValues(alpha: .85),
            ),
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
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                if (job.status == 'downloading')
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
                        pct == null
                            ? transferSizeLabel(job.received)
                            : '${(pct * 100).toStringAsFixed(0)}%',
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
                else if (job.status == 'done')
                  Row(
                    children: [
                      Icon(Icons.check_circle, size: 14, color: scheme.primary),
                      const SizedBox(width: 5),
                      Text(
                        transferSizeLabel(job.received),
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Error: ${job.error ?? 'desconocido'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: scheme.error),
                        ),
                      ),
                      if (onRetry != null)
                        TextButton.icon(
                          onPressed: onRetry,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                          ),
                          icon: const Icon(Icons.refresh_rounded, size: 14),
                          label: const Text(
                            'Reintentar',
                            style: TextStyle(fontSize: 11.5),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

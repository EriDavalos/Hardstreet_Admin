import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../hs_access.dart';
import '../hs_api.dart';
import '../note_model.dart';
import '../note_selection.dart';
import '../theme.dart';
import '../widgets/confirm_dialog.dart';

// ==================================================================
// MÓDULO NOTAS (estilo Samsung Notes)
//
//   * LISTA: tarjetas con título, vista previa, fecha y a quién pertenece
//     (Personal / Empresa). En computadora la lista va a la izquierda y la
//     nota a la derecha; en el celular la nota se abre a pantalla completa.
//   * DOCUMENTO: se escribe DIRECTO en la hoja (sin campos con caja). El
//     título es solo texto grande con una línea debajo que se ilumina al
//     escribir. Los bloques van insertados en el texto: párrafos, listas de
//     actividades con casilla y DIBUJOS (un lienzo que se abre completo al
//     tocarlo, con lápiz, resaltador, goma, colores y deshacer).
//   * VISIBILIDAD: cada nota es PERSONAL (solo su autor) o de EMPRESA (la lee
//     todo el equipo; los demás la ven en solo lectura).
//
// Backend: /api/admin/notes (permiso del módulo «Notas»).
// ==================================================================

const double _kWideBreakpoint = 1020;

/// Confirmación para salir de una nota con cambios sin guardar.
Future<bool> _confirmDiscard(BuildContext context) async {
  final scheme = Theme.of(context).colorScheme;
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      icon: Icon(Icons.edit_note_rounded, color: scheme.primary, size: 30),
      title: const Text(
        '¿Salir sin guardar?',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
      content: Text(
        'Los cambios de esta nota se perderán.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          height: 1.35,
          color: scheme.onSurfaceVariant,
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Seguir editando'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Salir sin guardar'),
        ),
      ],
    ),
  );
  return res == true;
}

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  bool _loading = true;
  String? _error;
  List<NoteSummary> _notes = const [];
  String _query = '';

  /// Nota abierta en el panel de escritorio.
  Note? _openNote;
  int? _openId;
  bool _loadingNote = false;

  /// Cambia al abrir otra nota: reinicia el estado del editor.
  int _editorEpoch = 0;

  /// ¿El editor abierto tiene cambios sin guardar?
  bool _editorDirty = false;

  bool get _canCreate => HsAccess.instance.can('notes', 'create');
  bool get _canEdit => HsAccess.instance.can('notes', 'update');
  bool get _canDelete => HsAccess.instance.can('notes', 'delete');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = _notes.isEmpty && _error == null);
    try {
      final notes = await HsApi.notes();
      if (!mounted) return;
      setState(() {
        _notes = notes;
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
        _error = 'No se pudieron cargar las notas';
        _loading = false;
      });
    }
  }

  List<NoteSummary> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _notes;
    return _notes
        .where(
          (n) =>
              n.title.toLowerCase().contains(q) ||
              n.preview.toLowerCase().contains(q) ||
              n.ownerName.toLowerCase().contains(q),
        )
        .toList();
  }

  bool get _isWide => MediaQuery.sizeOf(context).width >= _kWideBreakpoint;

  /// Si el editor tiene cambios sin guardar, pide confirmación.
  Future<bool> _leaveEditor() async {
    if (!_editorDirty) return true;
    final ok = await _confirmDiscard(context);
    if (!mounted) return false;
    if (ok) _editorDirty = false;
    return ok;
  }

  Future<void> _newNote() async {
    if (!_canCreate) return;
    if (_isWide) {
      if (!await _leaveEditor()) return;
      if (!mounted) return;
      setState(() {
        _openNote = Note();
        _openId = null;
        _loadingNote = false;
        _editorEpoch++;
      });
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoteEditorPage(noteId: 0, onSaved: _load),
      ),
    );
    await _load();
  }

  Future<void> _open(NoteSummary summary) async {
    if (!_isWide) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NoteEditorPage(noteId: summary.id, onSaved: _load),
        ),
      );
      await _load();
      return;
    }
    if (!await _leaveEditor()) return;
    if (!mounted) return;
    setState(() {
      _openId = summary.id;
      _openNote = null;
      _loadingNote = true;
      _editorEpoch++;
    });
    try {
      final note = await HsApi.note(summary.id);
      if (!mounted || _openId != summary.id) return;
      note.mine = summary.mine;
      note.ownerName = summary.ownerName;
      setState(() {
        _openNote = note;
        _loadingNote = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingNote = false);
    }
  }

  Future<void> _delete(NoteSummary summary) async {
    if (!_canDelete || !summary.mine) return;
    final ok = await confirmDelete(
      context,
      title: '¿Eliminar la nota?',
      message:
          '«${summary.displayTitle}» se eliminará de tus notas. Esta acción no se puede deshacer.',
      confirmLabel: 'Eliminar',
    );
    if (ok != true) return;
    try {
      await HsApi.deleteNote(summary.id);
    } catch (_) {
      // La capa de API ya avisó del error.
    }
    if (_openId == summary.id) {
      setState(() {
        _openId = null;
        _openNote = null;
      });
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isWide) return _listPanel(context, compact: true);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 372, child: _listPanel(context, compact: false)),
        const VerticalDivider(width: 1),
        Expanded(child: _editorPanel(context)),
      ],
    );
  }

  // ----------------------------------------------------------------
  // Lista
  // ----------------------------------------------------------------

  Widget _listPanel(BuildContext context, {required bool compact}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 14 : 18, 16, compact ? 14 : 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Notas',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _notes.isEmpty
                          ? 'Tu bloc personal'
                          : '${_notes.length} ${_notes.length == 1 ? 'nota' : 'notas'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (_canCreate)
                Tooltip(
                  message: 'Nueva nota',
                  child: Material(
                    color: AppColors.brand,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _newNote,
                      child: const SizedBox(
                        width: 42,
                        height: 42,
                        child: Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar notas',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              filled: true,
              fillColor: scheme.surfaceContainerHighest.withValues(alpha: .32),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _listBody(context, _visible)),
        ],
      ),
    );
  }

  Widget _listBody(BuildContext context, List<NoteSummary> notes) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 34, color: scheme.error),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    if (notes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: .10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _query.isEmpty
                      ? Icons.edit_note_rounded
                      : Icons.search_off_rounded,
                  size: 30,
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _query.isEmpty ? 'Todavía no hay notas' : 'Sin resultados',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _query.isEmpty
                    ? 'Escribe, haz listas o dibuja en una hoja nueva.'
                    : 'Ninguna nota coincide con «$_query».',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (_query.isEmpty && _canCreate) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _newNote,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Escribir una nota'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 18),
        itemCount: notes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 9),
        itemBuilder: (context, i) => _noteCard(context, notes[i]),
      ),
    );
  }

  Widget _noteCard(BuildContext context, NoteSummary note) {
    final scheme = Theme.of(context).colorScheme;
    final open = note.id == _openId;
    final tint = noteCardColor(note.color);
    return Material(
      color: open
          ? AppColors.brand.withValues(alpha: .09)
          : scheme.surfaceContainerHighest.withValues(alpha: .26),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(note),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 4, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: open
                  ? AppColors.brand.withValues(alpha: .42)
                  : scheme.outlineVariant.withValues(alpha: .38),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (tint ?? AppColors.brand).withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  note.hasDrawing
                      ? Icons.draw_outlined
                      : (note.sharedWithCompany
                            ? Icons.groups_2_outlined
                            : Icons.sticky_note_2_outlined),
                  size: 19,
                  color: tint ?? AppColors.brand,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.2,
                      ),
                    ),
                    if (note.preview.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        note.preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.32,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _miniChip(
                          scheme,
                          icon: note.sharedWithCompany
                              ? Icons.groups_2_outlined
                              : Icons.lock_outline_rounded,
                          label: note.sharedWithCompany
                              ? 'Empresa'
                              : 'Personal',
                          color: note.sharedWithCompany
                              ? AppColors.brand
                              : scheme.onSurfaceVariant,
                        ),
                        if (!note.mine && note.ownerName.isNotEmpty)
                          _miniChip(
                            scheme,
                            icon: Icons.person_outline_rounded,
                            label: note.ownerName,
                            color: scheme.onSurfaceVariant,
                          ),
                        Text(
                          _dateLabel(note.updated),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: .85,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_canDelete && note.mine)
                IconButton(
                  tooltip: 'Eliminar nota',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _delete(note),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: scheme.error.withValues(alpha: .75),
                  ),
                )
              else
                const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniChip(
    ColorScheme scheme, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  // Editor (escritorio)
  // ----------------------------------------------------------------

  Widget _editorPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loadingNote) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    final note = _openNote;
    if (note == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.edit_note_rounded,
                size: 58,
                color: AppColors.brand.withValues(alpha: .40),
              ),
              const SizedBox(height: 12),
              const Text(
                'Elige una nota',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'O empieza una nueva con el botón +.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return NoteEditor(
      key: ValueKey('note-$_editorEpoch'),
      note: note,
      readOnly: !_canEdit || !note.mine,
      onDirtyChanged: (v) => _editorDirty = v,
      onSaved: (saved) {
        _editorDirty = false;
        setState(() => _openId = saved.id);
        _load();
      },
    );
  }

  // ----------------------------------------------------------------
  // Utilidades
  // ----------------------------------------------------------------

  static const _months = [
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

  String _dateLabel(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    if (diff == 0) return 'Hoy · $hh:$mm';
    if (diff == 1) return 'Ayer · $hh:$mm';
    return '${date.day} ${_months[date.month - 1]} · $hh:$mm';
  }
}

// ==================================================================
// PÁGINA DEL EDITOR (celular: a pantalla completa)
// ==================================================================

class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({super.key, required this.noteId, this.onSaved});

  /// 0 = nota nueva (se crea al guardar).
  final int noteId;
  final VoidCallback? onSaved;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  Note? _note;
  bool _loading = false;
  String? _error;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    if (widget.noteId > 0) {
      _load();
    } else {
      _note = Note();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final note = await HsApi.note(widget.noteId);
      if (!mounted) return;
      setState(() {
        _note = note;
        _loading = false;
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
        _error = 'No se pudo abrir la nota';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = _note;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !_dirty) return;
        final ok = await _confirmDiscard(context);
        if (!ok || !mounted) return;
        Navigator.of(this.context).pop();
      },
      child: Scaffold(
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                )
              : note == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error ?? 'No se pudo abrir la nota',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : NoteEditor(
                  key: ValueKey('page-note-${note.id}'),
                  note: note,
                  readOnly:
                      !HsAccess.instance.can('notes', 'update') || !note.mine,
                  onDirtyChanged: (v) => _dirty = v,
                  onClose: () => Navigator.of(context).pop(),
                  onSaved: (saved) => widget.onSaved?.call(),
                ),
        ),
      ),
    );
  }
}

// ==================================================================
// EDITOR DE UNA NOTA (documento)
// ==================================================================

class NoteEditor extends StatefulWidget {
  const NoteEditor({
    super.key,
    required this.note,
    this.readOnly = false,
    this.onClose,
    this.onSaved,
    this.onDirtyChanged,
  });

  final Note note;
  final bool readOnly;

  /// Cerrar (solo cuando se abre como página). Sin él, el editor vive dentro
  /// de la lista (escritorio).
  final VoidCallback? onClose;
  final ValueChanged<Note>? onSaved;

  /// Avisa cuando la nota pasa a tener cambios sin guardar (y cuando se
  /// guarda). Sirve para no perderlos al cambiar de nota o salir de la app.
  final ValueChanged<bool>? onDirtyChanged;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final NoteRichTextController _title = NoteRichTextController(
    text: widget.note.title,
    formats: widget.note.titleFormats,
  )..addListener(_markDirty);
  late final FocusNode _titleFocus = FocusNode()..addListener(_onFocus);

  late final List<NoteBlock> _blocks = widget.note.blocks;

  /// Controllers y focos por bloque/actividad (identidad del objeto).
  final Map<Object, TextEditingController> _ctrls = {};
  final Map<Object, FocusNode> _focus = {};

  /// Último campo de texto usado y su selección: la barra de formato aplica
  /// el estilo al texto SELECCIONADO aunque el toque del botón quite el foco.
  NoteRichTextController? _textTarget;
  TextSelection _textTargetSelection = const TextSelection.collapsed(
    offset: -1,
  );

  /// Visibilidad elegida (se guarda con la nota).
  late String _visibility = widget.note.visibility;

  bool _saving = false;
  bool _dirty = false;

  /// Modo selección: la nota se ve pero no se edita; se arrastra para elegir
  /// un tramo (letras de párrafos y tareas, y dibujos enteros) y se borra.
  bool _selecting = false;
  NoteSelection? _selection;
  final Map<Object, GlobalKey> _selKeys = {};
  final FocusNode _selectionFocus = FocusNode(debugLabel: 'note-selection');
  final ScrollController _docScroll = ScrollController();
  final GlobalKey _docKey = GlobalKey();
  Timer? _autoScrollTimer;
  double _autoScrollStep = 0;
  Offset _lastDrag = Offset.zero;

  @override
  void dispose() {
    _title.dispose();
    _titleFocus.dispose();
    _selectionFocus.dispose();
    _autoScrollTimer?.cancel();
    _docScroll.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  void _markDirty() {
    if (!_dirty) {
      _dirty = true;
      widget.onDirtyChanged?.call(true);
    }
    // Se recuerda el campo y la selección VIGENTES: al tocar la barra de
    // formato el campo puede perder el foco y aun así debe formatearse lo
    // que el usuario tenía seleccionado.
    final active = _focusedTextController;
    if (active != null) {
      _textTarget = active;
      _textTargetSelection = active.value.selection;
    }
    // También se reconstruye al cambiar la selección, para mostrar/actualizar
    // la barra de formato aunque el documento ya estuviera modificado.
    if (mounted) setState(() {});
  }

  TextEditingController _ctrl(Object key, String initial) {
    return _ctrls.putIfAbsent(key, () {
      final formats = key is NoteBlock
          ? key.formats
          : key is NoteItem
          ? key.formats
          : const <NoteTextRun>[];
      return NoteRichTextController(text: initial, formats: formats)
        ..addListener(_markDirty);
    });
  }

  FocusNode _focusFor(Object key) =>
      _focus.putIfAbsent(key, () => FocusNode()..addListener(_onFocus));

  bool get _wide => MediaQuery.sizeOf(context).width >= _kWideBreakpoint;

  bool get _canWrite => !widget.readOnly;

  // ---------------- Bloques ----------------

  /// Dónde entra lo nuevo: justo DEBAJO del bloque que se está escribiendo
  /// (la nota se lee de arriba abajo), o al final si no hay foco.
  int _insertAt() {
    for (var i = 0; i < _blocks.length; i++) {
      final block = _blocks[i];
      if (_focus[block]?.hasFocus ?? false) return i + 1;
      if (block.items.any((item) => _focus[item]?.hasFocus ?? false)) {
        return i + 1;
      }
    }
    return _blocks.length;
  }

  void _insertBlocks(List<NoteBlock> inserted) {
    final at = _insertAt().clamp(0, _blocks.length);
    setState(() => _blocks.insertAll(at, inserted));
    _markDirty();
  }

  void _focusField(Object key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _canWrite) _focusFor(key).requestFocus();
    });
  }

  void _addTextBlock() {
    final block = NoteBlock.text();
    _insertBlocks([block]);
    _focusField(block);
  }

  void _addChecklist() {
    final block = NoteBlock.checklist([NoteItem()]);
    // Debajo de la lista queda SIEMPRE un párrafo: el cuerpo de la nota es
    // texto y la lista es solo un complemento dentro de él.
    _insertBlocks([block, NoteBlock.text()]);
    _focusField(block.items.first);
  }

  void _addDrawing() {
    // Tomar la proporción del área útil (sin barras del sistema ni del módulo)
    // donde se inserta el lienzo.
    final screen = MediaQuery.sizeOf(context);
    final ratio =
        (_wide
                ? (screen.width - 360) / (screen.height - 210)
                : screen.width / (screen.height - 185))
            .clamp(.5, 2.0);

    // Insertar primero una tarjeta en el documento. El lienzo de pantalla
    // completa solo se abre cuando el usuario toca esa tarjeta; debajo queda
    // un párrafo para seguir escribiendo.
    final paragraph = NoteBlock.text();
    _insertBlocks([
      NoteBlock.drawing(pageColor: kNotePageColors.first, aspectRatio: ratio),
      paragraph,
    ]);
    // El cursor baja al párrafo: se escribe enseguida, sin tener que buscar el
    // hueco que queda debajo del dibujo.
    _focusField(paragraph);
  }

  void _removeBlock(int index) {
    setState(() {
      final b = _blocks.removeAt(index);
      _forget(b);
      if (_blocks.isEmpty) _blocks.add(NoteBlock.text());
    });
    _markDirty();
  }

  void _addItem(NoteBlock block, {NoteItem? after}) {
    final item = NoteItem();
    setState(() {
      final index = after == null ? -1 : block.items.indexOf(after);
      if (index < 0) {
        block.items.add(item);
      } else {
        block.items.insert(index + 1, item);
      }
    });
    _markDirty();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_canWrite) return;
      _focusFor(item).requestFocus();
    });
  }

  void _removeItem(NoteBlock block, NoteItem item) {
    final wasFocused = _focus[item]?.hasFocus ?? false;
    final itemIndex = block.items.indexOf(item);
    final adjacent = itemIndex > 0
        ? block.items[itemIndex - 1]
        : (itemIndex + 1 < block.items.length
              ? block.items[itemIndex + 1]
              : null);
    setState(() {
      block.items.remove(item);
      final removed = _ctrls.remove(item);
      // La barra de formato no debe quedar apuntando a un campo ya liberado.
      if (identical(removed, _textTarget)) _textTarget = null;
      removed?.dispose();
      _focus.remove(item)?.dispose();
      if (block.items.isEmpty) _blocks.remove(block);
      if (_blocks.isEmpty) _blocks.add(NoteBlock.text());
    });
    _markDirty();
    if (wasFocused && adjacent != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _canWrite) _focusFor(adjacent).requestFocus();
      });
    }
  }

  /// Enter en la ÚLTIMA casilla vacía de una lista: en vez de abrir otra
  /// casilla, la borra y baja el cursor al párrafo que va debajo de la lista
  /// (si no existe, se crea). Así la lista se cierra y el texto continúa.
  void _exitChecklist(NoteBlock block, NoteItem item) {
    final at = _blocks.indexOf(block);
    var listRemoved = false;
    setState(() {
      block.items.remove(item);
      final removed = _ctrls.remove(item);
      if (identical(removed, _textTarget)) _textTarget = null;
      removed?.dispose();
      _focus.remove(item)?.dispose();
      if (block.items.isEmpty) {
        _blocks.remove(block);
        _forget(block);
        listRemoved = true;
      }
      if (_blocks.isEmpty) _blocks.add(NoteBlock.text());
    });
    _markDirty();
    // Posición que ocupa ahora el bloque de abajo.
    final pos = (listRemoved ? at : at + 1).clamp(0, _blocks.length);
    final below = pos < _blocks.length ? _blocks[pos] : null;
    if (below != null && !below.isChecklist && !below.isDrawing) {
      // Ya hay un párrafo debajo: se reutiliza (no se llena la nota de huecos).
      _focusField(below);
      return;
    }
    final paragraph = NoteBlock.text();
    setState(() => _blocks.insert(pos, paragraph));
    _markDirty();
    _focusField(paragraph);
  }

  /// Cierra el documento con un párrafo: se usa al tocar la zona
  /// «Sigue escribiendo…» que aparece debajo de una lista o un dibujo.
  void _continueWriting() {
    if (!_canWrite) return;
    final last = _blocks.isEmpty ? null : _blocks.last;
    if (last != null && !last.isChecklist && !last.isDrawing) {
      _focusField(last);
      return;
    }
    final paragraph = NoteBlock.text();
    setState(() => _blocks.add(paragraph));
    _markDirty();
    _focusField(paragraph);
  }

  // ---------------- Selección de tramos (letras + dibujos) ----------------

  GlobalKey _selKey(Object key) => _selKeys.putIfAbsent(key, () => GlobalKey());

  void _enterSelection() {
    if (!_canWrite) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _stopAutoScroll();
    setState(() {
      _selecting = true;
      _selection = null;
    });
    _selectionFocus.requestFocus();
  }

  void _exitSelection() {
    _stopAutoScroll();
    setState(() {
      _selecting = false;
      _selection = null;
    });
  }

  KeyEventResult _selectionKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      _deleteSelection();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _exitSelection();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Rectángulos (globales) de lo seleccionable, en orden de lectura.
  List<_SelRegion> _selRegions() {
    final out = <_SelRegion>[];
    void add(int block, int item, String text, Object? key) {
      if (key == null) return;
      final renderObject = _selKeys[key]?.currentContext?.findRenderObject();
      final box = renderObject is RenderBox ? renderObject : null;
      if (box == null) return;
      out.add(
        _SelRegion(
          block: block,
          item: item,
          length: text.length,
          rect: box.localToGlobal(Offset.zero) & box.size,
          paragraph: renderObject is RenderParagraph ? renderObject : null,
        ),
      );
    }

    for (var i = 0; i < _blocks.length; i++) {
      final block = _blocks[i];
      if (block.isDrawing) {
        add(i, -1, '', block);
        continue;
      }
      if (block.isChecklist) {
        for (var j = 0; j < block.items.length; j++) {
          add(i, j, block.items[j].text, block.items[j]);
        }
        continue;
      }
      add(i, -1, block.text, block);
    }
    return out;
  }

  /// Punto de la nota que queda bajo una posición de la pantalla.
  NotePoint? _pointAt(Offset global) {
    final regions = _selRegions();
    if (regions.isEmpty) return null;
    double distance(_SelRegion r) {
      if (global.dy < r.rect.top) return r.rect.top - global.dy;
      if (global.dy > r.rect.bottom) return global.dy - r.rect.bottom;
      return 0;
    }

    var region = regions.first;
    var best = distance(regions.first);
    for (final r in regions) {
      if (r.rect.inflate(2).contains(global)) {
        region = r;
        best = 0;
        break;
      }
      final d = distance(r);
      if (d < best) {
        best = d;
        region = r;
      }
    }

    var offset = 0;
    final paragraph = region.paragraph;
    if (paragraph != null && region.length > 0) {
      offset = paragraph
          .getPositionForOffset(paragraph.globalToLocal(global))
          .offset
          .clamp(0, region.length);
    }
    if (global.dy < region.rect.top) offset = 0;
    if (global.dy > region.rect.bottom) offset = region.length;
    return NotePoint(region.block, item: region.item, offset: offset);
  }

  /// Un toque (sin arrastrar) elige el bloque completo.
  void _tapSelect(Offset global) {
    final point = _pointAt(global);
    if (point == null) return;
    final block = _blocks[point.block];
    NotePoint from;
    NotePoint to;
    if (block.isDrawing) {
      from = NotePoint(point.block);
      to = NotePoint(point.block);
    } else if (block.isChecklist) {
      if (block.items.isEmpty) return;
      from = NotePoint(point.block, item: 0);
      to = NotePoint(
        point.block,
        item: block.items.length - 1,
        offset: block.items.last.text.length,
      );
    } else {
      from = NotePoint(point.block);
      to = NotePoint(point.block, offset: block.text.length);
    }
    setState(() => _selection = NoteSelection(anchor: from, focus: to));
  }

  void _selectionDragStart(Offset global) {
    final point = _pointAt(global);
    setState(
      () => _selection = point == null
          ? null
          : NoteSelection(anchor: point, focus: point),
    );
    _lastDrag = global;
    _updateAutoScroll(global);
  }

  void _selectionDragUpdate(Offset global) {
    final current = _selection;
    _lastDrag = global;
    _updateAutoScroll(global);
    if (current == null) return;
    final point = _pointAt(global);
    if (point == null) return;
    setState(
      () => _selection = NoteSelection(anchor: current.anchor, focus: point),
    );
  }

  /// Al arrastrar cerca del borde, la hoja se desplaza sola para poder
  /// seleccionar más allá de lo que se ve (notas largas).
  void _updateAutoScroll(Offset global) {
    final box = _docKey.currentContext?.findRenderObject();
    if (!_selecting || box is! RenderBox) {
      _stopAutoScroll();
      return;
    }
    const edge = 56.0;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    var step = 0.0;
    if (global.dy < rect.top + edge) step = -1;
    if (global.dy > rect.bottom - edge) step = 1;
    if (step == 0) {
      _stopAutoScroll();
      return;
    }
    if (_autoScrollTimer != null && _autoScrollStep == step) return;
    _stopAutoScroll();
    _autoScrollStep = step;
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 32), (_) {
      if (!mounted || !_docScroll.hasClients) return;
      final position = _docScroll.position;
      final next = (position.pixels + _autoScrollStep * 16).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (next == position.pixels) return;
      _docScroll.jumpTo(next);
      // Al moverse la hoja, el tramo sigue al dedo.
      final selection = _selection;
      if (selection == null) return;
      final point = _pointAt(_lastDrag);
      if (point == null) return;
      setState(
        () =>
            _selection = NoteSelection(anchor: selection.anchor, focus: point),
      );
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollStep = 0;
  }

  /// Elimina lo seleccionado: los bloques completos (dibujo incluido) y, en el
  /// bloque cortado a la mitad, solo las letras elegidas.
  void _deleteSelection() {
    final selection = _selection;
    if (!_canWrite || selection == null) return;
    _stopAutoScroll();
    _syncBlocks();
    final before = List<NoteBlock>.of(_blocks);
    final remaining = deleteSelection(_blocks, selection);
    // Los campos tocados se recrean con el texto que quedó.
    for (final block in before) {
      _forget(block);
    }
    setState(() {
      _blocks
        ..clear()
        ..addAll(remaining);
      _selection = null;
    });
    _markDirty();
  }

  bool _blockSelected(int index) =>
      _selecting && (_selection?.touchesBlock(index) ?? false);

  /// Delete/retroceso en un párrafo VACÍO (el que dice «Sigue escribiendo…»):
  /// se elimina solo, sin dejar huecos en la nota, y el cursor sube al bloque
  /// anterior. Nunca se borra el último bloque que queda.
  KeyEventResult _handleEmptyParagraphBackspace(
    NoteBlock block,
    KeyEvent event,
  ) {
    if (!_canWrite || event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    if (block.isChecklist || block.isDrawing) return KeyEventResult.ignored;
    final controller = _ctrls[block];
    final empty = (controller?.text ?? block.text).isEmpty;
    final index = _blocks.indexOf(block);
    if (!empty || index < 0 || _blocks.length <= 1) {
      return KeyEventResult.ignored;
    }
    final above = index > 0 ? _blocks[index - 1] : null;
    setState(() {
      _blocks.removeAt(index);
      _forget(block);
      if (_blocks.isEmpty) _blocks.add(NoteBlock.text());
    });
    _markDirty();
    // El cursor se va al final de lo que hay arriba (texto) o a su última
    // tarea, para seguir escribiendo donde estaba la nota.
    if (above != null) {
      final target = above.isChecklist && above.items.isNotEmpty
          ? above.items.last
          : above;
      _focusEnd(target);
    }
    return KeyEventResult.handled;
  }

  /// Enfoca un campo y pone el cursor al final de su texto.
  void _focusEnd(Object key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_canWrite) return;
      _focusFor(key).requestFocus();
      final controller = _ctrls[key];
      if (controller == null) return;
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
    });
  }

  KeyEventResult _handleEmptyTaskBackspace(
    NoteBlock block,
    NoteItem item,
    KeyEvent event,
  ) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        item.text.isEmpty &&
        block.items.contains(item)) {
      _removeItem(block, item);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onTaskChanged(NoteItem item, String value) {
    item.text = value;
    _markDirty();
  }

  NoteRichTextController? get _focusedTextController {
    if (_titleFocus.hasFocus) return _title;
    return _focus.entries
        .where((entry) => entry.value.hasFocus)
        .map((entry) => _ctrls[entry.key])
        .whereType<NoteRichTextController>()
        .firstOrNull;
  }

  /// Campo sobre el que actúa la barra de formato (aunque el botón le quite
  /// el foco al campo).
  NoteRichTextController? get _formatTarget =>
      _focusedTextController ?? _textTarget;

  TextSelection get _formatSelection {
    final focused = _focusedTextController;
    if (focused != null) return focused.value.selection;
    return _textTargetSelection;
  }

  void _applyFormatToSelection({
    bool? bold,
    bool? italic,
    bool? underline,
    String? fontFamily,
    double? fontSize,
  }) {
    final target = _formatTarget;
    if (target == null) return;
    var selection = _formatSelection;
    if (!selection.isValid) selection = target.value.selection;
    target.applyFormat(
      bold: bold,
      italic: italic,
      underline: underline,
      fontFamily: fontFamily,
      fontSize: fontSize,
      range: selection,
    );
    // Se recuerda el rango elegido: así se puede volver a pulsar (negrita,
    // cursiva…) sobre la MISMA selección sin que se pierda.
    _textTarget = target;
    _textTargetSelection = selection;
    _markDirty();
    if (mounted) setState(() {});
  }

  void _forget(NoteBlock block) {
    void release(Object key) {
      final controller = _ctrls.remove(key);
      // La barra de formato no debe quedar apuntando a un campo ya liberado.
      if (identical(controller, _textTarget)) _textTarget = null;
      controller?.dispose();
      _focus.remove(key)?.dispose();
    }

    release(block);
    for (final item in block.items) {
      release(item);
    }
  }

  /// Abre el lienzo a PANTALLA COMPLETA. Devuelve los trazos, o null si se
  /// cancela.
  Future<_DrawingResult?> _pushDrawing(NoteBlock block) async {
    if (!_canWrite) return null;
    return Navigator.of(context).push<_DrawingResult>(
      MaterialPageRoute<_DrawingResult>(
        builder: (_) => DrawingPage(
          strokes: block.strokes,
          pageColor: block.pageColor,
          aspectRatio: block.aspectRatio,
        ),
      ),
    );
  }

  void _titleFormatsSync() {
    widget.note.titleFormats = _title.formats.toList();
  }

  /// Abre el dibujo a PANTALLA COMPLETA y guarda lo que se dibuje ahí.
  Future<void> _editDrawing(NoteBlock block) async {
    if (!_canWrite) return;
    final result = await _pushDrawing(block);
    if (result == null || !mounted) return;
    setState(() {
      block
        ..strokes = result.strokes
        ..pageColor = result.pageColor
        ..aspectRatio = result.aspectRatio;
    });
    _markDirty();
  }

  // ---------------- Guardar / cerrar ----------------

  /// Copia el texto de los controllers a los bloques antes de serializar.
  void _syncBlocks() {
    _titleFormatsSync();
    for (final b in _blocks) {
      if (b.isChecklist) {
        for (final item in b.items) {
          final controller = _ctrl(item, item.text);
          item.text = controller.text;
          if (controller is NoteRichTextController) {
            item.formats = controller.formats.toList();
          }
        }
      } else if (!b.isDrawing) {
        final controller = _ctrl(b, b.text);
        b.text = controller.text;
        if (controller is NoteRichTextController) {
          b.formats = controller.formats.toList();
        }
      }
    }
  }

  Future<void> _save() async {
    if (_saving || !_canWrite) return;
    _syncBlocks();
    final payload = Note(
      id: widget.note.id,
      title: _title.text,
      titleFormats: _title.formats.toList(),
      blocks: _blocks,
      color: widget.note.color,
      pinned: widget.note.pinned,
      visibility: _visibility,
      ownerId: widget.note.ownerId,
      ownerName: widget.note.ownerName,
      mine: widget.note.mine,
    );
    setState(() => _saving = true);
    try {
      final saved = await HsApi.saveNote(payload);
      if (!mounted) return;
      widget.note
        ..id = saved.id
        ..updated = saved.updated
        ..title = saved.title
        ..visibility = _visibility;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      widget.onDirtyChanged?.call(false);
      widget.onSaved?.call(saved);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _close() async {
    final close = widget.onClose;
    if (close == null) return;
    if (_dirty) {
      final ok = await _confirmDiscard(context);
      if (!ok || !mounted) return;
    }
    close();
  }

  Future<void> _pickVisibility() async {
    if (!_canWrite) return;
    final scheme = Theme.of(context).colorScheme;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
                child: Text(
                  '¿Quién puede ver esta nota?',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              _visibilityTile(
                ctx,
                value: 'private',
                icon: Icons.lock_outline_rounded,
                title: 'Personal',
                subtitle: 'Solo tú puedes verla y editarla.',
              ),
              const SizedBox(height: 8),
              _visibilityTile(
                ctx,
                value: 'company',
                icon: Icons.groups_2_outlined,
                title: 'Empresa',
                subtitle:
                    'La ve todo el equipo de ${HsSession.companyName.isEmpty ? 'tu empresa' : HsSession.companyName}; '
                    'solo tú la editas.',
              ),
              const SizedBox(height: 10),
              Text(
                'Se aplica al guardar.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _visibility = chosen);
    _markDirty();
  }

  Widget _visibilityTile(
    BuildContext context, {
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final active = _visibility == value;
    return Material(
      color: active
          ? AppColors.brand.withValues(alpha: .10)
          : scheme.surfaceContainerHighest.withValues(alpha: .30),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).pop(value),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active
                  ? AppColors.brand.withValues(alpha: .45)
                  : scheme.outlineVariant.withValues(alpha: .45),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: active ? AppColors.brand : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (active)
                Icon(
                  Icons.check_circle_rounded,
                  size: 19,
                  color: AppColors.brand,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(scheme),
        if (!_canWrite) _readOnlyBanner(scheme),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: _selecting
                  ? Focus(
                      focusNode: _selectionFocus,
                      onKeyEvent: _selectionKey,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) => _tapSelect(d.globalPosition),
                        onPanStart: (d) =>
                            _selectionDragStart(d.globalPosition),
                        onPanUpdate: (d) =>
                            _selectionDragUpdate(d.globalPosition),
                        onPanEnd: (_) => _stopAutoScroll(),
                        onPanCancel: _stopAutoScroll,
                        child: _document(scheme),
                      ),
                    )
                  : _document(scheme),
            ),
          ),
        ),
        if (_canWrite && _selecting)
          _selectionBar(scheme)
        else ...[
          if (_canWrite) _formatToolbar(scheme),
          if (_canWrite) _insertBar(scheme),
        ],
      ],
    );
  }

  Widget _document(ColorScheme scheme) {
    return ListView(
      key: _docKey,
      controller: _docScroll,
      // En modo selección el dedo elige un tramo: la hoja no hace scroll, salvo
      // el automático cuando el dedo llega al borde.
      physics: _selecting ? const NeverScrollableScrollPhysics() : null,
      padding: EdgeInsets.fromLTRB(_wide ? 28 : 18, 4, _wide ? 28 : 14, 28),
      children: [
        for (var i = 0; i < _blocks.length; i++) _blockView(scheme, i),
        // La nota siempre puede seguir creciendo: si termina en una lista o un
        // dibujo, aquí se puede tocar y escribir debajo.
        if (!_selecting &&
            _canWrite &&
            _blocks.isNotEmpty &&
            (_blocks.last.isChecklist || _blocks.last.isDrawing))
          _continueZone(scheme),
        const SizedBox(height: 6),
      ],
    );
  }

  // ---------------- Cabecera ----------------

  Widget _header(ColorScheme scheme) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.onClose != null ? 4 : 18,
        widget.onClose != null ? 2 : 12,
        10,
        4,
      ),
      child: Row(
        children: [
          if (widget.onClose != null)
            IconButton(
              tooltip: 'Volver',
              onPressed: _close,
              icon: const Icon(Icons.arrow_back_rounded, size: 22),
            ),
          if (_canWrite) ...[
            _visibilityButton(scheme),
            const SizedBox(width: 8),
          ] else
            const SizedBox(width: 4),
          // El TÍTULO va al lado de la visibilidad: es la cabecera de la nota,
          // no una línea más de la hoja.
          Expanded(child: _titleField(scheme)),
          if (_canWrite) ...[
            // Puntito de cambios sin guardar.
            AnimatedOpacity(
              opacity: _dirty ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: AppColors.brand,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // Guardar: SOLO icono (en el celular no cabe una etiqueta).
            IconButton.filled(
              tooltip: 'Guardar nota',
              onPressed: _saving ? null : _save,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                minimumSize: const Size(42, 42),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 21),
            ),
          ],
        ],
      ),
    );
  }

  Widget _visibilityButton(ColorScheme scheme) {
    final shared = _visibility == 'company';
    return Tooltip(
      message: shared ? 'Compartida con la empresa' : 'Solo para ti',
      child: Material(
        color: shared
            ? AppColors.brand.withValues(alpha: .12)
            : scheme.surfaceContainerHighest.withValues(alpha: .34),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: _pickVisibility,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  shared ? Icons.groups_2_outlined : Icons.lock_outline_rounded,
                  size: 15,
                  color: shared ? AppColors.brand : scheme.onSurfaceVariant,
                ),
                if (_wide) ...[
                  const SizedBox(width: 6),
                  Text(
                    shared ? 'Empresa' : 'Personal',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: shared ? AppColors.brand : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(width: 2),
                Icon(
                  Icons.expand_more_rounded,
                  size: 15,
                  color: shared ? AppColors.brand : scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _readOnlyBanner(ColorScheme scheme) {
    final who = widget.note.ownerName.trim();
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Icon(
            Icons.visibility_outlined,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              who.isEmpty
                  ? 'Solo lectura: esta nota la compartió la empresa.'
                  : 'Solo lectura: nota de $who compartida con la empresa.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.3,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- Título (texto editable sin aspecto de campo) ----------------

  Widget _titleField(ColorScheme scheme) {
    return TextField(
      controller: _title,
      focusNode: _titleFocus,
      readOnly: !_canWrite,
      maxLines: 1,
      textInputAction: TextInputAction.next,
      cursorColor: AppColors.brand,
      style: TextStyle(
        fontSize: _wide ? 21 : 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -.4,
        height: 1.2,
      ),
      decoration: InputDecoration(
        hintText: 'Título',
        hintStyle: TextStyle(
          fontSize: _wide ? 21 : 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -.5,
          color: scheme.onSurfaceVariant.withValues(alpha: .5),
        ),
        filled: false,
        fillColor: Colors.transparent,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        isDense: true,
      ),
    );
  }

  Widget _formatToolbar(ColorScheme scheme) {
    final target = _formatTarget;
    if (target == null) return const SizedBox.shrink();
    final selection = _formatSelection;

    bool enabled({bool? bold, bool? italic, bool? underline}) =>
        target.hasFormat(
          bold: bold,
          italic: italic,
          underline: underline,
          range: selection,
        );

    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: .42),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            _formatButton(
              scheme,
              icon: Icons.format_bold_rounded,
              tooltip: 'Negrita',
              selected: enabled(bold: true),
              onPressed: () =>
                  _applyFormatToSelection(bold: !enabled(bold: true)),
            ),
            _formatButton(
              scheme,
              icon: Icons.format_italic_rounded,
              tooltip: 'Cursiva',
              selected: enabled(italic: true),
              onPressed: () =>
                  _applyFormatToSelection(italic: !enabled(italic: true)),
            ),
            _formatButton(
              scheme,
              icon: Icons.format_underline_rounded,
              tooltip: 'Subrayado',
              selected: enabled(underline: true),
              onPressed: () =>
                  _applyFormatToSelection(underline: !enabled(underline: true)),
            ),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              tooltip: 'Fuente',
              onSelected: (value) => _applyFormatToSelection(fontFamily: value),
              itemBuilder: (_) => const [
                PopupMenuItem(value: '', child: Text('Predeterminada')),
                PopupMenuItem(value: 'Roboto', child: Text('Roboto')),
                PopupMenuItem(value: 'serif', child: Text('Serif')),
                PopupMenuItem(value: 'monospace', child: Text('Monoespaciada')),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.font_download_outlined,
                      size: 17,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Fuente',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const Icon(Icons.expand_more_rounded, size: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            PopupMenuButton<double>(
              tooltip: 'Tamaño de letra',
              onSelected: (value) => _applyFormatToSelection(fontSize: value),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 12, child: Text('Pequeña · 12')),
                PopupMenuItem(value: 15.5, child: Text('Normal · 16')),
                PopupMenuItem(value: 20, child: Text('Grande · 20')),
                PopupMenuItem(value: 26, child: Text('Muy grande · 26')),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.format_size_rounded,
                      size: 17,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Tamaño',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const Icon(Icons.expand_more_rounded, size: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formatButton(
    ColorScheme scheme, {
    required IconData icon,
    required String tooltip,
    required bool selected,
    required VoidCallback onPressed,
  }) => IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    isSelected: selected,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      foregroundColor: selected ? AppColors.brand : scheme.onSurfaceVariant,
      backgroundColor: selected ? AppColors.brand.withValues(alpha: .12) : null,
    ),
    icon: Icon(icon, size: 19),
  );

  // ---------------- Bloques (insertados en la hoja) ----------------

  Widget _blockView(ColorScheme scheme, int index) {
    final block = _blocks[index];
    if (block.isDrawing) return _drawingBlock(scheme, block, index);
    if (block.isChecklist) {
      return _selecting
          ? _checklistSelectionView(scheme, block, index)
          : _checklistBlock(scheme, block, index);
    }
    return _selecting
        ? _textSelectionView(scheme, block, index)
        : _textBlock(scheme, block, index);
  }

  /// Párrafo en modo selección: mismo texto y estilo, pero ya no es un campo
  /// (no se puede escribir) y el tramo elegido se ve resaltado.
  Widget _textSelectionView(ColorScheme scheme, NoteBlock block, int index) {
    const base = TextStyle(fontSize: 15.5, height: 1.6);
    final text = block.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
        child: text.isEmpty
            ? Text(
                'Sigue escribiendo…',
                key: _selKey(block),
                style: base.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: .45),
                ),
              )
            : Text.rich(
                key: _selKey(block),
                TextSpan(
                  children: highlightedSpans(
                    text: text,
                    formats: block.formats,
                    base: base,
                    range: _selection?.rangeIn(index, -1, text.length),
                    highlight: AppColors.brand.withValues(alpha: .24),
                  ),
                ),
                style: base.copyWith(color: scheme.onSurface),
              ),
      ),
    );
  }

  /// Lista de actividades en modo selección (casilla quieta + texto).
  Widget _checklistSelectionView(
    ColorScheme scheme,
    NoteBlock block,
    int index,
  ) {
    const base = TextStyle(fontSize: 15.5, height: 1.6);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var j = 0; j < block.items.length; j++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      block.items[j].done
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 21,
                      color: block.items[j].done
                          ? AppColors.brand
                          : scheme.onSurfaceVariant.withValues(alpha: .6),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      key: _selKey(block.items[j]),
                      TextSpan(
                        children: highlightedSpans(
                          text: block.items[j].text,
                          formats: block.items[j].formats,
                          base: base,
                          range: _selection?.rangeIn(
                            index,
                            j,
                            block.items[j].text.length,
                          ),
                          highlight: AppColors.brand.withValues(alpha: .24),
                        ),
                      ),
                      style: base.copyWith(
                        color: block.items[j].done
                            ? scheme.onSurfaceVariant.withValues(alpha: .8)
                            : scheme.onSurface,
                        decoration: block.items[j].done
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
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

  Widget _textBlock(ColorScheme scheme, NoteBlock block, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Focus(
        onKeyEvent: (_, event) => _handleEmptyParagraphBackspace(block, event),
        child: TextField(
          controller: _ctrl(block, block.text),
          focusNode: _focusFor(block),
          readOnly: !_canWrite,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(fontSize: 15.5, height: 1.6),
          cursorColor: AppColors.brand,
          decoration: InputDecoration(
            // Un hueco vacío se anuncia en texto tenue: el cuerpo de la nota es
            // texto, también debajo de una lista o de un dibujo.
            hintText: index == 0 ? 'Escribe algo…' : 'Sigue escribiendo…',
            hintStyle: TextStyle(
              fontSize: 15.5,
              color: scheme.onSurfaceVariant.withValues(alpha: .55),
            ),
            filled: false,
            fillColor: Colors.transparent,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 7,
              horizontal: 2,
            ),
          ),
        ),
      ),
    );
  }

  /// Cierre del documento cuando la nota acaba en lista o dibujo: al tocarla
  /// se agrega (o se enfoca) el párrafo de abajo. Sin esto, el espacio libre
  /// bajo el último bloque no respondía al tacto.
  Widget _continueZone(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        onTap: _continueWriting,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              Icon(
                Icons.edit_outlined,
                size: 14,
                color: scheme.onSurfaceVariant.withValues(alpha: .7),
              ),
              const SizedBox(width: 6),
              Text(
                'Sigue escribiendo…',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant.withValues(alpha: .7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _checklistBlock(ColorScheme scheme, NoteBlock block, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in block.items) _checklistRow(scheme, block, item),
        ],
      ),
    );
  }

  Widget _checklistRow(ColorScheme scheme, NoteBlock block, NoteItem item) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 30,
          height: 34,
          child: Checkbox(
            value: item.done,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            side: BorderSide(
              color: scheme.onSurfaceVariant.withValues(alpha: .55),
              width: 1.4,
            ),
            onChanged: _canWrite
                ? (v) {
                    setState(() => item.done = v == true);
                    _markDirty();
                  }
                : null,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Focus(
            onKeyEvent: (_, event) =>
                _handleEmptyTaskBackspace(block, item, event),
            child: TextField(
              key: ValueKey('note-task-${identityHashCode(item)}'),
              controller: _ctrl(item, item.text),
              focusNode: _focusFor(item),
              readOnly: !_canWrite,
              maxLines: 1,
              textInputAction: TextInputAction.next,
              onChanged: (value) => _onTaskChanged(item, value),
              onSubmitted: (value) {
                // Cada casilla es una tarea: Enter abre otra debajo. Si la
                // casilla está VACÍA y es la última (y ya hay tareas encima),
                // Enter la borra y el texto continúa en el párrafo de abajo:
                // así la lista se cierra pulsando Enter dos veces.
                item.text = value;
                if (value.trim().isEmpty &&
                    block.items.length > 1 &&
                    block.items.last == item) {
                  _exitChecklist(block, item);
                  return;
                }
                _addItem(block, after: item);
              },
              style: TextStyle(
                fontSize: 15.5,
                height: 1.6,
                decoration: item.done
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
                color: item.done
                    ? scheme.onSurfaceVariant.withValues(alpha: .8)
                    : scheme.onSurface,
              ),
              cursorColor: AppColors.brand,
              decoration: InputDecoration(
                hintText: 'Escribe una tarea…',
                hintStyle: TextStyle(
                  fontSize: 15.5,
                  color: scheme.onSurfaceVariant.withValues(alpha: .45),
                ),
                filled: false,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 7),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// DIBUJO insertado: una tarjeta con el lienzo en miniatura. Al tocarla se
  /// abre a pantalla completa para seguir dibujando.
  Widget _drawingBlock(ColorScheme scheme, NoteBlock block, int index) {
    final strokes = block.strokes;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.draw_outlined,
                size: 15,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'Dibujo',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .3,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              if (strokes.isNotEmpty)
                Text(
                  '· ${strokes.length} ${strokes.length == 1 ? 'trazo' : 'trazos'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant.withValues(alpha: .8),
                  ),
                ),
              const Spacer(),
              if (_canWrite && !_selecting)
                IconButton(
                  tooltip: 'Quitar dibujo',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _removeBlock(index),
                  icon: Icon(
                    Icons.close_rounded,
                    size: 17,
                    color: scheme.onSurfaceVariant.withValues(alpha: .8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            // En modo selección el dibujo no se abre: se elige y se borra.
            onTap: (_canWrite && !_selecting)
                ? () => _editDrawing(block)
                : null,
            child: SizedBox(
              key: _selKey(block),
              height:
                  (_wide ? 250.0 : 260.0) /
                  (block.aspectRatio > 1 ? block.aspectRatio : 1),
              child: Center(
                child: AspectRatio(
                  aspectRatio: block.aspectRatio,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _blockSelected(index)
                            ? AppColors.brand
                            : scheme.outlineVariant.withValues(alpha: .55),
                        width: _blockSelected(index) ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .06),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DrawingThumb(
                          strokes: strokes,
                          pageColor: block.pageColor,
                          aspectRatio: block.aspectRatio,
                        ),
                        if (strokes.isEmpty)
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.gesture_rounded,
                                  size: 26,
                                  color: const Color(0xFF1F2937)
                                      .withValues(alpha: .4),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Toca para dibujar',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .82),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: const Icon(
                              Icons.open_in_full_rounded,
                              size: 14,
                              color: Color(0xFF374151),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Barra inferior para INSERTAR contenido en la nota.
  Widget _insertBar(ColorScheme scheme) {
    final buttons = <Widget>[
      _insertButton(
        scheme,
        icon: Icons.notes_rounded,
        label: 'Texto',
        onTap: _addTextBlock,
      ),
      _insertButton(
        scheme,
        icon: Icons.checklist_rounded,
        label: 'Lista',
        onTap: _addChecklist,
      ),
      _insertButton(
        scheme,
        icon: Icons.draw_outlined,
        label: 'Dibujo',
        onTap: _addDrawing,
      ),
      Tooltip(
        message: 'Seleccionar texto y dibujos',
        child: _insertButton(
          scheme,
          icon: Icons.select_all_rounded,
          // En el celular solo el icono: la etiqueta no cabe en la barra.
          label: _wide ? 'Seleccionar' : '',
          onTap: _enterSelection,
        ),
      ),
    ];
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(_wide ? 18 : 12, 4, _wide ? 18 : 12, 10),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh.withValues(alpha: .96),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .5),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .10),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(child: buttons[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Barra del modo selección: dice qué se va a borrar y lo elimina.
  Widget _selectionBar(ColorScheme scheme) {
    final selection = _selection;
    final active = selection != null;
    final count = selection == null
        ? 0
        : selection.end.block - selection.start.block + 1;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(_wide ? 18 : 12, 4, _wide ? 18 : 12, 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh.withValues(alpha: .98),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.brand.withValues(alpha: .35)),
          ),
          child: Row(
            children: [
              Icon(Icons.select_all_rounded, size: 18, color: AppColors.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  !active
                      ? 'Arrastra sobre la nota para seleccionar'
                      : (count == 1
                            ? 'Tramo seleccionado'
                            : '$count bloques seleccionados'),
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface.withValues(alpha: .85),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Cancelar selección',
                visualDensity: VisualDensity.compact,
                onPressed: _exitSelection,
                icon: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Tooltip(
                message: 'Eliminar selección',
                child: FilledButton.icon(
                  onPressed: active ? _deleteSelection : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.symmetric(horizontal: _wide ? 14 : 10),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: _wide
                      ? const Text('Eliminar')
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _insertButton(
    ColorScheme scheme, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: AppColors.brand),
              const SizedBox(width: 6),
              // Flexible: en teléfonos angostos la etiqueta se recorta en vez
              // de desbordar la barra.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface.withValues(alpha: .9),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================================================================
// LIENZO COMPLETO (pantalla del dibujo)
// ==================================================================

enum _DrawTool { pen, marker, eraser }

/// Pantalla completa para DIBUJAR un bloque de la nota.
///
/// Devuelve los trazos con `Navigator.pop(strokes)`; `null` = cancelar.
class _DrawingResult {
  const _DrawingResult({
    required this.strokes,
    required this.pageColor,
    required this.aspectRatio,
  });

  final List<NoteStroke> strokes;
  final Color pageColor;
  final double aspectRatio;
}

class DrawingPage extends StatefulWidget {
  const DrawingPage({
    super.key,
    required this.strokes,
    required this.pageColor,
    required this.aspectRatio,
  });

  final List<NoteStroke> strokes;
  final Color pageColor;
  final double aspectRatio;

  @override
  State<DrawingPage> createState() => _DrawingPageState();
}

class _DrawingPageState extends State<DrawingPage> {
  late List<NoteStroke> _strokes = List<NoteStroke>.of(widget.strokes);
  late Color _pageColor = widget.pageColor;
  late double _aspectRatio = widget.aspectRatio;
  final List<List<NoteStroke>> _undo = [];
  final List<List<NoteStroke>> _redo = [];

  _DrawTool _tool = _DrawTool.pen;
  int _inkIndex = 0;
  int _widthIndex = 1;

  bool _changed = false;

  static const _penWidths = [2.0, 3.5, 6.0];
  static const _markerWidths = [12.0, 18.0, 26.0];

  Color get _color {
    if (_tool == _DrawTool.marker) {
      return kNoteMarkers[_inkIndex.clamp(0, kNoteMarkers.length - 1)];
    }
    return kNoteInks[_inkIndex.clamp(0, kNoteInks.length - 1)];
  }

  double get _width {
    final list = _tool == _DrawTool.marker ? _markerWidths : _penWidths;
    return list[_widthIndex.clamp(0, list.length - 1)];
  }

  Future<void> _cancel() async {
    if (!_changed) {
      Navigator.of(context).pop();
      return;
    }
    final ok = await _confirmDiscard(context);
    if (!ok || !mounted) return;
    Navigator.of(context).pop();
  }

  void _apply(List<NoteStroke> next) {
    _undo.add(List<NoteStroke>.of(_strokes));
    if (_undo.length > 50) _undo.removeAt(0);
    _redo.clear();
    setState(() {
      _strokes = next;
      _changed = true;
    });
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    setState(() {
      _redo.add(List<NoteStroke>.of(_strokes));
      _strokes = _undo.removeLast();
      _changed = true;
    });
  }

  void _redoLast() {
    if (_redo.isEmpty) return;
    setState(() {
      _undo.add(List<NoteStroke>.of(_strokes));
      _strokes = _redo.removeLast();
      _changed = true;
    });
  }

  void _clear() {
    if (_strokes.isEmpty) return;
    _apply(<NoteStroke>[]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _cancel();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _topBar(scheme),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: NoteCanvas(
                    strokes: _strokes,
                    ink: _color,
                    strokeWidth: _width,
                    eraser: _tool == _DrawTool.eraser,
                    pageColor: _pageColor,
                    aspectRatio: _aspectRatio,
                    allowZoom: true,
                    onChanged: _apply,
                  ),
                ),
              ),
              _tools(scheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Volver',
            onPressed: _cancel,
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
          ),
          const SizedBox(width: 2),
          const Expanded(
            child: Text(
              'Dibujo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: 'Deshacer',
            onPressed: _undo.isEmpty ? null : _undoLast,
            icon: const Icon(Icons.undo_rounded, size: 21),
          ),
          IconButton(
            tooltip: 'Rehacer',
            onPressed: _redo.isEmpty ? null : _redoLast,
            icon: const Icon(Icons.redo_rounded, size: 21),
          ),
          IconButton(
            tooltip: 'Borrar todo',
            onPressed: _strokes.isEmpty ? null : _clear,
            icon: const Icon(Icons.delete_sweep_outlined, size: 21),
          ),
          const SizedBox(width: 4),
          IconButton.filled(
            tooltip: 'Listo',
            onPressed: () => Navigator.of(context).pop(
              _DrawingResult(
                strokes: _strokes,
                pageColor: _pageColor,
                aspectRatio: _aspectRatio,
              ),
            ),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
              minimumSize: const Size(42, 42),
            ),
            icon: const Icon(Icons.check_rounded, size: 21),
          ),
        ],
      ),
    );
  }

  Widget _tools(ColorScheme scheme) {
    final widths = _tool == _DrawTool.marker ? _markerWidths : _penWidths;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: .96),
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Herramientas: lápiz, resaltador y goma.
          Row(
            children: [
              _toolChip(
                scheme,
                tool: _DrawTool.pen,
                icon: Icons.edit_rounded,
                label: 'Lápiz',
              ),
              const SizedBox(width: 8),
              _toolChip(
                scheme,
                tool: _DrawTool.marker,
                icon: Icons.brush_rounded,
                label: 'Resaltador',
              ),
              const SizedBox(width: 8),
              _toolChip(
                scheme,
                tool: _DrawTool.eraser,
                icon: Icons.auto_fix_normal_rounded,
                label: 'Goma',
              ),
            ],
          ),
          Row(
            children: [
              Icon(
                Icons.color_lens_outlined,
                size: 17,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: kNotePageColors.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) =>
                        _pageColorDot(scheme, index),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Vertical',
                visualDensity: VisualDensity.compact,
                isSelected: _aspectRatio < 1,
                onPressed: () => setState(() => _aspectRatio = .72),
                icon: const Icon(Icons.stay_current_portrait_rounded, size: 19),
              ),
              IconButton(
                tooltip: 'Horizontal',
                visualDensity: VisualDensity.compact,
                isSelected: _aspectRatio >= 1,
                onPressed: () => setState(() => _aspectRatio = 1.42),
                icon: const Icon(
                  Icons.stay_current_landscape_rounded,
                  size: 19,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_tool != _DrawTool.eraser) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                // Colores.
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: kNoteInks.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) => _inkDot(scheme, i),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Grosores.
                for (var i = 0; i < widths.length; i++) ...[
                  _widthDot(scheme, i, widths[i]),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Toca un trazo para borrarlo',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pageColorDot(ColorScheme scheme, int index) {
    final color = kNotePageColors[index];
    final active = _pageColor == color;
    return GestureDetector(
      onTap: () => setState(() {
        _pageColor = color;
        _changed = true;
      }),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? AppColors.brand : scheme.outlineVariant,
            width: active ? 2.2 : 1,
          ),
        ),
        child: active
            ? Icon(
                Icons.check_rounded,
                size: 14,
                color: color.computeLuminance() > .55
                    ? Colors.black87
                    : Colors.white,
              )
            : null,
      ),
    );
  }

  Widget _toolChip(
    ColorScheme scheme, {
    required _DrawTool tool,
    required IconData icon,
    required String label,
  }) {
    final active = _tool == tool;
    return Expanded(
      child: Material(
        color: active
            ? AppColors.brand.withValues(alpha: .12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _tool = tool),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active
                    ? AppColors.brand.withValues(alpha: .45)
                    : scheme.outlineVariant.withValues(alpha: .5),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: active ? AppColors.brand : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: active ? AppColors.brand : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _inkDot(ColorScheme scheme, int index) {
    final active = _inkIndex == index;
    final color = _tool == _DrawTool.marker
        ? kNoteInks[index].withValues(alpha: .55)
        : kNoteInks[index];
    return GestureDetector(
      onTap: () => setState(() => _inkIndex = index),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: active
                ? scheme.onSurface
                : Colors.black.withValues(alpha: .12),
            width: active ? 2.4 : 1,
          ),
        ),
        child: active
            ? Icon(
                Icons.check_rounded,
                size: 14,
                color: color.computeLuminance() > .6
                    ? Colors.black87
                    : Colors.white,
              )
            : null,
      ),
    );
  }

  Widget _widthDot(ColorScheme scheme, int index, double width) {
    final active = _widthIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _widthIndex = index),
      child: Container(
        width: 34,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? AppColors.brand.withValues(alpha: .12)
              : scheme.surfaceContainerHighest.withValues(alpha: .30),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? AppColors.brand.withValues(alpha: .45)
                : scheme.outlineVariant.withValues(alpha: .45),
          ),
        ),
        child: Container(
          width: 16,
          height: width.clamp(2, 7),
          decoration: BoxDecoration(
            color: active ? AppColors.brand : scheme.onSurfaceVariant,
            borderRadius: BorderRadius.circular(width),
          ),
        ),
      ),
    );
  }
}

// ==================================================================
// MINIATURA DEL DIBUJO (bloque insertado en la nota)
// ==================================================================

class DrawingThumb extends StatelessWidget {
  const DrawingThumb({
    super.key,
    required this.strokes,
    this.pageColor = const Color(0xFFFDFDFB),
    this.aspectRatio = .72,
  });

  final List<NoteStroke> strokes;
  final Color pageColor;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: pageColor,
      child: CustomPaint(
        painter: _StrokesPainter(strokes: strokes, current: const []),
        child: const SizedBox.expand(),
      ),
    );
  }
}

// ==================================================================
// LIENZO DEL DIBUJO (interactivo)
// ==================================================================

/// Lienzo de dibujo a mano alzada.
///
/// Los puntos se guardan NORMALIZADOS (0..1), así la nota se ve igual en el
/// celular y en la computadora. La goma BORRA el trazo que se toca (no pinta
/// encima), que es lo que se espera en un bloc de notas.
class NoteCanvas extends StatefulWidget {
  const NoteCanvas({
    super.key,
    required this.strokes,
    required this.ink,
    required this.strokeWidth,
    required this.eraser,
    required this.onChanged,
    this.pageColor = const Color(0xFFFDFDFB),
    this.aspectRatio = .72,
    this.allowZoom = false,
    this.readOnly = false,
  });

  final List<NoteStroke> strokes;
  final Color ink;
  final double strokeWidth;
  final bool eraser;
  final ValueChanged<List<NoteStroke>> onChanged;
  final Color pageColor;
  final double aspectRatio;
  final bool allowZoom;
  final bool readOnly;

  @override
  State<NoteCanvas> createState() => _NoteCanvasState();
}

class _NoteCanvasState extends State<NoteCanvas> {
  final List<Offset> _current = [];
  Size _size = Size.zero;
  double _zoom = 1;
  double _zoomStart = 1;

  /// Radio (normalizado) con el que la goma alcanza un trazo.
  static const double _eraseRadius = .035;

  Offset _normalized(Offset local) {
    if (_size.width <= 0 || _size.height <= 0) return Offset.zero;
    return Offset(
      (local.dx / _size.width).clamp(0, 1),
      (local.dy / _size.height).clamp(0, 1),
    );
  }

  bool _eraseAt(Offset point) {
    final left = <NoteStroke>[];
    var hit = false;
    for (final s in widget.strokes) {
      if (_touches(s.points, point)) {
        hit = true;
        continue;
      }
      left.add(s);
    }
    if (hit) widget.onChanged(left);
    return hit;
  }

  bool _touches(List<Offset> points, Offset target) {
    if (points.length == 1) {
      return (points.first - target).distance <= _eraseRadius;
    }
    for (var i = 1; i < points.length; i++) {
      if (_distanceToSegment(target, points[i - 1], points[i]) <=
          _eraseRadius) {
        return true;
      }
    }
    return false;
  }

  double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len = ab.distanceSquared;
    if (len == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  void _start(DragStartDetails d) {
    if (widget.readOnly) return;
    final point = _normalized(d.localPosition);
    if (widget.eraser) {
      _eraseAt(point);
      return;
    }
    setState(() {
      _current
        ..clear()
        ..add(point);
    });
  }

  void _move(DragUpdateDetails d) {
    if (widget.readOnly) return;
    final point = _normalized(d.localPosition);
    if (widget.eraser) {
      _eraseAt(point);
      return;
    }
    if (_current.isEmpty) return;
    if ((point - _current.last).distance < .002) return;
    setState(() => _current.add(point));
  }

  void _end(DragEndDetails d) {
    if (widget.readOnly || widget.eraser || _current.isEmpty) return;
    widget.onChanged([
      ...widget.strokes,
      NoteStroke(
        points: List<Offset>.of(_current),
        color: widget.ink,
        width: widget.strokeWidth,
      ),
    ]);
    setState(() => _current.clear());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (details) {
            _zoomStart = _zoom;
            if (details.pointerCount == 1) {
              _start(
                DragStartDetails(
                  globalPosition: details.focalPoint,
                  localPosition: details.localFocalPoint,
                ),
              );
            } else {
              _current.clear();
            }
          },
          onScaleUpdate: (details) {
            if (widget.allowZoom && details.pointerCount >= 2) {
              setState(() => _zoom = (_zoomStart * details.scale).clamp(1, 4));
              _current.clear();
            } else if (details.pointerCount == 1) {
              _move(
                DragUpdateDetails(
                  globalPosition: details.focalPoint,
                  localPosition: details.localFocalPoint,
                  delta: details.focalPointDelta,
                ),
              );
            }
          },
          onScaleEnd: (details) =>
              _end(DragEndDetails(velocity: details.velocity)),
          child: Center(
            child: AspectRatio(
              aspectRatio: widget.aspectRatio,
              child: Transform.scale(
                scale: _zoom,
                alignment: Alignment.center,
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.pageColor,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: .7),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        painter: _StrokesPainter(
                          strokes: widget.strokes,
                          current: _current,
                          ink: widget.ink,
                          width: widget.strokeWidth,
                        ),
                      ),
                      if (widget.strokes.isEmpty && _current.isEmpty)
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.gesture_rounded,
                                size: 30,
                                color: const Color(0xFF1F2937)
                                    .withValues(alpha: .30),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Dibuja con el dedo o el mouse',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StrokesPainter extends CustomPainter {
  _StrokesPainter({
    required this.strokes,
    required this.current,
    this.ink = const Color(0xFF1F2937),
    this.width = 3,
  });

  final List<NoteStroke> strokes;
  final List<Offset> current;
  final Color ink;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      _paintStroke(canvas, size, s.points, s.color, s.width);
    }
    if (current.length >= 2) {
      _paintStroke(canvas, size, current, ink, width);
    }
  }

  void _paintStroke(
    Canvas canvas,
    Size size,
    List<Offset> points,
    Color color,
    double strokeWidth,
  ) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    Offset at(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
    if (points.length == 1) {
      canvas.drawCircle(
        at(points.first),
        strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    final path = Path()..moveTo(at(points.first).dx, at(points.first).dy);
    for (var i = 1; i < points.length; i++) {
      final p = at(points[i]);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _StrokesPainter old) =>
      old.strokes != strokes ||
      old.current.length != current.length ||
      old.ink != ink ||
      old.width != width;
}

/// Zona seleccionable del documento (un párrafo, una tarea o un dibujo) con su
/// rectángulo en pantalla y, si es texto, el párrafo ya maquetado para saber
/// qué carácter cae bajo el dedo.
class _SelRegion {
  const _SelRegion({
    required this.block,
    required this.item,
    required this.length,
    required this.rect,
    required this.paragraph,
  });

  final int block;
  final int item;
  final int length;
  final Rect rect;
  final RenderParagraph? paragraph;
}

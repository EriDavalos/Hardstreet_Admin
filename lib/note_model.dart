import 'package:flutter/material.dart';

/// Formato aplicado a un rango de texto dentro de un párrafo o tarea.
class NoteTextRun {
  const NoteTextRun({
    required this.start,
    required this.end,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.fontFamily = '',
    this.fontSize = 0,
  });

  final int start;
  final int end;
  final bool bold;
  final bool italic;
  final bool underline;
  final String fontFamily;
  final double fontSize;

  bool get isDefault =>
      !bold && !italic && !underline && fontFamily.isEmpty && fontSize <= 0;

  TextStyle applyTo(TextStyle base) => base.copyWith(
    fontWeight: bold ? FontWeight.w700 : base.fontWeight,
    fontStyle: italic ? FontStyle.italic : base.fontStyle,
    decoration: underline ? TextDecoration.underline : base.decoration,
    fontFamily: fontFamily.isEmpty ? base.fontFamily : fontFamily,
    fontSize: fontSize > 0 ? fontSize : base.fontSize,
  );

  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
    'bold': bold,
    'italic': italic,
    'underline': underline,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
  };

  factory NoteTextRun.fromJson(Map<String, dynamic> json) => NoteTextRun(
    start: (json['start'] as num?)?.toInt() ?? 0,
    end: (json['end'] as num?)?.toInt() ?? 0,
    bold: json['bold'] == true,
    italic: json['italic'] == true,
    underline: json['underline'] == true,
    fontFamily: (json['fontFamily'] ?? '').toString(),
    fontSize: (json['fontSize'] as num?)?.toDouble() ?? 0,
  );
}

/// TextEditingController que conserva estilo por rango al escribir y al guardar.
class NoteRichTextController extends TextEditingController {
  NoteRichTextController({super.text, List<NoteTextRun>? formats})
    : _formats = List<NoteTextRun>.of(formats ?? const []),
      _textStyles = [] {
    _textStyles = List<NoteTextRun>.generate(text.length, (index) {
      for (final run in _formats) {
        if (index >= run.start && index < run.end) {
          return NoteTextRun(
            start: index,
            end: index + 1,
            bold: run.bold,
            italic: run.italic,
            underline: run.underline,
            fontFamily: run.fontFamily,
            fontSize: run.fontSize,
          );
        }
      }
      return NoteTextRun(start: index, end: index + 1);
    });
    _compressStyles();
  }

  List<NoteTextRun> _formats;
  List<NoteTextRun> _textStyles;
  bool _pendingBold = false;
  bool _pendingItalic = false;
  bool _pendingUnderline = false;
  String _pendingFontFamily = '';
  double _pendingFontSize = 0;
  int _pendingOffset = -1;
  List<NoteTextRun> get formats => List.unmodifiable(_formats);

  @override
  set value(TextEditingValue newValue) {
    final oldText = text;
    if (oldText != newValue.text) {
      var prefix = 0;
      while (prefix < oldText.length &&
          prefix < newValue.text.length &&
          oldText.codeUnitAt(prefix) == newValue.text.codeUnitAt(prefix)) {
        prefix++;
      }
      var suffix = 0;
      while (suffix < oldText.length - prefix &&
          suffix < newValue.text.length - prefix &&
          oldText.codeUnitAt(oldText.length - suffix - 1) ==
              newValue.text.codeUnitAt(newValue.text.length - suffix - 1)) {
        suffix++;
      }
      final removed = oldText.length - prefix - suffix;
      final inserted = newValue.text.length - prefix - suffix;
      final inherited = prefix > 0 && prefix - 1 < _textStyles.length
          ? _textStyles[prefix - 1]
          : (prefix < _textStyles.length ? _textStyles[prefix] : null);
      final shouldUsePending =
          value.selection.isValid &&
          value.selection.isCollapsed &&
          value.selection.extentOffset == prefix &&
          _pendingOffset == prefix;
      final insertionSource = shouldUsePending
          ? NoteTextRun(
              start: prefix,
              end: prefix + 1,
              bold: _pendingBold,
              italic: _pendingItalic,
              underline: _pendingUnderline,
              fontFamily: _pendingFontFamily,
              fontSize: _pendingFontSize,
            )
          : inherited ?? NoteTextRun(start: prefix, end: prefix + 1);
      final insertedStyles = <NoteTextRun>[
        for (var i = 0; i < inserted; i++)
          NoteTextRun(
            start: prefix + i,
            end: prefix + i + 1,
            bold: insertionSource.bold,
            italic: insertionSource.italic,
            underline: insertionSource.underline,
            fontFamily: insertionSource.fontFamily,
            fontSize: insertionSource.fontSize,
          ),
      ];
      final shiftedSuffix = <NoteTextRun>[
        for (final style in _textStyles.skip(prefix + removed))
          NoteTextRun(
            start: style.start + inserted - removed,
            end: style.end + inserted - removed,
            bold: style.bold,
            italic: style.italic,
            underline: style.underline,
            fontFamily: style.fontFamily,
            fontSize: style.fontSize,
          ),
      ];
      final next = <NoteTextRun>[
        ..._textStyles.take(prefix),
        ...insertedStyles,
        ...shiftedSuffix,
      ];
      _textStyles = next.take(newValue.text.length).toList();
      while (_textStyles.length < newValue.text.length) {
        _textStyles.add(NoteTextRun(start: 0, end: 0));
      }
      _compressStyles();
      if (shouldUsePending) {
        _pendingOffset = newValue.selection.isValid
            ? newValue.selection.extentOffset
            : prefix + inserted;
      } else {
        _pendingOffset = -1;
      }
    } else if (newValue.selection != value.selection &&
        newValue.selection.isValid &&
        newValue.selection.isCollapsed) {
      _pendingOffset = -1;
    }
    super.value = newValue;
  }

  /// ¿Todo el rango ([range], o la selección actual) tiene ese estilo?
  bool hasFormat({
    bool? bold,
    bool? italic,
    bool? underline,
    String? fontFamily,
    double? fontSize,
    TextRange? range,
  }) {
    final selection = range ?? value.selection;
    final start = selection.isValid && !selection.isCollapsed
        ? selection.start.clamp(0, text.length)
        : selection.isValid
        ? selection.end.clamp(0, text.length)
        : text.length;
    final end = selection.isValid && !selection.isCollapsed
        ? selection.end.clamp(start, text.length)
        : start;
    if (start == end) {
      final offset = selection.isValid ? selection.end : text.length;
      final styleIndex = offset > 0 ? offset - 1 : offset;
      final current = styleIndex >= 0 && styleIndex < _textStyles.length
          ? _textStyles[styleIndex]
          : null;
      if (bold != null) {
        return _pendingOffset == offset
            ? _pendingBold == bold
            : (current?.bold ?? false) == bold;
      }
      if (italic != null) {
        return _pendingOffset == offset
            ? _pendingItalic == italic
            : (current?.italic ?? false) == italic;
      }
      if (underline != null) {
        return _pendingOffset == offset
            ? _pendingUnderline == underline
            : (current?.underline ?? false) == underline;
      }
      if (fontFamily != null) {
        return _pendingOffset == offset
            ? _pendingFontFamily == fontFamily
            : (current?.fontFamily ?? '') == fontFamily;
      }
      if (fontSize != null) {
        return _pendingOffset == offset
            ? _pendingFontSize == fontSize
            : (current?.fontSize ?? 0) == fontSize;
      }
      return false;
    }
    return _textStyles.skip(start).take(end - start).every((s) {
      if (bold != null && s.bold != bold) return false;
      if (italic != null && s.italic != italic) return false;
      if (underline != null && s.underline != underline) return false;
      if (fontFamily != null && s.fontFamily != fontFamily) return false;
      if (fontSize != null && s.fontSize != fontSize) return false;
      return true;
    });
  }

  /// Aplica el estilo al texto SELECCIONADO (o a [range]); con el cursor
  /// simplemente queda armado para lo que se escriba después.
  void applyFormat({
    bool? bold,
    bool? italic,
    bool? underline,
    String? fontFamily,
    double? fontSize,
    TextRange? range,
  }) {
    final selection = range ?? value.selection;
    final offset = selection.isValid
        ? selection.end.clamp(0, text.length)
        : text.length;
    var start = selection.isValid && !selection.isCollapsed
        ? selection.start
        : offset;
    var end = selection.isValid && !selection.isCollapsed
        ? selection.end
        : offset;
    start = start.clamp(0, text.length);
    end = end.clamp(start, text.length);
    if (start == end) {
      if (bold != null) _pendingBold = bold;
      if (italic != null) _pendingItalic = italic;
      if (underline != null) _pendingUnderline = underline;
      if (fontFamily != null) _pendingFontFamily = fontFamily;
      if (fontSize != null) _pendingFontSize = fontSize;
      _pendingOffset = offset;
      notifyListeners();
      return;
    }
    _pendingOffset = -1;
    for (var i = start; i < end; i++) {
      final old = _textStyles[i];
      _textStyles[i] = NoteTextRun(
        start: i,
        end: i + 1,
        bold: bold ?? old.bold,
        italic: italic ?? old.italic,
        underline: underline ?? old.underline,
        fontFamily: fontFamily ?? old.fontFamily,
        fontSize: fontSize ?? old.fontSize,
      );
    }
    _compressStyles();
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (text.isEmpty) return TextSpan(style: style, text: text);
    final spans = <InlineSpan>[];
    var start = 0;
    for (var i = 1; i <= text.length; i++) {
      if (i < text.length && _sameStyle(_textStyles[i - 1], _textStyles[i])) {
        continue;
      }
      spans.add(
        TextSpan(
          text: text.substring(start, i),
          style: _textStyles[start].applyTo(style ?? const TextStyle()),
        ),
      );
      start = i;
    }
    return TextSpan(style: style, children: spans);
  }

  void _compressStyles() {
    final runs = <NoteTextRun>[];
    for (var i = 0; i < _textStyles.length; i++) {
      final s = _textStyles[i];
      if (s.isDefault) continue;
      if (runs.isNotEmpty && runs.last.end == i && _sameStyle(runs.last, s)) {
        final previous = runs.removeLast();
        runs.add(
          NoteTextRun(
            start: previous.start,
            end: i + 1,
            bold: s.bold,
            italic: s.italic,
            underline: s.underline,
            fontFamily: s.fontFamily,
            fontSize: s.fontSize,
          ),
        );
      } else {
        runs.add(
          NoteTextRun(
            start: i,
            end: i + 1,
            bold: s.bold,
            italic: s.italic,
            underline: s.underline,
            fontFamily: s.fontFamily,
            fontSize: s.fontSize,
          ),
        );
      }
    }
    _formats = runs;
  }

  bool _sameStyle(NoteTextRun a, NoteTextRun b) =>
      a.bold == b.bold &&
      a.italic == b.italic &&
      a.underline == b.underline &&
      a.fontFamily == b.fontFamily &&
      a.fontSize == b.fontSize;
}

// ==================================================================
// MODELO DE NOTAS
// ==================================================================
// Una nota es TÍTULO + BLOQUES, como un documento de Samsung Notes:
//
//   * bloque de TEXTO      -> un párrafo escrito directamente en la hoja;
//   * bloque de ACTIVIDADES -> lista con casilla (checklist);
//   * bloque de DIBUJO     -> un lienzo insertado en la nota (se abre a
//                             pantalla completa al tocarlo y se sigue
//                             dibujando ahí).
//
// Los puntos del dibujo se guardan NORMALIZADOS (0..1 sobre el ancho y el alto
// del lienzo), así la misma nota se ve igual en el celular y en la computadora.
// El JSON es el mismo que guarda el backend (`content`).
//
// VISIBILIDAD: 'private' (solo el autor) o 'company' (todo el equipo). Solo el
// autor puede editar; las notas de empresa ajenas se abren en solo lectura.
// ==================================================================

/// Una actividad de una lista (con su casilla).
class NoteItem {
  NoteItem({this.text = '', this.done = false, List<NoteTextRun>? formats})
    : formats = formats ?? <NoteTextRun>[];

  String text;
  bool done;
  List<NoteTextRun> formats;

  Map<String, dynamic> toJson() => {
    'text': text,
    'done': done,
    'formats': [for (final f in formats) f.toJson()],
  };

  factory NoteItem.fromJson(Map<String, dynamic> json) => NoteItem(
    text: (json['text'] ?? '').toString(),
    done: json['done'] == true || json['done'] == 1,
    formats: [
      for (final f in (json['formats'] as List? ?? const []).whereType<Map>())
        NoteTextRun.fromJson(f.cast<String, dynamic>()),
    ],
  );
}

/// Un trazo del dibujo.
class NoteStroke {
  NoteStroke({
    required this.points,
    required this.color,
    required this.width,
    this.eraser = false,
  });

  /// Puntos NORMALIZADOS (0..1) sobre el lienzo.
  final List<Offset> points;
  final Color color;
  final double width;

  /// Compatibilidad con notas guardadas con goma de borrar como trazo.
  final bool eraser;

  /// ¿Es resaltador? Se guarda con alfa en el color (no hace falta otra clave).
  bool get isMarker => color.a < .98;

  Map<String, dynamic> toJson() => {
    'color': _hexOf(color),
    'width': width,
    'eraser': eraser,
    'points': [
      for (final p in points)
        [(p.dx * 10000).round() / 10000, (p.dy * 10000).round() / 10000],
    ],
  };

  factory NoteStroke.fromJson(Map<String, dynamic> json) {
    final raw = (json['points'] as List?) ?? const [];
    final points = <Offset>[];
    for (final p in raw) {
      if (p is! List || p.length < 2) continue;
      final x = (p[0] as num?)?.toDouble();
      final y = (p[1] as num?)?.toDouble();
      if (x == null || y == null) continue;
      points.add(Offset(x.clamp(0, 1), y.clamp(0, 1)));
    }
    return NoteStroke(
      points: points,
      color: _colorOf((json['color'] ?? '').toString()),
      width: (json['width'] as num?)?.toDouble() ?? 3,
      eraser: json['eraser'] == true,
    );
  }
}

/// Un bloque de la nota: texto, lista de actividades o dibujo insertado.
class NoteBlock {
  NoteBlock.text([this.text = '', List<NoteTextRun>? formats])
    : type = 'text',
      formats = formats ?? <NoteTextRun>[],
      items = <NoteItem>[],
      strokes = <NoteStroke>[],
      pageColor = const Color(0xFFFDFDFB),
      aspectRatio = .72;

  NoteBlock.checklist([List<NoteItem>? items])
    : type = 'checklist',
      text = '',
      formats = <NoteTextRun>[],
      items = items ?? <NoteItem>[],
      strokes = <NoteStroke>[],
      pageColor = const Color(0xFFFDFDFB),
      aspectRatio = .72;

  NoteBlock.drawing({
    List<NoteStroke>? strokes,
    this.pageColor = const Color(0xFFFDFDFB),
    this.aspectRatio = .72,
  }) : type = 'drawing',
       text = '',
       formats = <NoteTextRun>[],
       items = <NoteItem>[],
       strokes = strokes ?? <NoteStroke>[];

  /// 'text' | 'checklist' | 'drawing'.
  final String type;

  /// Solo para los bloques de texto.
  String text;
  List<NoteTextRun> formats;

  /// Solo para las listas.
  final List<NoteItem> items;

  /// Solo para los dibujos insertados (mutable: se edita al dibujar).
  List<NoteStroke> strokes;
  Color pageColor;
  double aspectRatio;

  bool get isChecklist => type == 'checklist';

  bool get isDrawing => type == 'drawing';

  /// ¿Todavía no tiene nada escrito/dibujado?
  bool get isEmpty =>
      strokes.isEmpty &&
      text.trim().isEmpty &&
      !items.any((i) => i.text.trim().isNotEmpty);

  Map<String, dynamic> toJson() {
    switch (type) {
      case 'checklist':
        return {
          'type': 'checklist',
          'text': '',
          'items': [for (final i in items) i.toJson()],
        };
      case 'drawing':
        return {
          'type': 'drawing',
          'text': '',
          'items': const <dynamic>[],
          'strokes': [for (final s in strokes) s.toJson()],
          'pageColor': _hexOf(pageColor),
          'aspectRatio': aspectRatio,
        };
      default:
        return {
          'type': 'text',
          'text': text,
          'items': const <dynamic>[],
          'formats': [for (final f in formats) f.toJson()],
        };
    }
  }

  factory NoteBlock.fromJson(Map<String, dynamic> json) {
    final type = (json['type'] ?? 'text').toString();
    if (type == 'drawing') {
      final raw = (json['strokes'] as List?) ?? const [];
      return NoteBlock.drawing(
        strokes: [
          for (final s in raw.whereType<Map>())
            NoteStroke.fromJson(s.cast<String, dynamic>()),
        ],
        pageColor: _colorOf((json['pageColor'] ?? '#FDFDFB').toString()),
        aspectRatio: ((json['aspectRatio'] as num?)?.toDouble() ?? .72).clamp(
          .35,
          2.5,
        ),
      );
    }
    if (type == 'checklist') {
      final raw = (json['items'] as List?) ?? const [];
      return NoteBlock.checklist([
        for (final e in raw.whereType<Map>())
          NoteItem.fromJson(e.cast<String, dynamic>()),
      ]);
    }
    return NoteBlock.text((json['text'] ?? '').toString(), [
      for (final f in (json['formats'] as List? ?? const []).whereType<Map>())
        NoteTextRun.fromJson(f.cast<String, dynamic>()),
    ]);
  }
}

/// Una nota completa (lo que abre el editor).
class Note {
  Note({
    this.id = 0,
    this.title = '',
    List<NoteBlock>? blocks,
    this.color = '',
    this.pinned = false,
    this.updated,
    this.visibility = 'private',
    this.ownerId = 0,
    this.ownerName = '',
    this.mine = true,
    List<NoteTextRun>? titleFormats,
  }) : blocks = blocks ?? [NoteBlock.text()],
       titleFormats = titleFormats ?? <NoteTextRun>[];

  int id;
  String title;
  List<NoteTextRun> titleFormats;
  List<NoteBlock> blocks;

  /// Color de la tarjeta en el listado (#RRGGBB, '' = el del tema).
  String color;
  bool pinned;
  DateTime? updated;

  /// 'private' (solo yo) | 'company' (todo el equipo).
  String visibility;

  /// Autor de la nota y si soy yo (para saber si se puede editar).
  int ownerId;
  String ownerName;
  bool mine;

  bool get isNew => id == 0;

  bool get sharedWithCompany => visibility == 'company';

  bool get hasDrawing => blocks.any((b) => b.isDrawing && b.strokes.isNotEmpty);

  /// Dibujos insertados en la nota (para el listado y la vista previa).
  List<NoteBlock> get drawingBlocks =>
      blocks.where((b) => b.isDrawing).toList();

  /// Texto de la primera parte del contenido (para la tarjeta).
  String get preview {
    final parts = <String>[];
    for (final b in blocks) {
      if (b.isChecklist) {
        for (final i in b.items) {
          if (i.text.trim().isNotEmpty) parts.add(i.text.trim());
        }
      } else if (!b.isDrawing && b.text.trim().isNotEmpty) {
        parts.add(b.text.trim());
      }
    }
    return parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// JSON para el backend (el mismo que lee [fromJson]).
  Map<String, dynamic> toJson() => {
    if (id > 0) 'id': id,
    'title': title.trim(),
    'titleFormats': [for (final f in titleFormats) f.toJson()],
    'blocks': [for (final b in blocks) b.toJson()],
    'visibility': visibility,
    'color': color,
    'pinned': pinned,
  };

  factory Note.fromJson(Map<String, dynamic> json) {
    final rawBlocks = (json['blocks'] as List?) ?? const [];
    final blocks = [
      for (final b in rawBlocks.whereType<Map>())
        NoteBlock.fromJson(b.cast<String, dynamic>()),
    ];
    // Notas viejas: el dibujo venía APARTE (columna `drawing`). Se convierte
    // en un bloque insertado para que se pueda seguir dibujando igual.
    final legacy = (json['drawing'] is Map)
        ? ((json['drawing'] as Map)['strokes'] as List?) ?? const []
        : (json['strokes'] as List?) ?? const [];
    final legacyStrokes = [
      for (final s in legacy.whereType<Map>())
        NoteStroke.fromJson(s.cast<String, dynamic>()),
    ];
    if (legacyStrokes.isNotEmpty && !blocks.any((b) => b.isDrawing)) {
      blocks.add(NoteBlock.drawing(strokes: legacyStrokes));
    }
    return Note(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] ?? '').toString(),
      titleFormats: [
        for (final f
            in (json['titleFormats'] as List? ?? const []).whereType<Map>())
          NoteTextRun.fromJson(f.cast<String, dynamic>()),
      ],
      blocks: blocks.isEmpty ? [NoteBlock.text()] : blocks,
      color: (json['color'] ?? '').toString(),
      pinned: json['pinned'] == true,
      updated: DateTime.tryParse((json['updated'] ?? '').toString()),
      visibility: (json['visibility'] ?? 'private').toString() == 'company'
          ? 'company'
          : 'private',
      ownerId: (json['ownerId'] as num?)?.toInt() ?? 0,
      ownerName: (json['ownerName'] ?? '').toString(),
      mine: json['mine'] != false,
    );
  }
}

/// Lo que se pinta en el listado (sin cargar el contenido completo).
class NoteSummary {
  const NoteSummary({
    required this.id,
    required this.title,
    required this.preview,
    required this.color,
    required this.pinned,
    required this.updated,
    required this.hasDrawing,
    this.visibility = 'private',
    this.mine = true,
    this.ownerName = '',
    this.drawings = 0,
  });

  final int id;
  final String title;
  final String preview;
  final String color;
  final bool pinned;
  final DateTime? updated;
  final bool hasDrawing;

  /// 'private' | 'company'.
  final String visibility;

  /// ¿La escribí yo? (si no, se abre en solo lectura).
  final bool mine;
  final String ownerName;

  /// Cuántos dibujos tiene (chip de la tarjeta).
  final int drawings;

  /// Título visible («Sin título» si está en blanco).
  String get displayTitle => title.trim().isEmpty ? 'Sin título' : title.trim();

  bool get sharedWithCompany => visibility == 'company';

  factory NoteSummary.fromJson(Map<String, dynamic> json) => NoteSummary(
    id: (json['id'] as num?)?.toInt() ?? 0,
    title: (json['title'] ?? '').toString(),
    preview: (json['preview'] ?? '').toString(),
    color: (json['color'] ?? '').toString(),
    pinned: json['pinned'] == true,
    updated: DateTime.tryParse(
      (json['updated'] ?? json['created'] ?? '').toString(),
    ),
    hasDrawing: json['hasDrawing'] == true,
    visibility: (json['visibility'] ?? 'private').toString() == 'company'
        ? 'company'
        : 'private',
    mine: json['mine'] != false,
    ownerName: (json['ownerName'] ?? '').toString(),
    drawings: (json['drawings'] as num?)?.toInt() ?? 0,
  );
}

// ------------------------------------------------------------------
// Utilidades de color del dibujo
// ------------------------------------------------------------------

/// Tintas del lápiz (opacas).
const List<Color> kNotePageColors = [
  Color(0xFFFDFDFB), // papel
  Color(0xFFFFF4D6), // crema
  Color(0xFFEAF4FF), // azul claro
  Color(0xFFEAF7EE), // verde claro
  Color(0xFFF2ECFF), // lavanda
  Color(0xFF24262B), // oscuro
];

const List<Color> kNoteInks = [
  Color(0xFF1F2937), // tinta
  Color(0xFF2F6BFF), // azul
  Color(0xFFDC2626), // rojo
  Color(0xFF16A34A), // verde
  Color(0xFFD97706), // ámbar
  Color(0xFF7C3AED), // violeta
  Color(0xFF0891B2), // cian
];

/// Tintas del resaltador (translúcidas, se guardan con alfa en el color).
List<Color> get kNoteMarkers => [
  for (final c in kNoteInks) c.withValues(alpha: .35),
];

String _hexOf(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

Color _colorOf(String raw) {
  final s = raw.replaceFirst('#', '').trim();
  final v = int.tryParse(s, radix: 16);
  if (v == null) return kNoteInks.first;
  // #RRGGBB -> opaco; #AARRGGBB se respeta (resaltador).
  return Color(s.length <= 6 ? 0xFF000000 | v : v);
}

/// Color de tarjeta guardado como #RRGGBB, o null si no hay.
Color? noteCardColor(String raw) {
  final s = raw.replaceFirst('#', '').trim();
  if (s.length != 6) return null;
  final v = int.tryParse(s, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

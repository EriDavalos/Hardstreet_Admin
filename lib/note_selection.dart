import 'package:flutter/material.dart';

import 'note_model.dart';

/// Un punto dentro de la nota: bloque, tarea (solo listas) y carácter.
///
/// El orden es el de lectura del documento, así que una selección es el tramo
/// que va de [NoteSelection.start] a [NoteSelection.end].
@immutable
class NotePoint implements Comparable<NotePoint> {
  const NotePoint(this.block, {this.item = -1, this.offset = 0});

  final int block;

  /// Tarea dentro de una lista (-1 en párrafos y dibujos).
  final int item;

  /// Carácter dentro del texto (del párrafo o de la tarea).
  final int offset;

  @override
  int compareTo(NotePoint other) {
    if (block != other.block) return block.compareTo(other.block);
    if (item != other.item) return item.compareTo(other.item);
    return offset.compareTo(other.offset);
  }

  @override
  bool operator ==(Object other) =>
      other is NotePoint &&
      other.block == block &&
      other.item == item &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(block, item, offset);

  @override
  String toString() => 'NotePoint(b: $block, i: $item, o: $offset)';
}

/// Tramo seleccionado de la nota. Sirve igual para LETRAS que para bloques
/// enteros: los dibujos son atómicos (si la selección los toca, se van).
@immutable
class NoteSelection {
  const NoteSelection({required this.anchor, required this.focus});

  /// Dónde empezó el gesto y dónde va ahora (en cualquier orden).
  final NotePoint anchor;
  final NotePoint focus;

  NotePoint get start => anchor.compareTo(focus) <= 0 ? anchor : focus;
  NotePoint get end => anchor.compareTo(focus) <= 0 ? focus : anchor;

  bool get isCollapsed => start.compareTo(end) == 0;

  /// Bloques que quedan enteros dentro de la selección (los del medio).
  bool coversBlock(int block) => block > start.block && block < end.block;

  /// ¿La selección toca este bloque (aunque sea a la mitad)?
  bool touchesBlock(int block) =>
      !isCollapsed && block >= start.block && block <= end.block;

  /// Caracteres seleccionados de un texto concreto.
  ///
  /// [block] es el bloque, [item] la tarea (-1 en párrafos) y [length] cuántos
  /// caracteres tiene ese texto. Devuelve null si ese texto no se toca.
  TextRange? rangeIn(int block, int item, int length) {
    final s = start;
    final e = end;
    if (block < s.block || block > e.block) return null;

    // Bloques del medio: completo.
    if (block > s.block && block < e.block) {
      return TextRange(start: 0, end: length);
    }

    // Un solo bloque: el tramo puede ir de una tarea a otra.
    if (block == s.block && block == e.block) {
      // Misma tarea (o mismo párrafo): las demás no se tocan.
      if (s.item == e.item) {
        if (item != s.item) return null;
        return _clamp(s.offset, e.offset, length);
      }
      if (item < s.item || item > e.item) return null;
      if (item == s.item) return _clamp(s.offset, length, length);
      if (item == e.item) return _clamp(0, e.offset, length);
      return TextRange(start: 0, end: length);
    }

    // Primer bloque: de la selección hasta su final.
    if (block == s.block) {
      if (s.item < 0 || item < 0) return _clamp(s.offset, length, length);
      if (item < s.item) return null;
      if (item == s.item) return _clamp(s.offset, length, length);
      return TextRange(start: 0, end: length);
    }

    // Último bloque: de su inicio hasta la selección.
    if (item < 0) return _clamp(0, e.offset, length);
    if (item < e.item) return TextRange(start: 0, end: length);
    if (item == e.item) return _clamp(0, e.offset, length);
    return null;
  }

  static TextRange _clamp(int from, int to, int length) {
    final a = from.clamp(0, length);
    final b = to.clamp(a, length);
    return TextRange(start: a, end: b);
  }
}

/// Aplica el borrado de [selection] sobre [blocks].
///
///   * Un bloque entero dentro de la selección desaparece (los dibujos también).
///   * Un bloque cortado a la mitad: solo se van las letras seleccionadas y el
///     resto se queda, en el texto y en las actividades.
List<NoteBlock> deleteSelection(
  List<NoteBlock> blocks,
  NoteSelection selection,
) {
  if (selection.isCollapsed) {
    // Un dibujo tocado sin arrastrar ya es «seleccionado»: es atómico.
    final point = selection.start;
    if (point.block >= 0 && point.block < blocks.length) {
      final only = blocks[point.block];
      if (only.isDrawing) {
        final rest = [...blocks]..removeAt(point.block);
        return rest.isEmpty ? [NoteBlock.text()] : rest;
      }
    }
    return blocks;
  }
  final out = <NoteBlock>[];
  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];
    if (i < selection.start.block || i > selection.end.block) {
      out.add(block);
      continue;
    }
    // Dibujo: no tiene letras, así que si la selección lo toca, se elimina.
    if (block.isDrawing) continue;

    if (block.isChecklist) {
      final keep = <NoteItem>[];
      for (var j = 0; j < block.items.length; j++) {
        final item = block.items[j];
        final range = selection.rangeIn(i, j, item.text.length);
        if (range == null) {
          keep.add(item);
          continue;
        }
        // Casilla completa dentro de la selección: se va con sus letras.
        if (range.start <= 0 && range.end >= item.text.length) continue;
        final cut = cutTextRange(
          item.text,
          item.formats,
          range.start,
          range.end,
        );
        item.text = cut.text;
        item.formats = cut.formats;
        keep.add(item);
      }
      if (keep.isEmpty) continue;
      block.items
        ..clear()
        ..addAll(keep);
      out.add(block);
      continue;
    }

    final range = selection.rangeIn(i, -1, block.text.length);
    if (range == null) {
      out.add(block);
      continue;
    }
    if (range.start <= 0 && range.end >= block.text.length) continue;
    final cut = cutTextRange(block.text, block.formats, range.start, range.end);
    block.text = cut.text;
    block.formats = cut.formats;
    out.add(block);
  }
  return out.isEmpty ? [NoteBlock.text()] : out;
}

/// Borra [start]..[end] de un texto y reajusta sus estilos de formato.
({String text, List<NoteTextRun> formats}) cutTextRange(
  String text,
  List<NoteTextRun> formats,
  int start,
  int end,
) {
  final a = start.clamp(0, text.length);
  final b = end.clamp(a, text.length);
  if (b <= a) return (text: text, formats: formats);
  final perChar = _perChar(text, formats)..removeRange(a, b);
  return (
    text: text.substring(0, a) + text.substring(b),
    formats: _compress(perChar),
  );
}

/// Estilos por carácter (para cortar, comprimir y pintar con resaltado).
List<NoteTextRun> _perChar(String text, List<NoteTextRun> formats) {
  return List<NoteTextRun>.generate(text.length, (i) {
    for (final f in formats) {
      if (i >= f.start && i < f.end) {
        return NoteTextRun(
          start: i,
          end: i + 1,
          bold: f.bold,
          italic: f.italic,
          underline: f.underline,
          fontFamily: f.fontFamily,
          fontSize: f.fontSize,
        );
      }
    }
    return NoteTextRun(start: i, end: i + 1);
  });
}

bool _sameStyle(NoteTextRun a, NoteTextRun b) =>
    a.bold == b.bold &&
    a.italic == b.italic &&
    a.underline == b.underline &&
    a.fontFamily == b.fontFamily &&
    a.fontSize == b.fontSize;

/// Junta caracteres seguidos con el mismo estilo en un solo rango.
List<NoteTextRun> _compress(List<NoteTextRun> perChar) {
  final out = <NoteTextRun>[];
  var i = 0;
  while (i < perChar.length) {
    final first = perChar[i];
    var j = i + 1;
    while (j < perChar.length && _sameStyle(first, perChar[j])) {
      j++;
    }
    out.add(
      NoteTextRun(
        start: i,
        end: j,
        bold: first.bold,
        italic: first.italic,
        underline: first.underline,
        fontFamily: first.fontFamily,
        fontSize: first.fontSize,
      ),
    );
    i = j;
  }
  return out;
}

/// Texto con su formato y, si [range] lo indica, el tramo seleccionado
/// resaltado. Se usa en el modo de selección (la nota se ve, pero no se edita).
List<InlineSpan> highlightedSpans({
  required String text,
  required List<NoteTextRun> formats,
  required TextStyle base,
  TextRange? range,
  Color? highlight,
}) {
  if (text.isEmpty) return const [];
  final perChar = _perChar(text, formats);
  final spans = <InlineSpan>[];
  var i = 0;
  while (i < text.length) {
    final style = perChar[i];
    final selected = _covers(range, i);
    // Junta los caracteres seguidos con el mismo estilo y el mismo estado.
    var j = i + 1;
    while (j < text.length &&
        _sameStyle(style, perChar[j]) &&
        (_covers(range, j) == selected)) {
      j++;
    }
    spans.add(
      TextSpan(
        text: text.substring(i, j),
        style: style
            .applyTo(base)
            .copyWith(
              backgroundColor: highlight != null && selected ? highlight : null,
            ),
      ),
    );
    i = j;
  }
  return spans;
}

bool _covers(TextRange? range, int index) =>
    range != null && index >= range.start && index < range.end;

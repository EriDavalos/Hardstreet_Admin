import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/note_model.dart';
import 'package:hardstreet_admin/note_selection.dart';

/// SELECCIÓN EN NOTAS: un tramo puede empezar y terminar a la mitad de un
/// párrafo; lo que se queda a la mitad conserva las letras que no se eligieron.

void main() {
  test('borra solo las letras elegidas y deja el resto del párrafo', () {
    final blocks = [NoteBlock.text('Hola mundo')];
    final selection = NoteSelection(
      anchor: const NotePoint(0, offset: 4),
      focus: const NotePoint(0, offset: 10),
    );

    final out = deleteSelection(blocks, selection);

    expect(out, hasLength(1));
    expect(out.single.text, 'Hola');
  });

  test('los bloques del medio se van completos y los cortados se quedan', () {
    final blocks = [
      NoteBlock.text('Primero'),
      NoteBlock.text('Segundo'),
      NoteBlock.drawing(),
      NoteBlock.text('Tercero'),
    ];
    final selection = NoteSelection(
      anchor: const NotePoint(0, offset: 3),
      focus: const NotePoint(3, offset: 2),
    );

    final out = deleteSelection(blocks, selection);

    // El primer párrafo conserva lo de arriba del corte y el último lo de
    // abajo: solo se van las letras cumplidas.
    expect(out.map((b) => b.text).toList(), ['Pri', 'rcero']);
    expect(out.any((b) => b.isDrawing), isFalse);
  });

  test('en las actividades se borra el tramo y las demás casillas', () {
    final blocks = [
      NoteBlock.checklist([
        NoteItem(text: 'uno'),
        NoteItem(text: 'dos'),
        NoteItem(text: 'tres'),
      ]),
    ];
    final selection = NoteSelection(
      anchor: const NotePoint(0, item: 0, offset: 1),
      focus: const NotePoint(0, item: 2, offset: 2),
    );

    final out = deleteSelection(blocks, selection);

    expect(out, hasLength(1));
    expect(out.single.items.map((i) => i.text).toList(), ['u', 'es']);
  });

  test('la actividad que todavía tiene letras se mantiene entera', () {
    final blocks = [
      NoteBlock.checklist([
        NoteItem(text: 'comprar'),
        NoteItem(text: 'flores'),
      ]),
    ];
    // La selección empieza y termina dentro de la MISMA actividad.
    final selection = NoteSelection(
      anchor: const NotePoint(0, item: 0, offset: 2),
      focus: const NotePoint(0, item: 0, offset: 5),
    );

    final out = deleteSelection(blocks, selection);

    expect(out.single.items.map((i) => i.text).toList(), ['coar', 'flores']);
  });

  test('un dibujo tocado sin arrastrar ya se elimina', () {
    final blocks = [NoteBlock.text('a'), NoteBlock.drawing()];
    final out = deleteSelection(
      blocks,
      const NoteSelection(anchor: NotePoint(1), focus: NotePoint(1)),
    );

    expect(out, hasLength(1));
    expect(out.single.text, 'a');
  });

  test('el formato sobrevive al corte de letras', () {
    final blocks = [
      NoteBlock.text('abcdef', const [
        NoteTextRun(start: 0, end: 2, bold: true),
        NoteTextRun(start: 4, end: 6, bold: true),
      ]),
    ];
    final selection = NoteSelection(
      anchor: const NotePoint(0, offset: 1),
      focus: const NotePoint(0, offset: 5),
    );

    final out = deleteSelection(blocks, selection);

    expect(out.single.text, 'af');
    expect(out.single.formats, hasLength(1));
    expect(out.single.formats.single.bold, isTrue);
    expect(out.single.formats.single.start, 0);
    expect(out.single.formats.single.end, 2);
  });

  test('nunca se queda una nota sin ningún bloque', () {
    final blocks = [NoteBlock.text('todo esto')];
    final out = deleteSelection(
      blocks,
      const NoteSelection(
        anchor: NotePoint(0, offset: 0),
        focus: NotePoint(0, offset: 99),
      ),
    );

    expect(out, hasLength(1));
    expect(out.single.isChecklist, isFalse);
    expect(out.single.isDrawing, isFalse);
    expect(out.single.text, isEmpty);
  });

  test('un tramo que no toca nada no cambia la nota', () {
    final blocks = [NoteBlock.text('hola')];
    final out = deleteSelection(
      blocks,
      const NoteSelection(anchor: NotePoint(0), focus: NotePoint(0)),
    );

    expect(out.single.text, 'hola');
  });
}

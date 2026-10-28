import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_access.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/note_model.dart';
import 'package:hardstreet_admin/pages/notes_page.dart';

/// MÓDULO NOTAS: documento con título de una línea, bloques insertados
/// (texto, actividades y dibujo), guardado, visibilidad y solo lectura.
///
/// Backend falso: lo importante es que la pantalla pida, abra y guarde la nota
/// con la forma que espera `/api/admin/notes`.

final _posts = <Map<String, dynamic>>[];
var _deleted = <int>[];

Map<String, dynamic> _summary() => {
  'id': 1,
  'title': 'Lista del sábado',
  'preview': 'Comprar baterías Cargar flashes',
  'color': '',
  'pinned': false,
  'updated': '2026-10-28T10:00:00',
  'hasDrawing': false,
  'visibility': 'private',
  'mine': true,
  'ownerName': 'Erika',
};

Map<String, dynamic> _fullNote() => {
  'id': 1,
  'title': 'Lista del sábado',
  'blocks': [
    {'type': 'text', 'text': 'Comprar baterías', 'items': <dynamic>[]},
    {
      'type': 'checklist',
      'text': '',
      'items': [
        {'text': 'Cargar flashes', 'done': true},
      ],
    },
  ],
  'visibility': 'private',
  'ownerId': 0,
  'ownerName': 'Erika',
  'color': '',
  'pinned': false,
  'updated': '2026-10-28T10:00:00',
};

void _installMock() {
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;
    final id = request.url.queryParameters['id'];
    if (path.endsWith('/api/admin/notes')) {
      switch (request.method) {
        case 'GET':
          if (id != null) {
            return http.Response(
              jsonEncode({'ok': true, 'item': _fullNote()}),
              200,
              headers: headers,
            );
          }
          return http.Response(
            jsonEncode({
              'ok': true,
              'notes': [_summary()],
            }),
            200,
            headers: headers,
          );
        case 'POST':
          final body = (jsonDecode(request.body) as Map)
              .cast<String, dynamic>();
          _posts.add(body);
          return http.Response(
            jsonEncode({
              'ok': true,
              'item': {
                ..._fullNote(),
                'title': body['title'],
                'blocks': body['blocks'],
                'visibility': body['visibility'],
              },
            }),
            201,
            headers: headers,
          );
        case 'DELETE':
          _deleted.add(int.parse(id ?? '0'));
          return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
      }
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(1200, 900),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: NotesPage())));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Párrafo del DOCUMENTO (en modo selección es un Text.rich). La tarjeta del
/// listado también contiene el texto, así que se busca el texto exacto.
Finder _editorParagraph(String text) => find.byWidgetPredicate(
  (widget) => widget is Text && widget.textSpan?.toPlainText() == text,
);

Future<void> _openNote(WidgetTester tester) async {
  await tester.tap(find.text('Lista del sábado'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  test('el estilo en cursor se hereda al texto que se escribe después', () {
    final controller = NoteRichTextController();
    controller.value = const TextEditingValue(
      selection: TextSelection.collapsed(offset: 0),
    );
    controller.applyFormat(bold: true);
    controller.value = const TextEditingValue(
      text: 'abc',
      selection: TextSelection.collapsed(offset: 3),
    );

    expect(controller.formats, hasLength(1));
    expect(controller.formats.single.start, 0);
    expect(controller.formats.single.end, 3);
    expect(controller.formats.single.bold, isTrue);
    controller.dispose();
  });

  test('el formato de una selección se conserva al insertar antes', () {
    final controller = NoteRichTextController(text: 'hola mundo');
    controller.value = controller.value.copyWith(
      selection: const TextSelection(baseOffset: 5, extentOffset: 10),
    );
    controller.applyFormat(underline: true);
    controller.value = const TextEditingValue(
      text: 'nuevo hola mundo',
      selection: TextSelection.collapsed(offset: 5),
    );

    expect(controller.formats, hasLength(1));
    expect(controller.formats.single.start, 11);
    expect(controller.formats.single.end, 16);
    expect(controller.formats.single.underline, isTrue);
    controller.dispose();
  });

  testWidgets(
    'Enter en la última casilla vacía cierra la lista y sigue el texto',
    (tester) async {
      await _pump(tester);
      await _openNote(tester);
      await tester.tap(find.text('Lista'));
      await tester.pumpAndSettle();

      final taskHints = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Escribe una tarea…',
      );
      expect(taskHints, findsNWidgets(2));

      // Primer Enter: la casilla vacía abre otra debajo.
      await tester.tap(taskHints.last);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(taskHints, findsNWidgets(3));

      // Segundo Enter con la casilla vacía: se borra y el cursor baja al texto.
      await tester.tap(taskHints.last);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(taskHints, findsNWidgets(2));

      final tail = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Sigue escribiendo…',
      );
      expect(tail, findsOneWidget);
      expect(tester.widget<TextField>(tail).focusNode?.hasFocus, isTrue);
    },
  );

  testWidgets('debajo de una lista queda un párrafo para seguir escribiendo', (
    tester,
  ) async {
    await _pump(tester);
    await _openNote(tester);
    // La nota ya trae texto + lista: no hay ningún párrafo «extra» todavía.
    final tailParagraph = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Sigue escribiendo…',
    );
    expect(tailParagraph, findsNothing);

    await tester.tap(find.text('Lista'));
    await tester.pumpAndSettle();

    // Se inserta la lista Y un párrafo debajo, sin pulsar «Texto».
    expect(tailParagraph, findsOneWidget);
  });

  testWidgets('debajo de un dibujo se puede seguir escribiendo', (
    tester,
  ) async {
    await _pump(tester);
    await _openNote(tester);
    await tester.tap(find.text('Dibujo'));
    await tester.pumpAndSettle();

    // El dibujo deja un párrafo debajo y recibe el cursor.
    final tail = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Sigue escribiendo…',
    );
    expect(tail, findsOneWidget);
    expect(tester.widget<TextField>(tail).focusNode?.hasFocus, isTrue);
  });

  testWidgets('delete en el párrafo vacío lo elimina solo', (tester) async {
    await _pump(tester);
    await _openNote(tester);

    final tail = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Sigue escribiendo…',
    );
    expect(tail, findsNothing);

    await tester.tap(find.text('Lista'));
    await tester.pumpAndSettle();
    // La lista deja un párrafo vacío debajo.
    expect(tail, findsOneWidget);

    await tester.tap(tail);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    // Sin letras, el párrafo desaparece: no queda un hueco en la nota.
    expect(tail, findsNothing);
  });

  test('el formato solo cambia la parte seleccionada del texto', () {
    final controller = NoteRichTextController(text: 'hola mundo');
    controller.applyFormat(
      bold: true,
      range: const TextSelection(baseOffset: 5, extentOffset: 10),
    );

    expect(controller.formats, hasLength(1));
    expect(controller.formats.single.start, 5);
    expect(controller.formats.single.end, 10);
    expect(controller.formats.single.bold, isTrue);
    controller.dispose();
  });

  test('con el cursor, el estilo se aplica a lo que se escribe después', () {
    final controller = NoteRichTextController(text: 'hola');
    // El cursor se coloca al final, como al tocar el final del párrafo.
    controller.value = const TextEditingValue(
      text: 'hola',
      selection: TextSelection.collapsed(offset: 4),
    );
    controller.applyFormat(bold: true);
    // Nada se pone en negrita todavía: el estilo queda armado en el cursor.
    expect(controller.formats, isEmpty);

    controller.value = const TextEditingValue(
      text: 'hola!',
      selection: TextSelection.collapsed(offset: 5),
    );
    expect(controller.formats, hasLength(1));
    expect(controller.formats.single.start, 4);
    expect(controller.formats.single.end, 5);
    expect(controller.formats.single.bold, isTrue);
    controller.dispose();
  });

  setUp(() {
    _posts.clear();
    _deleted = <int>[];
    HsAccess.seedForTest(
      admin: true,
      modules: {
        'notes': {'create', 'read', 'update', 'delete'},
      },
    );
    _installMock();
  });

  tearDown(() {
    HsApi.client = http.Client();
  });

  testWidgets('escritorio: lista a la izquierda y documento a la derecha', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Notas'), findsOneWidget);
    expect(find.text('Lista del sábado'), findsOneWidget);
    expect(find.text('Elige una nota'), findsOneWidget);
    // Chip de visibilidad en la tarjeta.
    expect(find.text('Personal'), findsOneWidget);

    await _openNote(tester);

    // Se escribe DIRECTO en la hoja: texto y tareas comparten un estilo
    // plano sin campos ni tarjeta envolviendo la lista.
    expect(find.text('Comprar baterías'), findsWidgets);
    expect(find.text('Cargar flashes'), findsOneWidget);
    expect(find.text('Elige una nota'), findsNothing);
    // El título y los párrafos se ven como texto, sin campo ni línea.
    expect(find.text('Título'), findsOneWidget);
    final titleField = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.hintText == 'Título',
      ),
    );
    expect(titleField.decoration?.border, InputBorder.none);
    expect(titleField.decoration?.filled, isNot(true));
    final paragraphField = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Escribe algo…',
      ),
    );
    expect(paragraphField.decoration?.border, InputBorder.none);
    expect(paragraphField.decoration?.filled, isNot(true));
    // Guardar es SOLO un icono.
    expect(find.byTooltip('Guardar nota'), findsOneWidget);
  });

  testWidgets('guarda el título, los bloques y la casilla marcada', (
    tester,
  ) async {
    await _pump(tester);
    await _openNote(tester);

    await tester.tap(find.byTooltip('Guardar nota'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_posts, isNotEmpty);
    final body = _posts.last;
    expect(body['title'], 'Lista del sábado');
    expect(body['visibility'], 'private');
    final blocks = (body['blocks'] as List).cast<Map>();
    expect(blocks.length, 2);
    expect(blocks[0]['text'], 'Comprar baterías');
    final items = (blocks[1]['items'] as List).cast<Map>();
    expect(items.single['text'], 'Cargar flashes');
    expect(items.single['done'], isTrue);
  });

  testWidgets('modo selección: se elige un dibujo y se elimina', (
    tester,
  ) async {
    await _pump(tester);
    await _openNote(tester);
    await tester.tap(find.text('Dibujo'));
    await tester.pumpAndSettle();
    expect(find.byType(AspectRatio), findsOneWidget);

    await tester.tap(find.text('Seleccionar'));
    await tester.pumpAndSettle();
    expect(
      find.text('Arrastra sobre la nota para seleccionar'),
      findsOneWidget,
    );

    // Tocar el lienzo elige el dibujo (es atómico, no tiene letras).
    await tester.tap(find.byType(AspectRatio));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Eliminar selección'));
    await tester.pumpAndSettle();

    expect(find.byType(AspectRatio), findsNothing);
    expect(_editorParagraph('Comprar baterías'), findsOneWidget);
    expect(_editorParagraph('Cargar flashes'), findsOneWidget);
  });

  testWidgets('modo selección: arrastrar corta el texto y borra el dibujo', (
    tester,
  ) async {
    await _pump(tester);
    await _openNote(tester);
    await tester.tap(find.text('Dibujo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seleccionar'));
    await tester.pumpAndSettle();

    final paragraph = _editorParagraph('Comprar baterías');
    final from = tester.getTopLeft(paragraph) + const Offset(24, 4);
    final to = tester.getCenter(find.byType(AspectRatio));
    await tester.dragFrom(from, to - from);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Eliminar selección'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Guardar nota'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final blocks = (_posts.last['blocks'] as List).cast<Map>();
    expect(blocks.any((b) => b['type'] == 'drawing'), isFalse);
    // El párrafo se cortó a la mitad: quedan las letras de arriba.
    final kept = (blocks.first['text'] ?? '').toString();
    expect(kept.length, lessThan('Comprar baterías'.length));
    expect('Comprar baterías'.startsWith(kept), isTrue);
  });

  testWidgets('el dibujo se inserta como bloque y se edita al tocarlo', (
    tester,
  ) async {
    await _pump(tester);
    await _openNote(tester);

    // Insertar el bloque no navega; tocar su tarjeta sí abre el lienzo.
    await tester.tap(find.text('Dibujo'));
    await tester.pumpAndSettle();
    expect(find.byType(DrawingThumb), findsOneWidget);
    expect(find.text('Toca para dibujar'), findsOneWidget);
    await tester.tap(find.text('Toca para dibujar'));
    await tester.pumpAndSettle();
    expect(find.text('Lápiz'), findsOneWidget);
    expect(find.text('Resaltador'), findsOneWidget);
    expect(find.text('Goma'), findsOneWidget);

    final canvas = find.byType(NoteCanvas);
    expect(canvas, findsOneWidget);
    final box = tester.getRect(canvas);
    final gesture = await tester.startGesture(box.center);
    await gesture.moveBy(const Offset(-30, -20));
    await gesture.moveBy(const Offset(40, 25));
    await gesture.up();
    await tester.pump();

    // «Listo» vuelve a la nota con el dibujo insertado.
    await tester.tap(find.byTooltip('Listo'));
    await tester.pumpAndSettle();
    expect(find.byType(DrawingThumb), findsOneWidget);

    await tester.tap(find.byTooltip('Guardar nota'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final blocks = (_posts.last['blocks'] as List).cast<Map>();
    final drawing = blocks.lastWhere((b) => b['type'] == 'drawing');
    final strokes = (drawing['strokes'] as List).cast<Map>();
    expect(strokes, hasLength(1));
    final points = (strokes.single['points'] as List).cast<List>();
    expect(points.length, greaterThan(1));
    // Puntos NORMALIZADOS (0..1): se ven igual en cualquier pantalla.
    for (final p in points) {
      expect((p[0] as num).toDouble(), inInclusiveRange(0, 1));
      expect((p[1] as num).toDouble(), inInclusiveRange(0, 1));
    }
  });

  testWidgets('Enter en una tarea crea otra casilla', (tester) async {
    await _pump(tester);
    await _openNote(tester);

    final taskField = find.ancestor(
      of: find.text('Cargar flashes'),
      matching: find.byType(TextField),
    );
    expect(taskField, findsOneWidget);
    await tester.tap(taskField);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();

    expect(find.text('Cargar flashes'), findsOneWidget);
    expect(find.text('Escribe una tarea…'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Guardar nota'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final blocks = (_posts.last['blocks'] as List).cast<Map>();
    final tasks = (blocks[1]['items'] as List).cast<Map>();
    expect(tasks, hasLength(2));
    expect(tasks.first['text'], 'Cargar flashes');
  });

  testWidgets('la nota se puede compartir con la empresa', (tester) async {
    await _pump(tester);
    await _openNote(tester);

    await tester.tap(find.byTooltip('Solo para ti'));
    await tester.pumpAndSettle();
    expect(find.text('¿Quién puede ver esta nota?'), findsOneWidget);

    await tester.tap(find.text('Empresa'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Guardar nota'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_posts.last['visibility'], 'company');
  });

  testWidgets(
    'celular: documento completo, guardar de icono y barra de insertar',
    (tester) async {
      await _pump(tester, size: const Size(420, 880));

      expect(find.text('Lista del sábado'), findsOneWidget);
      expect(find.text('Elige una nota'), findsNothing);

      await _openNote(tester);
      await tester.pumpAndSettle();

      expect(find.text('Título'), findsOneWidget);
      expect(find.text('Texto'), findsOneWidget);
      expect(find.text('Lista'), findsOneWidget);
      expect(find.text('Dibujo'), findsOneWidget);
      expect(find.byTooltip('Guardar nota'), findsOneWidget);
      // En el celular el botón de visibilidad es solo icono (sin etiqueta).
      expect(find.text('Personal'), findsNothing);
    },
  );

  testWidgets('celular angosto: el título cabe junto a la visibilidad', (
    tester,
  ) async {
    await _pump(tester, size: const Size(320, 720));
    await _openNote(tester);
    await tester.pumpAndSettle();

    // Título, visibilidad y guardar conviven en la misma fila (sin desbordar).
    expect(find.text('Lista del sábado'), findsWidgets);
    expect(find.byTooltip('Solo para ti'), findsOneWidget);
    expect(find.byTooltip('Guardar nota'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin permiso de editar, la nota se abre en solo lectura', (
    tester,
  ) async {
    HsAccess.seedForTest(
      admin: true,
      modules: {
        'notes': {'read'},
      },
    );
    await _pump(tester);
    await _openNote(tester);

    expect(find.byTooltip('Guardar nota'), findsNothing);
    expect(find.text('Cargar flashes'), findsOneWidget);
    // Sin barra de insertar: no se puede modificar.
    expect(find.text('Texto'), findsNothing);
  });

  testWidgets('eliminar pide confirmación y llama al backend', (tester) async {
    await _pump(tester);

    await tester.tap(find.byTooltip('Eliminar nota'));
    await tester.pumpAndSettle();

    expect(find.text('¿Eliminar la nota?'), findsOneWidget);
    await tester.tap(find.text('Eliminar').last);
    await tester.pumpAndSettle();

    expect(_deleted, [1]);
  });
}

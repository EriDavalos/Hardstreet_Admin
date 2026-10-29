import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/home_widgets.dart';
import 'package:hardstreet_admin/event_widget.dart';
import 'package:hardstreet_admin/note_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 29, 12, 0);

  // ---------------- Notas ----------------

  test('Notas: las fijadas primero y dentro de cada grupo la más reciente arriba', () {
    final rows = NotesWidget.buildRows(
      [
        _summary(id: 1, title: 'Vieja', updated: DateTime(2026, 10, 10)),
        _summary(
          id: 2,
          title: 'Fijada vieja',
          updated: DateTime(2026, 10, 1),
          pinned: true,
        ),
        _summary(id: 3, title: 'Reciente', updated: DateTime(2026, 10, 29, 9)),
      ],
      now: now,
    );
    expect(rows.map((r) => r['id']).toList(), [2, 3, 1]);
  });

  test('Notas: cada fila lleva las claves que lee el widget nativo', () {
    final rows = NotesWidget.buildRows(
      [
        _summary(
          id: 5,
          title: 'Lista del sábado',
          preview: 'Comprar baterías',
          updated: DateTime(2026, 10, 20, 18, 30),
        ),
      ],
      now: now,
    );
    expect(rows.single.keys.toSet(), {'id', 'title', 'sub', 'when'});
    expect(rows.single['id'], 5);
    expect(rows.single['title'], 'Lista del sábado');
    expect(rows.single['sub'], 'Comprar baterías');
    expect(rows.single['when'], 'MAR 20 OCT');
  });

  test('Notas: título en blanco se reporta como «Sin título»', () {
    final rows = NotesWidget.buildRows(
      [_summary(id: 9, title: '   ')],
      now: now,
    );
    expect(rows.single['title'], 'Sin título');
  });

  test('Notas: notas sin id o sin fecha no rompen el listado', () {
    final rows = NotesWidget.buildRows(
      [
        _summary(id: 0, title: 'apagada'),
        _summary(id: 4, title: 'sin fecha', updated: null),
      ],
      now: now,
    );
    expect(rows, hasLength(1));
    expect(rows.single['id'], 4);
    expect(rows.single['when'], '');
  });

  // ---------------- Avisos ----------------

  test('Avisos: los no leídos llevan «● » en el título', () {
    final rows = AvisosWidget.buildRows([
      {'id': 1, 'title': 'Falta 1 día', 'body': 'Boda Ana', 'isRead': 0},
      {'id': 2, 'title': 'Ya leído', 'body': '', 'isRead': 1},
    ]);
    expect(rows[0]['title'], '● Falta 1 día');
    expect(rows[1]['title'], 'Ya leído');
    expect(rows[0]['sub'], 'Boda Ana');
    expect(rows[1]['sub'], '');
  });

  test('Avisos: el más reciente arriba y la fecha corta con hora', () {
    final rows = AvisosWidget.buildRows([
      {
        'id': 1,
        'title': 'Viejo',
        'body': '',
        'isRead': 1,
        'eventDate': '2026-10-10 08:00:00',
      },
      {
        'id': 2,
        'title': 'Nuevo',
        'body': '',
        'isRead': 1,
        'eventDate': '2026-10-29 09:30:00',
      },
    ]);
    expect(rows.map((r) => r['id']).toList(), [2, 1]);
    // Sin fecha válida va al final con `when` vacía.
    expect(rows.last['when'], '10 oct · 08:00');
  });

  test('Avisos: filas totalmente vacías se descartan', () {
    final rows = AvisosWidget.buildRows([
      {'id': 1, 'title': '', 'body': ''},
      {'id': 2, 'title': 'Algo', 'body': ''},
    ]);
    expect(rows, hasLength(1));
    expect(rows.single['id'], 2);
  });

  // ---------------- Toques compartidos (arranque en frío) ----------------

  test('la acción pendiente se REPARTE: cada widget reclama solo la suya',
      () async {
    final Map<String, Object?> taps = {'action': 'note', 'id': 5};
    var cleared = false;
    const eventsChannel = MethodChannel(UpcomingEventsWidget.channelName);
    const notesChannel = MethodChannel(NotesWidget.channelName);
    Map<String, Object?>? notesResult = taps;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(eventsChannel, (call) async {
        if (call.method == 'consumeTap') {
          return cleared ? null : taps;
        }
        // clearTap del lado de eventos: lo mismo que en Kotlin, una sola
        // variable compartida.
        if (call.method == 'clearTap') {
          cleared = true;
          return true;
        }
        return null;
      })
      ..setMockMethodCallHandler(notesChannel, (call) async {
        if (call.method == 'consumeTap') {
          return cleared ? null : notesResult;
        }
        if (call.method == 'clearTap') {
          notesResult = null;
          return true;
        }
        return null;
      });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        ..setMockMethodCallHandler(eventsChannel, null)
        ..setMockMethodCallHandler(notesChannel, null);
      NotesWidget.resetForTest();
      UpcomingEventsWidget.requested.value = null;
    });

    // El widget de eventos pregunta primero: el toque es de NOTAS, no lo
    // reclama ni lo borra.
    await UpcomingEventsWidget.consumePending();
    expect(UpcomingEventsWidget.requested.value, isNull);
    expect(cleared, isFalse, reason: 'la acción queda para el widget dueño');

    // El widget de notas pregunta: es suya, la atiende y la borra.
    await NotesWidget.consumePending();
    expect(NotesWidget.requested.value?.noteId, 5);
    expect(NotesWidget.requested.value?.create, isFalse);
    expect(notesResult, isNull, reason: 'consumida: ya no se ofrece otra vez');
  });
}

NoteSummary _summary({
  required int id,
  required String title,
  String preview = '',
  bool pinned = false,
  DateTime? updated,
}) =>
    NoteSummary(
      id: id,
      title: title,
      preview: preview,
      color: '',
      pinned: pinned,
      updated: updated,
      hasDrawing: false,
    );

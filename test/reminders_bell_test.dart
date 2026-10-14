import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/reminders_service.dart';
import 'package:hardstreet_admin/widgets/reminders_bell.dart';

/// Monta la campanita dentro de un MaterialApp mínimo, con el servicio
/// precargado (sin red) para poder verificar el badge y el diálogo.
Future<void> _pumpBell(WidgetTester tester, {int unread = 0}) async {
  final service = RemindersService.instance;
  // Responder PUT /api/reminders sin red real: markAllRead() confirma con el
  // servidor y, sin este mock, el TestWidgetsFlutterBinding devolvería 400 y
  // rompería el diálogo.
  final previousClient = HsApi.client;
  HsApi.client = MockClient((_) async => http.Response(
        '{"ok":true,"unread":0}',
        200,
        headers: {'content-type': 'application/json'},
      ));
  addTearDown(() => HsApi.client = previousClient);

  service.seedForTest([
    for (var i = 1; i <= (unread == 0 ? 2 : unread); i++)
      {
        'id': i,
        'scheduleId': i * 10,
        'kind': i.isOdd ? '7d' : '1d',
        'title': 'Aviso $i',
        'body': 'Evento en $i días',
        'isRead': i <= unread ? 0 : 1,
        'created': '2026-10-11T08:00:00',
      },
  ]);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        // ListenableBuilder separa el widget de la campanita del singleton:
        // al cambiar el estado, solo se reconstruye este subtree y el finder
        // sigue apuntando al MISMO IconButton (sin desmontarse).
        body: ListenableBuilder(
          listenable: service,
          builder: (context, _) => const Align(
            alignment: Alignment.topRight,
            child: RemindersBell(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Iconos dentro de la fila de un aviso (la fila lleva una clave por ID).
List<IconData?> _rowIcons(WidgetTester tester, int id) => tester
    .widgetList<Icon>(find.descendant(
      of: find.byKey(ValueKey('reminder-$id')),
      matching: find.byType(Icon),
    ))
    .map((i) => i.icon)
    .toList();

void main() {
  final service = RemindersService.instance;

  tearDown(() => service.reset());

  testWidgets('badge cuenta los avisos NO leídos (y oculta si no hay)',
      (tester) async {
    await _pumpBell(tester, unread: 0);
    // Sin no leídos: no debe salir ningún badge con número.
    expect(find.text('1'), findsNothing);
    expect(find.text('2'), findsNothing);

    await _pumpBell(tester, unread: 2);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('badge limita el número a 9+', (tester) async {
    await _pumpBell(tester, unread: 12);
    expect(find.text('9+'), findsOneWidget);
  });

  testWidgets('al tocar la campanita se abre el PANEL con los avisos',
      (tester) async {
    await _pumpBell(tester, unread: 2);

    await tester.tap(find.byType(RemindersBell));
    await tester.pumpAndSettle();

    // Ya no es un diálogo modal: el panel FIJO se ancla bajo la top bar
    // (junto a la campanita) sin tapar el resto de la pantalla.
    expect(find.byType(Dialog), findsNothing);
    final panel = tester.getRect(find.text('Avisos de eventos'));
    expect(panel.top, lessThan(160),
        reason: 'el panel queda anclado arriba, bajo la barra superior');

    expect(find.text('Avisos de eventos'), findsOneWidget);
    expect(find.text('Aviso 1'), findsOneWidget);
    expect(find.text('Aviso 2'), findsOneWidget);
    // Con no leídos pendientes aparece la acción de marcar todos.
    expect(find.text('Marcar leídos'), findsOneWidget);
  });

  testWidgets('"Marcar leídos" deja las filas leÍDAS y oculta la acción',
      (tester) async {
    await _pumpBell(tester, unread: 2);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byType(RemindersBell));
    await tester.pumpAndSettle();

    // Fila 1 ANTES de marcar: no leída (icono "circle").
    expect(_rowIcons(tester, 1), <IconData?>[Icons.circle]);

    await tester.tap(find.text('Marcar leídos'));
    await tester.pumpAndSettle();

    // Fila 1 DESPUÉS: leída (icono "check_circle_outline"), sin "circle".
    final after = _rowIcons(tester, 1);
    expect(after, contains(Icons.check_circle_outline));
    expect(after, isNot(contains(Icons.circle)));

    // La acción de marcar desaparece (0 sin leer) y el panel sigue abierto.
    expect(find.text('Marcar leídos'), findsNothing);
    expect(find.text('Avisos de eventos'), findsOneWidget);

    // Tocar la campanita de nuevo (o fuera) lo cierra.
    await tester.tap(find.byType(RemindersBell));
    await tester.pumpAndSettle();
    expect(find.text('Avisos de eventos'), findsNothing);
  });
}

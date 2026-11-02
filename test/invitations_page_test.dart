import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_access.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/invitations_page.dart';

// ==================================================================
// MÓDULO INVITACIONES — listado, alta y compartir
// ==================================================================
// Backend falso: lo que importa es que la pantalla pida la lista, abra el
// catálogo de plantillas, guarde la invitación con su HTML (el que alimenta
// la liga pública) y enseñe la liga al compartir.
// ==================================================================

final _posts = <Map<String, dynamic>>[];
final _puts = <Map<String, dynamic>>[];

List<Map<String, dynamic>> _items() => [
  {
    'id': 1,
    'title': 'Boda de Ana & Luis',
    'template': 'boda-marfil',
    'occasion': 'Boda',
    'headline': 'Ana & Luis',
    'subheadline': '¡Nos casamos!',
    'dateText': '14 de febrero de 2026',
    'timeText': '6:00 pm',
    'placeName': 'Hacienda San José',
    'placeAddress': 'Camino Real 120',
    'message': '',
    'dressCode': '',
    'rsvpPhone': '',
    'accent': '',
    'font': '',
    'photos': <String>[],
    'slug': 'abc123def456',
    'published': true,
    'updated': '2026-10-30T10:00:00',
  },
  {
    'id': 2,
    'title': 'Cumple de Sofía',
    'template': 'cumple-pop',
    'occasion': 'Cumpleaños',
    'headline': 'Sofía',
    'subheadline': '¡Cumple 18!',
    'dateText': '',
    'timeText': '',
    'placeName': '',
    'placeAddress': '',
    'message': '',
    'dressCode': '',
    'rsvpPhone': '',
    'accent': '',
    'font': '',
    'photos': <String>[],
    'slug': '',
    'published': false,
    'updated': '2026-10-30T09:00:00',
  },
];

void _installMock() {
  final previous = HsApi.client;
  addTearDown(() => HsApi.client = previous);
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    if (!request.url.path.endsWith('/api/admin/invitations')) {
      return http.Response(
        jsonEncode({'ok': false, 'message': 'ruta no simulada'}),
        404,
        headers: headers,
      );
    }
    switch (request.method) {
      case 'GET':
        return http.Response(
          jsonEncode({'ok': true, 'ready': true, 'invitations': _items()}),
          200,
          headers: headers,
        );
      case 'POST':
      case 'PUT':
        final body = (jsonDecode(request.body) as Map).cast<String, dynamic>();
        if (request.method == 'POST') {
          _posts.add(body);
        } else {
          _puts.add(body);
        }
        final saved = <String, dynamic>{
          ..._items().first,
          ...body,
          'id': body['id'] ?? 3,
          // El slug lo genera el servidor: se conserva el de la invitación.
          'slug': body['slug'] ??
              (body['id'] == 1 ? 'abc123def456' : 'nuevaliga123'),
          'published': body['published'] ?? false,
        };
        return http.Response(
          jsonEncode({
            'ok': true,
            'message': 'Invitación guardada',
            'item': saved,
          }),
          200,
          headers: headers,
        );
      case 'DELETE':
        return http.Response(
          jsonEncode({
            'ok': true,
            'message': 'Invitación eliminada',
            'item': {'id': 1},
          }),
          200,
          headers: headers,
        );
    }
    return http.Response('{}', 405, headers: headers);
  });
}

void _seedAccess() {
  HsAccess.seedForTest(
    modules: {
      'invitations': {'read', 'create', 'update', 'delete'},
    },
  );
  addTearDown(HsAccess.reset);
}

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1500, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: InvitationsPage())),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    _posts.clear();
    _puts.clear();
  });

  testWidgets('el listado enseña cada invitación y su estado', (tester) async {
    _installMock();
    _seedAccess();
    await _open(tester);

    expect(find.text('Boda de Ana & Luis'), findsOneWidget);
    expect(find.text('Cumple de Sofía'), findsOneWidget);
    expect(find.text('Publicada'), findsOneWidget);
    expect(find.text('Borrador'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('crear: escribe los nombres y guarda el HTML', (tester) async {
    _installMock();
    _seedAccess();
    await _open(tester);

    await tester.tap(find.text('Nueva invitación'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Primero se elige la plantilla (ReynaCoot o Marfil & Oro).
    expect(find.text('Elige una plantilla'), findsOneWidget);
    await tester.tap(find.text('Usar ReynaCoot'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('invitation-headline')), findsOneWidget);

    // Editor: el formulario y la vista previa salen del mismo modelo.
    final headline = find.byKey(const ValueKey('invitation-headline'));
    expect(headline, findsOneWidget);
    await tester.enterText(headline, 'Ana & Luis');
    await tester.pump();
    expect(find.text('Ana & Luis'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('invitation-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(_posts, isNotEmpty, reason: 'se manda al backend');
    final body = _posts.last;
    expect(body['template'], 'sobre-xv');
    expect(body['headline'], 'Ana & Luis');
    final html = '${body['html']}';
    expect(html, contains('<html'));
    expect(html, contains('Ana &amp; Luis'));
    expect(html, contains('og:title'));
    expect(body['published'], isFalse);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('compartir enseña la liga pública de la invitación', (
    tester,
  ) async {
    _installMock();
    _seedAccess();
    await _open(tester);

    await tester.tap(find.byTooltip('Compartir').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Compartir invitación'), findsOneWidget);
    final link = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(link.data, contains('?invitation=abc123def456'));
    // Compartir regenera el HTML con la portada animada de la plantilla.
    expect(_puts, isNotEmpty);
    expect('${_puts.last['html']}', contains('env-flap'));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('despublicar desde la tarjeta pide confirmación', (tester) async {
    _installMock();
    _seedAccess();
    await _open(tester);

    await tester.tap(find.byTooltip('Acciones de Boda de Ana & Luis'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Despublicar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('¿Despublicar la invitación?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Despublicar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_puts.any((p) => p['published'] == false), isTrue);

    await tester.pumpWidget(const SizedBox());
  });
}

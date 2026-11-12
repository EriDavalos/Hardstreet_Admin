import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hardstreet_admin/core/access/hs_access.dart';
import 'package:hardstreet_admin/modules/invitations/components/templates/custom_invitation_templates.dart';
import 'package:hardstreet_admin/core/api/hs_api.dart';
import 'package:hardstreet_admin/modules/invitations/pages/invitations_page.dart';

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
          'slug':
              body['slug'] ??
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

Future<void> _open(
  WidgetTester tester, {
  Size size = const Size(1500, 1500),
}) async {
  tester.view.physicalSize = size;
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
    SharedPreferences.setMockInitialValues({});
    InvitationTemplateStore.resetForTest();
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

    // Primero se elige la plantilla (Rosa Pastel o Marfil & Oro).
    expect(find.text('Elige una plantilla'), findsOneWidget);
    await tester.tap(find.text('Usar Rosa Pastel'));
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

  testWidgets('el editor abre el panel de componentes', (tester) async {
    _installMock();
    _seedAccess();
    await _open(tester);

    await tester.tap(find.text('Boda de Ana & Luis'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey('invitation-tab-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.byKey(const ValueKey('invitation-canvas-tab-invitation')),
    );
    await tester.pump();

    expect(find.text('Componentes de la invitación'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('invitation-layer-families')),
      findsOneWidget,
    );
    // El lienzo arranca en la invitación; la portada tiene su propia pestaña.
    expect(find.byKey(const ValueKey('invitation-drop-end')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('invitation-cover-preview')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('invitation-item-cover-carta')),
      findsOneWidget,
    );
    for (final key in const ['cover', 'quote', 'photos', 'rsvp']) {
      expect(
        find.byKey(ValueKey('invitation-fixed-layer-$key')),
        findsOneWidget,
      );
    }

    // Ocultar un componente lo manda a la biblioteca; desde ahí se restaura.
    final familiesToggle = find.byKey(
      const ValueKey('invitation-toggle-families'),
    );
    await tester.ensureVisible(familiesToggle);
    await tester.pump();
    await tester.tap(familiesToggle);
    await tester.pump();
    final addFamilies = find.byKey(
      const ValueKey('invitation-add-component-families'),
    );
    await tester.ensureVisible(addFamilies);
    await tester.pump();
    expect(addFamilies, findsOneWidget);
    await tester.tap(addFamilies);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('invitation-add-component-families')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el lienzo separa Portada, Invitación y Todo', (tester) async {
    _installMock();
    _seedAccess();
    await _open(tester);

    await tester.tap(find.text('Boda de Ana & Luis'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final coverTab = find.byKey(const ValueKey('invitation-canvas-tab-cover'));
    final invitationTab = find.byKey(
      const ValueKey('invitation-canvas-tab-invitation'),
    );
    final allTab = find.byKey(const ValueKey('invitation-canvas-tab-all'));
    expect(coverTab, findsOneWidget);
    expect(invitationTab, findsOneWidget);
    expect(allTab, findsOneWidget);

    // Invitación: el documento editable, sin la portada diminuta al lado.
    expect(find.byKey(const ValueKey('invitation-preview')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('invitation-cover-preview')),
      findsNothing,
    );

    // Portada: responde al mismo conmutador de teléfono/computadora.
    await tester.tap(coverTab);
    await tester.pump();
    final cover = find.byKey(const ValueKey('invitation-cover-preview'));
    expect(cover, findsOneWidget);
    expect(tester.getSize(cover).width, lessThan(460));
    expect(find.byKey(const ValueKey('invitation-preview')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('invitation-device-desktop')));
    await tester.pump();
    expect(tester.getSize(cover).width, greaterThan(700));
    await tester.tap(find.byKey(const ValueKey('invitation-device-phone')));
    await tester.pump();
    expect(tester.getSize(cover).width, lessThan(460));

    // Todo: el documento público completo, empezando por el sobre.
    await tester.tap(allTab);
    await tester.pump();
    expect(find.byKey(const ValueKey('invitation-preview')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('invitation-cover-preview')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Items agrupa todos los diseños por componente y los aplica', (
    tester,
  ) async {
    _installMock();
    _seedAccess();
    await _open(tester);

    await tester.tap(find.text('Boda de Ana & Luis'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey('invitation-tab-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('TODOS LOS DISEÑOS, POR COMPONENTE'), findsOneWidget);
    for (final key in const ['cover', 'details', 'itinerary']) {
      expect(
        find.byKey(ValueKey('invitation-design-group-$key')),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey('invitation-item-cover-carta')),
      findsOneWidget,
    );
    final detailsList = find.byKey(
      const ValueKey('invitation-item-design-details-lista'),
    );
    expect(detailsList, findsOneWidget);
    expect(
      find.byKey(const ValueKey('invitation-item-design-itinerary-tarjetas')),
      findsOneWidget,
    );

    await tester.ensureVisible(detailsList);
    await tester.pump();
    await tester.tap(detailsList);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('invitation-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(_puts, isNotEmpty);
    expect(_puts.last['design']['components']['details'], 'lista');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el lienzo muestra acciones al pasar el ratón y elimina', (
    tester,
  ) async {
    _installMock();
    _seedAccess();
    await _open(tester);

    await tester.tap(find.text('Boda de Ana & Luis'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey('invitation-tab-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.byKey(const ValueKey('invitation-canvas-tab-invitation')),
    );
    await tester.pump();

    final section = find.byKey(
      const ValueKey('invitation-preview-section-families'),
    );
    expect(section, findsOneWidget);
    await tester.ensureVisible(section);
    await tester.pump();

    final remove = find.byKey(
      const ValueKey('invitation-preview-remove-families'),
    );
    expect(remove, findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(section));
    await tester.pump();

    expect(remove, findsOneWidget);
    expect(tester.widget<IconButton>(remove).onPressed, isNotNull);
    await tester.tap(remove);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('invitation-preview-section-families')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('invitation-add-component-families')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('arrastrar un ítem del panel lo inserta en la invitación', (
    tester,
  ) async {
    _installMock();
    _seedAccess();
    await _open(tester);

    await tester.tap(find.text('Boda de Ana & Luis'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey('invitation-tab-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.byKey(const ValueKey('invitation-canvas-tab-invitation')),
    );
    await tester.pump();

    // Se oculta para que quede en la biblioteca y se pueda arrastrar como
    // componente nuevo.
    final toggle = find.byKey(const ValueKey('invitation-toggle-families'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('invitation-preview-section-families')),
      findsNothing,
    );

    final source = find.byKey(
      const ValueKey('invitation-add-component-families'),
    );
    final target = find.byKey(const ValueKey('invitation-drop-end'));
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.ensureVisible(source);
    await tester.pump();

    final gesture = await tester.startGesture(tester.getCenter(source));
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.moveBy(const Offset(0, -24));
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 160));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('invitation-preview-section-families')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('la portada se elige y se guarda con el diseño', (tester) async {
    _installMock();
    _seedAccess();
    await _open(tester);

    await tester.tap(find.text('Boda de Ana & Luis'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey('invitation-tab-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    for (final key in const [
      'rosa',
      'carta',
      'xv',
      'noche',
      'cortina',
      'clasica',
    ]) {
      expect(find.byKey(ValueKey('invitation-cover-$key')), findsOneWidget);
    }

    final xv = find.byKey(const ValueKey('invitation-cover-xv'));
    await tester.ensureVisible(xv);
    await tester.tap(xv);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('invitation-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(_puts, isNotEmpty);
    expect(_puts.last['design']['coverStyle'], 'xv');
    expect('${_puts.last['html']}', contains('hs-scene-xv'));
    expect('${_puts.last['html']}', contains('hs-xv-number'));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('la Carta elige y guarda su fondo de boda', (tester) async {
    _installMock();
    _seedAccess();
    await _open(tester);

    await tester.tap(find.text('Boda de Ana & Luis'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey('invitation-tab-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final carta = find.byKey(const ValueKey('invitation-cover-carta'));
    await tester.ensureVisible(carta);
    await tester.tap(carta);
    await tester.pump();

    expect(find.text('FONDO DE LA CARTA'), findsOneWidget);
    final jardin = find.byKey(
      const ValueKey('invitation-carta-backdrop-jardin'),
    );
    await tester.ensureVisible(jardin);
    await tester.tap(jardin);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('invitation-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(_puts, isNotEmpty);
    expect(_puts.last['design']['coverStyle'], 'carta');
    expect(_puts.last['design']['coverBackdrop'], 'jardin');
    final html = '${_puts.last['html']}';
    expect(html, contains('hs-carta-bg-jardin'));
    expect(html, contains('hs-carta-flor-esquina'));
    expect(html, contains('hs-carta-anillos'));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el editor ocupa la ventana y el lienzo domina el espacio', (
    tester,
  ) async {
    _installMock();
    _seedAccess();
    await _open(tester);

    await tester.tap(find.text('Boda de Ana & Luis'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // La ventana ya no es un diálogo de 1160 px: ocupa la pantalla.
    final dialog = tester.getSize(find.byType(Dialog));
    expect(dialog.width, greaterThan(1490));
    expect(dialog.height, greaterThan(1490));

    // Las herramientas viven en el borde izquierdo y la vista previa se
    // queda con el resto del lienzo.
    final rail = tester.getSize(
      find.byKey(const ValueKey('invitation-tool-rail')),
    );
    final panel = tester.getSize(
      find.byKey(const ValueKey('invitation-tool-panel')),
    );
    final canvas = tester.getSize(
      find.byKey(const ValueKey('invitation-canvas')),
    );
    expect(rail.width, greaterThan(70));
    expect(panel.width, greaterThan(380));
    expect(canvas.width, greaterThan(900));
    expect(canvas.height, greaterThan(1300));

    // La vista arranca como teléfono y puede pasar a computadora.
    final phone = tester.getSize(
      find.byKey(const ValueKey('invitation-preview')),
    );
    expect(phone.width, lessThan(460));
    await tester.tap(find.byKey(const ValueKey('invitation-device-desktop')));
    await tester.pump();
    final desktop = tester.getSize(
      find.byKey(const ValueKey('invitation-preview')),
    );
    // En escritorio la invitación también usa todo el ancho del lienzo.
    expect(desktop.width, greaterThan(700));
    expect(desktop.width, greaterThan(phone.width));
    await tester.tap(find.byKey(const ValueKey('invitation-device-phone')));
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('en ventana angosta el lienzo sigue siendo el protagonista', (
    tester,
  ) async {
    _installMock();
    _seedAccess();
    await _open(tester, size: const Size(600, 900));

    await tester.ensureVisible(find.text('Boda de Ana & Luis'));
    await tester.tap(find.text('Boda de Ana & Luis'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final dialog = tester.getSize(find.byType(Dialog));
    expect(dialog.width, greaterThan(590));
    expect(dialog.height, greaterThan(890));
    expect(find.byKey(const ValueKey('invitation-tool-panel')), findsNothing);
    final canvas = tester.getSize(
      find.byKey(const ValueKey('invitation-canvas')),
    );
    expect(canvas.width, greaterThan(500));

    // El riel sigue en el borde y abre el panel encima del lienzo.
    await tester.tap(find.byKey(const ValueKey('invitation-tab-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('invitation-tool-panel')), findsOneWidget);
    expect(find.text('Componentes de la invitación'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('invitation-cover-preview')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

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

  testWidgets('crear y actualizar una plantilla desde el editor', (
    tester,
  ) async {
    _installMock();
    _seedAccess();
    await _open(tester);

    await tester.tap(find.text('Boda de Ana & Luis'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('invitation-tab-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final saveTemplate = find.byKey(const ValueKey('invitation-template-save'));
    await tester.ensureVisible(saveTemplate);
    await tester.tap(saveTemplate);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Guardar plantilla'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('template-dialog-name')),
      'Mi plantilla de boda',
    );
    await tester.tap(find.byKey(const ValueKey('template-dialog-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(InvitationTemplateStore.recipes, hasLength(1));
    final created = InvitationTemplateStore.recipes.single;
    expect(created.name, 'Mi plantilla de boda');
    expect(created.custom, isTrue);

    // Cambiar un componente y actualizar la misma plantilla.
    final detailsList = find.byKey(
      const ValueKey('invitation-item-design-details-lista'),
    );
    await tester.ensureVisible(detailsList);
    await tester.tap(detailsList);
    await tester.pump();
    await tester.ensureVisible(saveTemplate);
    await tester.tap(saveTemplate);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Editar plantilla'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('template-dialog-name')),
      'Mi plantilla actualizada',
    );
    await tester.tap(find.byKey(const ValueKey('template-dialog-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(InvitationTemplateStore.recipes, hasLength(1));
    final updated = InvitationTemplateStore.recipes.single;
    expect(updated.key, created.key);
    expect(updated.name, 'Mi plantilla actualizada');
    expect(updated.components['details'], 'lista');

    await tester.tap(find.byKey(const ValueKey('invitation-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(_puts, isNotEmpty);
    expect(_puts.last['design']['preset'], created.key);
    expect(_puts.last['design']['components']['details'], 'lista');
    expect('${_puts.last['html']}', contains('data-component="details"'));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el catálogo crea una plantilla y la ofrece para usar', (
    tester,
  ) async {
    _installMock();
    _seedAccess();
    await _open(tester);

    await tester.tap(find.text('Nueva invitación'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey('template-create')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nueva plantilla'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('template-dialog-name')),
      'Mi estilo propio',
    );
    await tester.tap(find.byKey(const ValueKey('template-dialog-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(InvitationTemplateStore.recipes, hasLength(1));
    expect(find.text('Mi estilo propio'), findsOneWidget);
    final use = find.text('Usar Mi estilo propio');
    await tester.ensureVisible(use);
    await tester.tap(use);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey('invitation-headline')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}

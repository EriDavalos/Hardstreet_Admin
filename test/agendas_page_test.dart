import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/event_widget.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/agendas_page.dart';
import 'package:hardstreet_admin/widgets/form_dialog.dart';
import 'package:hardstreet_admin/widgets/hs_place_picker.dart';

/// Instala un cliente HTTP falso con TRES agendas:
/// - el LUNES de la semana actual a las 14:30, "Cliente Test"
///   (siempre visible en la semana por defecto, sin depender de la fecha).
/// - día 20 a las 16:00, servicio "Sesión de fotos" (icono de cámara).
/// - día 22 SIN hora (medianoche) -> fila de "todo el día" de la semana.
void _installMockClient({
  List<Map<String, dynamic>>? posts,
  List<Map<String, dynamic>>? agendas,
}) {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  String dayOf(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
  final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));

  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;

    if (path.endsWith('/api/admin/agendas')) {
      if (request.method == 'POST') {
        posts?.add((jsonDecode(request.body) as Map).cast<String, dynamic>());
        return http.Response(
          jsonEncode({'ok': true, 'id': 9}),
          201,
          headers: headers,
        );
      }
      return http.Response(
        jsonEncode({
          // [agendas] permite simular lo que manda el servidor a un CLIENTE
          // (sus eventos + los ajenos enmascarados con `busy: true`).
          'agendas':
              agendas ??
              [
                {
                  'id': 1,
                  'purchasedPackageId': 1,
                  'userId': 2,
                  'clientName': 'Cliente Test',
                  'packageName': 'Boda Premium',
                  'serviceId': 5,
                  'serviceName': 'Cobertura en evento',
                  'eventDate': '${dayOf(monday)}T14:30:00',
                  'description': 'Ceremonia en el jardín',
                  // Lugar CON coordenadas: el detalle pinta el mini mapa (aquí se
                  // comprobaba el crash de los intrínsecos con FlutterMap dentro
                  // del AlertDialog).
                  'location': 'Hacienda San José',
                  'lat': 4.711,
                  'lng': -74.0721,
                },
                {
                  'id': 2,
                  'purchasedPackageId': 1,
                  'userId': 3,
                  'clientName': 'Otra Clienta',
                  'packageName': 'Sesión Familiar',
                  'serviceId': 6,
                  'serviceName': 'Sesión de fotos',
                  'eventDate': '${now.year}-${two(now.month)}-20T16:00:00',
                  'description': 'Fotos en el parque',
                },
                {
                  'id': 3,
                  'purchasedPackageId': 2,
                  'userId': 4,
                  'clientName': 'Entrega Álbum',
                  'packageName': 'Álbum de lujo',
                  'serviceId': 7,
                  'serviceName': 'Entrega de álbum',
                  'eventDate': '${now.year}-${two(now.month)}-22T00:00:00',
                  'description': 'Sin hora fija',
                },
              ],
        }),
        200,
        headers: headers,
      );
    }

    // ---- Datos del alta de evento (cliente → paquete → servicio) ----
    if (path.endsWith('/api/admin/clients')) {
      return http.Response(
        jsonEncode({
          'clients': [
            {'id': 2, 'name': 'Ana', 'lastname': 'Ruiz', 'email': 'ana@hs.mx'},
            {
              'id': 3,
              'name': 'Luis',
              'lastname': 'Gómez',
              'email': 'luis@hs.mx',
            },
          ],
        }),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/admin/client-packages')) {
      final userId =
          int.tryParse(request.url.queryParameters['userId'] ?? '') ?? 0;
      return http.Response(
        jsonEncode({
          'purchasedPackages': userId == 2
              ? [
                  {
                    'id': 10,
                    'name': 'Paquete Aniversario',
                    'price': 9000,
                    'paid': 3000,
                    'currency': 'MXN',
                    'status': 'En proceso',
                    'services': const [],
                  },
                ]
              : const [],
          'catalog': const [],
        }),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/admin/package-progress')) {
      return http.Response(
        jsonEncode({
          'package': {
            'id': 10,
            'name': 'Paquete Aniversario',
            'price': 9000,
            'paid': 3000,
            'balance': 6000,
            'status': 'En proceso',
            'statusId': 2,
            'finished': false,
          },
          'services': [
            {
              'id': 1,
              'serviceId': 5,
              'name': 'Cobertura de estudio',
              'description': '',
              'status': 'Pendiente',
              'statusId': 1,
              'done': false,
            },
          ],
          'movements': const [],
          'totals': const {},
          'canFinish': false,
          'blockers': const [],
        }),
        200,
        headers: headers,
      );
    }

    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

Future<void> _pumpAgendas(
  WidgetTester tester,
  Size size, {
  List<Map<String, dynamic>>? posts,
  List<Map<String, dynamic>>? agendas,
}) async {
  await tester.binding.setSurfaceSize(size);
  // En pruebas, MediaQuery NO sigue al tamaño de la superficie: hay que
  // declarar la vista para que la página vea la MISMA ventana que dibuja
  // (si no, un móvil de 390 px se maqueta como si fuera ancho).
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final previous = HsApi.client;
  _installMockClient(posts: posts, agendas: agendas);
  addTearDown(() => HsApi.client = previous);

  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: AgendasPage())),
  );
  await tester.pump(); // resuelve la respuesta simulada
  await tester.pump(const Duration(milliseconds: 900)); // animaciones
}

Future<void> _tapPump(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Bloque del evento en la REJILLA del calendario (excluye el panel lateral).
Finder _weekBlock() => find.descendant(
  of: find.byKey(const ValueKey('agenda-calendar')),
  matching: find.text('Cliente Test'),
);

/// Número que muestra el hueco [i] de ubicaciones del alta (1, 2, 3…).
String _placeNumber(WidgetTester tester, int i) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(ValueKey('agenda-place-number-$i')),
        matching: find.byType(Text),
      ),
    )
    .data!;

void main() {
  testWidgets(
    'Agendas (escritorio): semana estilo Google Calendar con panel lateral',
    (tester) async {
      await _pumpAgendas(tester, const Size(1200, 900));

      // Barra superior: Hoy + flechas + conmutador Semana/Mes.
      expect(find.byKey(const ValueKey('agenda-today')), findsOneWidget);
      expect(find.byTooltip('Semana siguiente'), findsOneWidget);
      expect(find.byIcon(Icons.view_week_outlined), findsOneWidget);
      expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);

      // Panel lateral (como el de Google Calendar): buscador, mini-calendario,
      // "Mis servicios" y próximos eventos.
      expect(find.text('Mis servicios'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Próximos eventos'), findsOneWidget);

      // Rejilla de semana: encabezados de día.
      expect(find.text('LUN'), findsOneWidget);

      // El evento del lunes está en la REJILLA de la semana actual (sin navegar).
      expect(_weekBlock(), findsOneWidget);

      // ‹ › navega la semana de verdad: el título cambia Y el bloque sale de la
      // rejilla; "Hoy" lo trae de vuelta.
      final titleFinder = find.byKey(const ValueKey('agenda-title'));
      final before = tester.widget<Text>(titleFinder).data!;
      await _tapPump(tester, find.byTooltip('Semana siguiente'));
      final after = tester.widget<Text>(titleFinder).data!;
      expect(after, isNot(before));
      expect(
        _weekBlock(),
        findsNothing,
        reason: 'La semana siguiente ya no contiene el lunes',
      );

      await _tapPump(tester, find.byKey(const ValueKey('agenda-today')));
      expect(tester.widget<Text>(titleFinder).data, before);
      expect(_weekBlock(), findsOneWidget);

      // Clic en el bloque -> modal ESTÁNDAR del panel (cerrar arriba a la
      // derecha, sin "Cerrar" abajo).
      await tester.ensureVisible(_weekBlock());
      await tester.pump(const Duration(milliseconds: 300));
      await _tapPump(tester, _weekBlock());
      expect(find.text('Detalle de la agenda'), findsOneWidget);
      expect(find.textContaining('Boda Premium'), findsWidgets);
      expect(find.textContaining('Cobertura en evento'), findsWidgets);
      expect(find.text('Lugar '), findsOneWidget);
      expect(find.text('Hacienda San José'), findsWidgets);
      // El mapa se dibuja dentro del modal (antes el diálogo reventaba al
      // pedir medidas intrínsecas a un FlutterMap).
      expect(find.byType(HsPlaceMapPreview), findsOneWidget);
      expect(tester.takeException(), isNull);

      final close = find.byTooltip('Cerrar');
      expect(close, findsOneWidget);
      final dialog = tester.getRect(find.byType(AlertDialog));
      final closeRect = tester.getRect(close);
      expect(
        closeRect.center.dx,
        greaterThan(dialog.center.dx),
        reason: 'El cierre va a la DERECHA del modal',
      );
      expect(
        closeRect.top,
        lessThan(dialog.center.dy),
        reason: 'El cierre va ARRIBA del modal',
      );
      expect(
        find.text('Cerrar'),
        findsNothing,
        reason: 'El cierre es el botón de la cabecera, no un texto abajo',
      );
      await _tapPump(tester, close);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Agendas: vista de mes con badges y detalle del día', (
    tester,
  ) async {
    await _pumpAgendas(tester, const Size(1200, 900));

    // Cambiar a vista de mes.
    await _tapPump(tester, find.byIcon(Icons.calendar_month_outlined));

    // Etiquetas de día de la semana de la cuadrícula mensual.
    expect(find.text('L'), findsWidgets);

    // Badge con el icono ESPECÍFICO del servicio ("Sesión de fotos" -> cámara).
    expect(find.byIcon(Icons.photo_camera_rounded), findsOneWidget);

    // Tocar el día 20 (celda del mes, la última que aparece en el árbol)
    // -> modal con el detalle del evento.
    await _tapPump(tester, find.text('20').last);
    expect(find.text('Detalle de la agenda'), findsOneWidget);
    expect(find.textContaining('Sesión de fotos'), findsWidgets);
    await _tapPump(tester, find.byTooltip('Cerrar'));

    expect(tester.takeException(), isNull);
  });

  // El ROJO del calendario es SOLO para los CLIENTES: el servidor les manda
  // los eventos de otros clientes sin detalle (`busy: true`) y esos días sí se
  // marcan en rojo. El personal del estudio ve el detalle completo y su
  // calendario NO se pinta de rojo (antes TODOS los días con eventos salían en
  // rojo y tapaban el color del servicio, que es lo que se veía bien).
  testWidgets(
    'Agendas: el día con eventos NO va en rojo; el hueco ocupado ajeno sí',
    (tester) async {
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      // Días que NUNCA son hoy (el de hoy va seleccionado y su número se pinta
      // en el color de selección).
      final eventDay = now.day == 15 ? 16 : 15;
      final busyDay = now.day == 17 ? 18 : 17;

      await _pumpAgendas(
        tester,
        const Size(1200, 900),
        agendas: [
          {
            'id': 1,
            'purchasedPackageId': 1,
            'userId': 2,
            'clientName': 'Cliente Test',
            'packageName': 'Boda Premium',
            'serviceId': 6,
            'serviceName': 'Sesión de fotos',
            'eventDate':
                '${now.year}-${two(now.month)}-${two(eventDay)}T10:00:00',
            'description': 'Evento con detalle',
          },
          {
            // Hueco ocupado de OTRO cliente: el servidor manda `busy: true` y
            // ningún dato del evento.
            'id': 2,
            'clientName': '',
            'packageName': '',
            'serviceId': null,
            'serviceName': '',
            'eventDate':
                '${now.year}-${two(now.month)}-${two(busyDay)}T09:00:00',
            'description': '',
            'busy': true,
          },
        ],
      );

      // Vista de mes.
      await _tapPump(tester, find.byIcon(Icons.calendar_month_outlined));

      final withDetail = tester.widget<Text>(find.text('$eventDay').last);
      expect(
        withDetail.style?.color,
        isNot(const Color(0xFFDC2626)),
        reason: 'un día con evento NO se marca en rojo para el estudio',
      );
      // Su badge sigue diciendo QUÉ hay agendado (icono del servicio).
      expect(find.byIcon(Icons.photo_camera_rounded), findsOneWidget);

      final occupied = tester.widget<Text>(find.text('$busyDay').last);
      expect(
        occupied.style?.color,
        const Color(0xFFDC2626),
        reason: 'un hueco ocupado sin detalle (vista del cliente) va en ROJO',
      );
      // Sin detalle no hay servicio: el badge es un candado.
      expect(find.byIcon(Icons.lock_outline_rounded), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Agendas (móvil): calendario a pantalla completa y panel en hoja',
    (tester) async {
      await _pumpAgendas(tester, const Size(390, 844));

      // Por defecto en móvil: vista de mes a pantalla completa; el panel vive
      // en una hoja inferior.
      expect(find.byKey(const ValueKey('agenda-calendar')), findsOneWidget);
      expect(find.text('Mis servicios'), findsNothing);

      // La franja DESTACADA de próximos eventos también se ve en móvil.
      expect(find.text('Próximos eventos'), findsOneWidget);

      // El calendario sigue ocupando la altura RESTANTE (la franja de próximos
      // eventos consume la parte superior, así que el umbral baja).
      final cal = tester.getRect(find.byKey(const ValueKey('agenda-calendar')));
      expect(cal.bottom, lessThanOrEqualTo(844));
      expect(
        cal.height,
        greaterThan(200),
        reason: 'El calendario ocupa la altura restante',
      );
      expect(tester.takeException(), isNull);

      // El alta de evento vive en la barra del calendario (ícono +): el héroe
      // no se estira y el calendario conserva su espacio.
      expect(find.byTooltip('Nuevo evento'), findsOneWidget);
      await _tapPump(tester, find.byTooltip('Nuevo evento'));
      expect(find.text('Crear evento'), findsOneWidget);
      await _tapPump(tester, find.text('Cancelar'));
      expect(find.text('Crear evento'), findsNothing);

      // Abrir la hoja de filtros (buscador + mini-calendario + servicios).
      await _tapPump(tester, find.byTooltip('Filtros y calendario'));
      expect(find.text('Mis servicios'), findsOneWidget);
      expect(find.text('Próximos eventos'), findsOneWidget);
      await tester.tapAt(const Offset(20, 30)); // toca el fondo y cierra
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Mis servicios'), findsNothing);

      // Vista de semana en móvil: sigue ocupando la altura restante y la
      // semana visible responde a la navegación (el evento del lunes está).
      await _tapPump(tester, find.byIcon(Icons.view_week_outlined));
      expect(find.text('LUN'), findsWidgets);

      final weekCal = tester.getRect(
        find.byKey(const ValueKey('agenda-calendar')),
      );
      expect(weekCal.bottom, lessThanOrEqualTo(844));
      expect(weekCal.height, greaterThan(200));
      expect(tester.takeException(), isNull);

      // ‹ › navega la semana de verdad también en móvil.
      final titleFinder = find.byKey(const ValueKey('agenda-title'));
      final before = tester.widget<Text>(titleFinder).data!;
      await _tapPump(tester, find.byTooltip('Semana siguiente'));
      expect(tester.widget<Text>(titleFinder).data, isNot(before));
      expect(_weekBlock(), findsNothing);
      await _tapPump(tester, find.byTooltip('Semana anterior'));
      expect(_weekBlock(), findsOneWidget);

      // Tocar el bloque del evento abre el modal estándar (cerrar arriba-derecha).
      await tester.ensureVisible(_weekBlock());
      await tester.pump(const Duration(milliseconds: 300));
      await _tapPump(tester, _weekBlock());
      expect(find.text('Detalle de la agenda'), findsOneWidget);
      final close = find.byTooltip('Cerrar');
      expect(close, findsOneWidget);
      // En móvil el modal es de PANTALLA COMPLETA: ya no hay cuadro flotante, la
      // superficie ocupa todo (390x844) y el cierre sigue arriba a la derecha.
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'el detalle en móvil no es un diálogo flotante',
      );
      expect(
        tester.getRect(find.byType(FormDialog)).size,
        const Size(390, 844),
      );
      expect(tester.getRect(close).center.dx, greaterThan(390 / 2));
      expect(tester.getRect(close).top, lessThan(844 / 2));
    },
  );

  testWidgets(
    'nuevo evento: se elige el cliente, su paquete y el servicio del paquete',
    (tester) async {
      final posts = <Map<String, dynamic>>[];
      await _pumpAgendas(tester, const Size(1200, 900), posts: posts);

      await _tapPump(tester, find.text('Nuevo evento'));
      expect(
        find.text('Elige el cliente, su paquete y el servicio a agendar'),
        findsOneWidget,
      );

      // 1) CLIENTE: sin él no hay paquetes que elegir.
      expect(find.text('Elige el paquete'), findsNothing);
      await _tapPump(tester, find.byKey(const ValueKey('agenda-client')));
      await _tapPump(tester, find.text('Ana Ruiz').last);

      // 2) PAQUETE del cliente (se cargan los suyos).
      await _tapPump(tester, find.byKey(const ValueKey('agenda-package')));
      await _tapPump(tester, find.text('Paquete Aniversario').last);

      // 3) SERVICIO del paquete.
      await _tapPump(tester, find.byKey(const ValueKey('agenda-service')));
      await _tapPump(tester, find.text('Cobertura de estudio').last);

      await tester.enterText(
        find.widgetWithText(TextField, 'Descripción'),
        'Prueba de evento',
      );
      await _tapPump(tester, find.text('Crear evento'));

      expect(posts, hasLength(1));
      expect(posts.first['purchasedPackageId'], 10);
      expect(posts.first['serviceId'], 5);
      expect(posts.first['description'], 'Prueba de evento');
      expect(
        posts.first['eventDate'],
        matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:00$')),
      );
    },
  );

  testWidgets('nuevo evento: las ubicaciones se numeran 1, 2, 3 solas', (
    tester,
  ) async {
    final posts = <Map<String, dynamic>>[];
    await _pumpAgendas(tester, const Size(1200, 900), posts: posts);

    await _tapPump(tester, find.text('Nuevo evento'));

    final add = find.byKey(const ValueKey('agenda-place-add'));
    await tester.ensureVisible(find.text('UBICACIONES (OPCIONAL)'));
    await tester.pump();
    // Arranca con UN hueco, numerado 1.
    expect(find.byKey(const ValueKey('agenda-place-0')), findsOneWidget);
    expect(_placeNumber(tester, 0), '1');

    await tester.ensureVisible(add);
    await _tapPump(tester, add);
    expect(find.byKey(const ValueKey('agenda-place-1')), findsOneWidget);
    expect(_placeNumber(tester, 0), '1');
    expect(_placeNumber(tester, 1), '2');
    expect(find.text('Agregar ubicación 3'), findsOneWidget);

    await _tapPump(tester, add);
    expect(_placeNumber(tester, 2), '3');

    // Quitar la primera renumera el resto: la que era 2 pasa a ser 1.
    final removeFirst = find.byTooltip('Quitar ubicación 1');
    await tester.ensureVisible(removeFirst);
    await tester.pump();
    await _tapPump(tester, removeFirst);
    expect(find.byKey(const ValueKey('agenda-place-2')), findsNothing);
    expect(_placeNumber(tester, 0), '1');
    expect(_placeNumber(tester, 1), '2');

    // Al crear sin elegir lugares viaja la lista vacía (el servidor no
    // inventa ubicaciones).
    await _tapPump(tester, find.byKey(const ValueKey('agenda-client')));
    await _tapPump(tester, find.text('Ana Ruiz').last);
    await _tapPump(tester, find.byKey(const ValueKey('agenda-package')));
    await _tapPump(tester, find.text('Paquete Aniversario').last);
    await _tapPump(tester, find.text('Crear evento'));

    expect(posts, hasLength(1));
    expect(posts.first['locations'], isEmpty);
    expect(posts.first.containsKey('location'), isFalse);
  });

  testWidgets('detalle: varias ubicaciones se muestran numeradas', (
    tester,
  ) async {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final day = '${monday.year}-${two(monday.month)}-${two(monday.day)}';

    await _pumpAgendas(
      tester,
      const Size(1200, 900),
      agendas: [
        {
          'id': 1,
          'purchasedPackageId': 1,
          'userId': 2,
          'clientName': 'Cliente Test',
          'packageName': 'Boda Premium',
          'serviceId': 5,
          'serviceName': 'Cobertura en evento',
          'eventDate': '${day}T14:30:00',
          'description': 'Ceremonia en el jardín',
          // El servidor manda la lista numerada y, por compatibilidad, la
          // primera también en los campos sueltos.
          'location': 'Hacienda San José',
          'lat': 4.711,
          'lng': -74.0721,
          'locations': [
            {
              'position': 1,
              'location': 'Hacienda San José',
              'lat': 4.711,
              'lng': -74.0721,
            },
            {'position': 2, 'location': 'Salón Real', 'lat': null, 'lng': null},
          ],
        },
      ],
    );

    await tester.ensureVisible(_weekBlock());
    await tester.pump(const Duration(milliseconds: 300));
    await _tapPump(tester, _weekBlock());

    expect(find.text('Detalle de la agenda'), findsOneWidget);
    expect(find.text('Lugar 1 '), findsOneWidget);
    expect(find.text('Lugar 2 '), findsOneWidget);
    expect(find.text('Hacienda San José'), findsWidgets);
    expect(find.text('Salón Real'), findsOneWidget);
    // Un solo mapa (el de la primera ubicación con coordenadas).
    expect(find.byType(HsPlaceMapPreview), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'widget nativo (Android/Windows): tocar un evento abre SU detalle',
    (tester) async {
      await _pumpAgendas(tester, const Size(1200, 900));

      // El widget no navega: AVISA qué se tocó y la app decide. id 2 = la agenda
      // de "Otra Clienta" ("Sesión de fotos").
      UpcomingEventsWidget.requested.value = const WidgetTap(agendaId: 2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Detalle de la agenda'), findsOneWidget);
      expect(find.textContaining('Otra Clienta'), findsWidgets);
      expect(find.textContaining('Sesión de fotos'), findsWidgets);
      // La petición queda CONSUMIDA: no se vuelve a abrir sola.
      expect(UpcomingEventsWidget.requested.value, isNull);

      await _tapPump(tester, find.byTooltip('Cerrar'));
      expect(find.text('Detalle de la agenda'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('widget nativo: el botón "Agregar agenda" abre el ALTA', (
    tester,
  ) async {
    await _pumpAgendas(tester, const Size(1200, 900));

    UpcomingEventsWidget.requested.value = const WidgetTap(create: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Crear evento'), findsOneWidget);
    expect(
      find.text('Elige el cliente, su paquete y el servicio a agendar'),
      findsOneWidget,
    );
    expect(UpcomingEventsWidget.requested.value, isNull);

    await _tapPump(tester, find.text('Cancelar'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'widget nativo: una agenda que ya no existe avisa y no rompe nada',
    (tester) async {
      await _pumpAgendas(tester, const Size(1200, 900));

      UpcomingEventsWidget.requested.value = const WidgetTap(agendaId: 999);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Detalle de la agenda'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cliente: sus eventos con detalle y los de OTROS solo como "Ocupado"',
    (tester) async {
      // Lo que el servidor manda a un CLIENTE: su evento completo y el de otro
      // cliente enmascarado (`busy: true`, sin nombres ni servicio).
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
      final day = '${monday.year}-${two(monday.month)}-${two(monday.day)}';

      await _pumpAgendas(
        tester,
        const Size(1200, 900),
        agendas: [
          {
            'id': 1,
            'purchasedPackageId': 10,
            'userId': 2,
            'clientName': 'Ana Ruiz',
            'packageName': 'Boda Premium',
            'serviceId': 5,
            'serviceName': 'Cobertura en evento',
            'eventDate': '${day}T14:30:00',
            'description': 'Ceremonia en el jardín',
            'busy': false,
          },
          {
            'id': 2,
            'purchasedPackageId': null,
            'userId': null,
            'clientName': '',
            'packageName': '',
            'serviceId': null,
            'serviceName': '',
            'eventDate': '${day}T17:00:00',
            'description': '',
            'location': '',
            'lat': null,
            'lng': null,
            'busy': true,
          },
        ],
      );

      final calendar = find.byKey(const ValueKey('agenda-calendar'));
      final busyBlock = find.descendant(
        of: calendar,
        matching: find.text('Ocupado'),
      );
      // Su evento se ve con su nombre; el ajeno, solo como hueco ocupado.
      expect(
        find.descendant(of: calendar, matching: find.text('Ana Ruiz')),
        findsOneWidget,
      );
      expect(busyBlock, findsOneWidget);

      // El hueco ocupado abre un detalle que SOLO dice que está ocupado.
      await tester.ensureVisible(busyBlock);
      await tester.pump(const Duration(milliseconds: 300));
      await _tapPump(tester, busyBlock);

      final dialog = find.byType(FormDialog);
      expect(find.text('Detalle de la agenda'), findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('Ocupado')),
        findsOneWidget,
      );
      expect(find.text('Horario reservado con otro cliente'), findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('Paquete ')),
        findsNothing,
        reason: 'El paquete de otro cliente no se muestra',
      );
      expect(
        find.descendant(of: dialog, matching: find.text('Servicio ')),
        findsNothing,
      );
      expect(find.textContaining('Boda Premium'), findsNothing);
      await _tapPump(tester, find.byTooltip('Cerrar'));

      // Su PROPIO evento sigue abriendo con todos los detalles.
      final ownBlock = find.descendant(
        of: calendar,
        matching: find.text('Ana Ruiz'),
      );
      await tester.ensureVisible(ownBlock);
      await tester.pump(const Duration(milliseconds: 300));
      await _tapPump(tester, ownBlock);

      expect(find.textContaining('Boda Premium'), findsWidgets);
      expect(find.textContaining('Cobertura en evento'), findsWidgets);
      expect(find.text('Ceremonia en el jardín'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

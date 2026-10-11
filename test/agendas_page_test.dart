import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/agendas_page.dart';

/// Instala un cliente HTTP falso con TRES agendas:
/// - el LUNES de la semana actual a las 14:30, "Cliente Test"
///   (siempre visible en la semana por defecto, sin depender de la fecha).
/// - día 20 a las 16:00, servicio "Sesión de fotos" (icono de cámara).
/// - día 22 SIN hora (medianoche) -> fila de "todo el día" de la semana.
void _installMockClient() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  String dayOf(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
  final monday =
      DateTime(now.year, now.month, now.day - (now.weekday - 1));

  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    if (request.url.path.endsWith('/api/admin/agendas')) {
      return http.Response(
        jsonEncode({
          'agendas': [
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
          ]
        }),
        200,
        headers: headers,
      );
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

Future<void> _pumpAgendas(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final previous = HsApi.client;
  _installMockClient();
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

void main() {
  testWidgets(
      'Agendas (escritorio): semana estilo Google Calendar con panel lateral',
      (tester) async {
    await _pumpAgendas(tester, const Size(1200, 900));

    // Barra superior: Hoy + flechas + conmutador Semana/Mes.
    expect(find.text('Hoy'), findsOneWidget);
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
    expect(_weekBlock(), findsNothing,
        reason: 'La semana siguiente ya no contiene el lunes');

    await _tapPump(tester, find.text('Hoy'));
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

    final close = find.byTooltip('Cerrar');
    expect(close, findsOneWidget);
    final dialog = tester.getRect(find.byType(AlertDialog));
    final closeRect = tester.getRect(close);
    expect(closeRect.center.dx, greaterThan(dialog.center.dx),
        reason: 'El cierre va a la DERECHA del modal');
    expect(closeRect.top, lessThan(dialog.center.dy),
        reason: 'El cierre va ARRIBA del modal');
    expect(find.text('Cerrar'), findsNothing,
        reason: 'El cierre es el botón de la cabecera, no un texto abajo');
    await _tapPump(tester, close);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Agendas: vista de mes con badges y detalle del día',
      (tester) async {
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

  testWidgets(
      'Agendas (móvil): calendario a pantalla completa y panel en hoja',
      (tester) async {
    await _pumpAgendas(tester, const Size(390, 844));

    // Por defecto en móvil: vista de mes a pantalla completa; el panel vive
    // en una hoja inferior.
    expect(find.byKey(const ValueKey('agenda-calendar')), findsOneWidget);
    expect(find.text('Mis servicios'), findsNothing);

    final cal = tester.getRect(find.byKey(const ValueKey('agenda-calendar')));
    expect(cal.bottom, lessThanOrEqualTo(844));
    expect(cal.height, greaterThan(300),
        reason: 'El calendario ocupa la altura visible');
    expect(tester.takeException(), isNull);

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

    final weekCal = tester.getRect(find.byKey(const ValueKey('agenda-calendar')));
    expect(weekCal.bottom, lessThanOrEqualTo(844));
    expect(weekCal.height, greaterThan(300));
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
    final dialog = tester.getRect(find.byType(AlertDialog));
    expect(tester.getRect(close).center.dx, greaterThan(dialog.center.dx));
    expect(tester.getRect(close).top, lessThan(dialog.center.dy));
  });
}

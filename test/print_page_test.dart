import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_access.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/print_page.dart';

Map<String, dynamic> _request({
  int id = 1,
  String service = 'Sesión Previa',
  String client = 'Reyna Coot',
  String status = 'sent',
  String? formatName,
  int border = 0,
  Map<String, dynamic> crops = const {},
}) => {
  'id': id,
  'serviceId': 18,
  'serviceName': service,
  'packageName': 'XV Años - Premium',
  'clientName': client,
  'status': status,
  'formatId': formatName == null ? null : 2,
  'formatName': formatName ?? '',
  'border': border,
  'sentAt': '2026-10-19T10:00:00',
  'photos': ['XV/Reyna/foto1.jpg', 'XV/Reyna/foto2.jpg'],
  'crops': crops,
};

void main() {
  late http.Client previous;

  setUp(() {
    previous = HsApi.client;
    HsAccess.seedForTest(
      modules: const {
        'Impresiones': {'read', 'create', 'update', 'delete', 'download'},
      },
    );
  });

  tearDown(() {
    HsApi.client = previous;
    HsAccess.reset();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PrintPage())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lista los envíos con servicio, cliente y número de fotos', (
    tester,
  ) async {
    HsApi.client = MockClient((request) async {
      if (request.url.path.endsWith('/api/admin/print-requests')) {
        return http.Response(
          jsonEncode({
            'requests': [_request()],
            'formats': [
              {'id': 1, 'name': '5x7', 'width': 5, 'height': 7, 'unit': 'in'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 200);
    });

    await pump(tester);

    expect(find.text('Sesión Previa'), findsOneWidget);
    expect(find.textContaining('Reyna Coot'), findsOneWidget);
    expect(find.textContaining('2 fotos'), findsWidgets);
    expect(find.text('Enviado'), findsOneWidget);
    expect(find.text('Seleccionar todo'), findsOneWidget);
  });

  testWidgets('seleccionar todo marca las fotos y habilita los formatos', (
    tester,
  ) async {
    HsApi.client = MockClient((request) async {
      if (request.url.path.contains('/api/admin/print-requests')) {
        return http.Response(
          jsonEncode({
            'requests': [_request()],
            'formats': const [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 200);
    });

    await pump(tester);
    expect(find.text('Abrir formatos'), findsOneWidget);

    await tester.tap(find.text('Seleccionar todo'));
    await tester.pumpAndSettle();

    expect(find.text('Abrir formatos (2)'), findsOneWidget);
    // "Quitar selección" dice cuántas fotos va a soltar: no es lo mismo que
    // "Seleccionar todo", que ahora queda deshabilitado cuando ya está todo.
    expect(find.text('Quitar selección (2)'), findsOneWidget);
    final selectAll = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Seleccionar todo'),
    );
    expect(selectAll.onPressed, isNull);
  });

  testWidgets('un envío terminado muestra su formato y Reabrir', (
    tester,
  ) async {
    HsApi.client = MockClient((request) async {
      if (request.url.path.contains('/api/admin/print-requests')) {
        return http.Response(
          jsonEncode({
            'requests': [
              _request(status: 'finished', formatName: '5x7', border: 10),
            ],
            'formats': const [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 200);
    });

    await pump(tester);

    expect(find.text('Terminado'), findsOneWidget);
    expect(find.text('5x7 · 10 %'), findsOneWidget);

    await tester.tap(find.text('Sesión Previa'));
    await tester.pumpAndSettle();
    expect(find.text('Reabrir selección'), findsOneWidget);
    expect(find.text('Formatos'), findsOneWidget);
  });

  testWidgets(
    'abrir formatos muestra el recorte, el borde y permite crear uno',
    (tester) async {
      HsApi.client = MockClient((request) async {
        if (request.url.path.endsWith('/api/admin/print-formats') &&
            request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'format': {
                'id': 9,
                'name': body['name'],
                'width': body['width'],
                'height': body['height'],
                'unit': body['unit'],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.contains('/api/admin/print-requests')) {
          return http.Response(
            jsonEncode({
              'requests': [_request()],
              'formats': [
                {'id': 2, 'name': '5x7', 'width': 5, 'height': 7, 'unit': 'in'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(jsonEncode({'ok': true}), 200);
      });

      await pump(tester);
      await tester.tap(find.text('Seleccionar todo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir formatos (2)'));
      await tester.pumpAndSettle();

      expect(find.text('Formatos de impresión'), findsOneWidget);
      expect(find.text('Grosor de borde'), findsOneWidget);
      expect(find.text('Listo · Descargar'), findsOneWidget);
      expect(find.text('Terminar'), findsOneWidget);

      // Se agrega un formato nuevo desde el propio módulo.
      await tester.tap(find.text('Agregar formato'));
      await tester.pumpAndSettle();
      expect(find.text('Nuevo formato de impresión'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('print-format-width')),
        '1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('print-format-height')),
        '1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('print-format-name')),
        '1x1',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Agregar'));
      await tester.pumpAndSettle();

      expect(find.text('1x1'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Guardar conserva formato, borde y posiciones sin cerrar el envío',
    (tester) async {
      Map<String, dynamic>? saved;
      final crops = {
        'XV/Reyna/foto1.jpg': {
          'x': 0.2,
          'y': 0.3,
          'zoom': 2.0,
          'landscape': true,
        },
      };
      HsApi.client = MockClient((request) async {
        if (request.url.path.endsWith('/api/admin/print-requests') &&
            request.method == 'POST') {
          saved = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'done': true}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.contains('/api/admin/print-requests')) {
          return http.Response(
            jsonEncode({
              'requests': [
                _request(formatName: '5x7', border: 10, crops: crops),
              ],
              'formats': [
                {'id': 2, 'name': '5x7', 'width': 5, 'height': 7, 'unit': 'in'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(jsonEncode({'ok': true}), 200);
      });

      await pump(tester);
      await tester.tap(find.text('Seleccionar todo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir formatos (2)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!['action'], 'save');
      expect(saved!['requestId'], 1);
      expect(saved!['formatId'], 2);
      expect(saved!['border'], 10);
      // Las posiciones guardadas se restauraron al abrir y se vuelven a
      // enviar tal cual (mismo encuadre para cada foto).
      final sent = saved!['crops'] as Map;
      expect(sent['XV/Reyna/foto1.jpg']['x'], 0.2);
      expect(sent['XV/Reyna/foto1.jpg']['y'], 0.3);
      expect(sent['XV/Reyna/foto1.jpg']['zoom'], 2.0);
      expect(sent['XV/Reyna/foto1.jpg']['landscape'], isTrue);

      // Guardar NO cierra el módulo: se puede seguir ajustando o descargar.
      expect(find.text('Formatos de impresión'), findsOneWidget);
      // Y un clic fuera del modal lo cierra (regla del panel).
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.text('Formatos de impresión'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('en el celular el módulo no desborda', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    HsApi.client = MockClient((request) async {
      if (request.url.path.contains('/api/admin/print-requests')) {
        return http.Response(
          jsonEncode({
            'requests': [_request()],
            'formats': const [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 200);
    });

    await pump(tester);
    expect(find.text('Sesión Previa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin envíos explica cómo llegar aquí', (tester) async {
    HsApi.client = MockClient(
      (request) async => http.Response(
        jsonEncode({'requests': const [], 'formats': const []}),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );

    await pump(tester);
    expect(find.text('Todavía no hay envíos a impresión'), findsOneWidget);
  });

  testWidgets('pagina los envíos de 30 en 30', (tester) async {
    HsApi.client = MockClient((request) async {
      if (request.url.path.contains('/api/admin/print-requests')) {
        return http.Response(
          jsonEncode({
            'requests': [
              for (var i = 1; i <= 35; i++)
                _request(id: i, service: 'Servicio $i', client: 'Cliente $i'),
            ],
            'formats': const [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 200);
    });

    await pump(tester);

    // Solo la primera página; el pie dice cuántos hay en total.
    expect(find.text('Servicio 30'), findsOneWidget);
    expect(find.text('Servicio 31'), findsNothing);
    expect(find.text('1–30 de 35'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('hs-pager-next')));
    await tester.pumpAndSettle();

    expect(find.text('Servicio 1'), findsNothing);
    expect(find.text('Servicio 31'), findsOneWidget);
    expect(find.text('Servicio 35'), findsOneWidget);
    expect(find.text('31–35 de 35'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

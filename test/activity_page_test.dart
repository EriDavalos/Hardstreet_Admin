import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/activity_page.dart';

/// Bitácora falsa: una creación y una eliminación.
void _installMock() {
  final previous = HsApi.client;
  addTearDown(() => HsApi.client = previous);
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    if (request.url.path.endsWith('/api/admin/activity')) {
      return http.Response(
        jsonEncode({
          'code': 200,
          'ok': true,
          'message': 'Bitácora cargada',
          'entries': [
            {
              'id': 2,
              'userId': 1,
              'userName': 'Hardstreet Inc',
              'roleName': 'Admin',
              'module': 'clientes',
              'moduleName': 'Clientes',
              'action': 'create',
              'entity': 'cliente',
              'entityId': 9,
              'description': 'Cliente creado exitosamente',
              'details': {'name': 'Ana', 'email': 'ana@hardstreet.com'},
              'ip': '127.0.0.1',
              'created': '2026-10-16T10:30:00',
            },
            {
              'id': 1,
              'userId': 1,
              'userName': 'Hardstreet Inc',
              'roleName': 'Admin',
              'module': 'rols',
              'moduleName': 'Roles',
              'action': 'delete',
              'entity': 'rol',
              'entityId': 3,
              'description': 'Rol eliminado exitosamente',
              'details': null,
              'ip': '',
              'created': '2026-10-15T09:00:00',
            },
          ],
          'total': 2,
          'limit': 100,
          'offset': 0,
        }),
        200,
        headers: headers,
      );
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

Future<void> _pumpPage(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: ActivityPage())),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('muestra quién creó o eliminó qué, con su módulo y acción', (
    tester,
  ) async {
    _installMock();
    await _pumpPage(tester);

    // Descripción que devolvió el backend (el mismo texto del aviso).
    expect(find.text('Cliente creado exitosamente'), findsOneWidget);
    expect(find.text('Rol eliminado exitosamente'), findsOneWidget);

    // Quién lo hizo y con qué rol.
    expect(find.text('Hardstreet Inc'), findsWidgets);
    expect(find.text('Admin'), findsWidgets);

    // Módulo + registro afectado, y la etiqueta de la acción.
    expect(find.textContaining('Clientes'), findsWidgets);
    expect(find.textContaining('cliente #9'), findsWidgets);
    expect(find.textContaining('rol #3'), findsWidgets);
    expect(find.text('Creación'), findsWidgets);
    expect(find.text('Eliminación'), findsWidgets);

    expect(tester.takeException(), isNull);
  });

  testWidgets('el detalle (details) se ve al expandir la fila', (tester) async {
    _installMock();
    await _pumpPage(tester);

    // El detalle no está visible hasta abrir la fila.
    expect(find.textContaining('name: Ana'), findsNothing);

    await tester.tap(find.text('Cliente creado exitosamente'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('name: Ana'), findsOneWidget);
    expect(find.textContaining('email: ana@hardstreet.com'), findsOneWidget);
  });

  testWidgets('la flecha de detalle tiene aire: no va pegada a la hora', (
    tester,
  ) async {
    _installMock();
    await _pumpPage(tester);

    // Solo la fila CON detalle dibuja la flecha.
    final arrow = find.byIcon(Icons.expand_more_rounded);
    expect(arrow, findsOneWidget);

    final time = tester.getRect(find.text('10:30'));
    final box = tester.getRect(arrow);
    // Va DEBAJO de la hora, con aire vertical entre las dos.
    expect(
      box.top - time.bottom,
      greaterThanOrEqualTo(6),
      reason: 'la flecha tiene aire respecto a la hora (antes pegaba)',
    );

    // Y tampoco pegada al borde derecho de la tarjeta.
    final card = tester.getRect(find.byType(Card).first);
    expect(
      card.right - box.right,
      greaterThanOrEqualTo(10),
      reason: 'queda margen contra el borde de la tarjeta',
    );
  });

  testWidgets('el filtro por acción pide solo las eliminaciones', (
    tester,
  ) async {
    final urls = <String>[];
    HsApi.client = MockClient((request) async {
      urls.add(request.url.toString());
      return http.Response(
        jsonEncode({'code': 200, 'ok': true, 'entries': <dynamic>[]}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    await _pumpPage(tester);

    // El filtro vive en el MÓDULO DE FILTROS que abre el botón de la barra.
    await tester.tap(find.byKey(const ValueKey('hs-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminaciones'));
    await tester.pump();
    await tester.tap(find.textContaining('Aplicar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      urls.any((u) => u.contains('action=delete')),
      isTrue,
      reason: 'el filtro viaja al backend',
    );
  });
}

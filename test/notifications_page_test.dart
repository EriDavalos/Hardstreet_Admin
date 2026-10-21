import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_access.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/notifications_page.dart';

/// Eventos del módulo tal como los manda /api/admin/notifications.
List<Map<String, dynamic>> _events() => [
  {
    'key': 'agenda-proxima',
    'title': 'Avisar a fechas próximas a agenda',
    'description': 'Falta una semana y falta un día de cada evento.',
    'target': 'schedules',
    'automatic': true,
    'configured': false,
    'enabled': true,
    'roleIds': [2, 3],
    'roles': ['Cliente', 'Colaborador'],
    'defaultRoles': ['Cliente', 'Colaborador'],
  },
  {
    'key': 'fotos-disponibles',
    'title': 'Avisar cuando se puedan seleccionar las fotos',
    'description': 'Cuando el estudio abre la selección de fotos.',
    'target': 'my_package',
    'automatic': true,
    'configured': true,
    'enabled': true,
    'roleIds': [2],
    'roles': ['Cliente'],
    'defaultRoles': ['Cliente'],
  },
  {
    'key': 'fotos-enviadas',
    'title': 'Avisar el envío de fotos seleccionadas',
    'description': 'Cuando el cliente envía sus fotos a impresión.',
    'target': 'print',
    'automatic': true,
    'configured': false,
    'enabled': true,
    'roleIds': [3],
    'roles': ['Colaborador'],
    'defaultRoles': ['Colaborador'],
  },
  {
    'key': 'aviso-manual',
    'title': 'Avisos manuales del estudio',
    'description': 'Los avisos que escribes a mano.',
    'target': 'notifications',
    'automatic': false,
    'configured': false,
    'enabled': true,
    'roleIds': [],
    'roles': [],
    'defaultRoles': [],
  },
];

void _installMock(List<Map<String, dynamic>> posts) {
  final previous = HsApi.client;
  addTearDown(() => HsApi.client = previous);
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;

    if (path.endsWith('/api/admin/notifications')) {
      if (request.method == 'POST') {
        posts.add((jsonDecode(request.body) as Map).cast<String, dynamic>());
        return http.Response(
          jsonEncode({'ok': true, 'message': 'Aviso actualizado'}),
          200,
          headers: headers,
        );
      }
      return http.Response(
        jsonEncode({
          'ok': true,
          'events': _events(),
          'roles': [
            {'id': 1, 'name': 'Admin'},
            {'id': 2, 'name': 'Cliente'},
            {'id': 3, 'name': 'Colaborador'},
          ],
          'history': [
            {
              'id': 9,
              'kind': 'print',
              'title': 'Nuevo envío a impresión · Cobertura',
              'body': 'Ana envió 4 fotos a impresión',
              'target': 'print',
              'isRead': false,
              'created': '2026-10-20T10:00:00',
              'userName': 'Ana Ruiz',
              'roleName': 'Cliente',
            },
          ],
        }),
        200,
        headers: headers,
      );
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

Future<void> _pumpPage(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1250, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1250, 1000);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: NotificationsPage())),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    // Modo degradado: las acciones del módulo quedan disponibles (como un
    // panel que aún no cargó permisos).
    HsAccess.seedForTest(admin: true, degraded: true);
  });

  testWidgets('muestra los eventos con los roles que los reciben', (
    tester,
  ) async {
    _installMock(<Map<String, dynamic>>[]);
    await _pumpPage(tester);

    expect(find.text('Avisar a fechas próximas a agenda'), findsOneWidget);
    expect(
      find.text('Avisar cuando se puedan seleccionar las fotos'),
      findsOneWidget,
    );
    expect(find.text('Avisar el envío de fotos seleccionadas'), findsOneWidget);
    expect(find.text('Avisos manuales del estudio'), findsOneWidget);

    // Roles configurados (Cliente y Colaborador) y a qué módulo llevan.
    expect(find.text('Cliente'), findsWidgets);
    expect(find.text('Colaborador'), findsWidgets);
    expect(find.text('Abre Agendas'), findsOneWidget);
    expect(find.text('Abre Impresiones'), findsOneWidget);

    // Historial de lo ya enviado.
    expect(find.text('Nuevo envío a impresión · Cobertura'), findsOneWidget);
  });

  testWidgets('elegir roles guarda la regla del evento', (tester) async {
    final posts = <Map<String, dynamic>>[];
    _installMock(posts);
    await _pumpPage(tester);

    await tester.tap(find.byKey(const ValueKey('notif-roles-agenda-proxima')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('¿Quién recibe «Avisar a fechas próximas a agenda»?'),
        findsOneWidget);

    // Agregar Admin a Cliente + Colaborador.
    await tester.tap(
      find.byKey(const ValueKey('notif-role-agenda-proxima-1')),
    );
    await tester.pump();
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(posts, isNotEmpty);
    final saved = posts.last;
    expect(saved['action'], 'save-rule');
    expect(saved['eventKey'], 'agenda-proxima');
    expect((saved['roleIds'] as List).toSet(), {1, 2, 3});
    expect(saved['enabled'], true);
  });

  testWidgets('el interruptor apaga el evento sin perder sus roles', (
    tester,
  ) async {
    final posts = <Map<String, dynamic>>[];
    _installMock(posts);
    await _pumpPage(tester);

    await tester.tap(
      find.byKey(const ValueKey('notif-switch-fotos-disponibles')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final saved = posts.last;
    expect(saved['action'], 'save-rule');
    expect(saved['eventKey'], 'fotos-disponibles');
    expect(saved['enabled'], false);
    expect((saved['roleIds'] as List), [2]);
  });

  testWidgets('enviar un aviso manual a un rol manda título y módulo', (
    tester,
  ) async {
    final posts = <Map<String, dynamic>>[];
    _installMock(posts);
    await _pumpPage(tester);

    await tester.tap(find.text('Enviar aviso'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
      find.byKey(const ValueKey('notif-send-title')),
      'Entrega de fotos el viernes',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, 'Colaborador'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('notif-send-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final sent = posts.last;
    expect(sent['action'], 'send');
    expect(sent['title'], 'Entrega de fotos el viernes');
    expect((sent['roleIds'] as List), [3]);
    expect(sent['target'], 'notifications');
  });
}

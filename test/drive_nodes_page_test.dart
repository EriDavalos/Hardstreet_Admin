import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/drive_api_service.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/connection_page.dart';

// ==================================================================
// SERVIDORES DEL DRIVE EN EL PANEL (Drive federado) — módulo Conexión
// ==================================================================
// La pantalla enseña los servidores como una TABLA (la de `drive_nodes`) con
// una columna por dato: servidor, estado, versión, prioridad, bibliotecas,
// espacio, ping, depende de y acciones. Aquí se comprueba:
//
//   · que se pintan los datos que da el hub (estado real, espacio, ping…);
//   · que una DEPENDENCIA rota deja el servidor en mantenimiento y se dice;
//   · que la terminal pide el log al hub y lo enseña;
//   · que reiniciar pide confirmación y llama al hub (nunca al servidor);
//   · que en el celular se ve como tarjetas, sin desbordes.
// ==================================================================

/// Nodos falsos con el estado que daría el hub.
void _installMocks(
  List<Map<String, dynamic>> nodes, {
  Map<String, dynamic>? health,
  int healthStatus = 200,
  Future<({int statusCode, String body})> Function(
    String url,
    Duration timeout,
  )?
  healthFor,
  List<Map<String, dynamic>>? hubNodes,
  List<http.Request>? adminCalls,
  String logText = '2026-10-25T10:00:00 drive: ✔ HardStreet Drive API en 4000',
  int adminStatus = 200,
}) {
  final previousCrud = HsApi.client;
  final previousDrive = DriveApiService.client;
  final previousHealth = ConnectionPage.healthGet;
  final previousNodes = ConnectionPage.hubNodesGet;
  final previousAdmin = ConnectionPage.adminClient;
  addTearDown(() {
    HsApi.client = previousCrud;
    DriveApiService.client = previousDrive;
    ConnectionPage.healthGet = previousHealth;
    ConnectionPage.hubNodesGet = previousNodes;
    ConnectionPage.adminClient = previousAdmin;
  });

  ConnectionPage.hubNodesGet = (url, timeout) async =>
      (statusCode: 200, body: jsonEncode({'nodes': hubNodes ?? const []}));

  ConnectionPage.healthGet = (url, timeout) async {
    if (healthFor != null) return healthFor(url, timeout);
    return (
      statusCode: healthStatus,
      body: jsonEncode(health ?? const <String, dynamic>{}),
    );
  };

  // Acciones de administración: log, reinicio y subida al proyecto.
  ConnectionPage.adminClient = MockClient((request) async {
    adminCalls?.add(request);
    if (request.url.path.endsWith('/logs')) {
      return http.Response(
        jsonEncode({
          'ok': true,
          'service': 'hardstreet-drive',
          'text': logText,
        }),
        adminStatus,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.url.path.endsWith('/restart')) {
      return http.Response(
        jsonEncode({
          'ok': true,
          'message': 'Reiniciando hardstreet-drive… el servidor vuelve en unos segundos.',
        }),
        adminStatus,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(
      jsonEncode({'ok': true, 'saved': 1, 'names': ['server.js']}),
      adminStatus,
      headers: {'content-type': 'application/json'},
    );
  });

  HsApi.client = MockClient((request) async {
    if (request.url.path.endsWith('/api/admin/drive-nodes')) {
      return http.Response(
        jsonEncode({
          'code': 200,
          'ok': true,
          'message': 'Servidores del Drive',
          'nodes': nodes,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(
      '{}',
      200,
      headers: {'content-type': 'application/json'},
    );
  });

  DriveApiService.client = MockClient(
    (_) async =>
        http.Response('{}', 200, headers: {'content-type': 'application/json'}),
  );
}

Widget _page({String? base}) => MaterialApp(
  home: Scaffold(
    body: ConnectionPage(driveApi: DriveApiService(baseUrl: base)),
  ),
);

/// Alto de sobra: la página es un ListView y la tabla vive abajo.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 4200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Map<String, dynamic> _node({
  required int id,
  required String name,
  String url = 'http://192.168.1.72:4000',
  int enabled = 1,
  int priority = 10,
  String? notes,
  List<int> dependsOn = const [],
}) => {
  'id': id,
  'name': name,
  'url': url,
  'enabled': enabled,
  'priority': priority,
  'notes': notes,
  'dependsOn': dependsOn,
};

Future<void> _open(WidgetTester tester, {String? base}) async {
  await tester.pumpWidget(_page(base: base));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
}

void main() {
  testWidgets('la tabla enseña versión, prioridad, bibliotecas, espacio y ping', (
    tester,
  ) async {
    _installMocks(
      [_node(id: 1, name: 'Servidor 1', notes: 'Bodega')],
      health: {
        'service': 'hardstreet-drive-hub',
        'version': '1.0.0',
        'nodesSource': 'backend',
        'nodes': [
          {
            'id': 1,
            'name': 'Servidor 1',
            'enabled': true,
            'online': true,
            'version': '1.0.0',
            'latencyMs': 34,
            'libs': {'sharp': true, 'ffmpeg': true},
            'dependsOn': const <int>[],
          },
        ],
      },
      hubNodes: [
        {
          'id': 1,
          'name': 'Servidor 1',
          'url': 'http://192.168.1.72:4000',
          'priority': 10,
          'notes': 'Bodega',
          'online': true,
          'version': '1.0.0',
          'latencyMs': 34,
          'freeBytes': 120 * 1024 * 1024 * 1024,
          'totalBytes': 240 * 1024 * 1024 * 1024,
          'dependsOn': const <int>[],
        },
      ],
    );

    _tall(tester);
    await _open(tester);

    // Cabecera de la tabla (como un esquema de la base `drive_nodes`).
    for (final header in [
      'SERVIDOR',
      'ESTADO',
      'VERSIÓN',
      'PRIOR.',
      'BIBLIOTECAS',
      'ESPACIO',
      'PING',
      'DEPENDE DE',
    ]) {
      expect(find.text(header), findsOneWidget, reason: 'columna $header');
    }

    expect(find.text('Servidor 1'), findsOneWidget);
    expect(find.text('http://192.168.1.72:4000'), findsOneWidget);
    expect(find.text('Bodega'), findsOneWidget);
    expect(find.text('v1.0.0'), findsOneWidget);
    expect(find.text('10'), findsOneWidget, reason: 'prioridad');
    expect(find.text('34 ms'), findsOneWidget, reason: 'ping');
    expect(find.text('120 GB / 240 GB'), findsOneWidget);
    expect(find.text('sharp'), findsOneWidget);
    expect(find.text('ffmpeg'), findsOneWidget);
    // «En línea» en la tabla y en «Detalles de la conexión».
    expect(find.text('En línea'), findsNWidgets(2));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('lo que NO responde lo dice el hub, con su motivo', (tester) async {
    _installMocks(
      [
        _node(id: 1, name: 'Servidor 1'),
        _node(id: 2, name: 'Servidor 2', url: 'http://192.168.1.73:4000'),
      ],
      health: {
        'service': 'hardstreet-drive-hub',
        'nodes': [
          {'id': 1, 'name': 'Servidor 1', 'enabled': true, 'online': true},
          {
            'id': 2,
            'name': 'Servidor 2',
            'enabled': true,
            'online': false,
            'error': 'Tiempo de espera con Servidor 2',
          },
        ],
      },
    );

    _tall(tester);
    await _open(tester);

    expect(find.text('Sin respuesta'), findsOneWidget);
    expect(
      find.textContaining('Tiempo de espera con Servidor 2'),
      findsNWidgets(2),
      reason: 'se dice POR QUÉ no responde (en la tabla y en los detalles)',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('una dependencia caída deja el servidor en MANTENIMIENTO', (
    tester,
  ) async {
    // Servidor 2 depende del 1: si el 1 no responde, el 2 queda bloqueado y
    // el panel lo dice (y el hub deja de usarlo).
    _installMocks(
      [
        _node(id: 1, name: 'Bodega'),
        _node(id: 2, name: 'Respaldo', dependsOn: const [1]),
      ],
      health: {
        'service': 'hardstreet-drive-hub',
        'nodes': [
          {
            'id': 1,
            'name': 'Bodega',
            'enabled': true,
            'online': false,
            'error': 'nada escucha en ese puerto (ECONNREFUSED)',
          },
          {
            'id': 2,
            'name': 'Respaldo',
            'enabled': true,
            'online': true,
            'blocked': true,
            'blockedReason': 'Depende de Bodega, que no responde',
            'dependsOn': const [1],
          },
        ],
        'maintenance': {
          'blocked': 1,
          'items': [
            {
              'id': 2,
              'name': 'Respaldo',
              'reason': 'Depende de Bodega, que no responde',
              'dependsOn': [
                {'id': 1, 'name': 'Bodega'},
              ],
            },
          ],
          'message': 'El Drive está en mantenimiento.',
        },
      },
    );

    _tall(tester);
    await _open(tester);

    expect(find.text('Mantenimiento'), findsOneWidget, reason: 'píldora');
    expect(find.text('Drive en mantenimiento'), findsOneWidget);
    expect(
      find.textContaining('Depende de Bodega, que no responde'),
      findsWidgets,
    );
    // La columna «depende de» enseña el NOMBRE, no el id.
    expect(find.text('Bodega'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sin hub no se inventa el estado: «Sin comprobar»', (tester) async {
    _installMocks(
      [_node(id: 1, name: 'Servidor 1'), _node(id: 2, name: 'Servidor 2', enabled: 0)],
      healthStatus: 503,
    );

    _tall(tester);
    await _open(tester);

    expect(find.text('Hub sin respuesta'), findsOneWidget);
    expect(find.text('Sin comprobar'), findsOneWidget);
    expect(find.text('Apagado'), findsOneWidget);
    expect(find.text('En línea'), findsNothing);
    expect(find.text('Encendido'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el alta deja elegir de quién DEPENDE el servidor', (tester) async {
    _installMocks([_node(id: 1, name: 'Bodega')]);

    _tall(tester);
    await _open(tester);

    await tester.tap(find.byKey(const ValueKey('drive-node-add')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Nuevo servidor del Drive'), findsOneWidget);
    expect(find.byKey(const ValueKey('drive-node-name')), findsOneWidget);
    expect(find.byKey(const ValueKey('drive-node-url')), findsOneWidget);
    // El otro servidor se puede marcar como dependencia.
    expect(find.text('Depende de'), findsOneWidget);
    expect(find.byKey(const ValueKey('drive-node-dep-1')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('la terminal pide el log al hub y lo enseña', (tester) async {
    final calls = <http.Request>[];
    _installMocks(
      [_node(id: 7, name: 'Bodega')],
      health: {
        'service': 'hardstreet-drive-hub',
        'nodes': [
          {'id': 7, 'name': 'Bodega', 'enabled': true, 'online': true},
        ],
      },
      adminCalls: calls,
      logText: '✔ HardStreet Drive API en http://0.0.0.0:4000',
    );

    _tall(tester);
    await _open(tester);

    await tester.tap(find.byTooltip('Acciones de Bodega'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Ver terminal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // El log llega de un Future: un pump más lo pinta.
    await tester.pump();

    expect(find.text('Terminal · Bodega'), findsOneWidget);
    expect(find.textContaining('journalctl -u hardstreet-drive'), findsOneWidget);
    expect(
      find.textContaining('HardStreet Drive API en http://0.0.0.0:4000'),
      findsOneWidget,
      reason: 'el log que devolvió el hub',
    );
    expect(
      calls.any((r) => r.url.path.endsWith('/api/admin/node/7/logs')),
      isTrue,
      reason: 'el log se pide al HUB, no al servidor de archivos',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reiniciar pide confirmación y llama al hub', (tester) async {
    final calls = <http.Request>[];
    _installMocks(
      [_node(id: 7, name: 'Bodega')],
      health: {
        'service': 'hardstreet-drive-hub',
        'nodes': [
          {'id': 7, 'name': 'Bodega', 'enabled': true, 'online': true},
        ],
      },
      adminCalls: calls,
    );

    _tall(tester);
    await _open(tester);

    await tester.tap(find.byTooltip('Acciones de Bodega'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Reiniciar servicio'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Primero pregunta: un reinicio corta el Drive unos segundos.
    expect(find.text('Reiniciar Bodega'), findsOneWidget);
    expect(calls, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Reiniciar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      calls.any((r) => r.url.path.endsWith('/api/admin/node/7/restart')),
      isTrue,
    );

    // El refresco diferido de la salud no debe quedar pendiente al cerrar.
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('en el celular se ven tarjetas, sin desbordes', (tester) async {
    _installMocks(
      [
        _node(
          id: 1,
          name: 'Servidor bodega con un nombre bastante largo',
          notes: 'Este servidor guarda las fotos de las bodas de todo el año',
        ),
      ],
      health: {
        'service': 'hardstreet-drive-hub',
        'nodes': [
          {
            'id': 1,
            'name': 'Servidor bodega con un nombre bastante largo',
            'enabled': true,
            'online': true,
            'version': '1.0.0',
            'libs': {'sharp': false, 'ffmpeg': true},
          },
        ],
      },
      hubNodes: [
        {
          'id': 1,
          'name': 'Servidor bodega con un nombre bastante largo',
          'url': 'http://192.168.1.72:4000',
          'priority': 100,
          'freeBytes': 3 * 1024 * 1024 * 1024,
          'totalBytes': 100 * 1024 * 1024 * 1024,
        },
      ],
    );

    tester.view.physicalSize = const Size(380, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _open(tester);

    // Si algo se saliera de la tarjeta, el layout lanzaría la excepción.
    expect(tester.takeException(), isNull);
    expect(find.text('3.00 GB / 100 GB'), findsOneWidget);
    expect(find.text('v1.0.0'), findsOneWidget);
    // La cabecera de la tabla NO está: en angosto son tarjetas.
    expect(find.text('BIBLIOTECAS'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('si el backend rechaza (no es superadmin) se dice y no rompe', (
    tester,
  ) async {
    final previousCrud = HsApi.client;
    final previousDrive = DriveApiService.client;
    addTearDown(() {
      HsApi.client = previousCrud;
      DriveApiService.client = previousDrive;
    });
    HsApi.client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'code': 403,
          'ok': false,
          'error': 'Solo el Superadministrador',
          'message': 'Solo el Superadministrador',
        }),
        403,
        headers: {'content-type': 'application/json'},
      ),
    );
    DriveApiService.client = MockClient(
      (_) async =>
          http.Response('{}', 200, headers: {'content-type': 'application/json'}),
    );

    _tall(tester);
    await _open(tester);

    expect(find.textContaining('Solo el Superadministrador'), findsWidgets);
    // El resto de la página sigue ahí.
    expect(find.text('Detalles de la conexión'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}

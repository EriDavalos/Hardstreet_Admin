import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/drive_api_service.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/connection_page.dart';

// ==================================================================
// SERVIDORES DEL DRIVE EN EL PANEL (Drive federado) — módulo Conexión
// ==================================================================
// La pantalla enseña los servidores como un DIAGRAMA de red: el HUB en el
// centro conectado a cada servidor, cada uno como una card con su ficha
// completa (estado, versión, prioridad, bibliotecas, espacio, ping y de quién
// depende) y líneas de DEPENDENCIA entre servidores. Aquí se comprueba:
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

  /// Peticiones al CRUD (servidores): aquí se ven los PUT/POST que guarda el
  /// panel, incluido el `dependsOn` del modal de dependencias.
  List<http.Request>? crudCalls,
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
      jsonEncode({
        'ok': true,
        'saved': 1,
        'names': ['server.js'],
      }),
      adminStatus,
      headers: {'content-type': 'application/json'},
    );
  });

  HsApi.client = MockClient((request) async {
    crudCalls?.add(request);
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
  int active = 1,
  int priority = 10,
  String? notes,
  List<int> dependsOn = const [],
}) => {
  'id': id,
  'name': name,
  'url': url,
  'enabled': enabled,
  'active': active,
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
  testWidgets(
    'el diagrama enseña versión, prioridad, bibliotecas, espacio y ping',
    (tester) async {
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

      // El lienzo del diagrama (no una tabla) con el HUB en el centro.
      expect(find.byKey(const ValueKey('drive-topology')), findsOneWidget);
      expect(find.text('HUB del Drive'), findsOneWidget);
      expect(find.text('BIBLIOTECAS'), findsNothing, reason: 'ya no es tabla');

      expect(find.text('Servidor 1'), findsOneWidget);
      expect(find.text('http://192.168.1.72:4000'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && '${w.message}'.contains('Bodega'),
        ),
        findsOneWidget,
        reason: 'las notas del servidor siguen a mano (en la card)',
      );
      // La versión sale en la card y en el HUB: se comprueba que esté.
      expect(find.text('v1.0.0'), findsWidgets);
      expect(find.text('10'), findsOneWidget, reason: 'prioridad');
      expect(find.text('34 ms'), findsOneWidget, reason: 'ping');
      expect(find.text('120 GB / 240 GB'), findsOneWidget);
      expect(find.text('sharp'), findsOneWidget);
      expect(find.text('ffmpeg'), findsOneWidget);
      // «En línea» en la tabla y en «Detalles de la conexión».
      expect(find.text('En línea'), findsNWidgets(2));

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('lo que NO responde lo dice el hub, con su motivo', (
    tester,
  ) async {
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
      reason: 'se dice POR QUÉ no responde (en su card y en los detalles)',
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
    // La card dice de QUIÉN depende con su NOMBRE, no con el id.
    expect(find.textContaining('depende de Bodega'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('un bloqueo PARCIAL no dice «Drive en mantenimiento»', (
    tester,
  ) async {
    // Bodega responde y se puede usar; Respaldo está bloqueado porque depende
    // de un tercero caído. El Drive ENTERO sigue en funcionamiento, así que el
    // aviso de mantenimiento no sale (el bloqueo de Respaldo se sigue viendo
    // en su card).
    _installMocks(
      [
        _node(id: 1, name: 'Bodega'),
        _node(id: 2, name: 'Caido'),
        _node(id: 3, name: 'Respaldo', dependsOn: const [2]),
      ],
      health: {
        'service': 'hardstreet-drive-hub',
        'nodes': [
          {'id': 1, 'name': 'Bodega', 'enabled': true, 'online': true},
          {
            'id': 2,
            'name': 'Caido',
            'enabled': true,
            'online': false,
            'error': 'nada escucha en ese puerto (ECONNREFUSED)',
          },
          {
            'id': 3,
            'name': 'Respaldo',
            'enabled': true,
            'online': true,
            'blocked': true,
            'blockedReason': 'Depende de Caido, que no responde',
            'dependsOn': const [2],
          },
        ],
        'maintenance': {
          'active': false,
          'blocked': 1,
          'items': [
            {
              'id': 3,
              'name': 'Respaldo',
              'reason': 'Depende de Caido, que no responde',
              'dependsOn': [
                {'id': 2, 'name': 'Caido'},
              ],
            },
          ],
          'message': '',
        },
      },
    );

    _tall(tester);
    await _open(tester);

    expect(find.text('Drive en mantenimiento'), findsNothing);
    expect(find.byKey(const ValueKey('drive-maintenance')), findsNothing);
    // El bloqueo de ESE servidor se sigue contando en su card.
    expect(find.text('Mantenimiento'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sin hub no se inventa el estado: «Sin comprobar»', (
    tester,
  ) async {
    _installMocks([
      _node(id: 1, name: 'Servidor 1'),
      _node(id: 2, name: 'Servidor 2', enabled: 0),
    ], healthStatus: 503);

    _tall(tester);
    await _open(tester);

    expect(find.text('Hub sin respuesta'), findsOneWidget);
    expect(find.text('Sin comprobar'), findsOneWidget);
    expect(find.text('En línea'), findsNothing);
    expect(find.text('Encendido'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('un servidor ELIMINADO (active 0) no se dibuja: borrado lógico', (
    tester,
  ) async {
    _installMocks([
      _node(id: 1, name: 'Servidor 1'),
      _node(id: 2, name: 'Servidor viejo', active: 0),
    ]);

    _tall(tester);
    await _open(tester);

    // El diagrama solo enseña lo que cuenta para el Drive.
    expect(find.text('Servidor 1'), findsWidgets);
    expect(find.text('Servidor viejo'), findsNothing);
    // Ni siquiera queda un interruptor para «verlos»: `active = 0` es un
    // borrado lógico, así que ese servidor no existe para el panel.
    expect(find.byKey(const ValueKey('drive-node-show-off')), findsNothing);
    expect(find.textContaining('Desactivados'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('un servidor APAGADO (enabled 0) sí se ve: se puede encender', (
    tester,
  ) async {
    final crud = <http.Request>[];
    _installMocks([
      _node(id: 1, name: 'Servidor 1'),
      _node(id: 2, name: 'Servidor apagado', enabled: 0),
    ], crudCalls: crud);

    _tall(tester);
    await _open(tester);

    // Apagado NO es eliminado: sigue en la lista, marcado «Apagado».
    expect(find.text('Servidor apagado'), findsWidgets);
    expect(find.text('Apagado'), findsOneWidget);

    await tester.tap(find.byTooltip('Acciones de Servidor apagado'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Encender en el Drive'), findsOneWidget);

    await tester.tap(find.text('Encender en el Drive').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final puts = crud.where((r) => r.method == 'PUT').toList();
    expect(puts, isNotEmpty);
    expect(jsonDecode(puts.last.body)['enabled'], true);
    // Encender no elimina nada.
    expect(crud.where((r) => r.method == 'DELETE'), isEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Eliminar del Drive es borrado lógico, distinto de apagar', (
    tester,
  ) async {
    final crud = <http.Request>[];
    _installMocks([
      _node(id: 1, name: 'Bodega'),
      _node(id: 2, name: 'Bodas', url: 'http://192.168.1.73:4000'),
    ], crudCalls: crud);

    _tall(tester);
    await _open(tester);

    await tester.tap(find.byTooltip('Acciones de Bodega'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Editar').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final borrar = find.byKey(const ValueKey('drive-node-delete'));
    expect(borrar, findsOneWidget);
    await tester.ensureVisible(borrar);
    await tester.pump();
    await tester.tap(borrar);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Eliminar "Bodega" del Drive'), findsOneWidget);
    expect(find.textContaining('BORRADO LÓGICO'), findsOneWidget);
    expect(
      find.textContaining('No se borra nada del servidor ni de sus archivos'),
      findsOneWidget,
    );

    await tester.tap(find.text('Eliminar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final deletes = crud.where((r) => r.method == 'DELETE').toList();
    expect(deletes, isNotEmpty);
    expect(jsonDecode(deletes.last.body)['id'], 1);
    // Eliminar no es apagar: no manda enabled = false.
    expect(crud.where((r) => r.method == 'PUT'), isEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('con UN servidor suelto el SO sale de su propia salud', (
    tester,
  ) async {
    // Sin hub no hay lista de nodos: el único dato de SO es el de la salud de
    // ESE servidor, y es el que tiene que verse en su card.
    _installMocks(
      [_node(id: 1, name: 'Servidor único')],
      health: {
        'service': 'hardstreet-drive',
        'version': '3.4.5',
        'root': '/srv/drive-data',
        'os': {
          'platform': 'linux',
          'type': 'Linux',
          'arch': 'arm64',
          'distro': 'Debian GNU/Linux 12 (bookworm)',
        },
      },
    );

    _tall(tester);
    await _open(tester);

    expect(find.text('Debian GNU/Linux 12 (bookworm) · arm64'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el alta NO mezcla dependencias: tienen su propio modal', (
    tester,
  ) async {
    _installMocks([_node(id: 1, name: 'Bodega')]);

    _tall(tester);
    await _open(tester);

    await tester.tap(find.byKey(const ValueKey('drive-node-add')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Nuevo servidor del Drive'), findsOneWidget);
    expect(find.byKey(const ValueKey('drive-node-name')), findsOneWidget);
    expect(find.byKey(const ValueKey('drive-node-url')), findsOneWidget);
    // Se avisa DÓNDE se configuran, pero las casillas ya no están aquí.
    expect(find.textContaining('«Dependencias»'), findsOneWidget);
    expect(find.byKey(const ValueKey('drive-node-dep-1')), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el modal de DEPENDENCIAS marca y guarda la relación', (
    tester,
  ) async {
    final crud = <http.Request>[];
    _installMocks(
      [_node(id: 1, name: 'Bodega'), _node(id: 2, name: 'Respaldo')],
      health: {
        'service': 'hardstreet-drive-hub',
        'nodes': [
          {'id': 1, 'name': 'Bodega', 'enabled': true, 'online': true},
          {'id': 2, 'name': 'Respaldo', 'enabled': true, 'online': true},
        ],
      },
      crudCalls: crud,
    );

    _tall(tester);
    await _open(tester);

    await tester.tap(find.byTooltip('Acciones de Respaldo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Dependencias'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Dependencias de Respaldo'), findsOneWidget);
    final dep = find.byKey(const ValueKey('drive-node-dep-1'));
    expect(dep, findsOneWidget);
    await tester.tap(dep);
    await tester.pump();
    expect(find.textContaining('unificado con 1 servidor'), findsOneWidget);

    await tester.tap(find.text('Guardar dependencias'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final put = crud.where((r) => r.method == 'PUT').toList();
    expect(put, isNotEmpty, reason: 'se guarda contra /api/admin/drive-nodes');
    expect(jsonDecode(put.last.body)['dependsOn'], [1]);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('la card enseña la DESCRIPCIÓN y la RAM del servidor', (
    tester,
  ) async {
    _installMocks(
      [_node(id: 1, name: 'Bodega', notes: 'Guarda las fotos de las bodas')],
      health: {
        'service': 'hardstreet-drive-hub',
        'nodes': [
          {'id': 1, 'name': 'Bodega', 'enabled': true, 'online': true},
        ],
      },
      hubNodes: [
        {
          'id': 1,
          'name': 'Bodega',
          'url': 'http://192.168.1.72:4000',
          'mem': {
            'totalBytes': 8 * 1024 * 1024 * 1024,
            'freeBytes': 4 * 1024 * 1024 * 1024,
            'usedBytes': 4 * 1024 * 1024 * 1024,
          },
        },
      ],
    );

    _tall(tester);
    await _open(tester);

    expect(find.text('Guarda las fotos de las bodas'), findsOneWidget);
    expect(find.text('RAM'), findsWidgets);
    expect(find.text('4.00 GB / 8.00 GB'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('la DESCRIPCIÓN no se pierde si el hub la manda vacía', (
    tester,
  ) async {
    // El hub reenvía lo que le da el backend, y ese endpoint no siempre lleva
    // `notes`: con el hub conectado la card se quedaba SIN descripción aunque
    // la base de datos sí la tuviera. La de la base manda cuando llega vacía.
    _installMocks(
      [_node(id: 1, name: 'Bodega', notes: 'Guarda las fotos de las bodas')],
      health: {
        'service': 'hardstreet-drive-hub',
        'nodes': [
          {'id': 1, 'name': 'Bodega', 'enabled': true, 'online': true},
        ],
      },
      hubNodes: [
        {
          'id': 1,
          'name': 'Bodega',
          'url': 'http://192.168.1.72:4000',
          'notes': '',
          'online': true,
        },
      ],
    );

    _tall(tester);
    await _open(tester);

    expect(find.text('DESCRIPCIÓN'), findsOneWidget);
    expect(find.text('Guarda las fotos de las bodas'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tocar una card la selecciona y NO mueve nada', (tester) async {
    _installMocks([
      _node(id: 1, name: 'Bodega', priority: 10),
      _node(
        id: 2,
        name: 'Bodas',
        url: 'http://192.168.1.73:4000',
        priority: 20,
      ),
    ]);

    _tall(tester);
    await _open(tester);

    final before = tester.getTopLeft(find.text('Bodega'));
    // Un toque normal en el CUERPO de la card (no en la letra del nombre).
    await tester.tapAt(before + const Offset(50, 70));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      tester.getTopLeft(find.text('Bodega')),
      before,
      reason: 'un toque no puede arrastrar la card',
    );
    expect(
      find.text('Reordenar'),
      findsNothing,
      reason: 'ninguna card quedó desplazada',
    );
    // Se DESTACA la tocada (y no al revés), pero la otra sigue a la vista:
    // antes las demás se atenuaban y parecía que se ocultaban.
    bool isSelected(String name) => tester
        .widgetList<Semantics>(
          find.ancestor(of: find.text(name), matching: find.byType(Semantics)),
        )
        .any((s) => s.properties.selected == true);
    expect(isSelected('Bodega'), isTrue);
    expect(isSelected('Bodas'), isFalse);
    expect(find.text('Bodas'), findsOneWidget);

    // El foco se quita SOLO a los 4 s.
    await tester.pump(const Duration(seconds: 4));
    expect(isSelected('Bodega'), isFalse);

    // Y también con Esc.
    await tester.tapAt(before + const Offset(50, 70));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(isSelected('Bodega'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(isSelected('Bodega'), isFalse);

    // Pulsación LARGA + arrastre: ahora sí se mueve.
    final drag = await tester.startGesture(before + const Offset(50, 70));
    await tester.pump(const Duration(milliseconds: 700));
    await drag.moveBy(const Offset(70, 10));
    await tester.pump();
    await drag.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      tester.getTopLeft(find.text('Bodega')).dx,
      greaterThan(before.dx + 30),
      reason: 'con pulsación larga la card se puede reacomodar',
    );
    expect(find.text('Reordenar'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('en modo selección se marca tocando cualquier parte de la card', (
    tester,
  ) async {
    _installMocks([
      _node(id: 1, name: 'Bodega'),
      _node(id: 2, name: 'Bodas', url: 'http://192.168.1.73:4000'),
    ]);

    _tall(tester);
    await _open(tester);

    await tester.tap(find.byKey(const ValueKey('drive-node-select')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // El botón de selección se ve bien al activarse: sin el check animado de
    // Material encima del icono, con su etiqueta de estado y sin desbordes.
    final chip = tester.widget<FilterChip>(
      find.byKey(const ValueKey('drive-node-select')),
    );
    expect(chip.showCheckmark, isFalse);
    expect(find.text('Seleccionando'), findsOneWidget);
    expect(find.byKey(const ValueKey('node-pick-1')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Debajo del nombre, no en la casilla: antes solo la casilla marcaba.
    await tester.tapAt(
      tester.getTopLeft(find.text('Bodega')) + const Offset(50, 70),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const ValueKey('drive-node-bulk')), findsOneWidget);
    expect(find.textContaining('1 servidor marcado'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('apagar un servidor del que dependen otros avisa antes', (
    tester,
  ) async {
    final crud = <http.Request>[];
    _installMocks([
      _node(id: 1, name: 'Bodega'),
      _node(
        id: 2,
        name: 'Bodas',
        url: 'http://192.168.1.73:4000',
        dependsOn: [1],
      ),
    ], crudCalls: crud);

    _tall(tester);
    await _open(tester);

    Future<void> abrirApagar() async {
      await tester.tap(find.byTooltip('Acciones de Bodega'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Apagar en el Drive').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await abrirApagar();
    // Apagarlo deja a Bodas en mantenimiento: se dice con su nombre.
    expect(find.text('Apagar "Bodega" en el Drive'), findsOneWidget);
    expect(
      find.textContaining('Bodas depende de este servidor'),
      findsOneWidget,
    );
    // Y deja claro que NO se toca el servicio del servidor ni sus archivos.
    expect(
      find.textContaining(
        'El servicio del servidor y sus archivos no se tocan',
      ),
      findsOneWidget,
    );

    // Cancelar no apaga nada (ni manda el PUT).
    await tester.tap(find.text('Cancelar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(crud.where((r) => r.method == 'PUT'), isEmpty);

    // «Apagar» sí guarda el cambio: enabled = false (la fila sigue viva).
    await abrirApagar();
    await tester.tap(find.text('Apagar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final puts = crud.where((r) => r.method == 'PUT').toList();
    expect(puts, isNotEmpty);
    expect(jsonDecode(puts.last.body)['enabled'], false);
    // Apagar no elimina: la fila se queda (active sigue en 1).
    expect(crud.where((r) => r.method == 'DELETE'), isEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cada servidor dice su DESCRIPCIÓN y el SO con el que trabaja', (
    tester,
  ) async {
    _installMocks(
      [
        _node(
          id: 1,
          name: 'Casa de Eri',
          notes: 'Disco de 180 GB en casa de Eri',
        ),
        _node(id: 2, name: 'Casa de Edgar', url: 'http://192.168.1.73:4000'),
      ],
      health: {
        'service': 'hardstreet-drive-hub',
        'nodes': [
          {
            'id': 1,
            'name': 'Casa de Eri',
            'enabled': true,
            'online': true,
            // Lo que manda el nodo en su /api/health (el hub lo reenvía).
            'os': {
              'platform': 'linux',
              'type': 'Linux',
              'release': '6.8.0-45-generic',
              'arch': 'x64',
              'distro': 'Ubuntu 24.04.1 LTS',
            },
          },
          {
            'id': 2,
            'name': 'Casa de Edgar',
            'enabled': true,
            'online': true,
            // Windows no tiene /etc/os-release: se arma con `type`.
            'os': {'platform': 'win32', 'type': 'Windows_NT', 'arch': 'x64'},
          },
        ],
      },
    );

    _tall(tester);
    await _open(tester);

    // La descripción lleva su rótulo (no es un texto suelto) y cada card dice
    // el SO de ESE servidor: Ubuntu el de Eri y Windows el de Edgar.
    expect(find.text('DESCRIPCIÓN'), findsOneWidget);
    expect(find.text('Disco de 180 GB en casa de Eri'), findsOneWidget);
    expect(find.text('Ubuntu 24.04.1 LTS · x64'), findsOneWidget);
    expect(find.text('Windows · x64'), findsOneWidget);
    expect(find.text('SO'), findsNWidgets(2));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('se puede subir el MISMO proyecto a varios servidores', (
    tester,
  ) async {
    final calls = <http.Request>[];
    _installMocks(
      [_node(id: 1, name: 'Bodega'), _node(id: 2, name: 'Respaldo')],
      health: {
        'service': 'hardstreet-drive-hub',
        'nodes': [
          {'id': 1, 'name': 'Bodega', 'enabled': true, 'online': true},
          {'id': 2, 'name': 'Respaldo', 'enabled': true, 'online': true},
        ],
      },
      adminCalls: calls,
    );
    final previousPicker = ConnectionPage.pickProjectFiles;
    addTearDown(() => ConnectionPage.pickProjectFiles = previousPicker);
    ConnectionPage.pickProjectFiles = () async => [
      XFile.fromData(
        Uint8List.fromList('console.log(1)'.codeUnits),
        name: 'server.js',
      ),
    ];

    _tall(tester);
    await _open(tester);

    await tester.tap(find.byKey(const ValueKey('drive-node-select')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('node-pick-1')));
    await tester.tap(find.byKey(const ValueKey('node-pick-2')));
    await tester.pump();

    expect(find.text('2 servidores marcados'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('drive-node-bulk-upload')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final uploads = calls
        .where((r) => r.url.path.endsWith('/files'))
        .map((r) => r.url.path)
        .toList();
    expect(
      uploads,
      containsAll(['/api/admin/node/1/files', '/api/admin/node/2/files']),
      reason: 'el archivo se elige una vez y va a los DOS servidores',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('la dirección del Drive se configura en el HUB', (tester) async {
    _installMocks([_node(id: 1, name: 'Bodega')]);

    _tall(tester);
    await _open(tester);

    // Ya NO hay una sección suelta de «Dirección del servidor».
    expect(find.text('Dirección del servidor'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('hub-configure')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey('hub-address-field')), findsOneWidget);

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
    expect(
      find.textContaining('journalctl -u hardstreet-drive'),
      findsOneWidget,
    );
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
            'os': {
              'platform': 'linux',
              'type': 'Linux',
              'arch': 'x64',
              'distro': 'Ubuntu 24.04.1 LTS',
            },
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
    expect(find.text('v1.0.0'), findsWidgets);
    // En el celular también se ven la descripción y el SO del servidor.
    expect(find.text('DESCRIPCIÓN'), findsOneWidget);
    expect(find.text('Ubuntu 24.04.1 LTS · x64'), findsOneWidget);
    // En angosto NO se dibuja el diagrama: son tarjetas una debajo de otra.
    expect(find.byKey(const ValueKey('drive-topology')), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('en computadora los detalles van en el panel de al lado', (
    tester,
  ) async {
    _installMocks([_node(id: 1, name: 'Bodega')]);

    tester.view.physicalSize = const Size(1500, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester);

    // El diagrama ocupa el RESTO de la vista (todo menos el panel).
    final diagram = find.byKey(const ValueKey('drive-topology'));
    expect(diagram, findsOneWidget);
    expect(tester.getSize(diagram).width, greaterThan(900));

    // El panel de detalles va a la DERECHA del diagrama, no debajo.
    final side = find.byKey(const ValueKey('connection-side'));
    expect(side, findsOneWidget);
    expect(
      tester.getTopLeft(side).dx,
      greaterThan(tester.getTopRight(diagram).dx),
      reason: 'los detalles salen a un lado',
    );
    expect(find.text('Detalles de la conexión'), findsOneWidget);
    expect(find.text('HUB'), findsOneWidget);

    // La card se lee, pero es ESTRECHA a propósito: no se estira a todo el
    // ancho del diagrama (con una sola, se quedaba enorme y se comía el
    // lienzo).
    final card = find
        .ancestor(
          of: find.text('Bodega'),
          matching: find.byType(AnimatedContainer),
        )
        .first;
    expect(tester.getSize(card).width, greaterThan(300));
    expect(tester.getSize(card).width, lessThan(460));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('la tarjeta del diagrama LLENA el alto de la vista', (
    tester,
  ) async {
    // El fallo que se arregla aquí: con una ventana normal la tarjeta acababa
    // a media pantalla y dejaba una franja vacía debajo (se veía «cortada»).
    _installMocks(
      [_node(id: 1, name: 'Bodega')],
      health: {
        'service': 'hardstreet-drive-hub',
        'version': '1.0.0',
        'nodesSource': 'backend',
        'nodes': [
          {'id': 1, 'name': 'Bodega', 'enabled': true, 'online': true},
        ],
      },
      hubNodes: [
        {
          'id': 1,
          'name': 'Bodega',
          'url': 'http://192.168.1.72:4000',
          'priority': 10,
          'online': true,
          'version': '1.0.0',
          'latencyMs': 12,
          'dependsOn': const <int>[],
        },
      ],
    );

    // Ventana alta: el contenido del diagrama no llega a llenarla, así que es
    // la tarjeta la que estira (antes se quedaba corta y dejaba el hueco).
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester);

    final card = find.byKey(const ValueKey('drive-nodes-card'));
    expect(card, findsOneWidget);
    final rect = tester.getRect(card);
    // Se queda con TODO el alto: lo de arriba (18) y el margen de scroll (40).
    expect(rect.height, closeTo(1400 - 58, 1));

    // Y el diagrama no se pega a los bordes: el aire sobrante se reparte
    // alrededor (queda centrado), no todo al final.
    final topo = tester.getRect(find.byKey(const ValueKey('drive-topology')));
    expect(topo.top - rect.top, greaterThan(120), reason: 'aire arriba');
    expect(rect.bottom - topo.bottom, greaterThan(60), reason: 'aire abajo');
    expect(tester.takeException(), isNull);

    // En una ventana BAJA no se desborda: la tarjeta se queda en su mínimo y
    // la página hace scroll.
    tester.view.physicalSize = const Size(1600, 520);
    await tester.pump();
    expect(tester.getRect(card).height, greaterThanOrEqualTo(320));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el estado del hub sale en los detalles, no sobre el diagrama', (
    tester,
  ) async {
    _installMocks(
      [_node(id: 1, name: 'Bodega')],
      health: {
        'service': 'hardstreet-drive-hub',
        'nodes': [
          {'id': 1, 'name': 'Bodega', 'enabled': true, 'online': true},
        ],
      },
    );

    _tall(tester);
    await _open(tester);

    // La vista principal es SOLO el diagrama: el estado del hub ya no es una
    // tarjeta grande encima de él.
    expect(find.byKey(const ValueKey('drive-topology')), findsOneWidget);

    final side = find.byKey(const ValueKey('connection-side'));
    expect(side, findsOneWidget);
    expect(
      find.descendant(
        of: side,
        matching: find.byKey(const ValueKey('hub-status')),
      ),
      findsOneWidget,
      reason: 'el estado del hub va en el panel lateral',
    );
    expect(
      find.descendant(of: side, matching: find.text('Hub conectado')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: side,
        matching: find.textContaining('1 de 1 servidor en línea'),
      ),
      findsOneWidget,
    );
    // Una sola vez en toda la pantalla: no quedó duplicado en el diagrama.
    expect(find.text('Hub conectado'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('en el celular el panel lateral se apila (sin desbordes)', (
    tester,
  ) async {
    _installMocks([_node(id: 1, name: 'Bodega')]);

    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester);

    // En angosto no hay panel al lado: los detalles quedan más abajo y se
    // baja como en el resto del panel.
    expect(find.byKey(const ValueKey('connection-side')), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Detalles de la conexión'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Detalles de la conexión'), findsOneWidget);
    expect(tester.takeException(), isNull);

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
      (_) async => http.Response(
        '{}',
        200,
        headers: {'content-type': 'application/json'},
      ),
    );

    _tall(tester);
    await _open(tester);

    expect(find.textContaining('Solo el Superadministrador'), findsWidgets);
    // El resto de la página sigue ahí.
    expect(find.text('Detalles de la conexión'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'con TRES servidores es una ESTRELLA: el HUB en el medio y cards alrededor',
    (tester) async {
      _installMocks([
        _node(id: 1, name: 'Bodega'),
        _node(id: 2, name: 'Estudio', url: 'http://192.168.1.73:4000'),
        _node(
          id: 3,
          name: 'Respaldo',
          url: 'http://192.168.1.74:4000',
          // La ficha completa (descripción incluida) también tiene que caber
          // en la card estrecha.
          notes: 'Disco de respaldo en casa de Eri',
        ),
      ]);

      tester.view.physicalSize = const Size(1400, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _open(tester);

      Rect card(String name) => tester.getRect(
        find
            .ancestor(
              of: find.text(name),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );

      final first = card('Bodega');
      final second = card('Estudio');
      final third = card('Respaldo');
      final hub = tester.getRect(
        find.byKey(const ValueKey('drive-topology-hub')),
      );

      // Los dos primeros comparten fila ARRIBA del HUB; el tercero va DEBAJO.
      expect(first.top, second.top);
      expect(first.bottom, lessThanOrEqualTo(hub.top));
      expect(third.top, greaterThanOrEqualTo(hub.bottom));

      // El HUB queda EN MEDIO de la estrella, no arriba de todo.
      expect(hub.center.dy, greaterThan(first.bottom));
      expect(hub.center.dy, lessThan(third.top));

      // Y todo se centra con el HUB (no pegado a la izquierda).
      expect((third.center.dx - hub.center.dx).abs(), lessThan(2));
      expect(
        ((first.center.dx + second.center.dx) / 2 - hub.center.dx).abs(),
        lessThan(2),
      );

      // La ficha es MÁS ESTRECHA que antes (620) sin achicar letras ni datos.
      expect(first.width, lessThanOrEqualTo(520));
      expect(first.width, lessThan(620));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'un servidor y aquel del que depende van JUNTOS, del mismo lado del HUB',
    (tester) async {
      // El caso que se veía mal: dos servidores, uno depende del otro, y el
      // diagrama los ponía uno ARRIBA y otro ABAJO del HUB, así que la línea
      // de la relación lo cruzaba por encima.
      _installMocks([
        _node(id: 1, name: 'Bodega'),
        _node(
          id: 2,
          name: 'Respaldo',
          url: 'http://192.168.1.73:4000',
          dependsOn: const [1],
        ),
      ]);

      tester.view.physicalSize = const Size(1400, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _open(tester);

      Rect card(String name) => tester.getRect(
        find
            .ancestor(
              of: find.text(name),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );

      final base = card('Bodega');
      final dependent = card('Respaldo');
      final hub = tester.getRect(
        find.byKey(const ValueKey('drive-topology-hub')),
      );

      // Misma fila, del mismo lado del HUB: la relación es una línea corta
      // entre vecinos y no puede atravesar la card del hub.
      expect(dependent.top, base.top);
      expect(dependent.top, greaterThan(hub.bottom));
      // Se lee «Bodega → Respaldo»: el que no depende de nadie va primero.
      expect(base.left, lessThan(dependent.left));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'con una pareja relacionada y un suelto, la pareja no se separa',
    (tester) async {
      _installMocks([
        _node(id: 1, name: 'Bodega'),
        _node(
          id: 2,
          name: 'Respaldo',
          url: 'http://192.168.1.73:4000',
          dependsOn: const [1],
        ),
        _node(id: 3, name: 'Estudio', url: 'http://192.168.1.74:4000'),
      ]);

      tester.view.physicalSize = const Size(1400, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _open(tester);

      Rect card(String name) => tester.getRect(
        find
            .ancestor(
              of: find.text(name),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );

      final base = card('Bodega');
      final dependent = card('Respaldo');
      final hub = tester.getRect(
        find.byKey(const ValueKey('drive-topology-hub')),
      );

      // La pareja comparte fila (y por tanto lado del HUB).
      expect(dependent.top, base.top);
      final pairAbove = base.bottom < hub.top;
      final pairBelow = base.top > hub.bottom;
      expect(pairAbove || pairBelow, isTrue, reason: 'pareja del mismo lado');
      expect((dependent.top - base.top).abs(), lessThan(1));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
    },
  );
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/drive_api_service.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';

// ==================================================================
// ENCABEZADO DEL DRIVE (computadora)
// ==================================================================
// Lo pedido:
//
//   · fuera la franja «En línea · servidor · latencia», que ocupaba una fila
//     en todas las vistas;
//   · un botón de RECARGAR (icono) al lado de «Nueva carpeta» en computadora,
//     que en el celular no hace falta (ahí se recarga tirando hacia abajo);
//   · y la vista de MANTENIMIENTO —a pantalla completa y centrada— cuando NO
//     queda ningún servidor en funcionamiento. Un bloqueo parcial NO para el
//     Drive, y el aviso sale solo al entrar (sin pulsar «Reintentar»).
// ==================================================================

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _listing({List<String> folders = const []}) => {
  'path': <String>[],
  'folders': [
    for (final name in folders) {'name': name, 'isFolder': true},
  ],
  'maintenance': {'blocked': 0, 'items': const <Object>[], 'message': ''},
};

void _mock({
  Map<String, dynamic>? listing,
  http.Response? driveResponse,
  http.Response Function(http.Request request)? onRequest,
}) {
  final previousCrud = HsApi.client;
  final previousDrive = DriveApiService.client;
  addTearDown(() {
    HsApi.client = previousCrud;
    DriveApiService.client = previousDrive;
    HsSession.clear();
  });
  // Permisos: puede crear (así sale «Nueva carpeta» al lado del icono).
  HsApi.client = MockClient(
    (r) async => _json({
      'isAdmin': false,
      'modules': [
        {
          'key': 'drive',
          'name': 'Archivos',
          'actions': ['read', 'create', 'update', 'delete', 'download'],
        },
      ],
    }),
  );
  DriveApiService.client = MockClient(
    (r) async =>
        onRequest?.call(r) ?? driveResponse ?? _json(listing ?? _listing()),
  );
  HsSession.token = 'tok-de-prueba';
}

Future<void> _open(
  WidgetTester tester, {
  Size size = const Size(1280, 900),
}) async {
  // Se fija la VISTA (no solo la superficie): `MediaQuery.sizeOf` lee de aquí
  // y es lo que decide si la pantalla es "compacta" (celular).
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final drive = DriveApiService(baseUrl: 'http://drive.test');
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: DrivePage(drive: drive)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
    'en computadora hay un botón «Recargar» junto a «Nueva carpeta»',
    (tester) async {
      _mock();
      await _open(tester);

      expect(find.text('Nueva carpeta'), findsOneWidget);
      expect(find.byTooltip('Recargar'), findsOneWidget);

      // Y ya no está la franja de estado que ocupaba una fila.
      expect(find.textContaining('En línea'), findsNothing);
    },
  );

  testWidgets('en el celular NO se dibuja el botón de recargar', (
    tester,
  ) async {
    _mock();
    await _open(tester, size: const Size(390, 844));

    expect(find.byTooltip('Recargar'), findsNothing);
    expect(find.text('Nueva carpeta'), findsNothing);
  });

  testWidgets(
    'un bloqueo PARCIAL no para el Drive: solo se va el servidor bloqueado',
    (tester) async {
      // El hub sigue teniendo servidores en funcionamiento y avisa de que uno
      // quedó bloqueado. Eso YA no entra en mantenimiento: el Drive enseña su
      // árbol con normalidad.
      _mock(
        listing: {
          'path': <String>[],
          'folders': [
            {'name': 'Boda', 'isFolder': true},
          ],
          'maintenance': {
            'active': false,
            'blocked': 1,
            'items': [
              {
                'id': 2,
                'name': 'Respaldo',
                'reason': 'Depende de Bodega, que no responde',
              },
            ],
            'message': '',
          },
        },
      );
      await _open(tester);

      expect(find.byKey(const ValueKey('drive-maintenance')), findsNothing);
      expect(find.text('Drive en mantenimiento'), findsNothing);
      expect(find.text('Boda'), findsOneWidget);
      // Y no se nombra a los servidores dependientes en ningún sitio.
      expect(find.textContaining('Respald'), findsNothing);
      expect(find.textContaining('Bodega'), findsNothing);
    },
  );

  testWidgets('el mantenimiento aparece AL ENTRAR, sin pulsar Reintentar', (
    tester,
  ) async {
    // La app llevaba rato abierta y el hub entró en mantenimiento después del
    // último listado. Al abrir Archivos se pregunta a la salud del hub: la
    // vista entera sale en mantenimiento desde el primer instante y NO se ve
    // el árbol viejo que quedaba en memoria.
    _mock(
      onRequest: (r) {
        if (r.url.path.endsWith('/api/health')) {
          return _json({
            'ok': true,
            'maintenance': {
              'active': true,
              'working': 0,
              'blocked': 1,
              'items': [
                {
                  'id': 2,
                  'name': 'Respaldo',
                  'reason': 'Depende de Bodega, que no responde',
                },
              ],
              'message': 'El Drive está en mantenimiento.',
            },
            'nodes': [
              {
                'id': 1,
                'name': 'Bodega',
                'enabled': true,
                'online': false,
                'blocked': false,
              },
              {
                'id': 2,
                'name': 'Respaldo',
                'enabled': true,
                'online': true,
                'blocked': true,
              },
            ],
          });
        }
        return _json(_listing(folders: const ['Vieja']));
      },
    );
    await _open(tester);

    expect(find.byKey(const ValueKey('drive-maintenance')), findsOneWidget);
    expect(find.text('Drive en mantenimiento'), findsOneWidget);
    // Ni el árbol viejo ni los botones del Drive.
    expect(find.text('Vieja'), findsNothing);
    expect(find.text('Nueva carpeta'), findsNothing);
    expect(find.byTooltip('Recargar'), findsNothing);
    // El aviso OCUPA la vista entera y va centrado en ella.
    expect(
      tester.getSize(find.byKey(const ValueKey('drive-maintenance'))),
      const Size(1280, 900),
    );
    final title = tester.getCenter(find.text('Drive en mantenimiento'));
    expect(title.dx, closeTo(640, 40));
    expect(title.dy, greaterThan(250));
    expect(title.dy, lessThan(650));
    // Y no se nombra a los servidores dependientes.
    expect(find.textContaining('Bodega'), findsNothing);
    expect(find.textContaining('Respald'), findsNothing);
  });

  testWidgets('sin ningún servidor en funcionamiento, el 503 es mantenimiento', (
    tester,
  ) async {
    // El hub contesta 503 cuando no le queda ningún servidor en funcionamiento
    // (caídos o bloqueados por dependencia). Antes eso se veía como «No se pudo
    // conectar … HTTP 503» y parecía un problema de red del panel.
    _mock(
      driveResponse: http.Response(
        jsonEncode({
          'code': 503,
          'ok': false,
          'error': 'El Drive está en mantenimiento',
          'message': 'El Drive está en mantenimiento',
          'details': 'Respaldo: Depende de Bodega, que no responde.',
        }),
        503,
        headers: {'content-type': 'application/json'},
      ),
    );
    await _open(tester);

    expect(find.byKey(const ValueKey('drive-maintenance')), findsOneWidget);
    expect(find.text('Drive en mantenimiento'), findsOneWidget);
    // El detalle del hub nombra servidores: aquí NO se reproduce.
    expect(find.textContaining('Bodega'), findsNothing);
    expect(find.textContaining('Respald'), findsNothing);
    expect(find.text(driveMaintenanceNotice), findsWidgets);
    expect(find.text('Sin conexión con el Drive'), findsNothing);
  });

  testWidgets('en el celular la vista de mantenimiento no se desborda', (
    tester,
  ) async {
    _mock(
      driveResponse: http.Response(
        jsonEncode({'error': 'El Drive está en mantenimiento'}),
        503,
        headers: {'content-type': 'application/json'},
      ),
    );
    await _open(tester, size: const Size(390, 844));

    expect(find.text('Drive en mantenimiento'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('drive-maintenance'))),
      const Size(390, 844),
    );
  });
}

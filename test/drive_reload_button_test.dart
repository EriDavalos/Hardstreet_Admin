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
//   · y un aviso de MANTENIMIENTO cuando el hub dice que un servidor está
//     bloqueado porque depende de otro que no responde.
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

void _mock({Map<String, dynamic>? listing, http.Response? driveResponse}) {
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
    (r) async => driveResponse ?? _json(listing ?? _listing()),
  );
  HsSession.token = 'tok-de-prueba';
}

Future<void> _open(WidgetTester tester, {Size size = const Size(1280, 900)}) async {
  // Se fija la VISTA (no solo la superficie): `MediaQuery.sizeOf` lee de aquí
  // y es lo que decide si la pantalla es "compacta" (celular).
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final drive = DriveApiService(baseUrl: 'http://drive.test');
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: DrivePage(drive: drive))),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('en computadora hay un botón «Recargar» junto a «Nueva carpeta»', (
    tester,
  ) async {
    _mock();
    await _open(tester);

    expect(find.text('Nueva carpeta'), findsOneWidget);
    expect(find.byTooltip('Recargar'), findsOneWidget);

    // Y ya no está la franja de estado que ocupaba una fila.
    expect(find.textContaining('En línea'), findsNothing);
  });

  testWidgets('en el celular NO se dibuja el botón de recargar', (tester) async {
    _mock();
    await _open(tester, size: const Size(390, 844));

    expect(find.byTooltip('Recargar'), findsNothing);
    expect(find.text('Nueva carpeta'), findsNothing);
  });

  testWidgets('un servidor en mantenimiento avisa en el Drive', (tester) async {
    _mock(
      listing: {
        'path': <String>[],
        'folders': [
          {'name': 'Boda', 'isFolder': true},
        ],
        'maintenance': {
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
      },
    );
    await _open(tester);

    expect(find.byKey(const ValueKey('drive-maintenance-banner')), findsOneWidget);
    expect(find.text('Mantenimiento'), findsOneWidget);
    expect(
      find.textContaining('Respald'),
      findsWidgets,
      reason: 'se dice QUÉ servidor está bloqueado y por qué',
    );
    // El contenido se sigue viendo: el aviso no tapa las carpetas.
    expect(find.text('Boda'), findsOneWidget);
  });

  testWidgets('si NINGÚN servidor es usable, el 503 se lee como mantenimiento', (
    tester,
  ) async {
    // El hub contesta 503 cuando todos sus servidores están bloqueados por
    // dependencia. Antes eso se veía como «No se pudo conectar … HTTP 503» y
    // parecía un problema de red del panel.
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

    expect(find.text('Drive en mantenimiento'), findsOneWidget);
    expect(
      find.textContaining('Bodega'),
      findsWidgets,
      reason: 'se dice qué servidor cayó y cuál quedó bloqueado',
    );
    expect(find.text('Sin conexión con el Drive'), findsNothing);
  });
}

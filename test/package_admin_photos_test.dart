import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_access.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/clients_page.dart';

/// Paquete vigente con UN servicio que ya tiene selección de fotos.
const int _pkgId = 10;

void _installMock({
  required List<Map<String, dynamic>> posts,
  required bool sent,
}) {
  final previous = HsApi.client;
  addTearDown(() => HsApi.client = previous);

  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;

    if (path.endsWith('/api/admin/client-packages')) {
      return http.Response(
        jsonEncode({
          'purchasedPackages': [
            {
              'usersPackageId': 30,
              'id': _pkgId,
              'name': 'Boda - Premium',
              'subtitle': '',
              'price': 12000,
              'paid': 6000,
              'currency': 'MXN',
              'status': 'En proceso',
              'packageId': 1,
              'tierName': 'Premium',
              'categoryName': 'Boda',
              'agendaCount': 0,
              'services': const [],
            },
          ],
          'catalog': const [],
        }),
        200,
        headers: headers,
      );
    }

    if (path.endsWith('/api/admin/agendas')) {
      return http.Response(
        jsonEncode({'agendas': const []}),
        200,
        headers: headers,
      );
    }

    if (path.endsWith('/api/admin/package-progress')) {
      if (request.method == 'POST') {
        posts.add((jsonDecode(request.body) as Map).cast<String, dynamic>());
        return http.Response(
          jsonEncode({'ok': true, 'message': 'Listo'}),
          200,
          headers: headers,
        );
      }
      return http.Response(
        jsonEncode({
          'package': {
            'id': _pkgId,
            'name': 'Boda - Premium',
            'price': 12000,
            'paid': 6000,
            'balance': 6000,
            'status': 'En proceso',
            'statusId': 2,
            'finished': false,
            'finishedAt': null,
          },
          'services': [
            {
              'id': 1,
              'serviceId': 5,
              'name': 'Cobertura en evento',
              'description': '',
              'url': '',
              'status': 'Pendiente',
              'statusId': 1,
              'done': false,
              'finishedAt': null,
              'shareFolder': 'Boda/Seleccion',
              'shareLink': '',
              'pickPhotos': true,
              'showFolder': true,
              'photosMax': 5,
              'items': 2,
              'itemPaths': [
                'Boda/Seleccion/foto-1.jpg',
                'Boda/Seleccion/foto-2.jpg',
              ],
              'sentToPrint': sent,
              'printStatus': sent ? 'sent' : '',
              'printRequestId': sent ? 77 : null,
            },
          ],
          'movements': const [],
          'totals': {
            'abonado': 6000,
            'invertido': 0,
            'gastado': 0,
            'pagos': 0,
            'ahorrado': 0,
            'abonoExterno': 0,
            'disponible': 6000,
          },
          'canFinish': false,
          'blockers': const [],
        }),
        200,
        headers: headers,
      );
    }

    if (path.endsWith('/api/admin/print-requests')) {
      if (request.method == 'POST') {
        posts.add((jsonDecode(request.body) as Map).cast<String, dynamic>());
      }
      return http.Response(
        jsonEncode({'ok': true, 'message': 'Envío reabierto'}),
        200,
        headers: headers,
      );
    }

    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required List<Map<String, dynamic>> posts,
  required bool sent,
}) async {
  const size = Size(1250, 940);
  await tester.binding.setSurfaceSize(size);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  HsAccess.seedForTest(admin: true, degraded: true);
  _installMock(posts: posts, sent: sent);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ClientPackagesDialog(
          client: const {'id': 7, 'name': 'Ana', 'lastname': 'Ruiz'},
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  await _tap(tester, find.text('Boda - Premium'));
  await _tap(tester, find.text('Servicios'));
  await _tap(tester, find.text('Cobertura en evento'));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('las fotos se ven en botones destacados y el admin puede '
      'elegirlas', (tester) async {
    await _pumpDialog(tester, posts: [], sent: false);

    // «Ver fotos» es un botón RELLENO (destacado), no un enlace discreto.
    expect(
      find.widgetWithText(FilledButton, 'Ver fotos (2)'),
      findsOneWidget,
    );
    // El estudio también puede elegir/cambiar la selección…
    expect(find.text('Cambiar fotos'), findsOneWidget);
    // …y avisar al cliente desde el mismo bloque.
    expect(find.text('Avisar al cliente'), findsOneWidget);
    // Sin envío no hay nada que reabrir.
    expect(find.text('Reabrir envío'), findsNothing);

    await _tap(tester, find.text('Ver fotos (2)'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('con el envío hecho, en su lugar aparece «Reabrir envío» y '
      'reabre el envío', (tester) async {
    final posts = <Map<String, dynamic>>[];
    await _pumpDialog(tester, posts: posts, sent: true);

    expect(find.text('Reabrir envío'), findsOneWidget);
    expect(find.text('Cambiar fotos'), findsNothing);
    expect(find.text('Enviadas'), findsOneWidget);
    // Las fotos se pueden VER igual.
    expect(find.text('Ver fotos (2)'), findsOneWidget);

    await _tap(tester, find.text('Reabrir envío'));
    // El diálogo de confirmación avisa de lo que va a pasar.
    expect(find.text('¿Reabrir el envío?'), findsOneWidget);
    await _tap(tester, find.text('Reabrir envío').last);

    expect(posts, isNotEmpty);
    final reopen = posts.last;
    expect(reopen['action'], 'reopen');
    expect(reopen['requestId'], 77);
  });
}

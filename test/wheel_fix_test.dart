import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/roles_page.dart';
import 'package:hardstreet_admin/widgets/wheel_fix.dart';

// ==================================================================
// RUEDA SIN SHIFT: HsScrollBehavior traduce eventos de rueda con SOLO
// eje X (dx ≠ 0, dy = 0 — drivers que mandan la rueda vertical en
// horizontal) a avance vertical. Aquí se cubre la página de Roles y su
// diálogo de permisos, con la MISMA behavior que usa la app real.
// ==================================================================

void _installMock() {
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;
    if (path.endsWith('/api/admin/roles')) {
      return http.Response(
        jsonEncode({
          'roles': [
            for (var i = 0; i < 30; i++)
              {
                'id': i + 1,
                'name': 'Rol $i',
                'permissions': [
                  {'moduleId': 1, 'permissionId': 2}
                ],
              },
          ],
        }),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/admin/meta')) {
      return http.Response(
        jsonEncode({
          'modules': [
            for (var i = 0; i < 12; i++)
              {
                'id': i + 1,
                'name': 'Módulo $i',
                'actions': [
                  {'id': 2, 'key': 'read', 'label': 'Ver'},
                  {'id': 3, 'key': 'create', 'label': 'Crear'},
                ],
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

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(1000, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final previous = HsApi.client;
  addTearDown(() => HsApi.client = previous);
  await tester.pumpWidget(MaterialApp(
    // La misma behavior global que usa la app (main.dart).
    scrollBehavior: const HsScrollBehavior(),
    home: Scaffold(body: child),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Máximo desplazamiento entre todos los scrollables vivos.
double _pixels(WidgetTester tester) {
  var best = 0.0;
  for (final s in tester.stateList<ScrollableState>(find.byType(Scrollable))) {
    final p = s.position;
    if (p.pixels > best) best = p.pixels;
  }
  return best;
}

Future<void> _wheel(WidgetTester tester, Offset position, Offset delta,
    {int times = 6}) async {
  for (var i = 0; i < times; i++) {
    await tester.sendEventToBinding(
        PointerScrollEvent(position: position, scrollDelta: delta));
    await tester.pump();
  }
}

void main() {
  testWidgets('regresión: la rueda VERTICAL sigue moviendo la página',
      (tester) async {
    _installMock();
    await _pump(tester, const RolesPage());
    expect(find.text('Rol 0'), findsOneWidget);

    await _wheel(tester, tester.getCenter(find.byType(RolesPage)),
        const Offset(0, 200));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_pixels(tester), greaterThan(0));
  });

  testWidgets('fix: rueda con SOLO eje X mueve la página (sin shift)',
      (tester) async {
    _installMock();
    await _pump(tester, const RolesPage());
    expect(find.text('Rol 0'), findsOneWidget);

    // Misma firma que mandan los drivers problemáticos de Windows.
    await _wheel(tester, tester.getCenter(find.byType(RolesPage)),
        const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_pixels(tester), greaterThan(0));
  });

  testWidgets('fix: rueda con SOLO eje X mueve el diálogo de permisos',
      (tester) async {
    _installMock();
    await _pump(tester, const RolesPage());
    await tester.tap(find.byIcon(Icons.tune).first, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Asignación de acciones por módulo'), findsOneWidget);

    final sc = find.byType(SingleChildScrollView);
    expect(sc, findsWidgets);
    await _wheel(tester, tester.getCenter(sc.first), const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_pixels(tester), greaterThan(0));
  });
}

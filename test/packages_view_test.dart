import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/packages_page.dart';

/// El módulo Paquetes se puede ver de dos formas y las DOS deben mostrar el
/// mismo catálogo: en CARDS (el flyer de la web, por defecto) o en FILAS (más
/// compacto, para comparar). Aquí se comprueba el conmutador y que cada vista
/// pinte de verdad lo suyo.

const _packages = [
  {
    'id': 1,
    'name': 'Boda Full',
    'subtitle': 'Cobertura completa',
    'description': 'Todo el día',
    'price': 25000,
    'currency': 'MXN',
    'tierName': 'Premium',
    'tier': 1,
    'categoryId': 7,
    'categoryName': 'Bodas',
    'serviceNames': ['Cobertura', 'Álbum'],
  },
  {
    'id': 2,
    'name': 'XV Años Gold',
    'subtitle': 'Sesión + video',
    'description': '',
    'price': 18000,
    'currency': 'MXN',
    'tierName': 'Gold',
    'tier': 2,
    'categoryId': 8,
    'categoryName': 'XV Años',
    'serviceNames': ['Cobertura'],
  },
];

void _installMock() {
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;
    if (path.endsWith('/api/admin/packages')) {
      return http.Response(jsonEncode({'packages': _packages}), 200,
          headers: headers);
    }
    if (path.endsWith('/api/tiers')) {
      return http.Response(
        jsonEncode({
          'tiers': [
            {'id': 1, 'name': 'Premium', 'tier': 1},
            {'id': 2, 'name': 'Gold', 'tier': 2},
          ],
        }),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/categories')) {
      return http.Response(
        jsonEncode({
          'categories': [
            {'id': 7, 'name': 'Bodas', 'icon': ''},
            {'id': 8, 'name': 'XV Años', 'icon': ''},
          ],
        }),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/services')) {
      return http.Response(jsonEncode({'services': []}), 200, headers: headers);
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1240, 1000);
  await tester.binding.setSurfaceSize(const Size(1240, 1000));
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final previous = HsApi.client;
  _installMock();
  addTearDown(() => HsApi.client = previous);

  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: PackagesPage())),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Cambia de vista con el botón del encabezado del listado.
Future<void> _toggle(WidgetTester tester) async {
  final button = find.byIcon(
    find.byIcon(Icons.view_list_rounded).evaluate().isNotEmpty
        ? Icons.view_list_rounded
        : Icons.grid_view_rounded,
  );
  expect(button, findsOneWidget);
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('por defecto el catálogo se ve en CARDS (el flyer de la web)',
      (tester) async {
    await _pump(tester);

    expect(find.text('Boda Full'), findsOneWidget);
    expect(find.text('XV Años Gold'), findsOneWidget);
    // El card trae su botón dorado "PERSONALIZAR" y el precio del flyer.
    expect(find.text('PERSONALIZAR'), findsNWidgets(2));
    expect(find.text('Desde'), findsNWidgets(2));
    // El conmutador ofrece pasar a filas.
    expect(find.byIcon(Icons.view_list_rounded), findsOneWidget);
  });

  testWidgets('el conmutador cambia a FILAS y vuelve, sin perder el catálogo',
      (tester) async {
    await _pump(tester);
    expect(find.text('PERSONALIZAR'), findsNWidgets(2));

    await _toggle(tester);

    // Vista de filas: mismo catálogo, presentación compacta (sin CTA grande).
    expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
    expect(find.text('PERSONALIZAR'), findsNothing);
    expect(find.text('Boda Full'), findsOneWidget);
    expect(find.text('XV Años Gold'), findsOneWidget);
    expect(find.text('PREMIUM'), findsOneWidget);   // badge del tier
    expect(find.text('BODAS'), findsOneWidget);     // categoría
    expect(find.text('2'), findsWidgets);           // servicios incluidos
    expect(find.textContaining('servicio'), findsWidgets);

    // Y se puede volver a los cards.
    await _toggle(tester);
    expect(find.byIcon(Icons.view_list_rounded), findsOneWidget);
    expect(find.text('PERSONALIZAR'), findsNWidgets(2));
  });

  testWidgets('el buscador sigue filtrando en la vista de filas',
      (tester) async {
    await _pump(tester);
    await _toggle(tester);

    await tester.enterText(find.byType(TextField).first, 'XV');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('XV Años Gold'), findsOneWidget);
    expect(find.text('Boda Full'), findsNothing);
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/packages_page.dart';

/// Catálogo falso para el módulo Paquetes (con tiers y categorías).
void _installMock({required List<Map<String, dynamic>> posts}) {
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;

    if (path.endsWith('/api/admin/packages')) {
      if (request.method == 'GET') {
        return http.Response(jsonEncode({'packages': []}), 200,
            headers: headers);
      }
      posts.add((jsonDecode(request.body) as Map).cast<String, dynamic>());
      return http.Response(jsonEncode({'ok': true}), 201, headers: headers);
    }
    if (path.endsWith('/api/tiers')) {
      return http.Response(
        jsonEncode({
          'tiers': [
            {'id': 1, 'name': 'Premium', 'tier': 1},
            {'id': 2, 'name': 'Gold', 'tier': 2},
            {'id': 3, 'name': 'Basic', 'tier': 3},
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
          ],
        }),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/services')) {
      return http.Response(
        jsonEncode({
          'services': [
            {
              'id': 1,
              'name': 'Cobertura',
              'description': 'Todo el evento',
              'icon': 'material:videocam',
              'url': '',
            },
            {
              'id': 2,
              'name': 'Álbum',
              'description': '100 fotos editadas',
              'icon': 'material:photo_library',
              'url': '',
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
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final previous = HsApi.client;
  _installMock(posts: []);
  addTearDown(() => HsApi.client = previous);

  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: PackagesPage())),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _openForm(WidgetTester tester) async {
  await _tap(tester, find.text('Nuevo paquete'));
}

void main() {
  testWidgets('el diálogo de paquete tiene pestañas Datos y Servicios',
      (tester) async {
    await _pumpPage(tester);
    await _openForm(tester);

    // Botón del módulo + título del diálogo.
    expect(find.text('Nuevo paquete'), findsNWidgets(2));
    expect(find.text('Crear paquete'), findsOneWidget);
    expect(find.text('Datos'), findsOneWidget);
    expect(find.text('Servicios'), findsOneWidget);

    // La pestaña Servicios lista el catálogo como en el administrador.
    await _tap(tester, find.text('Servicios'));
    expect(find.text('Cobertura'), findsOneWidget);
    expect(find.text('Álbum'), findsOneWidget);
    expect(find.text('0 de 2 seleccionados'), findsOneWidget);

    await _tap(tester, find.text('Cobertura'));
    expect(find.text('1 de 2 seleccionados'), findsOneWidget);
    // El contador también se marca en la pestaña.
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('crear paquete manda los servicios seleccionados',
      (tester) async {
    final posts = <Map<String, dynamic>>[];
    await _pumpPage(tester);
    final previous = HsApi.client;
    _installMock(posts: posts);
    addTearDown(() => HsApi.client = previous);
    await _openForm(tester);

    // Datos: nombre, tier y categoría.
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre'),
      'Boda Full',
    );
    await _tap(tester, find.byType(DropdownButtonFormField<int>).first);
    // El menú del dropdown puede pintar la etiqueta más de una vez: se toma
    // la última (la del menú desplegado).
    await _tap(tester, find.text('Gold').last);
    final dropdowns = find.byType(DropdownButtonFormField<int>);
    await tester.ensureVisible(dropdowns.at(1));
    await tester.pump();
    await tester.tap(dropdowns.at(1), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _tap(tester, find.text('Bodas').last);

    // Servicios: los dos incluidos.
    await _tap(tester, find.text('Servicios'));
    await _tap(tester, find.text('Cobertura'));
    await _tap(tester, find.text('Álbum'));
    await _tap(tester, find.text('Crear paquete'));

    final create = posts.where((p) => p['name'] == 'Boda Full').toList();
    expect(create, hasLength(1));
    expect(create.first['id_tier'], 2);
    expect(create.first['id_package_category'], 7);
    expect((create.first['serviceIds'] as List).toList(), [1, 2]);
  });

  testWidgets('si falta un dato de la pestaña Datos, el guardado regresa a '
      'ella con el motivo', (tester) async {
    await _pumpPage(tester);
    await _openForm(tester);

    await _tap(tester, find.text('Servicios'));
    await _tap(tester, find.text('Crear paquete'));

    expect(find.text('Escribe el nombre del paquete'), findsOneWidget);
  });
}

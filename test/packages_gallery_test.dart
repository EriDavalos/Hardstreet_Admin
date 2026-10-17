import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/packages_page.dart';
import 'package:hardstreet_admin/widgets/drive_thumb.dart';

// ==================================================================
// HARD STREET ADMIN — Módulo PAQUETES: la galería de categorías
// ==================================================================
// El módulo abre en la GALERÍA: los cards de las categorías del catálogo, cada
// uno con la foto que lo representa, cuántos paquetes tiene y desde qué precio
// salen. De ahí se entra a los paquetes (de una categoría o de todo el
// catálogo) SIN salir del módulo y SIN modal, y desde la galería se pueden
// CREAR categorías.
//
// Lo que se comprueba aquí:
//
//   * la galería es el arranque (y ya no hay tarjeta "Destacada");
//   * cada portada enseña la FOTO que la representa (o su emoji), con la misma
//     miniatura del drive que el resto del panel (w=640 + token);
//   * abrir una categoría muestra SUS paquetes con la MISMA tarjeta del
//     catálogo, editables, y se puede volver a la galería;
//   * "Todo el catálogo" muestra todos los paquetes;
//   * "Nueva categoría" crea la categoría de verdad (POST /api/admin/categories).
// ==================================================================

const _photoA =
    'https://oriongo.ddns.net/files/Boda/Ana/Fiesta/IMG_3196 Mejorado.jpg';

const _packages = [
  {
    'id': 1,
    'name': 'Boda Premium',
    'subtitle': 'Cobertura completa',
    'price': 25000,
    'currency': 'MXN',
    'tierName': 'Premium',
    'categoryId': 1,
    'categoryName': 'Boda',
    'serviceNames': ['Cobertura'],
    'urlImage': _photoA,
  },
  {
    'id': 2,
    'name': 'Boda Basic',
    'subtitle': 'Lo esencial',
    'price': 12000,
    'currency': 'MXN',
    'tierName': 'Basic',
    'categoryId': 1,
    'categoryName': 'Boda',
    'serviceNames': ['Cobertura'],
    'urlImage': '',
  },
  {
    'id': 3,
    'name': 'XV Años Gold',
    'subtitle': 'Sesión + video',
    'price': 18000,
    'currency': 'MXN',
    'tierName': 'Gold',
    'categoryId': 2,
    'categoryName': 'XV Años',
    'serviceNames': ['Cobertura'],
    'urlImage': '',
  },
];

final _created = <Map<String, dynamic>>[];

void _installMock() {
  _created.clear();
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;
    if (path.endsWith('/api/admin/categories') && request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      _created.add(body);
      return http.Response(
        jsonEncode({'ok': true, 'message': 'Categoría creada exitosamente'}),
        201,
        headers: headers,
      );
    }
    if (path.endsWith('/api/admin/packages')) {
      return http.Response(
        jsonEncode({'packages': _packages}),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/categories')) {
      return http.Response(
        jsonEncode({
          'categories': [
            {'id': 1, 'name': 'Boda', 'icon': ''},
            {'id': 2, 'name': 'XV Años', 'icon': ''},
            {'id': 3, 'name': 'Bautizo', 'icon': ''},
          ],
        }),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/admin/site')) {
      return http.Response(
        jsonEncode({
          'design': {
            'card': {'imageMode': 'top', 'imageHeight': 120},
          },
        }),
        200,
        headers: headers,
      );
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

Future<void> _pump(WidgetTester tester) async {
  const size = Size(1240, 1100);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final previous = HsApi.client;
  _installMock();
  addTearDown(() => HsApi.client = previous);

  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: PackagesPage())),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() => HsSession.token = 'token-de-prueba');
  tearDown(() => HsSession.clear());

  testWidgets('el módulo arranca en la GALERÍA de categorías', (tester) async {
    await _pump(tester);

    // Portadas de las categorías del catálogo (con y sin paquetes).
    expect(find.textContaining('BODA'), findsWidgets);
    expect(find.textContaining('XV AÑOS'), findsWidgets);
    expect(find.textContaining('BAUTIZO'), findsWidgets);
    expect(find.text('Sin paquetes todavía'), findsOneWidget);
    // "Todo el catálogo" es la salida para ver todos los paquetes de golpe.
    expect(find.text('TODO EL CATÁLOGO'), findsOneWidget);
    // Cada portada dice cuántos paquetes tiene y desde qué precio salen.
    expect(find.textContaining('2 paquetes'), findsWidgets);
    expect(find.textContaining(r'$12,000'), findsWidgets);
    // Los paquetes NO se ven todavía: primero se elige una categoría.
    expect(find.byType(WebPackageCard), findsNothing);
    // La tarjeta "Destacada" de la galería anterior ya no existe.
    expect(find.text('Destacada'), findsNothing);
    // Y se puede crear una categoría desde aquí.
    expect(find.text('Nueva categoría'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cada portada enseña la FOTO que representa a la categoría', (
    tester,
  ) async {
    await _pump(tester);

    final thumbs = tester
        .widgetList<DriveThumb>(find.byType(DriveThumb))
        .where((t) => t.source.contains('/thumb/'))
        .toList();
    expect(
      thumbs,
      isNotEmpty,
      reason: 'la portada de la categoría se quedó sin foto',
    );
    // La foto es la del paquete que la tiene, pedida al servidor del drive en
    // tamaño de portada y con el token (sin él el servidor responde 403).
    expect(
      thumbs.first.source,
      contains('/thumb/Boda/Ana/Fiesta/IMG_3196%20Mejorado.jpg'),
    );
    expect(thumbs.first.source, contains('w=640'));
    expect(thumbs.first.source, contains('apikey=token-de-prueba'));
  });

  testWidgets('abrir una categoría muestra SUS paquetes en el mismo módulo', (
    tester,
  ) async {
    await _pump(tester);

    // La categoría sin paquetes lo explica en vez de quedarse en blanco.
    await _tap(tester, find.textContaining('BAUTIZO'));
    expect(
      find.text('No hay paquetes que coincidan. Crea el primero con el botón '
          '"Nuevo paquete".'),
      findsOneWidget,
    );
    await _tap(tester, find.byIcon(Icons.arrow_back_rounded));
    expect(find.text('TODO EL CATÁLOGO'), findsOneWidget);

    // Ahora la que sí tiene: se ven SUS paquetes con la tarjeta del catálogo.
    await _tap(tester, find.textContaining('BODA').first);
    expect(find.byType(WebPackageCard), findsNWidgets(2));
    expect(find.text('Boda Premium'), findsWidgets);
    expect(find.text('Boda Basic'), findsWidgets);
    // Dentro de una categoría sólo están SUS paquetes…
    expect(find.text('XV Años Gold'), findsNothing);
    // …y se editan como en el catálogo (no es una vista de solo lectura).
    expect(find.text('Editar'), findsNWidgets(2));
    expect(find.text('Nuevo paquete'), findsOneWidget);
    // No hay ningún modal por medio: todo pasa en la misma pantalla.
    expect(find.byType(AlertDialog), findsNothing);
    // Y se puede volver a la galería.
    await _tap(tester, find.byIcon(Icons.arrow_back_rounded));
    expect(find.text('TODO EL CATÁLOGO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Todo el catálogo" muestra todos los paquetes', (tester) async {
    await _pump(tester);

    await _tap(tester, find.text('TODO EL CATÁLOGO'));

    expect(find.byType(WebPackageCard), findsNWidgets(3));
    expect(find.text('Boda Premium'), findsWidgets);
    expect(find.text('XV Años Gold'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el buscador de la galería filtra por categoría o paquete', (
    tester,
  ) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField).first, 'XV');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('XV AÑOS'), findsWidgets);
    expect(find.textContaining('BODA'), findsNothing);
    expect(find.textContaining('BAUTIZO'), findsNothing);

    // Sin resultados, se dice (no una galería vacía sin explicación).
    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Sin resultados'), findsOneWidget);
  });

  testWidgets('se puede CREAR una categoría desde la galería', (tester) async {
    await _pump(tester);

    await _tap(tester, find.text('Nueva categoría'));
    expect(find.text('Nueva categoría'), findsWidgets);

    await tester.enterText(find.byType(TextField).last, 'Bautizo');
    await _tap(tester, find.text('Crear categoría'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(_created, hasLength(1));
    expect(_created.single['name'], 'Bautizo');
    expect(tester.takeException(), isNull);
  });
}

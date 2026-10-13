import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/finance_page.dart';

/// Finanzas falsas: 2 paquetes activos y 2 meses de serie.
/// Totales: ganado 18000, por cobrar 12000, ahorro 3000,
/// gastos 2250 + inversiones 800 => gastado 3050.
void _installMockClient({List<Map<String, dynamic>>? posts}) {
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;

    if (path.endsWith('/api/admin/finance')) {
      if (request.method == 'POST') {
        posts?.add((jsonDecode(request.body) as Map).cast<String, dynamic>());
        return http.Response(jsonEncode({'ok': true, 'id': 1}), 201,
            headers: headers);
      }
      return http.Response(
        jsonEncode({
          'currency': 'MXN',
          'totals': {
            'facturado': 30000,
            'ganancias': 18000,
            'porCobrar': 12000,
            'disponible': 14950,
            'ahorro': 3000,
            'inversiones': 800,
            'gastos': 2250,
            'abonoExterno': 500,
          },
          'packages': [
            {
              'id': 10,
              'name': 'Boda - Premium',
              'clientName': 'Ana Ruiz',
              'currency': 'MXN',
              'price': 12000,
              'paid': 6000,
              'balance': 6000,
              'disponible': 5200,
              'ahorro': 0,
              'gastos': 300,
              'inversiones': 500,
              'abonoExterno': 0,
            },
            {
              'id': 11,
              'name': 'XV Años - Gold',
              'clientName': 'Luis Gómez',
              'currency': 'MXN',
              'price': 18000,
              'paid': 12000,
              'balance': 6000,
              'disponible': 9750,
              'ahorro': 3000,
              'gastos': 1950,
              'inversiones': 300,
              'abonoExterno': 500,
            },
          ],
          'months': [
            {
              'month': '2026-09',
              'label': 'sep',
              'ganancias': 5000,
              'gastos': 400,
              'inversiones': 0,
              'ahorro': 0,
              'abonoExterno': 0,
            },
            {
              'month': '2026-10',
              'label': 'oct',
              'ganancias': 13000,
              'gastos': 1850,
              'inversiones': 800,
              'ahorro': 3000,
              'abonoExterno': 500,
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

Future<void> _pumpFinance(WidgetTester tester, Size size,
    {List<Map<String, dynamic>>? posts}) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final previous = HsApi.client;
  _installMockClient(posts: posts);
  addTearDown(() => HsApi.client = previous);

  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: FinancePage())),
  );
  await tester.pump(); // respuesta simulada
  await tester.pump(const Duration(milliseconds: 700)); // animaciones
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Botón del diálogo (evita el "Abonar" de la tarjeta de ahorro, detrás).
Finder _inDialog(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(text),
    );

void main() {
  testWidgets('Finanzas: cuadros del dinero, gráfica y dinero por paquete',
      (tester) async {
    await _pumpFinance(tester, const Size(1280, 950));

    // El módulo con su resumen del dinero (cuadros HORIZONTALES).
    expect(find.text('Finanzas'), findsOneWidget);
    expect(find.text('Resumen del dinero'), findsOneWidget);
    for (final label in [
      'GANANCIAS',
      'POR COBRAR',
      'DISPONIBLE',
      'AHORRO',
      'INVERSIONES',
      'GASTOS',
      'ABONO EXTERNO',
    ]) {
      expect(find.text(label), findsOneWidget, reason: 'cuadro $label');
    }
    // Los cuadros de una fila comparten altura y no se salen de la pantalla.
    final ganancias = tester.getRect(find.text('GANANCIAS'));
    final porCobrar = tester.getRect(find.text('POR COBRAR'));
    expect((ganancias.top - porCobrar.top).abs(), lessThan(1),
        reason: 'los cuadros están alineados en la misma fila (horizontal)');
    expect(porCobrar.left, greaterThan(ganancias.left));

    // La gráfica de los últimos meses, con su leyenda.
    expect(find.text('Últimos 6 meses'), findsOneWidget);
    expect(find.text('sep'), findsOneWidget);
    expect(find.text('oct'), findsOneWidget);
    expect(find.text('Entró'), findsNothing);
    expect(find.text('Ganancias'), findsOneWidget); // leyenda
    expect(find.text('Ahorro'), findsWidgets);

    // El dinero de cada paquete, con su cliente.
    expect(find.text('Por paquete'), findsOneWidget);
    expect(find.text('Boda - Premium'), findsOneWidget);
    expect(find.text('Ana Ruiz'), findsOneWidget);
    expect(find.text('XV Años - Gold'), findsOneWidget);
    expect(find.text('Luis Gómez'), findsOneWidget);
    // Disponible del primer paquete (5200) y su ganado (6000).
    expect(find.text(r'MXN $5,200'), findsWidgets);
    expect(find.text(r'MXN $6,000'), findsWidgets);

    // La acción principal vive en la cabecera.
    expect(find.text('Abonar al ahorro'), findsOneWidget);
    expect(find.byTooltip('Abonar al ahorro'), findsNWidgets(2));

    expect(tester.takeException(), isNull);
  });

  testWidgets('Finanzas: el ahorro por PORCENTAJE se calcula sobre el '
      'disponible del paquete', (tester) async {
    final posts = <Map<String, dynamic>>[];
    await _pumpFinance(tester, const Size(1280, 950), posts: posts);

    await _tap(tester, find.text('Abonar al ahorro'));
    expect(find.text('Abonar al ahorro'), findsWidgets); // también el título
    expect(find.textContaining('Disponible del paquete'), findsOneWidget);
    expect(_inDialog('Abonar'), findsOneWidget);

    // Porcentaje: 25 % del disponible del paquete elegido (5200) = 1300.
    await _tap(tester, find.text('Porcentaje'));
    await tester.enterText(
        find.widgetWithText(TextField, 'Porcentaje'), '25');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Se ahorrarán'), findsOneWidget);
    expect(find.text(r'MXN $1,300'), findsOneWidget);

    await _tap(tester, _inDialog('Abonar'));

    final saves = posts
        .where((p) => p['purchasedPackageId'] == 10)
        .toList();
    expect(saves, hasLength(1));
    expect(saves.first['amount'], 1300);
    expect(saves.first['description'], '25 % del disponible');
  });

  testWidgets('Finanzas (móvil): se ve ordenado y sin desbordes',
      (tester) async {
    await _pumpFinance(tester, const Size(390, 844));

    expect(find.text('Finanzas'), findsOneWidget);
    expect(find.text('Resumen del dinero'), findsOneWidget);
    expect(find.text('GANANCIAS'), findsOneWidget);
    expect(find.text('Por paquete'), findsOneWidget);
    expect(find.text('Boda - Premium'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}

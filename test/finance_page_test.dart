import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/finance_data.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/finance_page.dart';

/// Finanzas falsas:
///   totales: abonado 18000, gastos 2400, inversión 800, ahorro 3000,
///            abono externo 500, pagos 4000, por cobrar 12000.
///   DINERO ACTUAL = 18000 + 500 - 2400 - 800 - 3000 - 4000 = 8300.
///
/// Trae un paquete GRATIS sin movimientos ("Sesión gratis", debe ocultarse) y
/// uno gratis CON un gasto ("Cortesía con gasto", debe verse).
void _installMockClient({List<Map<String, dynamic>>? posts}) {
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;

    if (path.endsWith('/api/admin/finance')) {
      if (request.method == 'POST') {
        posts?.add((jsonDecode(request.body) as Map).cast<String, dynamic>());
        return http.Response(
          jsonEncode({'ok': true, 'id': 1}),
          201,
          headers: headers,
        );
      }
      return http.Response(
        jsonEncode({
          'currency': 'MXN',
          'totals': {
            'facturado': 30000,
            'ganancias': 18000,
            'porCobrar': 12000,
            'disponible': 8300,
            'ahorro': 3000,
            'inversiones': 800,
            'gastos': 2400,
            'abonoExterno': 500,
            'pagos': 4000,
            'gananciaEstimada': 14700,
            'gananciaReal': 8300,
          },
          'general': {
            'gastos': 900,
            'inversiones': 0,
            'salidas': 900,
            'ahorro': 0,
            'abonoExterno': 0,
            'pagos': 0,
            'neto': -900,
          },
          'packages': [
            {
              'id': 10,
              'name': 'Boda Premium',
              'clientName': 'Ana Ruiz',
              'currency': 'MXN',
              'price': 12000,
              'paid': 6000,
              'balance': 6000,
              'disponible': 2700,
              'ahorro': 0,
              'gastos': 300,
              'inversiones': 500,
              'abonoExterno': 0,
              'pagos': 2500,
            },
            {
              'id': 11,
              'name': 'XV Años Gold',
              'clientName': 'Luis Gómez',
              'currency': 'MXN',
              'price': 18000,
              'paid': 12000,
              'balance': 6000,
              'disponible': 5750,
              'ahorro': 3000,
              'gastos': 1950,
              'inversiones': 300,
              'abonoExterno': 500,
              'pagos': 1500,
            },
            {
              'id': 12,
              'name': 'Sesión gratis',
              'clientName': 'Pablo Sin Pago',
              'currency': 'MXN',
              'price': 0,
              'paid': 0,
              'balance': 0,
              'disponible': 0,
              'ahorro': 0,
              'gastos': 0,
              'inversiones': 0,
              'abonoExterno': 0,
              'pagos': 0,
            },
            {
              'id': 13,
              'name': 'Cortesía con gasto',
              'clientName': 'Marta Cortés',
              'currency': 'MXN',
              'price': 0,
              'paid': 0,
              'balance': 0,
              'disponible': -150,
              'ahorro': 0,
              'gastos': 150,
              'inversiones': 0,
              'abonoExterno': 0,
              'pagos': 0,
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
              'gastos': 2000,
              'inversiones': 800,
              'ahorro': 3000,
              'abonoExterno': 500,
            },
          ],
          'payees': [
            {
              'userId': 7,
              'name': 'Carla Méndez',
              'roleName': 'Colaboradora',
              'total': 2500,
              'count': 1,
              'packageCount': 1,
              'lastPaid': '2026-10-09T10:00:00',
            },
            {
              'userId': 8,
              'name': 'Jorge Ruiz',
              'roleName': 'Empleado',
              'total': 1500,
              'count': 1,
              'packageCount': 1,
              'lastPaid': '2026-10-08T12:00:00',
            },
          ],
          'payments': [
            {
              'id': 20,
              'userId': 7,
              'userName': 'Carla Méndez',
              'roleName': 'Colaboradora',
              'packageId': 10,
              'packageName': 'Boda Premium',
              'clientName': 'Ana Ruiz',
              'amount': 2500,
              'description': 'Pago a Carla Méndez',
              'created': '2026-10-09T10:00:00',
            },
            {
              'id': 21,
              'userId': 8,
              'userName': 'Jorge Ruiz',
              'roleName': 'Empleado',
              'packageId': 11,
              'packageName': 'XV Años Gold',
              'clientName': 'Luis Gómez',
              'amount': 1500,
              'description': 'Pago a Jorge Ruiz',
              'created': '2026-10-08T12:00:00',
            },
          ],
          'movements': [
            {
              'id': 1,
              'packageId': 10,
              'packageName': 'Boda Premium',
              'clientName': 'Ana Ruiz',
              'kind': 'abono',
              'amount': 6000,
              'description': 'Anticipo',
              'created': '2026-10-02T10:00:00',
            },
            {
              'id': 2,
              'packageId': 11,
              'packageName': 'XV Años Gold',
              'clientName': 'Luis Gómez',
              'kind': 'ahorro',
              'amount': 3000,
              'description': 'Ahorro del mes',
              'created': '2026-10-03T11:00:00',
            },
            {
              'id': 3,
              'packageId': 10,
              'packageName': 'Boda Premium',
              'clientName': 'Ana Ruiz',
              'kind': 'gasto',
              'amount': 300,
              'description': 'Transporte',
              'created': '2026-10-04T12:00:00',
            },
            {
              'id': 20,
              'packageId': 10,
              'packageName': 'Boda Premium',
              'clientName': 'Ana Ruiz',
              'kind': 'pago',
              'amount': 2500,
              'description': 'Pago a Carla Méndez',
              'created': '2026-10-09T10:00:00',
              'userId': 7,
              'userName': 'Carla Méndez',
            },
            {
              'id': 21,
              'packageId': 11,
              'packageName': 'XV Años Gold',
              'clientName': 'Luis Gómez',
              'kind': 'pago',
              'amount': 1500,
              'description': 'Pago a Jorge Ruiz',
              'created': '2026-10-08T12:00:00',
              'userId': 8,
              'userName': 'Jorge Ruiz',
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

Future<void> _pumpFinance(
  WidgetTester tester,
  Size size, {
  List<Map<String, dynamic>>? posts,
}) async {
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

Future<void> _openTab(WidgetTester tester, int index) =>
    _tap(tester, find.byKey(ValueKey('finance-tab-$index')));

/// Textos de UNA línea dentro de [wanted] que NO caben en su celda (se
/// dibujarían con puntos suspensivos).
List<String> _clippedOneLineTexts(WidgetTester tester, Set<String> wanted) {
  final out = <String>{};
  for (final p in tester.allRenderObjects.whereType<RenderParagraph>()) {
    final text = p.text.toPlainText();
    if (!wanted.contains(text)) continue;
    if (p.size.height > 24) continue; // envuelve a dos líneas
    if (p.getMaxIntrinsicWidth(p.size.height) > p.size.width + 0.5) {
      out.add(text);
    }
  }
  return out.toList()..sort();
}

void main() {
  group('FinanceData', () {
    test('oculta los paquetes gratis SIN movimientos', () {
      final data = FinanceData.fromJson({
        'packages': [
          {'id': 1, 'name': 'Gratis vacío', 'price': 0},
          {
            'id': 2,
            'name': 'Gratis con gasto',
            'price': 0,
            'gastos': 150,
          },
          {'id': 3, 'name': 'De pago', 'price': 9000, 'paid': 0},
        ],
      });
      expect(data.packages.map((p) => p.id), [2, 3]);
    });

    test('calcula el dinero actual con los pagos incluidos', () {
      final totals = FinanceTotals.fromJson({
        'ganancias': 1000,
        'gastos': 100,
        'inversiones': 50,
        'ahorro': 200,
        'abonoExterno': 40,
        'pagos': 300,
      });
      // 1000 + 40 - 50 - 200 = 790 estimada; 790 - 100 - 300 = 390 actual.
      expect(totals.gananciaEstimada, 790);
      expect(totals.gananciaReal, 390);
      expect(totals.dineroActual, 390);
    });

    test('deriva los pagos por persona de un backend viejo', () {
      final data = FinanceData.fromJson({
        'movements': [
          {
            'id': 1,
            'kind': 'pago',
            'amount': 500,
            'userId': 4,
            'userName': 'Ana',
            'packageId': 9,
            'packageName': 'Boda',
            'created': '2026-10-01T09:00:00',
          },
          {
            'id': 2,
            'kind': 'pago',
            'amount': 300,
            'userId': 4,
            'userName': 'Ana',
            'packageId': 8,
            'packageName': 'XV',
            'created': '2026-10-02T09:00:00',
          },
        ],
      });
      expect(data.payments, hasLength(2));
      expect(data.payees, hasLength(1));
      expect(data.payees.first.name, 'Ana');
      expect(data.payees.first.total, 800);
      expect(data.payees.first.packageCount, 2);
      expect(data.totalPagos, 800);
    });
  });

  testWidgets('Resumen: dinero actual, tabla de conceptos y gráfica', (
    tester,
  ) async {
    await _pumpFinance(tester, const Size(1280, 1100));

    expect(find.text('Finanzas'), findsOneWidget);
    for (final tab in ['Resumen', 'Por paquete', 'Pagos']) {
      expect(find.text(tab), findsWidgets, reason: 'pestaña $tab');
    }

    // DINERO ACTUAL con la fórmula de la petición (incluye pagos).
    expect(find.text('DINERO ACTUAL'), findsWidgets);
    expect(find.text(r'MXN $8,300'), findsWidgets);
    expect(
      find.text(
        'Abonado + abono externo − gastos − inversión − ahorro − pagos',
      ),
      findsOneWidget,
    );

    // La tabla con TODOS los conceptos pedidos.
    expect(find.text('Movimiento del dinero'), findsOneWidget);
    for (final label in [
      'Abonado',
      'Abono externo',
      'Gastos',
      'Inversión',
      'Ahorro',
      'Pagos',
      'Por cobrar',
    ]) {
      expect(find.text(label), findsWidgets, reason: 'concepto $label');
    }
    // Montos de cada concepto.
    for (final amount in [
      r'MXN $18,000', // abonado
      r'MXN $500', // abono externo
      r'MXN $2,400', // gastos
      r'MXN $800', // inversión
      r'MXN $3,000', // ahorro
      r'MXN $4,000', // pagos
      r'MXN $12,000', // por cobrar
    ]) {
      expect(find.text(amount), findsWidgets, reason: 'monto $amount');
    }

    // Gráfica y movimientos recientes.
    expect(find.text('Últimos 6 meses'), findsOneWidget);
    expect(find.text('sep'), findsOneWidget);
    expect(find.text('oct'), findsOneWidget);
    expect(find.text('Movimientos recientes'), findsOneWidget);
    expect(find.textContaining('Pago a Carla Méndez'), findsWidgets);

    // El título viejo del "ahorro apartado" ya NO existe como separador.
    expect(find.text('Ahorro apartado'), findsNothing);
    expect(find.text('APARTADO Y PAGOS'), findsNothing);
    expect(find.text('Abonar al ahorro'), findsNothing);

    // La acción de la cabecera.
    expect(find.text('Registrar movimiento'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Por paquete: oculta los gratis vacíos y desglosa cada uno', (
    tester,
  ) async {
    await _pumpFinance(tester, const Size(1280, 1100));

    await _openTab(tester, 1);

    // Columnas de la tabla por paquete.
    for (final col in [
      'PAQUETE',
      'ABONADO',
      'GASTOS',
      'INVERSIÓN',
      'AHORRO',
      'POR COBRAR',
      'EXTERNO',
      'PAGOS',
      'ACTUAL',
    ]) {
      expect(find.text(col), findsOneWidget, reason: 'columna $col');
    }

    // El paquete de pago y el gratis CON gasto se ven…
    expect(find.text('Boda Premium'), findsWidgets);
    expect(find.text('XV Años Gold'), findsWidgets);
    expect(find.text('Cortesía con gasto'), findsWidgets);
    // …y el gratis SIN movimientos no.
    expect(find.text('Sesión gratis'), findsNothing);

    // Se expande un paquete: su desglose, sus movimientos y sus acciones.
    expect(find.text('MOVIMIENTOS DEL PAQUETE'), findsNothing);
    await _tap(tester, find.text('Boda Premium').first);
    expect(find.text('MOVIMIENTOS DEL PAQUETE'), findsOneWidget);
    expect(find.textContaining('Anticipo'), findsOneWidget);
    expect(find.textContaining('Pago a Carla Méndez'), findsWidgets);
    expect(find.text('Abonar al ahorro'), findsOneWidget);

    // La búsqueda filtra la tabla.
    await tester.enterText(
      find.widgetWithText(TextField, 'Buscar paquete o cliente…'),
      'XV',
    );
    await tester.pump();
    expect(find.text('XV Años Gold'), findsWidgets);
    expect(find.text('Cortesía con gasto'), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Pagos: total por persona y desglose de cada pago', (
    tester,
  ) async {
    await _pumpFinance(tester, const Size(1280, 1100));

    await _openTab(tester, 2);

    expect(find.text('TOTAL PAGADO A PERSONAS'), findsOneWidget);
    expect(find.text(r'MXN $4,000'), findsWidgets);
    expect(find.text('En 2 personas'), findsOneWidget);

    // Cada persona con su rol, su total y su conteo.
    expect(find.text('Carla Méndez'), findsWidgets);
    expect(find.text('Jorge Ruiz'), findsWidgets);
    expect(find.textContaining('Colaboradora'), findsOneWidget);
    expect(find.textContaining('Empleado'), findsOneWidget);
    expect(find.text(r'MXN $2,500'), findsWidgets);
    expect(find.text(r'MXN $1,500'), findsWidgets);

    // Se desglosa una persona: sus pagos individuales.
    expect(find.text('PAGOS RECIBIDOS'), findsNothing);
    await _tap(tester, find.text('Carla Méndez').first);
    expect(find.text('PAGOS RECIBIDOS'), findsOneWidget);
    expect(find.textContaining('Boda Premium · Ana Ruiz'), findsOneWidget);
    expect(find.textContaining('09/10/2026'), findsWidgets);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Registrar movimiento: general, con Gastos por defecto', (
    tester,
  ) async {
    final posts = <Map<String, dynamic>>[];
    await _pumpFinance(tester, const Size(1280, 1100), posts: posts);

    await _tap(tester, find.text('Registrar movimiento'));
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining('Movimiento GENERAL'),
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.descendant(of: dialog, matching: find.widgetWithText(TextField, 'Monto')),
      '450',
    );
    await tester.pump();
    await _tap(
      tester,
      find.descendant(of: dialog, matching: find.text('Registrar')),
    );

    expect(posts, hasLength(1));
    expect(posts.first['kind'], 'gasto');
    expect(posts.first['amount'], 450);
    expect(
      posts.first.containsKey('purchasedPackageId'),
      isFalse,
      reason: 'un movimiento general no manda paquete',
    );
  });

  testWidgets('Ahorro por porcentaje: se calcula sobre el DINERO ACTUAL', (
    tester,
  ) async {
    final posts = <Map<String, dynamic>>[];
    await _pumpFinance(tester, const Size(1280, 1100), posts: posts);

    await _tap(tester, find.text('Registrar movimiento'));
    final dialog = find.byType(AlertDialog);

    // Se elige AHORRO y el modo porcentaje.
    await _tap(
      tester,
      find.descendant(of: dialog, matching: find.text('Ahorro')),
    );
    await _tap(
      tester,
      find.descendant(of: dialog, matching: find.text('Porcentaje')),
    );
    await tester.enterText(
      find.descendant(
        of: dialog,
        matching: find.widgetWithText(TextField, 'Porcentaje'),
      ),
      '25',
    );
    await tester.pump(const Duration(milliseconds: 200));

    // 25 % de 8300 = 2075. Sin paquete, la base es el negocio entero.
    expect(find.text('Se ahorrarán del negocio'), findsOneWidget);
    expect(find.text(r'MXN $2,075'), findsWidgets);

    await _tap(
      tester,
      find.descendant(of: dialog, matching: find.text('Abonar')),
    );
    expect(posts, hasLength(1));
    expect(posts.first['kind'], 'ahorro');
    expect(posts.first['amount'], 2075);
  });

  testWidgets('Móvil: pestañas, tabla y pagos sin desbordes ni recortes', (
    tester,
  ) async {
    await _pumpFinance(tester, const Size(390, 844));

    expect(find.text('Finanzas'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('finance-tab-0')));
    expect(find.text('DINERO ACTUAL'), findsWidgets);
    expect(find.text('Movimiento del dinero'), findsOneWidget);

    final clipped = _clippedOneLineTexts(tester, {
      'DINERO ACTUAL',
      'Abonado',
      'Abono externo',
      'Gastos',
      'Inversión',
      'Ahorro',
      'Pagos',
      'Por cobrar',
      'Resumen',
      'Por paquete',
    });
    expect(clipped, isEmpty, reason: 'textos cortados en el teléfono: $clipped');

    // Pestaña por paquete: tarjetas (no tabla ancha) y sin desbordes.
    await _openTab(tester, 1);
    expect(find.text('Boda Premium'), findsWidgets);
    expect(find.text('Sesión gratis'), findsNothing);
    expect(tester.takeException(), isNull);

    // Pestaña de pagos.
    await _openTab(tester, 2);
    expect(find.text('Carla Méndez'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

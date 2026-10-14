import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/finance_page.dart';

/// Finanzas falsas: 2 paquetes activos, 2 meses de serie y 3 movimientos.
/// Totales: cobrado 18000, por cobrar 12000, ahorro 3000,
/// gastos 2250 + inversiones 800 => salidas 3050.
void _installMockClient({List<Map<String, dynamic>>? posts, bool general = false}) {
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
          if (general)
            'general': {
              'gastos': 900,
              'inversiones': 0,
              'salidas': 900,
              'ahorro': 0,
              'abonoExterno': 0,
              'neto': -900,
            },
          'movements': [
            if (general)
              {
                'id': 9,
                'packageId': 0,
                'packageName': '',
                'clientName': '',
                'kind': 'gasto',
                'amount': 900,
                'description': 'Renta del estudio',
                'created': '2026-10-05T09:00:00',
              },
            {
              'id': 1,
              'packageId': 10,
              'packageName': 'Boda - Premium',
              'clientName': 'Ana Ruiz',
              'kind': 'abono',
              'amount': 6000,
              'description': 'Anticipo',
              'created': '2026-10-02T10:00:00',
            },
            {
              'id': 2,
              'packageId': 11,
              'packageName': 'XV Años - Gold',
              'clientName': 'Luis Gómez',
              'kind': 'ahorro',
              'amount': 3000,
              'description': 'Ahorro del mes',
              'created': '2026-10-03T11:00:00',
            },
            {
              'id': 3,
              'packageId': 10,
              'packageName': 'Boda - Premium',
              'clientName': 'Ana Ruiz',
              'kind': 'gasto',
              'amount': 300,
              'description': 'Transporte',
              'created': '2026-10-04T12:00:00',
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
    {List<Map<String, dynamic>>? posts, bool general = false}) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final previous = HsApi.client;
  _installMockClient(posts: posts, general: general);
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

/// Botón del diálogo (evita los de la página, detrás).
Finder _inDialog(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(text),
    );

/// Textos de UNA línea dentro de [wanted] que NO caben en su celda (se
/// dibujarían con puntos suspensivos). Los de varias líneas envuelven y no
/// se consideran recortados.
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
  testWidgets('Finanzas: totales, tabla de paquetes/movimientos y gráfica',
      (tester) async {
    await _pumpFinance(tester, const Size(1280, 1000));

    // El módulo con su tira de totales (cuadros HORIZONTALES).
    expect(find.text('Finanzas'), findsOneWidget);
    for (final label in [
      'GANADO',
      'COBRADO',
      'POR COBRAR',
      'AHORRO',
      'GASTOS',
      'INVERSIÓN',
      'ABONO EXTERNO',
    ]) {
      // 'AHORRO' también es una columna de la tabla.
      expect(find.text(label), findsWidgets, reason: 'cuadro $label');
    }
    // "Ganado" es el DISPONIBLE de los datos.
    expect(find.text(r'MXN $14,950'), findsWidgets);
    expect(find.text('= Disponible'), findsOneWidget);

    // Los cuadros de una fila comparten altura.
    final ganado = tester.getRect(find.text('GANADO'));
    final cobrado = tester.getRect(find.text('COBRADO'));
    expect((ganado.top - cobrado.top).abs(), lessThan(1),
        reason: 'los cuadros están alineados en la misma fila (horizontal)');
    expect(cobrado.left, greaterThan(ganado.left));

    // La TABLA: encabezado de columnas y de grupos.
    expect(find.text('Dinero por paquete y movimiento'), findsOneWidget);
    for (final col in ['CONCEPTO', 'MONTO', 'SALIDAS']) {
      expect(find.text(col), findsOneWidget, reason: 'columna $col');
    }
    // 'AHORRO' es columna de la tabla Y cuadro de totales.
    expect(find.text('AHORRO'), findsNWidgets(2));
    expect(find.text('PAQUETES'), findsOneWidget);
    expect(find.text('MOVIMIENTOS'), findsOneWidget);

    // Sus paquetes, con su cliente y su disponible (el "ganado").
    expect(find.text('Boda - Premium'), findsWidgets);
    expect(find.text('Ana Ruiz'), findsWidgets);
    expect(find.text('XV Años - Gold'), findsWidgets);
    expect(find.text('Luis Gómez'), findsWidgets);
    expect(find.text(r'MXN $5,200'), findsWidgets);
    expect(find.text(r'MXN $9,750'), findsWidgets);

    // Y las filas de cada tipo de movimiento.
    for (final kind in [
      'Abonos',
      'Gastos',
      'Inversiones',
      'Ahorro',
      'Abonos externos',
    ]) {
      expect(find.text(kind), findsWidgets, reason: 'fila $kind');
    }

    // La gráfica de los últimos meses, con su leyenda.
    expect(find.text('Últimos 6 meses'), findsOneWidget);
    expect(find.text('sep'), findsOneWidget);
    expect(find.text('oct'), findsOneWidget);

    // Las acciones viven en la cabecera.
    expect(find.text('Abonar al ahorro'), findsOneWidget);
    expect(find.text('Agregar movimiento'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Finanzas: la fila de un paquete se EXPANDE con su desglose',
      (tester) async {
    await _pumpFinance(tester, const Size(1280, 1000));

    // Cerrada: el desglose y sus movimientos no están.
    expect(find.textContaining('Ganado (disponible)'), findsNothing);
    expect(find.textContaining('Anticipo'), findsNothing);

    await _tap(tester, find.text('Boda - Premium').first);

    // Abierta: los conceptos del paquete…
    expect(find.textContaining('Ganado (disponible)'), findsOneWidget);
    expect(find.textContaining('Cobrado'), findsOneWidget);
    // ('Abono externo' también es la leyenda de la gráfica.)
    expect(find.textContaining('Abono externo'), findsWidgets);
    // …sus movimientos (abono y gasto del paquete)…
    expect(find.textContaining('Anticipo'), findsOneWidget);
    expect(find.textContaining('Transporte'), findsOneWidget);
    // …y sus acciones.
    expect(find.text('MOVIMIENTOS DEL PAQUETE'), findsOneWidget);
    expect(find.text('Abonar al ahorro'), findsNWidgets(2));

    // Se vuelve a cerrar.
    await _tap(tester, find.text('Boda - Premium').first);
    expect(find.textContaining('Ganado (disponible)'), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Finanzas: cada TIPO de movimiento se desglosa al expandir',
      (tester) async {
    await _pumpFinance(tester, const Size(1280, 1000));

    expect(find.textContaining('Transporte'), findsNothing);

    // La fila "Gastos" lista los gastos registrados.
    await _tap(tester, find.text('Gastos').first);
    expect(find.textContaining('Transporte'), findsOneWidget);
    expect(find.textContaining('Boda - Premium'), findsWidgets);

    // La fila "Ahorro" lista el ahorro apartado.
    await _tap(tester, find.text('Ahorro').first);
    expect(find.textContaining('Ahorro del mes'), findsOneWidget);
    expect(find.textContaining('XV Años - Gold'), findsWidgets);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Finanzas: el ahorro por PORCENTAJE se calcula sobre el '
      'disponible del paquete', (tester) async {
    final posts = <Map<String, dynamic>>[];
    await _pumpFinance(tester, const Size(1280, 1000), posts: posts);

    await _tap(tester, find.text('Abonar al ahorro'));
    expect(find.text('Abonar al ahorro'), findsWidgets); // también el título
    // Por DEFECTO el movimiento es general (ya no obliga a elegir paquete).
    expect(find.textContaining('Disponible general del negocio'), findsOneWidget);
    expect(_inDialog('Abonar'), findsOneWidget);

    // Se elige el paquete en el selector (es opcional).
    await _tap(tester, find.byType(DropdownButton<int>));
    await _tap(tester, find.text('Boda - Premium · Ana Ruiz').last);
    expect(find.textContaining('Disponible del paquete'), findsOneWidget);

    // Porcentaje: 25 % del disponible del paquete elegido (5200) = 1300.
    await _tap(tester, find.text('Porcentaje'));
    await tester.enterText(
        find.widgetWithText(TextField, 'Porcentaje'), '25');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Se ahorrarán'), findsOneWidget);
    expect(find.text(r'MXN $1,300'), findsWidgets);

    await _tap(tester, _inDialog('Abonar'));

    final saves = posts
        .where((p) => p['purchasedPackageId'] == 10)
        .toList();
    expect(saves, hasLength(1));
    expect(saves.first['kind'], 'ahorro');
    expect(saves.first['amount'], 1300);
    expect(saves.first['description'], '25 % del disponible');
  });

  testWidgets('Finanzas: "Agregar movimiento" registra un movimiento '
      'GENERAL (sin pedir paquete)', (tester) async {
    final posts = <Map<String, dynamic>>[];
    await _pumpFinance(tester, const Size(1280, 1000), posts: posts);

    await _tap(tester, find.text('Agregar movimiento'));
    // El diálogo NO obliga a elegir paquete: viene en "General".
    expect(find.textContaining('Disponible general del negocio'), findsOneWidget);
    expect(_inDialog('General (todo el negocio)'), findsOneWidget);

    // Se elige GASTOS y se captura un monto.
    await _tap(tester, _inDialog('Gastos'));
    await tester.enterText(find.widgetWithText(TextField, 'Monto'), '450');
    await tester.pump();
    await _tap(tester, _inDialog('Registrar'));

    expect(posts, hasLength(1));
    expect(posts.first['kind'], 'gasto');
    expect(posts.first['amount'], 450);
    expect(posts.first.containsKey('purchasedPackageId'), isFalse,
        reason: 'un movimiento general no manda paquete');
  });

  testWidgets('Finanzas: el dinero SIN paquete aparece como grupo "General"',
      (tester) async {
    await _pumpFinance(tester, const Size(1280, 1000), general: true);

    // La fila general, con su dinero y su indicador.
    expect(find.text('General (sin paquete)'), findsOneWidget);
    expect(find.textContaining('movimiento'), findsWidgets);

    await _tap(tester, find.text('General (sin paquete)'));
    // Su desglose y sus registros (el que NO pertenece a ningún paquete).
    expect(find.textContaining('Renta del estudio'), findsOneWidget);
    expect(find.text('Agregar movimiento general'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Finanzas (móvil): la tabla se ve ordenada y sin desbordes',
      (tester) async {
    await _pumpFinance(tester, const Size(390, 844));

    expect(find.text('Finanzas'), findsOneWidget);
    expect(find.text('GANADO'), findsOneWidget);
    expect(find.text('Dinero por paquete y movimiento'), findsOneWidget);
    expect(find.text('PAQUETES'), findsOneWidget);
    expect(find.text('Boda - Premium'), findsWidgets);
    expect(find.text('Abonos'), findsWidgets);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Finanzas (móvil): los nombres, montos y cuadros caben ENTEROS',
      (tester) async {
    await _pumpFinance(tester, const Size(390, 844));

    // Nada recortado: los textos de UNA línea deben caber en su celda
    // (los que envuelven varias líneas no cuentan como recortados).
    final clipped = _clippedOneLineTexts(tester, {
      'Boda - Premium',
      'Ana Ruiz',
      'XV Años - Gold',
      'Luis Gómez',
      'GANADO',
      'COBRADO',
      'POR COBRAR',
      'AHORRO',
      'GASTOS',
      'INVERSIÓN',
      'ABONO EXTERNO',
      'Abonos externos',
      'Ahorro apartado',
      'Abonar al ahorro',
      'Nuevo movimiento',
    });
    expect(clipped, isEmpty, reason: 'textos cortados en el teléfono: $clipped');

    // En el teléfono la acción es la versión corta (la larga no cabía).
    expect(find.text('Nuevo movimiento'), findsOneWidget);

    // Las columnas de la tabla se alinean con su encabezado.
    final head = tester.getRect(find.text('CONCEPTO'));
    final monto = tester.getRect(find.text('MONTO'));
    final paquete = tester.getRect(find.text('Boda - Premium').first);
    expect(paquete.left, greaterThanOrEqualTo(head.left - 1),
        reason: 'el concepto arranca bajo su encabezado');
    expect(monto.left, greaterThan(head.left),
        reason: 'MONTO va a la derecha del concepto');

    expect(tester.takeException(), isNull);
  });

  testWidgets('Finanzas (móvil): los totales se DESLIZAN de uno en uno',
      (tester) async {
    await _pumpFinance(tester, const Size(390, 844));

    // El carrusel ocupa el ancho de la pantalla…
    final page = tester.getRect(find.byType(PageView));
    expect(page.width, greaterThan(340));
    // …y se ve UNA tarjeta COMPLETA: la siguiente no asoma a medias.
    expect(find.text('GANADO'), findsOneWidget);
    expect(find.text('COBRADO'), findsNothing);
    expect(find.text('POR COBRAR'), findsNothing);

    // Al deslizar de lado entra la SIGUIENTE y la de antes se va.
    await tester.drag(find.byType(PageView), const Offset(-340, 0));
    await tester.pumpAndSettle();
    expect(find.text('COBRADO'), findsOneWidget);
    expect(find.text('GANADO'), findsNothing);

    // La tarjeta que quedó a la vista no trae nada recortado.
    final clipped = _clippedOneLineTexts(tester, {'COBRADO'});
    expect(clipped, isEmpty, reason: 'etiqueta recortada: $clipped');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Finanzas (móvil): desglose y acciones en UNA fila horizontal',
      (tester) async {
    await _pumpFinance(tester, const Size(390, 844));

    // Las acciones de la página comparten renglón (no una por línea).
    final nuevo = tester.getRect(find.text('Nuevo movimiento'));
    final abonar = tester.getRect(find.text('Abonar al ahorro').first);
    expect((nuevo.top - abonar.top).abs(), lessThan(1),
        reason: 'las acciones de la página van en el mismo renglón');

    // Al expandir un paquete, sus píldoras de desglose también van en fila.
    await _tap(tester, find.text('Boda - Premium').first);
    final cobrado = tester.getRect(find.text('Cobrado '));
    final porCobrar = tester.getRect(find.text('Por cobrar '));
    final ganado = tester.getRect(find.text('Ganado (disponible) '));
    expect((cobrado.top - porCobrar.top).abs(), lessThan(1));
    expect((ganado.top - porCobrar.top).abs(), lessThan(1));
    expect(cobrado.left, lessThan(porCobrar.left));
    expect(porCobrar.left, lessThan(ganado.left));
    expect(tester.takeException(), isNull);
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/drive_api_service.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/admin_pages.dart';

/// Drive remoto de mentira: al tablero solo le interesa el espacio ocupado.
class _FakeApiDrive extends DriveApiService {
  _FakeApiDrive() : super(baseUrl: 'http://127.0.0.1:1');

  @override
  Future<Map<String, dynamic>> fetchSpace() async => {
        'usedBytes': 123456789,
        'totalBytes': 500000000,
        'files': 1204,
        'folders': 88,
      };
}

/// Cliente HTTP falso con el resumen completo (usuarios, clientes, catálogo y
/// una agenda futura) para poder renderizar el Dashboard con datos reales.
void _installMockClient() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final future = now.add(const Duration(days: 3));
  final eventDate =
      '${future.year}-${two(future.month)}-${two(future.day)}T17:30:00';

  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;
    if (path.endsWith('/api/admin/users')) {
      return http.Response(
        jsonEncode({
          'users': [
            {'id': 1, 'name': 'Ana', 'lastname': 'Ruiz', 'role': 'Admin'},
            {'id': 2, 'name': 'Beto', 'lastname': 'Soto', 'role': 'Editor'},
          ]
        }),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/admin/clients')) {
      return http.Response(
        jsonEncode({
          'clients': [
            {
              'id': 7,
              'name': 'Carla',
              'lastname': 'Méndez',
              'email': 'carla@correo.com',
              'packagesCount': 2,
            },
          ]
        }),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/admin/packages')) {
      return http.Response(
        jsonEncode({
          'packages': [
            {'id': 1, 'name': 'Boda Premium', 'price': 12000, 'currency': 'MXN'},
            {'id': 2, 'name': 'Sesión Familiar', 'price': 8500, 'currency': 'MXN'},
          ]
        }),
        200,
        headers: headers,
      );
    }
    // Finanzas del negocio (opcional): cuadros + serie de meses.
    if (path.endsWith('/api/admin/finance')) {
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
          'packages': const [],
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
    if (path.endsWith('/api/admin/agendas')) {
      return http.Response(
        jsonEncode({
          'agendas': [
            {
              'id': 1,
              'purchasedPackageId': 1,
              'userId': 7,
              'clientName': 'Carla Méndez',
              'packageName': 'Boda Premium',
              'serviceId': 5,
              'serviceName': 'Cobertura en evento',
              'eventDate': eventDate,
              'description': 'Ceremonia en el jardín',
            }
          ]
        }),
        200,
        headers: headers,
      );
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

Future<void> _pumpDashboard(WidgetTester tester, Size size,
    {bool withDrive = false}) async {
  await tester.binding.setSurfaceSize(size);
  // MediaQuery NO sigue al tamaño de la superficie: hay que declarar la
  // vista para que el panel vea la MISMA ventana (y elija su acomodo).
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final previous = HsApi.client;
  _installMockClient();
  addTearDown(() => HsApi.client = previous);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DashboardPage(drive: withDrive ? _FakeApiDrive() : null),
      ),
    ),
  );
  await tester.pump(); // respuestas simuladas
  await tester.pump(const Duration(milliseconds: 700)); // animaciones
}

/// Cuánto hay que bajar DENTRO de cada zona con scroll del dashboard.
List<double> _scrollExtents(WidgetTester tester) => [
      for (final s in tester.stateList<ScrollableState>(find.byType(Scrollable)))
        s.position.maxScrollExtent,
    ];

void main() {
  testWidgets('Dashboard (escritorio): resumen ordenado con todas las fuentes',
      (tester) async {
    await _pumpDashboard(tester, const Size(1200, 1000));

    // Secciones en orden.
    expect(find.text('Resumen general'), findsOneWidget);
    expect(find.text('Próximos eventos'), findsOneWidget);
    expect(find.text('Accesos rápidos'), findsOneWidget);
    expect(find.text('Clientes recientes'), findsOneWidget);

    // Sección FINANZAS: cuadros horizontales + gráfica de los últimos meses.
    expect(find.text('Finanzas'), findsNWidgets(2),
        reason: 'encabezado de la sección + acceso rápido');
    expect(find.text('GANANCIAS'), findsOneWidget);
    expect(find.text('AHORRO'), findsOneWidget);
    expect(find.text('Últimos 6 meses'), findsOneWidget);
    // 'sep' solo puede venir de la gráfica; 'oct' también sale en la fecha del
    // evento próximo, así que ahí sí pueden ser varios.
    expect(find.text('sep'), findsOneWidget);
    expect(find.text('oct'), findsWidgets);
    expect(find.text('Ganancias'), findsOneWidget, reason: 'leyenda');

    // Métricas con los datos de la API.
    expect(find.text('2'), findsWidgets); // usuarios internos
    expect(find.text('Clientes'), findsWidgets); // métrica + acceso rápido
    expect(find.textContaining('MXN'), findsWidgets); // valor del catálogo

    // Próximo evento con cliente, servicio y paquete.
    expect(find.text('Carla Méndez'), findsWidgets);
    expect(find.textContaining('Boda Premium'), findsWidgets);
    expect(find.textContaining('Cobertura en evento'), findsWidgets);

    // Accesos rápidos a los módulos.
    expect(find.text('Agendas'), findsOneWidget);
    expect(find.text('Paquetes'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Dashboard (escritorio): NO hay que bajar para verlo todo',
      (tester) async {
    // El tamaño más apretado de una laptop corriente: todo el resumen debe
    // caber SIN scroll de página (ni de sus columnas), con el drive incluido.
    await _pumpDashboard(tester, const Size(1366, 768), withDrive: true);

    expect(find.text('Resumen general'), findsOneWidget);
    expect(find.text('Finanzas'), findsNWidgets(2));
    expect(find.text('Próximos eventos'), findsOneWidget);
    expect(find.text('Accesos rápidos'), findsOneWidget);
    expect(find.text('Carla Méndez'), findsWidgets);
    expect(find.textContaining('archivos'), findsOneWidget,
        reason: 'el espacio del drive va en una línea, sin tarjeta extra');

    final extents = _scrollExtents(tester);
    expect(extents, isNotEmpty);
    expect(
      extents.every((e) => e <= 0.5),
      isTrue,
      reason: 'en 1366x768 nada debería necesitar scroll: $extents',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dashboard (móvil): se ve ordenado y sin desbordes',
      (tester) async {
    await _pumpDashboard(tester, const Size(420, 900));

    expect(find.text('Resumen general'), findsOneWidget);
    expect(find.text('Próximos eventos'), findsOneWidget);
    expect(find.text('Accesos rápidos'), findsOneWidget);
    expect(find.text('Carla Méndez'), findsWidgets);

    // La sección financiera también cabe en el teléfono.
    expect(find.text('Finanzas'), findsWidgets);
    expect(find.text('GANANCIAS'), findsOneWidget);
    expect(find.text('Últimos 6 meses'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}

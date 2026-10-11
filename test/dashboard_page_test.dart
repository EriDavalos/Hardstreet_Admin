import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/admin_pages.dart';

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

Future<void> _pumpDashboard(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final previous = HsApi.client;
  _installMockClient();
  addTearDown(() => HsApi.client = previous);

  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: DashboardPage())),
  );
  await tester.pump(); // respuestas simuladas
  await tester.pump(const Duration(milliseconds: 700)); // animaciones
}

void main() {
  testWidgets('Dashboard (escritorio): resumen ordenado con todas las fuentes',
      (tester) async {
    await _pumpDashboard(tester, const Size(1200, 1000));

    // Secciones en orden.
    expect(find.text('Resumen general'), findsOneWidget);
    expect(find.text('Próximos eventos'), findsOneWidget);
    expect(find.text('Accesos rápidos'), findsOneWidget);
    expect(find.text('Clientes recientes'), findsOneWidget);

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

  testWidgets('Dashboard (móvil): se ve ordenado y sin desbordes',
      (tester) async {
    await _pumpDashboard(tester, const Size(420, 900));

    expect(find.text('Resumen general'), findsOneWidget);
    expect(find.text('Próximos eventos'), findsOneWidget);
    expect(find.text('Accesos rápidos'), findsOneWidget);
    expect(find.text('Carla Méndez'), findsWidgets);

    expect(tester.takeException(), isNull);
  });
}

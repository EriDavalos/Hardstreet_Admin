import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/widgets/hs_toast.dart';

/// Instala una respuesta fija para CUALQUIER llamada a la API.
void _mockResponse(int status, Map<String, dynamic> body) {
  final previous = HsApi.client;
  addTearDown(() => HsApi.client = previous);
  HsApi.client = MockClient((_) async => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      ));
}

Future<void> _pumpHost(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) =>
        HsToastHost(child: child ?? const SizedBox.shrink()),
    home: const Scaffold(body: SizedBox.expand()),
  ));
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('crear avisa en verde con el message del backend',
      (tester) async {
    _mockResponse(201, {
      'code': 201,
      'ok': true,
      'message': 'Cliente creado exitosamente',
      'item': {'id': 9, 'name': 'Ana'},
    });
    await _pumpHost(tester);

    await HsApi.createClient({
      'name': 'Ana',
      'email': 'ana@hardstreet.com',
      'password': 'secreta',
    });
    await _settle(tester);

    expect(find.text('Cliente creado exitosamente'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.check_circle_rounded));
    expect(icon.color, const Color(0xFF2F6BFF));
  });

  testWidgets('editar y eliminar también avisan', (tester) async {
    _mockResponse(200, {
      'code': 200,
      'ok': true,
      'message': 'Rol actualizado exitosamente',
      'item': {'id': 3, 'name': 'Empleado'},
    });
    await _pumpHost(tester);

    await HsApi.updateRole({'id': 3, 'name': 'Empleado'});
    await _settle(tester);
    expect(find.text('Rol actualizado exitosamente'), findsOneWidget);
  });

  testWidgets('un error del backend avisa en rojo con message y details',
      (tester) async {
    _mockResponse(403, {
      'code': 403,
      'ok': false,
      'message': 'No tienes permiso para realizar esta acción',
      'details': 'A tu rol le falta el permiso "delete" en el módulo "clientes"',
    });
    await _pumpHost(tester);

    await expectLater(
      HsApi.deleteClient(1),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message',
              'No tienes permiso para realizar esta acción')
          .having((e) => e.details, 'details',
              'A tu rol le falta el permiso "delete" en el módulo "clientes"')
          .having((e) => e.statusCode, 'statusCode', 403)),
    );
    await _settle(tester);

    expect(find.text('No tienes permiso para realizar esta acción'),
        findsOneWidget);
    expect(
      find.text('A tu rol le falta el permiso "delete" en el módulo "clientes"'),
      findsOneWidget,
    );
    final icon = tester.widget<Icon>(find.byIcon(Icons.error_rounded));
    expect(icon.color, const Color(0xFFEF4444));
  });

  testWidgets('un backend viejo (solo `error`) sigue avisando',
      (tester) async {
    _mockResponse(400, {'error': 'El nombre del paquete es obligatorio'});
    await _pumpHost(tester);

    await expectLater(
      HsApi.createPackage({'name': ''}),
      throwsA(isA<ApiException>()),
    );
    await _settle(tester);
    expect(find.text('El nombre del paquete es obligatorio'), findsOneWidget);
  });

  testWidgets('las LECTURAS no disparan notificación', (tester) async {
    _mockResponse(200, {
      'code': 200,
      'ok': true,
      'message': 'Listado cargado',
      'clients': <dynamic>[],
    });
    await _pumpHost(tester);

    await HsApi.clients();
    await _settle(tester);
    expect(find.text('Listado cargado'), findsNothing);
  });

  testWidgets('el login no dispara notificación', (tester) async {
    _mockResponse(200, {
      'code': 200,
      'ok': true,
      'message': 'Sesión iniciada',
      'token': 't',
      'user': {'id': 1, 'name': 'Hardstreet', 'role': 'Admin'},
    });
    await _pumpHost(tester);

    await HsApi.login('admin@hardstreet.com', 'x');
    await _settle(tester);
    expect(find.text('Sesión iniciada'), findsNothing);
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/clients_page.dart';
import 'package:hardstreet_admin/widgets/form_dialog.dart';

/// Catálogo falso con DOS paquetes: así el diálogo tiene que dejar elegir.
const List<Map<String, dynamic>> _catalog = [
  {
    'id': 3,
    'name': 'Boda - Basic',
    'subtitle': 'Cobertura esencial',
    'price': 6500,
    'currency': 'MXN',
  },
  {
    'id': 4,
    'name': 'Boda - Premium',
    'subtitle': 'Cobertura premium',
    'price': 12000,
    'currency': 'MXN',
  },
];

/// Cliente sin paquetes: la vista arranca con el alta desde el catálogo.
void _installMock({required List<Map<String, dynamic>> posts}) {
  final previous = HsApi.client;
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;

    if (path.endsWith('/api/admin/client-packages')) {
      if (request.method == 'POST') {
        posts.add((jsonDecode(request.body) as Map).cast<String, dynamic>());
        return http.Response(
          jsonEncode({
            'ok': true,
            'message': 'Paquete creado y asignado al cliente exitosamente',
            'purchasedPackageId': 2,
            'usersPackageId': 1,
          }),
          201,
          headers: headers,
        );
      }
      return http.Response(
        jsonEncode({'purchasedPackages': [], 'catalog': _catalog}),
        200,
        headers: headers,
      );
    }

    if (path.endsWith('/api/admin/agendas')) {
      return http.Response(
        jsonEncode({'agendas': []}),
        200,
        headers: headers,
      );
    }

    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
  addTearDown(() => HsApi.client = previous);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Abre el administrador del cliente y entra al alta desde el catálogo.
Future<void> _openAssign(
  WidgetTester tester, {
  required List<Map<String, dynamic>> posts,
  Size size = const Size(1200, 900),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  _installMock(posts: posts);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ClientPackagesDialog(
          client: const {'id': 7, 'name': 'Ana', 'lastname': 'Ruiz'},
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  await _tap(tester, find.text('Asignar del catálogo').first);
  expect(find.text('Asignar paquete'), findsWidgets);
}

/// Botón del formulario del alta (el de la pregunta y el del precio tienen
/// otros rótulos/llaves).
Finder get _saveButton => find.widgetWithText(FilledButton, 'Asignar paquete');

Finder get _acceptButton => find.byKey(const ValueKey('assign-price-keep'));
Finder get _changeButton => find.byKey(const ValueKey('assign-price-change'));
Finder get _cancelButton => find.byKey(const ValueKey('assign-price-cancel'));
Finder get _priceField => find.byKey(const ValueKey('assign-price-field'));

void main() {
  testWidgets('la vista lista los paquetes en tarjetas compactas con su precio', (
    tester,
  ) async {
    await _openAssign(tester, posts: []);

    // Todas las tarjetas del catálogo, con su precio.
    expect(find.text('Boda - Basic'), findsOneWidget);
    expect(find.text('Cobertura esencial'), findsOneWidget);
    expect(find.text('Boda - Premium'), findsOneWidget);
    expect(find.text('MXN \$6,500'), findsOneWidget);
    expect(find.text('MXN \$12,000'), findsOneWidget);

    // Sin paquete elegido todavía no se decide el precio: solo se avisa que
    // al asignar se preguntará.
    expect(find.text('¿Quieres mantener el precio?'), findsNothing);
    expect(
      find.textContaining('Al asignar te preguntaremos si lo mantienes'),
      findsNothing,
    );

    await _tap(tester, find.byKey(const ValueKey('assign-pkg-3')));

    // Elegido: se explica el precio del catálogo y que se preguntará por él.
    expect(
      find.textContaining('Precio del catálogo: MXN \$6,500'),
      findsOneWidget,
    );
    expect(_priceField, findsNothing);
  });

  testWidgets('mantener el precio: la pregunta sale antes de asignar y '
      'Aceptar asigna SIN precio especial', (tester) async {
    final posts = <Map<String, dynamic>>[];
    await _openAssign(tester, posts: posts);

    await _tap(tester, find.byKey(const ValueKey('assign-pkg-3')));
    // Todavía no se llamó a la API: primero se pregunta.
    expect(posts, isEmpty);

    await _tap(tester, _saveButton);
    expect(find.text('¿Quieres mantener el precio?'), findsOneWidget);
    expect(find.text('Aceptar'), findsOneWidget);
    expect(find.text('Cambiar'), findsOneWidget);
    expect(posts, isEmpty);

    await _tap(tester, _acceptButton);
    await tester.pump(const Duration(milliseconds: 400));

    expect(posts, hasLength(1));
    expect(posts.first['userId'], 7);
    expect(posts.first['packageId'], 3);
    // Sin precio: el backend usa el del catálogo (no se toca el catálogo).
    expect(posts.first.containsKey('price'), isFalse);
  });

  testWidgets('cancelar la pregunta no asigna nada', (tester) async {
    final posts = <Map<String, dynamic>>[];
    await _openAssign(tester, posts: posts);

    await _tap(tester, find.byKey(const ValueKey('assign-pkg-3')));
    await _tap(tester, _saveButton);
    await _tap(tester, _cancelButton);

    expect(find.text('¿Quieres mantener el precio?'), findsNothing);
    expect(posts, isEmpty);
    // El alta sigue abierta para reintentar.
    expect(_saveButton, findsOneWidget);
  });

  testWidgets('cambiar el precio: el campo llega precargado y manda el '
      'precio especial solo de esta asignación', (tester) async {
    final posts = <Map<String, dynamic>>[];
    await _openAssign(tester, posts: posts);

    await _tap(tester, find.byKey(const ValueKey('assign-pkg-3')));
    await _tap(tester, _saveButton);
    await _tap(tester, _changeButton);

    expect(_priceField, findsOneWidget);
    // Llega precargado con el del catálogo, listo para editar.
    expect(tester.widget<TextField>(_priceField).controller?.text, '6500');

    await tester.enterText(_priceField, '5000');
    await tester.pump();

    // El resumen avisa cuánto baja contra el catálogo.
    expect(find.text('MXN \$5,000'), findsOneWidget);
    expect(find.textContaining('vs catálogo'), findsOneWidget);

    await _tap(tester, find.widgetWithText(FilledButton, 'Asignar'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(posts, hasLength(1));
    expect(posts.first['packageId'], 3);
    expect(posts.first['price'], 5000);
  });

  testWidgets('precio 0 asigna el paquete como GRATUITO', (tester) async {
    final posts = <Map<String, dynamic>>[];
    await _openAssign(tester, posts: posts);

    await _tap(tester, find.byKey(const ValueKey('assign-pkg-4')));
    await _tap(tester, _saveButton);
    await _tap(tester, _changeButton);

    await tester.enterText(_priceField, '0');
    await tester.pump();

    // El resumen lo dice con todas sus letras.
    expect(find.text('Gratuito'), findsOneWidget);
    expect(find.text('GRATIS'), findsOneWidget);

    await _tap(tester, find.widgetWithText(FilledButton, 'Asignar'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(posts, hasLength(1));
    expect(posts.first['packageId'], 4);
    // 0 viaja tal cual: el backend guarda la compra en cero.
    expect(posts.first['price'], 0);
  });

  testWidgets('valida el paquete elegido y que el precio no sea negativo', (
    tester,
  ) async {
    final posts = <Map<String, dynamic>>[];
    await _openAssign(tester, posts: posts);

    // Sin elegir paquete no hay nada que asignar (ni pregunta).
    await _tap(tester, _saveButton);
    expect(find.text('Elige el paquete que vas a asignar'), findsOneWidget);
    expect(find.text('¿Quieres mantener el precio?'), findsNothing);
    expect(posts, isEmpty);

    await _tap(tester, find.byKey(const ValueKey('assign-pkg-4')));
    await _tap(tester, _saveButton);
    await _tap(tester, _changeButton);
    await tester.enterText(_priceField, '-50');
    await tester.pump();
    await _tap(tester, find.widgetWithText(FilledButton, 'Asignar'));

    expect(find.text('El precio no puede ser negativo'), findsOneWidget);
    expect(posts, isEmpty);
  });

  testWidgets('en el teléfono las tarjetas se acomodan sin desbordar', (
    tester,
  ) async {
    final posts = <Map<String, dynamic>>[];
    await _openAssign(tester, posts: posts, size: const Size(430, 760));

    // Un desbordamiento de layout hace fallar el test automáticamente.
    await _tap(tester, find.byKey(const ValueKey('assign-pkg-4')));
    expect(
      find.textContaining('Precio del catálogo: MXN \$12,000'),
      findsOneWidget,
    );
    await _tap(tester, _saveButton);
    expect(find.text('¿Quieres mantener el precio?'), findsOneWidget);
    await _tap(tester, _changeButton);
    expect(_priceField, findsOneWidget);
  });

  testWidgets('con un solo paquete en el catálogo ya viene elegido', (
    tester,
  ) async {
    // El catálogo con un solo paquete evita un toque de más.
    final posts = <Map<String, dynamic>>[];
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final previous = HsApi.client;
    HsApi.client = MockClient((request) async {
      final headers = {'content-type': 'application/json'};
      if (request.method == 'POST') {
        posts.add((jsonDecode(request.body) as Map).cast<String, dynamic>());
        return http.Response(jsonEncode({'ok': true}), 201, headers: headers);
      }
      if (request.url.path.endsWith('/api/admin/client-packages')) {
        return http.Response(
          jsonEncode({
            'purchasedPackages': [],
            'catalog': [_catalog.first],
          }),
          200,
          headers: headers,
        );
      }
      return http.Response(
        jsonEncode({'agendas': []}),
        200,
        headers: headers,
      );
    });
    addTearDown(() => HsApi.client = previous);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientPackagesDialog(
            client: const {'id': 7, 'name': 'Ana', 'lastname': 'Ruiz'},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _tap(tester, find.text('Asignar del catálogo').first);

    // Ya está seleccionado: el precio se decide sin tocar la tarjeta.
    expect(
      find.textContaining('Precio del catálogo: MXN \$6,500'),
      findsOneWidget,
    );
    await _tap(tester, _saveButton);
    await _tap(tester, _acceptButton);
    await tester.pump(const Duration(milliseconds: 400));

    expect(posts, hasLength(1));
    expect(posts.first['packageId'], 3);
    expect(posts.first.containsKey('price'), isFalse);
    // El modal del alta se cerró al asignar.
    expect(find.byType(FormDialog), findsNothing);
  });
}

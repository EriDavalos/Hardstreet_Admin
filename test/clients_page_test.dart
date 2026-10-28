import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/clients_page.dart';

/// Cliente falso con 2 paquetes + lo que pide el administrador de paquetes
/// al abrirse (paquetes del cliente, agendas y el detalle del vigente).
void _installMockClient() {
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;

    if (path.endsWith('/api/admin/clients')) {
      return http.Response(
        jsonEncode({
          'clients': [
            {
              'id': 7,
              'name': 'Ana',
              'lastname': 'Ruiz',
              'email': 'ana@correo.com',
              'number': '9991112233',
              'packagesCount': 2,
            },
            {
              'id': 8,
              'name': 'Luis',
              'lastname': 'Gómez',
              'email': 'luis@correo.com',
              'packagesCount': 0,
            },
          ]
        }),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/admin/client-packages')) {
      return http.Response(
        jsonEncode({
          'purchasedPackages': [
            {
              'usersPackageId': 30,
              'id': 10,
              'name': 'Boda - Premium',
              'subtitle': '',
              'description': '',
              'price': 12000,
              'paid': 6000,
              'currency': 'MXN',
              'status': 'En proceso',
              'packageId': 1,
              'tierName': 'Premium',
              'categoryName': 'Boda',
              'agendaCount': 0,
              'services': const [],
            },
          ],
          'catalog': const [],
        }),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/admin/agendas')) {
      return http.Response(jsonEncode({'agendas': const []}), 200,
          headers: headers);
    }
    if (path.endsWith('/api/admin/user-drive')) {
      // Una carpeta viene de un paquete (se copia a su usuario) y otra está
      // compartida directamente con el cliente.
      return http.Response(
        jsonEncode({
          'paths': [
            'Hardstreet/Comercial/RegalandoSonrisas/PrimerServicio',
            'Hardstreet/Comercial/RegalandoSonrisas/SegundoServicio',
          ],
          'items': [
            {
              'path': 'Hardstreet/Comercial/RegalandoSonrisas/PrimerServicio',
              'packageId': 10,
              'packageName': 'Publicidad Digital - Básico',
            },
            {
              'path': 'Hardstreet/Comercial/RegalandoSonrisas/SegundoServicio',
              'packageId': 0,
              'packageName': '',
            },
          ],
        }),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/admin/package-progress')) {
      return http.Response(
        jsonEncode({
          'package': {
            'id': 10,
            'name': 'Boda - Premium',
            'price': 12000,
            'paid': 6000,
            'balance': 6000,
            'status': 'En proceso',
            'statusId': 2,
            'finished': false,
          },
          'services': const [],
          'movements': const [],
          'totals': const {},
          'canFinish': false,
          'blockers': const [],
        }),
        200,
        headers: headers,
      );
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

Future<void> _pumpClients(WidgetTester tester, Size size,
    {String query = ''}) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final previous = HsApi.client;
  _installMockClient();
  addTearDown(() => HsApi.client = previous);

  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: ClientsPage())),
  );
  await tester.pump(); // lista de clientes
  await tester.pump(const Duration(milliseconds: 600)); // animaciones
  if (query.isNotEmpty) {
    await tester.enterText(find.byType(TextField), query);
    await tester.pump();
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Sello de que el ADMINISTRADOR DE PAQUETES está abierto (sus tarjetas).
Finder get _adminOpen => find.text('Ver administración');

void main() {
  testWidgets('la tarjeta del cliente es interactiva: al tocarla se abre el '
      'administrador de paquetes', (tester) async {
    await _pumpClients(tester, const Size(1280, 900));

    // La tarjeta muestra sus datos y sus paquetes.
    expect(find.text('Ana Ruiz'), findsOneWidget);
    expect(find.textContaining('ana@correo.com'), findsOneWidget);
    expect(find.text('2 paquetes'), findsOneWidget);
    expect(find.text('0 paquetes'), findsOneWidget);
    expect(_adminOpen, findsNothing);

    // Tocar la tarjeta (el nombre, lejos de los botones) abre el admin.
    await _tap(tester, find.text('Ana Ruiz'));
    expect(_adminOpen, findsOneWidget);
    expect(find.text('Boda - Premium'), findsWidgets);

    // Y desde ahí se entra al detalle de administración del paquete: la
    // ficha del vigente con sus pestañas (la etiqueta "Paquetes del cliente"
    // se quitó: se vuelve al selector con la flecha del encabezado).
    await _tap(tester, find.text('Boda - Premium').first);
    expect(find.text('Finalizar paquete'), findsOneWidget);
    expect(find.text('Drive'), findsOneWidget);

    // Se puede cerrar.
    await _tap(tester, find.byTooltip('Cerrar').last);
    expect(_adminOpen, findsNothing);
    expect(find.text('Finalizar paquete'), findsNothing);
  });

  testWidgets('el botón "Paquetes" sigue abriendo el administrador',
      (tester) async {
    await _pumpClients(tester, const Size(1280, 900));

    expect(find.byTooltip('Paquetes'), findsNWidgets(2));
    await _tap(tester, find.byTooltip('Paquetes').first);
    expect(_adminOpen, findsOneWidget);
    await _tap(tester, find.byTooltip('Cerrar').last);
    expect(_adminOpen, findsNothing);
  });

  testWidgets('los botones Editar y Eliminar NO abren el administrador',
      (tester) async {
    await _pumpClients(tester, const Size(1280, 900));

    await _tap(tester, find.byTooltip('Editar').first);
    expect(find.text('Editar cliente'), findsOneWidget);
    expect(_adminOpen, findsNothing);
    await _tap(tester, find.text('Cancelar'));

    await _tap(tester, find.byTooltip('Eliminar').first);
    expect(find.text('¿Eliminar cliente?'), findsOneWidget);
    expect(_adminOpen, findsNothing);
    await _tap(tester, find.text('Cancelar'));
  });

  testWidgets('el icono de carpetas del Drive abre el diálogo del cliente',
      (tester) async {
    await _pumpClients(tester, const Size(1280, 900));

    // Mismo icono que en el módulo Usuarios: el cliente es un usuario de tipo
    // cliente y se le pueden compartir VARIAS carpetas.
    expect(find.byTooltip('Carpetas del Drive'), findsNWidgets(2));
    await _tap(tester, find.byTooltip('Carpetas del Drive').first);

    expect(find.text('Carpetas del Drive'), findsOneWidget);
    expect(
      find.text('Hardstreet/Comercial/RegalandoSonrisas/PrimerServicio'),
      findsOneWidget,
    );
    // La carpeta compartida desde un paquete aparece y dice de cuál viene: es
    // la que antes no salía porque vivía atada al paquete en `users_drive`.
    expect(
      find.text('Carpeta del paquete Publicidad Digital - Básico'),
      findsOneWidget,
    );
    expect(find.text('Compartir otra carpeta'), findsOneWidget);
    expect(_adminOpen, findsNothing);

    await _tap(tester, find.text('Cerrar'));
    expect(find.text('Compartir otra carpeta'), findsNothing);
  });

  testWidgets('la búsqueda sigue funcionando y en móvil no desborda',
      (tester) async {
    await _pumpClients(tester, const Size(390, 844), query: 'Luis');

    expect(find.text('Luis Gómez'), findsOneWidget);
    expect(find.text('Ana Ruiz'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en el celular el modal de carpetas ocupa la pantalla y no '
      'desborda', (tester) async {
    await _pumpClients(tester, const Size(390, 844));

    // En móvil las acciones de la tarjeta viven en el menú «⋮».
    await _tap(tester, find.byTooltip('Acciones').first);
    await _tap(tester, find.text('Carpetas del Drive'));

    // El modal se adapta al ancho del teléfono: se ven sus carpetas, el
    // paquete del que vienen y el botón, sin desbordes.
    expect(find.text('Compartir otra carpeta'), findsOneWidget);
    expect(
      find.text('Hardstreet/Comercial/RegalandoSonrisas/SegundoServicio'),
      findsOneWidget,
    );
    expect(
      find.text('Carpeta del paquete Publicidad Digital - Básico'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // La ✕ de la esquina superior derecha cierra el modal.
    await _tap(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byTooltip('Cerrar'),
      ),
    );
    expect(find.text('Compartir otra carpeta'), findsNothing);
  });
}

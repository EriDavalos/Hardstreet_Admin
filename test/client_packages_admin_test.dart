import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/clients_page.dart';

/// Paquete VIGENTE (el que se administra) y uno TERMINADO (solo consulta).
const int _vigenteId = 10;

String _two(int n) => n.toString().padLeft(2, '0');

void _installMockClient({required List<Map<String, dynamic>> posts}) {
  final now = DateTime.now();
  final agendaDay = DateTime(now.year, now.month, 15, 14, 30);

  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;

    if (path.endsWith('/api/admin/client-packages')) {
      return http.Response(
        jsonEncode({
          'purchasedPackages': [
            {
              'usersPackageId': 30,
              'id': _vigenteId,
              'name': 'Boda - Premium',
              'subtitle': 'Cobertura premium',
              'description': '',
              'price': 12000,
              'paid': 6000,
              'currency': 'MXN',
              'status': 'En proceso',
              'packageId': 1,
              // Identidad del catálogo (flyer): tier + categoría.
              'tierName': 'Premium',
              'categoryName': 'Boda',
              'agendaCount': 1,
              'services': [
                {'id': 1, 'serviceId': 5, 'name': 'Cobertura en evento', 'description': '', 'status': 'Pendiente'},
              ],
            },
            {
              'usersPackageId': 29,
              'id': 9,
              'name': 'XV Años - Gold',
              'subtitle': 'Evento anterior',
              'description': '',
              'price': 7500,
              'paid': 7500,
              'currency': 'MXN',
              'status': 'Terminado',
              'packageId': 5,
              'tierName': 'Gold',
              'categoryName': 'XV Años',
              'agendaCount': 0,
              'services': const [],
            },
          ],
          'catalog': [
            {'id': 3, 'name': 'Boda - Basic', 'price': 6500, 'currency': 'MXN'},
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
              'purchasedPackageId': _vigenteId,
              'userId': 7,
              'clientName': 'Ana Ruiz',
              'packageName': 'Boda - Premium',
              'serviceId': 5,
              'serviceName': 'Cobertura en evento',
              'eventDate':
                  '${agendaDay.year}-${_two(agendaDay.month)}-${_two(agendaDay.day)}T14:30:00',
              'description': 'Ceremonia en el jardín',
            },
          ],
        }),
        200,
        headers: headers,
      );
    }

    if (path.endsWith('/api/admin/package-progress')) {
      if (request.method == 'POST') {
        posts.add(
            (jsonDecode(request.body) as Map).cast<String, dynamic>());
        return http.Response(jsonEncode({'ok': true}), 201,
            headers: headers);
      }
      final id = int.tryParse(request.url.queryParameters['purchasedPackageId'] ?? '') ?? 0;
      final isVigente = id == _vigenteId;
      final doneAt =
          '${now.year}-${_two(now.month)}-${_two(now.day)}T12:00:00';
      return http.Response(
        jsonEncode({
          'package': {
            'id': id,
            'name': isVigente ? 'Boda - Premium' : 'XV Años - Gold',
            'price': isVigente ? 12000 : 7500,
            'paid': isVigente ? 6000 : 7500,
            'balance': isVigente ? 6000 : 0,
            'status': isVigente ? 'En proceso' : 'Terminado',
            'statusId': isVigente ? 2 : 6,
            'finished': !isVigente,
            'finishedAt': isVigente ? null : doneAt,
          },
          'services': isVigente
              ? [
                  {
                    'id': 1,
                    'serviceId': 5,
                    'name': 'Cobertura en evento',
                    'description': '',
                    'url': 'https://drive.google.com/drive/u/0/boda',
                    'status': 'Pendiente',
                    'statusId': 1,
                    'done': false,
                    'finishedAt': null,
                  },
                  {
                    'id': 2,
                    'serviceId': 10,
                    'name': 'Sesión previa',
                    'description': 'Sesión en el parque',
                    'status': 'Entregado',
                    'statusId': 3,
                    'done': true,
                    'finishedAt': doneAt,
                  },
                ]
              : const [],
          'movements': [
            {
              'id': 5,
              'kind': 'abono',
              'source': 'payment',
              'amount': 6000,
              'description': 'Anticipo',
              'created': doneAt,
            },
            {
              'id': 6,
              'kind': 'inversion',
              'source': 'movement',
              'amount': 800,
              'description': 'Renta de lente',
              'created': doneAt,
            },
          ],
          'movementsAvailable': true,
          'totals': {
            'abonado': 6000,
            'invertido': 800,
            'gastado': 0,
            'abonoExterno': 0,
          },
          'canFinish': false,
          'blockers': [
            'Falta terminar 1 servicio del paquete',
            'El pago está incompleto: falta por abonar 6000.00',
          ],
        }),
        200,
        headers: headers,
      );
    }

    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

Future<void> _pumpDialog(WidgetTester tester,
    {required List<Map<String, dynamic>> posts,
    Size size = const Size(1250, 940),
    bool openDetail = true}) async {
  await tester.binding.setSurfaceSize(size);
  // En pruebas, MediaQuery NO sigue al tamaño de la superficie: hay que
  // declarar la vista para que el modal vea la MISMA ventana que dibuja.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final previous = HsApi.client;
  _installMockClient(posts: posts);
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
  await tester.pump(); // client-packages + agendas
  await tester.pump(); // detalle del paquete
  await tester.pump(const Duration(milliseconds: 400));
  if (openDetail) {
    // El modal abre con las TARJETAS de los paquetes: para ver el detalle
    // hay que elegir el paquete vigente (la dinámica pedida).
    await _tap(tester, find.text('Boda - Premium'));
    await tester.pump(const Duration(milliseconds: 400));
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('ventana ancha: la ficha del paquete a la izquierda y la '
      'administración a la derecha', (tester) async {
    await _pumpDialog(tester, posts: [], size: const Size(1320, 900));

    final cover = tester.getTopLeft(find.text('EN ADMINISTRACIÓN'));
    final tab = tester.getTopLeft(find.text('Servicios'));
    // Las pestañas están a la DERECHA de la ficha…
    expect(tab.dx, greaterThan(cover.dx));
    // …y las acciones de la ficha caen por debajo de la fila de pestañas
    // (dos columnas de verdad, no apiladas).
    expect(
      tester.getTopLeft(find.text('Finalizar paquete')).dy,
      greaterThan(tab.dy),
    );
  });

  testWidgets('ventana angosta: el modal se apila sin desbordarse',
      (tester) async {
    await _pumpDialog(tester, posts: [], size: const Size(820, 780));

    final panel = tester.getTopLeft(find.text('PAQUETES DEL CLIENTE'));
    final tab = tester.getTopLeft(find.text('Servicios'));
    expect(tab.dy, greaterThan(panel.dy),
        reason: 'en ventana angosta la ficha va arriba y las pestañas debajo');
    expect(find.text('Finalizar paquete'), findsOneWidget);
    // Abonar ya NO vive en la ficha: está en la pestaña Movimientos.
    expect(find.text('Abonar'), findsNothing);
    await _tap(tester, find.text('Movimientos'));
    expect(find.text('Abonar'), findsOneWidget);
    expect(find.text('Registrar inversión / gasto / abono externo'),
        findsOneWidget);
  });

  testWidgets('ventana tipo teléfono: los controles se reacomodan sin '
      'desbordar', (tester) async {
    await _pumpDialog(tester, posts: [], size: const Size(430, 760));

    // Nada se sale del modal: el framework falla el test si algo desborda.
    expect(find.text('Servicios'), findsOneWidget);
    expect(find.text('Calendario'), findsOneWidget);
    expect(find.text('Movimientos'), findsOneWidget);
    expect(find.text('MXN \$12,000'), findsOneWidget);
  });

  testWidgets('justo en el umbral (1024) ya son dos columnas y nada '
      'desborda', (tester) async {
    final posts = <Map<String, dynamic>>[];
    await _pumpDialog(tester, posts: posts, size: const Size(1024, 820));

    expect(
      tester.getTopLeft(find.text('Servicios')).dx,
      greaterThan(tester.getTopLeft(find.text('EN ADMINISTRACIÓN')).dx),
    );
    // Cada pestaña se dibuja sin salirse del modal.
    await _tap(tester, find.text('Calendario'));
    await _tap(tester, find.text('Movimientos'));
    expect(find.text('Abonar'), findsOneWidget);
    expect(find.text('Registrar inversión / gasto / abono externo'),
        findsOneWidget);
  });

  testWidgets('el modal muestra el paquete VIGENTE con dinero, servicios y '
      'lo que falta para finalizar', (tester) async {
    await _pumpDialog(tester, posts: []);

    // Ficha del paquete en foco (el vigente): el flyer representativo con
    // precio, más el dinero y el avance.
    expect(find.text('Boda - Premium'), findsWidgets);
    expect(find.text('Actual'), findsOneWidget);
    expect(find.text('EN ADMINISTRACIÓN'), findsOneWidget);
    expect(find.text('MXN \$12,000'), findsOneWidget);
    // El flyer lleva el tier y la categoría del catálogo.
    expect(find.text('PREMIUM'), findsOneWidget);
    expect(find.text('BODA'), findsOneWidget);
    expect(find.text('ABONADO'), findsOneWidget);
    expect(find.text('SALDO'), findsOneWidget);
    expect(find.text('PAGADO'), findsOneWidget);
    expect(find.text('MXN \$6,000'), findsWidgets);

    // Progresos y bloqueos de la validación de cierre.
    expect(find.text('Pago'), findsOneWidget);
    expect(find.text('Terminados'), findsOneWidget);
    expect(find.text('Para finalizar el paquete'), findsOneWidget);
    expect(find.text('• Falta terminar 1 servicio del paquete'), findsOneWidget);
    expect(
      find.text('• El pago está incompleto: falta por abonar 6000.00'),
      findsOneWidget,
    );

    // Con servicios/dinero pendientes, "Finalizar paquete" está DESHABILITADO.
    final finish = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Finalizar paquete'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(finish.onPressed, isNull,
        reason: 'no se puede finalizar con servicios o pago incompletos');

    // La ficha ya NO tiene botones de "Acciones del paquete": todo vive en
    // las pestañas y solo queda Finalizar (verificado arriba).
    expect(find.text('Acciones del paquete'), findsNothing);
    expect(find.text('Agendas (1)'), findsNothing);
    await _tap(tester, find.text('Movimientos'));
    expect(find.text('Abonar'), findsOneWidget);
    expect(find.text('Registrar inversión / gasto / abono externo'),
        findsOneWidget);
  });

  testWidgets('los demás paquetes se ven como detalle (solo lectura)',
      (tester) async {
    await _pumpDialog(tester, posts: []);

    await _tap(tester, find.text('XV Años - Gold'));

    expect(find.text('Paquete terminado · consulta'), findsOneWidget);
    expect(find.text('Solo lectura'), findsOneWidget);
    // Sin acciones de administración.
    expect(find.text('Abonar'), findsNothing);
    expect(find.text('Movimiento'), findsNothing);
    expect(find.text('Finalizar paquete'), findsNothing);
  });

  testWidgets('completar un servicio registra su cierre con descripción',
      (tester) async {
    final posts = <Map<String, dynamic>>[];
    await _pumpDialog(tester, posts: posts);

    await _tap(tester, find.text('Completar servicio'));
    expect(find.text('Terminar servicio'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Cómo quedó el servicio / observaciones'),
        'Entrega de la galería completa');
    await _tap(tester, find.text('Dar por terminado'));

    final completar = posts
        .where((p) => p['action'] == 'completar-servicio')
        .toList();
    expect(completar, hasLength(1));
    expect(completar.first['serviceId'], 1);
    expect(completar.first['description'], 'Entrega de la galería completa');
  });

  testWidgets('el calendario usa días CÍRCULOS y el detalle muestra sus '
      'eventos', (tester) async {
    await _pumpDialog(tester, posts: []);

    await _tap(tester, find.text('Calendario'));

    // Mes visible + navegación + rejilla con los círculos de los días.
    expect(find.byTooltip('Mes anterior'), findsOneWidget);
    expect(find.byTooltip('Mes siguiente'), findsOneWidget);
    expect(find.text('LUN'), findsOneWidget);
    expect(find.text('Servicio terminado'), findsOneWidget); // leyenda

    // Tocar el día 15 abre su detalle con la agenda del mock.
    await _tap(tester, find.text('15'));
    expect(find.textContaining('Ceremonia en el jardín'), findsOneWidget);
    await _tap(tester, find.text('Cerrar'));

    // El servicio terminado (hoy) se ve en el detalle de su día.
    final today = DateTime.now().day;
    if (today != 15) {
      await _tap(tester, find.text('$today'));
      expect(find.textContaining('Sesión previa'), findsOneWidget);
      await _tap(tester, find.text('Cerrar'));
    } else {
      expect(find.textContaining('Sesión previa'), findsOneWidget);
    }
  });

  testWidgets('los movimientos listan abonos e inversiones con totales',
      (tester) async {
    final posts = <Map<String, dynamic>>[];
    await _pumpDialog(tester, posts: posts);

    await _tap(tester, find.text('Movimientos'));

    expect(find.text('Abono'), findsWidgets);
    expect(find.text('Inversión'), findsWidgets);
    expect(find.textContaining('Renta de lente'), findsWidgets);
    expect(find.text('MXN \$800'), findsWidgets);
    expect(find.text('ABONO EXTERNO'), findsOneWidget);
    // Abonar vive ahora en esta pestaña (ya no en la ficha).
    expect(find.text('Abonar'), findsOneWidget);

    // Registrar un movimiento del paquete actual.
    await _tap(
      tester,
      find.text('Registrar inversión / gasto / abono externo'),
    );
    expect(find.text('Movimiento del paquete'), findsOneWidget);
    expect(find.text('Abono externo'), findsWidgets);
    expect(find.text('Gasto'), findsWidgets);

    // El campo de monto NO debe duplicar el "$" (icono + prefixText).
    final double$ = tester
        .widgetList<TextField>(find.byType(TextField))
        .any((t) => (t.decoration?.prefixText ?? '').contains(r'$'));
    expect(double$, isFalse,
        reason: 'el signo de dinero solo puede venir del icono');
  });

  testWidgets('la pestaña Servicios muestra la liga del Drive y permite '
      'editarla', (tester) async {
    final posts = <Map<String, dynamic>>[];
    await _pumpDialog(tester, posts: posts);

    // El servicio del paquete muestra la liga base de su carpeta.
    expect(find.text('https://drive.google.com/drive/u/0/boda'), findsOneWidget);

    // Editar la liga manda la acción al backend con el servicio correcto.
    await _tap(tester, find.text('Editar enlace'));
    expect(find.text('Carpeta del Drive'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'URL base del Drive'),
      'https://drive.google.com/drive/u/0/nuevo',
    );
    await _tap(tester, find.text('Guardar enlace'));

    final urlPosts =
        posts.where((p) => p['action'] == 'actualizar-servicio-url').toList();
    expect(urlPosts, hasLength(1));
    expect(urlPosts.first['serviceId'], 5);
    expect(urlPosts.first['url'], 'https://drive.google.com/drive/u/0/nuevo');
  });

  testWidgets('el administrador abre con TARJETAS de los paquetes y al '
      'tocar una entra al detalle', (tester) async {
    await _pumpDialog(tester, posts: [], openDetail: false);

    // Etapa inicial: solo las tarjetas ("targets"), sin pestañas ni ficha.
    expect(find.text('Boda - Premium'), findsOneWidget);
    expect(find.text('XV Años - Gold'), findsOneWidget);
    expect(find.text('Ver administración'), findsNWidgets(2));
    expect(find.byTooltip('Todos los paquetes'), findsNothing);
    expect(find.text('Servicios'), findsNothing);
    expect(find.text('Finalizar paquete'), findsNothing);

    // Al tocar una tarjeta se pasa al detalle (con la flecha de regreso).
    await _tap(tester, find.text('XV Años - Gold'));
    expect(find.text('Servicios'), findsOneWidget);
    expect(find.byTooltip('Todos los paquetes'), findsOneWidget);
    expect(find.text('Paquete terminado · consulta'), findsOneWidget);

    // La flecha vuelve a las tarjetas.
    await _tap(tester, find.byTooltip('Todos los paquetes'));
    expect(find.byTooltip('Todos los paquetes'), findsNothing);
    expect(find.text('Ver administración'), findsNWidgets(2));
    expect(find.text('Servicios'), findsNothing);
  });
}

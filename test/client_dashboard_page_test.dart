import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/client_dashboard_page.dart';
import 'package:hardstreet_admin/widgets/hs_toast.dart';

/// Dos paquetes comprados: uno con liga de drive PROPIA y otra externa.
void _installMock({
  List<Map<String, dynamic>>? packages,
  List<Map<String, dynamic>> notifications = const [],
}) {
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    if (request.url.path.endsWith('/api/my/packages')) {
      return http.Response(
        jsonEncode({'purchasedPackages': packages ?? _defaultPackages()}),
        200,
        headers: headers,
      );
    }
    if (request.url.path.endsWith('/api/my/notifications')) {
      if (request.method != 'GET') {
        return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
      }
      return http.Response(
        jsonEncode({
          'notifications': notifications,
          'unread': notifications.length,
        }),
        200,
        headers: headers,
      );
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

List<Map<String, dynamic>> _defaultPackages() => [
  {
    'id': 11,
    'name': 'Boda Ana & Luis',
    'subtitle': 'Paquete Gold',
    'description': '',
    'price': 12000,
    'paid': 6000,
    'currency': 'MXN',
    'status': {'id': 2, 'name': 'En proceso'},
    'package': {
      'id': 1,
      'name': 'Boda',
      'tier': {'id': 1, 'name': 'Gold', 'tier': 1},
      'packageCategory': {'id': 1, 'name': 'Bodas', 'icon': ''},
      'services': <dynamic>[],
    },
    'services': [
      {
        'id': 101,
        'description': 'Cobertura completa del evento',
        'status': {'id': 3, 'name': 'Entregado'},
        'service': {
          'id': 1,
          'name': 'Cobertura en evento',
          'icon': 'material:videocam',
          'url': 'http://oriongo.ddns.net:4000/?path=clientes/boda',
        },
      },
      {
        'id': 102,
        'description': '',
        'status': {'id': 2, 'name': 'En proceso'},
        'service': {'id': 2, 'name': 'Álbum de fotos', 'icon': '', 'url': ''},
      },
      {
        'id': 103,
        'description': '',
        'status': {'id': 1, 'name': 'Pendiente'},
        'service': {
          'id': 3,
          'name': 'Sesión previa',
          'icon': '',
          'url': 'https://drive.google.com/drive/folders/xyz',
        },
      },
    ],
  },
  {
    'id': 12,
    'name': 'XV Años Sofía',
    'subtitle': 'Paquete Premium',
    'description': '',
    'price': 9000,
    'paid': 9000,
    'currency': 'MXN',
    'status': {'id': 3, 'name': 'Entregado'},
    'package': {
      'id': 2,
      'name': 'XV Años',
      'tier': {'id': 2, 'name': 'Premium', 'tier': 2},
      'packageCategory': {'id': 2, 'name': 'XV Años', 'icon': ''},
      'services': <dynamic>[],
    },
    'services': [
      {
        'id': 201,
        'description': '',
        'status': {'id': 3, 'name': 'Entregado'},
        'service': {'id': 4, 'name': 'Fotos', 'icon': '', 'url': ''},
      },
    ],
  },
];

Future<void> _pumpPage(
  WidgetTester tester, {
  void Function(List<String>)? onOpenDrive,
  Size size = const Size(1100, 900),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final previous = HsApi.client;
  addTearDown(() => HsApi.client = previous);

  // Con HsToastHost, los avisos laterales ("Enlace copiado") se pintan como
  // en la app real.
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          HsToastHost(child: child ?? const SizedBox.shrink()),
      home: Scaffold(body: ClientDashboardPage(onOpenDrive: onOpenDrive)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('muestra el paquete, lo cumplido (checklist) y el Drive', (
    tester,
  ) async {
    _installMock();
    await _pumpPage(tester);

    // Selector + hero del primer paquete.
    expect(find.text('Boda Ana & Luis'), findsWidgets);
    expect(find.text('Paquete Gold'), findsOneWidget); // solo en el hero
    expect(find.text('En proceso'), findsWidgets); // estatus global + servicio

    // Avance de pago (6000 de 12000) y pill de servicios cumplidos.
    expect(find.textContaining('MXN'), findsWidgets);
    expect(find.text('1 de 3 servicios cumplidos'), findsOneWidget);

    // Checklist: cada servicio con su estado (verde/azul/gris).
    expect(find.text('Cumplido'), findsOneWidget);
    expect(find.text('En proceso'), findsWidgets);
    expect(find.text('Pendiente'), findsWidgets);
    expect(find.text('Cobertura completa del evento'), findsOneWidget);

    // Secciones clave y acceso al Drive (la primera liga es del drive propio).
    expect(find.text('Tus servicios'), findsOneWidget);
    expect(find.text('Mi Drive compartido'), findsOneWidget);
    expect(find.text('Entrar a mi Drive'), findsOneWidget);
    expect(
      find.text('Copiar enlace del Drive'),
      findsNothing,
      reason: 'la PRIMERA liga es propia → botón "Entrar"',
    );
    expect(
      find.text('Sesión previa'),
      findsWidgets,
      reason: 'liga externa: aparece en el checklist y en las ligas',
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('cambiar de paquete con el selector actualiza la portada', (
    tester,
  ) async {
    _installMock();
    await _pumpPage(tester);
    expect(find.text('Paquete Premium'), findsNothing);

    // El selector es una tira de tarjetas con la foto del paquete.
    await _tap(tester, find.text('XV Años Sofía'));

    expect(find.text('Paquete Premium'), findsOneWidget);
    expect(
      find.text('1 de 1 servicios cumplidos'),
      findsWidgets,
      reason: 'pill de la cabecera + cabecera del checklist',
    );
    expect(find.text('Paquete liquidado ✓'), findsOneWidget);
  });

  testWidgets('la carpeta propia entrega la ruta al panel (onOpenDrive)', (
    tester,
  ) async {
    _installMock();
    final opened = <List<String>>[];
    await _pumpPage(tester, onOpenDrive: opened.add);

    await _tap(tester, find.text('Entrar a mi Drive'));

    expect(opened, hasLength(1));
    expect(opened.single, ['clientes', 'boda']);
  });

  testWidgets('liga externa: se copia al portapapeles con aviso', (
    tester,
  ) async {
    _installMock();
    await _pumpPage(tester);

    // La liga de Google Drive está en la lista de servicios con liga.
    await _tap(tester, find.text('Copiar').last);

    expect(find.text('Enlace copiado'), findsOneWidget);
  });

  testWidgets('los avisos del estudio se ven en «Novedades»', (tester) async {
    _installMock(
      notifications: [
        {
          'id': 1,
          'kind': 'fotos-disponibles',
          'title': 'Ya puedes elegir tus fotos',
          'body': 'La selección de «Álbum de fotos» ya está disponible.',
          'isRead': false,
          'created': '2026-10-18T10:00:00',
        },
      ],
    );
    await _pumpPage(tester);

    expect(find.text('Novedades'), findsOneWidget);
    expect(find.text('Ya puedes elegir tus fotos'), findsOneWidget);
    expect(find.textContaining('Álbum de fotos'), findsWidgets);

    // Al tocar el aviso se marca leído (y la lista se queda a la vista).
    await _tap(tester, find.text('Ya puedes elegir tus fotos'));
    expect(find.text('Ya puedes elegir tus fotos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin paquetes: estado vacío claro', (tester) async {
    _installMock(packages: const []);
    await _pumpPage(tester);

    expect(find.text('Aún no tienes paquetes'), findsOneWidget);
    expect(find.text('Entrar a mi Drive'), findsNothing);
  });

  testWidgets('los servicios con fotos van arriba y los completados abajo', (
    tester,
  ) async {
    final pkgs = _defaultPackages();
    final services = (pkgs.first['services'] as List);
    (services[1] as Map<String, dynamic>)
      ..['pickPhotos'] = true
      ..['shareFolder'] = 'ReynaCoot'
      ..['showFolder'] = true
      ..['items'] = 2;
    _installMock(packages: pkgs);
    await _pumpPage(tester);

    final photos = tester.getTopLeft(find.text('Álbum de fotos').first).dy;
    final pending = tester.getTopLeft(find.text('Sesión previa').first).dy;
    final done = tester.getTopLeft(find.text('Cobertura en evento').first).dy;
    expect(photos, lessThan(pending));
    expect(pending, lessThan(done));
    expect(find.text('Elige tus fotos · 1'), findsOneWidget);
    expect(find.text('2 fotos elegidas'), findsOneWidget);
  });

  testWidgets('en celular la portada, la búsqueda y los servicios caben', (
    tester,
  ) async {
    _installMock();
    await _pumpPage(tester, size: const Size(390, 844));

    expect(find.byKey(const ValueKey('hs-filter-button')), findsWidgets);
    expect(find.text('Tus servicios'), findsOneWidget);
    expect(find.text('Mi Drive compartido'), findsOneWidget);
    expect(find.text('Cobertura en evento'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'en celular las acciones del servicio van juntas y el aviso dice Enviadas',
    (tester) async {
      final pkgs = _defaultPackages();
      final services = (pkgs.first['services'] as List);
      (services[1] as Map<String, dynamic>)
        ..['pickPhotos'] = true
        ..['shareFolder'] = 'ReynaCoot'
        ..['showFolder'] = true
        ..['items'] = 2
        ..['sentToPrint'] = true
        ..['printStatus'] = 'sent';
      _installMock(packages: pkgs);
      await _pumpPage(tester, size: const Size(390, 844));

      final view = find.text('Ver fotos (2)');
      final folder = find.text('Abrir carpeta');
      expect(view, findsOneWidget);
      expect(folder, findsWidgets);

      // «Ver fotos» y «Abrir carpeta» comparten fila (centro vertical).
      final dy = tester.getCenter(view).dy;
      final folderDy = tester.getCenter(folder.first).dy;
      expect((dy - folderDy).abs(), lessThan(1.5));

      // El aviso es corto y no queda el botón de enviar.
      expect(find.text('Enviadas'), findsOneWidget);
      expect(find.text('Enviadas a impresión'), findsNothing);
      expect(find.text('Enviar a impresión'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('el cliente ENVÍA sus fotos a impresión y luego solo las ve', (
    tester,
  ) async {
    final pkgs = _defaultPackages();
    final services = (pkgs.first['services'] as List);
    (services[1] as Map<String, dynamic>)
      ..['pickPhotos'] = true
      ..['shareFolder'] = 'ReynaCoot'
      ..['showFolder'] = true
      ..['items'] = 2;

    // Mock con estado: al enviar, el siguiente listado ya trae el envío.
    var sent = false;
    final posted = <String>[];
    HsApi.client = MockClient((request) async {
      final headers = {'content-type': 'application/json'};
      if (request.url.path.endsWith('/api/my/print-requests') &&
          request.method == 'POST') {
        posted.add(request.body);
        sent = true;
        return http.Response(
          jsonEncode({'ok': true, 'status': 'sent'}),
          200,
          headers: headers,
        );
      }
      if (request.url.path.endsWith('/api/my/packages')) {
        if (sent) {
          for (final s in services) {
            if ((s as Map)['id'] == 102) {
              s['sentToPrint'] = true;
              s['printStatus'] = 'sent';
            }
          }
        }
        return http.Response(
          jsonEncode({'purchasedPackages': pkgs}),
          200,
          headers: headers,
        );
      }
      if (request.url.path.endsWith('/api/my/notifications')) {
        return http.Response(
          jsonEncode({'notifications': const [], 'unread': 0}),
          200,
          headers: headers,
        );
      }
      return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
    });
    await _pumpPage(tester);

    final send = find.widgetWithText(OutlinedButton, 'Enviar a impresión');
    expect(send, findsOneWidget);
    await _tap(tester, send);

    // El modal explica que después ya no se puede modificar.
    expect(
      find.textContaining('ya no podrás cambiar la selección'),
      findsOneWidget,
    );
    await _tap(tester, find.widgetWithText(FilledButton, 'Enviar'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(posted, hasLength(1));
    expect(jsonDecode(posted.single), {'serviceId': 102});
    // El cliente ya solo puede VERLAS.
    expect(find.text('Ver fotos (2)'), findsOneWidget);
    expect(find.text('Enviadas a impresión'), findsOneWidget);
    expect(find.text('Enviar a impresión'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

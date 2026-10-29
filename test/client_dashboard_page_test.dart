import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/drive_scope.dart';
import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/client_dashboard_page.dart';
import 'package:hardstreet_admin/widgets/anim.dart';
import 'package:hardstreet_admin/widgets/hs_toast.dart';
import 'package:hardstreet_admin/widgets/service_photos_sheet.dart';

/// Dos paquetes comprados: uno con liga de drive PROPIA y otra externa.
///
/// [gateItems] retrasa la respuesta de «fotos elegidas del servicio»: con eso
/// se puede imitar al cliente que toca el botón mientras todavía está abriendo.
void _installMock({
  List<Map<String, dynamic>>? packages,
  List<Map<String, dynamic>> notifications = const [],
  Future<void>? gateItems,
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
    if (request.url.path.endsWith('/api/my/service-items')) {
      if (gateItems != null) await gateItems;
      return http.Response(
        jsonEncode({'items': const [], 'folder': 'ReynaCoot', 'max': 0}),
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

    // Portada: qué toca hacer y cuánto FALTA (sin barra de pago), más la
    // píldora de servicios cumplidos.
    expect(find.text('2 servicios en preparación'), findsOneWidget);
    expect(find.text('Faltan \$6,000'), findsOneWidget);
    expect(find.textContaining('\$12,000'), findsOneWidget);
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
    // Cabecera del checklist del paquete elegido (una sola pestaña de
    // servicios, ya cumplida).
    expect(
      find.text('1 de 1 cumplidos'),
      findsWidgets,
      reason: 'cabecera del checklist con el avance del paquete elegido',
    );
    // Al estar pagado completo, la portada dice «Liquidado».
    expect(find.text('Liquidado'), findsOneWidget);
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

    // MINIMIZADA: se ve la barra (con el resumen) y NO la lista.
    expect(find.text('Novedades'), findsOneWidget);
    expect(find.text('Ya puedes elegir tus fotos'), findsNothing);
    expect(find.text('1 sin leer · 1 aviso'), findsOneWidget);

    // Un toque en la barra la despliega.
    await _tap(tester, find.text('Novedades'));
    expect(find.text('Ya puedes elegir tus fotos'), findsOneWidget);
    expect(find.textContaining('Álbum de fotos'), findsWidgets);

    // Al tocar el aviso se marca leído (y la lista sigue abierta).
    await _tap(tester, find.text('Ya puedes elegir tus fotos'));
    expect(find.text('Ya puedes elegir tus fotos'), findsOneWidget);
    expect(find.text('1 aviso · todo leído'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '«Novedades» arranca minimizada y se abre/cierra ANIMANDO el alto',
    (tester) async {
      _installMock(
        notifications: [
          for (var i = 1; i <= 3; i++)
            {
              'id': i,
              'kind': 'fotos-disponibles',
              'title': 'Aviso $i',
              'body': 'Detalle del aviso $i.',
              'isRead': false,
              'created': '2026-10-1${i}T10:00:00',
            },
        ],
      );
      await _pumpPage(tester);

      final card = find.byKey(const ValueKey('client-notices-card'));
      final toggle = find.byKey(const ValueKey('client-notices-toggle'));
      final closed = tester.getSize(card).height;
      expect(
        find.text('Aviso 1'),
        findsNothing,
        reason: 'normalmente la ventana está minimizada',
      );

      // Desplegar: a mitad de la animación el alto ya creció pero NO llegó al
      // final (es una transición, no un salto).
      await tester.ensureVisible(toggle);
      await tester.pump();
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      final medio = tester.getSize(card).height;
      await tester.pump(const Duration(milliseconds: 400));
      final open = tester.getSize(card).height;
      expect(find.text('Aviso 1'), findsOneWidget);
      expect(open, greaterThan(closed + 40), reason: 'la lista ocupa su alto');
      expect(medio, greaterThan(closed), reason: 'crece progresivamente');
      expect(
        medio,
        lessThan(open),
        reason: 'a mitad de la animación aún no llega',
      );

      // Minimizar: vuelve al alto de la barra, también animando.
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      final medioCierre = tester.getSize(card).height;
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.getSize(card).height,
        moreOrLessEquals(closed, epsilon: 1),
        reason: 'vuelve a quedar minimizada',
      );
      expect(medioCierre, greaterThan(closed));
      expect(medioCierre, lessThan(open));
      expect(find.text('Aviso 1'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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
    expect(find.text('Elige tus fotos'), findsOneWidget);
    expect(find.text('2 fotos elegidas'), findsOneWidget);
  });

  testWidgets('en «En proceso» va primero lo que ya tiene carpeta', (
    tester,
  ) async {
    final pkgs = _defaultPackages();
    final services = (pkgs.first['services'] as List);
    // «Sesión previa» está PENDIENTE y sin carpeta; le damos una compartida:
    // debe subir por encima de «Álbum de fotos» (en proceso, sin carpeta).
    (services[2] as Map<String, dynamic>)
      ..['shareFolder'] = 'Sesion'
      ..['showFolder'] = true;
    _installMock(packages: pkgs);
    await _pumpPage(tester);

    final withFolder = tester.getTopLeft(find.text('Sesión previa').first).dy;
    final without = tester.getTopLeft(find.text('Álbum de fotos').first).dy;
    expect(
      withFolder,
      lessThan(without),
      reason: 'la carpeta disponible manda sobre el estado',
    );
  });

  testWidgets('en «Completados» van primero carpeta y luego fotos', (
    tester,
  ) async {
    final pkgs = _defaultPackages();
    final services = (pkgs.first['services'] as List);
    // Un entregado que SOLO abre carpeta y otro que además tiene fotos
    // («Ver fotos»): primero el de solo carpeta, luego el de fotos y al final
    // el que no ofrece nada.
    services.add({
      'id': 104,
      'description': '',
      'status': {'id': 3, 'name': 'Entregado'},
      'shareFolder': 'ReynaCoot/entrega',
      'showFolder': true,
      'pickPhotos': true,
      'items': 3,
      'service': {'id': 5, 'name': 'Galería digital', 'icon': '', 'url': ''},
    });
    services.add({
      'id': 105,
      'description': '',
      'status': {'id': 3, 'name': 'Entregado'},
      'shareFolder': 'ReynaCoot/video',
      'showFolder': true,
      'service': {'id': 6, 'name': 'Video resumen', 'icon': '', 'url': ''},
    });
    _installMock(packages: pkgs);
    await _pumpPage(tester);

    final folderOnly = tester.getTopLeft(find.text('Video resumen').first).dy;
    final withPhotos = tester.getTopLeft(find.text('Galería digital').first).dy;
    final without = tester
        .getTopLeft(find.text('Cobertura en evento').first)
        .dy;
    expect(folderOnly, lessThan(withPhotos));
    expect(withPhotos, lessThan(without));
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

    // El envío se DESTACA como siguiente paso (bloque propio + botón lleno):
    // con las fotos elegidas y sin enviar, el cliente lo ve sin buscarlo.
    expect(find.byKey(const ValueKey('client-send-next-step')), findsOneWidget);
    expect(find.text('SIGUIENTE PASO'), findsOneWidget);
    expect(find.text('Envía tus fotos a impresión'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('client-send-next-step')),
        matching: find.textContaining('2 fotos elegidas'),
      ),
      findsOneWidget,
    );

    final send = find.widgetWithText(FilledButton, 'Enviar a impresión');
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
    // El cliente ya solo puede VERLAS, y el bloque de «siguiente paso» se fue.
    expect(find.text('Ver fotos (2)'), findsOneWidget);
    expect(find.text('Enviadas a impresión'), findsOneWidget);
    expect(find.text('Enviar a impresión'), findsNothing);
    expect(find.text('SIGUIENTE PASO'), findsNothing);
    expect(find.byKey(const ValueKey('client-send-next-step')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dos toques en «Elegir fotos» NO abren dos ventanas', (
    tester,
  ) async {
    final pkgs = _defaultPackages();
    ((pkgs.first['services'] as List)[1] as Map<String, dynamic>)
      ..['pickPhotos'] = true
      ..['shareFolder'] = 'ReynaCoot';
    // El servidor tarda: es justo la ventana en la que se podía tocar dos veces
    // y quedaban DOS selectores apilados (y el atrás se quedaba sin qué hacer).
    final gate = Completer<void>();
    _installMock(packages: pkgs, gateItems: gate.future);

    // Con DriveScope: sin él la pantalla avisa «El Drive no está disponible» y
    // no llega a abrir nada (el guardia que se prueba vive después).
    late Directory tmp;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('hardstreet_doble_toque');
    });
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 900);
    addTearDown(tester.view.reset);
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      DriveScope(
        drive: DriveService.testRoot(tmp),
        child: const MaterialApp(home: Scaffold(body: ClientDashboardPage())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final pick = find.byKey(const ValueKey('client-pick-button'));
    await tester.ensureVisible(pick);
    await tester.pump();
    await tester.tap(pick, warnIfMissed: false);
    await tester.pump();
    // Segundo toque mientras la primera sigue abriendo: se ignora.
    await tester.tap(pick, warnIfMissed: false);
    await tester.pump();

    expect(
      find.text('Abriendo…'),
      findsWidgets,
      reason: 'el botón avisa que está trabajando',
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('client-pick-button')),
          )
          .onPressed,
      isNull,
      reason: 'mientras abre, el botón queda deshabilitado',
    );

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byType(ServicePhotosSheet),
      findsOneWidget,
      reason: 'una sola ventana, no dos',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin fotos elegidas NO se destaca el envío (no hay nada que '
      'mandar)', (tester) async {
    final pkgs = _defaultPackages();
    ((pkgs.first['services'] as List)[1] as Map<String, dynamic>)
      ..['pickPhotos'] = true
      ..['shareFolder'] = 'ReynaCoot';
    _installMock(packages: pkgs);
    await _pumpPage(tester);

    expect(find.byKey(const ValueKey('client-send-next-step')), findsNothing);
    expect(find.text('Elegir fotos'), findsWidgets);
  });

  testWidgets('en el celular el siguiente paso (enviar) se ve y no desborda', (
    tester,
  ) async {
    final pkgs = _defaultPackages();
    (pkgs.first['services'] as List)[1]
      ..['pickPhotos'] = true
      ..['shareFolder'] = 'ReynaCoot'
      ..['items'] = 2;
    _installMock(packages: pkgs);
    await _pumpPage(tester, size: const Size(390, 844));

    expect(find.byKey(const ValueKey('client-send-next-step')), findsOneWidget);
    expect(find.text('SIGUIENTE PASO'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('client-send-button')),
      findsOneWidget,
      reason: 'el botón de enviar va dentro del bloque destacado',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('el paso que le TOCA (elegir) se destaca y su botón LATE', (
    tester,
  ) async {
    final pkgs = _defaultPackages();
    ((pkgs.first['services'] as List)[1] as Map<String, dynamic>)
      ..['pickPhotos'] = true
      ..['shareFolder'] = 'ReynaCoot';
    _installMock(packages: pkgs);
    await _pumpPage(tester);

    // El paso va en su BLOQUE destacado (borde, rótulo y botón a lo ancho), no
    // perdido dentro de la fila de acciones del servicio.
    expect(find.byKey(const ValueKey('client-pick-next-step')), findsOneWidget);
    expect(find.text('TE TOCA A TI'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('client-pick-next-step')),
        matching: find.text('Elige tus fotos'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('client-pick-button')), findsOneWidget);

    final ring = find.byKey(const ValueKey('client-pick-ring'));
    expect(ring, findsOneWidget);
    expect(
      tester.widget<AttentionRing>(ring).enabled,
      isTrue,
      reason: 'sin fotos elegidas, el turno es del cliente',
    );

    // El botón se queda COMO ESTABA: nada de agrandarlo ni moverlo. Lo único
    // que cambia es el aro que se pinta por fuera.
    final button = find.byKey(const ValueKey('client-pick-button'));
    final size = tester.getSize(button);
    expect(
      find.descendant(of: ring, matching: find.byType(Transform)),
      findsNothing,
      reason: 'sin escala: el botón no crece',
    );

    AttentionRingPainter painter() =>
        tester
                .widget<CustomPaint>(
                  find
                      .descendant(of: ring, matching: find.byType(CustomPaint))
                      .first,
                )
                .painter!
            as AttentionRingPainter;

    final start = painter().t;
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      painter().t,
      isNot(closeTo(start, .01)),
      reason: 'el aro late (el trazo cambia entre fotogramas)',
    );
    expect(
      tester.getSize(button),
      size,
      reason: 'el botón mide lo mismo con el paso pendiente',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('con fotos YA elegidas el latido pasa al botón de enviar', (
    tester,
  ) async {
    final pkgs = _defaultPackages();
    ((pkgs.first['services'] as List)[1] as Map<String, dynamic>)
      ..['pickPhotos'] = true
      ..['shareFolder'] = 'ReynaCoot'
      ..['items'] = 2;
    _installMock(packages: pkgs);
    await _pumpPage(tester);

    // Ya eligió: el bloque de elegir se fue y en la fila vuelve «Mis fotos (N)».
    expect(find.byKey(const ValueKey('client-pick-next-step')), findsNothing);
    expect(find.byKey(const ValueKey('client-pick-ring')), findsNothing);
    expect(find.text('Mis fotos (2)'), findsOneWidget);
    // Ahora el turno es ENVIAR y el aro pasa a su botón.
    expect(find.text('SIGUIENTE PASO'), findsOneWidget);
    expect(
      tester
          .widget<AttentionRing>(find.byKey(const ValueKey('client-send-ring')))
          .enabled,
      isTrue,
      reason: 'ahora lo que falta es ENVIAR',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('enviadas las fotos, NADIE late (ya no hay paso pendiente)', (
    tester,
  ) async {
    final pkgs = _defaultPackages();
    ((pkgs.first['services'] as List)[1] as Map<String, dynamic>)
      ..['pickPhotos'] = true
      ..['shareFolder'] = 'ReynaCoot'
      ..['items'] = 2
      ..['sentToPrint'] = true
      ..['printStatus'] = 'sent';
    _installMock(packages: pkgs);
    await _pumpPage(tester);

    expect(find.byKey(const ValueKey('client-pick-ring')), findsNothing);
    expect(find.byKey(const ValueKey('client-send-ring')), findsNothing);
    expect(find.text('Ver fotos (2)'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}

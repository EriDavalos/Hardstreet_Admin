// ==================================================================
// ARRANQUE DEL PANEL
// ==================================================================
// Bug reportado: al entrar a la app se veía el Dashboard y, cuando por fin
// llegaban los permisos, la app saltaba al PRIMER módulo que el rol puede ver.
// Ese cambio de módulo no debe verse: mientras se leen los permisos se muestra
// la pantalla de carga y el panel aparece YA en su módulo. Y si los permisos no
// se pueden leer (sin conexión), se dice que falta la conexión en vez de dibujar
// el panel completo como si todo estuviera permitido.
// ==================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hardstreet_admin/back_nav.dart';
import 'package:hardstreet_admin/drive_api_service.dart';
import 'package:hardstreet_admin/drive_scope.dart';
import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/hs_access.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/main.dart';
import 'package:hardstreet_admin/pages/admin_pages.dart';
import 'package:hardstreet_admin/pages/client_dashboard_page.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';

Map<String, dynamic> _mod(
  String key,
  String name, {
  required int order,
  List<String> actions = const ['read'],
}) => {
  'key': key,
  'name': name,
  'order': order,
  'categoryKey': null,
  'categoryName': null,
  'categoryOrder': null,
  'actions': actions,
};

/// Permisos del rol: Dashboard SIN "Ver" y "Mi paquete" CON "Ver", así el
/// primer módulo permitido (el que debe abrirse) NO es el Dashboard.
List<Map<String, dynamic>> _modules() => [
  _mod('dashboard', 'Dashboard', order: 1, actions: const []),
  _mod('my_package', 'Mi paquete', order: 2),
  _mod('drive', 'Archivos', order: 3),
];

/// Mock del backend. [gate] retrasa la respuesta de permisos (para poder mirar
/// la pantalla de carga); [failPermissions] hace que no se puedan leer;
/// [modules] cambia los permisos (orden y "Ver") del rol.
MockClient _mock({
  Completer<void>? gate,
  bool failPermissions = false,
  List<Map<String, dynamic>>? modules,
}) {
  return MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;
    if (path.endsWith('/api/admin/permission')) {
      if (gate != null) await gate.future;
      if (failPermissions) {
        return http.Response(
          jsonEncode({'error': 'No hay conexión'}),
          500,
          headers: headers,
        );
      }
      return http.Response(
        jsonEncode({'isAdmin': false, 'modules': modules ?? _modules()}),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/my/drive')) {
      return http.Response(
        jsonEncode({'isClient': false, 'paths': const []}),
        200,
        headers: headers,
      );
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

Future<Directory> _tempDir(WidgetTester tester) async {
  late Directory tmp;
  await tester.runAsync(() async {
    tmp = await Directory.systemTemp.createTemp('hardstreet_panel_start');
  });
  addTearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });
  return tmp;
}

/// El MISMO mensaje que mandan Android y el motor web al pulsar ATRÁS.
Future<void> _pressBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _pumpPanel(WidgetTester tester, Directory tmp) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    DriveScope(
      drive: DriveService.testRoot(tmp),
      child: MaterialApp(
        home: AdminHome(dark: false, onToggleTheme: () {}, onLogout: () {}),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HsAccess.reset(); // permisos sin cargar: como al abrir la app
  });
  tearDown(() {
    HsAccess.reset();
    HsSession.clear();
    DriveApiService.client = http.Client();
  });

  testWidgets('mientras se leen los permisos no se dibuja ningún módulo', (
    tester,
  ) async {
    final tmp = await _tempDir(tester);
    final previous = HsApi.client;
    final gate = Completer<void>();
    HsApi.client = _mock(gate: gate);
    addTearDown(() => HsApi.client = previous);

    await _pumpPanel(tester, tmp);
    await tester.pump();

    expect(
      find.text('Preparando tu panel…'),
      findsOneWidget,
      reason: 'la pantalla de carga tapa el momento en que se decide el menú',
    );
    expect(
      find.byType(DashboardPage),
      findsNothing,
      reason: 'el Dashboard no debe verse para luego saltar a otro módulo',
    );
    expect(find.byType(ClientDashboardPage), findsNothing);

    // Llegan los permisos: el panel aparece DIRECTO en su módulo (Mi paquete).
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ClientDashboardPage), findsOneWidget);
    expect(find.byType(DashboardPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin poder leer los permisos se avisa que falta la conexión', (
    tester,
  ) async {
    final tmp = await _tempDir(tester);
    final previous = HsApi.client;
    var fail = true;
    HsApi.client = MockClient((request) async {
      final headers = {'content-type': 'application/json'};
      if (request.url.path.endsWith('/api/admin/permission') && fail) {
        return http.Response(
          jsonEncode({'error': 'sin red'}),
          500,
          headers: headers,
        );
      }
      if (request.url.path.endsWith('/api/admin/permission')) {
        return http.Response(
          jsonEncode({'isAdmin': false, 'modules': _modules()}),
          200,
          headers: headers,
        );
      }
      return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
    });
    addTearDown(() => HsApi.client = previous);

    await _pumpPanel(tester, tmp);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Falta la conexión'), findsOneWidget);
    expect(
      find.byType(DashboardPage),
      findsNothing,
      reason: 'sin permisos no se dibuja el panel entero',
    );
    expect(find.byType(ClientDashboardPage), findsNothing);

    // Vuelve la conexión y el botón Reintentar carga el panel de verdad.
    fail = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Falta la conexión'), findsNothing);
    expect(find.byType(ClientDashboardPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el atrás vuelve al módulo de inicio y pregunta antes de salir', (
    tester,
  ) async {
    final tmp = await _tempDir(tester);
    final previous = HsApi.client;
    HsApi.client = _mock();
    addTearDown(() => HsApi.client = previous);
    BackNav.resetForTest();

    // Arranca en "Mi paquete" (su primer módulo permitido).
    await _pumpPanel(tester, tmp);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ClientDashboardPage), findsOneWidget);

    // Se va a OTRO módulo desde el menú (el panel de navegación se abre con
    // la hamburguesa; cerrado queda deslizado fuera de la vista).
    await tester.tap(find.byTooltip('Menú'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Archivos').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(DrivePage), findsOneWidget);

    // Atrás: vuelve al módulo de INICIO, no sale de la app.
    await _pressBack(tester);
    expect(find.byType(ClientDashboardPage), findsOneWidget);
    expect(find.byType(DrivePage), findsNothing);

    // Ya en el inicio: pregunta antes de salir.
    await _pressBack(tester);
    expect(find.text('¿Salir de la app?'), findsOneWidget);

    // Cancelar = seguir dentro.
    await tester.tap(find.text('Cancelar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('¿Salir de la app?'), findsNothing);
    expect(find.byType(ClientDashboardPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el CLIENTE vuelve a "Mi paquete" aunque el menú empiece por '
      'Dashboard', (tester) async {
    final tmp = await _tempDir(tester);
    final previous = HsApi.client;
    // El rol SÍ puede ver el Dashboard y es el PRIMER módulo del menú; aun así
    // el cliente entra (y vuelve) por su paquete.
    HsApi.client = _mock(
      modules: [
        _mod('dashboard', 'Dashboard', order: 1),
        _mod('my_package', 'Mi paquete', order: 2),
        _mod('drive', 'Archivos', order: 3),
      ],
    );
    addTearDown(() => HsApi.client = previous);
    BackNav.resetForTest();
    HsSession.setUser({'role': 'cliente', 'name': 'Cliente'});

    await _pumpPanel(tester, tmp);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byType(ClientDashboardPage),
      findsOneWidget,
      reason: 'el cliente abre en su paquete, no en el Dashboard',
    );

    // Se va a Archivos y pulsa atrás: vuelve a Mi paquete.
    await tester.tap(find.byTooltip('Menú'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Archivos').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(DrivePage), findsOneWidget);

    await _pressBack(tester);
    expect(find.byType(ClientDashboardPage), findsOneWidget);
    expect(find.byType(DrivePage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el resto del equipo vuelve al DASHBOARD aunque su menú empiece '
      'por Archivos', (tester) async {
    final tmp = await _tempDir(tester);
    final previous = HsApi.client;
    // En la BD "Archivos" va primero (order 1). El atrás ya NO sigue ese
    // orden: el equipo vuelve al Dashboard.
    HsApi.client = _mock(
      modules: [
        _mod('drive', 'Archivos', order: 1),
        _mod('dashboard', 'Dashboard', order: 2),
        _mod('my_package', 'Mi paquete', order: 3),
      ],
    );
    addTearDown(() => HsApi.client = previous);
    BackNav.resetForTest();
    HsSession.setUser({'role': 'admin', 'name': 'Admin'});

    await _pumpPanel(tester, tmp);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byType(DashboardPage),
      findsOneWidget,
      reason: 'el equipo abre en el Dashboard aunque Archivos vaya primero',
    );

    await tester.tap(find.byTooltip('Menú'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Archivos').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(DrivePage), findsOneWidget);

    await _pressBack(tester);
    expect(find.byType(DashboardPage), findsOneWidget);
    expect(find.byType(DrivePage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el drive remoto pide su listado en cuanto hay sesión', (
    tester,
  ) async {
    final previousApi = HsApi.client;
    HsApi.client = _mock();
    addTearDown(() => HsApi.client = previousApi);

    // Al crear el cliente del drive TODAVÍA no hay sesión (la app se construye
    // antes del login): su primer refresco se omite y no sale una petición sin
    // permiso, que era el error que se veía al abrir la app.
    HsSession.clear();
    final pedidos = <http.BaseRequest>[];
    DriveApiService.client = MockClient((request) async {
      pedidos.add(request);
      return http.Response(
        jsonEncode({'path': const [], 'folders': const []}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final drive = DriveApiService(baseUrl: 'http://drive.test');
    expect(pedidos, isEmpty, reason: 'sin sesión no se pide nada al servidor');

    // Entra la sesión y con ella el panel: el listado se pide CON el token.
    HsSession.token = 'tok-test';
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      DriveScope(
        drive: drive,
        child: MaterialApp(
          home: AdminHome(dark: false, onToggleTheme: () {}, onLogout: () {}),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      pedidos,
      isNotEmpty,
      reason: 'con sesión el drive ya pide el listado',
    );
    expect(
      pedidos.first.headers['Apikey'],
      'tok-test',
      reason: 'la petición del drive va autorizada',
    );
    expect(drive.error, isNull);
    expect(tester.takeException(), isNull);
  });
}

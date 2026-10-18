import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/activity_page.dart';
import 'package:hardstreet_admin/pages/services_page.dart';
import 'package:hardstreet_admin/pages/users_page.dart';
import 'package:hardstreet_admin/widgets/hs_pager.dart';

// ==================================================================
// PAGINADO DEL SERVIDOR + PIE FIJO
// ==================================================================
// 1) El listado pide `?page=&limit=` (nunca `all=1`) y usa el `total` que
//    devuelve el backend: la barra muestra "1–30 de 65" aunque en la página
//    solo vengan 30 filas.
// 2) La barra va en un PIE FIJO: al scrollear la lista no se mueve.
// 3) La búsqueda y los filtros viajan al servidor (q / role / link), con una
//    pequeña espera entre teclas.
// 4) Respuesta SIN `total` (backend viejo): el listado pagina en pantalla,
//    como antes.
// ==================================================================

Map<String, dynamic> _user(int n) => {
  'id': n,
  'name': 'Usuario $n',
  'lastname': '',
  'email': 'user$n@hardstreet.com',
  'role': n.isEven ? 'Fotógrafo' : 'Empleado',
  'roleId': n.isEven ? 3 : 2,
};

MockClient _usersMock(List<String> urls) => MockClient((request) async {
  final url = request.url;
  final headers = {'content-type': 'application/json'};
  if (url.path.endsWith('/api/admin/users')) {
    urls.add(url.toString());
    final page = int.parse(url.queryParameters['page'] ?? '1');
    final limit = int.parse(url.queryParameters['limit'] ?? '30');
    final role = url.queryParameters['role'] ?? '';
    // Con filtro de rol hay menos resultados (simula el backend).
    final total = role.isEmpty ? 65 : 15;
    final base = (page - 1) * limit;
    final count = (total - base).clamp(0, limit);
    return http.Response(
      jsonEncode({
        'users': [
          for (var i = 0; i < count; i++)
            if (role.isEmpty || _user(base + i + 1)['role'] == role)
              _user(base + i + 1),
        ],
        'total': total,
        'limit': limit,
        'page': page,
        'pages': (total + limit - 1) ~/ limit,
        'roleCounts': {'Empleado': 50, 'Fotógrafo': 15},
        'allTotal': 65,
      }),
      200,
      headers: headers,
    );
  }
  if (url.path.endsWith('/api/admin/roles')) {
    return http.Response(
      jsonEncode({
        'roles': [
          {'id': 1, 'name': 'Admin', 'permissions': []},
          {'id': 2, 'name': 'Empleado', 'permissions': []},
          {'id': 3, 'name': 'Fotógrafo', 'permissions': []},
        ],
      }),
      200,
      headers: headers,
    );
  }
  return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
});

Future<void> _pumpUsers(WidgetTester tester, List<String> urls) async {
  HsSession.token = 't';
  HsSession.user = {'email': 'ana@hardstreet.com', 'role': 'Admin'};
  HsApi.client = _usersMock(urls);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 900);
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: UsersPage())));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  final previous = HsApi.client;
  tearDown(() {
    HsApi.client = previous;
    HsSession.clear();
  });

  testWidgets('pide una página al backend y la barra usa SU total', (
    tester,
  ) async {
    final urls = <String>[];
    await _pumpUsers(tester, urls);

    // Nada de `all=1`: el listado se trae solo la página.
    expect(urls.first, contains('page=1'));
    expect(urls.first, contains('limit=30'));
    expect(urls.first, isNot(contains('all=1')));

    // 30 filas en pantalla, pero la barra sabe que hay 65.
    expect(find.text('1–30 de 65'), findsOneWidget);

    // Siguiente página: se pide page=2 al servidor.
    await tester.tap(find.byKey(const ValueKey('hs-pager-next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(urls.last, contains('page=2'));
    expect(find.text('31–60 de 65'), findsOneWidget);
  });

  testWidgets('la barra de páginas queda FIJA al scrollear la lista', (
    tester,
  ) async {
    final urls = <String>[];
    await _pumpUsers(tester, urls);

    final pager = find.byType(HsPager);
    expect(pager, findsOneWidget);
    final before = tester.getRect(pager);
    // Está abajo, dentro de la pantalla (no al final de 30 filas).
    expect(before.bottom, lessThanOrEqualTo(900));

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(find.text('Usuario 1'), findsOneWidget);
    // Se arrastra DESDE una fila (el gesto va a la lista, no al buscador).
    await tester.drag(find.text('Usuario 2'), const Offset(0, -600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final after = tester.getRect(pager);
    expect(
      after.top,
      closeTo(before.top, .5),
      reason: 'el pie no se va con el scroll',
    );
    // El contenido SÍ se movió: el pie no acompaña al scroll.
    expect(scrollable.position.pixels, greaterThan(0));
  });

  testWidgets('buscador y filtro viajan al servidor (q / role)', (
    tester,
  ) async {
    final urls = <String>[];
    await _pumpUsers(tester, urls);

    await tester.enterText(find.byType(TextField).first, 'ana');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(urls.last, contains('q=ana'));
    expect(urls.last, contains('page=1'));

    // El módulo de filtros trae los conteos que mandó el backend.
    await tester.tap(find.byKey(const ValueKey('hs-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fotógrafo').last);
    await tester.pump();
    await tester.tap(find.textContaining('Aplicar'));
    await tester.pumpAndSettle();

    expect(urls.last, contains('role=Fot'));
    expect(find.text('Fotógrafo'), findsWidgets);
  });

  testWidgets('servicios filtra la liga en el servidor y pagina desde el pie', (
    tester,
  ) async {
    final urls = <String>[];
    HsApi.client = MockClient((request) async {
      final headers = {'content-type': 'application/json'};
      if (request.url.path.endsWith('/api/admin/services')) {
        urls.add(request.url.toString());
        return http.Response(
          jsonEncode({
            'services': [
              {'id': 1, 'name': 'Álbum', 'description': '', 'icon': ''},
            ],
            'total': 1,
            'limit': 30,
            'page': 1,
            'pages': 1,
            'linkCounts': {'with': 1, 'without': 0, 'all': 1},
          }),
          200,
          headers: headers,
        );
      }
      return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
    });
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ServicesPage())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(urls.first, contains('page=1'));
    expect(urls.first, isNot(contains('all=1')));
    expect(find.text('1–1 de 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('hs-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Con carpeta asignada'));
    await tester.pump();
    await tester.tap(find.textContaining('Aplicar'));
    await tester.pumpAndSettle();
    expect(urls.last, contains('link=con'));
  });

  testWidgets(
    'actividad pide page (no offset) y muestra el total del backend',
    (tester) async {
      final urls = <String>[];
      HsApi.client = MockClient((request) async {
        final headers = {'content-type': 'application/json'};
        if (request.url.path.endsWith('/api/admin/activity')) {
          urls.add(request.url.toString());
          return http.Response(
            jsonEncode({
              'entries': [
                {
                  'id': 1,
                  'userId': 1,
                  'userName': 'Ana',
                  'roleName': 'Admin',
                  'module': 'clientes',
                  'moduleName': 'Clientes',
                  'action': 'create',
                  'entity': 'cliente',
                  'entityId': 2,
                  'description': 'Cliente creado',
                  'created': '2026-10-16T10:00:00',
                },
              ],
              'total': 41,
              'limit': 30,
              'page': 1,
              'pages': 2,
              'moduleCounts': {'Clientes': 41},
              'actionCounts': {'create': 41},
            }),
            200,
            headers: headers,
          );
        }
        return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
      });
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ActivityPage())),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(urls.first, contains('page=1'));
      expect(urls.first, isNot(contains('offset=')));
      expect(find.text('1–30 de 41'), findsOneWidget);
      expect(find.text('41 registros'), findsOneWidget);
    },
  );

  test(
    'HsPageResult: con total pagina en el servidor; sin total, en la app',
    () {
      final server = HsPageResult.from({
        'users': [_user(1)],
        'total': 65,
        'limit': 30,
        'page': 2,
        'pages': 3,
      }, 'users');
      expect(server.serverPaged, isTrue);
      expect(server.total, 65);
      expect(server.page, 2);
      expect(server.pages, 3);

      final legacy = HsPageResult.from({
        'users': [_user(1), _user(2)],
      }, 'users');
      expect(legacy.serverPaged, isFalse);
      expect(legacy.total, 2);
      expect(legacy.pages, 1);
    },
  );
}

import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/drive_base.dart';
import 'package:hardstreet_admin/drive_scope.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/local_share_service.dart';
import 'package:hardstreet_admin/pages/shared_files_page.dart';
import 'package:hardstreet_admin/share_permissions.dart';

/// Escritura DENTRO de una carpeta compartida (renombrar, mover).
///
/// Lo que se comprueba:
///   * renombrar una imagen CONSERVA su extensión (sin ella desaparecía del
///     listado y parecía que el renombrado la borraba),
///   * si el servidor rechaza una acción (permiso, app del dueño cerrada…) el
///     módulo lo DICE, en vez de fallar en silencio.
class _FakeDrive extends DriveBase {
  @override
  Future<void> refresh() async {}
  @override
  Future<List<String>> listChildFolders(List<String> rel) async => const [];
  @override
  List<String> listFolders(List<String> rel) => const [];
  @override
  String absolutePathOf(DriveItem item) => [...path, item.name].join('/');
  @override
  Future<int> uploadFromPaths(List<String> sources,
          {bool overwrite = false}) async =>
      0;
  @override
  Future<void> createFolder(String name) async {}
  @override
  Future<void> rename(DriveItem item, String newName) async {}
  @override
  Future<void> delete(DriveItem item) async {}
  @override
  Future<({int moved, List<String> errors})> moveItems(
          List<String> names, List<String> targetPath) async =>
      (moved: 0, errors: const <String>[]);
  @override
  Future<({int copied, List<String> errors})> copyItems(
          List<String> names, List<String> targetPath) async =>
      (copied: 0, errors: const <String>[]);
  @override
  Future<({int deleted, List<String> errors})> deleteItems(
          List<String> names) async =>
      (deleted: 0, errors: const <String>[]);
  @override
  Future<void> retryUpload(String jobId) async {}
}

/// Servidor del drive falso CON ESTADO (permite escribir y lo recuerda).
class _Server {
  _Server({this.moveError});

  /// Mensaje que devuelve /api/local/move (null = funciona).
  final String? moveError;

  final calls = <String>[];
  final tree = <String, List<Map<String, dynamic>>>{
    '': [
      {'name': 'Sub', 'isFolder': true},
      {'name': 'foto.jpg', 'isFolder': false, 'size': 10},
    ],
    'Sub': [],
  };

  LocalShareService service() => LocalShareService(
        baseUrl: 'http://drive.test',
        client: MockClient((request) async {
          final p = request.url.path;
          calls.add('${request.method} $p');
          const headers = {'content-type': 'application/json'};
          if (p == '/api/local/status') {
            return http.Response(
              jsonEncode({
                'available': true,
                'servedFrom': 'server',
                'permissions': {
                  'view': true,
                  'edit': true,
                  'create': true,
                  'download': true,
                },
              }),
              200,
              headers: headers,
            );
          }
          if (p == '/api/local/list') {
            final path = request.url.queryParameters['path'] ?? '';
            return http.Response(
              jsonEncode({
                'local': false,
                'path': path,
                'folders': tree[path] ?? const [],
              }),
              200,
              headers: headers,
            );
          }
          if (p == '/api/local/item' && request.method == 'PATCH') {
            final b = jsonDecode(request.body) as Map<String, dynamic>;
            final rel = '${b['path']}'.split('/');
            final dir = rel.sublist(0, rel.length - 1).join('/');
            final name = rel.last;
            final list = tree[dir] ?? [];
            final i = list.indexWhere((e) => e['name'] == name);
            if (i >= 0) list[i] = {...list[i], 'name': '${b['name']}'};
            return http.Response(jsonEncode({'ok': true}), 200,
                headers: headers);
          }
          if (p == '/api/local/move') {
            if (moveError != null) {
              return http.Response(
                jsonEncode({'error': moveError}),
                403,
                headers: headers,
              );
            }
            return http.Response(
              jsonEncode({'ok': true, 'moved': 1, 'errors': const []}),
              200,
              headers: headers,
            );
          }
          return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
        }),
      );
}

void main() {
  setUp(() => HsApi.client = http.Client());
  tearDown(() {
    HsApi.client = http.Client();
    debugLocalShareService = null;
  });

  Future<void> pumpModule(WidgetTester tester, _Server server) async {
    HsApi.client = MockClient((request) async {
      const headers = {'content-type': 'application/json'};
      if (request.url.path.endsWith('/api/admin/shared-files') &&
          request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'ok': true,
            'item': {
              'shared': const [],
              'received': [
                {
                  'shareId': 5,
                  'path': 'Estudio 2026',
                  'owners': [
                    {'id': 9, 'name': 'Yusef Ali'},
                  ],
                  'permissions': {
                    'view': true,
                    'edit': true,
                    'create': true,
                    'download': true,
                  },
                },
              ],
              'candidates': const [],
            },
            'canShare': true,
            'canDelete': true,
          }),
          200,
          headers: headers,
        );
      }
      return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
    });
    debugLocalShareService = () => server.service();

    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      DriveScope(
        drive: _FakeDrive(),
        child: const MaterialApp(home: Scaffold(body: SharedFilesPage())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Doble clic con el ratón abre la carpeta compartida.
    final folder = find.text('Estudio 2026');
    await tester.tap(folder, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.tap(folder, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  }

  testWidgets('renombrar una imagen compartida conserva su extensión',
      (tester) async {
    final server = _Server();
    await pumpModule(tester, server);

    await tester.tap(find.text('foto.jpg'),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Renombrar'), findsOneWidget);

    await tester.tap(find.text('Renombrar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(
      find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Nuevo nombre'),
      'otra',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(server.calls, contains('PATCH /api/local/item'));
    expect(find.text('otra.jpg'), findsOneWidget,
        reason: 'la imagen se quedó sin extensión (desapareció del listado)');
  });

  testWidgets('si el servidor rechaza MOVER, el módulo lo dice',
      (tester) async {
    final server = _Server(moveError: 'No tienes permiso para editar');
    await pumpModule(tester, server);

    // Selecciona la imagen y abre "Mover a...".
    await tester.tap(find.text('foto.jpg'), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Mover a...'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Mover aquí'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(server.calls, contains('POST /api/local/move'));
    expect(find.textContaining('No tienes permiso'), findsWidgets,
        reason: 'el fallo del movimiento se perdió en silencio');
  });

  test('los permisos del servidor del drive mandan al abrir', () {
    // La vista de una carpeta compartida usa los permisos que devuelve
    // /api/local/status (los mismos que el servidor exige después).
    final s = LocalShareStatus.fromJson({
      'servedFrom': 'server',
      'permissions': {'view': true, 'edit': true, 'create': false},
    });
    expect(s.permissionsKnown, isTrue);
    expect(s.permissions.edit, isTrue);
    expect(s.permissions.create, isFalse);
    expect(SharePermissions.readOnly.edit, isFalse);
  });
}

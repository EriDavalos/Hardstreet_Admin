import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/drive_base.dart';
import 'package:hardstreet_admin/drive_scope.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/clients_page.dart';

/// Drive de prueba con un árbol FIJO de carpetas (sin red).
class _FakeDrive extends DriveBase {
  static const Map<String, List<String>> tree = {
    '': ['ReynaCoot', 'Cliente', 'Privado'],
    'ReynaCoot': ['SesionPrevia', 'Fiesta'],
    'Cliente': <String>[],
    'Privado': <String>[],
  };

  @override
  Future<void> refresh() async {
    updateItems([
      for (final n in tree[path.join('/')] ?? const <String>[])
        DriveItem(name: n, isFolder: true),
    ]);
    loadedPath = pathLabel;
    conn = DriveConn.online;
  }

  @override
  Future<List<String>> listChildFolders(List<String> rel) async =>
      tree[rel.join('/')] ?? const <String>[];

  @override
  List<String> listFolders(List<String> rel) =>
      tree[rel.join('/')] ?? const <String>[];

  @override
  String absolutePathOf(DriveItem item) => [...path, item.name].join('/');

  @override
  Future<int> uploadFromPaths(List<String> sources, {bool overwrite = false}) async =>
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

/// Paquete del cliente con su carpeta compartida (la que se edita aquí).
void _installMock({required List<Map<String, dynamic>> posts, required _Shared path}) {
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final p = request.url.path;

    if (p.endsWith('/api/admin/client-packages')) {
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

    if (p.endsWith('/api/admin/agendas')) {
      return http.Response(jsonEncode({'agendas': const []}), 200,
          headers: headers);
    }

    if (p.endsWith('/api/admin/package-progress')) {
      if (request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, dynamic>();
        posts.add(body);
        if (body['action'] == 'compartir-directorio') {
          path.value = (body['path'] ?? '').toString();
        }
        return http.Response(jsonEncode({'ok': true}), 201, headers: headers);
      }
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
            'finishedAt': null,
            'drivePath': path.value,
          },
          'services': const [],
          'movements': const [],
          'movementsAvailable': true,
          'totals': const {'abonado': 6000, 'disponible': 5200},
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

/// Carpeta compartida mutable (el mock la devuelve y el POST la actualiza).
class _Shared {
  _Shared(this.value);
  String value;
}

Future<void> _pump(WidgetTester tester,
    {required List<Map<String, dynamic>> posts,
    required _Shared path,
    required _FakeDrive drive}) async {
  const size = Size(1250, 940);
  await tester.binding.setSurfaceSize(size);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final previous = HsApi.client;
  _installMock(posts: posts, path: path);
  addTearDown(() => HsApi.client = previous);

  await tester.pumpWidget(
    DriveScope(
      drive: drive,
      child: MaterialApp(
        home: Scaffold(
          body: ClientPackagesDialog(
            client: const {'id': 7, 'name': 'Ana', 'lastname': 'Ruiz'},
          ),
        ),
      ),
    ),
  );
  await tester.pump(); // client-packages + agendas
  await tester.pump(); // detalle del paquete
  await tester.pump(const Duration(milliseconds: 400));
  // Entra al detalle del paquete (tarjeta) y a la pestaña Drive.
  await _tap(tester, find.text('Boda - Premium').first);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Finder _inDialog(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(text),
    );

void main() {
  testWidgets('paquete del cliente: la pestaña Drive COMPARTE una carpeta',
      (tester) async {
    final posts = <Map<String, dynamic>>[];
    final path = _Shared('');
    await _pump(tester,
        posts: posts, path: path, drive: _FakeDrive());

    await _tap(tester, find.text('Drive'));

    // Sin carpeta compartida, el paquete lo dice claramente.
    expect(find.text('Sin carpeta compartida'), findsOneWidget);

    // Se elige del Drive: ReynaCoot / SesionPrevia.
    await _tap(tester, find.text('Elegir carpeta del Drive'));
    await _tap(tester, _inDialog('ReynaCoot'));
    await _tap(tester, _inDialog('SesionPrevia'));
    await _tap(tester, _inDialog('Compartir esta carpeta'));

    expect(posts, hasLength(1));
    expect(posts.first['action'], 'compartir-directorio');
    expect(posts.first['purchasedPackageId'], 10);
    expect(posts.first['path'], 'ReynaCoot/SesionPrevia');

    // La pestaña ya muestra la carpeta compartida.
    expect(find.text('ReynaCoot/SesionPrevia'), findsOneWidget);
    expect(find.text('Sin carpeta compartida'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paquete del cliente: se puede DEJAR de compartir',
      (tester) async {
    final posts = <Map<String, dynamic>>[];
    final path = _Shared('ReynaCoot');
    await _pump(tester,
        posts: posts, path: path, drive: _FakeDrive());

    await _tap(tester, find.text('Drive'));
    expect(find.text('ReynaCoot'), findsOneWidget);

    await _tap(tester, find.text('Dejar de compartir'));

    expect(posts, hasLength(1));
    expect(posts.first['action'], 'compartir-directorio');
    expect(posts.first['path'], '');
    expect(find.text('Sin carpeta compartida'), findsOneWidget);
  });
}

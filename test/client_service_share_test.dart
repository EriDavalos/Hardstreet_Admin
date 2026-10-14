import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/drive_base.dart';
import 'package:hardstreet_admin/drive_scope.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/client_dashboard_page.dart';
import 'package:hardstreet_admin/widgets/hs_toast.dart';

/// Drive de prueba: carpetas y ARCHIVOS fijos, sin red. El selector de fotos
/// del cliente navega esto (`listFolderItems`) sin mover la vista de Archivos.
class _FakeDrive extends DriveBase {
  static const Map<String, List<DriveItem>> tree = {
    '': [
      DriveItem(name: 'ReynaCoot', isFolder: true),
      DriveItem(name: 'Cliente', isFolder: true),
    ],
    'ReynaCoot': [
      DriveItem(name: 'portada.jpg', isFolder: false),
      DriveItem(name: 'fiesta.jpg', isFolder: false),
    ],
    'Cliente': [DriveItem(name: 'extra.png', isFolder: false)],
  };

  @override
  Future<void> refresh() async {
    updateItems(tree[path.join('/')] ?? const <DriveItem>[]);
    loadedPath = pathLabel;
    conn = DriveConn.online;
  }

  @override
  Future<List<DriveItem>> listFolderItems(List<String> rel) async =>
      tree[rel.join('/')] ?? const <DriveItem>[];

  @override
  Future<List<String>> listChildFolders(List<String> rel) async =>
      (tree[rel.join('/')] ?? const <DriveItem>[])
          .where((i) => i.isFolder)
          .map((i) => i.name)
          .toList(growable: false);

  @override
  List<String> listFolders(List<String> rel) => (tree[rel.join('/')] ??
          const <DriveItem>[])
      .where((i) => i.isFolder)
      .map((i) => i.name)
      .toList(growable: false);

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

/// Un paquete con UN servicio que ya trae carpeta compartida, liga y UNA foto
/// elegida por el cliente.
List<Map<String, dynamic>> _packages() => [
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
            'description': '',
            'status': {'id': 2, 'name': 'En proceso'},
            'shareFolder': 'ReynaCoot',
            'shareLink': 'https://ejemplo.mx/album',
            'items': 1,
            'service': {'id': 2, 'name': 'Álbum de fotos', 'icon': '', 'url': ''},
          },
        ],
      },
    ];

/// Mock: paquetes, carpetas compartidas y la SELECCIÓN de elementos.
/// `saved` acumula los cuerpos de los PUT a /api/my/service-items.
void _installMock({required List<Map<String, dynamic>> puts}) {
  var items = <String>['ReynaCoot/portada.jpg'];
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final p = request.url.path;

    if (p.endsWith('/api/my/packages')) {
      final packages = _packages();
      (packages.first['services'] as List).first['items'] = items.length;
      return http.Response(jsonEncode({'purchasedPackages': packages}), 200,
          headers: headers);
    }
    if (p.endsWith('/api/my/drive')) {
      return http.Response(
        jsonEncode({
          'isClient': true,
          'paths': [
            {'packageId': 11, 'packageName': 'Boda', 'path': 'ReynaCoot'},
          ],
        }),
        200,
        headers: headers,
      );
    }
    if (p.endsWith('/api/my/service-items')) {
      if (request.method == 'PUT') {
        final body = (jsonDecode(request.body) as Map).cast<String, dynamic>();
        puts.add(body);
        items = ((body['paths'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList();
        return http.Response(
          jsonEncode({'serviceId': body['serviceId'], 'items': items}),
          200,
          headers: headers,
        );
      }
      return http.Response(
        jsonEncode({'serviceId': 101, 'items': items}),
        200,
        headers: headers,
      );
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

Future<void> _pump(WidgetTester tester,
    {void Function(List<String>)? onOpenDrive}) async {
  await tester.binding.setSurfaceSize(const Size(1100, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    DriveScope(
      drive: _FakeDrive(),
      child: MaterialApp(
        builder: (context, child) =>
            HsToastHost(child: child ?? const SizedBox.shrink()),
        home: Scaffold(
          body: ClientDashboardPage(onOpenDrive: onOpenDrive),
        ),
      ),
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
  testWidgets('cada servicio ofrece carpeta, liga y elegir fotos',
      (tester) async {
    _installMock(puts: []);
    await _pump(tester);

    expect(find.text('Abrir carpeta'), findsOneWidget);
    expect(find.text('Ver liga'), findsOneWidget);
    // El conteo que ya tenía guardado el cliente.
    expect(find.text('Mis fotos (1)'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('"Abrir carpeta" entra a la carpeta compartida del servicio',
      (tester) async {
    _installMock(puts: []);
    final opened = <List<String>>[];
    await _pump(tester, onOpenDrive: opened.add);

    await _tap(tester, find.text('Abrir carpeta'));

    expect(opened, hasLength(1));
    expect(opened.single, ['ReynaCoot']);
  });

  testWidgets('el cliente elige fotos de SU drive y se guarda la lista',
      (tester) async {
    final puts = <Map<String, dynamic>>[];
    _installMock(puts: puts);
    await _pump(tester);

    await _tap(tester, find.text('Mis fotos (1)'));

    // El selector arranca en la raíz de lo compartido.
    expect(find.text('Elegir fotos · Álbum de fotos'), findsOneWidget);
    expect(find.text('1 elegidos'), findsOneWidget);

    // Entrar a la carpeta compartida y marcar OTRA foto (el nombre también
    // aparece en la tarjeta del Drive de la página: se toma el del diálogo).
    await _tap(tester, find.text('ReynaCoot').last);
    expect(find.text('portada.jpg'), findsOneWidget);
    await _tap(tester, find.text('fiesta.jpg'));

    expect(find.text('2 elegidos'), findsOneWidget);

    await _tap(tester, find.text('Guardar selección'));

    expect(puts, hasLength(1));
    expect(puts.single['serviceId'], 101);
    expect(puts.single['paths'], ['ReynaCoot/fiesta.jpg', 'ReynaCoot/portada.jpg']);
    expect(find.text('Selección guardada'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}

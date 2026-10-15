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
    '': ['ReynaCoot', 'Cliente'],
    'ReynaCoot': ['SesionPrevia'],
    'Cliente': <String>[],
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

/// Cliente con DOS paquetes: el vigente (el que se administra, sin carpeta) y
/// otro que YA tiene compartida `Reynacoot`.
void _installMock({required List<Map<String, dynamic>> posts}) {
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
              'drivePath': '',
              'drivePaths': const [],
              'services': const [],
            },
            {
              'usersPackageId': 29,
              'id': 11,
              'name': 'XV Años - Gold',
              'subtitle': '',
              'description': '',
              'price': 7500,
              'paid': 7500,
              'currency': 'MXN',
              'status': 'Terminado',
              'packageId': 5,
              'tierName': 'Gold',
              'categoryName': 'XV Años',
              'agendaCount': 0,
              // ESTA es la carpeta ya compartida con el cliente.
              'drivePath': 'ReynaCoot',
              'drivePaths': const ['ReynaCoot'],
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
        posts.add((jsonDecode(request.body) as Map).cast<String, dynamic>());
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
            'drivePath': '',
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

Future<void> _pump(WidgetTester tester,
    {required List<Map<String, dynamic>> posts}) async {
  const size = Size(1250, 940);
  await tester.binding.setSurfaceSize(size);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final previous = HsApi.client;
  _installMock(posts: posts);
  addTearDown(() => HsApi.client = previous);

  await tester.pumpWidget(
    DriveScope(
      drive: _FakeDrive(),
      child: MaterialApp(
        home: Scaffold(
          body: ClientPackagesDialog(
            client: const {'id': 7, 'name': 'Ana', 'lastname': 'Ruiz'},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await _tap(tester, find.text('Boda - Premium').first);
  await _tap(tester, find.text('Drive'));
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
  group('drivePathsOverlap', () {
    test('la misma carpeta se solapa consigo misma', () {
      expect(drivePathsOverlap('ReynaCoot', 'ReynaCoot'), isTrue);
    });

    test('contenida dentro de otra: se solapan (en los dos sentidos)', () {
      expect(drivePathsOverlap('ReynaCoot/SesionPrevia', 'ReynaCoot'), isTrue);
      expect(drivePathsOverlap('ReynaCoot', 'ReynaCoot/SesionPrevia'), isTrue);
    });

    test('carpetas hermanas NO se solapan', () {
      expect(drivePathsOverlap('ReynaCoot', 'Cliente'), isFalse);
      expect(drivePathsOverlap('ReynaCoot/A', 'ReynaCoot/B'), isFalse);
    });

    test('un prefijo de texto no es estar dentro', () {
      // "ReynaCoot2" NO está dentro de "ReynaCoot" (no es un nivel de carpeta).
      expect(drivePathsOverlap('ReynaCoot2', 'ReynaCoot'), isFalse);
    });

    test('normaliza barras, espacios y puntos', () {
      expect(drivePathNormalize(r'\ReynaCoot\SesionPrevia\'),
          'ReynaCoot/SesionPrevia');
      expect(drivePathsOverlap('  ReynaCoot  ', './ReynaCoot/'), isTrue);
      // Los '..' se DESCARTAN, no se resuelven hacia arriba (la misma regla
      // que aplica el backend al guardar la ruta compartida).
      expect(drivePathNormalize('ReynaCoot/../Cliente'), 'ReynaCoot/Cliente');
      expect(drivePathsOverlap('ReynaCoot/../Cliente', 'Cliente'), isFalse);
      expect(drivePathsOverlap('', 'ReynaCoot'), isFalse);
    });
  });

  testWidgets(
      'no deja compartir una carpeta que se solapa con la de otro paquete',
      (tester) async {
    final posts = <Map<String, dynamic>>[];
    await _pump(tester, posts: posts);

    await _tap(tester, find.text('Compartir una carpeta del Drive'));

    // La carpeta ya compartida aparece BLOQUEADA, con el motivo a la vista.
    expect(_inDialog('Ya compartida en «ReynaCoot»'), findsOneWidget);

    // Tocarla no entra: se queda en la raíz ("Mi Drive").
    await _tap(tester, _inDialog('ReynaCoot'));
    expect(_inDialog('Mi Drive'), findsOneWidget);

    // Una carpeta sin choque sí se puede elegir y compartir.
    await _tap(tester, _inDialog('Cliente'));
    await _tap(tester, _inDialog('Compartir esta carpeta'));

    expect(posts, hasLength(1));
    // Se comparte al CLIENTE (el Drive no depende del paquete).
    expect(posts.first['action'], 'agregar-directorio-cliente');
    expect(posts.first['path'], 'Cliente');
    expect(tester.takeException(), isNull);
  });
}

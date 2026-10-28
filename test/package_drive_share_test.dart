import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/drive_base.dart';
import 'package:hardstreet_admin/drive_scope.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/clients_page.dart';
import 'package:hardstreet_admin/widgets/drive_folder_picker.dart';

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

/// Carpetas del PAQUETE (el mock las devuelve y el POST las cambia). Cada
/// paquete comparte UNA sola carpeta del Drive.
class _Shared {
  _Shared(this.value);
  List<String> value;
}

void _installMock({
  required List<Map<String, dynamic>> posts,
  required _Shared paths,
}) {
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
              'drivePaths': const [],
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
        final path = (body['path'] ?? '').toString();
        switch (body['action']) {
          // La carpeta es DEL PAQUETE: compartirla REEMPLAZA la anterior.
          case 'agregar-directorio':
          case 'compartir-directorio':
            paths.value = path.isEmpty ? <String>[] : [path];
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
            'drivePaths': paths.value,
            'clientDrivePaths': const [],
          },
          // Un servicio PENDIENTE con el que se prueba compartir su carpeta.
          'services': const [
            {
              'id': 1,
              'serviceId': 5,
              'name': 'Cobertura en evento',
              'description': '',
              'url': '',
              'status': 'Pendiente',
              'statusId': 1,
              'done': false,
              'finishedAt': null,
              'shareFolder': '',
              'shareLink': '',
              'items': 0,
            },
          ],
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

Future<void> _pump(
  WidgetTester tester, {
  required List<Map<String, dynamic>> posts,
  required _Shared paths,
  _FakeDrive? drive,
  Size size = const Size(1250, 940),
}) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final previous = HsApi.client;
  _installMock(posts: posts, paths: paths);
  addTearDown(() => HsApi.client = previous);

  await tester.pumpWidget(
    DriveScope(
      drive: drive ?? _FakeDrive(),
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
  testWidgets('la pestaña Drive comparte LA carpeta del PAQUETE',
      (tester) async {
    final posts = <Map<String, dynamic>>[];
    final paths = _Shared([]);
    await _pump(tester, posts: posts, paths: paths);

    await _tap(tester, find.text('Drive'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Sin carpeta en el paquete, lo dice claramente.
    expect(find.text('Sin carpeta en este paquete'), findsOneWidget);

    // Se elige del Drive: ReynaCoot / SesionPrevia.
    await _tap(tester, find.text('Compartir una carpeta del Drive'));
    await _tap(tester, _inDialog('ReynaCoot'));
    await _tap(tester, _inDialog('SesionPrevia'));
    await _tap(tester, _inDialog('Compartir esta carpeta'));

    // La carpeta es DEL PAQUETE (no se comparte al cliente entero).
    expect(posts, hasLength(1));
    expect(posts.first['action'], 'agregar-directorio');
    expect(posts.first['purchasedPackageId'], 10);
    expect(posts.first['path'], 'ReynaCoot/SesionPrevia');

    // La pestaña ya muestra la carpeta del paquete.
    expect(find.text('ReynaCoot/SesionPrevia'), findsOneWidget);
    expect(find.text('Sin carpeta en este paquete'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cambiar la carpeta REEMPLAZA la del paquete (una sola)',
      (tester) async {
    final posts = <Map<String, dynamic>>[];
    // El paquete YA tiene una carpeta.
    final paths = _Shared(['ReynaCoot']);
    await _pump(tester, posts: posts, paths: paths);

    await _tap(tester, find.text('Drive'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('ReynaCoot'), findsOneWidget);

    // Se elige otra carpeta del drive.
    await _tap(tester, find.text('Cambiar la carpeta'));
    await _tap(tester, _inDialog('Privado'));
    await _tap(tester, _inDialog('Compartir esta carpeta'));

    expect(posts, hasLength(1));
    expect(posts.first['action'], 'agregar-directorio');
    expect(posts.first['path'], 'Privado');
    // El paquete se queda con UNA carpeta: la nueva.
    expect(paths.value, ['Privado']);
    expect(find.text('Privado'), findsOneWidget);
    expect(find.text('ReynaCoot'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('se quita la carpeta del paquete', (tester) async {
    final posts = <Map<String, dynamic>>[];
    final paths = _Shared(['ReynaCoot']);
    await _pump(tester, posts: posts, paths: paths);

    await _tap(tester, find.text('Drive'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('ReynaCoot'), findsOneWidget);

    await _tap(
        tester, find.byTooltip('Dejar de compartir la carpeta del paquete'));
    await _tap(tester, find.text('Continuar'));

    expect(posts, hasLength(1));
    expect(posts.first['action'], 'compartir-directorio');
    expect(posts.first['path'], '');
    expect(paths.value, isEmpty);
    expect(find.text('Sin carpeta en este paquete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('las carpetas compartidas al CLIENTE no se ven en el paquete',
      (tester) async {
    final posts = <Map<String, dynamic>>[];
    final paths = _Shared(['ReynaCoot']);
    // El cliente tiene OTRA carpeta compartida directamente con él.
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
                'price': 12000,
                'paid': 6000,
                'currency': 'MXN',
                'status': 'En proceso',
                'drivePaths': paths.value,
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
        return http.Response(
          jsonEncode({
            'package': {
              'id': 10,
              'name': 'Boda - Premium',
              'price': 12000,
              'paid': 6000,
              'status': 'En proceso',
              'statusId': 2,
              'finished': false,
              'drivePaths': paths.value,
              'clientDrivePaths': const ['SoloDelCliente'],
            },
            'services': const [],
            'movements': const [],
            'totals': const {},
            'blockers': const [],
          }),
          200,
          headers: headers,
        );
      }
      return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
    });
    addTearDown(() => HsApi.client = MockClient((_) async =>
        http.Response(jsonEncode({'ok': true}), 200,
            headers: {'content-type': 'application/json'})));

    await tester.binding.setSurfaceSize(const Size(1250, 940));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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

    // Solo la carpeta DEL PAQUETE; la compartida al cliente no aparece aquí.
    expect(find.text('ReynaCoot'), findsOneWidget);
    expect(find.text('SoloDelCliente'), findsNothing);
    expect(posts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la carpeta de un SERVICIO se elige DENTRO del Drive del '
      'cliente: se ven sus subcarpetas y nada antes de ella', (tester) async {
    final posts = <Map<String, dynamic>>[];
    // El cliente ya tiene compartida ReynaCoot (con Fiesta y SesionPrevia).
    final paths = _Shared(['ReynaCoot']);
    await _pump(tester, posts: posts, paths: paths);

    await _tap(tester, find.text('Servicios'));
    await tester.pump(const Duration(milliseconds: 400));
    // Se despliega el servicio y se abre "Compartir".
    await _tap(tester, find.text('Cobertura en evento'));
    await _tap(tester, find.text('Compartir').last);
    await tester.pump(const Duration(milliseconds: 400));

    // El diálogo moderno del servicio: la tarjeta que abre el selector.
    expect(find.text('Compartir con el cliente'), findsOneWidget);
    await _tap(tester, find.text('Compartir una carpeta del Drive').last);
    await tester.pump(const Duration(milliseconds: 400));

    // El selector se abre DENTRO de la carpeta compartida: se ven sus
    // subcarpetas…
    expect(find.text('Fiesta'), findsOneWidget);
    expect(find.text('SesionPrevia'), findsOneWidget);
    // …y NADA de fuera de ella (ni las otras carpetas del drive ni la raíz).
    expect(find.text('Privado'), findsNothing);
    expect(find.text('Cliente'), findsNothing);
    expect(find.text('Mi Drive'), findsNothing);
    expect(find.text('Subir un nivel'), findsNothing);
    // La carpeta compartida es la raíz del selector y así se anuncia.
    expect(find.text('ReynaCoot'), findsOneWidget);
    // UNA sola raíz: no hay selector para saltar a otras carpetas compartidas
    // ni se ofrece el drive general del cliente. Solo el contenido de la
    // carpeta del paquete al que pertenece el servicio.
    expect(
      find.descendant(
        of: find.byType(DriveFolderPicker),
        matching: find.byType(ChoiceChip),
      ),
      findsNothing,
    );
    expect(find.text('SoloDelCliente'), findsNothing);

    // Se elige la subcarpeta y se guarda: la ruta queda completa.
    await _tap(tester, find.text('Fiesta'));
    await _tap(tester, find.text('Compartir esta carpeta'));
    await tester.pump(const Duration(milliseconds: 400));

    // Ya en el diálogo del servicio: la carpeta con su botón de DESVINCULAR.
    expect(find.text('ReynaCoot/Fiesta'), findsOneWidget);
    expect(find.text('Desvincular'), findsOneWidget);
    await _tap(tester, find.text('Guardar'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(posts, hasLength(1));
    expect(posts.first['action'], 'actualizar-servicio-share');
    expect(posts.first['folder'], 'ReynaCoot/Fiesta');
    expect(tester.takeException(), isNull);
  });

  testWidgets('en el CELULAR el selector de la carpeta no se desborda y '
      'avisa de dónde se elige', (tester) async {
    final posts = <Map<String, dynamic>>[];
    final paths = _Shared(['ReynaCoot']);
    await _pump(
      tester,
      posts: posts,
      paths: paths,
      size: const Size(430, 800),
    );

    // La tarjeta de la carpeta compartida con el cliente (con su botón de
    // desvincular) también cabe en el teléfono.
    await _tap(tester, find.text('Drive'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('ReynaCoot'), findsOneWidget);
    expect(find.text('Quitar'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _tap(tester, find.text('Servicios'));
    await tester.pump(const Duration(milliseconds: 400));
    await _tap(tester, find.text('Cobertura en evento'));
    await _tap(tester, find.text('Compartir').last);
    await tester.pump(const Duration(milliseconds: 400));
    await _tap(tester, find.text('Compartir una carpeta del Drive').last);
    await tester.pump(const Duration(milliseconds: 400));

    // El aviso de alcance y las subcarpetas de la carpeta compartida.
    expect(find.text('Carpeta del Drive'), findsWidgets);
    expect(
      find.text('Solo lo que está dentro del Drive del cliente'),
      findsOneWidget,
    );
    expect(find.text('Fiesta'), findsOneWidget);
    expect(find.text('SesionPrevia'), findsOneWidget);
    // Nada se sale de la pantalla del teléfono.
    expect(tester.takeException(), isNull);
  });
}

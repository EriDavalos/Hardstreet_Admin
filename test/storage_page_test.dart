import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_base.dart';
import 'package:hardstreet_admin/drive_scope.dart';
import 'package:hardstreet_admin/pages/storage_page.dart';

/// Drive de prueba: devuelve lo que el servidor contestaría en /api/space.
class _FakeDrive extends DriveBase {
  _FakeDrive(this.info);

  final Map<String, dynamic>? info;

  @override
  Future<Map<String, dynamic>?> storageInfo() async => info;

  @override
  Future<void> refresh() async {}

  @override
  List<String> listFolders(List<String> rel) => const <String>[];

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

const int _gb = 1024 * 1024 * 1024;

Future<void> _pump(WidgetTester tester, DriveBase drive) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    DriveScope(
      drive: drive,
      child: const MaterialApp(home: Scaffold(body: StoragePage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('muestra lo usado, la cuota y lo libre del disco',
      (tester) async {
    await _pump(
      tester,
      _FakeDrive({
        'root': 'C:/HardStreetDrive',
        'usedBytes': 45 * _gb,
        'files': 18342,
        'folders': 210,
        'totalBytes': 500 * _gb,
        'freeBytes': 380 * _gb,
        'limitGb': 180,
        'limitBytes': 180 * _gb,
        'limitFreeBytes': 135 * _gb,
      }),
    );

    expect(find.text('Almacenamiento'), findsOneWidget);
    expect(find.text('45.0 GB de 180 GB ocupados'), findsOneWidget);
    expect(find.text('25 %'), findsOneWidget);
    expect(find.text('18342'), findsOneWidget);
    expect(find.text('C:/HardStreetDrive'), findsOneWidget);
    expect(find.textContaining('DRIVE_LIMIT_GB'), findsOneWidget);
    // Al 25 % no hay avisos.
    expect(find.textContaining('85 %'), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('avisa cuando la cuota se está llenando (85 % o más)',
      (tester) async {
    await _pump(
      tester,
      _FakeDrive({
        'usedBytes': 160 * _gb,
        'files': 900,
        'folders': 40,
        'totalBytes': 500 * _gb,
        'freeBytes': 300 * _gb,
        'limitGb': 180,
        'limitBytes': 180 * _gb,
        'limitFreeBytes': 20 * _gb,
      }),
    );

    expect(find.text('89 %'), findsOneWidget);
    expect(find.textContaining('85 % o más de su cuota'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('avisa cuando el DISCO tiene menos libre que la cuota',
      (tester) async {
    await _pump(
      tester,
      _FakeDrive({
        'usedBytes': 20 * _gb,
        'files': 10,
        'folders': 2,
        'totalBytes': 100 * _gb,
        'freeBytes': 5 * _gb,
        'limitGb': 180,
        'limitBytes': 180 * _gb,
        'limitFreeBytes': 160 * _gb,
      }),
    );

    expect(find.textContaining('MENOS espacio libre que la cuota'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin datos del servidor lo dice en vez de inventar cifras',
      (tester) async {
    await _pump(tester, _FakeDrive(null));

    expect(find.text('Sin datos de espacio'), findsOneWidget);
    expect(find.textContaining('no reporta el espacio'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

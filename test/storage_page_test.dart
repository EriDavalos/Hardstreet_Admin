import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';

import 'package:hardstreet_admin/drive_api_service.dart'
    show DriveApiService, DriveMaintenance;
import 'package:hardstreet_admin/drive_base.dart';
import 'package:hardstreet_admin/drive_scope.dart';
import 'package:hardstreet_admin/pages/storage_page.dart';

/// Drive de prueba: devuelve lo que el servidor contestaría en /api/space.
class _FakeDrive extends DriveBase {
  _FakeDrive(this.info, {this.inMaintenance = false});

  final Map<String, dynamic>? info;

  /// El hub no da cifras: no queda ningún servidor en funcionamiento.
  final bool inMaintenance;

  @override
  Future<Map<String, dynamic>?> storageInfo() async {
    if (inMaintenance) {
      maintenance = const [driveMaintenanceNotice];
      throw const DriveMaintenance(driveMaintenanceNotice);
    }
    return info;
  }

  @override
  Future<void> refresh() async {}

  @override
  List<String> listFolders(List<String> rel) => const <String>[];

  @override
  String absolutePathOf(DriveItem item) => [...path, item.name].join('/');

  @override
  Future<int> uploadFromPaths(
    List<String> sources, {
    bool overwrite = false,
  }) async => 0;

  @override
  Future<void> createFolder(String name) async {}

  @override
  Future<void> rename(DriveItem item, String newName) async {}

  @override
  Future<void> delete(DriveItem item) async {}

  @override
  Future<({int moved, List<String> errors})> moveItems(
    List<String> names,
    List<String> targetPath,
  ) async => (moved: 0, errors: const <String>[]);

  @override
  Future<({int copied, List<String> errors})> copyItems(
    List<String> names,
    List<String> targetPath,
  ) async => (copied: 0, errors: const <String>[]);

  @override
  Future<({int deleted, List<String> errors})> deleteItems(
    List<String> names,
  ) async => (deleted: 0, errors: const <String>[]);

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
  /// Drive real contra un hub falso que contesta [status]/[body] en todo.
  DriveApiService apiFor(int status, Object body) {
    final previous = DriveApiService.client;
    addTearDown(() {
      DriveApiService.client = previous;
      HsSession.clear();
    });
    HsSession.token = 'tok-de-prueba';
    DriveApiService.client = MockClient(
      (_) async => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      ),
    );
    return DriveApiService(baseUrl: 'http://hub.test');
  }

  test(
    'un 503 de mantenimiento llega como mantenimiento, no como HTTP 503',
    () async {
      final drive = apiFor(503, {
        'ok': false,
        'error': 'El Drive está en mantenimiento',
        'message': 'El Drive está en mantenimiento',
        'details': 'Respaldo: Depende de Bodega, que no responde.',
      });

      await expectLater(drive.storageInfo(), throwsA(isA<DriveMaintenance>()));
      expect(drive.maintenance, isNotEmpty);
    },
  );

  test(
    'un 503 que NO es mantenimiento se lee con el motivo del servidor',
    () async {
      final drive = apiFor(503, {
        'ok': false,
        'error': 'Todos los servidores del Drive están apagados',
        'message': 'Todos los servidores del Drive están apagados',
      });

      Object? error;
      try {
        await drive.storageInfo();
      } catch (e) {
        error = e;
      }
      expect('$error', contains('HTTP 503'));
      expect('$error', contains('Todos los servidores'));
      expect(drive.maintenance, isEmpty);
    },
  );

  testWidgets('muestra lo usado, la cuota y lo libre del disco', (
    tester,
  ) async {
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
    // El % de la cuota se repite: número grande, barra partida y gráficas.
    expect(find.text('25 %'), findsWidgets);
    expect(find.text('18342'), findsOneWidget);
    expect(find.text('C:/HardStreetDrive'), findsOneWidget);
    expect(find.textContaining('DRIVE_LIMIT_GB'), findsOneWidget);
    // Las GRÁFICAS del espacio: barra partida y una barra por porcentaje.
    expect(find.text('Porcentajes del espacio'), findsOneWidget);
    expect(find.text('Cuota usada'), findsOneWidget);
    expect(find.text('Cuota libre'), findsOneWidget);
    expect(find.text('Disco usado'), findsOneWidget);
    expect(find.text('Disco libre'), findsOneWidget);
    // Sin botón de recargar (se pidió quitarlo de todos los módulos): el
    // espacio se pone al día deslizando hacia abajo, como en el resto.
    expect(find.byTooltip('Actualizar el espacio'), findsNothing);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    // Al 25 % no hay avisos.
    expect(find.textContaining('85 %'), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('avisa cuando la cuota se está llenando (85 % o más)', (
    tester,
  ) async {
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

    expect(find.text('89 %'), findsWidgets);
    expect(find.textContaining('85 % o más de su cuota'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('avisa cuando el DISCO tiene menos libre que la cuota', (
    tester,
  ) async {
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

    expect(
      find.textContaining('MENOS espacio libre que la cuota'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin datos del servidor lo dice en vez de inventar cifras', (
    tester,
  ) async {
    await _pump(tester, _FakeDrive(null));

    expect(find.text('Sin datos de espacio'), findsOneWidget);
    expect(find.textContaining('no reporta el espacio'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en mantenimiento lo explica en vez de decir «HTTP 503»', (
    tester,
  ) async {
    // El 503 del hub no es un fallo de red: no queda ningún servidor en
    // funcionamiento y no hay cifras que dar.
    await _pump(tester, _FakeDrive(null, inMaintenance: true));

    expect(find.text('Drive en mantenimiento'), findsOneWidget);
    expect(find.text(driveMaintenanceNotice), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.textContaining('HTTP 503'), findsNothing);
    expect(find.text('Sin datos de espacio'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_base.dart';
import 'package:hardstreet_admin/drive_host.dart';
import 'package:hardstreet_admin/widgets/drive_status_card.dart';

/// Drive mínimo para probar la card (no habla con ningún servidor).
class _FakeDrive extends DriveBase {
  _FakeDrive({this.remote = true});

  final bool remote;

  @override
  bool get isRemote => remote;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> createFolder(String name) async {}

  @override
  Future<void> rename(DriveItem item, String newName) async {}

  @override
  Future<void> delete(DriveItem item) async {}

  @override
  List<String> listFolders(List<String> rel) => const [];

  @override
  String absolutePathOf(DriveItem item) => item.name;

  @override
  Future<void> retryUpload(String jobId) async {}

  @override
  Future<int> uploadFromPaths(
    List<String> sources, {
    bool overwrite = false,
  }) async => 0;

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
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(520, 420),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(
        body: Center(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  tearDown(() => DriveHost.set(null));

  testWidgets(
    'conectado: la franja dice el estado, la dirección y la latencia',
    (tester) async {
      final drive = _FakeDrive()
        ..conn = DriveConn.online
        ..lastResponse = const Duration(milliseconds: 820);

      await _pump(tester, DriveStatusCard(drive: drive, compact: true));

      expect(find.textContaining('En línea'), findsOneWidget);
      expect(find.textContaining('oriongo.ddns.net'), findsOneWidget);
      expect(find.textContaining('820 ms'), findsOneWidget);
    },
  );

  testWidgets('sin comprobar: no se anuncia como conectado', (tester) async {
    final drive = _FakeDrive(); // conn = checking por defecto

    await _pump(tester, DriveStatusCard(drive: drive, compact: true));

    expect(find.textContaining('Sin comprobar'), findsOneWidget);
    expect(find.textContaining('En línea'), findsNothing);
  });

  testWidgets(
    'el fallo se cuenta en la card, no en un icono a página completa',
    (tester) async {
      var retries = 0;
      // Una dirección guardada que va por HTTPS contra un puerto que habla HTTP.
      DriveHost.set('https://drive.midominio.com:8443');
      final drive = _FakeDrive()
        ..conn = DriveConn.offline
        ..error =
            'No se pudo conectar con el servidor '
            '(https://drive.midominio.com:8443): HandshakeException: Handshake '
            'error in client (OS Error: WRONG_VERSION_NUMBER)';

      await _pump(
        tester,
        DriveStatusCard(drive: drive, onRetry: () => retries++),
        size: const Size(560, 620),
      );

      expect(find.text('Sin conexión con el Drive'), findsOneWidget);
      expect(find.text('Sin respuesta'), findsOneWidget);
      // La dirección y el protocolo se leen sin abrir nada más.
      expect(find.text('drive.midominio.com:8443'), findsOneWidget);
      expect(find.text('HTTPS'), findsOneWidget);
      // Error reconocible (TLS en un puerto HTTP): se dice qué probar.
      expect(
        find.textContaining('http://drive.midominio.com:8443'),
        findsOneWidget,
      );

      await tester.tap(find.text('Reintentar'));
      expect(retries, 1);
    },
  );

  testWidgets('en un móvil la card y la franja no se desbordan', (
    tester,
  ) async {
    final drive = _FakeDrive()
      ..conn = DriveConn.offline
      ..error =
          'No se pudo conectar con el servidor '
          '(http://192.168.1.72:4100): ClientException: Connection closed '
          'before full header was received';
    await _pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DriveStatusCard(drive: drive, onRetry: () {}),
          const SizedBox(height: 12),
          DriveStatusCard(drive: drive, compact: true, onRetry: () {}),
        ],
      ),
      size: const Size(340, 720),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Sin conexión con el Drive'), findsOneWidget);
  });

  testWidgets('un drive local no finge tener servidor', (tester) async {
    final drive = _FakeDrive(remote: false)
      ..conn = DriveConn.online
      ..error = 'No se pudo leer la carpeta';

    await _pump(
      tester,
      DriveStatusCard(drive: drive),
      size: const Size(560, 620),
    );

    expect(find.text('Carpeta de este equipo'), findsOneWidget);
    expect(find.text('HTTP'), findsNothing);
    expect(find.text('HTTPS'), findsNothing);
  });
}

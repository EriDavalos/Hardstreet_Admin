import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_api_service.dart';
import 'package:hardstreet_admin/drive_downloader.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';

/// PNG 1x1 válido (los bytes que NO deben perderse por el camino).
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/'
  'q842iQAAAABJRU5ErkJggg==',
);

/// ZIP con las entradas indicadas (tal como responde el backend).
List<int> _zipOf(Map<String, List<int>> entries) {
  final archive = Archive();
  entries.forEach((name, bytes) {
    archive.add(ArchiveFile.bytes(name, bytes));
  });
  return ZipEncoder().encode(archive);
}

/// Drive remoto FALSO: no toca la red, solo devuelve el ZIP del backend.
class _FakeApiDrive extends DriveApiService {
  _FakeApiDrive(this.zipBytes) : super(baseUrl: 'http://drive.local');

  final List<int> zipBytes;

  /// Última carpeta de la que se pidió el ZIP (null = la que el drive ve).
  List<String>? lastFrom;

  @override
  Future<void> refresh() async {}

  @override
  Future<List<int>> downloadZip(
    List<String> names, {
    void Function(int received, int total)? onProgress,
    List<String>? from,
  }) async {
    lastFrom = from;
    onProgress?.call(zipBytes.length, zipBytes.length);
    return zipBytes;
  }
}

void main() {
  group('descarga individual: el ZIP del backend no debe guardarse tal cual',
      () {
    test('extrae el archivo cuando el ZIP trae UNA sola entrada', () {
      final zip = _zipOf({'foto.png': _png});
      expect(extractSingleFile(zip, 'foto.png'), equals(_png));
    });

    test('no toca los bytes si NO es un ZIP (ya son la imagen)', () {
      expect(extractSingleFile(_png, 'foto.png'), isNull);
    });

    test('un ZIP con varias entradas (carpeta) se deja como ZIP', () {
      final zip = _zipOf({
        'uno.png': _png,
        'dos.png': _png,
      });
      expect(extractSingleFile(zip, 'carpeta'), isNull);
    });

    test('fetchDriveBytes devuelve la IMAGEN, no el ZIP, para 1 archivo',
        () async {
      final drive = _FakeApiDrive(_zipOf({'foto.png': _png}));
      final bytes = await fetchDriveBytes(
        drive,
        const [DriveItem(name: 'foto.png', isFolder: false)],
        onProgress: (_, _) {},
      );
      expect(bytes, equals(_png),
          reason: 'guardar el ZIP con extensión .png corrompía el archivo');
    });

    test('la descarga pide la carpeta DE LA QUE sale la foto', () async {
      // El selector de fotos navega por su cuenta: si la carpeta no viajara con
      // la descarga, bajaría el archivo homónimo de la carpeta que el módulo
      // Archivos tuviera abierta (o ninguno).
      final drive = _FakeApiDrive(_zipOf({'foto.png': _png}));
      await fetchDriveBytes(
        drive,
        const [DriveItem(name: 'foto.png', isFolder: false)],
        from: const ['XV', 'ReynaCoot'],
        onProgress: (_, _) {},
      );
      expect(drive.lastFrom, ['XV', 'ReynaCoot']);
    });
  });

  group('panel de descargas (segundo plano)', () {
    DriveDownloadJob job(String status, {int received = 0, int total = 0}) {
      final j = DriveDownloadJob(
        id: 'd1',
        name: 'boda.zip',
        items: const [DriveItem(name: 'boda', isFolder: true)],
        targetPath: 'C:/tmp/boda.zip',
      );
      j
        ..status = status
        ..received = received
        ..total = total;
      return j;
    }

    Future<void> pumpTile(
      WidgetTester tester,
      DriveDownloadJob j, {
      VoidCallback? onRetry,
      VoidCallback? onCancel,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DownloadJobTile(job: j, onRetry: onRetry, onCancel: onCancel),
          ),
        ),
      );
    }

    testWidgets('en curso: nombre, porcentaje y cancelar', (tester) async {
      var cancelled = false;
      final j = job('downloading', received: 512, total: 1024);
      await pumpTile(tester, j, onCancel: () => cancelled = true);

      expect(find.text('boda.zip'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);

      await tester.tap(find.byTooltip('Cancelar'));
      expect(cancelled, isTrue);
    });

    testWidgets('terminada: marca de listo con el tamaño', (tester) async {
      final j = job('done', received: 2048, total: 2048);
      await pumpTile(tester, j);

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('2 KB'), findsOneWidget);
    });

    testWidgets('con error: muestra el motivo y ofrece reintentar',
        (tester) async {
      var retried = false;
      final j = job('error')
        ..error = 'El archivo ya no existe';
      await pumpTile(tester, j, onRetry: () => retried = true);

      expect(find.textContaining('El archivo ya no existe'), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      expect(retried, isTrue);
    });

    testWidgets('el drive avisa del progreso y cierra el trabajo',
        (tester) async {
      final drive = _FakeApiDrive(_zipOf({'foto.png': _png}));
      var notifications = 0;
      drive.addListener(() => notifications++);

      final j = drive.startDownload('foto.png',
          items: const [DriveItem(name: 'foto.png', isFolder: false)]);
      expect(drive.downloadJobs, contains(j));
      expect(j.status, 'downloading');

      j.received = 10;
      j.total = 20;
      drive.notifyDownloadProgress();
      drive.finishDownloadJob(j);

      expect(j.status, 'done');
      expect(j.received, 20, reason: 'al terminar se completan los bytes');
      expect(notifications, greaterThanOrEqualTo(3));
      expect(drive.downloadJobs.length, 1);

      drive.clearFinishedDownloads();
      expect(drive.downloadJobs, isEmpty);
    });
  });

  group('descarga en Android (sin diálogo "Guardar como")', () {
    test('deja el archivo temporal con los bytes y pide guardarlo', () async {
      final dir = await Directory.systemTemp.createTemp('hs_downloads_test');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final calls = <MethodCall>[];
      const channel = MethodChannel('hardstreet/downloads');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        // El lado nativo COPIA ese archivo: aquí se comprueba que existe y que
        // lleva los bytes correctos (nada de pasar megabytes por el canal).
        final args = (call.arguments as Map).cast<String, dynamic>();
        final bytes = File(args['path'] as String).readAsBytesSync();
        expect(bytes, equals(_png));
        return 'Descargas/foto.png';
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance
          .defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      final where = await saveToAndroidDownloads(_png, 'foto.png',
          tempDir: dir.path);

      expect(calls.single.method, 'save');
      expect((calls.single.arguments as Map)['name'], 'foto.png');
      expect(where, 'Descargas/foto.png');
      // El temporal se borra SIEMPRE: no quedan copias por ahí.
      expect(File('${dir.path}/foto.png').existsSync(), isFalse);
    });
  });
}

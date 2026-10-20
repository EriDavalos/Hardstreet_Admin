import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_downloader.dart';
import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/local_share_service.dart';
import 'package:hardstreet_admin/share_permissions.dart';
import 'package:hardstreet_admin/shared_drive.dart';

// ==================================================================
// DESCARGAR (Y VER) ARCHIVOS DE UNA CARPETA COMPARTIDA
// ==================================================================
// Una carpeta compartida NO vive en este disco: la sirve el servidor del drive
// con /api/local/*. La descarga la trataba como un archivo local (`File(ruta)`)
// y fallaba SIEMPRE —"El archivo ya no existe"—, de modo que un vídeo (o una
// foto) de una carpeta compartida no se podía guardar.
//
// Aquí se levanta un servidor de verdad en loopback que responde como el del
// drive, y se comprueba que la descarga pide los bytes por HTTP, que el ZIP de
// una carpeta compartida incluye los vídeos y que las miniaturas se le piden
// al servidor también para los vídeos.
// ==================================================================

void main() {
  late HttpServer server;
  late String base;

  /// Bytes "de vídeo" (no importa el formato: lo que viaja son bytes).
  final video = List<int>.generate(5000, (i) => i % 251);

  const listing = {
    'folders': [
      {'name': 'clip.mp4', 'isFolder': false, 'size': 5000, 'kind': 'video'},
      {'name': 'notas.txt', 'isFolder': false, 'size': 9, 'kind': 'text'},
      {'name': 'fotos', 'isFolder': true, 'childCount': 1},
    ],
  };

  const subListing = {
    'folders': [
      {'name': 'otro.mp4', 'isFolder': false, 'size': 3, 'kind': 'video'},
    ],
  };

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final res = req.response;
      final q = req.uri.queryParameters;
      switch (req.uri.path) {
        case '/api/local/list':
          final body = (q['path'] ?? '').isEmpty
              ? listing
              : (q['path'] == 'fotos' ? subListing : const {'folders': []});
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode(body));
        case '/api/local/file':
          final path = q['path'] ?? '';
          final bytes = switch (path) {
            'clip.mp4' => video,
            'fotos/otro.mp4' => const [1, 2, 3],
            'notas.txt' => const [104, 111, 108, 97],
            _ => <int>[],
          };
          res.statusCode = bytes.isEmpty ? 404 : 200;
          res.headers.contentLength = bytes.length;
          res.add(bytes);
        default:
          res.statusCode = 404;
      }
      await res.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  SharedDrive driveAt(List<String> path) {
    final drive = SharedDrive(
      service: LocalShareService(baseUrl: base),
      shareId: 7,
      label: 'Bodas',
      rights: SharePermissions.readOnly,
    );
    drive.path = List<String>.of(path);
    return drive;
  }

  test(
    'un VÍDEO de una carpeta compartida se descarga (antes fallaba)',
    () async {
      final drive = driveAt(const []);
      final progress = <int>[];

      final bytes = await fetchDriveBytes(drive, const [
        DriveItem(name: 'clip.mp4', isFolder: false),
      ], onProgress: (received, _) => progress.add(received));

      expect(
        bytes,
        equals(video),
        reason: 'los bytes son los del archivo, no un "no existe"',
      );
      expect(progress, isNotEmpty);
      expect(progress.last, video.length);
    },
  );

  test('la descarga pide el archivo de la carpeta en la que está', () async {
    final drive = driveAt(const ['fotos']);
    final bytes = await fetchDriveBytes(drive, const [
      DriveItem(name: 'otro.mp4', isFolder: false),
    ], onProgress: (_, _) {});
    expect(bytes, const [1, 2, 3]);
  });

  test(
    'el ZIP de una carpeta compartida incluye vídeos y subcarpetas',
    () async {
      final drive = driveAt(const []);
      final bytes = await remoteZipBytes(
        drive,
        const [
          DriveItem(name: 'clip.mp4', isFolder: false),
          DriveItem(name: 'fotos', isFolder: true),
        ],
        const [],
        onProgress: (_, _) {},
      );

      final archive = ZipDecoder().decodeBytes(bytes);
      final names = archive.files.map((f) => f.name).toSet();
      expect(names, containsAll(['clip.mp4', 'fotos/', 'fotos/otro.mp4']));
      final clip = archive.files.firstWhere((f) => f.name == 'clip.mp4');
      expect(clip.content, equals(video));
    },
  );

  test(
    'la descarga grande se escribe por TROZOS, sin pasar por memoria',
    () async {
      final dir = await Directory.systemTemp.createTemp('hs_share_dl');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final target = '${dir.path}${Platform.pathSeparator}clip.mp4';

      var last = 0;
      await downloadRemoteToFile(
        Uri.parse('$base/api/local/file?share=7&path=clip.mp4'),
        target,
        onProgress: (received, _) => last = received,
      );

      expect(File(target).readAsBytesSync(), equals(video));
      expect(last, video.length);
    },
  );

  test(
    'los VÍDEOS tienen miniatura (el servidor la genera), las fotos también',
    () async {
      final drive = driveAt(const []);
      const clip = DriveItem(name: 'clip.mp4', isFolder: false);
      const foto = DriveItem(name: 'foto.jpg', isFolder: false);

      expect(
        drive.canThumb(clip),
        isTrue,
        reason: 'el servidor saca el primer fotograma del vídeo',
      );
      expect(drive.canThumb(foto), isTrue);
      expect(drive.thumbSource(clip, width: 480), contains('/api/local/thumb'));
    },
  );

  test(
    'en un drive de DISCO el vídeo no pide miniatura (se ve su icono)',
    () async {
      final dir = await Directory.systemTemp.createTemp('hs_drive_local');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      File('${dir.path}${Platform.pathSeparator}clip.mp4')
          .writeAsBytesSync(const [1, 2, 3]);
      final drive = DriveService.testRoot(dir);

      expect(
        drive.canThumb(const DriveItem(name: 'clip.mp4', isFolder: false)),
        isFalse,
        reason: 'en el disco no hay quién saque el fotograma',
      );
    },
  );
}

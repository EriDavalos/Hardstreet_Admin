import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_downloader.dart';
import 'package:hardstreet_admin/drive_service.dart';

/// PNG 1x1 válido.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/'
  'q842iQAAAABJRU5ErkJggg==',
);

void main() {
  test('la selección de varias fotos se empaqueta en un ZIP', () async {
    final tmp = await Directory.systemTemp.createTemp('hardstreet_zip_test');
    addTearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {/* el temporal es prescindible */}
    });

    final drive = DriveService.testRoot(tmp);
    for (final n in ['uno.png', 'dos.png']) {
      File([tmp.path, n].join('/')).writeAsBytesSync(_png);
    }
    await drive.createFolder('Sub');
    File([tmp.path, 'Sub', 'dentro.png'].join('/')).writeAsBytesSync(_png);
    await drive.refresh();

    expect(drive.items.length, 3, reason: 'carpeta + 2 imágenes');

    final bytes = await buildLocalZipBytes(drive, drive.items);
    expect(bytes, isNotEmpty);

    final zip = ZipDecoder().decodeBytes(bytes);
    final names = zip.files.map((f) => f.name).toSet();

    // Las dos fotos sueltas y la carpeta completa (recursiva).
    expect(names, containsAll(['uno.png', 'dos.png', 'Sub/dentro.png']));

    final uno = zip.files.firstWhere((f) => f.name == 'uno.png');
    expect(uno.size, _png.length, reason: 'el contenido viaja íntegro');
  });
}

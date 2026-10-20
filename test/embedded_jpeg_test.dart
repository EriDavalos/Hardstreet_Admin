import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_base.dart';
import 'package:hardstreet_admin/embedded_jpeg.dart';

/// Arma un JPEG "de mentira" con la MISMA estructura de segmentos que uno
/// real (SOI, comentario, SOS con datos comprimidos y EOI). No hace falta que
/// los píxeles decodifiquen: aquí se prueba el recorrido de marcadores.
Uint8List fakeJpeg(int payloadBytes, {int fill = 0x11}) {
  final data = <int>[
    0xFF, 0xD8, // SOI
    0xFF, 0xFE, 0x00, 0x06, 0x41, 0x41, 0x41, 0x41, // comentario
    0xFF, 0xDA, 0x00, 0x02, // inicio del scan
    for (var i = 0; i < payloadBytes; i++) fill,
    0xFF, 0xD9, // EOI
  ];
  return Uint8List.fromList(data);
}

void main() {
  test('reconoce las extensiones RAW', () {
    expect(isRawFileName('boda.CR3'), isTrue);
    expect(isRawFileName('foto.cr2'), isTrue);
    expect(isRawFileName('cielo.dng'), isTrue);
    expect(isRawFileName('foto.jpg'), isFalse);
    expect(isRawFileName('sin-extension'), isFalse);
    expect(driveItemKindOf('boda.CR3'), DriveItemKind.raw);
    expect(driveItemKindOf('foto.jpg'), DriveItemKind.image);
  });

  test('elige el JPEG de vista previa más grande', () {
    final small = fakeJpeg(1200, fill: 0x22);
    final big = fakeJpeg(5000, fill: 0x33);
    final raw = Uint8List.fromList([
      ...List<int>.filled(3000, 0x77),
      ...small,
      ...List<int>.filled(2000, 0x55),
      ...big,
      ...List<int>.filled(1000, 0x44),
    ]);

    final preview = embeddedJpeg(raw);
    expect(preview, isNotNull);
    expect(preview!.length, big.length);
    expect(preview.sublist(0, 3), [0xFF, 0xD8, 0xFF]);
    expect(preview.sublist(preview.length - 2), [0xFF, 0xD9]);
    expect(preview[preview.length - 3], 0x33);
  });

  test('ignora los JPEG diminutos y los archivos sin vista previa', () {
    final tiny = fakeJpeg(20);
    final raw = Uint8List.fromList([
      ...List<int>.filled(100, 1),
      ...tiny,
      ...List<int>.filled(100, 2),
    ]);
    expect(embeddedJpeg(raw), isNull);
    expect(embeddedJpeg(Uint8List.fromList(List<int>.filled(4000, 9))), isNull);
    expect(embeddedJpeg(Uint8List(0)), isNull);
  });
}

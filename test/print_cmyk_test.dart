import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart' show ZLibDecoder;
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/modules/print/services/print_export.dart';
import 'package:hardstreet_admin/modules/print/models/print_models.dart';

const _square = PrintFormat(id: 1, name: '1x1', width: 1, height: 1);
const _photo = PrintFormat(id: 2, name: '5x7', width: 5, height: 7);

class _TiffTag {
  const _TiffTag(this.type, this.count, this.value);

  final int type;
  final int count;
  final int value;
}

Map<int, _TiffTag> _readTags(Uint8List tiff) {
  final data = ByteData.sublistView(tiff);
  expect(data.getUint16(0, Endian.little), 0x4949);
  expect(data.getUint16(2, Endian.little), 42);
  final ifd = data.getUint32(4, Endian.little);
  final count = data.getUint16(ifd, Endian.little);
  final tags = <int, _TiffTag>{};
  for (var i = 0; i < count; i++) {
    final at = ifd + 2 + i * 12;
    tags[data.getUint16(at, Endian.little)] = _TiffTag(
      data.getUint16(at + 2, Endian.little),
      data.getUint32(at + 4, Endian.little),
      data.getUint32(at + 8, Endian.little),
    );
  }
  return tags;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('RGBA a CMYK: blanco, negro y rojo', () {
    final cmyk = rgbaToCmyk(
      Uint8List.fromList([
        255, 255, 255, 255, //
        0, 0, 0, 255, //
        255, 0, 0, 255, //
      ]),
    );
    expect(cmyk.sublist(0, 4), [0, 0, 0, 0]);
    expect(cmyk.sublist(4, 8), [0, 0, 0, 255]);
    expect(cmyk.sublist(8, 12), [0, 255, 255, 0]);
  });

  test('limita la tinta total (TAC)', () {
    final cmyk = rgbaToCmyk(Uint8List.fromList([0, 0, 255, 255]), maxInk: 1.5);
    final total = cmyk[0] + cmyk[1] + cmyk[2] + cmyk[3];
    expect(total, lessThanOrEqualTo(383));
  });

  test('el TIFF es CMYK, de una tira y lleva el perfil ICC', () {
    final cmyk = Uint8List(2 * 2 * 4);
    final icc = Uint8List.fromList(List.generate(64, (i) => i));
    final tiff = buildCmykTiff(
      pixelWidth: 2,
      pixelHeight: 2,
      cmyk: cmyk,
      iccProfile: icc,
      xDpi: 300,
      yDpi: 300,
    );
    final tags = _readTags(tiff);
    final data = ByteData.sublistView(tiff);

    expect(tags[256]!.value, 2); // ancho
    expect(tags[257]!.value, 2); // alto
    expect(tags[258]!.type, 3); // SHORT
    expect(tags[258]!.count, 4);
    expect(tags[262]!.value, 5); // Separated / CMYK
    expect(tags[277]!.value, 4); // cuatro canales
    expect(tags[278]!.value, 2); // una sola tira
    expect(tags[332]!.value, 1); // InkSet = CMYK
    expect(tags[334]!.value, 4); // NumberOfInks

    final bits = tags[258]!.value;
    expect(
      [for (var i = 0; i < 4; i++) data.getUint16(bits + i * 2, Endian.little)],
      [8, 8, 8, 8],
    );

    final iccTag = tags[34675]!;
    expect(iccTag.type, 7); // UNDEFINED
    expect(iccTag.count, icc.length);
    expect(tiff.sublist(iccTag.value, iccTag.value + icc.length), icc);

    final compression = tags[259]!.value;
    final strip = tags[273]!.value;
    final stripLength = tags[279]!.value;
    final raw = compression == 8
        ? Uint8List.fromList(
            ZLibDecoder().decodeBytes(tiff.sublist(strip, strip + stripLength)),
          )
        : tiff.sublist(strip, strip + stripLength);
    expect(raw, cmyk);

    expect(tags[282]!.type, 5); // RATIONAL
    expect(data.getUint32(tags[282]!.value, Endian.little), 300);
  });

  test('el TIFF conserva el tamaño físico del formato', () {
    final setup = printCmykImageSetup(_photo, 7 / 5);
    expect(setup.pixelsWide, greaterThan(setup.pixelsHigh));
    expect(setup.xDpi, closeTo(300, .1));
    expect(setup.yDpi, closeTo(300, .1));

    final large = printCmykImageSetup(
      const PrintFormat(id: 3, name: '12x18', width: 12, height: 18),
      18 / 12,
    );
    expect(large.pixelsWide * large.pixelsHigh, lessThanOrEqualTo(18000000));
    expect(large.xDpi, lessThanOrEqualTo(300));

    expect(printCmykFileName('XV/Reyna/foto.jpg', _photo), 'foto_5x7.tif');
  });

  test('el perfil ICC de imprenta está disponible y es CMYK', () async {
    final profile = await loadPrintCmykProfile();
    expect(profile.length, greaterThan(1000));
    expect(String.fromCharCodes(profile.sublist(36, 40)), 'acsp');
    expect(String.fromCharCodes(profile.sublist(16, 20)), 'CMYK');
    final data = ByteData.sublistView(profile);
    expect(data.getUint32(0, Endian.big), profile.length);
  });

  test('genera un TIFF CMYK desde una imagen recortada', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 100, 100),
      ui.Paint()..color = const ui.Color(0xFFFF0000),
    );
    final image = await recorder.endRecording().toImage(100, 100);
    final icc = Uint8List.fromList(List.generate(64, (i) => i));
    final tiff = await renderPrintCmykImage(
      image: image,
      format: _square,
      crop: const PrintCrop(),
      iccProfile: icc,
    );
    final tags = _readTags(tiff);
    expect(tags[256]!.value, 300);
    expect(tags[257]!.value, 300);
    expect(tags[262]!.value, 5);
    expect(tags[34675]!.count, icc.length);
    image.dispose();
  });
}

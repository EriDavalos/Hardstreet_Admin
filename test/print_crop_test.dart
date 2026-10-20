import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' show Rect, Size;
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/print_export.dart';
import 'package:hardstreet_admin/print_models.dart';

const _landscape = PrintFormat(id: 1, name: '4x6', width: 4, height: 6);
const _square = PrintFormat(id: 2, name: '1x1', width: 1, height: 1);

void main() {
  group('PrintCrop · recorte al formato (como Lightroom)', () {
    test('una foto horizontal a 1x1 recorta el centro (no deforma)', () {
      const crop = PrintCrop();
      final r = crop.sourceRect(const Size(300, 200), _square.ratio);
      expect(r.width, 200);
      expect(r.height, 200);
      expect(r.left, 50);
      expect(r.top, 0);
    });

    test('una foto vertical a 4x6 usa todo el alto disponible', () {
      final r = const PrintCrop().sourceRect(
        const Size(300, 600),
        _landscape.ratio,
      );
      // ratio = 4/6 = .6667 -> ancho = 600 * .6667 = 400 > 300: se limita.
      expect(r.width, 300);
      expect(r.height, 450);
      expect(r.top, 75);
    });

    test('el zoom encoge el recorte y lo mantiene dentro de la foto', () {
      const crop = PrintCrop(focusX: 1, focusY: 0, zoom: 2);
      final r = crop.sourceRect(const Size(400, 400), 1);
      expect(r.width, 200);
      expect(r.height, 200);
      // Con el foco en la esquina, el recorte se pega a esa esquina.
      expect(r.right, 400);
      expect(r.top, 0);
    });

    test('el foco fuera de rango no saca el recorte de la imagen', () {
      final r = const PrintCrop(
        focusX: -2,
        focusY: 5,
      ).sourceRect(const Size(100, 100), 1);
      expect(r.left, 0);
      expect(r.top, 0);
      expect(r.right, lessThanOrEqualTo(100));
      expect(r.bottom, lessThanOrEqualTo(100));
    });
  });

  group('Orientación del recorte', () {
    test('una foto horizontal se recorta en horizontal por defecto', () {
      const crop = PrintCrop();
      // 4x6 es vertical (ratio 4/6); la foto apaisada manda: 6/4.
      expect(crop.ratioFor(_landscape, const Size(300, 200)), closeTo(1.5, .001));
      final r = crop.sourceRect(const Size(300, 200), crop.ratioFor(_landscape, const Size(300, 200)));
      expect(r.width, 300);
      expect(r.height, 200);
    });

    test('una foto vertical usa el formato tal cual', () {
      const crop = PrintCrop();
      expect(
        crop.ratioFor(_landscape, const Size(200, 300)),
        closeTo(4 / 6, .001),
      );
    });

    test('se puede pedir el recorte vertical aunque la foto sea apaisada', () {
      const crop = PrintCrop(landscape: false);
      expect(
        crop.ratioFor(_landscape, const Size(300, 200)),
        closeTo(4 / 6, .001),
      );
    });

    test('el giro explícito sobrevive al mover el encuadre', () {
      const crop = PrintCrop(landscape: false, focusX: .4, focusY: .6);
      final moved = crop.copyWith(focusX: .7, zoom: 2);
      expect(moved.landscape, isFalse);
      expect(moved.focusX, .7);
      expect(moved.zoom, 2);
    });
  });

  group('Posiciones guardadas (JSON)', () {
    test('el encuadre de cada foto vuelve tal cual del servidor', () {
      const crop = PrintCrop(
        focusX: .2,
        focusY: .3,
        zoom: 2.5,
        landscape: false,
      );
      final json = crop.toJson();
      expect(json['x'], .2);
      expect(json['y'], .3);
      expect(json['zoom'], 2.5);
      expect(json['landscape'], isFalse);

      final back = PrintCrop.fromJson(json)!;
      expect(back.focusX, .2);
      expect(back.focusY, .3);
      expect(back.zoom, 2.5);
      expect(back.landscape, isFalse);
    });

    test('sin orientación elegida el JSON no la fuerza', () {
      final json = const PrintCrop().toJson();
      expect(json.containsKey('landscape'), isFalse);
      expect(PrintCrop.fromJson(json)!.landscape, isNull);
    });

    test('un valor inválido o fuera de rango no rompe el editor', () {
      expect(PrintCrop.fromJson(null), isNull);
      expect(PrintCrop.fromJson('no es un mapa'), isNull);
      expect(PrintCrop.fromJson({'x': .5}), isNull);

      final clamped = PrintCrop.fromJson({
        'x': 4,
        'y': -1,
        'zoom': 99,
      })!;
      expect(clamped.focusX, 1);
      expect(clamped.focusY, 0);
      expect(clamped.zoom, 8);
    });
  });

  group('Borde blanco', () {
    test('0 % no deja borde y 10 % encoge la foto en el marco', () {
      const frame = Rect.fromLTWH(0, 0, 100, 100);
      final none = borderGeometry(frame, 0);
      expect(none.pixels, 0);
      expect(none.inner, frame);

      final ten = borderGeometry(frame, 10);
      expect(ten.pixels, 10);
      expect(ten.inner.width, 80);
      expect(ten.inner.height, 80);
      expect(
        ten.inner.width,
        lessThan(frame.width),
        reason: 'más borde = foto más pequeña',
      );
    });

    test('se mide sobre el lado corto (5x7 y 1x1 se ven igual)', () {
      final a = borderGeometry(const Rect.fromLTWH(0, 0, 100, 150), 10);
      final b = borderGeometry(const Rect.fromLTWH(0, 0, 100, 100), 10);
      expect(a.pixels, 10);
      expect(b.pixels, 10);
    });

    test('el borde no se sale del marco (máximo 30 %)', () {
      final g = borderGeometry(const Rect.fromLTWH(0, 0, 100, 100), 90);
      expect(g.pixels, 30);
      expect(g.inner.width, greaterThan(0));
      expect(g.inner.height, greaterThan(0));
    });
  });

  group('Nombres y ZIP', () {
    test('la foto final lleva el formato y la extensión PNG', () {
      expect(printFileName('XV/Reyna/foto.jpg', _landscape), 'foto_4x6.png');
      expect(printFileName('sin-extension', _square), 'sin-extension_1x1.png');
    });

    test('dos fotos con el mismo nombre no se pisan en el ZIP', () {
      final names = uniquePrintNames(['foto_5x7.png', 'foto_5x7.png']);
      expect(names, ['foto_5x7.png', 'foto_5x7_1.png']);
    });

    test('el ZIP contiene los archivos', () {
      final zip = zipPrintPhotos([
        (name: 'a.png', bytes: Uint8List.fromList([1, 2, 3])),
        (name: 'b.png', bytes: Uint8List.fromList([4, 5])),
      ]);
      // Firma de un ZIP (PK\x03\x04).
      expect(zip.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);
      expect(zip.length, greaterThan(20));
    });
  });

  test(
    'el PNG final conserva la resolución del recorte y pinta el borde',
    () async {
      // Foto de prueba 100x100 con un cuadrado rojo en el centro.
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, 100, 100),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
      canvas.drawRect(
        const ui.Rect.fromLTWH(25, 25, 50, 50),
        ui.Paint()..color = const ui.Color(0xFFFF0000),
      );
      final image = await recorder.endRecording().toImage(100, 100);

      final bytes = await renderPrintPhoto(
        image: image,
        format: _square,
        crop: const PrintCrop(),
        borderPercent: 10,
      );
      final decoded = await decodePrintImage(bytes);
      expect(decoded.width, 100, reason: 'misma resolución que el recorte');
      expect(decoded.height, 100);

      final data = await decoded.toByteData(format: ui.ImageByteFormat.rawRgba);
      final rgba = data!.buffer.asUint8List();
      // La esquina es blanca por el borde; el centro conserva el rojo.
      int pixel(int x, int y) => (y * decoded.width + x) * 4;
      expect(rgba[pixel(0, 0)], 255);
      expect(rgba[pixel(0, 0) + 1], 255);
      expect(rgba[pixel(0, 0) + 2], 255);
      expect(rgba[pixel(50, 50)], greaterThan(200));
      expect(rgba[pixel(50, 50) + 1], lessThan(60));
      image.dispose();
      decoded.dispose();
    },
  );
}

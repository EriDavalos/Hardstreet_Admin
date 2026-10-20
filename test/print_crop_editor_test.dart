import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/print_models.dart';
import 'package:hardstreet_admin/widgets/print_preview.dart';

// ==================================================================
// EL DIÁLOGO DE RECORTE, TAL COMO LO USA EL USUARIO
// ==================================================================
// Se comprueba lo que reportó el cliente:
//   * arrastrar mueve el encuadre,
//   * estirar desde el borde/costado encoge o agranda el recorte,
//   * el botón DERECHO del mouse también arrastra,
//   * la orientación se puede cambiar a vertical.
// El diálogo devuelve el [PrintCrop] al pulsar "Listo", así que se verifica
// el resultado real del ajuste.
// ==================================================================

const _format = PrintFormat(id: 1, name: '4x6', width: 4, height: 6);

/// Resultado que devolvió el último diálogo cerrado.
PrintCrop? _result;

Future<ui.Image> _image(WidgetTester tester) async {
  final image = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 400, 300),
      Paint()..color = const Color(0xFF3366FF),
    );
    return recorder.endRecording().toImage(400, 300);
  });
  return image!;
}

/// Monta una pantalla con un botón y abre el diálogo de recorte.
Future<void> _open(WidgetTester tester, ui.Image image) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              _result = await showPrintCropDialog(
                ctx,
                image: image,
                format: _format,
                initial: const PrintCrop(),
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

/// Pulsa "Listo" y devuelve el ajuste que entregó el diálogo.
Future<PrintCrop> _done(WidgetTester tester) async {
  _result = null;
  await tester.tap(find.text('Listo'));
  await tester.pumpAndSettle();
  return _result!;
}

/// Geometría del lienzo: la foto 400x300 se ajusta dentro (contain), así que
/// el centro del canvas es el centro de la foto.
Rect _imageRect(WidgetTester tester) {
  final canvas = tester.getRect(
    find.byKey(const ValueKey('print-crop-canvas')),
  );
  final ratio = 400 / 300;
  var w = canvas.width;
  var h = w / ratio;
  if (h > canvas.height) {
    h = canvas.height;
    w = h * ratio;
  }
  return Rect.fromCenter(center: canvas.center, width: w, height: h);
}

void main() {
  testWidgets('arrastrar con el botón izquierdo mueve el encuadre', (
    tester,
  ) async {
    final image = await _image(tester);
    await _open(tester, image);

    final img = _imageRect(tester);
    final gesture = await tester.startGesture(img.center);
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    final crop = await _done(tester);
    expect(crop.focusX, greaterThan(.5));
  });

  testWidgets('estirar desde el borde derecho encoge el recorte (zoom)', (
    tester,
  ) async {
    final image = await _image(tester);
    await _open(tester, image);

    final img = _imageRect(tester);
    // El recorte inicial (4x6 en foto apaisada = 3:2) toca el borde derecho.
    final gesture = await tester.startGesture(
      Offset(img.right - 3, img.center.dy),
    );
    await gesture.moveBy(const Offset(-80, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    final crop = await _done(tester);
    expect(crop.zoom, greaterThan(1));
    expect(crop.landscape, isTrue);
  });

  testWidgets('el botón DERECHO del mouse también arrastra', (tester) async {
    final image = await _image(tester);
    await _open(tester, image);

    final img = _imageRect(tester);
    final gesture = await tester.startGesture(
      img.center,
      buttons: kSecondaryMouseButton,
    );
    await gesture.moveBy(const Offset(-50, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    final crop = await _done(tester);
    expect(crop.focusX, lessThan(.5));
  });

  testWidgets('el botón de orientación cambia el recorte a vertical', (
    tester,
  ) async {
    final image = await _image(tester);
    await _open(tester, image);

    // La foto es apaisada: empieza en horizontal.
    expect(find.text('Horizontal'), findsOneWidget);
    await tester.tap(find.text('Horizontal'));
    await tester.pumpAndSettle();
    expect(find.text('Vertical'), findsOneWidget);

    final crop = await _done(tester);
    expect(crop.landscape, isFalse);
  });

  testWidgets('se puede volver a ajustar sin quedarse atorado', (tester) async {
    final image = await _image(tester);
    await _open(tester, image);

    // Abrir, mover, listo… y otra vez: el diálogo nuevo debe responder igual.
    for (var i = 0; i < 3; i++) {
      final img = _imageRect(tester);
      final gesture = await tester.startGesture(img.center);
      await gesture.moveBy(const Offset(20, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      final crop = await _done(tester);
      expect(crop.focusX, greaterThan(.5), reason: 'intento $i');

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}

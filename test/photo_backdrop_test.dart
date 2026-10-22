import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/widgets/photo_backdrop.dart';

/// Proveedor de una imagen ya hecha: nada de red.
class _SolidImage extends ImageProvider<_SolidImage> {
  _SolidImage(this.image);

  final ui.Image image;

  @override
  Future<_SolidImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_SolidImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _SolidImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    SynchronousFuture<ImageInfo>(ImageInfo(image: image)),
  );
}

Future<ui.Image> _solid(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
      .drawRect(const Rect.fromLTWH(0, 0, 64, 64), Paint()..color = color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(64, 64);
  picture.dispose();
  return image;
}

Future<void> _pump(
  WidgetTester tester,
  ImageProvider? image, {
  Duration fade = const Duration(milliseconds: 100),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [PhotoBackdrop(image: image, fade: fade)],
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Las capas de foto que hay AHORA mismo dentro del fondo.
Finder _layers() => find.descendant(
  of: find.byType(PhotoBackdrop),
  matching: find.byType(ImageFiltered),
);

void main() {
  testWidgets('con foto pinta la foto DESENFOCADA y su velo', (tester) async {
    final image = await _solid(const Color(0xFF3F7F2A));
    await _pump(tester, _SolidImage(image));

    expect(_layers(), findsOneWidget);
    final filtered = tester.widget<ImageFiltered>(_layers());
    expect(
      filtered.imageFilter,
      ui.ImageFilter.blur(sigmaX: 38, sigmaY: 38, tileMode: TileMode.decal),
    );
    // La foto llena el fondo (no deja huecos a los lados).
    expect(
      tester.getSize(
        find.descendant(of: _layers(), matching: find.byType(Image)),
      ),
      tester.getSize(find.byType(PhotoBackdrop)),
    );
    // El velo del panel va por encima para que el contenido se lea.
    expect(
      find.descendant(
        of: find.byType(PhotoBackdrop),
        matching: find.byType(ColoredBox),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sin foto el fondo no pinta NADA (ni velo)', (tester) async {
    await _pump(tester, null);
    expect(_layers(), findsNothing);
    expect(
      find.descendant(
        of: find.byType(PhotoBackdrop),
        matching: find.byType(ColoredBox),
      ),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('al cambiar de foto se funde encima y luego queda una', (
    tester,
  ) async {
    final a = _SolidImage(await _solid(const Color(0xFF2050C0)));
    final b = _SolidImage(await _solid(const Color(0xFFC03030)));
    await _pump(tester, a);
    expect(_layers(), findsOneWidget);

    await _pump(tester, b, fade: const Duration(milliseconds: 300));
    // A media transición están las DOS: la que se va no deja un hueco.
    await tester.pump(const Duration(milliseconds: 100));
    expect(_layers(), findsNWidgets(2));

    // Termina el fundido: se queda solo la nueva.
    await tester.pump(const Duration(milliseconds: 400));
    expect(_layers(), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el fondo no se come los toques de la vista', (tester) async {
    var taps = 0;
    final image = await _solid(const Color(0xFFB03030));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              PhotoBackdrop(image: _SolidImage(image)),
              Center(
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('Botón'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Botón'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    await tester.pumpWidget(const SizedBox());
  });
}

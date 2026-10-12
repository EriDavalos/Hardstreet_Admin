import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/widgets/drive_thumb.dart';

/// PNG 1x1 válido (transparente): sirve para probar la decodificación real.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/'
  'q842iQAAAABJRU5ErkJggg==',
);

Widget _wrap(Widget child) => MaterialApp(
      home: Material(
        child: Center(child: SizedBox(width: 220, height: 220, child: child)),
      ),
    );

/// Espera lo suficiente para agotar los reintentos automáticos (0.6 + 1.5 + 3 s).
Future<void> _exhaustRetries(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
  }
}

void main() {
  group('DriveThumb', () {
    late Directory tmp;
    late File local;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('hardstreet_thumb_test');
      local = File([tmp.path, 'foto.jpg'].join('/'))
        ..writeAsBytesSync(_png);
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    testWidgets('mientras la imagen no llega muestra marcador, nunca un hueco',
        (tester) async {
      await tester.pumpWidget(_wrap(const DriveThumb(
        source: 'https://example.invalid/foto.jpg',
        isRemote: true,
        big: true,
      )));
      await tester.pump();
      // El marcador es un spinner: la celda no se ve vacía.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('muestra la copia LOCAL al instante aunque el servidor falle',
        (tester) async {
      await tester.pumpWidget(_wrap(DriveThumb(
        source: 'https://example.invalid/foto.jpg',
        isRemote: true,
        localPreview: local.path,
        big: true,
      )));
      // Sin esperar a nada: el archivo recién subido ya está en pantalla.
      await tester.pump();
      final fileImage = find.byWidgetPredicate((w) =>
          w is Image &&
          w.image is FileImage &&
          (w.image as FileImage).file.path == local.path);
      expect(fileImage, findsOneWidget);
    });

    testWidgets('tras agotar reintentos ofrece reintentar a mano',
        (tester) async {
      await tester.pumpWidget(_wrap(const DriveThumb(
        source: 'https://example.invalid/otra.jpg',
        isRemote: true,
        big: true,
      )));
      await tester.pump();
      await _exhaustRetries(tester);
      expect(
        find.byTooltip('No se pudo cargar. Toca para reintentar'),
        findsOneWidget,
      );

      // El toque vuelve a intentar: reaparece el marcador de carga.
      await tester.tap(find.byTooltip('No se pudo cargar. Toca para reintentar'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Deja el widget sin temporizadores pendientes al cerrar.
      await _exhaustRetries(tester);
    });
  });
}

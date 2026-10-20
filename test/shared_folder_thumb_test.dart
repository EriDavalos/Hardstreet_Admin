import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/local_share_service.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';
import 'package:hardstreet_admin/share_permissions.dart';
import 'package:hardstreet_admin/shared_drive.dart';
import 'package:hardstreet_admin/widgets/drive_thumb.dart';

// ==================================================================
// LA TARJETA DE UN VÍDEO EN UNA CARPETA COMPARTIDA
// ==================================================================
// En una carpeta compartida el vídeo se veía solo como un icono: ahora su
// tarjeta pide la miniatura al servidor (que saca el primer fotograma) y, si no
// llega, cae al icono de su tipo en vez de dejar un recuadro roto.
// ==================================================================

void main() {
  testWidgets('la tarjeta de un VÍDEO pide su miniatura al servidor', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final client = MockClient((request) async {
      if (request.url.path == '/api/local/list') {
        return http.Response(
          jsonEncode({
            'folders': [
              {'name': 'clip.mp4', 'isFolder': false, 'size': 5000},
              {'name': 'notas.txt', 'isFolder': false, 'size': 4},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      // La miniatura no llega (como cuando el servidor no tiene ffmpeg).
      return http.Response('', 404);
    });

    final drive = SharedDrive(
      service: LocalShareService(baseUrl: 'http://drive.test', client: client),
      shareId: 3,
      label: 'Bodas',
      rights: SharePermissions.readOnly,
    );
    await drive.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DrivePage(drive: drive)),
      ),
    );
    await tester.pump();

    // El VÍDEO usa la miniatura (DriveThumb), no el icono de tipo: es el
    // servidor quien saca el primer fotograma.
    final videoCard = find.ancestor(
      of: find.text('clip.mp4'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: videoCard, matching: find.byType(DriveThumb)),
      findsOneWidget,
    );

    // El texto no pide miniatura: sigue con su icono.
    final textCard = find.ancestor(
      of: find.text('notas.txt'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: textCard, matching: find.byType(DriveThumb)),
      findsNothing,
    );

    // Y no hay excepciones de pintado mientras la miniatura falla.
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/local_share_service.dart';
import 'package:hardstreet_admin/widgets/local_share_browser.dart';

/// Servidor del drive falso: responde SOLO a /api/local/list, con un árbol
/// fijo, y lleva la cuenta de las rutas pedidas.
class _DriveMock {
  final called = <String>[];

  LocalShareService service() => LocalShareService(
        baseUrl: 'http://drive.test',
        client: MockClient((request) async {
          called.add(request.url.path);
          final path = request.url.queryParameters['path'] ?? '';
          Map<String, dynamic> body;
          switch (path) {
            case '':
              body = {
                'local': true,
                'path': '',
                'folders': [
                  {'name': 'Bodas', 'isFolder': true},
                  {'name': 'foto.jpg', 'isFolder': false, 'size': 1024},
                ],
              };
              break;
            case 'Bodas':
              body = {
                'local': true,
                'path': 'Bodas',
                'folders': [
                  {'name': 'Ana', 'isFolder': true},
                ],
              };
              break;
            default:
              body = {'local': true, 'path': path, 'folders': const []};
          }
          return http.Response(jsonEncode(body), 200,
              headers: {'content-type': 'application/json'});
        }),
      );
}

Future<void> _open(WidgetTester tester, LocalShareService service) async {
  await tester.binding.setSurfaceSize(const Size(900, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showLocalShareBrowser(
                context,
                shareId: 7,
                title: r'D:\Eventos\2026',
                ownerName: 'Yusef Ali',
                service: service,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  tearDown(() => HsSession.token = null);

  testWidgets('lista la carpeta local y se puede NAVEGAR sin editar nada',
      (tester) async {
    final mock = _DriveMock();
    await _open(tester, mock.service());

    // Cabecera: el nombre y de quién es (solo lectura).
    expect(find.text(r'D:\Eventos\2026'), findsOneWidget);
    expect(find.text('Compartida por Yusef Ali · solo lectura'), findsOneWidget);
    // Contenido: una carpeta y una imagen.
    expect(find.text('Bodas'), findsOneWidget);
    expect(find.text('foto.jpg'), findsOneWidget);
    // SOLO LECTURA: ni subir, ni crear carpeta, ni renombrar, ni borrar.
    expect(find.byTooltip('Subir archivos'), findsNothing);
    expect(find.byTooltip('Nueva carpeta'), findsNothing);
    expect(find.byTooltip('Renombrar'), findsNothing);
    expect(find.byTooltip('Eliminar'), findsNothing);
    // Descargar sí (lo pedido: ver y descargar).
    expect(find.byTooltip('Descargar'), findsWidgets);

    // Se entra a la subcarpeta: se pide al servidor del DRIVE con la subruta.
    await tester.tap(find.text('Bodas'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Ana'), findsOneWidget);
    expect(mock.called, everyElement('/api/local/list'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('si el servidor del drive falla ofrece reintentar',
      (tester) async {
    final service = LocalShareService(
      baseUrl: 'http://drive.test',
      client: MockClient((_) async => http.Response('boom', 500)),
    );
    await _open(tester, service);

    expect(find.textContaining('No se pudo abrir la carpeta'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

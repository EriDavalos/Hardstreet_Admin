import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/services_page.dart';

/// Catálogo falso: los servicios aún traen `url` en la BD, pero la UI del
/// catálogo NO debe mostrarla ni mandarla (vive solo en el paquete comprado).
void _installMock({required List<Map<String, dynamic>> posts}) {
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;
    if (path.endsWith('/api/admin/services')) {
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'services': [
              {
                'id': 1,
                'name': 'Cobertura en evento',
                'description': 'Video y fotos del evento completo',
                'icon': 'material:videocam',
                'url': 'https://drive.google.com/drive/u/0/boda',
              },
              {
                'id': 2,
                'name': 'Álbum de fotos',
                'description': 'Selección de imágenes',
                'icon': 'icon/album.svg', // valor heredado de la web
                'url': '',
              },
            ],
          }),
          200,
          headers: headers,
        );
      }
      posts.add((jsonDecode(request.body) as Map).cast<String, dynamic>());
      return http.Response(
        jsonEncode({'ok': true}),
        request.method == 'POST' ? 201 : 200,
        headers: headers,
      );
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

Future<void> _pumpPage(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final previous = HsApi.client;
  addTearDown(() => HsApi.client = previous);

  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: ServicesPage())),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Baja dentro del formulario hasta que el campo quede a la vista.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.dragUntilVisible(
    finder,
    find.byType(SingleChildScrollView).last,
    const Offset(0, -220),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lista servicios con icono y descripción, SIN la liga del Drive',
      (tester) async {
    _installMock(posts: []);
    await _pumpPage(tester);

    expect(find.text('Cobertura en evento'), findsOneWidget);
    expect(find.text('Video y fotos del evento completo'), findsOneWidget);
    expect(find.text('Álbum de fotos'), findsOneWidget);
    // La liga del Drive NO aparece en el catálogo (se administra en el
    // paquete comprado, no aquí).
    expect(find.text('https://drive.google.com/drive/u/0/boda'),
        findsNothing);
    expect(find.text('1 con enlace'), findsNothing);
    expect(find.textContaining('con enlace'), findsNothing);
  });

  testWidgets('crear servicio manda nombre, icono y descripción (sin url)',
      (tester) async {
    final posts = <Map<String, dynamic>>[];
    _installMock(posts: posts);
    await _pumpPage(tester);

    await _tap(tester, find.text('Nuevo servicio'));
    // Botón del módulo + título del diálogo.
    expect(find.text('Nuevo servicio'), findsNWidgets(2));
    expect(find.text('Crear servicio'), findsOneWidget);

    // Elegir un icono del selector y llenar los campos.
    await _tap(tester, find.byIcon(Icons.music_note_outlined));
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre del servicio'),
      'Sesión previa',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Descripción'),
      'Sesión fotográfica antes del evento',
    );
    await _tap(tester, find.text('Crear servicio'));

    final create = posts.where((p) => p['name'] == 'Sesión previa').toList();
    expect(create, hasLength(1));
    expect(create.first['icon'], 'material:music_note');
    expect(create.first['description'], 'Sesión fotográfica antes del evento');
    // El catálogo ya no pide la URL del Drive.
    expect(create.first.containsKey('url'), isFalse);
  });

  testWidgets('editar servicio manda el id y solo los campos cambiados',
      (tester) async {
    final posts = <Map<String, dynamic>>[];
    _installMock(posts: posts);
    await _pumpPage(tester);

    // La tarjeta abre el diálogo de personalización con el nombre cargado.
    await _tap(tester, find.text('Álbum de fotos'));
    expect(find.text('Personalizar servicio'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre del servicio'),
      'Álbum premium',
    );
    await _tap(tester, find.text('Guardar cambios'));

    final update = posts.where((p) => p['id'] == 2).toList();
    expect(update, hasLength(1));
    expect(update.first['name'], 'Álbum premium');
  });

  testWidgets('los parámetros especiales guardan el máximo de fotos',
      (tester) async {
    final posts = <Map<String, dynamic>>[];
    _installMock(posts: posts);
    await _pumpPage(tester);

    await _tap(tester, find.text('Álbum de fotos'));
    await _reveal(tester, find.text('Elegir fotos'));
    expect(find.text('PARÁMETROS ESPECIALES'), findsOneWidget);

    // «Elegir fotos» trae su campo de cuántas fotos y enciende la carpeta.
    await _tap(tester, find.text('Elegir fotos'));
    await _reveal(tester, find.byKey(const ValueKey('service-photos-max')));
    await tester.enterText(
      find.byKey(const ValueKey('service-photos-max')),
      '12',
    );
    await _tap(tester, find.text('Guardar cambios'));

    final update = posts.where((p) => p['id'] == 2).toList();
    expect(update, hasLength(1));
    expect(update.first['photosMax'], 12);
    expect(update.first['allowFolder'], isTrue);
  });

  testWidgets('sin «Abrir carpeta» tampoco se puede elegir fotos',
      (tester) async {
    final posts = <Map<String, dynamic>>[];
    _installMock(posts: posts);
    await _pumpPage(tester);

    await _tap(tester, find.text('Álbum de fotos'));
    await _reveal(tester, find.text('Elegir fotos'));
    // Primero se encienden las fotos y después se apaga la carpeta: las fotos
    // se apagan solas (el selector vive DENTRO de la carpeta compartida).
    await _tap(tester, find.text('Elegir fotos'));
    await _reveal(tester, find.text('Abrir carpeta'));
    await _tap(tester, find.text('Abrir carpeta'));
    await _tap(tester, find.text('Guardar cambios'));

    final update = posts.where((p) => p['id'] == 2).toList();
    expect(update, hasLength(1));
    expect(update.first['photosMax'], 0);
    expect(update.first['allowFolder'], isFalse);
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/drive_base.dart';
import 'package:hardstreet_admin/drive_scope.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/packages_page.dart';

/// Catálogo falso para el módulo Paquetes (con tiers y categorías).
void _installMock({
  required List<Map<String, dynamic>> posts,
  List<Map<String, dynamic>>? services,
}) {
  final catalog =
      services ??
      <Map<String, dynamic>>[
        {
          'id': 1,
          'name': 'Cobertura',
          'description': 'Todo el evento',
          'icon': 'material:videocam',
          'url': '',
        },
        {
          'id': 2,
          'name': 'Álbum',
          'description': '100 fotos editadas',
          'icon': 'material:photo_library',
          'url': '',
        },
      ];
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;

    if (path.endsWith('/api/admin/packages')) {
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({'packages': []}),
          200,
          headers: headers,
        );
      }
      posts.add((jsonDecode(request.body) as Map).cast<String, dynamic>());
      return http.Response(jsonEncode({'ok': true}), 201, headers: headers);
    }
    if (path.endsWith('/api/tiers')) {
      return http.Response(
        jsonEncode({
          'tiers': [
            {'id': 1, 'name': 'Premium', 'tier': 1},
            {'id': 2, 'name': 'Gold', 'tier': 2},
            {'id': 3, 'name': 'Basic', 'tier': 3},
          ],
        }),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/categories')) {
      return http.Response(
        jsonEncode({
          'categories': [
            {'id': 7, 'name': 'Bodas', 'icon': ''},
          ],
        }),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/admin/services') && request.method == 'POST') {
      final body = (jsonDecode(request.body) as Map).cast<String, dynamic>();
      catalog.add({
        'id': catalog.length + 1,
        'name': (body['name'] ?? '').toString(),
        'description': (body['description'] ?? '').toString(),
        'icon': (body['icon'] ?? '').toString(),
        'url': '',
      });
      return http.Response(jsonEncode({'ok': true}), 201, headers: headers);
    }
    if (path.endsWith('/api/services')) {
      return http.Response(
        jsonEncode({'services': catalog}),
        200,
        headers: headers,
      );
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  List<Map<String, dynamic>>? services,
  bool withDrive = false,
  Size size = const Size(1200, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final previous = HsApi.client;
  _installMock(posts: [], services: services);
  addTearDown(() => HsApi.client = previous);

  const page = MaterialApp(home: Scaffold(body: PackagesPage()));
  await tester.pumpWidget(
    withDrive ? DriveScope(drive: _FakeDrive(), child: page) : page,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  // El módulo abre en la GALERÍA de categorías: se entra al catálogo completo
  // para probar el formulario de paquete.
  await _openCatalog(tester);
}

/// Entra al catálogo completo desde la galería de categorías.
Future<void> _openCatalog(WidgetTester tester) async {
  await tester.tap(find.text('TODO EL CATÁLOGO'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Drive de prueba sin red: una carpeta (`XV`) con una foto dentro.
class _FakeDrive extends DriveBase {
  static const Map<String, List<DriveItem>> tree = {
    '': [DriveItem(name: 'XV', isFolder: true)],
    'XV': [DriveItem(name: 'portada.jpg', isFolder: false, size: 2048)],
  };

  @override
  Future<void> refresh() async {
    updateItems(tree[path.join('/')] ?? const <DriveItem>[]);
    loadedPath = pathLabel;
    conn = DriveConn.online;
  }

  @override
  Future<List<DriveItem>> listFolderItems(List<String> rel) async =>
      tree[rel.join('/')] ?? const <DriveItem>[];

  @override
  List<String> listFolders(List<String> rel) => const <String>[];

  @override
  String absolutePathOf(DriveItem item) => [...path, item.name].join('/');

  @override
  Future<int> uploadFromPaths(
    List<String> sources, {
    bool overwrite = false,
  }) async => 0;

  @override
  Future<void> createFolder(String name) async {}

  @override
  Future<void> rename(DriveItem item, String newName) async {}

  @override
  Future<void> delete(DriveItem item) async {}

  @override
  Future<({int moved, List<String> errors})> moveItems(
    List<String> names,
    List<String> targetPath,
  ) async => (moved: 0, errors: const <String>[]);

  @override
  Future<({int copied, List<String> errors})> copyItems(
    List<String> names,
    List<String> targetPath,
  ) async => (copied: 0, errors: const <String>[]);

  @override
  Future<({int deleted, List<String> errors})> deleteItems(
    List<String> names,
  ) async => (deleted: 0, errors: const <String>[]);

  @override
  Future<void> retryUpload(String jobId) async {}
}

/// Deja correr unos frames (animaciones y desplazamientos) SIN esperar a que
/// todo quede quieto: el Drive de prueba y los menús tienen animaciones que no
/// terminan nunca, así que `pumpAndSettle` se colgaría.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  // Frames para que el desplazamiento termine: si se toca mientras la lista
  // todavía se mueve, el toque cae en otro widget.
  await _settle(tester);
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Elige una opción de un dropdown: se abre el menú y se toca la opción.
Future<void> _pick(WidgetTester tester, Finder dropdown, String option) async {
  await _tap(tester, dropdown);
  // El menú del dropdown puede pintar la etiqueta más de una vez: se toma la
  // última (la del menú desplegado).
  await _tap(tester, find.text(option).last);
}

Future<void> _openForm(WidgetTester tester) async {
  await _tap(tester, find.text('Nuevo paquete'));
}

void main() {
  testWidgets('el diálogo de paquete tiene pestañas Datos y Servicios', (
    tester,
  ) async {
    await _pumpPage(tester);
    await _openForm(tester);

    // Botón del módulo + título del diálogo.
    expect(find.text('Nuevo paquete'), findsNWidgets(2));
    expect(find.text('Crear paquete'), findsOneWidget);
    expect(find.text('Datos'), findsOneWidget);
    expect(find.text('Servicios'), findsOneWidget);

    // La pestaña Servicios lista el catálogo como en el administrador.
    await _tap(tester, find.text('Servicios'));
    expect(find.text('Cobertura'), findsOneWidget);
    expect(find.text('Álbum'), findsOneWidget);
    expect(find.text('0 de 2 seleccionados'), findsOneWidget);

    await _tap(tester, find.text('Cobertura'));
    expect(find.text('1 de 2 seleccionados'), findsOneWidget);
    // El contador también se marca en la pestaña.
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('crear paquete manda los servicios seleccionados', (
    tester,
  ) async {
    final posts = <Map<String, dynamic>>[];
    await _pumpPage(tester);
    final previous = HsApi.client;
    _installMock(posts: posts);
    addTearDown(() => HsApi.client = previous);
    await _openForm(tester);

    // Datos: nombre, tier y categoría.
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre'),
      'Boda Full',
    );
    final dropdowns = find.byType(DropdownButtonFormField<int>);
    await _pick(tester, dropdowns.first, 'Gold');
    await _pick(tester, dropdowns.at(1), 'Bodas');

    // Visibilidad en la web: se apaga desde "Público".
    await _tap(tester, find.text('Público (visible en la web)'));

    // Servicios: los dos incluidos.
    await _tap(tester, find.text('Servicios'));
    await _tap(tester, find.text('Cobertura'));
    await _tap(tester, find.text('Álbum'));
    await _tap(tester, find.text('Crear paquete'));

    final create = posts.where((p) => p['name'] == 'Boda Full').toList();
    expect(create, hasLength(1));
    expect(create.first['id_tier'], 2);
    expect(create.first['id_package_category'], 7);
    expect((create.first['serviceIds'] as List).toList(), [1, 2]);
    expect(
      create.first['is_public'],
      isFalse,
      reason: 'apagado = no se muestra en la web',
    );
  });

  testWidgets('en pantalla angosta los campos y la vista previa van en '
      'pestañas', (tester) async {
    await _pumpPage(tester, size: const Size(700, 820));
    await _openForm(tester);

    // La misma estructura del diseñador, pero apilada: una pestaña para los
    // campos (con sus Datos/Servicios dentro) y otra para la vista previa.
    expect(find.text('Editar'), findsOneWidget);
    expect(find.text('Vista previa'), findsOneWidget);
    expect(find.text('Datos'), findsOneWidget);
    expect(find.text('Servicios'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('si falta un dato de la pestaña Datos, el guardado regresa a '
      'ella con el motivo', (tester) async {
    await _pumpPage(tester);
    await _openForm(tester);

    await _tap(tester, find.text('Servicios'));
    await _tap(tester, find.text('Crear paquete'));

    expect(find.text('Escribe el nombre del paquete'), findsOneWidget);
  });

  testWidgets('la foto del paquete se elige DEL DRIVE (su URL pública queda '
      'en el campo)', (tester) async {
    await _pumpPage(tester, withDrive: true);
    await _openForm(tester);

    // El botón del campo de la imagen abre el MISMO selector de fotos del Drive
    // que usan los demás módulos (rejilla con miniatura, vista previa…).
    // El formulario es una lista perezosa: primero se baja hasta la foto.
    await tester.dragUntilVisible(
      find.text('Elegir una foto del Drive'),
      find
          .descendant(
            of: find.byType(Dialog),
            matching: find.byType(ListView),
          )
          .first,
      const Offset(0, -240),
    );
    await tester.pump();
    await _tap(tester, find.text('Elegir una foto del Drive'));
    expect(find.text('Foto del paquete'), findsOneWidget);

    // Se entra a la carpeta y se elige la foto.
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('XV')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _tap(tester, find.byKey(const ValueKey('drive-photo-portada.jpg')));
    await _tap(tester, find.text('Usar esta foto'));

    // El campo queda con la URL PÚBLICA (sin sesión): es la que la web abre.
    expect(
      find.widgetWithText(
        TextField,
        'https://oriongo.ddns.net/files/XV/portada.jpg',
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('la vista previa refleja los datos y se puede AGREGAR un '
      'servicio desde la pestaña Servicios', (tester) async {
    final catalog = <Map<String, dynamic>>[
      {
        'id': 1,
        'name': 'Cobertura',
        'description': 'Todo el evento',
        'icon': 'material:videocam',
        'url': '',
      },
    ];
    await _pumpPage(tester, services: catalog);
    await _openForm(tester);

    // La vista previa en vivo sigue el nombre que se escribe.
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre'),
      'Boda Oro',
    );
    await tester.pump();
    // El campo, la tarjeta de la vista previa y la fila compacta del catálogo.
    expect(
      find.text('Boda Oro'),
      findsNWidgets(2),
      reason: 'campo del formulario + tarjeta de la vista previa',
    );
    expect(
      find.descendant(
        of: find.byType(WebPackageCard),
        matching: find.text('Boda Oro'),
      ),
      findsOneWidget,
    );

    // Agregar un servicio nuevo sin salir de la personalización.
    await _tap(tester, find.text('Servicios'));
    await _tap(tester, find.text('Agregar'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre del servicio'),
      'Dron 4K',
    );
    await _tap(tester, find.text('Crear servicio'));

    // El servicio entra al catálogo y queda seleccionado automáticamente (se
    // ve en la lista Y en la vista previa, que ya lo incluye).
    expect(
      find.text('Dron 4K'),
      findsNWidgets(2),
      reason: 'lista de servicios + tarjeta de la vista previa ',
    );
    expect(find.text('1 de 2 seleccionados'), findsOneWidget);
    expect(catalog.any((s) => s['name'] == 'Dron 4K'), isTrue);
  });
}

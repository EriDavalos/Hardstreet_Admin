import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/drive_api_service.dart';
import 'package:hardstreet_admin/hs_access.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/packages_page.dart';
import 'package:hardstreet_admin/widgets/drive_thumb.dart';
import 'package:hardstreet_admin/widgets/form_dialog.dart';

// ==================================================================
// HARD STREET ADMIN — Módulo PAQUETES: la galería de categorías
// ==================================================================
// El módulo abre en la GALERÍA: los cards de las categorías del catálogo, cada
// uno con la foto que lo representa, cuántos paquetes tiene y desde qué precio
// salen. De ahí se entra a los paquetes (de una categoría o de todo el
// catálogo) SIN salir del módulo y SIN modal, y desde la galería se pueden
// CREAR categorías.
//
// Lo que se comprueba aquí:
//
//   * la galería es el arranque (y ya no hay tarjeta "Destacada");
//   * cada portada enseña la FOTO que la representa (o su emoji), con la misma
//     miniatura del drive que el resto del panel (w=640 + token);
//   * abrir una categoría muestra SUS paquetes con la MISMA tarjeta del
//     catálogo, editables, y se puede volver a la galería;
//   * "Todo el catálogo" muestra todos los paquetes;
//   * "Nueva categoría" crea la categoría de verdad (POST /api/admin/categories),
//     con su FOTO opcional (enlace o Drive), y el lápiz de una portada abre la
//     categoría para EDITARLA (PUT /api/admin/categories);
//   * sin permiso para ver el Drive, la opción "Elegir del Drive" no existe.
// ==================================================================

const _photoA =
    'https://oriongo.ddns.net/files/Boda/Ana/Fiesta/IMG_3196 Mejorado.jpg';

/// La portada de la categoría (otra foto DISTINTA: así se ve si de verdad se
/// publica la de la categoría y no solo la del paquete).
const _photoCat =
    'https://oriongo.ddns.net/files/ReynaCoot/Categoria/portada.jpg';

/// El botón "Personalizar" DENTRO de las cards (la barra de diseño también se
/// llama así: aquí interesa el de cada tarjeta de paquete).
final _cardEdit = find.descendant(
  of: find.byType(WebPackageCard),
  matching: find.text('Personalizar'),
);

const _packages = [
  {
    'id': 1,
    'name': 'Boda Premium',
    'subtitle': 'Cobertura completa',
    'price': 25000,
    'currency': 'MXN',
    'tierName': 'Premium',
    'categoryId': 1,
    'categoryName': 'Boda',
    'serviceNames': ['Cobertura'],
    'urlImage': _photoA,
  },
  {
    'id': 2,
    'name': 'Boda Basic',
    'subtitle': 'Lo esencial',
    'price': 12000,
    'currency': 'MXN',
    'tierName': 'Basic',
    'categoryId': 1,
    'categoryName': 'Boda',
    'serviceNames': ['Cobertura'],
    'urlImage': '',
  },
  {
    'id': 3,
    'name': 'XV Años Gold',
    'subtitle': 'Sesión + video',
    'price': 18000,
    'currency': 'MXN',
    'tierName': 'Gold',
    'categoryId': 2,
    'categoryName': 'XV Años',
    'serviceNames': ['Cobertura'],
    'urlImage': '',
  },
];

final _created = <Map<String, dynamic>>[];
final _updated = <Map<String, dynamic>>[];
final _deleted = <String>[];

void _installMock() {
  _created.clear();
  _updated.clear();
  _deleted.clear();
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;
    if (path.endsWith('/api/admin/categories') && request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      _created.add(body);
      return http.Response(
        jsonEncode({'ok': true, 'message': 'Categoría creada exitosamente'}),
        201,
        headers: headers,
      );
    }
    if (path.endsWith('/api/admin/categories') && request.method == 'PUT') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      _updated.add(body);
      return http.Response(
        jsonEncode({'ok': true, 'message': 'Categoría actualizada exitosamente'}),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/admin/categories') &&
        request.method == 'DELETE') {
      _deleted.add(request.url.queryParameters['id'] ?? '');
      return http.Response(
        jsonEncode({
          'ok': true,
          'message': 'Categoría eliminada exitosamente',
          'item': {'movedToGeneral': 2},
        }),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/admin/packages')) {
      return http.Response(
        jsonEncode({'packages': _packages}),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/categories')) {
      return http.Response(
        jsonEncode({
          'categories': [
            {'id': 1, 'name': 'Boda', 'icon': ''},
            {'id': 2, 'name': 'XV Años', 'icon': '', 'urlImage': _photoCat},
            {'id': 3, 'name': 'Bautizo', 'icon': ''},
          ],
        }),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/admin/site')) {
      return http.Response(
        jsonEncode({
          'design': {
            'card': {'imageMode': 'top', 'imageHeight': 120},
          },
        }),
        200,
        headers: headers,
      );
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

Future<void> _pump(WidgetTester tester) async {
  const size = Size(1240, 1100);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final previous = HsApi.client;
  _installMock();
  addTearDown(() => HsApi.client = previous);

  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: PackagesPage())),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() => HsSession.token = 'token-de-prueba');
  tearDown(() => HsSession.clear());

  testWidgets('el módulo arranca en la GALERÍA de categorías', (tester) async {
    await _pump(tester);

    // Portadas de las categorías del catálogo (con y sin paquetes).
    expect(find.textContaining('BODA'), findsWidgets);
    expect(find.textContaining('XV AÑOS'), findsWidgets);
    expect(find.textContaining('BAUTIZO'), findsWidgets);
    expect(find.text('Sin paquetes todavía'), findsOneWidget);
    // "Todo el catálogo" es la salida para ver todos los paquetes de golpe.
    expect(find.text('TODO EL CATÁLOGO'), findsOneWidget);
    // Cada portada dice cuántos paquetes tiene y desde qué precio salen.
    expect(find.textContaining('2 paquetes'), findsWidgets);
    expect(find.textContaining(r'$12,000'), findsWidgets);
    // Los paquetes NO se ven todavía: primero se elige una categoría.
    expect(find.byType(WebPackageCard), findsNothing);
    // La tarjeta "Destacada" de la galería anterior ya no existe.
    expect(find.text('Destacada'), findsNothing);
    // Y se puede crear una categoría desde aquí.
    expect(find.text('Nueva categoría'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cada portada enseña la FOTO que representa a la categoría', (
    tester,
  ) async {
    await _pump(tester);

    final thumbs = tester
        .widgetList<DriveThumb>(find.byType(DriveThumb))
        .where((t) => t.source.contains('/thumb/'))
        .toList();
    expect(
      thumbs,
      isNotEmpty,
      reason: 'la portada de la categoría se quedó sin foto',
    );
    // La foto es la del paquete que la tiene, pedida al servidor del drive en
    // tamaño de portada. Lleva el token: `/thumb` no exige permisos, pero lo
    // usa para saber en qué CARPETA DE EMPRESA está la foto (sin él, 404 y la
    // portada en blanco para cualquier usuario de empresa).
    expect(
      thumbs.first.source,
      contains('/thumb/Boda/Ana/Fiesta/IMG_3196%20Mejorado.jpg'),
    );
    expect(thumbs.first.source, contains('w=640'));
    expect(thumbs.first.source, contains('apikey=token-de-prueba'));
  });

  // La WEB no tiene sesión: sus fotos del Drive tienen que estar PUBLICADAS en
  // el servidor del drive. La portada de una CATEGORÍA se ve en el catálogo
  // igual que la de un paquete, así que también se publica (si no, la web la
  // pide y el servidor la niega: la imagen sale rota).
  testWidgets('publica en el drive las fotos de paquetes Y de categorías', (
    tester,
  ) async {
    final previous = DriveApiService.client;
    final published = <List<String>>[];
    DriveApiService.client = MockClient((request) async {
      if (request.url.path.endsWith('/api/public-photos')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        published.add((body['paths'] as List).cast<String>());
        return http.Response(
          jsonEncode({'ok': true, 'count': 1}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 200);
    });
    addTearDown(() => DriveApiService.client = previous);

    await _pump(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(published, isNotEmpty, reason: 'no se publicó ninguna foto');
    expect(
      published.first,
      contains('Boda/Ana/Fiesta/IMG_3196 Mejorado.jpg'),
      reason: 'la foto del paquete',
    );
    expect(
      published.first,
      contains('ReynaCoot/Categoria/portada.jpg'),
      reason: 'la portada de la categoría también la abre la web sin sesión',
    );
  });

  testWidgets('abrir una categoría muestra SUS paquetes en el mismo módulo', (
    tester,
  ) async {
    await _pump(tester);

    // La categoría sin paquetes lo explica en vez de quedarse en blanco.
    await _tap(tester, find.textContaining('BAUTIZO'));
    expect(
      find.text('No hay paquetes que coincidan. Crea el primero con el botón '
          '"Nuevo paquete".'),
      findsOneWidget,
    );
    await _tap(tester, find.byIcon(Icons.arrow_back_rounded));
    expect(find.text('TODO EL CATÁLOGO'), findsOneWidget);

    // Ahora la que sí tiene: se ven SUS paquetes con la tarjeta del catálogo.
    await _tap(tester, find.textContaining('BODA').first);
    expect(find.byType(WebPackageCard), findsNWidgets(2));
    expect(find.text('Boda Premium'), findsWidgets);
    expect(find.text('Boda Basic'), findsWidgets);
    // Dentro de una categoría sólo están SUS paquetes…
    expect(find.text('XV Años Gold'), findsNothing);
    // …y se editan como en el catálogo (no es una vista de solo lectura).
    expect(_cardEdit, findsNWidgets(2));
    expect(find.text('Nuevo paquete'), findsOneWidget);
    // No hay ningún modal por medio: todo pasa en la misma pantalla.
    expect(find.byType(AlertDialog), findsNothing);
    // Y se puede volver a la galería.
    await _tap(tester, find.byIcon(Icons.arrow_back_rounded));
    expect(find.text('TODO EL CATÁLOGO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Todo el catálogo" muestra todos los paquetes', (tester) async {
    await _pump(tester);

    await _tap(tester, find.text('TODO EL CATÁLOGO'));

    expect(find.byType(WebPackageCard), findsNWidgets(3));
    expect(find.text('Boda Premium'), findsWidgets);
    expect(find.text('XV Años Gold'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el buscador de la galería filtra por categoría o paquete', (
    tester,
  ) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField).first, 'XV');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('XV AÑOS'), findsWidgets);
    expect(find.textContaining('BODA'), findsNothing);
    expect(find.textContaining('BAUTIZO'), findsNothing);

    // Sin resultados, se dice (no una galería vacía sin explicación).
    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Sin resultados'), findsOneWidget);
  });

  testWidgets('se puede CREAR una categoría desde la galería', (tester) async {
    await _pump(tester);

    await _tap(tester, find.text('Nueva categoría'));
    expect(find.text('Nueva categoría'), findsWidgets);

    // El diálogo trae la VISTA PREVIA de la portada tal como saldrá en la
    // galería (y en la web).
    expect(find.byKey(const ValueKey('category-preview')), findsOneWidget);
    // (La sección se rotula en mayúsculas, como el resto del panel.)
    expect(find.text('ASÍ SE VERÁ EN EL CATÁLOGO'), findsOneWidget);

    // El nombre va en SU campo (el diálogo también tiene el de la foto).
    await tester.enterText(
      find.byKey(const ValueKey('category-name')),
      'Bautizo',
    );
    await _tap(tester, find.text('Crear categoría'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(_created, hasLength(1));
    expect(_created.single['name'], 'Bautizo');
    // Sin foto, no se manda el campo (la categoría usa la de su paquete).
    expect(_created.single.containsKey('urlImage'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la categoría nueva puede llevar su FOTO (enlace o Drive)', (
    tester,
  ) async {
    await _pump(tester);

    await _tap(tester, find.text('Nueva categoría'));
    await tester.enterText(
      find.byKey(const ValueKey('category-name')),
      'Graduación',
    );
    await tester.enterText(
      find.byKey(const ValueKey('category-image-url')),
      'https://oriongo.ddns.net/files/Boda/Ana/portada.jpg',
    );
    await tester.pump();
    // Con enlace, la opción del Drive sigue ahí y la miniatura se ve.
    expect(find.byKey(const ValueKey('category-image-drive')), findsOneWidget);
    expect(find.byType(DriveThumb), findsWidgets);

    await _tap(tester, find.text('Crear categoría'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(_created.single['name'], 'Graduación');
    expect(
      _created.single['urlImage'],
      'https://oriongo.ddns.net/files/Boda/Ana/portada.jpg',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('el lápiz de una portada EDITA la categoría (nombre y foto)', (
    tester,
  ) async {
    // Con permiso de actualizar, cada portada trae su botón "Personalizar".
    HsAccess.seedForTest(
      modules: const {
        'Categorías': {'read', 'create', 'update', 'delete'},
        'Paquetes': {'read', 'create', 'update'},
        'Archivos': {'read'},
      },
    );
    addTearDown(HsAccess.reset);
    await _pump(tester);

    await _tap(tester, find.byTooltip('Personalizar categoría').first);
    // El diálogo abre con lo que ya tenía la categoría.
    expect(find.text('Personalizar categoría'), findsWidgets);
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('category-name')))
          .controller!
          .text,
      isNotEmpty,
    );

    await tester.enterText(
      find.byKey(const ValueKey('category-image-url')),
      'https://oriongo.ddns.net/files/Boda/Ana/nueva-portada.jpg',
    );
    await _tap(tester, find.text('Guardar categoría'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(_updated, hasLength(1));
    expect(_updated.single['id'], isNotNull);
    expect(
      _updated.single['urlImage'],
      'https://oriongo.ddns.net/files/Boda/Ana/nueva-portada.jpg',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('eliminar una categoría se hace desde su PORTADA', (
    tester,
  ) async {
    HsAccess.seedForTest(
      modules: const {
        'Categorías': {'read', 'update', 'delete'},
        'Paquetes': {'read'},
      },
    );
    addTearDown(HsAccess.reset);
    await _pump(tester);

    // El botón de borrar vive en la ESQUINA superior derecha de cada portada
    // (una por categoría —Boda, XV Años y Bautizo—; "Todo el catálogo" no lo
    // lleva) y no dentro del formulario, que ya no ofrece eliminar.
    expect(find.byKey(const ValueKey('category-delete')), findsNWidgets(3));
    await _tap(tester, find.byKey(const ValueKey('category-delete')).first);

    // Se confirma (la acción avisa de que los paquetes pasan a "General").
    expect(find.textContaining('pasan a "General"'), findsOneWidget);
    await _tap(tester, find.text('Eliminar').last);

    expect(_deleted, hasLength(1));
    expect(_deleted.single, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('personalizar una categoría NO ofrece eliminar', (tester) async {
    HsAccess.seedForTest(
      modules: const {
        'Categorías': {'read', 'update', 'delete'},
        'Paquetes': {'read'},
      },
    );
    addTearDown(HsAccess.reset);
    await _pump(tester);

    await _tap(tester, find.byTooltip('Personalizar categoría').first);
    // El formulario ya no borra: eso es cosa de la portada (que sigue detrás
    // del modal con sus botones).
    final dialog = find.byType(FormDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(
        of: dialog,
        matching: find.byKey(const ValueKey('category-delete')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Eliminar')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin el permiso de eliminar, la portada no ofrece borrar', (
    tester,
  ) async {
    HsAccess.seedForTest(
      modules: const {
        'Categorías': {'read', 'update'},
        'Paquetes': {'read'},
      },
    );
    addTearDown(HsAccess.reset);
    await _pump(tester);

    expect(find.byKey(const ValueKey('category-delete')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin permiso para VER el Drive no se ofrece elegir del Drive', (
    tester,
  ) async {
    // El rol ve Categorías, pero no Archivos: las opciones del Drive se
    // ocultan.
    HsAccess.seedForTest(
      modules: const {
        'Categorías': {'read', 'create', 'update'},
        'Paquetes': {'read', 'create', 'update'},
        'Usuarios': {'read'},
      },
    );
    addTearDown(HsAccess.reset);
    await _pump(tester);

    await _tap(tester, find.text('Nueva categoría'));
    expect(find.text('Elegir del Drive'), findsNothing);
    expect(find.byKey(const ValueKey('category-image-drive')), findsNothing);
    // El campo del enlace sigue disponible.
    expect(find.byKey(const ValueKey('category-image-url')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

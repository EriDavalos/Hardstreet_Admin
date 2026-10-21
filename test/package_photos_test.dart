import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/packages_page.dart';
import 'package:hardstreet_admin/widgets/drive_thumb.dart';

// ==================================================================
// HARD STREET ADMIN — La FOTO del paquete en el catálogo del panel
// ==================================================================
// Bug reportado: \"no se ven las imágenes\". El panel pintaba un HUECO falso
// (\"Foto del paquete\" con un icono) en vez de la foto de verdad, así que el
// catálogo no se parecía a la página. Ahora se pide la MISMA foto que ve la
// web (`url_image`), al servidor del drive y en tamaño de tarjeta:
//
//   https://servidor/thumb/<ruta>?w=640&apikey=<token>
//
// `/thumb` NO exige permisos (las portadas se ven aunque al rol se le haya
// quitado "Ver Drive"), pero SÍ necesita saber de qué EMPRESA es la foto: la
// ruta que ve el panel es relativa a su carpeta. Sin el token, un usuario de
// empresa pedía la foto en la RAÍZ del disco y la portada salía en blanco.
// ==================================================================

const _drivePhoto =
    'https://oriongo.ddns.net/files/Boda/Ana/Fiesta/IMG_3196 Mejorado.jpg';

const _packages = [
  {
    'id': 1,
    'name': 'Boda Premium',
    'subtitle': 'Cobertura completa',
    'price': 25000,
    'currency': 'MXN',
    'tierName': 'Premium',
    'categoryName': 'Bodas',
    'serviceNames': ['Cobertura'],
    'urlImage': _drivePhoto,
  },
  {
    'id': 2,
    'name': 'XV Años Gold',
    'subtitle': 'Sesión + video',
    'price': 18000,
    'currency': 'MXN',
    'tierName': 'Gold',
    'categoryName': 'XV Años',
    'serviceNames': ['Cobertura'],
    'urlImage': '',
  },
];

void _installMock({String imageMode = 'top'}) {
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;
    if (path.endsWith('/api/admin/packages')) {
      return http.Response(
        jsonEncode({'packages': _packages}),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/admin/site')) {
      // El diseño pide la foto en BANDA arriba (como puede pedirla en fondo).
      return http.Response(
        jsonEncode({
          'design': {
            'card': {'imageMode': imageMode, 'imageHeight': 150},
          },
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
            {'id': 8, 'name': 'XV Años', 'icon': ''},
          ],
        }),
        200,
        headers: headers,
      );
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

Future<void> _pump(WidgetTester tester, {String imageMode = 'top'}) async {
  const size = Size(1240, 1000);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final previous = HsApi.client;
  _installMock(imageMode: imageMode);
  addTearDown(() => HsApi.client = previous);

  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: PackagesPage())),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  // El módulo abre en la GALERÍA de categorías: la foto del PAQUETE se ve al
  // entrar al catálogo, así que se abre "Todo el catálogo".
  await tester.tap(find.text('TODO EL CATÁLOGO'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() => HsSession.token = 'token-de-prueba');
  tearDown(() => HsSession.clear());

  testWidgets('la tarjeta pinta la FOTO real del paquete (la misma que la web)',
      (tester) async {
    await _pump(tester);

    final thumbs = tester
        .widgetList<DriveThumb>(find.byType(DriveThumb))
        .where((t) => t.source.contains('/thumb/'))
        .toList();
    expect(thumbs, isNotEmpty, reason: 'la foto del paquete no se pintó');

    final photo = thumbs.first;
    expect(
      photo.source,
      contains('/thumb/Boda/Ana/Fiesta/IMG_3196%20Mejorado.jpg'),
      reason: 'la foto se pide al servidor del drive, no a una URL inventada',
    );
    expect(photo.source, contains('w=640'));
    // El token va en la query (Image.network no manda cabeceras) y es lo que
    // dice al servidor en qué CARPETA DE EMPRESA buscar la foto.
    expect(
      photo.source,
      contains('apikey=token-de-prueba'),
      reason: 'sin el token, la foto de una empresa se busca en la raíz (404)',
    );
    expect(photo.isRemote, isTrue);
  });

  testWidgets('un paquete SIN foto se ve limpio (no inventa foto)', (
    tester,
  ) async {
    await _pump(tester);

    // El paquete sin foto NO pone una imagen de relleno ni un rótulo que lo
    // explique: su tarjeta se ve como la del panel (fondo del tier y ya).
    expect(find.text('Sin foto · la web usa una del sitio'), findsNothing);
    expect(find.text('Foto del paquete'), findsNothing);
    // La única foto pintada es la del paquete que SÍ la tiene.
    final withPhoto = tester
        .widgetList<DriveThumb>(find.byType(DriveThumb))
        .where((t) => t.source.contains('IMG_3196'))
        .length;
    expect(withPhoto, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('con la foto de FONDO, el paquete SIN foto pinta el degradado', (
    tester,
  ) async {
    await _pump(tester, imageMode: 'bg');

    // El hueco de la foto es el MISMO degradado del diseñador ("Así se verá en
    // la web"): un lavado del acento que se apaga a negro, en diagonal. Antes
    // el paquete sin foto quedaba como un bloque plano.
    final huecos = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.gradient)
        .whereType<LinearGradient>()
        .where(
          (g) =>
              g.begin == Alignment.topLeft &&
              g.colors.length == 2 &&
              (g.colors[0].a - .28).abs() < .02,
        )
        .toList();
    expect(huecos, isNotEmpty, reason: 'el hueco sin foto no tiene degradado');
    expect(huecos.first.colors[1].a, moreOrLessEquals(.35, epsilon: .02));

    // Y el paquete que SÍ tiene foto sigue enseñando su foto encima.
    expect(
      tester
          .widgetList<DriveThumb>(find.byType(DriveThumb))
          .where((t) => t.source.contains('IMG_3196'))
          .length,
      1,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('en la vista de FILAS la foto también se ve', (tester) async {
    await _pump(tester);

    await tester.tap(find.byIcon(Icons.view_list_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final thumbs = tester
        .widgetList<DriveThumb>(find.byType(DriveThumb))
        .where((t) => t.source.contains('IMG_3196'))
        .toList();
    expect(thumbs, hasLength(1));
    expect(thumbs.first.source, contains('w=160'));
    expect(tester.takeException(), isNull);
  });
}

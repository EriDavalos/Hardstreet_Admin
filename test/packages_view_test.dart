import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_access.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/packages_page.dart';
import 'package:hardstreet_admin/site_design.dart';

/// El módulo Paquetes abre en la GALERÍA de categorías y de ahí se entra a los
/// paquetes (de todo el catálogo o de una categoría). Ya dentro, el listado se
/// puede ver de dos formas y las DOS deben mostrar el mismo catálogo: en CARDS
/// (el flyer de la web, por defecto) o en FILAS (más compacto, para comparar).
/// Aquí se comprueba el conmutador y que cada vista pinte de verdad lo suyo.
///
/// Además: el diseño de las cards se personaliza AL INICIO del catálogo (la
/// barra va antes de las tarjetas, para no tener que bajar toda la lista), y
/// las cards dejan claro que se EDITAN: el botón "Personalizar" va en el PIE
/// de cada tarjeta (arriba ya no hay acciones) y toda la tarjeta es clicable.

/// El botón "Personalizar" DENTRO de las cards. La barra de diseño también
/// se llama así, y aquí lo que interesa es el de cada tarjeta.
final _cardEdit = find.descendant(
  of: find.byType(WebPackageCard),
  matching: find.text('Personalizar'),
);

const _packages = [
  {
    'id': 1,
    'name': 'Boda Full',
    'subtitle': 'Cobertura completa',
    'description': 'Todo el día',
    'price': 25000,
    'currency': 'MXN',
    'tierName': 'Premium',
    'tier': 1,
    'categoryId': 7,
    'categoryName': 'Bodas',
    'serviceNames': ['Cobertura', 'Álbum'],
  },
  {
    'id': 2,
    'name': 'XV Años Gold',
    'subtitle': 'Sesión + video',
    'description': '',
    'price': 18000,
    'currency': 'MXN',
    'tierName': 'Gold',
    'tier': 2,
    'categoryId': 8,
    'categoryName': 'XV Años',
    'serviceNames': ['Cobertura'],
  },
];

/// Paquetes borrados desde una tarjeta (para comprobar que borran de verdad).
final _deleted = <String>[];

void _installMock() {
  _deleted.clear();
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;
    if (path.endsWith('/api/admin/packages') && request.method == 'DELETE') {
      _deleted.add(request.url.queryParameters['id'] ?? '');
      return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
    }
    if (path.endsWith('/api/admin/packages')) {
      return http.Response(
        jsonEncode({'packages': _packages}),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/tiers')) {
      return http.Response(
        jsonEncode({
          'tiers': [
            {'id': 1, 'name': 'Premium', 'tier': 1},
            {'id': 2, 'name': 'Gold', 'tier': 2},
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
            {'id': 8, 'name': 'XV Años', 'icon': ''},
          ],
        }),
        200,
        headers: headers,
      );
    }
    if (path.endsWith('/api/services')) {
      return http.Response(jsonEncode({'services': []}), 200, headers: headers);
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  Size size = const Size(1240, 1000),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final previous = HsApi.client;
  _installMock();
  addTearDown(() => HsApi.client = previous);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: const Scaffold(body: PackagesPage()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  // El módulo abre en la GALERÍA de categorías: esta prueba es del LISTADO, así
  // que se entra a "Todo el catálogo" (la vista de cards/filas).
  await _openCatalog(tester);
}

/// Entra al listado de paquetes desde la galería de categorías.
Future<void> _openCatalog(WidgetTester tester) async {
  await tester.tap(find.text('TODO EL CATÁLOGO'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Cambia de vista con el botón del encabezado del listado.
Future<void> _toggle(WidgetTester tester) async {
  final button = find.byIcon(
    find.byIcon(Icons.view_list_rounded).evaluate().isNotEmpty
        ? Icons.view_list_rounded
        : Icons.grid_view_rounded,
  );
  expect(button, findsOneWidget);
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('por defecto el catálogo se ve en CARDS (el flyer de la web)', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Boda Full'), findsOneWidget);
    expect(find.text('XV Años Gold'), findsOneWidget);
    // El card trae su botón de edición y el precio del flyer.
    expect(_cardEdit, findsNWidgets(2));
    expect(find.text('Desde'), findsNWidgets(2));
    // El conmutador ofrece pasar a filas.
    expect(find.byIcon(Icons.view_list_rounded), findsOneWidget);
    // El diseño se personaliza AL INICIO: la barra se ve antes que las cards.
    final bar = find.byKey(const ValueKey('packages-design-bar'));
    expect(bar, findsOneWidget);
    expect(
      tester.getTopLeft(bar).dy,
      lessThan(tester.getTopLeft(find.text('Boda Full')).dy),
      reason: 'la barra de diseño debe estar por encima del catálogo',
    );
  });

  testWidgets('el conmutador cambia a FILAS y vuelve, sin perder el catálogo', (
    tester,
  ) async {
    await _pump(tester);
    expect(_cardEdit, findsNWidgets(2));

    await _toggle(tester);

    // Vista de filas: mismo catálogo, presentación compacta (sin CTA grande).
    expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
    expect(_cardEdit, findsNothing);
    expect(find.byIcon(Icons.edit_rounded), findsNWidgets(2));
    expect(find.text('Boda Full'), findsOneWidget);
    expect(find.text('XV Años Gold'), findsOneWidget);
    expect(find.text('PREMIUM'), findsOneWidget); // badge del tier
    expect(find.text('BODAS'), findsOneWidget); // categoría
    expect(find.text('2'), findsWidgets); // servicios incluidos
    expect(find.textContaining('servicio'), findsWidgets);

    // Y se puede volver a los cards.
    await _toggle(tester);
    expect(find.byIcon(Icons.view_list_rounded), findsOneWidget);
    expect(_cardEdit, findsNWidgets(2));
    // La barra de diseño sigue disponible (y arriba) en las dos vistas.
    final bar = find.byKey(const ValueKey('packages-design-bar'));
    expect(bar, findsOneWidget);
    expect(
      tester.getTopLeft(bar).dy,
      lessThan(tester.getTopLeft(find.text('Boda Full')).dy),
    );
  });

  testWidgets('el buscador sigue filtrando en la vista de filas', (
    tester,
  ) async {
    await _pump(tester);
    await _toggle(tester);

    await tester.enterText(find.byType(TextField).first, 'XV');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('XV Años Gold'), findsOneWidget);
    expect(find.text('Boda Full'), findsNothing);
  });

  testWidgets('la card tiene un tamaño MÁXIMO (450 × 675) y no se estira', (
    tester,
  ) async {
    // Pantalla muy ancha: sin tope, las tres columnas darían cards enormes.
    await _pump(tester, size: const Size(2400, 1400));

    final cards = find.byType(WebPackageCard);
    expect(cards, findsNWidgets(2));
    for (final card in cards.evaluate()) {
      final size = tester.getSize(find.byWidget(card.widget));
      expect(size.width, lessThanOrEqualTo(kPackageCardMaxWidth));
      expect(size.height, lessThanOrEqualTo(kPackageCardMaxHeight));
    }
    // Con espacio de sobra, la card se queda en su ancho máximo (no se
    // encoge ni se estira) y la fila la centra.
    expect(
      tester.getSize(cards.first).width,
      moreOrLessEquals(kPackageCardMaxWidth, epsilon: 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('al personalizar se ve la VISTA PREVIA de la tarjeta en vivo', (
    tester,
  ) async {
    await _pump(tester);

    // Se abre el paquete con el botón del pie de su tarjeta.
    await tester.tap(_cardEdit.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // La misma estructura del diseñador: campos y vista previa, con el panel
    // "Así se verá en la web" al lado.
    final form = find.byKey(const ValueKey('package-form'));
    expect(form, findsOneWidget);
    expect(find.textContaining('Así se verá'), findsOneWidget);

    // La vista previa es LA MISMA tarjeta del catálogo (y de la web), no un
    // boceto aparte: sale del diseño guardado.
    final preview = find.descendant(
      of: form,
      matching: find.byType(WebPackageCard),
    );
    expect(preview, findsOneWidget);
    // Y trae los datos del paquete que se está editando.
    expect(
      find.descendant(of: preview, matching: find.text('Boda Full')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: preview, matching: find.text(r'$25,000')),
      findsOneWidget,
    );

    // Al escribir, la vista previa cambia EN VIVO (el primer campo del
    // formulario es el nombre, en la pestaña "Datos").
    await tester.enterText(
      find.descendant(of: form, matching: find.byType(TextField)).first,
      'Boda Única',
    );
    await tester.pump();
    expect(
      find.descendant(of: preview, matching: find.text('Boda Única')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('eliminar un paquete se hace desde la ESQUINA de su card', (
    tester,
  ) async {
    HsAccess.seedForTest(
      modules: const {
        'Paquetes': {'read', 'update', 'delete'},
      },
    );
    addTearDown(HsAccess.reset);
    HsSession.token = 'token-de-prueba';
    addTearDown(HsSession.clear);
    await _pump(tester);

    // Una papelera por tarjeta, arriba a la derecha; el formulario ya no borra.
    final trash = find.byKey(const ValueKey('package-delete'));
    expect(trash, findsNWidgets(2));
    expect(
      tester.getTopLeft(find.byType(WebPackageCard).first).dx,
      lessThan(tester.getTopLeft(trash.first).dx),
      reason: 'la papelera va en la esquina, a la derecha de la tarjeta',
    );

    await tester.tap(trash.first);
    await tester.pump();
    // Pide confirmación antes de borrar (y avisa de las consecuencias).
    expect(find.text('¿Eliminar paquete?'), findsOneWidget);
    expect(find.textContaining('dejará de aparecer'), findsOneWidget);
    await tester.tap(find.text('Eliminar').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_deleted, ['1']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin permiso de borrar, la card no lleva papelera', (
    tester,
  ) async {
    HsAccess.seedForTest(
      modules: const {
        'Paquetes': {'read', 'update'},
      },
    );
    addTearDown(HsAccess.reset);
    await _pump(tester);

    expect(find.byKey(const ValueKey('package-delete')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // El CELULAR es donde peor se veía: la barra de diseño metía icono, texto y
  // botón en una sola fila (el texto quedaba en una columna de ~37 px, una
  // palabra por renglón, y los colores de los tiers se salían 210 px).
  testWidgets('en el CELULAR la barra de diseño apila el botón y no desborda', (
    tester,
  ) async {
    await _pump(tester, size: const Size(390, 844));
    expect(tester.takeException(), isNull);

    final bar = find.byKey(const ValueKey('packages-design-bar'));
    expect(bar, findsOneWidget);

    // El texto respira: ocupa el ancho de la tarjeta (no una columna fina).
    final desc = find.textContaining('Forma, densidad');
    expect(tester.getSize(desc).width, greaterThan(200));

    // Y el botón va DEBAJO del texto, a lo ancho.
    final button = find.descendant(
      of: bar,
      matching: find.text('Personalizar'),
    );
    expect(button, findsOneWidget);
    expect(
      tester.getTopLeft(button).dy,
      greaterThan(tester.getTopLeft(desc).dy),
      reason: 'el botón baja a su propia fila en el celular',
    );
    expect(
      tester.getSize(bar).height,
      lessThan(320),
      reason: 'la barra tiene que quedar compacta',
    );
  });

  testWidgets('en el CELULAR el formulario del paquete llena la pantalla', (
    tester,
  ) async {
    await _pump(tester, size: const Size(390, 844));

    final edit = find
        .descendant(
          of: find.byType(WebPackageCard),
          matching: find.text('Personalizar'),
        )
        .first;
    await tester.ensureVisible(edit);
    await tester.pump();
    await tester.tap(edit);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Sin márgenes (antes quedaba un marco de 18 px) y con el pie a la vista:
    // el botón de guardar se salía 72 px de la pantalla.
    final form = find.byKey(const ValueKey('package-form'));
    expect(form, findsOneWidget);
    final surface = find
        .descendant(of: form, matching: find.byType(Material))
        .first;
    expect(tester.getRect(surface), const Rect.fromLTRB(0, 0, 390, 844));
    expect(
      tester.getRect(find.text('Guardar cambios')).bottom,
      lessThan(844),
    );
    expect(tester.takeException(), isNull);
  });

  // El módulo se usa en claro y en oscuro: el catálogo tiene que pintarse
  // entero (cards y filas) sin desbordes ni excepciones de layout.
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('cards y filas se pintan sin errores en modo $brightness', (
      tester,
    ) async {
      await _pump(tester, brightness: brightness);
      expect(_cardEdit, findsNWidgets(2));
      expect(tester.takeException(), isNull);

      await _toggle(tester);
      expect(find.text('Boda Full'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  // El estilo nuevo ("fondo con degradado de desaparición"): la foto se funde
  // con el color —o el degradado— de fondo elegido en el diseñador. Aquí se
  // comprueba que la tarjeta del panel lo pinta de verdad.
  testWidgets('el fondo con degradado pinta el fondo del diseño y la máscara', (
    tester,
  ) async {
    const design = SiteDesign(
      card: SiteCardDesign(
        imageMode: 'fade',
        cardBgFrom: '#123456',
        cardBgTo: '#654321',
        cardBgGradient: true,
        cardBgAngle: 200,
        imageFadeStart: .2,
        imageFadeEnd: .7,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              height: 900,
              child: WebPackageCard(
                pkg: _packages.first,
                design: design,
                onEdit: () {},
                onDelete: () {},
                canEdit: false,
                canDelete: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // El fondo de la tarjeta es el DEGRADADO del diseño (no el color del tier).
    final fondos = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((b) => b.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.gradient)
        .whereType<LinearGradient>()
        .where(
          (g) =>
              g.colors.first == const Color(0xFF123456) &&
              g.colors.last == const Color(0xFF654321),
        );
    expect(fondos, isNotEmpty, reason: 'el fondo del diseño debe pintarse');

    // Y la foto va con la MÁSCARA del desvanecido (no con un velo encima).
    expect(find.byType(ShaderMask), findsWidgets);
    expect(find.text('Boda Full'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

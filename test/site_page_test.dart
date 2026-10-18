import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardstreet_admin/pages/site_page.dart';
import 'package:hardstreet_admin/web_content.dart';
import 'package:hardstreet_admin/web_sections.dart';
import 'package:hardstreet_admin/widgets/site_section_preview.dart';

// ==================================================================
// MÓDULO SITIO WEB (diseñador por SECCIONES)
// ==================================================================
//   1. Los ganchos del HTML y el catálogo del panel deben coincidir: si alguien
//      agrega un `data-hs` en la portada sin editor (o al revés), falla aquí.
//   2. Los valores de fábrica del catálogo son los que dice el HTML.
//   3. El documento sólo guarda lo CAMBIADO, y las secciones llevan sus
//      opciones (`props`) tal como se editaron.
//   4. La página: una tarjeta por sección con su miniatura, sus campos y el
//      guardado de lo editado.
// ==================================================================

const String _htmlPath = '../Hardstreet/index.html';

bool get _htmlAvailable => File(_htmlPath).existsSync();

String readHtml() => File(_htmlPath).readAsStringSync();

/// Claves de un tipo de gancho en el HTML (data-hs, data-hs-img…).
Set<String> hooksOf(String html, String attribute) {
  final re = RegExp('$attribute="([^"]+)"');
  return re.allMatches(html).map((m) => m.group(1)!).toSet();
}

/// El HTML con las entidades que usa el catálogo ya resueltas.
String normalizedHtml() => readHtml().replaceAll('&copy;', '©');

/// Implementación de mentira: guarda en memoria lo que recibe.
class FakeSiteApi implements SiteContentApi {
  FakeSiteApi({
    this.stored = SiteContent.empty,
    this.failOnLoad = false,
    this.dbHasContent = false,
    this.categories = const [
      (key: 'boda', name: 'Boda'),
      (key: 'xv-anos', name: 'XV Años'),
    ],
    this.gold = '#C9A96E',
  });

  SiteContent stored;
  final bool failOnLoad;

  /// ¿La base de datos ya tiene contenido de la portada? (lo que decide que el
  /// panel mande el documento COMPLETO en cada guardado).
  bool dbHasContent;
  final List<({String key, String name})> categories;
  final String gold;
  final List<SiteContent> saves = [];

  @override
  Future<SiteContent> load() async {
    if (failOnLoad) throw Exception('sin servidor');
    return stored;
  }

  @override
  Future<void> save(SiteContent content) async {
    saves.add(content);
    stored = content;
    if (content.texts.isNotEmpty || content.images.isNotEmpty) {
      dbHasContent = true;
    }
  }

  @override
  Future<SiteContext> context() async => SiteContext(
        categories: categories,
        gold: gold,
        stored: dbHasContent,
      );
}

void main() {
  group('ganchos de la portada (panel ⇄ HTML)', () {
    test('cada texto del catálogo tiene su gancho en el HTML, y al revés', () {
      if (!_htmlAvailable) {
        markTestSkipped('La web no está junto al panel: $_htmlPath');
        return;
      }
      final html = readHtml();
      expect(hooksOf(html, 'data-hs'),
          kSiteTexts.map((f) => f.key).toSet(),
          reason: 'Los textos del panel y los ganchos del HTML deben ser los mismos');
      expect(hooksOf(html, 'data-hs-img'),
          kSiteImages.map((f) => f.key).toSet(),
          reason: 'Las imágenes del panel y los ganchos del HTML deben ser los mismos');
      expect(hooksOf(html, 'data-hs-section'),
          kSiteSections.map((f) => f.key).toSet(),
          reason: 'Las secciones del panel y los ganchos del HTML deben ser los mismos');
    });

    test('los valores de fábrica son los que trae el HTML', () {
      if (!_htmlAvailable) {
        markTestSkipped('La web no está junto al panel: $_htmlPath');
        return;
      }
      final html = normalizedHtml();
      for (final f in kSiteTexts) {
        for (final part in f.def.split('|')) {
          expect(html.contains(part.trim()), isTrue,
              reason: 'El texto de fábrica de "${f.key}" no está en el HTML: '
                  '"${part.trim()}"');
        }
      }
      // Las imágenes se declaran en el HTML… salvo los fondos (hero y divisor),
      // que viven en el CSS.
      final css = File('../Hardstreet/index.css').readAsStringSync();
      for (final f in kSiteImages) {
        final where = f.background ? css : html;
        expect(where.contains(f.def), isTrue,
            reason: 'La imagen de fábrica de "${f.key}" no está en '
                '${f.background ? 'index.css' : 'index.html'}: ${f.def}');
      }
    });

    test('ninguna clave está repetida en el catálogo', () {
      for (final keys in [
        kSiteTexts.map((f) => f.key).toList(),
        kSiteImages.map((f) => f.key).toList(),
        kSiteSections.map((f) => f.key).toList(),
      ]) {
        expect(keys.toSet().length, keys.length);
      }
      // Y los textos de dos líneas lo declaran (si no, se perdería el énfasis).
      expect(kSiteTexts.firstWhere((f) => f.key == 'hero_title').lines, isTrue);
      expect(kSiteTexts.firstWhere((f) => f.key == 'hero_eyebrow').lines, isFalse);
    });
  });

  group('documento del sitio', () {
    test('sólo se guarda lo cambiado: los mapas vacíos no viajan', () {
      const doc = SiteContent(
        texts: {'hero_cta': 'Reservar'},
        sections: {'contact': SiteSectionState(visible: false, order: 1)},
      );
      final json = doc.toJson();
      expect(json.containsKey('images'), isFalse);
      expect(json['texts'], {'hero_cta': 'Reservar'});
      expect((json['sections'] as Map)['contact'], {'visible': false, 'order': 1});
      expect(SiteContent.empty.toJson(), isEmpty);
      expect(SiteContent.empty.isEmpty, isTrue);
    });

    test('las opciones de una sección viajan con ella y vuelven igual', () {
      const doc = SiteContent(
        sections: {
          'about': SiteSectionState(
            visible: true,
            order: 2,
            props: {
              'stats': [
                {'value': 12, 'label': 'Bodas'},
              ],
            },
          ),
        },
      );
      final json = doc.toJson();
      final saved = ((json['sections'] as Map)['about'] as Map);
      expect(saved['props'], {
        'stats': [
          {'value': 12, 'label': 'Bodas'},
        ],
      });
      // Y de vuelta: se lee tal cual (una sección sin props no los inventa).
      final back = SiteContent.fromJson(json);
      expect(back.propsOf('about')['stats'], isA<List>());
      expect((back.propsOf('about')['stats'] as List).single,
          {'value': 12, 'label': 'Bodas'});
      expect(back.propsOf('hero'), isEmpty);
    });

    test('lectura tolerante: lo raro se ignora y queda el default', () {
      final c = SiteContent.fromJson({
        'texts': {'hero_cta': '  Reservar  ', 'packages_title': '   '},
        'images': 'no-es-mapa',
        'sections': {
          'contact': {'visible': false, 'order': 3},
          'gallery': 'basura',
          'inventada': {'visible': false, 'order': 9},
        },
      });
      expect(c.textOf('hero_cta'), 'Reservar');
      expect(c.textOf('packages_title'), isNull); // vacío = sin cambio
      expect(c.images, isEmpty);
      expect(c.sectionOf('contact').visible, isFalse);
      expect(c.sectionOf('contact').order, 3);
      // Una sección con datos rotos cae a su valor de fábrica.
      expect(c.sectionOf('gallery').visible, isTrue);
      // Y una sección que el panel no conoce se conserva (la web la usa igual).
      expect(c.sections['inventada']?.visible, isFalse);
    });

    test('cuenta los campos editados para las píldoras', () {
      const doc = SiteContent(
        texts: {'a': '1', 'b': '2'},
        images: {'logo': 'x.png'},
        sections: {'contact': SiteSectionState(visible: false, order: 1)},
      );
      expect(doc.editedCount, 4);
    });
  });

  group('página del módulo', () {
    /// Monta la página como la ve el panel, con una pantalla alta (así caben
    /// varias secciones a la vez).
    /// La pantalla de las pruebas es ALTA a propósito: así las diez tarjetas
    /// (con sus miniaturas) están construidas a la vez y ninguna prueba depende
    /// de que un widget entre o no en la ventana.
    Future<void> pumpPage(
      WidgetTester tester, {
      required SiteContentApi api,
      bool supported = true,
      Size size = const Size(1500, 8000),
    }) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SitePage(api: api, supported: supported)),
      ));
      await tester.pumpAndSettle();
    }

    Finder cardOf(String key) => find.byKey(ValueKey('site-section-$key'));

    /// Despliega los campos de una sección (toca su botón "Editar").
    ///
    /// Si la tarjeta YA estaba abierta (su botón dice "Cerrar"), no hace nada:
    /// las pruebas la pueden llamar sin saber en qué estado quedó.
    Future<void> expand(WidgetTester tester, String key) async {
      final card = cardOf(key);
      final edit = find.descendant(of: card, matching: find.text('Editar'));
      if (edit.evaluate().isEmpty) return;
      await tester.tap(edit);
      await tester.pumpAndSettle();
    }

    /// Guarda (el botón vive en el encabezado del módulo).
    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
    }

    testWidgets('en plataformas sin soporte avisa y no pide datos',
        (tester) async {
      final api = FakeSiteApi();
      await pumpPage(tester, api: api, supported: false);

      expect(find.text('Disponible solo en Windows'), findsOneWidget);
      expect(api.saves, isEmpty);
    });

    testWidgets('cada sección es una tarjeta con su miniatura y sus campos',
        (tester) async {
      final api = FakeSiteApi();
      await pumpPage(tester, api: api);

      // La portada es lo primero y trae su miniatura.
      expect(cardOf('hero'), findsOneWidget);
      expect(
        find.descendant(
            of: cardOf('hero'), matching: find.byType(SiteSectionPreview)),
        findsOneWidget,
      );
      // La miniatura muestra el titular actual (las dos líneas del HTML).
      expect(find.descendant(of: cardOf('hero'), matching: find.text('Capturando')),
          findsOneWidget);
      expect(find.descendant(of: cardOf('hero'), matching: find.text('Momentos Únicos')),
          findsOneWidget);
      // Y sus etiquetas de plantilla / orden.
      expect(find.descendant(of: cardOf('hero'), matching: find.text('Plantilla')),
          findsOneWidget);
      expect(find.descendant(of: cardOf('hero'), matching: find.text('1')),
          findsOneWidget);

      // Al desplegarla aparecen sus campos de texto.
      await expand(tester, 'hero');
      expect(find.widgetWithText(TextField, 'Titular'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Fondo de la portada'), findsOneWidget);
    });

    testWidgets('la miniatura se puede ver EN GRANDE dentro del módulo',
        (tester) async {
      final api = FakeSiteApi();
      await pumpPage(tester, api: api);

      final big = find.byKey(const ValueKey('site-preview-hero'));
      expect(big, findsOneWidget);
      await tester.ensureVisible(big);
      await tester.tap(big);
      await tester.pumpAndSettle();

      // La MISMA maqueta, más grande (y sin salir del módulo ni abrir nada
      // fuera del panel).
      expect(find.byType(SiteSectionPreview), findsWidgets);
      expect(find.textContaining('Así se verá esta parte'), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('carga lo guardado, avisa de cambios y guarda lo editado',
        (tester) async {
      final api = FakeSiteApi(
        stored: const SiteContent(texts: {'hero_cta': 'Reservar'}),
      );
      await pumpPage(tester, api: api);

      // Como no se ha tocado nada, no hay nada que guardar.
      final saveButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Guardar cambios'),
      );
      expect(saveButton.onPressed, isNull);

      await expand(tester, 'hero');
      // El campo del botón trae lo guardado…
      expect(find.widgetWithText(TextField, 'Reservar'), findsOneWidget);

      // Se edita el titular: aparecen cambios sin guardar.
      await tester.enterText(
        find.widgetWithText(TextField, 'Titular'),
        'Fotografía que|Cuenta Historias',
      );
      await tester.pumpAndSettle();
      // El pie (al final de la página) lo avisa.
      expect(find.textContaining('Hay cambios sin guardar'), findsOneWidget);

      await save(tester);

      expect(api.saves, hasLength(1));
      final saved = api.saves.single;
      expect(saved.textOf('hero_title'), 'Fotografía que|Cuenta Historias');
      expect(saved.textOf('hero_cta'), 'Reservar'); // lo demás se conserva
      // Y sin opciones tocadas, las secciones viajan sin `props`.
      expect(saved.sectionOf('hero').props, isEmpty);
    });

    testWidgets('los números de "Sobre nosotros" se editan y se guardan como '
        'opciones de la sección', (tester) async {
      final api = FakeSiteApi();
      await pumpPage(tester, api: api);

      await expand(tester, 'about');
      // Los tres números de fábrica están a la vista (con sus etiquetas).
      final firstValue = find.byKey(const ValueKey('about-stat-0-value'));
      expect(firstValue, findsOneWidget);
      expect(find.text('Proyectos'), findsWidgets);

      await tester.enterText(firstValue, '48');
      await tester.enterText(
          find.byKey(const ValueKey('about-stat-0-label')), 'Bodas');
      await tester.pumpAndSettle();

      // Un número más: se agrega a la lista.
      await tester.tap(find.text('Agregar número'));
      await tester.pumpAndSettle();
      final lastValue = find.byKey(const ValueKey('about-stat-3-value'));
      expect(lastValue, findsOneWidget);
      await tester.enterText(lastValue, '7');
      await tester.enterText(
          find.byKey(const ValueKey('about-stat-3-label')), 'Estudios');
      await tester.pumpAndSettle();

      await save(tester);

      final stats =
          (api.saves.single.sectionOf('about').props['stats'] as List)
              .cast<Map>()
              .map((m) => m.cast<String, dynamic>())
              .toList();
      expect(stats, hasLength(4));
      expect(stats.first, {'value': 48, 'label': 'Bodas'});
      expect(stats.last, {'value': 7, 'label': 'Estudios'});
      // Los otros números siguen ahí, intactos.
      expect(stats[1], {'value': 4, 'label': 'Años Exp.'});
    });

    testWidgets('la galería guarda las fotos de cada categoría',
        (tester) async {
      final api = FakeSiteApi();
      await pumpPage(tester, api: api);

      await expand(tester, 'gallery');
      // Están las categorías del catálogo, cada una con su botón.
      expect(find.text('Boda'), findsWidgets);
      expect(find.text('XV Años'), findsWidgets);

      // Se pega una URL en la PRIMERA categoría (Boda).
      await tester.tap(find.text('Pegar URL').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'images/banner.jpg',
      );
      await tester.tap(find.text('Agregar'));
      await tester.pumpAndSettle();

      // Y se ve en la tarjeta (con su miniatura).
      expect(find.textContaining('1 foto'), findsWidgets);

      await save(tester);
      final cats =
          (api.saves.single.sectionOf('gallery').props['categories'] as List)
              .cast<Map>()
              .map((m) => m.cast<String, dynamic>())
              .toList();
      expect(cats, hasLength(1));
      expect(cats.single['key'], 'boda');
      expect(cats.single['items'], ['images/banner.jpg']);
      expect(api.saves.single.sectionOf('gallery').props['mode'], 'custom');
    });

    testWidgets('las secciones se pueden ocultar y reordenar', (tester) async {
      final api = FakeSiteApi();
      await pumpPage(tester, api: api);

      // La portada baja un puesto (su flecha de bajar) y se oculta.
      final hero = cardOf('hero');
      await tester.tap(find.descendant(
          of: hero, matching: find.byIcon(Icons.keyboard_arrow_down_rounded)));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: hero, matching: find.byType(Switch)));
      await tester.pumpAndSettle();

      // El aviso de la tarjeta lo dice.
      expect(find.descendant(of: hero, matching: find.text('Oculta')),
          findsOneWidget);

      await save(tester);
      final saved = api.saves.single;
      expect(saved.sectionOf('hero').visible, isFalse);
      expect(saved.sectionOf('hero').order, 2);
      expect(saved.sectionOf('about').order, 1);
      // El orden del resto se conserva (la siguiente es la galería).
      expect(saved.sectionOf('gallery').order, 3);
      // Y no se tocó ningún campo de texto.
      expect(saved.texts, isEmpty);
    });

    testWidgets('una sección oculta no pierde lo que tenía escrito',
        (tester) async {
      // Un titular propio (distinto del de fábrica: lo igual al HTML no viaja).
      final api = FakeSiteApi(
        stored: const SiteContent(texts: {'packages_title': 'Paquetes a tu medida'}),
      );
      await pumpPage(tester, api: api);

      // Se oculta y se guarda: la sección viaja como oculta, con su texto.
      final packages = cardOf('packages');
      await tester.tap(find.descendant(of: packages, matching: find.byType(Switch)));
      await tester.pumpAndSettle();
      await save(tester);

      expect(api.saves.single.sectionOf('packages').visible, isFalse);
      expect(api.saves.single.textOf('packages_title'), 'Paquetes a tu medida');
      expect(api.saves.single.sectionOf('packages').props, isEmpty);

      // Y al volver a encenderla, el texto sigue igual (no se perdió nada).
      await tester.tap(find.descendant(of: packages, matching: find.byType(Switch)));
      await tester.pumpAndSettle();
      await save(tester);

      expect(api.saves.last.sectionOf('packages').visible, isTrue);
      expect(api.saves.last.textOf('packages_title'), 'Paquetes a tu medida');
      // En el primer guardado la base quedó con contenido: a partir de ahí los
      // guardados van COMPLETOS, así que las opciones de la sección viajan con
      // sus valores de fábrica (los que la web usaba hasta ahora).
      expect(api.saves.last.sectionOf('packages').props,
          siteSectionDefaults('packages'));
      // El campo del titular también lo sigue mostrando.
      await expand(tester, 'packages');
      expect(find.widgetWithText(TextField, 'Paquetes a tu medida'), findsOneWidget);
    });

    testWidgets('con la base vacía avisa y sube TODO el contenido actual',
        (tester) async {
      // La web está usando su HTML: el módulo lo dice y ofrece pasar lo que hay
      // a la base de datos (que es lo que hace que la web lo lea de ahí).
      final api = FakeSiteApi();
      await pumpPage(tester, api: api);

      expect(find.text('La base de datos todavía no tiene el contenido'),
          findsOneWidget);
      expect(find.text('En el HTML del sitio'), findsOneWidget);

      await tester.tap(find.text('Guardar lo actual en la base'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar en la base'));
      await tester.pumpAndSettle();

      // Viaja el documento COMPLETO: cada texto y cada imagen del catálogo,
      // aunque no se haya tocado nada.
      final saved = api.saves.single;
      expect(saved.texts, hasLength(kSiteTexts.length));
      expect(saved.images, hasLength(kSiteImages.length));
      expect(saved.textOf('hero_title'),
          kSiteTexts.firstWhere((f) => f.key == 'hero_title').def);
      // Y las secciones con sus opciones de fábrica (los números de "Sobre
      // nosotros", por ejemplo).
      expect(
          (saved.sectionOf('about').props['stats'] as List), hasLength(3));
      expect(saved.sectionOf('hero').visible, isTrue);

      // Después de subirlo, el aviso desaparece y el encabezado lo dice.
      expect(find.text('La base de datos todavía no tiene el contenido'),
          findsNothing);
      expect(find.text('En la base de datos'), findsOneWidget);
    });

    testWidgets('con la base llena cada guardado manda todo (no se pierde '
        'nada)', (tester) async {
      // Si la base ya tiene el contenido, un guardado NO puede mandar sólo lo
      // que se tocó en esta sesión: borraría todo lo demás.
      final api = FakeSiteApi(
        dbHasContent: true,
        stored: const SiteContent(
          texts: {'hero_cta': 'Reservar', 'about_title': 'Nuestra historia'},
        ),
      );
      await pumpPage(tester, api: api);

      await expand(tester, 'hero');
      await tester.enterText(
          find.widgetWithText(TextField, 'Titular'), 'Bodas que|se recuerdan');
      await tester.pumpAndSettle();
      await save(tester);

      final saved = api.saves.single;
      expect(saved.textOf('hero_title'), 'Bodas que|se recuerdan');
      // Lo que ya estaba guardado sigue viajando…
      expect(saved.textOf('hero_cta'), 'Reservar');
      expect(saved.textOf('about_title'), 'Nuestra historia');
      // …y lo de fábrica también (la base es la fuente de verdad).
      expect(saved.texts, hasLength(kSiteTexts.length));
      expect(saved.images, hasLength(kSiteImages.length));
    });

    testWidgets('si el servidor falla, ofrece reintentar', (tester) async {
      final api = FakeSiteApi(failOnLoad: true);
      await pumpPage(tester, api: api);

      expect(find.text('Reintentar'), findsOneWidget);
      expect(api.saves, isEmpty);
      // El módulo no se rompe: la miniatura nunca llegó a pintarse.
      expect(find.byType(SiteSectionPreview), findsNothing);
    });
  });
}

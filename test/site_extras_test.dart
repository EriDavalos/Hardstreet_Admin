import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardstreet_admin/pages/site_page.dart';
import 'package:hardstreet_admin/web_content.dart';
import 'package:hardstreet_admin/web_sections.dart';

// ==================================================================
// SECCIONES AGREGADAS (copias de una plantilla)
// ==================================================================
// En "Sitio web" cada bloque existe una vez en la página. Con "Agregar sección"
// se puede poner OTRA copia (una segunda galería, otro divisor de fotos…): la
// copia nace con lo que tenga la sección de la que se copia y después se edita
// aparte, sin tocar la original.
//
// Aquí se comprueba:
//   1. El documento: las copias viajan en `extraSections`, completas y con su
//      nombre (`gallery-2`), y la lectura es tolerante.
//   2. La página: el catálogo sólo ofrece las plantillas repetibles, agregar
//      monta la tarjeta de la copia, y lo que se escriba en ella se guarda en
//      la copia (la sección original no se toca).
//   3. Quitar la copia la saca del documento.
// ==================================================================

/// Doble del contenido del sitio (igual que el de `site_page_test.dart`).
class _FakeSiteApi implements SiteContentApi {
  _FakeSiteApi({this.stored = SiteContent.empty, this.dbHasContent = false});

  SiteContent stored;
  bool dbHasContent;

  /// Categorías del catálogo de paquetes (para el editor de la galería).
  static const List<({String key, String name})> categories = [
    (key: 'boda', name: 'Boda'),
    (key: 'xv-anos', name: 'XV Años'),
  ];
  final List<SiteContent> saves = [];

  @override
  Future<SiteContent> load() async => stored;

  @override
  Future<void> save(SiteContent content) async {
    saves.add(content);
    stored = content;
    dbHasContent = true;
  }

  @override
  Future<SiteContext> context() async => SiteContext(
        categories: categories,
        gold: '#C9A96E',
        stored: dbHasContent,
      );
}

/// Una copia de la galería con fotos de una categoría (como la guarda el panel).
SiteExtraSection _galleryCopy({
  String id = 'gallery-2',
  String title = 'Nuestro Portafolio',
  List<String> items = const ['images/banner.jpg'],
}) =>
    SiteExtraSection(
      id: id,
      key: 'gallery',
      order: 8,
      texts: {'gallery_title': title},
      props: {
        'mode': 'custom',
        'categories': [
          {'key': 'boda', 'name': 'Boda', 'items': items},
        ],
      },
    );

void main() {
  group('documento: secciones agregadas', () {
    test('una copia viaja completa y vuelve igual', () {
      final doc = SiteContent(extraSections: [_galleryCopy()]);
      final json = doc.toJson();
      expect(json['extraSections'], hasLength(1));

      final back = SiteContent.fromJson(json);
      expect(back.extraSections, hasLength(1));
      final extra = back.extraSections.single;
      expect(extra.id, 'gallery-2');
      expect(extra.key, 'gallery');
      expect(extra.texts['gallery_title'], 'Nuestro Portafolio');
      expect(siteGalleryCategories(extra.props).single.items,
          ['images/banner.jpg']);
      expect(back.sameAs(doc), isTrue,
          reason: 'lo que va y vuelve tiene que ser lo mismo');
    });

    test('lectura tolerante: lo que no sirve se descarta', () {
      final back = SiteContent.fromJson({
        'extraSections': [
          {'id': 'gallery-2', 'key': 'gallery'}, // bien (sin contenido)
          {'id': '', 'key': 'gallery'}, // sin nombre
          {'id': 'parallax-2'}, // sin plantilla
          {'id': 'gallery-2', 'key': 'gallery'}, // repetida
          'basura',
        ],
      });
      expect(back.extraSections.map((e) => e.id), ['gallery-2']);
      // Sin contenido no se guarda basura (los textos vacíos se caen).
      expect(back.extraSections.single.texts, isEmpty);
    });

    test('las copias cuentan como contenido editado', () {
      const vacio = SiteContent();
      expect(vacio.isEmpty, isTrue);
      final conCopia = SiteContent(extraSections: [_galleryCopy()]);
      expect(conCopia.isEmpty, isFalse);
      expect(conCopia.editedCount, 1);
    });
  });

  group('página: agregar y quitar secciones', () {
    Future<void> pumpPage(WidgetTester tester, _FakeSiteApi api) async {
      // Pantalla alta: así todas las tarjetas están construidas a la vez.
      await tester.binding.setSurfaceSize(const Size(1500, 9000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SitePage(api: api, supported: true)),
      ));
      await tester.pumpAndSettle();
    }

    Finder cardOf(String key) => find.byKey(ValueKey('site-section-$key'));

    Future<void> expand(WidgetTester tester, String key) async {
      final card = cardOf(key);
      final edit = find.descendant(of: card, matching: find.text('Editar'));
      if (edit.evaluate().isEmpty) return;
      await tester.tap(edit);
      await tester.pumpAndSettle();
    }

    Future<void> addSection(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(const ValueKey('site-add-section')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('site-add-$key-go')));
      await tester.pumpAndSettle();
    }

    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
    }

    testWidgets('el catálogo ofrece las plantillas repetibles', (tester) async {
      final api = _FakeSiteApi();
      await pumpPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('site-add-section')));
      await tester.pumpAndSettle();

      // La galería y el divisor se pueden repetir…
      expect(find.byKey(const ValueKey('site-add-gallery')), findsOneWidget);
      expect(find.byKey(const ValueKey('site-add-parallax')), findsOneWidget);
      // …y lo que sale del catálogo de paquetes no tiene sentido repetirlo.
      expect(find.byKey(const ValueKey('site-add-packages')), findsNothing);
      expect(find.byKey(const ValueKey('site-add-services')), findsNothing);
    });

    testWidgets('la copia nace con el HTML propio de su original',
        (tester) async {
      const code = '<div class="packages-grid"><p>Hecho a mano</p></div>';
      final api = _FakeSiteApi(
        stored: const SiteContent(html: {'gallery': code}),
      );
      await pumpPage(tester, api);

      await addSection(tester, 'gallery');

      // La copia ya trae el HTML de la original (y lo anuncia su botón).
      final copyHtml = find.byKey(const ValueKey('site-html-gallery-2'));
      expect(
        find.descendant(of: copyHtml, matching: find.text('Editar HTML')),
        findsOneWidget,
      );

      await save(tester);
      final saved = api.saves.single;
      expect(saved.htmlOf('gallery-2'), code);
      expect(saved.extraSections.single.html, code);
      // La original conserva el suyo.
      expect(saved.htmlOf('gallery'), code);
    });

    testWidgets('agregar monta la copia y lo editado se guarda EN LA COPIA',
        (tester) async {
      final api = _FakeSiteApi();
      await pumpPage(tester, api);

      await addSection(tester, 'gallery');

      // La copia es una tarjeta más, con su nombre y su etiqueta.
      expect(cardOf('gallery-2'), findsOneWidget);
      expect(
        find.descendant(of: cardOf('gallery-2'), matching: find.text('Galería destacada 2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: cardOf('gallery-2'), matching: find.text('Agregada')),
        findsOneWidget,
      );
      // La original sigue donde estaba.
      expect(cardOf('gallery'), findsOneWidget);

      // Se le escribe su propio título (la tarjeta queda abierta al agregarla).
      await tester.enterText(
        find.descendant(
          of: cardOf('gallery-2'),
          matching: find.widgetWithText(TextField, 'Título'),
        ),
        'Portafolio|de Bodas',
      );
      await tester.pumpAndSettle();
      await save(tester);

      final saved = api.saves.single;
      expect(saved.extraSections, hasLength(1));
      final copy = saved.extraSections.single;
      expect(copy.id, 'gallery-2');
      expect(copy.key, 'gallery');
      expect(copy.texts['gallery_title'], 'Portafolio|de Bodas');
      // El titular de la sección ORIGINAL no se tocó (sigue leyéndose del HTML).
      expect(saved.textOf('gallery_title'), isNull);
    });

    testWidgets('la copia arranca con las opciones de la original (y aparte)',
        (tester) async {
      // La galería de fábrica ya tiene sus fotos elegidas.
      final api = _FakeSiteApi(
        dbHasContent: true,
        stored: const SiteContent(sections: {
          'gallery': SiteSectionState(visible: true, order: 3, props: {
            'mode': 'custom',
            'categories': [
              {
                'key': 'boda',
                'name': 'Boda',
                'items': ['images/banner.jpg'],
              },
            ],
          }),
        }),
      );
      await pumpPage(tester, api);

      await addSection(tester, 'gallery');
      await save(tester);

      final copy = api.saves.single.extraSections.single;
      expect(siteGalleryCategories(copy.props).single.items,
          ['images/banner.jpg'],
          reason: 'la copia arranca con las fotos que ya tenía la galería');
      // Y las fotos de la original siguen siendo suyas.
      expect(
        siteGalleryCategories(api.saves.single.propsOf('gallery')).single.items,
        ['images/banner.jpg'],
      );
    });

    testWidgets('quitar la copia la saca del documento', (tester) async {
      final api = _FakeSiteApi(
        dbHasContent: true,
        stored: SiteContent(extraSections: [_galleryCopy()]),
      );
      await pumpPage(tester, api);

      // La copia guardada se monta con lo que tenía (su tarjeta y sus campos).
      expect(cardOf('gallery-2'), findsOneWidget);
      await expand(tester, 'gallery-2');
      expect(
        find.descendant(
          of: cardOf('gallery-2'),
          matching: find.widgetWithText(TextField, 'Nuestro Portafolio'),
        ),
        findsOneWidget,
        reason: 'el campo del título de la copia trae lo guardado',
      );

      await tester.tap(find.byKey(const ValueKey('site-remove-gallery-2')));
      await tester.pumpAndSettle();
      // Pregunta antes de quitarla.
      expect(find.text('¿Quitar "Galería destacada 2"?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Quitar'));
      await tester.pumpAndSettle();

      expect(cardOf('gallery-2'), findsNothing);
      await save(tester);
      expect(api.saves.single.extraSections, isEmpty);
    });
  });
}

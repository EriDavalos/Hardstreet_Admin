import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardstreet_admin/pages/site_page.dart';
import 'package:hardstreet_admin/web_content.dart';
import 'package:hardstreet_admin/widgets/site_html_editor.dart';
import 'package:hardstreet_admin/widgets/site_html_preview.dart';

// ==================================================================
// HTML PROPIO DE CADA SECCIÓN (módulo "Sitio web")
// ==================================================================
//   1. El documento guarda el HTML por sección (y el de las copias) y viaja
//      entero de ida y vuelta.
//   2. Un cambio de HTML cuenta como cambio sin guardar.
//   3. El editor: se teclea, se insertan etiquetas del sitio y "Usar este HTML"
//      devuelve el código; vaciarlo devuelve '' (la web arma la sección como
//      siempre).
//   4. La página: el HTML editado se guarda con "Guardar cambios" y lo
//      guardado se recupera al abrir el módulo.
//
// La vista previa REAL (WebView con el sitio empaquetado) no existe en el
// entorno de pruebas: como en el resto del panel, se inyecta un doble por
// `previewBuilder`.
// ==================================================================

/// Implementación de mentira: guarda en memoria lo que recibe.
class FakeSiteApi implements SiteContentApi {
  FakeSiteApi({this.stored = SiteContent.empty});

  SiteContent stored;
  final List<SiteContent> saves = [];

  @override
  Future<SiteContent> load() async => stored;

  @override
  Future<void> save(SiteContent content) async {
    saves.add(content);
    stored = content;
  }

  @override
  Future<SiteContext> context() async => const SiteContext(
        categories: [(key: 'boda', name: 'Boda')],
        gold: '#C9A96E',
        stored: false,
      );
}

/// Doble de la vista previa: guarda lo último que le pidieron pintar.
class FakePreview {
  SiteHtmlPreviewController? controller;
  String? sectionId;
  String? html;
  int builds = 0;

  Widget build(
    BuildContext context,
    SiteHtmlPreviewController controller,
    String sectionId,
    String html,
  ) {
    this.controller = controller;
    this.sectionId = sectionId;
    this.html = html;
    builds++;
    return Container(
      key: const ValueKey('fake-site-preview'),
      color: const Color(0xFF101010),
      alignment: Alignment.center,
      child: const Text('vista previa del sitio'),
    );
  }
}

/// Monta el editor y devuelve la promesa con lo que el diálogo devuelva.
Future<Future<String?>> openEditor(
  WidgetTester tester, {
  required String initialHtml,
  SiteHtmlPreviewBuilder? previewBuilder,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  late Future<String?> result;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () {
              result = showSiteHtmlEditor(
                context,
                sectionId: 'hero',
                sectionLabel: 'Portada',
                sectionTemplate: 'hero',
                initialHtml: initialHtml,
                previewBuilder: previewBuilder,
              );
            },
            child: const Text('abrir editor'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir editor'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('documento del sitio (html por sección)', () {
    test('viaja de ida y vuelta y descarta lo vacío', () {
      const code = '<div class="hero-content"><h1>Hola</h1></div>';
      final doc = SiteContent.fromJson({
        'html': {
          'hero': code,
          'about': '   ',
        },
      });
      expect(doc.htmlOf('hero'), code);
      expect(doc.htmlOf('about'), '');
      expect(doc.toJson()['html'], {'hero': code});

      final again = SiteContent.fromJsonText(doc.toJson());
      expect(again.htmlOf('hero'), code);
      expect(again.sameAs(doc), isTrue);
    });

    test('un HTML distinto es un cambio (y cuenta para las píldoras)', () {
      const a = SiteContent(html: {'hero': '<h1>A</h1>'});
      const b = SiteContent(html: {'hero': '<h1>B</h1>'});
      expect(a.sameAs(b), isFalse);
      expect(a.sameAs(const SiteContent(html: {'hero': '<h1>A</h1>'})), isTrue);
      expect(a.editedCount, 1);
    });

    test('las copias llevan su propio HTML', () {
      const copy = SiteExtraSection(
        id: 'gallery-2',
        key: 'gallery',
        order: 3,
        html: '<div class="packages-grid"></div>',
      );
      final back = SiteExtraSection.fromJson(copy.toJson())!;
      expect(back.html, copy.html);
      expect(back, copy);
      // Sin HTML, la clave ni siquiera viaja (no engordamos el documento).
      expect(const SiteExtraSection(id: 'x', key: 'hero').toJson(),
          isNot(contains('html')));
    });

    test('lo que no es un mapa de HTML se ignora', () {
      final doc = SiteContent.fromJson({'html': 'hola'});
      expect(doc.html, isEmpty);
      final copy = SiteExtraSection.fromJson({
        'id': 'hero-2',
        'key': 'hero',
        'html': null,
      })!;
      expect(copy.html, '');
    });
  });

  group('editor de HTML', () {
    testWidgets('lo tecleado se devuelve con "Usar este HTML"',
        (tester) async {
      final fake = FakePreview();
      final result = await openEditor(tester,
          initialHtml: '', previewBuilder: fake.build);

      await tester.enterText(
        find.byKey(const ValueKey('site-html-code')),
        '<h2 class="section-title">Nueva portada</h2>',
      );
      await tester.pumpAndSettle();
      expect(fake.sectionId, 'hero');

      // La vista previa se refresca sola, sin cerrar el diálogo.
      await tester.pump(const Duration(milliseconds: 500));
      expect(fake.html, contains('Nueva portada'));

      await tester.tap(find.byKey(const ValueKey('site-html-apply')));
      await tester.pumpAndSettle();
      expect(await result, '<h2 class="section-title">Nueva portada</h2>');
    });

    testWidgets('los botones insertan etiquetas que el sitio ya estiliza',
        (tester) async {
      final fake = FakePreview();
      final result =
          await openEditor(tester, initialHtml: '', previewBuilder: fake.build);

      await tester.tap(find.text('Título'));
      await tester.pump();
      await tester.tap(find.text('Botón'));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('site-html-apply')));
      await tester.pumpAndSettle();
      final code = await result;
      expect(code, contains('<h2 class="section-title">'));
      expect(code, contains('class="hero-cta"'));
    });

    testWidgets('vaciarlo devuelve la sección a sus campos', (tester) async {
      final fake = FakePreview();
      final result = await openEditor(tester,
          initialHtml: '<p>Algo</p>', previewBuilder: fake.build);

      await tester.tap(find.text('Quitar HTML'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('site-html-apply')));
      await tester.pumpAndSettle();
      expect(await result, '');
    });

    testWidgets('cancelar no toca nada', (tester) async {
      final fake = FakePreview();
      final result = await openEditor(tester,
          initialHtml: '<p>Algo</p>', previewBuilder: fake.build);

      await tester.enterText(
          find.byKey(const ValueKey('site-html-code')), '<p>Otro</p>');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });
  });

  group('página del módulo', () {
    Future<void> pumpPage(
      WidgetTester tester, {
      required SiteContentApi api,
      SiteHtmlPreviewBuilder? previewBuilder,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1500, 8000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SitePage(
            api: api,
            supported: true,
            previewBuilder: previewBuilder,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Finder cardOf(String key) => find.byKey(ValueKey('site-section-$key'));

    Future<void> expand(WidgetTester tester, String key) async {
      final edit =
          find.descendant(of: cardOf(key), matching: find.text('Editar'));
      if (edit.evaluate().isEmpty) return;
      await tester.tap(edit);
      await tester.pumpAndSettle();
    }

    testWidgets('el HTML de la sección se escribe y se guarda',
        (tester) async {
      final api = FakeSiteApi();
      final fake = FakePreview();
      await pumpPage(tester, api: api, previewBuilder: fake.build);

      await expand(tester, 'hero');
      // Cada sección trae su acceso al editor.
      final open = find.byKey(const ValueKey('site-html-hero'));
      expect(open, findsOneWidget);
      expect(
        find.descendant(of: open, matching: find.text('Escribir HTML')),
        findsOneWidget,
      );

      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(fake.sectionId, 'hero');

      await tester.enterText(
        find.byKey(const ValueKey('site-html-code')),
        '<div class="hero-content"><h1>Hecho a mano</h1></div>',
      );
      await tester.tap(find.byKey(const ValueKey('site-html-apply')));
      await tester.pumpAndSettle();

      // La tarjeta ya lo anuncia y la página tiene cambios sin guardar.
      expect(
        find.descendant(of: open, matching: find.text('Editar HTML')),
        findsOneWidget,
      );
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();

      expect(api.saves, hasLength(1));
      expect(
        api.saves.single.htmlOf('hero'),
        '<div class="hero-content"><h1>Hecho a mano</h1></div>',
      );
    });

    testWidgets('lo guardado se recupera al abrir el módulo', (tester) async {
      final api = FakeSiteApi(
        stored: const SiteContent(html: {'hero': '<h1>Guardado</h1>'}),
      );
      await pumpPage(tester, api: api, previewBuilder: FakePreview().build);

      await expand(tester, 'hero');
      final open = find.byKey(const ValueKey('site-html-hero'));
      expect(
        find.descendant(of: open, matching: find.text('Editar HTML')),
        findsOneWidget,
      );

      await tester.tap(open);
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('site-html-code')),
      );
      expect(field.controller!.text, '<h1>Guardado</h1>');
    });

    testWidgets('quitar el HTML lo borra del documento', (tester) async {
      final api = FakeSiteApi(
        stored: const SiteContent(html: {'hero': '<h1>Guardado</h1>'}),
      );
      await pumpPage(tester, api: api, previewBuilder: FakePreview().build);

      await expand(tester, 'hero');
      await tester.tap(find.byKey(const ValueKey('site-html-hero')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quitar HTML'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('site-html-apply')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();

      expect(api.saves, hasLength(1));
      expect(api.saves.single.html, isEmpty);
    });
  });
}

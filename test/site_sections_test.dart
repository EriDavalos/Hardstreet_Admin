import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hardstreet_admin/web_content.dart';
import 'package:hardstreet_admin/web_sections.dart';

// ==================================================================
// SECCIONES DEL SITIO — el panel y la web deben ver LO MISMO
// ==================================================================
// El módulo "Sitio web" edita, sección por sección, sus textos, sus imágenes y
// sus OPCIONES (los números de "Sobre nosotros", las fotos de cada categoría,
// los comentarios de los clientes…). Las opciones viajan en el documento de la
// portada y las aplica la web (`Hardstreet/gallery/assets/site.js`).
//
// Si los dos lados se separan, el panel mostraría una cosa y la página otra:
// estas pruebas lo impiden.
//
//   1. Los valores de fábrica son idénticos en los dos archivos.
//   2. Cada sección del catálogo de ganchos pertenece a una plantilla real.
//   3. Las claves CSS de categoría son las mismas ("XV Años" → "xv-anos").
// ==================================================================

/// Ruta del script del sitio, relativa a la raíz del panel Flutter.
const String _siteJsPath = '../Hardstreet/gallery/assets/site.js';

/// ¿Existe la web junto al panel? (si el panel se compila solo, se salta).
bool get _webAvailable => File(_siteJsPath).existsSync();

/// Extrae y decodifica `const SITE_SECTIONS_DEFAULT = { … };` de site.js.
///
/// Se recorta contando llaves y se adapta el literal de JavaScript a JSON:
/// quita comentarios, comas finales, comillas simples y claves sin comillas.
Map<String, dynamic> readWebSectionDefaults() {
  final text = File(_siteJsPath).readAsStringSync();
  final marker = text.indexOf('SITE_SECTIONS_DEFAULT = {');
  expect(marker, greaterThanOrEqualTo(0),
      reason: 'site.js debería declarar SITE_SECTIONS_DEFAULT');
  final start = text.indexOf('{', marker);
  var depth = 0;
  var end = -1;
  for (var i = start; i < text.length; i++) {
    final ch = text[i];
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) {
        end = i + 1;
        break;
      }
    }
  }
  expect(end, greaterThan(0), reason: 'El objeto de defaults quedó sin cerrar');
  final js = text
      .substring(start, end)
      // Comentarios de línea (por si el objeto se comenta en el futuro).
      .replaceAll(RegExp(r'//.*?(?=\r?\n)'), '')
      // Comas finales: válidas en JS, ilegales en JSON.
      .replaceAllMapped(RegExp(r',\s*([}\]])'), (m) => m[1]!)
      // El contenido se escribe con comillas simples…
      .replaceAll("'", '"')
      // …y con claves sin comillas (válido en JS, no en JSON).
      .replaceAllMapped(
          RegExp(r'([{,]\s*)([A-Za-z_][A-Za-z0-9_]*)\s*:'),
          (m) => '${m[1]}"${m[2]}":');
  return (jsonDecode(js) as Map).cast<String, dynamic>();
}

void main() {
  group('opciones de sección (panel ⇄ web)', () {
    test('los defaults del panel son EXACTAMENTE los de la web', () {
      if (!_webAvailable) {
        markTestSkipped('La web no está junto al panel: $_siteJsPath');
        return;
      }
      final web = readWebSectionDefaults();
      expect(
        jsonEncode(web),
        jsonEncode(kSiteSectionDefaults),
        reason: 'Los defaults de web_sections.dart y site.js deben ser los '
            'mismos: si no, el panel mostraría algo distinto de la página',
      );
    });

    test('cada plantilla tiene sus defaults y viceversa', () {
      for (final t in kSiteSectionTemplates) {
        expect(kSiteSectionDefaults.containsKey(t.key), isTrue,
            reason: 'Falta el valor de fábrica de la sección "${t.key}"');
      }
      for (final key in kSiteSectionDefaults.keys) {
        expect(siteSectionTemplate(key), isNotNull,
            reason: 'La sección "$key" tiene defaults pero no plantilla');
      }
    });

    test('las secciones que se ordenan son las del HTML', () {
      // Las que se pueden mover/ocultar tienen gancho de sección en la portada.
      expect(
        kOrderableSectionTemplates.map((t) => t.key).toSet(),
        kSiteSections.map((s) => s.key).toSet(),
      );
    });
  });

  group('catálogo de ganchos por sección', () {
    test('todos los textos e imágenes caen en una sección conocida', () {
      for (final f in kSiteTexts) {
        expect(siteSectionTemplate(f.sectionKey), isNotNull,
            reason: 'El texto "${f.key}" (grupo "${f.group}") no pertenece a '
                'ninguna sección: revisa kSiteGroupSections');
      }
      for (final f in kSiteImages) {
        expect(siteSectionTemplate(f.sectionKey), isNotNull,
            reason: 'La imagen "${f.key}" (grupo "${f.group}") no pertenece a '
                'ninguna sección: revisa kSiteGroupSections');
      }
    });

    test('cada sección tiene algo que editar (o es de sólo mostrar)', () {
      for (final t in kSiteSectionTemplates) {
        final hasTexts = kSiteTexts.any((f) => f.sectionKey == t.key);
        final hasImages = kSiteImages.any((f) => f.sectionKey == t.key);
        expect(hasTexts || hasImages || t.props.isNotEmpty, isTrue,
            reason: 'La sección "${t.key}" no tiene ningún campo editable');
      }
    });
  });

  group('opciones guardadas', () {
    test('lo guardado se mezcla sobre los valores de fábrica', () {
      final props = siteSectionProps('about', {
        'stats': [
          {'value': 12, 'label': 'Bodas'},
        ],
      });
      expect((props['stats'] as List).length, 1);
      // Y lo que no vino se queda como viene.
      final packages = siteSectionProps('packages', null);
      expect(packages['groupByCategory'], isTrue);
    });

    test('las listas de una sección se leen tipadas', () {
      final props = siteSectionProps('testimonials', {
        'items': [
          {'name': 'Ana', 'role': 'Boda', 'text': 'Genial'},
          {'name': '', 'role': '', 'text': ''}, // se descarta
        ],
      });
      final items = siteTestimonials(props);
      expect(items, hasLength(1));
      expect(items.first.name, 'Ana');
      expect(items.first.role, 'Boda');

      final gallery = siteSectionProps('gallery', {
        'mode': 'custom',
        'categories': [
          {
            'key': 'boda',
            'name': 'Boda',
            'items': ['images/banner.jpg', ' '],
          },
          {'key': 'vacia', 'name': 'Vacía', 'items': <String>[]},
        ],
      });
      final cats = siteGalleryCategories(gallery);
      expect(cats, hasLength(2));
      expect(cats.first.items, ['images/banner.jpg']);
      expect(cats.last.items, isEmpty);

      final stats = siteStats(siteSectionProps('about', {
        'stats': [
          {'value': 30, 'label': 'Proyectos'},
        ],
      }));
      expect(stats.single.value, 30);
      expect(stats.single.label, 'Proyectos');
    });
  });

  group('claves de categoría (panel ⇄ web)', () {
    test('la clave es la misma que la de la página', () {
      // La web usa hsCategoryKey() para el `data-category` de sus tarjetas.
      expect(siteCategoryKey('XV Años'), 'xv-anos');
      expect(siteCategoryKey('  Boda  '), 'boda');
      expect(siteCategoryKey('Graduación'), 'graduacion');
      expect(siteCategoryKey('Sesión & Retoque'), 'sesion-retoque');
      expect(siteCategoryKey('Bautizo'), 'bautizo');
      expect(siteCategoryKey('¡Comercial!'), 'comercial');
    });
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';

// ==================================================================
// HARD STREET ADMIN — PLANTILLAS DE SECCIÓN DEL SITIO WEB
// ==================================================================
// El módulo "Sitio web" está hecho de SECCIONES: una tarjeta por bloque de la
// página (Portada, Sobre nosotros, Galería…), con su miniatura de cómo se ve y
// sus campos al lado. Este archivo es el CATÁLOGO de esas plantillas: qué
// opciones tiene cada sección, con qué valores viene de fábrica y qué ganchos
// del HTML le corresponden.
//
//   * Agregar una sección nueva al sitio = agregar una plantilla aquí (con sus
//     campos) y sus ganchos en el HTML: el módulo la pinta sola.
//   * Los DEFAULTS de `kSiteSectionDefaults` son EXACTAMENTE los de la web
//     (`Hardstreet/gallery/assets/site.js`, `SITE_SECTIONS_DEFAULT`). Una
//     prueba compara los dos archivos: así el panel nunca muestra algo
//     distinto de lo que la página tiene.
//   * Los textos e imágenes de cada sección salen del catálogo de ganchos
//     (`web_content.dart`), agrupados por sección con `kSiteGroupSections`.
// ==================================================================

/// Qué control usa una opción de sección en el panel.
enum SitePropKind {
  /// Texto corto.
  text,

  /// Número (con topes [SitePropField.min]/[SitePropField.max]).
  number,

  /// Interruptor (sí/no).
  toggle,

  /// Pares valor + etiqueta (las estadísticas de "Sobre nosotros").
  stats,

  /// Fotos por categoría de la galería (elegidas del Drive o por URL).
  gallery,

  /// Comentarios de clientes (nombre, servicio y texto).
  testimonials,
}

/// Una opción propia de una sección (lo que NO es un texto ni una imagen).
class SitePropField {
  const SitePropField({
    required this.key,
    required this.label,
    required this.kind,
    this.hint,
    this.min = 0,
    this.max = 99,
  });

  final String key;
  final String label;
  final SitePropKind kind;

  /// Ayuda corta bajo el control.
  final String? hint;

  /// Topes de un número (sólo para [SitePropKind.number]).
  final int min;
  final int max;
}

/// Una SECCIÓN (plantilla) del sitio web.
class SiteSectionTemplate {
  const SiteSectionTemplate({
    required this.key,
    required this.label,
    required this.description,
    required this.icon,
    this.props = const [],
    this.orderable = true,
    this.defaultVisible = true,
    this.repeatable = false,
  });

  /// `data-hs-section="key"` en el HTML ('' para las que no son una sección).
  final String key;

  /// Cómo se llama en el panel.
  final String label;

  /// Una línea explicando qué se puede cambiar aquí.
  final String description;
  final IconData icon;

  /// Opciones propias (estadísticas, galería, testimonios…).
  final List<SitePropField> props;

  /// ¿Se puede ocultar y reordenar? (la marca y el pie van siempre).
  final bool orderable;
  final bool defaultVisible;

  /// ¿Se puede AGREGAR OTRA COPIA de esta sección a la página?
  ///
  /// El panel ofrece "Agregar sección" con estas plantillas: la nueva copia se
  /// pinta con lo que tenga la sección original y después se edita aparte (una
  /// segunda galería, otro divisor de fotos…). Las que se pintan con los datos
  /// del catálogo (paquetes, lo que ofrecemos) no se repiten: repetirlas sería
  /// mostrar dos veces la misma lista.
  final bool repeatable;
}

/// Las secciones del sitio, en el orden de fábrica.
///
/// El orden de esta lista es el del HTML; las que se pueden mover guardan su
/// posición con `order` en el documento de la portada.
const List<SiteSectionTemplate> kSiteSectionTemplates = [
  SiteSectionTemplate(
    key: 'hero',
    label: 'Portada',
    description: 'La primera pantalla: la imagen de fondo, el titular y el '
        'botón que lleva a la galería.',
    icon: Icons.wallpaper_rounded,
  ),
  SiteSectionTemplate(
    key: 'about',
    label: 'Sobre nosotros',
    description: 'Quién está detrás: la foto, la historia y los números '
        '(proyectos, años de experiencia, clientes).',
    icon: Icons.badge_outlined,
    repeatable: true,
    props: [
      SitePropField(
        key: 'stats',
        label: 'Números',
        kind: SitePropKind.stats,
        hint: 'Se cuentan solos al entrar a la sección.',
      ),
    ],
  ),
  SiteSectionTemplate(
    key: 'gallery',
    label: 'Galería destacada',
    description: 'Las fotos que se muestran, por categoría del catálogo. Cada '
        'categoría puede tener sus propias fotos (del Drive o por URL).',
    icon: Icons.photo_library_outlined,
    repeatable: true,
    props: [
      SitePropField(
        key: 'mode',
        label: 'Origen de las fotos',
        kind: SitePropKind.gallery,
        hint: 'Públicas = las que ya están marcadas como públicas en el Drive.',
      ),
    ],
  ),
  SiteSectionTemplate(
    key: 'parallax',
    label: 'Divisor de fotos',
    description: 'La franja con fondo fijo y una frase en cursiva entre la '
        'galería y los servicios.',
    icon: Icons.landscape_outlined,
    repeatable: true,
  ),
  SiteSectionTemplate(
    key: 'services',
    label: 'Lo que ofrecemos',
    description: 'El carrusel de SERVICIOS EXTERNOS (paquetes marcados como '
        'externos). Se editan en el módulo Paquetes.',
    icon: Icons.auto_awesome_outlined,
    props: [
      SitePropField(
        key: 'servicesPerSlide',
        label: 'Servicios por slide',
        kind: SitePropKind.number,
        hint: 'Cuántas características se listan en cada servicio.',
        min: 2,
        max: 8,
      ),
    ],
  ),
  SiteSectionTemplate(
    key: 'packages',
    label: 'Paquetes',
    description: 'Los paquetes del catálogo (los que NO son externos), con '
        'sus filtros por categoría y el diseño de las tarjetas.',
    icon: Icons.grid_view_rounded,
    props: [
      SitePropField(
        key: 'groupByCategory',
        label: 'Agrupar por categoría',
        kind: SitePropKind.toggle,
        hint: 'Cada categoría con su título, en vez de una sola cuadrícula.',
      ),
    ],
  ),
  SiteSectionTemplate(
    key: 'testimonials',
    label: 'Testimonios',
    description: 'Lo que dicen los clientes: los comentarios se escriben aquí '
        'y se muestran en el carrusel de la página.',
    icon: Icons.format_quote_rounded,
    repeatable: true,
    props: [
      SitePropField(
        key: 'items',
        label: 'Comentarios',
        kind: SitePropKind.testimonials,
      ),
    ],
  ),
  SiteSectionTemplate(
    key: 'custom',
    label: 'Sección libre',
    description: 'Un bloque NUEVO para la página: escribe su HTML y se muestra '
        'con el diseño del sitio (títulos, botones, rejillas…). Se puede '
        'agregar varias veces.',
    icon: Icons.code_rounded,
    // No existe en el HTML de fábrica: es una plantilla oculta que se clona
    // al agregarla (por eso no se puede ocultar ni reordenar por sí sola).
    orderable: false,
    defaultVisible: false,
    repeatable: true,
  ),
  SiteSectionTemplate(
    key: 'contact',
    label: 'Contacto',
    description: 'Los datos de contacto de la página (correo, teléfono, '
        'ubicación y WhatsApp) y el formulario.',
    icon: Icons.contact_mail_outlined,
    props: [
      SitePropField(
        key: 'whatsapp',
        label: 'WhatsApp',
        kind: SitePropKind.text,
        hint: 'Sólo dígitos con código de país (5219991234567). Si se deja '
            'vacío, no se muestra.',
      ),
    ],
  ),
  SiteSectionTemplate(
    key: 'footer',
    label: 'Pie de página',
    description: 'El logo, la presentación y el copyright del final.',
    icon: Icons.horizontal_rule_rounded,
    orderable: false,
  ),
  SiteSectionTemplate(
    key: 'brand',
    label: 'Marca',
    description: 'Los logos que se usan en la barra de navegación y en el pie.',
    icon: Icons.branding_watermark_outlined,
    orderable: false,
  ),
];

/// Valores de fábrica de las opciones de cada sección.
///
/// ESPEJO de `SITE_SECTIONS_DEFAULT` en `Hardstreet/gallery/assets/site.js`:
/// la prueba `site_sections_test.dart` falla si los dos se separan.
const Map<String, Map<String, dynamic>> kSiteSectionDefaults = {
  'hero': <String, dynamic>{},
  'about': <String, dynamic>{
    'stats': <Map<String, dynamic>>[
      {'value': 30, 'label': 'Proyectos'},
      {'value': 4, 'label': 'Años Exp.'},
      {'value': 50, 'label': 'Clientes Felices'},
    ],
  },
  // 'public' = las fotos públicas que ya trae la API; 'custom' = las elegidas
  // aquí por categoría. Sin categorías configuradas, se usan las públicas.
  'gallery': <String, dynamic>{
    'mode': 'public',
    'categories': <Map<String, dynamic>>[],
  },
  'parallax': <String, dynamic>{},
  'services': <String, dynamic>{'servicesPerSlide': 4},
  'packages': <String, dynamic>{'groupByCategory': true},
  // Vacío = los testimonios que ya trae el HTML (así el sitio nunca se queda
  // sin la sección por no haber escrito nada todavía).
  'testimonials': <String, dynamic>{'items': <Map<String, dynamic>>[]},
  'custom': <String, dynamic>{},
  'contact': <String, dynamic>{'whatsapp': ''},
  'footer': <String, dynamic>{},
  'brand': <String, dynamic>{},
};

/// Clave CSS de una categoría ("XV Años" → "xv-anos").
///
/// ESPEJO de `hsCategoryKey` en la web: la categoría elegida en el panel tiene
/// que coincidir con el `data-category` de las tarjetas de la página.
String siteCategoryKey(String name) => name
    .trim()
    .toLowerCase()
    // Sin acentos (á → a): es lo que hace la web con normalize('NFD').
    .replaceAll(RegExp('[áàäâã]'), 'a')
    .replaceAll(RegExp('[éèëê]'), 'e')
    .replaceAll(RegExp('[íìïî]'), 'i')
    .replaceAll(RegExp('[óòöôõ]'), 'o')
    .replaceAll(RegExp('[úùüû]'), 'u')
    .replaceAll(RegExp('[ñ]'), 'n')
    .replaceAll(RegExp('[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

/// Plantilla de una sección (null si no existe).
SiteSectionTemplate? siteSectionTemplate(String key) {
  for (final t in kSiteSectionTemplates) {
    if (t.key == key) return t;
  }
  return null;
}

/// Las plantillas que se pueden ocultar y reordenar.
List<SiteSectionTemplate> get kOrderableSectionTemplates =>
    kSiteSectionTemplates.where((t) => t.orderable).toList(growable: false);

/// Las plantillas que se pueden AGREGAR otra vez a la página ("Agregar
/// sección"): una segunda galería, otro divisor de fotos, más testimonios…
List<SiteSectionTemplate> get kRepeatableSectionTemplates =>
    kSiteSectionTemplates.where((t) => t.repeatable).toList(growable: false);

/// Clave de una sección AGREGADA. La primera copia de la galería es
/// `gallery-2` (la `gallery` a secas es la de fábrica), y así en adelante.
///
/// Es el identificador que viaja en el documento (`id`) y el que la web pone
/// en `data-hs-section`: por eso tiene que ser único en TODA la página.
String siteExtraSectionId(String key, Iterable<String> used) {
  final taken = used.toSet();
  for (var n = 2;; n++) {
    final id = '$key-$n';
    if (!taken.contains(id)) return id;
  }
}

/// ¿Es [id] una sección AGREGADA de [key]? (`gallery-2` de `gallery`).
bool siteIdIsExtra(String id, String key) => id != key && id.startsWith('$key-');

/// Opciones de fábrica de una sección.
Map<String, dynamic> siteSectionDefaults(String key) =>
    kSiteSectionDefaults[key] ?? const <String, dynamic>{};

/// Mezcla lo guardado sobre los valores de fábrica (sin perder claves).
///
/// Es la MISMA mezcla que hace la web (`hsSectionProps` en site.js): lo que no
/// venga en el documento se queda con su valor de fábrica, así una sección
/// nueva (o incompleta) nunca deja la página rara.
Map<String, dynamic> siteSectionProps(String key, Map<String, dynamic>? stored) {
  final base = siteSectionDefaults(key);
  final out = <String, dynamic>{...base};
  for (final e in (stored ?? const <String, dynamic>{}).entries) {
    final v = e.value;
    if (v == null) continue;
    if (v is String && v.trim().isEmpty) {
      out[e.key] = v;
      continue;
    }
    if (v is List && v.isEmpty) {
      out[e.key] = v;
      continue;
    }
    out[e.key] = v;
  }
  return out;
}

/// ¿Son las opciones de fábrica? (para no guardar lo que no se tocó).
bool sitePropsAreDefault(String key, Map<String, dynamic> props) =>
    _json(props) == _json(siteSectionDefaults(key));

String _json(Object? v) => const JsonEncoder().convert(v);

/// Cuántas opciones EDITADAS tiene una sección (para la píldora de la tarjeta).
int sitePropsChanged(String key, Map<String, dynamic> props) {
  final base = siteSectionDefaults(key);
  var n = 0;
  for (final e in props.entries) {
    if (_json(e.value) != _json(base[e.key])) n++;
  }
  return n;
}

/// Estadísticas de "Sobre nosotros" (valor + etiqueta), listas para pintar.
List<({int value, String label})> siteStats(Map<String, dynamic> props) {
  final raw = props['stats'];
  if (raw is! List) return const [];
  final out = <({int value, String label})>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final value = (e['value'] as num?)?.toInt();
    final label = '${e['label'] ?? ''}'.trim();
    if (value == null || label.isEmpty) continue;
    out.add((value: value, label: label));
  }
  return out;
}

/// Categorías con sus fotos elegidas (galería).
List<({String key, String name, List<String> items})> siteGalleryCategories(
    Map<String, dynamic> props) {
  final raw = props['categories'];
  if (raw is! List) return const [];
  final out = <({String key, String name, List<String> items})>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final key = '${e['key'] ?? ''}'.trim();
    if (key.isEmpty) continue;
    final items = ((e['items'] as List?) ?? const [])
        .map((v) => '$v'.trim())
        .where((v) => v.isNotEmpty)
        .toList(growable: false);
    out.add((key: key, name: '${e['name'] ?? key}'.trim(), items: items));
  }
  return out;
}

/// Comentarios de clientes (testimonios).
List<({String name, String role, String text})> siteTestimonials(
    Map<String, dynamic> props) {
  final raw = props['items'];
  if (raw is! List) return const [];
  final out = <({String name, String role, String text})>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final text = '${e['text'] ?? ''}'.trim();
    final name = '${e['name'] ?? ''}'.trim();
    if (text.isEmpty && name.isEmpty) continue;
    out.add((name: name, role: '${e['role'] ?? ''}'.trim(), text: text));
  }
  return out;
}

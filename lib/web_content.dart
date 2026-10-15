import 'dart:convert';

// ==================================================================
// HARD STREET — CONTENIDO DE LA PÁGINA WEB (portada)
// ==================================================================
// El módulo "Sitio web" (solo Windows) edita los TEXTOS, las IMÁGENES y las
// SECCIONES de la portada. Cada campo de este catálogo corresponde a un gancho
// del HTML (`Hardstreet/index.html`):
//
//   data-hs="clave"          → texto
//   data-hs-img="clave"      → imagen (src del <img> o fondo del div)
//   data-hs-section="clave"  → sección (mostrar/ocultar y orden)
//
// Los valores `def` de aquí son EXACTAMENTE los que trae el HTML: el panel los
// muestra como "valor de fábrica" y una prueba compara catálogo y HTML para que
// ningún gancho quede sin editor (ni al revés).
//
// Sólo se guardan los campos CAMBIADOS: lo que no se toque sigue viniendo del
// HTML, así el sitio puede seguir mejorando su copy sin que el panel lo pise.
// Lo guardado lo aplica la web en vivo (`gallery/assets/site.js`).
// ==================================================================

/// Un texto editable de la portada.
class SiteTextField {
  const SiteTextField({
    required this.key,
    required this.label,
    required this.def,
    required this.group,
    this.lines = false,
    this.multiline = false,
    this.hint,
  });

  /// `data-hs="key"` en el HTML.
  final String key;

  /// Cómo se llama en el panel.
  final String label;

  /// Lo que dice hoy el HTML (valor de fábrica).
  final String def;

  /// Grupo del editor (Hero, Sobre nosotros…).
  final String group;

  /// Admite dos líneas separadas por `|`: la segunda va con énfasis (el dorado
  /// del titular o la cursiva del divisor).
  final bool lines;

  /// Texto largo (párrafos): el campo crece en vez de quedarse en una línea.
  final bool multiline;

  /// Ayuda corta bajo el campo.
  final String? hint;

  /// Sección (plantilla) a la que pertenece, según su grupo.
  String get sectionKey => kSiteGroupSections[group] ?? 'hero';
}

/// Grupo del editor ("Portada", "Sobre nosotros"…) → clave de su SECCIÓN.
///
/// El módulo del sitio trabaja por secciones (una tarjeta con su miniatura por
/// bloque de la página); este mapa es lo que une el catálogo de ganchos del
/// HTML con las plantillas de `web_sections.dart`.
const Map<String, String> kSiteGroupSections = {
  'Marca': 'brand',
  'Portada': 'hero',
  'Sobre nosotros': 'about',
  'Galería': 'gallery',
  'Divisor de fotos': 'parallax',
  'Lo que ofrecemos': 'services',
  'Paquetes': 'packages',
  'Testimonios': 'testimonials',
  'Contacto': 'contact',
  'Pie de página': 'footer',
};

/// Una imagen editable (logo, foto de "Sobre nosotros", fondo del hero…).
class SiteImageField {
  const SiteImageField({
    required this.key,
    required this.label,
    required this.def,
    required this.group,
    this.background = false,
  });

  /// `data-hs-img="key"` en el HTML.
  final String key;
  final String label;

  /// Ruta de fábrica (la del HTML / la del CSS, si es un fondo).
  final String def;
  final String group;

  /// true si el gancho está en un fondo (hero, divisor) y no en un `<img>`.
  final bool background;

  /// Sección (plantilla) a la que pertenece, según su grupo.
  String get sectionKey => kSiteGroupSections[group] ?? 'hero';
}

/// Una sección de la portada (se puede ocultar y reordenar).
class SiteSectionField {
  const SiteSectionField({
    required this.key,
    required this.label,
    this.defaultVisible = true,
  });

  /// `data-hs-section="key"` en el HTML.
  final String key;
  final String label;
  final bool defaultVisible;
}

/// Estado elegido para una sección: visibilidad, orden y, además, sus PROPIAS
/// opciones (`props`): las estadísticas de "Sobre nosotros", las fotos que se
/// muestran en cada categoría de la galería, los testimonios, etc.
///
/// Las plantillas (qué campos tiene cada sección y con qué valores por defecto)
/// viven en `web_sections.dart`; aquí sólo viaja lo que el usuario cambió.
class SiteSectionState {
  const SiteSectionState({
    required this.visible,
    required this.order,
    this.props = const {},
  });

  final bool visible;
  final int order;

  /// Opciones propias de la sección (lo que NO es un texto ni una imagen).
  final Map<String, dynamic> props;

  SiteSectionState copyWith({
    bool? visible,
    int? order,
    Map<String, dynamic>? props,
  }) =>
      SiteSectionState(
        visible: visible ?? this.visible,
        order: order ?? this.order,
        props: props ?? this.props,
      );

  Map<String, dynamic> toJson() => {
        'visible': visible,
        'order': order,
        if (props.isNotEmpty) 'props': props,
      };

  @override
  bool operator ==(Object other) =>
      other is SiteSectionState &&
      other.visible == visible &&
      other.order == order &&
      _sameProps(props, other.props);

  @override
  int get hashCode => Object.hash(visible, order, jsonEncode(props));

  @override
  String toString() =>
      'SiteSectionState(visible: $visible, order: $order, props: $props)';

  static SiteSectionState fromJson(Object? raw, SiteSectionState fallback) {
    if (raw is! Map) return fallback;
    final m = raw.cast<String, dynamic>();
    return SiteSectionState(
      visible: m['visible'] is bool ? m['visible'] as bool : fallback.visible,
      order: (m['order'] as num?)?.toInt() ?? fallback.order,
      props: m['props'] is Map
          ? (m['props'] as Map).cast<String, dynamic>()
          : fallback.props,
    );
  }

  /// Dos `props` son iguales si su JSON lo es (los mapas de Dart comparan por
  /// identidad de claves, no por contenido).
  static bool _sameProps(Map<String, dynamic> a, Map<String, dynamic> b) =>
      jsonEncode(a) == jsonEncode(b);
}

/// Documento del contenido de la portada (lo que va y viene por la API).
class SiteContent {
  const SiteContent({
    this.texts = const {},
    this.images = const {},
    this.sections = const {},
  });

  /// Sólo los textos CAMBIADOS (clave → valor).
  final Map<String, String> texts;

  /// Sólo las imágenes CAMBIADAS.
  final Map<String, String> images;

  /// Todas las secciones: visibilidad y orden.
  final Map<String, SiteSectionState> sections;

  /// Un documento vacío: la portada se ve tal como la trae el HTML.
  static const SiteContent empty = SiteContent();

  bool get isEmpty => texts.isEmpty && images.isEmpty && sections.isEmpty;

  /// Cuántos campos se han cambiado (para las píldoras del encabezado).
  int get editedCount =>
      texts.length + images.length + sections.values.where((s) => !s.visible).length;

  /// ¿Es el MISMO contenido? (valor a valor: `==` de dos mapas de Dart compara
  /// la identidad de las claves, no lo que llevan dentro, así que no sirve para
  /// saber si lo editado ya está guardado).
  bool sameAs(SiteContent other) =>
      _sameMap(texts, other.texts) &&
      _sameMap(images, other.images) &&
      _sameMap(sections, other.sections);

  static bool _sameMap<V>(Map<String, V> a, Map<String, V> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (!b.containsKey(e.key) || b[e.key] != e.value) return false;
    }
    return true;
  }

  SiteContent copyWith({
    Map<String, String>? texts,
    Map<String, String>? images,
    Map<String, SiteSectionState>? sections,
  }) =>
      SiteContent(
        texts: texts ?? this.texts,
        images: images ?? this.images,
        sections: sections ?? this.sections,
      );

  /// Un texto editado (o null si sigue el de fábrica).
  String? textOf(String key) => texts[key];

  /// Una imagen editada (o null).
  String? imageOf(String key) => images[key];

  /// Opciones propias de una sección (vacío = las de fábrica de la web).
  Map<String, dynamic> propsOf(String key) =>
      sections[key]?.props ?? const <String, dynamic>{};

  /// Estado actual de una sección, con el de fábrica como respaldo.
  SiteSectionState sectionOf(String key, {int order = 0, bool visible = true}) =>
      sections[key] ?? SiteSectionState(visible: visible, order: order);

  Map<String, dynamic> toJson() => {
        if (texts.isNotEmpty) 'texts': texts,
        if (images.isNotEmpty) 'images': images,
        if (sections.isNotEmpty)
          'sections': {for (final e in sections.entries) e.key: e.value.toJson()},
      };

  /// Lee lo guardado (tolerante: lo que falte o venga raro se ignora).
  static SiteContent fromJson(Object? raw) {
    if (raw is! Map) return empty;
    final m = raw.cast<String, dynamic>();
    final texts = <String, String>{};
    for (final e in _map(m['texts']).entries) {
      final v = e.value?.toString().trim() ?? '';
      if (v.isNotEmpty) texts[e.key] = v;
    }
    final images = <String, String>{};
    for (final e in _map(m['images']).entries) {
      final v = e.value?.toString().trim() ?? '';
      if (v.isNotEmpty) images[e.key] = v;
    }
    final sections = <String, SiteSectionState>{};
    for (final entry in _map(m['sections']).entries) {
      final fallback = kSiteSections.any((s) => s.key == entry.key)
          ? SiteSectionState(
              visible: kSiteSections.firstWhere((s) => s.key == entry.key).defaultVisible,
              order: kSiteSections.indexWhere((s) => s.key == entry.key),
            )
          : const SiteSectionState(visible: true, order: 0);
      sections[entry.key] = SiteSectionState.fromJson(entry.value, fallback);
    }
    return SiteContent(texts: texts, images: images, sections: sections);
  }

  /// Igual que [fromJson] pero desde el texto que devuelve la API.
  static SiteContent fromJsonText(Object? text) {
    if (text == null) return empty;
    if (text is Map) return fromJson(text);
    try {
      return fromJson(jsonDecode(text.toString()));
    } catch (_) {
      return empty;
    }
  }

  static Map<String, dynamic> _map(Object? v) =>
      v is Map ? v.cast<String, dynamic>() : const {};
}

// ------------------------------------------------------------------
// Catálogo de campos (espejo de los ganchos del HTML)
// ------------------------------------------------------------------

/// Textos de la portada, agrupados por sección (el orden es el de la web).
const List<SiteTextField> kSiteTexts = [
  // --- Hero ---
  SiteTextField(
    key: 'hero_eyebrow',
    label: 'Nombre sobre el titular',
    def: 'Hard Street',
    group: 'Portada',
  ),
  SiteTextField(
    key: 'hero_title',
    label: 'Titular',
    def: 'Capturando|Momentos Únicos',
    group: 'Portada',
    lines: true,
    hint: 'Usa | para la segunda línea (la que va en dorado)',
  ),
  SiteTextField(
    key: 'hero_cta',
    label: 'Botón',
    def: 'Explorar Galería',
    group: 'Portada',
  ),
  SiteTextField(
    key: 'hero_scroll',
    label: 'Indicador de scroll',
    def: 'Scroll',
    group: 'Portada',
  ),

  // --- Sobre nosotros ---
  SiteTextField(
    key: 'about_label',
    label: 'Etiqueta',
    def: 'Sobre Nosotros',
    group: 'Sobre nosotros',
  ),
  SiteTextField(
    key: 'about_title',
    label: 'Título',
    def: 'La historia detrás|de cada imagen',
    group: 'Sobre nosotros',
    lines: true,
  ),
  SiteTextField(
    key: 'about_text_1',
    label: 'Primer párrafo',
    def: 'Hard Street es un estudio de fotografía y vídeo especializado en eventos '
        'sociales: bodas, quinceañeros, bautizos, graduaciones y más. También '
        'ofrecemos servicios de medios visuales como flyers, publicidad para '
        'negocios y fotografía de producto.',
    group: 'Sobre nosotros',
    multiline: true,
  ),
  SiteTextField(
    key: 'about_text_2',
    label: 'Segundo párrafo',
    def: 'Nuestro enfoque combina una estética cuidada con sensibilidad única para '
        'la luz y la composición, creando imágenes que trascienden lo ordinario y '
        'conectan emocionalmente con quien las observa.',
    group: 'Sobre nosotros',
    multiline: true,
  ),

  // --- Galería ---
  SiteTextField(
    key: 'gallery_label',
    label: 'Etiqueta',
    def: 'Portafolio',
    group: 'Galería',
  ),
  SiteTextField(
    key: 'gallery_title',
    label: 'Título',
    def: 'Galería Destacada',
    group: 'Galería',
  ),

  // --- Divisor ---
  SiteTextField(
    key: 'parallax_text',
    label: 'Frase del divisor',
    def: 'Cada imagen, una|historia',
    group: 'Divisor de fotos',
    lines: true,
    hint: 'La segunda parte va en cursiva',
  ),

  // --- Servicios ---
  SiteTextField(
    key: 'services_label',
    label: 'Etiqueta',
    def: 'Nuestros Servicios',
    group: 'Lo que ofrecemos',
  ),
  SiteTextField(
    key: 'services_title',
    label: 'Título',
    def: 'Lo que Ofrecemos',
    group: 'Lo que ofrecemos',
  ),

  // --- Paquetes ---
  SiteTextField(
    key: 'packages_label',
    label: 'Etiqueta',
    def: 'Paquetes',
    group: 'Paquetes',
  ),
  SiteTextField(
    key: 'packages_title',
    label: 'Título',
    def: 'Nuestros Paquetes',
    group: 'Paquetes',
  ),
  SiteTextField(
    key: 'packages_desc',
    label: 'Descripción',
    def: 'Elige el paquete perfecto para tu evento. Todos incluyen nuestra '
        'garantía de calidad Hard Street.',
    group: 'Paquetes',
    multiline: true,
  ),

  // --- Testimonios ---
  SiteTextField(
    key: 'testimonials_label',
    label: 'Etiqueta',
    def: 'Testimonios',
    group: 'Testimonios',
  ),
  SiteTextField(
    key: 'testimonials_title',
    label: 'Título',
    def: 'Lo que Dicen Mis Clientes',
    group: 'Testimonios',
  ),
  SiteTextField(
    key: 'testimonials_subtitle',
    label: 'Subtítulo',
    def: 'Lo que dicen mis clientes',
    group: 'Testimonios',
  ),

  // --- Contacto ---
  SiteTextField(
    key: 'contact_label',
    label: 'Etiqueta',
    def: 'Contacto',
    group: 'Contacto',
  ),
  SiteTextField(
    key: 'contact_title',
    label: 'Título',
    def: 'Trabajemos Juntos',
    group: 'Contacto',
  ),
  SiteTextField(
    key: 'contact_text',
    label: 'Texto',
    def: 'Tienes un evento en mente? Contáctanos y hagamos que tus momentos '
        'cobren vida con Hard Street.',
    group: 'Contacto',
    multiline: true,
  ),
  SiteTextField(
    key: 'contact_email',
    label: 'Correo',
    def: 'hardstreet7@gmail.com',
    group: 'Contacto',
  ),
  SiteTextField(
    key: 'contact_phone',
    label: 'Teléfono',
    def: '+52 990 101 7986',
    group: 'Contacto',
  ),
  SiteTextField(
    key: 'contact_address',
    label: 'Ubicación',
    def: 'Mérida, Yuc. Temozón',
    group: 'Contacto',
  ),
  SiteTextField(
    key: 'contact_cta',
    label: 'Botón del formulario',
    def: 'Enviar Mensaje',
    group: 'Contacto',
  ),

  // --- Pie ---
  SiteTextField(
    key: 'footer_about',
    label: 'Presentación',
    def: 'Hard Street Estudio - Capturando momentos únicos con pasión y arte. '
        'Cada fotografía es una ventana a una historia que merece ser contada.',
    group: 'Pie de página',
    multiline: true,
  ),
  SiteTextField(
    key: 'footer_copyright',
    label: 'Copyright',
    def: '© 2026 Hard Street Estudio. Todos los derechos reservados.',
    group: 'Pie de página',
  ),
];

/// Imágenes de la portada.
const List<SiteImageField> kSiteImages = [
  SiteImageField(
    key: 'logo',
    label: 'Logo de la barra',
    def: './images/LOG-SB.png',
    group: 'Marca',
  ),
  SiteImageField(
    key: 'footer_logo',
    label: 'Logo del pie',
    def: 'images/LOG.png',
    group: 'Marca',
  ),
  SiteImageField(
    key: 'hero_image',
    label: 'Fondo de la portada',
    def: './images/banner.jpg',
    group: 'Portada',
    background: true,
  ),
  SiteImageField(
    key: 'about_image',
    label: 'Foto de "Sobre nosotros"',
    def: './images/review.jpg',
    group: 'Sobre nosotros',
  ),
  SiteImageField(
    key: 'parallax_image',
    label: 'Fondo del divisor',
    def: 'images/banner1.jpg',
    group: 'Divisor de fotos',
    background: true,
  ),
];

/// Secciones de la portada, en el orden de fábrica.
const List<SiteSectionField> kSiteSections = [
  SiteSectionField(key: 'hero', label: 'Portada'),
  SiteSectionField(key: 'about', label: 'Sobre nosotros'),
  SiteSectionField(key: 'gallery', label: 'Galería'),
  SiteSectionField(key: 'parallax', label: 'Divisor de fotos'),
  SiteSectionField(key: 'services', label: 'Lo que ofrecemos'),
  SiteSectionField(key: 'packages', label: 'Paquetes'),
  SiteSectionField(key: 'testimonials', label: 'Testimonios'),
  SiteSectionField(key: 'contact', label: 'Contacto'),
];

/// Grupos del editor en el orden en que se muestran.
List<String> get kSiteTextGroups {
  final out = <String>[];
  for (final f in kSiteTexts) {
    if (!out.contains(f.group)) out.add(f.group);
  }
  return out;
}

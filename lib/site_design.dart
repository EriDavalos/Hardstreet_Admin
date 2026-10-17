import 'dart:convert';

// ==================================================================
// HARD STREET ADMIN — DISEÑO DEL SITIO (tarjetas de paquetes y portada)
// ==================================================================
// El panel DISEÑA y el sitio lo LEE en vivo (GET /api/site): este archivo
// mantiene el documento de diseño tal como lo aplica la web
// (`Hardstreet/gallery/assets/site.js`, función `siteDesignCss`).
//
// Los DEFAULTS de aquí son EXACTAMENTE los de `site.js` (una prueba compara los
// dos archivos): así el diseñador del panel arranca mostrando lo que el sitio
// ya tiene, y lo que se ve en el panel es lo que se ve en la web.
// ==================================================================

/// Un tier con su paleta (Premium / Gold / Basic).
class SiteTierDesign {
  const SiteTierDesign({
    required this.accent,
    required this.accentSoft,
    required this.dark,
    this.badgeFilled = false,
    this.borderAlpha = .3,
  });

  /// Acento principal: borde, precio, badges y barra.
  final String accent;

  /// Acento claro: degradados del badge y texto sobre el borde dorado.
  final String accentSoft;

  /// Fondo de la tarjeta.
  final String dark;

  /// ¿El badge del tier va RELLENO (degradado) o solo delineado?
  final bool badgeFilled;

  /// Opacidad del borde (0..1) con el acento.
  final double borderAlpha;

  SiteTierDesign copyWith({
    String? accent,
    String? accentSoft,
    String? dark,
    bool? badgeFilled,
    double? borderAlpha,
  }) => SiteTierDesign(
    accent: accent ?? this.accent,
    accentSoft: accentSoft ?? this.accentSoft,
    dark: dark ?? this.dark,
    badgeFilled: badgeFilled ?? this.badgeFilled,
    borderAlpha: borderAlpha ?? this.borderAlpha,
  );

  Map<String, dynamic> toJson() => {
    'accent': accent,
    'accentSoft': accentSoft,
    'dark': dark,
    'badgeFilled': badgeFilled,
    'borderAlpha': borderAlpha,
  };

  static SiteTierDesign fromJson(
    Map<String, dynamic> j,
    SiteTierDesign fallback,
  ) => fallback.copyWith(
    accent: _hex(j['accent']) ?? fallback.accent,
    accentSoft: _hex(j['accentSoft']) ?? fallback.accentSoft,
    dark: _hex(j['dark']) ?? fallback.dark,
    badgeFilled: j['badgeFilled'] is bool
        ? j['badgeFilled'] as bool
        : fallback.badgeFilled,
    borderAlpha: (j['borderAlpha'] as num?)?.toDouble() ?? fallback.borderAlpha,
  );
}

/// Diseño de las TARJETAS de paquete (lo que edita el diseñador).
class SiteCardDesign {
  const SiteCardDesign({
    this.columns = 3,
    this.gap = 40,
    this.radius = 18,
    this.borderWidth = 1,
    this.padding = 32,
    this.lineTop = true,
    this.hoverLift = true,
    this.shadow = true,
    this.serifNames = true,
    this.uppercaseNames = false,
    this.showCategory = true,
    this.showSubtitle = true,
    this.showServiceCount = true,
    this.showServices = true,
    this.servicesLimit = 6,
    this.showPrice = true,
    this.showCta = true,
    this.priceLabel = 'Desde',
    this.ctaLabel = 'Cotizar',
    this.imageMode = 'none',
    this.imageHeight = 150,
    this.imageFade = .7,
    this.animMode = 'up',
    this.animMs = 600,
    this.animStagger = 100,
  });

  /// Columnas del catálogo en la web (1..4).
  final int columns;

  /// Separación entre tarjetas, en px.
  final double gap;

  /// Redondeo de la tarjeta, en px.
  final double radius;

  /// Grosor del borde (0 = sin borde).
  final double borderWidth;

  /// Relleno interior del flyer, en px.
  final double padding;

  /// ¿La línea superior degradada del flyer?
  final bool lineTop;

  /// ¿La tarjeta se eleva al pasar el mouse?
  final bool hoverLift;

  /// ¿Sombra al pasar el mouse?
  final bool shadow;

  /// Nombre en serif (Playfair) o en la tipografía de texto (Inter).
  final bool serifNames;

  /// Nombre en MAYÚSCULAS.
  final bool uppercaseNames;

  final bool showCategory;
  final bool showSubtitle;
  final bool showServiceCount;
  final bool showServices;

  /// Cuántos servicios se listan antes de resumir en "+N más…" (0 = todos).
  final int servicesLimit;

  final bool showPrice;
  final bool showCta;

  /// Rótulo del precio ("Desde", "Inversión"…).
  final String priceLabel;

  /// Texto del botón ("Cotizar", "Solicitar"…).
  final String ctaLabel;

  /// FOTO del paquete dentro de la tarjeta:
  /// `none` sin foto · `top` banda arriba · `bg` de fondo (la foto se ve y
  /// encima lleva el degradado del color de la tarjeta).
  final String imageMode;

  /// Alto de la banda de la foto (`top`), en px.
  final double imageHeight;

  /// Fuerza del degradado que oscurece la foto de fondo (`bg`, 0..1): 0 deja
  /// la foto limpia y 1 la tapa casi del todo para que el texto se lea.
  final double imageFade;

  /// Entrada de las tarjetas del catálogo:
  /// `up` subir · `fade` aparecer · `zoom` acercar · `none` sin animación.
  final String animMode;

  /// Duración de esa entrada, en ms.
  final int animMs;

  /// Retardo entre tarjeta y tarjeta (el efecto escalonado), en ms.
  final int animStagger;

  SiteCardDesign copyWith({
    int? columns,
    double? gap,
    double? radius,
    double? borderWidth,
    double? padding,
    bool? lineTop,
    bool? hoverLift,
    bool? shadow,
    bool? serifNames,
    bool? uppercaseNames,
    bool? showCategory,
    bool? showSubtitle,
    bool? showServiceCount,
    bool? showServices,
    int? servicesLimit,
    bool? showPrice,
    bool? showCta,
    String? priceLabel,
    String? ctaLabel,
    String? imageMode,
    double? imageHeight,
    double? imageFade,
    String? animMode,
    int? animMs,
    int? animStagger,
  }) => SiteCardDesign(
    columns: columns ?? this.columns,
    gap: gap ?? this.gap,
    radius: radius ?? this.radius,
    borderWidth: borderWidth ?? this.borderWidth,
    padding: padding ?? this.padding,
    lineTop: lineTop ?? this.lineTop,
    hoverLift: hoverLift ?? this.hoverLift,
    shadow: shadow ?? this.shadow,
    serifNames: serifNames ?? this.serifNames,
    uppercaseNames: uppercaseNames ?? this.uppercaseNames,
    showCategory: showCategory ?? this.showCategory,
    showSubtitle: showSubtitle ?? this.showSubtitle,
    showServiceCount: showServiceCount ?? this.showServiceCount,
    showServices: showServices ?? this.showServices,
    servicesLimit: servicesLimit ?? this.servicesLimit,
    showPrice: showPrice ?? this.showPrice,
    showCta: showCta ?? this.showCta,
    priceLabel: priceLabel ?? this.priceLabel,
    ctaLabel: ctaLabel ?? this.ctaLabel,
    imageMode: imageMode ?? this.imageMode,
    imageHeight: imageHeight ?? this.imageHeight,
    imageFade: imageFade ?? this.imageFade,
    animMode: animMode ?? this.animMode,
    animMs: animMs ?? this.animMs,
    animStagger: animStagger ?? this.animStagger,
  );

  Map<String, dynamic> toJson() => {
    'columns': columns,
    'gap': gap,
    'radius': radius,
    'borderWidth': borderWidth,
    'padding': padding,
    'lineTop': lineTop,
    'hoverLift': hoverLift,
    'shadow': shadow,
    'serifNames': serifNames,
    'uppercaseNames': uppercaseNames,
    'showCategory': showCategory,
    'showSubtitle': showSubtitle,
    'showServiceCount': showServiceCount,
    'showServices': showServices,
    'servicesLimit': servicesLimit,
    'showPrice': showPrice,
    'showCta': showCta,
    'priceLabel': priceLabel,
    'ctaLabel': ctaLabel,
    'imageMode': imageMode,
    'imageHeight': imageHeight,
    'imageFade': imageFade,
    'animMode': animMode,
    'animMs': animMs,
    'animStagger': animStagger,
  };

  static SiteCardDesign fromJson(Map<String, dynamic> j, SiteCardDesign f) =>
      f.copyWith(
        columns: _int(j['columns'], f.columns),
        gap: _num(j['gap'], f.gap),
        radius: _num(j['radius'], f.radius),
        borderWidth: _num(j['borderWidth'], f.borderWidth),
        padding: _num(j['padding'], f.padding),
        lineTop: _bool(j['lineTop'], f.lineTop),
        hoverLift: _bool(j['hoverLift'], f.hoverLift),
        shadow: _bool(j['shadow'], f.shadow),
        serifNames: _bool(j['serifNames'], f.serifNames),
        uppercaseNames: _bool(j['uppercaseNames'], f.uppercaseNames),
        showCategory: _bool(j['showCategory'], f.showCategory),
        showSubtitle: _bool(j['showSubtitle'], f.showSubtitle),
        showServiceCount: _bool(j['showServiceCount'], f.showServiceCount),
        showServices: _bool(j['showServices'], f.showServices),
        servicesLimit: _int(j['servicesLimit'], f.servicesLimit),
        showPrice: _bool(j['showPrice'], f.showPrice),
        showCta: _bool(j['showCta'], f.showCta),
        priceLabel: _text(j['priceLabel'], f.priceLabel),
        ctaLabel: _text(j['ctaLabel'], f.ctaLabel),
        imageMode: _choice(j['imageMode'], kDesignImageModes, f.imageMode),
        imageHeight: _num(j['imageHeight'], f.imageHeight),
        imageFade: _num(j['imageFade'], f.imageFade),
        animMode: _choice(j['animMode'], kDesignAnimModes, f.animMode),
        animMs: _int(j['animMs'], f.animMs),
        animStagger: _int(j['animStagger'], f.animStagger),
      );
}

/// Documento completo de diseño del sitio.
class SiteDesign {
  const SiteDesign({
    this.gold = '#C9A96E',
    this.goldLight = '#F0D48A',
    this.card = const SiteCardDesign(),
    this.tiers = const {
      'premium': SiteTierDesign(
        accent: '#C9A96E',
        accentSoft: '#F0D48A',
        dark: '#0B0E17',
        badgeFilled: true,
        borderAlpha: .55,
      ),
      'gold': SiteTierDesign(
        accent: '#D9A441',
        accentSoft: '#F2C66B',
        dark: '#120E05',
        badgeFilled: true,
        borderAlpha: .3,
      ),
      'basic': SiteTierDesign(
        accent: '#8FB0D4',
        accentSoft: '#B9D0E6',
        dark: '#0B111A',
        badgeFilled: false,
        borderAlpha: .22,
      ),
    },
  });

  /// Dorados de la marca (variables --gold / --gold-light del sitio).
  final String gold;
  final String goldLight;

  final SiteCardDesign card;

  /// Paleta por tier, con las claves en minúsculas: premium / gold / basic.
  final Map<String, SiteTierDesign> tiers;

  /// El diseño que trae la web de fábrica (el look actual del sitio).
  static const SiteDesign defaults = SiteDesign();

  /// Paleta de un tier por su nombre ("Premium" → premium), con respaldo.
  SiteTierDesign tierOf(String name) {
    final key = name.trim().toLowerCase();
    return tiers[key] ?? tiers['basic'] ?? defaults.tiers['basic']!;
  }

  SiteDesign copyWith({
    String? gold,
    String? goldLight,
    SiteCardDesign? card,
    Map<String, SiteTierDesign>? tiers,
  }) => SiteDesign(
    gold: gold ?? this.gold,
    goldLight: goldLight ?? this.goldLight,
    card: card ?? this.card,
    tiers: tiers ?? this.tiers,
  );

  /// Cambia la paleta de UN tier (devuelve un diseño nuevo).
  SiteDesign withTier(String key, SiteTierDesign value) =>
      copyWith(tiers: {...tiers, key.trim().toLowerCase(): value});

  Map<String, dynamic> toJson() => {
    'brand': {'gold': gold, 'goldLight': goldLight},
    'card': card.toJson(),
    'tiers': {for (final e in tiers.entries) e.key: e.value.toJson()},
  };

  /// Diseño a partir de lo que devuelve la API (tolerante: lo que falte, se
  /// queda con el default; así un documento a medias nunca deja la web rara).
  static SiteDesign fromJson(Object? raw) {
    if (raw is! Map) return defaults;
    final j = raw.cast<String, dynamic>();
    final brand = (j['brand'] as Map?)?.cast<String, dynamic>() ?? const {};
    final cardJson = (j['card'] as Map?)?.cast<String, dynamic>() ?? const {};
    final tiersJson = (j['tiers'] as Map?) ?? const {};
    final tiers = <String, SiteTierDesign>{};
    for (final e in defaults.tiers.entries) {
      final stored = (tiersJson[e.key] as Map?)?.cast<String, dynamic>();
      tiers[e.key] = stored == null
          ? e.value
          : SiteTierDesign.fromJson(stored, e.value);
    }
    return defaults.copyWith(
      gold: _hex(brand['gold']) ?? defaults.gold,
      goldLight: _hex(brand['goldLight']) ?? defaults.goldLight,
      card: SiteCardDesign.fromJson(cardJson, defaults.card),
      tiers: tiers,
    );
  }

  /// Igual que [fromJson] pero a partir del texto guardado (null-safe).
  static SiteDesign fromJsonText(Object? text) {
    if (text == null) return defaults;
    if (text is Map) return fromJson(text);
    try {
      return fromJson(jsonDecode(text.toString()));
    } catch (_) {
      return defaults;
    }
  }
}

// ---- Ayudas de lectura tolerante ----

String? _hex(Object? v) {
  final s = (v ?? '').toString().trim();
  if (!RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').hasMatch(s)) return null;
  return s.toUpperCase();
}

int _int(Object? v, int fallback) =>
    v is num ? v.toInt() : int.tryParse('$v') ?? fallback;

double _num(Object? v, double fallback) =>
    v is num ? v.toDouble() : double.tryParse('$v') ?? fallback;

bool _bool(Object? v, bool fallback) => v is bool ? v : fallback;

/// Color del velo que oscurece la FOTO DE FONDO de una tarjeta (`bg`).
///
/// Es NEGRO en los dos lados —aquí y en la web (`site.js` → `HS_PHOTO_FADE`)—:
/// sobre la foto, un velo negro es lo que hace resaltar el texto.
const String kPhotoFadeColor = '#000000';

/// Valores permitidos de un campo de opciones (foto, animación).
const List<String> kDesignImageModes = ['none', 'top', 'bg'];
const List<String> kDesignAnimModes = ['up', 'fade', 'zoom', 'none'];

/// Una opción guardada: si no es una de las válidas, se queda con el default.
String _choice(Object? v, List<String> allowed, String fallback) {
  final s = (v ?? '').toString().trim();
  return allowed.contains(s) ? s : fallback;
}

String _text(Object? v, String fallback) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? fallback : s;
}

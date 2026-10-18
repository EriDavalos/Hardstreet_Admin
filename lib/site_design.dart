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
    this.imageFadeColor = kPhotoFadeColor,
    this.imageFadeFrom = 'bottom',
    this.imageFadeAngle = -1,
    this.imageFadeStart = .15,
    this.imageFadeEnd = .85,
    this.cardBgFrom = kCardBgFrom,
    this.cardBgTo = kCardBgTo,
    this.cardBgGradient = false,
    this.cardBgAngle = 135,
    this.imageShadow = .55,
    this.imageShadowStart = .08,
    this.imageShadowEnd = .72,
    this.imageShadowAngle = 0,
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
  /// encima lleva el degradado del color de la tarjeta) · `fade` fondo con
  /// DESVANECIDO (la foto se ve de un lado y se desvanece hacia el otro hasta
  /// fundirse con el fondo, que puede ser un color o un degradado).
  final String imageMode;

  /// Alto de la banda de la foto (`top`), en px.
  final double imageHeight;

  /// Fuerza del degradado que oscurece la foto de fondo (`bg`, 0..1): 0 deja
  /// la foto limpia y 1 la tapa casi del todo para que el texto se lea.
  final double imageFade;

  /// Color del velo que va encima de la foto de fondo (por defecto negro, que
  /// es el que mejor hace resaltar el texto; se puede cambiar desde el
  /// diseñador y se ve igual en el panel y en la web).
  final String imageFadeColor;

  /// De dónde viene el degradado: la dirección desde la que oscurece la foto
  /// (`bottom` por defecto —tapa más abajo, donde van el nombre y el precio—,
  /// `top`, `left`, `right` y las cuatro esquinas).
  final String imageFadeFrom;

  /// Ángulo LIBRE del velo en grados (0..359, estilos CSS): -1 = seguir la
  /// dirección de [imageFadeFrom]. El ángulo manda cuando se usa el ajuste
  /// fino del diseñador.
  final double imageFadeAngle;

  /// DÓNDE se ve la foto en el estilo `fade` (0..1, medido desde el lado
  /// contrario a [imageFadeFrom]): hasta aquí la foto está completa.
  final double imageFadeStart;

  /// Dónde la foto TERMINA de desaparecer en el estilo `fade` (0..1). A partir
  /// de aquí se ve sólo el fondo de la tarjeta.
  final double imageFadeEnd;

  /// Color de fondo de la tarjeta en el estilo `fade` (el primer color del
  /// degradado cuando [cardBgGradient] está encendido).
  final String cardBgFrom;

  /// Segundo color del fondo: con [cardBgGradient] encendido, el fondo es un
  /// degradado de [cardBgFrom] a [cardBgTo].
  final String cardBgTo;

  /// ¿El fondo de la tarjeta es un DEGRADADO (dos colores) o un color plano?
  final bool cardBgGradient;

  /// Ángulo del degradado del fondo en grados CSS (0 = hacia arriba, 90 = a la
  /// derecha).
  final double cardBgAngle;

  /// SOMBRA de la foto de fondo (0..1): la fuerza del degradado NEGRO que sube
  /// desde el borde inferior. Es una capa APARTE del velo (que puede ser de
  /// cualquier color) y se ajusta en dos puntos, como en Photoshop:
  /// [imageShadowStart] es dónde el negro deja de ser sólido y
  /// [imageShadowEnd] dónde se apaga del todo. 0 = sin sombra.
  final double imageShadow;

  /// Inicio del desvanecido de la sombra (0..1 de la tarjeta, desde abajo).
  final double imageShadowStart;

  /// Fin del desvanecido de la sombra (0..1 de la tarjeta, desde abajo).
  final double imageShadowEnd;

  /// DE DÓNDE viene la sombra, en grados CSS (0 = desde abajo, el de siempre;
  /// 90 = desde la izquierda; 180 = desde arriba; 270 = desde la derecha).
  /// Así la sombra se puede mover de posición para tapar el lado donde esté el
  /// texto. Es independiente de la dirección del velo.
  final double imageShadowAngle;

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
    String? imageFadeColor,
    String? imageFadeFrom,
    double? imageFadeAngle,
    double? imageFadeStart,
    double? imageFadeEnd,
    String? cardBgFrom,
    String? cardBgTo,
    bool? cardBgGradient,
    double? cardBgAngle,
    double? imageShadow,
    double? imageShadowStart,
    double? imageShadowEnd,
    double? imageShadowAngle,
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
    imageFadeColor: imageFadeColor ?? this.imageFadeColor,
    imageFadeFrom: imageFadeFrom ?? this.imageFadeFrom,
    imageFadeAngle: imageFadeAngle ?? this.imageFadeAngle,
    imageFadeStart: imageFadeStart ?? this.imageFadeStart,
    imageFadeEnd: imageFadeEnd ?? this.imageFadeEnd,
    cardBgFrom: cardBgFrom ?? this.cardBgFrom,
    cardBgTo: cardBgTo ?? this.cardBgTo,
    cardBgGradient: cardBgGradient ?? this.cardBgGradient,
    cardBgAngle: cardBgAngle ?? this.cardBgAngle,
    imageShadow: imageShadow ?? this.imageShadow,
    imageShadowStart: imageShadowStart ?? this.imageShadowStart,
    imageShadowEnd: imageShadowEnd ?? this.imageShadowEnd,
    imageShadowAngle: imageShadowAngle ?? this.imageShadowAngle,
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
    'imageFadeColor': imageFadeColor,
    'imageFadeFrom': imageFadeFrom,
    'imageFadeAngle': imageFadeAngle,
    'imageFadeStart': imageFadeStart,
    'imageFadeEnd': imageFadeEnd,
    'cardBgFrom': cardBgFrom,
    'cardBgTo': cardBgTo,
    'cardBgGradient': cardBgGradient,
    'cardBgAngle': cardBgAngle,
    'imageShadow': imageShadow,
    'imageShadowStart': imageShadowStart,
    'imageShadowEnd': imageShadowEnd,
    'imageShadowAngle': imageShadowAngle,
    'animMode': animMode,
    'animMs': animMs,
    'animStagger': animStagger,
  };

  static SiteCardDesign fromJson(Map<String, dynamic> j, SiteCardDesign f) {
    // La SOMBRA de la foto llegó después: un documento guardado antes trae la
    // fuerza (o nada) pero NO sus dos paradas. Ahí se estrena con los valores de
    // fábrica, para que el degradado negro se vea sin tener que reajustarlo.
    final hasShadow =
        j.containsKey('imageShadowStart') && j.containsKey('imageShadowEnd');
    // Las dos paradas del desvanecido de la foto (estilo `fade`) no pueden
    // quedar cruzadas: el fin siempre va al menos 5 puntos después del inicio.
    final fadeStart = _num(
      j['imageFadeStart'],
      f.imageFadeStart,
    ).clamp(0, .95).toDouble();
    return f.copyWith(
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
      imageFadeColor: _hex(j['imageFadeColor']) ?? f.imageFadeColor,
      imageFadeFrom: _choice(
        j['imageFadeFrom'],
        kDesignFadeFroms,
        f.imageFadeFrom,
      ),
      imageFadeAngle: _fadeAngle(j['imageFadeAngle'], f.imageFadeAngle),
      imageFadeStart: fadeStart,
      imageFadeEnd: _num(
        j['imageFadeEnd'],
        f.imageFadeEnd,
      ).clamp(fadeStart + .05, 1),
      cardBgFrom: _hex(j['cardBgFrom']) ?? f.cardBgFrom,
      cardBgTo: _hex(j['cardBgTo']) ?? f.cardBgTo,
      cardBgGradient: _bool(j['cardBgGradient'], f.cardBgGradient),
      // El ángulo del FONDO no usa -1 (eso es "sin ángulo libre" del velo):
      // negativo o basura se queda con el de fábrica y el resto da la vuelta.
      cardBgAngle: _angle(j['cardBgAngle'], f.cardBgAngle),
      imageShadow: hasShadow
          ? _num(j['imageShadow'], f.imageShadow).clamp(0, 1)
          : f.imageShadow,
      imageShadowStart: hasShadow
          ? _num(j['imageShadowStart'], f.imageShadowStart).clamp(0, .95)
          : f.imageShadowStart,
      imageShadowEnd: hasShadow
          ? _num(j['imageShadowEnd'], f.imageShadowEnd).clamp(.05, 1)
          : f.imageShadowEnd,
      // La POSICIÓN de la sombra también llegó después: sin el campo se queda
      // abajo (0°), que es como se veía antes.
      imageShadowAngle: _angle(j['imageShadowAngle'], f.imageShadowAngle),
      animMode: _choice(j['animMode'], kDesignAnimModes, f.animMode),
      animMs: _int(j['animMs'], f.animMs),
      animStagger: _int(j['animStagger'], f.animStagger),
    );
  }
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

/// Color de fábrica del velo que oscurece la FOTO DE FONDO de una tarjeta
/// (`bg`): es NEGRO en los dos lados —aquí y en la web (`site.js`)— porque
/// sobre la foto es lo que mejor hace resaltar el texto. El color se puede
/// cambiar desde el diseñador.
const String kPhotoFadeColor = '#000000';

/// Colores de fábrica del fondo de la tarjeta en el estilo `fade` (fondo con
/// degradado de desaparición). Coinciden con los de la web (`site.js`).
const String kCardBgFrom = '#0B0E17';
const String kCardBgTo = '#0B111A';

/// Valores permitidos de un campo de opciones (foto, degradado, animación).
const List<String> kDesignImageModes = ['none', 'top', 'bg', 'fade'];

/// Direcciones del velo que oscurece la foto de fondo. [kFadeFromDeg] es el
/// ángulo CSS de cada una (el lado NOMBRADO es el que tapa más).
const List<String> kDesignFadeFroms = [
  'bottom',
  'top',
  'left',
  'right',
  'topLeft',
  'topRight',
  'bottomLeft',
  'bottomRight',
];

/// Ángulo CSS de cada dirección del velo (0 = arriba, 90 = derecha…): el
/// degradado termina del lado nombrado, que es el que queda más oscuro.
const Map<String, double> kFadeFromDeg = {
  'top': 0,
  'topRight': 45,
  'right': 90,
  'bottomRight': 135,
  'bottom': 180,
  'bottomLeft': 225,
  'left': 270,
  'topLeft': 315,
};

/// Ángulo de la capa PERPENDICULAR (la que tapa el flanco), por dirección.
/// Es el MISMO mapa que `HS_FADE_SIDE_DEG` de la web y el del HTML del panel:
/// si aquí cambiara un número, la tarjeta del panel y la del sitio dejarían de
/// verse iguales.
const Map<String, double> kFadeSideDeg = {
  'top': 95,
  'bottom': 95,
  'left': 5,
  'right': 5,
  'topLeft': 45,
  'topRight': 135,
  'bottomLeft': 315,
  'bottomRight': 225,
};

/// Ángulo CSS del velo: el libre manda; si no hay, la dirección nombrada.
///
/// Está aquí (y no en cada pintor) para que el panel, el HTML de la vista
/// previa y la web usen EXACTAMENTE el mismo número.
double hsFadeCssDeg(String from, double angle) {
  if (angle >= 0) return ((angle % 360) + 360) % 360;
  return kFadeFromDeg[from] ?? 180;
}

/// Ángulo CSS de la SOMBRA de la foto: cuánto se gira desde "abajo" (0°).
/// Se normaliza a 0..359 para que el panel y la web escriban el mismo número.
double hsShadowCssDeg(double angle) => ((angle % 360) + 360) % 360;

/// Ángulo CSS de la capa perpendicular del velo.
double hsFadeSideCssDeg(String from, double angle) {
  if (angle >= 0) return (((angle - 85) % 360) + 360) % 360;
  return kFadeSideDeg[from] ?? 95;
}

const List<String> kDesignAnimModes = ['up', 'fade', 'zoom', 'none'];

/// Ángulo del velo leído tolerante: -1 (o lo que no sea número) = sin ángulo
/// libre; cualquier otro valor se queda dentro de 0..359.
double _fadeAngle(Object? v, double fallback) {
  final n = _num(v, fallback);
  if (n < 0) return -1;
  return n % 360;
}

/// Ángulo normal 0..359 (el del fondo de la tarjeta): negativo o basura se
/// queda con el de fábrica, y lo que sobra da la vuelta.
double _angle(Object? v, double fallback) {
  final n = _num(v, fallback);
  if (n < 0) return fallback;
  return n % 360;
}

/// Una opción guardada: si no es una de las válidas, se queda con el default.
String _choice(Object? v, List<String> allowed, String fallback) {
  final s = (v ?? '').toString().trim();
  return allowed.contains(s) ? s : fallback;
}

String _text(Object? v, String fallback) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? fallback : s;
}

import 'site_design.dart';

// ==================================================================
// HARD STREET ADMIN — LA TARJETA DE PAQUETE, COMO HTML
// ==================================================================
// Genera un documento HTML AUTOCONTENIDO con UNA tarjeta de paquete pintada
// con los MISMOS valores que aplica la web (`gallery/assets/site.js` →
// `siteDesignCss` + `hsPhotoFade`) y con el mismo markup que `renderers.js`
// (`.package-card > .pkg-flyer-inner > …`).
//
// Sirve para la vista previa REAL del diseñador (WebView) y para abrir la
// tarjeta en el navegador. Al compartir valores con el sitio, lo que se ve en
// el panel es lo que se ve en la página — sin duplicar la hoja de estilos
// entera, solo la parte que pinta la tarjeta.
// ==================================================================

/// Datos de muestra de una tarjeta (el diseñador los pasa desde sus muestras).
class CardHtmlSample {
  const CardHtmlSample({
    this.tierKey = 'premium',
    this.tierLabel = 'Premium',
    this.name = 'Boda Full',
    this.category = 'Bodas',
    this.categoryIcon = '💍',
    this.subtitle = 'Cobertura completa del día',
    this.price = r'$25,000',
    this.services = const [
      'Cobertura',
      'Álbum impreso',
      'Video',
      'Galería online',
    ],
    this.photoUrl = '',
  });

  final String tierKey;
  final String tierLabel;
  final String name;
  final String category;
  final String categoryIcon;
  final String subtitle;
  final String price;
  final List<String> services;

  /// Foto real (URL) o vacío: sin foto, la tarjeta se ve limpia (o con el
  /// hueco degradado cuando la foto va de fondo), igual que en la web.
  final String photoUrl;
}

/// HTML completo (documento con su `<style>`) de una tarjeta de paquete.
String hsPackageCardHtml({
  required SiteCardDesign card,
  required SiteTierDesign tier,
  CardHtmlSample sample = const CardHtmlSample(),
  String gold = '#C9A96E',
}) {
  final accent = _hex(tier.accent);
  final accentSoft = _hex(tier.accentSoft);
  final dark = _hex(tier.dark);
  final mode = kDesignImageModes.contains(card.imageMode)
      ? card.imageMode
      : 'none';
  final photoBackdrop = mode == 'bg' || mode == 'fade';

  final css = StringBuffer()
    ..writeln(_baseCss(accent: accent, dark: dark))
    ..writeln(_designCss(card: card, accent: accent, accentSoft: accentSoft))
    ..writeln(
      _tierCss(
        card: card,
        tier: tier,
        tierKey: sample.tierKey,
        accent: accent,
        dark: dark,
        accentSoft: accentSoft,
      ),
    );

  final body = StringBuffer();
  // Foto: banda arriba o capa de fondo (como `packagePhotoHtml` en la web).
  if (mode == 'top' && sample.photoUrl.isNotEmpty) {
    body.writeln(
      '<img class="pkg-photo" src="${_esc(sample.photoUrl)}" alt="">',
    );
  } else if (photoBackdrop) {
    body.writeln(
      sample.photoUrl.isNotEmpty
          ? '<div class="pkg-photo-bg" '
                "style=\"background-image:url('${_esc(sample.photoUrl)}')\" "
                'aria-hidden="true"></div>'
          : '<div class="pkg-photo-bg pkg-photo-empty" '
                'aria-hidden="true"></div>',
    );
  }

  body.writeln('<div class="pkg-flyer-inner">');
  body.writeln(
    '<div class="pkg-tier-badge tier-${_esc(sample.tierKey)}">'
    '${_esc(sample.tierLabel)}</div>',
  );
  if (card.showCategory) {
    body.writeln(
      '<div class="pkg-category">'
      '<span class="pkg-category-icon">${_esc(sample.categoryIcon)}</span>'
      '<span class="pkg-category-name">${_esc(sample.category)}</span></div>',
    );
  }
  body.writeln('<div class="pkg-header">');
  body.writeln('<h3 class="pkg-name">${_esc(sample.name)}</h3>');
  if (card.showSubtitle) {
    body.writeln('<p class="pkg-subtitle">${_esc(sample.subtitle)}</p>');
  }
  body.writeln('</div>');
  if (card.showServices || card.showServiceCount) {
    body.writeln('<div class="pkg-divider"></div>');
  }
  if (card.showServiceCount) {
    body.writeln(
      '<div class="pkg-services-header"><span class="pkg-services-count">'
      '${sample.services.length} servicios incluidos</span></div>',
    );
  }
  if (card.showServices) {
    final limit = card.servicesLimit <= 0
        ? sample.services.length
        : card.servicesLimit;
    final shown = sample.services.take(limit).toList();
    body.writeln('<ul class="pkg-services">');
    for (final s in shown) {
      body.writeln(
        '<li><span class="pkg-icon-svg">✓</span>'
        '<span class="pkg-service-text">${_esc(s)}</span></li>',
      );
    }
    if (shown.length < sample.services.length) {
      body.writeln(
        '<li class="pkg-services-more">+${sample.services.length - shown.length}'
        ' más…</li>',
      );
    }
    body.writeln('</ul>');
  }
  if (card.showPrice || card.showCta) {
    body.writeln('<div class="pkg-footer">');
    if (card.showPrice) {
      body.writeln(
        '<div class="pkg-price">'
        '<span class="pkg-price-label">${_esc(card.priceLabel)}</span>'
        '<span class="pkg-price-value">${_esc(sample.price)}</span></div>',
      );
    }
    if (card.showCta) {
      body.writeln(
        '<a class="pkg-cta" href="#"><span>${_esc(card.ctaLabel)}</span></a>',
      );
    }
    body.writeln('</div>');
  }
  body.writeln('</div>');

  return '''
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Playfair+Display:wght@600;700&family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
$css
</style>
</head>
<body>
<div class="stage">
<div class="package-card tier-${_esc(sample.tierKey)}" style="--gold:$gold">
${body.toString().trimRight()}
</div>
</div>
</body>
</html>
''';
}

/// Estilos de los elementos de la tarjeta (los toma de `index.css`).
String _baseCss({required String accent, required String dark}) =>
    '''
*{box-sizing:border-box}
html,body{margin:0;padding:0;background:transparent}
body{font-family:'Inter',system-ui,-apple-system,sans-serif;-webkit-font-smoothing:antialiased}
.stage{display:flex;justify-content:center;align-items:flex-start;padding:16px;min-height:100vh}
.package-card{position:relative;overflow:hidden;width:100%;max-width:450px;
  display:flex;flex-direction:column;background:$dark}
.package-card::before{content:'';position:absolute;top:0;left:0;right:0;height:2.4px;z-index:2;
  background:linear-gradient(90deg,transparent,$accent,transparent)}
.pkg-flyer-inner{position:relative;z-index:1;display:flex;flex-direction:column}
.pkg-tier-badge{align-self:flex-start;display:inline-flex;align-items:center;padding:4px 10px;
  border:1px solid transparent;border-radius:6px;font-size:10px;font-weight:800;
  letter-spacing:2px;text-transform:uppercase}
.pkg-category{display:flex;align-items:center;gap:8px;margin-top:14px;
  font-size:10.5px;letter-spacing:2.2px;font-weight:700;text-transform:uppercase}
.pkg-category-icon{font-size:15px;letter-spacing:normal}
.pkg-header{margin-top:10px}
.pkg-name{margin:0;font-size:22px;font-weight:700;line-height:1.2}
.pkg-subtitle{margin:6px 0 0;font-style:italic;font-size:12.5px}
.pkg-divider{height:1px;margin:14px 0;background:rgba(255,255,255,.08)}
.pkg-services-header{font-size:10px;letter-spacing:1.6px;text-transform:uppercase;
  font-weight:700;color:rgba(255,255,255,.5)}
.pkg-services{list-style:none;margin:8px 0 0;padding:0;display:flex;flex-direction:column;gap:6px}
.pkg-services li{display:flex;align-items:center;gap:8px;font-size:12.5px;
  color:rgba(255,255,255,.82)}
.pkg-icon-svg{font-size:11px;font-weight:800}
.pkg-services-more{color:rgba(255,255,255,.5);font-size:11.5px;font-style:italic}
.pkg-footer{display:flex;align-items:flex-end;justify-content:space-between;gap:12px}
.pkg-price{display:flex;flex-direction:column}
.pkg-price-label{font-size:9.5px;letter-spacing:1.2px;font-style:italic;
  color:rgba(255,255,255,.45)}
.pkg-price-value{font-family:'Playfair Display',serif;font-size:22px;font-weight:700}
.pkg-cta{display:inline-flex;align-items:center;justify-content:center;padding:10px 18px;
  border-radius:999px;border:1px solid transparent;font-size:12px;font-weight:600;
  text-decoration:none}
.pkg-photo{display:block;width:100%;object-fit:cover}
.pkg-photo-bg{position:absolute;inset:0;background-size:cover;background-position:center}
''';

/// Lo que el diseñador ajusta: forma, relleno, tipografía y foto.
String _designCss({
  required SiteCardDesign card,
  required String accent,
  required String accentSoft,
}) {
  final css = StringBuffer();
  final pad = card.padding.round();
  final radius = card.radius.round();
  final border = card.borderWidth;
  css.writeln(
    '.package-card{border-radius:${radius}px;'
    'border:${_num(border)}px solid '
    '${border <= 0 ? 'transparent' : _rgba(accent, 1)};}',
  );
  css.writeln('.pkg-flyer-inner{padding:14px ${pad}px 0;}');
  css.writeln('.pkg-footer{padding:14px 0 ${pad}px;}');
  css.writeln(
    ".pkg-name{font-family:${card.serifNames ? "'Playfair Display',serif" : "'Inter',sans-serif"};"
    'text-transform:${card.uppercaseNames ? 'uppercase' : 'none'};'
    'letter-spacing:${card.uppercaseNames ? '.06em' : '0'};}',
  );
  if (!card.lineTop) {
    css.writeln('.package-card::before{display:none;}');
  }
  if (card.imageMode == 'top') {
    css.writeln('.pkg-photo{height:${card.imageHeight.round()}px;}');
  }
  if (card.imageMode == 'fade') {
    // FONDO CON DESVANECIDO: la foto se ve de un lado y se funde con el fondo
    // (sin velo encima). La web usa el MISMO `mask-image` y los mismos números.
    final deg = _num(hsFadeCssDeg(card.imageFadeFrom, card.imageFadeAngle));
    final a = card.imageFadeStart.clamp(0.0, .95);
    final b = card.imageFadeEnd.clamp(a + .05, 1.0);
    final mask =
        'linear-gradient(${deg}deg,#000 ${(a * 100).toStringAsFixed(1)}%,'
        'transparent ${(b * 100).toStringAsFixed(1)}%)';
    css.writeln('.pkg-photo-bg{-webkit-mask-image:$mask;mask-image:$mask;}');
    // Sin foto, el hueco del acento se desvanece igual: se ve dónde irá.
    css.writeln(
      '.pkg-photo-empty{background:linear-gradient(135deg,'
      '${_rgba(accent, .28)},${_rgba('#000000', .35)});}',
    );
  }
  if (card.imageMode == 'bg') {
    // El mismo velo que la web (`hsPhotoFade`), más la sombra (degradado negro
    // con dos paradas móviles, como el de Photoshop).
    if (card.imageShadow > 0) {
      final start = card.imageShadowStart.clamp(0.0, .95);
      final end = card.imageShadowEnd.clamp(start + .05, 1.0);
      final black = _rgba('#000000', _round2(card.imageShadow));
      // POSICIÓN: el diseño decide de qué lado entra la sombra (0° abajo).
      final deg = _num(hsShadowCssDeg(card.imageShadowAngle));
      css.writeln(
        ".pkg-photo-bg::before{content:'';position:absolute;inset:0;"
        'background:linear-gradient(${deg}deg,'
        '$black 0%,$black ${(start * 100).toStringAsFixed(1)}%,'
        'rgba(0,0,0,0) ${(end * 100).toStringAsFixed(1)}%);}',
      );
    }
    css.writeln(
      ".pkg-photo-bg::after{content:'';position:absolute;inset:0;"
      'background:${_fadeCss(card.imageFadeColor, card.imageFade, card.imageFadeFrom, card.imageFadeAngle)};}',
    );
    css.writeln(
      '.pkg-photo-empty{background:linear-gradient(135deg,'
      '${_rgba(accent, .28)},${_rgba('#000000', .35)});}',
    );
  }
  // El acento de la marca, por si el CSS base lo necesita.
  css.writeln(':root{--accent:$accent;--accent-soft:$accentSoft;}');
  return css.toString();
}

/// Lo mismo que el bucle por tier de `siteDesignCss`.
String _tierCss({
  required SiteCardDesign card,
  required SiteTierDesign tier,
  required String tierKey,
  required String accent,
  required String accentSoft,
  required String dark,
}) {
  final k = '.package-card.tier-${_slug(tierKey)}';
  final css = StringBuffer();
  // En el estilo `fade` el fondo lo elige el diseñador: un color o, si lo
  // pide, un degradado de dos colores con su ángulo (como en la web).
  final bg = card.imageMode == 'fade'
      ? (card.cardBgGradient
            ? 'linear-gradient(${_num(card.cardBgAngle)}deg,'
                  '${_hex(card.cardBgFrom)},${_hex(card.cardBgTo)})'
            : _hex(card.cardBgFrom))
      : dark;
  css.writeln(
    '$k{background:$bg;'
    'border-color:${card.borderWidth <= 0 ? 'transparent' : _rgba(accent, tier.borderAlpha)};'
    'border-width:${_num(card.borderWidth)}px;}',
  );
  css.writeln('$k .pkg-name{color:#fff;}');
  css.writeln('$k .pkg-price-value,$k .pkg-category-name{color:$accent;}');
  css.writeln('$k .pkg-icon-svg{color:$accent;}');
  css.writeln('$k .pkg-subtitle{color:${_rgba('#ffffff', .55)};}');
  css.writeln(
    '$k .pkg-cta{background:${_rgba(accent, .18)};color:$accent;'
    'border-color:transparent;}',
  );
  css.writeln(
    tier.badgeFilled
        ? '$k .pkg-tier-badge{background:linear-gradient(135deg,$accent,$accentSoft);'
              'color:$dark;border-color:transparent;}'
        : '$k .pkg-tier-badge{background:${_rgba(accent, .12)};'
              'color:$accentSoft;border-color:${_rgba(accent, .35)};}',
  );
  return css.toString();
}

/// Clase CSS del tier (`premium`, `gold`, `basic`) segura para el `<style>`.
String _slug(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

// ------------------------------------------------------------------
// Color y texto
// ------------------------------------------------------------------

/// `#RRGGBB` normalizado (3 → 6 dígitos). Si no se entiende, negro.
String _hex(String hex) {
  final s = hex.replaceAll('#', '').trim();
  final full = s.length == 3 ? s.split('').map((c) => '$c$c').join() : s;
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(full)) return '#000000';
  return '#${full.toUpperCase()}';
}

/// `rgba(r, g, b, a)` igual que `hsAlpha` de la web.
String _rgba(String hex, double alpha) {
  final full = _hex(hex).substring(1);
  final n = int.parse(full, radix: 16);
  final r = (n >> 16) & 255;
  final g = (n >> 8) & 255;
  final b = n & 255;
  return 'rgba($r, $g, $b, ${_round2(alpha.clamp(0.0, 1.0))})';
}

/// Número CSS: sin `.0` colgando (3 en vez de 3.0).
String _num(double v) {
  final r = _round2(v);
  return r == r.roundToDouble() ? r.round().toString() : r.toString();
}

double _round2(double v) => (v * 100).round() / 100;

/// El velo de la foto, calcado de `hsPhotoFade` de `site.js`.
String _fadeCss(String color, double amount, String from, double angle) {
  final f = _round2(amount.clamp(0.0, 1.0));
  String a(double x) => _rgba(color, _round2(x.clamp(0.0, 1.0)));
  // Los ángulos salen del MISMO sitio que usa el panel (`site_design.dart`):
  // así la vista previa del diseñador y la web no se separan ni un grado.
  final deg = _num(hsFadeCssDeg(from, angle));
  final side = _num(hsFadeSideCssDeg(from, angle));
  return 'linear-gradient(${deg}deg,${a(f * .15)} 0%,${a(f * .6)} 50%,'
      '${a(f)} 100%),linear-gradient(${side}deg,${a(f * .55)} 0%,'
      '${a(f * .22)} 55%,${a(0)} 100%)';
}

/// Texto seguro para HTML: lo que escriba el usuario se VE tal cual (nunca se
/// interpreta como etiquetas ni rompe un atributo).
String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

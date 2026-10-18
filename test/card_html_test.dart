import 'package:flutter_test/flutter_test.dart';
import 'package:hardstreet_admin/card_html.dart';
import 'package:hardstreet_admin/site_design.dart';

// ==================================================================
// LA TARJETA EN HTML (vista previa real del diseñador)
// ==================================================================
// El diseñador enseña la tarjeta en un WebView con este documento. Como lo que
// se busca es que se vea IGUAL que la web, aquí se revisa que el markup y los
// valores del diseño lleguen al CSS (y que no se cuele HTML del usuario).
// ==================================================================

String _html(SiteCardDesign card, {CardHtmlSample? sample}) =>
    hsPackageCardHtml(
      card: card,
      tier: SiteDesign.defaults.tiers['premium']!,
      sample: sample ?? const CardHtmlSample(),
    );

void main() {
  test('el markup es el de la web (clases del catálogo)', () {
    final html = _html(const SiteCardDesign());
    expect(html, contains('class="package-card tier-premium"'));
    expect(html, contains('pkg-flyer-inner'));
    expect(html, contains('pkg-tier-badge'));
    expect(html, contains('pkg-category-name'));
    expect(html, contains('class="pkg-name"'));
    expect(html, contains('pkg-services'));
    expect(html, contains('pkg-price-value'));
    expect(html, contains('class="pkg-cta"'));
  });

  test('los valores del diseño llegan al CSS', () {
    final html = _html(
      const SiteCardDesign(radius: 26, padding: 18, serifNames: false),
    );
    expect(html, contains('border-radius:26px'));
    expect(html, contains('padding:14px 18px 0'));
    expect(html, contains("font-family:'Inter',sans-serif"));
    // La línea superior se apaga cuando el diseño lo pide.
    final sinLinea = _html(const SiteCardDesign(lineTop: false));
    expect(sinLinea, contains('.package-card::before{display:none;}'));
  });

  test('lo que el diseño oculta no se dibuja', () {
    final html = _html(
      const SiteCardDesign(
        showPrice: false,
        showCta: false,
        showServices: false,
        showCategory: false,
      ),
    );
    // Ojo: el CSS siempre nombra las clases; lo que no puede aparecer es el
    // ELEMENTO.
    expect(html, isNot(contains('class="pkg-price-value"')));
    expect(html, isNot(contains('class="pkg-cta"')));
    expect(html, isNot(contains('class="pkg-services"')));
    expect(html, isNot(contains('class="pkg-category-name"')));
  });

  test('la foto de fondo lleva el velo y la sombra del diseño', () {
    final conSombra = _html(
      const SiteCardDesign(
        imageMode: 'bg',
        imageFade: .8,
        imageFadeFrom: 'top',
        imageFadeAngle: 90,
        imageShadow: .6,
      ),
    );
    // Velo: el ángulo libre manda (90°) y el color de fábrica es negro.
    expect(conSombra, contains('linear-gradient(90deg,rgba(0, 0, 0, 0.12)'));
    expect(conSombra, contains('rgba(0, 0, 0, 0.48) 50%'));
    // Sombra: degradado negro hacia arriba con sus DOS paradas (empieza en el
    // 8% y se apaga en el 72%), como el degradado de Photoshop.
    expect(
      conSombra,
      contains(
        'linear-gradient(to top,rgba(0, 0, 0, 0.6) 0%,'
        'rgba(0, 0, 0, 0.6) 8.0%,rgba(0,0,0,0) 72.0%)',
      ),
    );
    expect(conSombra, contains('pkg-photo-bg::after'));

    // Con la fuerza a 0, esa capa no se emite.
    final sinSombra = _html(
      const SiteCardDesign(imageMode: 'bg', imageShadow: 0),
    );
    expect(sinSombra, isNot(contains('to top,rgba')));
    expect(sinSombra, isNot(contains('pkg-photo-bg::before')));
  });

  test('el fondo con degradado funde la foto con el fondo elegido', () {
    final html = _html(
      const SiteCardDesign(
        imageMode: 'fade',
        imageFadeStart: .2,
        imageFadeEnd: .7,
        cardBgFrom: '#123456',
        cardBgTo: '#654321',
        cardBgGradient: true,
        cardBgAngle: 200,
      ),
    );
    // La foto lleva la MÁSCARA con las dos paradas del diseñador (no un velo).
    expect(
      html,
      contains(
        '.pkg-photo-bg{-webkit-mask-image:linear-gradient(180deg,#000 20.0%,'
        'transparent 70.0%);mask-image:linear-gradient(180deg,#000 20.0%,'
        'transparent 70.0%);}',
      ),
    );
    // El fondo de la tarjeta es el degradado elegido (no el del tier).
    expect(
      html,
      contains('background:linear-gradient(200deg,#123456,#654321)'),
    );
    // En este estilo no hay velo ni sombra encima de la foto.
    expect(html, isNot(contains('pkg-photo-bg::after')));
    expect(html, isNot(contains('pkg-photo-bg::before')));

    // Fondo de UN color y la máscara girada: 0..360 y ángulo libre.
    final plano = _html(
      const SiteCardDesign(
        imageMode: 'fade',
        imageFadeAngle: 45,
        cardBgFrom: '#0A0B0C',
        imageFadeStart: 0,
        imageFadeEnd: 1,
      ),
    );
    expect(plano, contains('mask-image:linear-gradient(45deg,#000 0.0%,'));
    expect(plano, contains('background:#0A0B0C'));
  });

  test('el nombre del paquete se escapa (no se cuela HTML)', () {
    final html = _html(
      const SiteCardDesign(),
      sample: const CardHtmlSample(name: '<script>x</script>Boda'),
    );
    expect(html, isNot(contains('<script>')));
    expect(html, contains('&lt;script&gt;x&lt;/script&gt;Boda'));
  });
}

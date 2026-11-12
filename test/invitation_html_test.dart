import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/modules/invitations/templates/invitation_html.dart';
import 'package:hardstreet_admin/modules/invitations/models/invitation_model.dart';

// ==================================================================
// INVITACIONES — catálogo, HTML público y liga para compartir
// ==================================================================
// El HTML es lo que ve el CLIENTE en /i/<liga>: es el documento original
// de Hardstreet/ReynaCoot (mismas clases, mismo CSS y mismo JS) con los
// datos inyectados. Aquí se comprueba que salga el contenido real (sobre,
// tarjeta, familias, detalles, itinerario…) y que el texto escrito se
// ESCAPE (un nombre con < o & nunca debe entrar como etiqueta).
// ==================================================================

void main() {
  test('el catálogo tiene las dos plantillas reales', () {
    expect(kInvitationTemplates.length, 2);
    expect(kInvitationTemplates.first.key, 'sobre-xv');
    expect(kInvitationTemplates.first.name, 'Rosa Pastel');
    expect(kInvitationTemplates[1].key, 'boda-marfil');
    expect(kInvitationTemplates[1].name, 'Marfil & Oro');
    expect(invitationCatalog().length, 2);
    expect(invitationCatalog().first.templates.length, 1);
    // Una invitación vieja con otra plantilla cae en Rosa Pastel.
    expect(invitationTemplate('plantilla-borrada').key, 'sobre-xv');
    expect(Invitation.sample('boda-jardin').design.occasion, 'XV');
    expect(Invitation.sample('sobre-xv').coverStyleKey, 'rosa');
    expect(Invitation.sample('boda-marfil').coverStyleKey, 'carta');
  });

  test('el texto del cliente se ESCAPA en el HTML', () {
    final inv = Invitation.sample('boda-clasica').copyWith(
      headline: '<script>alert(1)</script>',
      message: 'Ana & Luis <3',
      placeName: 'Casa "El Roble"',
    );
    final html = buildInvitationHtml(inv);

    expect(html, contains('&lt;script&gt;alert(1)&lt;/script&gt;'));
    expect(html, isNot(contains('<script>alert(1)</script>')));
    expect(html, contains('Ana &amp; Luis &lt;3'));
    expect(html, contains('Casa &quot;El Roble&quot;'));
    // Y sigue siendo un documento completo.
    expect(html, startsWith('<!DOCTYPE html>'));
  });

  test('la portada es el sobre original y abre con openInvitation()', () {
    final html = buildInvitationHtml(Invitation.sample('sobre-xv'));

    expect(html, contains('id="envelope"'));
    expect(html, contains('Tienes una invitación'));
    expect(html, contains('onclick="openInvitation()"'));
    // La tarjeta y los adornos del documento original de ReynaCoot.
    expect(html, contains('class="main-card"'));
    expect(html, contains('class="vertical-title"'));
    expect(html, contains('class="invite-frame"'));
    expect(html, contains('class="tiara"'));
    expect(html, contains('class="ribbon"'));
    expect(html, contains('class="butterfly"'));
    expect(html, contains('class="corner-svg tl"'));
    expect(html, contains('Faltan'));
    expect(html, contains('id="days"'));
    // Y las secciones del diseño de Reyna.
    expect(html, contains('Con mi familia'));
    expect(html, contains('Confirmar asistencia'));
    expect(html, contains('Itinerario de Actividades'));
    expect(html, contains('Hardstreet'));
    // El CSS y el JS originales viajan dentro del documento (una sola liga).
    expect(html, contains("font-family: 'Great Vibes', cursive;"));
    expect(html, contains('function openInvitation()'));
    expect(html, contains("envelope.classList.add('opening')"));
    expect(html, contains('function startCountdown()'));
  });

  test('cada portada tiene una composición distinta', () {
    final cases = <String, String>{
      'rosa': 'hs-rosa-arch',
      'carta': 'hs-carta-stage',
      'xv': 'hs-xv-number',
      'noche': 'hs-night-moon',
      'cortina': 'hs-curtain',
      'clasica': 'hs-clasica-frame',
    };
    for (final entry in cases.entries) {
      final html = buildInvitationHtml(
        Invitation.sample('sobre-xv').copyWith(coverStyle: entry.key),
      );
      expect(
        html,
        contains('hs-presentation hs-scene-${entry.key}'),
        reason: 'la portada ${entry.key} debe tener su propio escenario',
      );
      expect(html, contains(entry.value));
      expect(
        html,
        contains('hs-cover-${entry.key} hs-template-rosa hs-cover-custom'),
      );
      expect(html, contains('id="envelope"'));
      expect(html, contains('onclick="openInvitation()"'));
    }
  });

  test('Marfil añade la capa de boda solo a la invitación', () {
    final html = buildInvitationHtml(Invitation.sample('boda-marfil'));
    expect(html, contains('mf-branch left'));
    expect(html, contains('mf-branch right'));
    expect(html, contains('mf-sprig'));
    expect(html, contains('mf-hero-ornament'));
    expect(html, contains('CAPA «BODA EDITORIAL»'));
    expect(html, contains('mf-head::before'));
    expect(html, contains('mf-card::after'));
    expect(html, isNot(contains('{{')));
  });

  test('la portada toma la paleta de la plantilla', () {
    final rosa = buildInvitationHtml(Invitation.sample('sobre-xv'));
    expect(rosa, contains('--hs-cover-accent: #B76E79'));
    expect(rosa, contains('--hs-cover-bg: #E8CFCD'));

    final marfil = buildInvitationHtml(Invitation.sample('boda-marfil'));
    expect(marfil, contains('--hs-cover-accent: #B99A63'));
    expect(marfil, contains('--hs-cover-bg: #F8F3E7'));
    expect(marfil, contains('hs-carta-stage'));
    expect(marfil, contains('hs-carta-flap'));
    expect(marfil, contains('hs-carta-seal'));
    expect(marfil, contains("cover.classList.add('opening')"));
  });

  test('la Carta tiene cinco fondos y usa sus propios recursos', () {
    final marfil = Invitation.sample('boda-marfil');
    expect(marfil.coverBackdropKey, 'marfil');

    for (final backdrop in kInvitationCoverBackdrops) {
      final html = buildInvitationHtml(
        marfil.copyWith(coverBackdrop: backdrop.key, sections: const ['cover']),
      );
      expect(
        html,
        contains('hs-carta-bg-${backdrop.key}'),
        reason: 'el tinte ${backdrop.key} debe llegar al HTML',
      );
      expect(html, contains('hs-carta-portada'));
      expect(html, contains('hs-carta-papel'));
      expect(html, contains('hs-carta-tinte'));
      expect(html, contains('hs-carta-grano'));
      expect(html, contains('hs-carta-anillos'));
      expect(html, contains('hs-carta-flor-esquina'));
      expect(html, contains('hs-carta-cinta'));
      expect(html, contains('https://i.imgur.com/EjgjsxW.png'));
      expect(html, contains('https://i.imgur.com/zuk8cKV.png'));
      expect(html, contains('https://i.imgur.com/kHfHXdk.png'));
      expect(html, contains('hs-carta-petalo'));
      expect(html, contains('hs-carta-tilt'));
      expect(html, isNot(contains('hs-carta-address')));
      expect(html, contains('hs-carta-seal'));
      expect(html, contains('hs-carta-liner'));
      expect(html, isNot(contains('hs-carta-stack')));
      expect(html, contains('hs-carta-vineta'));
      expect(html, contains('hs-carta-destellos'));
      expect(html, contains('hs-carta-foil'));
      expect(html, contains('hs-carta-letter-wm'));
      expect(html, contains('hs-carta-letter-sprig'));
      expect(html, contains('hs-carta-lazada'));
      expect(html, contains('hs-carta-rule'));
      expect(html, contains('hs-carta-tap-line'));
      expect(html, contains('hs-carta-flap-mark'));
      expect(html, contains('hs-carta-flap-inner'));
      expect(html, contains('.envelope.opening .hs-carta-liner'));
      expect(html, contains('data:image/webp;base64,'));
      // El sobre es horizontal y descansa girado -45°; la carta vive dentro.
      expect(html, contains('aspect-ratio: 1.55;'));
      expect(html, contains('hs-carta-rotor'));
      expect(html, contains('transform: rotate(-45deg);'));
      expect(html, contains('hsCartaSprigSway'));
      expect(html, contains('@keyframes hsCartaCardIn'));
      expect(html, contains('@keyframes hsCartaCardFloat'));
      expect(html, contains('@keyframes hsCartaPaperDrift'));
      expect(html, contains('@keyframes hsCartaFloatSoft'));
      expect(html, contains('@keyframes hsCartaBloomSway'));
      expect(html, contains('@keyframes hsCartaFoilSweep'));
      expect(html, contains('@keyframes hsCartaTwinkle'));
      expect(html, contains('hs-carta-fold'));
      expect(html, isNot(contains('hs-carta-cta')));
      expect(html, isNot(contains('Abrir carta')));
      expect(html, contains('@keyframes hsCartaRibbonSway'));
      expect(html, contains('@keyframes hsCartaPetalo'));
      expect(html, contains('@keyframes hsCartaLetterContent'));
      expect(html, contains('.envelope.opening .hs-carta-flap'));
      expect(html, contains('.envelope.opening .hs-carta-letter'));
      // El escenario debe llenar el sobre; una regla posterior no puede
      // devolverlo al flujo y encogerlo al tamaño del contenido.
      expect(
        RegExp(r'\.hs-scene-carta\s*\{[^}]*position:\s*relative')
            .hasMatch(html),
        isFalse,
      );
      // La carta cerrada es una pieza completa; al abrirse, el frente no se
      // recorta: la hoja asoma por el borde superior del sobre.
      expect(
        RegExp(r'\.hs-carta-body\s*\{[^}]*inset:\s*0;').hasMatch(html),
        isTrue,
      );
      expect(
        RegExp(r'\.envelope\.opening \.hs-carta-body').hasMatch(html),
        isFalse,
      );
      final openLetter =
          RegExp(r'\.envelope\.opening \.hs-carta-letter\s*\{[^}]*\}')
              .firstMatch(html)
              ?.group(0) ??
          '';
      expect(openLetter, contains('translateY(-72%)'));
      expect(openLetter, isNot(contains('z-index')));
      expect(html, contains('animation: hsCartaLetterContent .68s ease both;'));
      expect(html, contains('animation-delay: .38s;'));
      // Los recursos viajan dentro del documento: debe seguir cabiendo en la API.
      expect(html.length, lessThan(2000000));
    }

    // Un valor desconocido no rompe: la Carta vuelve al marfil clásico.
    final fallback = buildInvitationHtml(
      marfil.copyWith(coverBackdrop: 'noche'),
    );
    expect(fallback, contains('hs-carta-bg-marfil'));
    expect(
      Invitation.fromJson(marfil.copyWith(coverBackdrop: 'jardin').toJson())
          .coverBackdropKey,
      'jardin',
    );
  });

  test('la carta muestra la frase, la fecha y el lugar', () {
    final inv = Invitation.sample('boda-marfil').copyWith(
      timeText: '7:30 PM',
      placeName: 'Hacienda San Gabriel',
      sections: const ['cover'],
    );
    final html = buildInvitationHtml(inv);

    expect(html, contains('hs-carta-message'));
    expect(html, contains('Acompáñanos a celebrar'));
    expect(html, contains('hs-carta-place'));
    expect(html, contains('7:30 PM · Hacienda San Gabriel'));
  });

  test('las secciones apagadas no se dibujan y sin portada abre directo', () {
    final inv = Invitation.sample('sobre-xv')
        .copyWith(sections: const ['details', 'rsvp', 'footer']);
    final html = buildInvitationHtml(inv);

    // El sobre sigue en el documento (es el original) pero oculto.
    expect(html, contains('id="envelope"'));
    expect(html, contains('style="display:none"'));
    expect(html, contains('class="invitation open"'));
    expect(html, isNot(contains('Con mi familia')));
    expect(html, isNot(contains('Itinerario de Actividades')));
    expect(html, isNot(contains('id="days"')));
    expect(html, contains('Confirmar'));
  });

  test('frase, fotos y confirmación se ocultan como componentes', () {
    final visible = <String>[
      for (final s in kInvitationSections)
        if (!const ['quote', 'photos', 'rsvp'].contains(s.key)) s.key,
    ];
    final inv = Invitation.sample('boda-marfil').copyWith(
      quote: 'Una frase única',
      photos: const ['https://drive.test/files/foto.jpg'],
      rsvpPhone: '+52 55 1234 5678',
      sections: visible,
    );
    final html = buildInvitationHtml(inv);

    expect(html, isNot(contains('<section class="mf-quote-section')));
    expect(html, isNot(contains('<div class="mf-photos">')));
    expect(html, isNot(contains('<section class="mf-rsvp')));
    expect(html, isNot(contains('Una frase única')));
  });

  test('las invitaciones viejas encienden los componentes nuevos', () {
    final json = Invitation.sample('boda-marfil').toJson();
    final design = Map<String, dynamic>.from(json['design'] as Map);
    design['sections'] = ['details', 'footer'];
    design.remove('sectionVersion');
    final back = Invitation.fromJson({...json, 'design': design});

    expect(back.sectionOn('quote'), isTrue);
    expect(back.sectionOn('photos'), isTrue);
    expect(back.sectionOn('rsvp'), isTrue);
    expect(back.sectionOn('details'), isTrue);
    expect(back.sectionOn('families'), isFalse);
  });

  test('el acento propio manda; uno inválido deja el rosa original', () {
    final own = Invitation.sample('xv-elegancia').copyWith(accent: '#123456');
    expect(buildInvitationHtml(own), contains('#123456'));

    final bad = Invitation.sample('xv-elegancia').copyWith(accent: 'azul');
    expect(buildInvitationHtml(bad), contains('#B76E79'));
  });

  test('la fecha, el lugar y el WhatsApp salen en la invitación', () {
    final inv = Invitation.sample('cumple-dulce').copyWith(
      dateText: 'Sábado 14 de febrero de 2026',
      timeText: '6:00 pm',
      placeName: 'Terraza del Lago',
      placeAddress: 'Camino Real 120',
      rsvpPhone: '+52 133 1234 5678',
      dressCode: 'Formal',
    );
    final html = buildInvitationHtml(inv);

    expect(html, contains('Sábado 14 de febrero de 2026'));
    expect(html, contains('6:00 pm'));
    expect(html, contains('Terraza del Lago'));
    expect(html, contains('Camino Real 120'));
    expect(html, contains('Formal'));
    // El botón de confirmar arma la liga de WhatsApp con ese número.
    expect(html, contains('5213312345678'));
    expect(html, contains('https://wa.me/'));
  });

  test('la fecha del evento arma la cápsula y la cuenta regresiva', () {
    final inv = Invitation.sample('sobre-xv')
        .copyWith(eventAt: '2026-11-14T19:30');
    final html = buildInvitationHtml(inv);

    expect(html, contains('"event":"2026-11-14T19:30:00"'));
    expect(html, contains('class="dc-circle">14<'));
    expect(html, contains('NOVIEMBRE'));
    expect(html, contains('SÁBADO'));
  });

  test('las fotos salen como polaroids y vista previa al compartir', () {
    final inv = Invitation.sample('sobre-xv').copyWith(
      photos: const [
        'https://drive.test/files/boda/portada.jpg',
        'https://drive.test/files/boda/uno.jpg',
        'https://drive.test/files/boda/dos.jpg',
      ],
    );
    final html = buildInvitationHtml(inv);

    expect(html, contains('https://drive.test/files/boda/portada.jpg'));
    expect(html, contains('https://drive.test/files/boda/uno.jpg'));
    expect(html, contains('class="polaroids"'));
    expect(html, contains('class="polaroid p1"'));
    expect(html, contains('class="polaroid p2"'));
    expect(html, contains('class="polaroid p3"'));
    expect(html, contains('og:image'));
    expect(html, contains('twitter:image'));
  });

  test('sin fotos no se dibujan las polaroids ni la imagen al compartir', () {
    final html = buildInvitationHtml(
      Invitation.sample('xv-rosa').copyWith(photos: const []),
    );
    expect(html, isNot(contains('class="polaroids"')));
    expect(html, isNot(contains('og:image')));
  });

  test('el fondo opcional se pinta en el sobre y la paleta se respeta', () {
    final video = buildInvitationHtml(
      Invitation.sample('sobre-xv')
          .copyWith(bgMedia: 'https://drive.test/files/video/fondo.mp4'),
    );
    expect(video, contains('<video class="cover-media"'));
    expect(video, contains('autoplay muted loop playsinline'));

    final photo = buildInvitationHtml(
      Invitation.sample('sobre-xv').copyWith(
        bgMedia: 'https://drive.test/files/fondo.jpg',
        bgColor: '#FFFBF7',
      ),
    );
    expect(photo, contains('<img class="cover-media"'));
    expect(photo, contains('background: #FFFBF7'));
  });

  test(
    'las familias, los detalles y el itinerario salen del texto del editor',
    () {
      final inv = Invitation.sample('sobre-xv').copyWith(
        families: parseFamiliesText('Papás: Ana, Luis\nPadrinos: Rosa'),
        details: parseDetailsText(
          'Ceremonia | 7:30 PM | Iglesia | https://maps.test/x | | ⛪',
        ),
        itinerary: parseItineraryText(
          '9:00 PM | Recepción\n10:00 PM | Brindis',
        ),
        hashtag: '#AnaYLuis2026',
        musicUrl: 'https://drive.test/files/musica.mp3',
      );
      final html = buildInvitationHtml(inv);

      expect(html, contains('Padrinos'));
      expect(html, contains('Rosa'));
      expect(html, contains('Iglesia'));
      expect(html, contains('https://maps.test/x'));
      expect(html, contains('Brindis'));
      expect(html, contains('#AnaYLuis2026'));
      expect(html, contains('musica.mp3'));
    },
  );

  test('la liga pública sale del slug y solo existe al publicar', () {
    final draft = Invitation.sample('xv-elegancia');
    expect(draft.shareable, isFalse);
    expect(draft.shareUrl, isEmpty);

    final published = draft.copyWith(slug: 'abc123def456', published: true);
    expect(published.shareable, isTrue);
    expect(published.shareUrl, endsWith('/?invitation=abc123def456'));
    expect(published.shareUrl, startsWith('https://'));
  });

  test('el diseño viaja en JSON dentro de la invitación', () {
    final inv = Invitation.sample('sobre-xv').copyWith(
      bgMedia: 'https://drive.test/video.mp4',
      detailsMedia: 'https://drive.test/detalles.jpg',
      bgColor: '#E8CFCD',
      coverStyle: 'cortina',
      sections: const ['cover', 'details'],
      sectionOrder: const [
        'footer',
        'details',
        'families',
        'itinerary',
        'hashtag',
      ],
      hashtag: '#ReynaXV2026',
    );
    final json = inv.toJson();
    final design = (json['design'] as Map).cast<String, dynamic>();
    expect(design['bgMedia'], 'https://drive.test/video.mp4');
    expect(design['detailsMedia'], 'https://drive.test/detalles.jpg');
    expect(design['bgColor'], '#E8CFCD');
    expect(design['coverStyle'], 'cortina');
    expect(design['sections'], ['cover', 'details']);
    expect(design['sectionOrder'], [
      'footer',
      'details',
      'families',
      'itinerary',
      'hashtag',
    ]);

    final back = Invitation.fromJson(json);
    expect(back.bgMedia, 'https://drive.test/video.mp4');
    expect(back.detailsMedia, 'https://drive.test/detalles.jpg');
    expect(back.bgColor, '#E8CFCD');
    expect(back.coverStyle, 'cortina');
    expect(back.coverStyleKey, 'cortina');
    expect(back.sectionOrder, [
      'footer',
      'details',
      'families',
      'itinerary',
      'hashtag',
    ]);
    expect(back.flowSectionOrder, [
      'footer',
      'details',
      'families',
      'itinerary',
      'hashtag',
    ]);
    expect(back.sectionOn('cover'), isTrue);
    expect(back.sectionOn('families'), isFalse);
    expect(back.hashtag, '#ReynaXV2026');
    expect(back.families.length, inv.families.length);
  });
  test('los textos del diseño se editan y los vacíos usan el original', () {
    final inv = Invitation.sample('sobre-xv').copyWith(
      occasion: 'XV',
      verticalTitle: 'Mis XV Años',
      arcTitle: 'VALERIA · XV',
      envelopeText: 'Estás invitado',
      familiesTitle: 'Mi gente',
      detailsTitle: 'Lo que debes saber',
      detailsIntro: 'Con cariño para ti',
      itineraryTitle: 'El plan',
      hashtagIntro: 'Comparte con',
      footerMessage: 'Te espero con mucho cariño.',
    );
    final html = buildInvitationHtml(inv);

    expect(html, contains('Mis XV Años'));
    expect(html, contains('VALERIA · XV'));
    expect(html, contains('Estás invitado'));
    expect(html, contains('Mi gente'));
    expect(html, contains('Lo que debes saber'));
    expect(html, contains('Con cariño para ti'));
    expect(html, contains('El plan'));
    expect(html, contains('Comparte con'));
    expect(html, contains('Te espero con mucho cariño.'));

    // El JSON conserva los textos para volver a abrir el editor.
    final back = Invitation.fromJson(inv.toJson());
    expect(back.verticalTitle, 'Mis XV Años');
    expect(back.envelopeText, 'Estás invitado');
    expect(back.footerMessage, 'Te espero con mucho cariño.');
  });

  test('Marfil & Oro es una plantilla aparte con su propio HTML', () {
    final inv = Invitation.sample('boda-marfil');
    expect(inv.template, 'boda-marfil');
    expect(invitationTemplate('boda-marfil').name, 'Marfil & Oro');

    final html = buildInvitationHtml(inv);
    expect(html, contains('mf-names'));
    expect(html, contains('Ana &amp; Luis'));
    expect(html, contains('mf-countdown'));
    expect(html, contains('confirmarAsistencia'));
    // Portada con sobre animado y RSVP en línea.
    expect(html, contains('class="env-flap"'));
    expect(html, contains('class="cover-hit"'));
    expect(html, contains('class="cover-flowers"'));
    expect(html, isNot(contains('cover-rsvp')));
    // El lugar y el código de vestimenta salen en las tarjetas de detalles.
    expect(html, contains('El lugar'));
    expect(html, contains('Código de vestimenta'));
    expect(html, isNot(contains('class="mf-details-media"')));

    final custom = inv.copyWith(
      accent: '#123456',
      bgColor: '#F0E0D0',
      detailsMedia: 'https://drive.test/files/detalles.jpg',
    );
    final customHtml = buildInvitationHtml(custom);
    expect(customHtml, contains('--gold: #123456'));
    expect(customHtml, contains('--paper: #F0E0D0'));
    // El tema propio debe quedar DESPUÉS del CSS base de Marfil para ganar.
    expect(
      customHtml.indexOf('--gold: #123456'),
      greaterThan(customHtml.indexOf('--gold: #B99A63')),
    );
    expect(
      customHtml.indexOf('--paper: #F0E0D0'),
      greaterThan(customHtml.indexOf('--paper: #F8F3E7')),
    );
    expect(customHtml, contains('class="mf-details-media"'));
    expect(customHtml, contains('mf-details-content'));
    expect(customHtml, contains('https://drive.test/files/detalles.jpg'));

    final detailsVideo = buildInvitationHtml(
      inv.copyWith(detailsMedia: 'https://drive.test/files/detalles.mp4'),
    );
    expect(
      detailsVideo,
      contains('class="mf-details-media" aria-hidden="true"><video'),
    );
    // Con movimiento reducido la apertura se mantiene completa; solo se
    // apagan los efectos ambientales.
    expect(html, contains('var revealAt = isCarta ? 1850 : 1450;'));
    expect(html, contains('var hideAt = isCarta ? 2800 : 2350;'));
    expect(html, isNot(contains('reduce ? 850')));
    expect(
      html,
      contains('.env-flap { transition-duration: 1.05s !important; }'),
    );
    expect(html, contains('transition-duration: 1.15s !important'));
    // No es la maqueta de ReynaCoot: tiene documento propio.
    expect(html, isNot(contains('main-card')));

    // El acento del editor manda en el dorado.
    final own = inv.copyWith(accent: 'B76E79');
    expect(buildInvitationHtml(own), contains('--gold: #B76E79'));
  });

  test('el orden de las capas se aplica al HTML de Marfil', () {
    final inv = Invitation.sample('boda-marfil').copyWith(
      families: const [
        InvitationFamily(title: 'Padres', names: ['Ana', 'Luis']),
      ],
      details: const [
        InvitationDetail(title: 'Misa', place: 'Iglesia Santa Úrsula'),
      ],
      itinerary: const [InvitationStop(time: '7:30 pm', title: 'Cena')],
      hashtag: '#AnaYLuis',
      sectionOrder: const [
        'footer',
        'details',
        'families',
        'hashtag',
        'itinerary',
      ],
    );
    final html = buildInvitationHtml(inv);
    final footer = html.indexOf('<footer class="mf-footer">');
    final details = html.indexOf('<section class="mf-details-section');
    final families = html.indexOf('<section class="mf-families-section');
    final hashtag = html.indexOf('<section class="mf-hashtag section">');
    final itinerary = html.indexOf('<section class="mf-day-section');

    expect(footer, greaterThanOrEqualTo(0));
    expect(details, greaterThanOrEqualTo(0));
    expect(families, greaterThanOrEqualTo(0));
    expect(hashtag, greaterThanOrEqualTo(0));
    expect(itinerary, greaterThanOrEqualTo(0));
    expect(footer, lessThan(details));
    expect(details, lessThan(families));
    expect(families, lessThan(hashtag));
    expect(hashtag, lessThan(itinerary));
  });

  test('las capas también ordenan el HTML de ReynaCoot', () {
    final inv = Invitation.sample('sobre-xv').copyWith(
      families: const [
        InvitationFamily(title: 'FAMILIA_UNICA', names: ['Ana']),
      ],
      details: const [InvitationDetail(title: 'DETALLE_UNICO')],
      itinerary: const [InvitationStop(time: '7:30', title: 'PROGRAMA_UNICO')],
      hashtag: '#HASH_UNICO',
      footerMessage: 'CIERRE_UNICO',
      sectionOrder: const [
        'footer',
        'details',
        'hashtag',
        'itinerary',
        'families',
      ],
    );
    final html = buildInvitationHtml(inv);
    int at(String value) => html.indexOf(value);

    expect(at('CIERRE_UNICO'), greaterThanOrEqualTo(0));
    expect(at('DETALLE_UNICO'), greaterThanOrEqualTo(0));
    expect(at('#HASH_UNICO'), greaterThanOrEqualTo(0));
    expect(at('PROGRAMA_UNICO'), greaterThanOrEqualTo(0));
    expect(at('FAMILIA_UNICA'), greaterThanOrEqualTo(0));
    expect(at('CIERRE_UNICO'), lessThan(at('DETALLE_UNICO')));
    expect(at('DETALLE_UNICO'), lessThan(at('#HASH_UNICO')));
    expect(at('#HASH_UNICO'), lessThan(at('PROGRAMA_UNICO')));
    expect(at('PROGRAMA_UNICO'), lessThan(at('FAMILIA_UNICA')));
  });

  test('el ejemplo de XV no repite el arco en el subtítulo', () {
    final inv = Invitation.sample('sobre-xv');
    expect(inv.subheadline, isNot('Mis XV Años'));
    expect(
      buildInvitationHtml(inv),
      contains('Estás invitad@ a celebrar conmigo'),
    );
  });

  test('la animación elegida cambia los efectos del HTML', () {
    final bubbles = Invitation.sample('sobre-xv').copyWith(effect: 'burbujas');
    final html = buildInvitationHtml(bubbles);
    expect(html, contains('hsBubble'));
    expect(html, contains('border-radius: 50%'));

    final none = Invitation.sample('sobre-xv').copyWith(effect: 'ninguno');
    expect(buildInvitationHtml(none), contains('display: none !important'));

    // La elección viaja en el diseño para reabrir el editor igual.
    final back = Invitation.fromJson(bubbles.toJson());
    expect(back.effect, 'burbujas');
  });

  test('Marfil & Oro tiene las interacciones de la invitación', () {
    final inv = Invitation.sample('boda-marfil').copyWith(
      photos: const [
        'https://drive.test/files/boda/uno.jpg',
        'https://drive.test/files/boda/dos.jpg',
        'https://drive.test/files/boda/tres.jpg',
      ],
    );
    final html = buildInvitationHtml(inv);

    // Portada e inicio con monograma, progreso y pista de scroll.
    expect(html, contains('id="mf-progress"'));
    expect(
      html,
      contains(
        '<div class="mf-monogram" aria-hidden="true"><span>AL</span></div>',
      ),
    );
    expect(html, contains('Desliza para descubrir'));
    expect(html, isNot(contains('{{HERO_MONOGRAM}}')));

    // Fotos con visor completo.
    expect(html, contains('class="mf-photo" role="button" tabindex="0"'));
    expect(html, contains('aria-label="Ver foto 1"'));
    expect(html, contains('class="mf-photo-zoom"'));
    expect(html, contains('id="mf-lightbox"'));
    expect(html, contains('id="mf-lightbox-img"'));
    expect(html, contains('function openMfPhoto'));
    expect(html, contains('function closeMfPhoto'));

    // Animaciones e interacción al abrir, al hacer scroll y al confirmar.
    expect(html, contains('function showProgress'));
    expect(html, contains('function updateProgress'));
    expect(html, contains('function celebrate'));
    expect(html, contains('function observeSections'));
    expect(html, contains('mf-reveal'));
    expect(html, contains('mf-tick'));
    expect(html, contains('mf-burst-piece'));
    expect(
      html,
      contains(
        "document.addEventListener('DOMContentLoaded', initMfInteractions)",
      ),
    );
  });
}

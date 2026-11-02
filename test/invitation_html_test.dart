import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/invitation_html.dart';
import 'package:hardstreet_admin/invitation_model.dart';

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
    expect(kInvitationTemplates.first.name, 'ReynaCoot');
    expect(kInvitationTemplates[1].key, 'boda-marfil');
    expect(kInvitationTemplates[1].name, 'Marfil & Oro');
    expect(invitationCatalog().length, 2);
    expect(invitationCatalog().first.templates.length, 1);
    // Una invitación vieja con otra plantilla cae en ReynaCoot.
    expect(invitationTemplate('plantilla-borrada').key, 'sobre-xv');
    expect(Invitation.sample('boda-jardin').design.occasion, 'XV');
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
    expect(html, contains('function startCountdown()'));
  });

  test('las secciones apagadas no se dibujan y sin portada abre directo', () {
    final inv = Invitation.sample('sobre-xv')
        .copyWith(sections: const ['details', 'footer']);
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
      sections: const ['cover', 'details'],
      hashtag: '#ReynaXV2026',
    );
    final json = inv.toJson();
    final design = (json['design'] as Map).cast<String, dynamic>();
    expect(design['bgMedia'], 'https://drive.test/video.mp4');
    expect(design['detailsMedia'], 'https://drive.test/detalles.jpg');
    expect(design['bgColor'], '#E8CFCD');
    expect(design['sections'], ['cover', 'details']);

    final back = Invitation.fromJson(json);
    expect(back.bgMedia, 'https://drive.test/video.mp4');
    expect(back.detailsMedia, 'https://drive.test/detalles.jpg');
    expect(back.bgColor, '#E8CFCD');
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
      inv.copyWith(
        detailsMedia: 'https://drive.test/files/detalles.mp4',
      ),
    );
    expect(
      detailsVideo,
      contains('class="mf-details-media" aria-hidden="true"><video'),
    );
    // Con movimiento reducido la apertura se mantiene completa; solo se
    // apagan los efectos ambientales.
    expect(html, contains('}, 1450);'));
    expect(html, contains('}, 2350);'));
    expect(html, isNot(contains('reduce ? 850')));
    expect(html, contains('.env-flap { transition-duration: 1.05s !important; }'));
    expect(html, contains('transition-duration: 1.15s !important'));
    // No es la maqueta de ReynaCoot: tiene documento propio.
    expect(html, isNot(contains('main-card')));

    // El acento del editor manda en el dorado.
    final own = inv.copyWith(accent: 'B76E79');
    expect(buildInvitationHtml(own), contains('--gold: #B76E79'));
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
}

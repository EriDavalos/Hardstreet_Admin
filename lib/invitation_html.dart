import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'invitation_carta_portada.dart';
import 'invitation_components/components_css.dart';
import 'invitation_marfil.dart';
import 'invitation_model.dart';
import 'invitation_reynacoot.dart';

// ==================================================================
// HTML DE LA INVITACIÓN — el documento original de ReynaCoot
// ==================================================================
// Lo que se guarda y se sirve en /i/<liga> es el MISMO documento de
// Hardstreet/ReynaCoot: su index.html, su index.css y su index.js, con los
// datos de la invitación sustituidos en su sitio. No hay una maqueta
// paralela: el sobre, la guirnalda, la tiara, las polaroids, la cuenta
// regresiva, las cintas, el confeti y el botón de música son los originales.
//
// Los únicos cambios sobre el original son los datos (nombres, fecha,
// fotos, textos, WhatsApp, música) y el acento si el usuario elige otro.
// ==================================================================

/// El HTML completo que se sirve en `/i/<liga>`.
String buildInvitationHtml(Invitation inv) {
  // Cada plantilla tiene su PROPIO documento HTML; comparten los datos.
  if (inv.template.trim() == 'boda-marfil') return _buildMarfilHtml(inv);
  final t = inv.design;
  final accent = inv.accentHex;
  final name = inv.displayTitle.trim();
  final occasion = inv.occasion.trim().isEmpty
      ? t.occasion
      : inv.occasion.trim();
  final event = inv.eventDate;
  final parts = event == null ? null : invitationDateParts(event);
  final photos = <String>[
    for (final p in inv.photos)
      if (isHttpUrl(p)) p.trim(),
  ];
  final music = isHttpUrl(inv.musicUrl) && inv.sectionOn('music')
      ? inv.musicUrl.trim()
      : '';
  final bgMedia = isHttpUrl(inv.bgMedia) ? inv.bgMedia.trim() : '';
  final coverOn = inv.sectionOn('cover');
  final coverStyle = inv.coverStyleKey;
  final wa = inv.rsvpPhone.replaceAll(RegExp(r'[^0-9]'), '');
  final waOk = wa.length >= 8;
  final dateText = inv.dateText.trim();
  final quote = inv.quoteText.trim();
  final hashtag = inv.hashtag.trim();

  final flowBlocks = <String, String>{
    'families': inv.sectionOn('families')
        ? invitationComponentBlock(
            inv,
            'families',
            _families(
              inv.families,
              _textOr(inv.familiesTitle, _defaultFamiliesTitle),
            ),
          )
        : '',
    'details': inv.sectionOn('details')
        ? invitationComponentBlock(
            inv,
            'details',
            _details(
              inv,
              waOk && inv.sectionOn('rsvp'),
              _textOr(inv.detailsTitle, _defaultDetailsTitle),
              _textOr(inv.detailsIntro, _defaultDetailsIntro),
            ),
          )
        : '',
    'hashtag': inv.sectionOn('hashtag')
        ? invitationComponentBlock(
            inv,
            'hashtag',
            _hashtag(hashtag, _textOr(inv.hashtagIntro, _defaultHashtagIntro)),
          )
        : '',
    'itinerary': inv.sectionOn('itinerary')
        ? invitationComponentBlock(
            inv,
            'itinerary',
            _itinerary(
              inv.itinerary,
              _textOr(inv.itineraryTitle, _defaultItineraryTitle),
            ),
          )
        : '',
    'footer': inv.sectionOn('footer')
        ? invitationComponentBlock(
            inv,
            'footer',
            _footer(name, _textOr(inv.footerMessage, _defaultFooterMessage)),
          )
        : '',
  };

  final desc = [
    inv.subheadline,
    dateText,
    inv.timeText,
    inv.placeName,
    inv.placeAddress,
  ].map((s) => s.trim()).where((s) => s.isNotEmpty).join(' · ');
  final description = desc.isEmpty ? 'Te comparto mi invitación' : desc;

  final envDate = parts == null
      ? (dateText.isEmpty ? 'Fecha por confirmar' : dateText)
      : '${_cap(parts.weekday)} ${parts.day} · '
            '${_cap(parts.month)} ${parts.year}';
  final thanksDate = parts == null
      ? (dateText.isEmpty ? 'pronto' : dateText)
      : '${parts.day} de ${parts.month}';
  final pageBg = colorOfHex(inv.bgColor);
  final css = _recolor(kReynaCootCss, accent, pageBg: pageBg);
  final js = _recolor(kReynaCootJs, accent);

  final head = StringBuffer()
    ..writeln('<meta charset="UTF-8" />')
    ..writeln('<meta name="referrer" content="no-referrer" />')
    ..writeln(
      '<meta name="viewport" content="width=device-width, initial-scale=1.0" />',
    )
    ..writeln('<title>${_esc(name)} · ${_esc(occasion)}</title>')
    ..writeln('<meta name="description" content="${_attr(description)}" />')
    ..writeln('<meta property="og:type" content="website" />')
    ..writeln(
      '<meta property="og:title" content="${_attr('$name · $occasion')}" />',
    )
    ..writeln(
      '<meta property="og:description" content="${_attr(description)}" />',
    )
    ..writeln(
      '<meta name="twitter:card" '
      'content="${photos.isEmpty ? 'summary' : 'summary_large_image'}" />',
    )
    ..writeln(
      '<meta name="twitter:title" content="${_attr('$name · $occasion')}" />',
    )
    ..writeln(
      '<meta name="twitter:description" content="${_attr(description)}" />',
    );
  if (photos.isNotEmpty) {
    head
      ..writeln('<meta property="og:image" content="${_attr(photos.first)}" />')
      ..writeln(
        '<meta name="twitter:image" content="${_attr(photos.first)}" />',
      );
  }
  head.writeln(
    '<link href="https://fonts.googleapis.com/css2?family=Great+Vibes'
    '&family=Cormorant+Garamond:ital,wght@0,300;0,400;0,600;1,300;1,400;'
    '1,600&family=Playfair+Display:wght@400;600;700&family=Inter:wght@300;'
    '400;500;600&display=swap" rel="stylesheet" />',
  );

  final body = _inject(kReynaCootBody, {
    'ENVELOPE_STYLE': coverOn ? '' : ' style="display:none"',
    'COVER_MEDIA': _coverMedia(bgMedia),
    'COVER_DESIGN': coverOn
        ? _coverDesign(
            inv,
            envDate: envDate,
            envelopeText: _textOr(inv.envelopeText, 'Tienes una invitación'),
            occasion: occasion,
            bgMedia: bgMedia,
          )
        : '',
    'ENVELOPE_TEXT': _esc(_textOr(inv.envelopeText, 'Tienes una invitación')),
    'ENVELOPE_NAME': _esc(name),
    'ENVELOPE_DATE': _esc(envDate),
    'INV_CLASS': coverOn ? 'invitation' : 'invitation open',
    'VERTICAL_TITLE': _esc(_verticalTitle(inv, occasion)),
    'ARC_TEXT': _esc(_arcText(inv, occasion)),
    'MAIN_NAME': _esc(name),
    'INVITE_SUB': _esc(
      inv.subheadline.trim().isEmpty
          ? 'Estás invitad@ a celebrar conmigo'
          : inv.subheadline.trim(),
    ),
    'DATE_CAPSULE': _dateCapsule(inv),
    'POLAROIDS': inv.sectionOn('photos')
        ? invitationComponentBlock(inv, 'photos', _polaroids(photos))
        : '',
    'QUOTE': quote.isEmpty || !inv.sectionOn('quote')
        ? ''
        : invitationComponentBlock(inv, 'quote', _quoteBox(quote)),
    'COUNTDOWN': event != null && inv.sectionOn('countdown')
        ? invitationComponentBlock(inv, 'countdown', _countdown())
        : '',
    'FLOW_SECTIONS': [
      for (final key in inv.flowSectionOrder) flowBlocks[key] ?? '',
    ].join(),
    'THANKS_DATE': _esc(thanksDate),
    'AUDIO': music.isEmpty
        ? ''
        : '<audio id="bg-music" src="${_attr(music)}" preload="auto" '
              'loop></audio>',
    'MUSIC_BTN': music.isEmpty
        ? ''
        : invitationComponentBlock(
            inv,
            'music',
            '<button class="music-btn" id="music-btn" '
                'onclick="toggleMusic()" title="Música" '
                'aria-label="Reproducir o pausar música">🎵</button>',
          ),
  });

  final html =
      '''
<!DOCTYPE html>
<html lang="es">
<head>
$head<style>
$css
${_extraCss(inv)}
${invitationComponentCss(inv)}
${_coverDesignCss(inv)}
</style>
</head>
<body class="hs-cover-$coverStyle hs-template-rosa hs-cover-custom">
$body
${_dataScript(name, envDate, event, waOk ? wa : '')}
<script>
$js
</script>
${coverOn ? '' : _autoOpen}
</body>
</html>
''';
  assert(
    !RegExp(r'\{\{[A-Z_]+\}\}').hasMatch(html),
    'Quedó un marcador sin reemplazar en el HTML',
  );
  return html;
}

// ------------------------------------------------------------------
// PLANTILLA «MARFIL & ORO»
// ------------------------------------------------------------------
// Mismos datos y mismos efectos de ambiente que ReynaCoot, pero con un
// documento propio: papel marfil, dorado, sobre con sello de cera y
// programa del día. Se elige al crear la invitación.

String _buildMarfilHtml(Invitation inv) {
  final name = inv.displayTitle.trim();
  final occasion = inv.occasion.trim().isEmpty ? 'Boda' : inv.occasion.trim();
  final event = inv.eventDate;
  final parts = event == null ? null : invitationDateParts(event);
  final photos = <String>[
    for (final p in inv.photos)
      if (isHttpUrl(p)) p.trim(),
  ];
  final music = isHttpUrl(inv.musicUrl) && inv.sectionOn('music')
      ? inv.musicUrl.trim()
      : '';
  final bgMedia = isHttpUrl(inv.bgMedia) ? inv.bgMedia.trim() : '';
  final coverOn = inv.sectionOn('cover');
  final coverStyle = inv.coverStyleKey;
  final wa = inv.rsvpPhone.replaceAll(RegExp(r'[^0-9]'), '');
  final waOk = wa.length >= 8;
  final dateText = inv.dateText.trim();
  final time = inv.timeText.trim();
  final quote = inv.quoteText.trim();
  final hashtag = inv.hashtag.trim();
  final accent = inv.accentColor;
  final paper = inv.backgroundColor;
  final paperAlt = Color.lerp(paper, accent, .10)!;
  final goldDeep = Color.lerp(accent, const Color(0xFF2E2820), .30)!;
  final detailsMedia = isHttpUrl(inv.detailsMedia)
      ? inv.detailsMedia.trim()
      : '';
  final pageMedia = bgMedia;

  final flowBlocks = <String, String>{
    'families': inv.sectionOn('families')
        ? invitationComponentBlock(
            inv,
            'families',
            _mfFamilies(
              inv.families,
              _textOr(inv.familiesTitle, 'Con la bendición de'),
            ),
          )
        : '',
    'details': inv.sectionOn('details')
        ? invitationComponentBlock(
            inv,
            'details',
            _mfDetails(
              inv,
              _textOr(inv.detailsTitle, 'Los detalles'),
              _textOr(inv.detailsIntro, 'Todo lo que necesitas saber'),
              detailsMedia,
            ),
          )
        : '',
    'hashtag': inv.sectionOn('hashtag')
        ? invitationComponentBlock(
            inv,
            'hashtag',
            _mfHashtag(
              hashtag,
              _textOr(inv.hashtagIntro, 'Comparte tus fotos con'),
            ),
          )
        : '',
    'itinerary': inv.sectionOn('itinerary')
        ? invitationComponentBlock(
            inv,
            'itinerary',
            _mfItinerary(inv.itinerary, _textOr(inv.itineraryTitle, 'El día')),
          )
        : '',
    'footer': inv.sectionOn('footer')
        ? invitationComponentBlock(
            inv,
            'footer',
            _mfFooter(name, _textOr(inv.footerMessage, _defaultFooterMessage)),
          )
        : '',
  };
  String flowAt(int i) {
    final order = inv.flowSectionOrder;
    return i < order.length ? flowBlocks[order[i]] ?? '' : '';
  }

  final dateLine = parts == null
      ? [dateText, time].where((s) => s.isNotEmpty).join(' · ')
      : '${_cap(parts.weekday)} ${parts.day} de ${parts.month} de '
            '${parts.year}${time.isEmpty ? '' : ' · $time'}';
  final envDate = parts == null
      ? (dateText.isEmpty ? 'Fecha por confirmar' : dateText)
      : '${_cap(parts.weekday)} ${parts.day} · '
            '${_cap(parts.month)} ${parts.year}';
  final thanksDate = parts == null
      ? (dateText.isEmpty ? 'pronto' : dateText)
      : '${parts.day} de ${parts.month}';
  final desc = [
    inv.subheadline,
    dateText,
    time,
    inv.placeName,
    inv.placeAddress,
  ].map((s) => s.trim()).where((s) => s.isNotEmpty).join(' · ');
  final description = desc.isEmpty ? 'Te comparto mi invitación' : desc;

  final body = _inject(kMarfilBody, {
    'ENVELOPE_STYLE': coverOn ? '' : ' style="display:none"',
    'COVER_MEDIA': _mfCoverMedia(bgMedia),
    'COVER_DESIGN': coverOn
        ? _coverDesign(
            inv,
            envDate: envDate,
            envelopeText: _textOr(
              inv.envelopeText,
              'Estás cordialmente invitado',
            ),
            occasion: occasion,
            bgMedia: bgMedia,
          )
        : '',
    'ENVELOPE_TEXT': _esc(
      _textOr(inv.envelopeText, 'Estás cordialmente invitado'),
    ),
    'ENVELOPE_NAME': _esc(name),
    'ENVELOPE_DATE': _esc(envDate),
    'SEAL': _esc(_initials(name)),
    'INV_CLASS': coverOn ? 'invitation' : 'invitation open',
    'HERO_MONOGRAM': _esc(_initials(name)),
    'ARC_TEXT': _esc(_arcText(inv, occasion)),
    'MAIN_NAME': _esc(name),
    'INVITE_SUB': _esc(
      inv.subheadline.trim().isEmpty ? 'Nos casamos' : inv.subheadline.trim(),
    ),
    'DATE_LINE': _esc(dateLine),
    'COUNTDOWN': event != null && inv.sectionOn('countdown')
        ? invitationComponentBlock(inv, 'countdown', _mfCountdown())
        : '',
    'FLOW_0': flowAt(0),
    'QUOTE': quote.isEmpty || !inv.sectionOn('quote')
        ? ''
        : invitationComponentBlock(inv, 'quote', _mfQuote(quote)),
    'FLOW_1': flowAt(1),
    'FLOW_2': flowAt(2),
    'PHOTOS': inv.sectionOn('photos')
        ? invitationComponentBlock(inv, 'photos', _mfPhotos(photos))
        : '',
    'FLOW_3': flowAt(3),
    'RSVP': waOk && inv.sectionOn('rsvp')
        ? invitationComponentBlock(inv, 'rsvp', _mfRsvp(thanksDate))
        : '',
    'FLOW_4': flowAt(4),
    'THANKS_DATE': _esc(thanksDate),
    'AUDIO': music.isEmpty
        ? ''
        : '<audio id="bg-music" src="${_attr(music)}" preload="auto" '
              'loop></audio>',
    'MUSIC_BTN': music.isEmpty
        ? ''
        : invitationComponentBlock(
            inv,
            'music',
            '<button class="music-btn" id="music-btn" '
                'onclick="toggleMusic()" title="Música" '
                'aria-label="Reproducir o pausar música">'
                '<svg viewBox="0 0 24 24" fill="currentColor" '
                'aria-hidden="true"><path d="M20 4.6v10.2a3 3 0 1 1-1.5-2.6V7.1l-8 '
                '1.7v8.3a3 3 0 1 1-1.5-2.6V5.7a1 1 0 0 1 .76-.97l9-1.9A1 '
                '1 0 0 1 20 4.6Z"/></svg></button>',
          ),
  });

  final head = StringBuffer()
    ..writeln('<meta charset="UTF-8" />')
    ..writeln('<meta name="referrer" content="no-referrer" />')
    ..writeln(
      '<meta name="viewport" content="width=device-width, initial-scale=1.0" />',
    )
    ..writeln('<title>${_esc(name)} · ${_esc(occasion)}</title>')
    ..writeln('<meta name="description" content="${_attr(description)}" />')
    ..writeln('<meta property="og:type" content="website" />')
    ..writeln(
      '<meta property="og:title" content="${_attr('$name · $occasion')}" />',
    )
    ..writeln(
      '<meta property="og:description" content="${_attr(description)}" />',
    )
    ..writeln(
      '<meta name="twitter:card" '
      'content="${photos.isEmpty ? 'summary' : 'summary_large_image'}" />',
    )
    ..writeln(
      '<meta name="twitter:title" content="${_attr('$name · $occasion')}" />',
    )
    ..writeln(
      '<meta name="twitter:description" content="${_attr(description)}" />',
    );
  if (photos.isNotEmpty) {
    head
      ..writeln('<meta property="og:image" content="${_attr(photos.first)}" />')
      ..writeln(
        '<meta name="twitter:image" content="${_attr(photos.first)}" />',
      );
  }
  head.writeln(
    '<link href="https://fonts.googleapis.com/css2?family=Italiana'
    '&family=Cormorant+Garamond:ital,wght@0,300;0,400;0,500;0,600;1,300;'
    '1,400&family=Great+Vibes&family=Inter:wght@300;400;500;600&display=swap" '
    'rel="stylesheet" />',
  );

  final theme =
      '''
:root {
  --gold: ${colorHex(accent)};
  --gold-deep: ${colorHex(goldDeep)};
  --paper: ${colorHex(paper)};
  --paper-2: ${colorHex(paperAlt)};
  --line: rgba(${_rgb(accent)}, .45);
}''';

  final html =
      '''
<!DOCTYPE html>
<html lang="es">
<head>
$head<style>
$kMarfilCss
$theme
${_effectCss(inv)}
${invitationComponentCss(inv)}
${_coverDesignCss(inv)}
</style>
</head>
<body${coverOn ? ' class="at-cover ' : ' class="'}hs-cover-$coverStyle hs-template-marfil hs-cover-custom${pageMedia.isEmpty ? '' : ' mf-has-page-bg'}">
${pageMedia.isEmpty ? '' : _mfPageMedia(pageMedia)}
$body
${_dataScript(name, envDate, event, waOk ? wa : '')}
<script>
$kMarfilJs
</script>
${coverOn ? '' : _autoOpen}
</body>
</html>
''';
  assert(
    !RegExp(r'\{\{[A-Z_]+\}\}').hasMatch(html),
    'Quedó un marcador sin reemplazar en el HTML de Marfil & Oro',
  );
  return html;
}

String _mfCoverMedia(String url) {
  if (url.isEmpty) return '';
  if (isVideoUrl(url)) {
    return '<div class="mf-cover-media"><video src="${_attr(url)}" '
        'autoplay muted loop playsinline></video></div>';
  }
  return '<div class="mf-cover-media"><img src="${_attr(url)}" alt="" />'
      '</div>';
}

String _initials(String name) {
  final words = name
      .split(RegExp(r'[\s&y]+'))
      .where((w) => w.trim().isNotEmpty)
      .toList();
  if (words.isEmpty) return 'HS';
  final out = StringBuffer();
  for (final w in words.take(3)) {
    out.write(w[0].toUpperCase());
  }
  return out.toString();
}

String _mfCountdown() => '''
<section class="mf-countdown section">
  <p class="mf-count-script">El tiempo vuela</p>
  <div class="mf-count-row">
    <div class="mf-count-box"><span class="mf-count-num" id="days">--</span><span class="mf-count-lab">Días</span></div>
    <div class="mf-count-box"><span class="mf-count-num" id="hours">--</span><span class="mf-count-lab">Horas</span></div>
    <div class="mf-count-box"><span class="mf-count-num" id="minutes">--</span><span class="mf-count-lab">Minutos</span></div>
    <div class="mf-count-box"><span class="mf-count-num" id="seconds">--</span><span class="mf-count-lab">Segundos</span></div>
  </div>
</section>''';

String _mfItinerary(List<InvitationStop> stops, String title) {
  final items = <String>[];
  for (final s in stops) {
    if (s.isEmpty) continue;
    items.add('''
    <div class="mf-stop">
      <span class="mf-dot"></span>
      ${s.time.trim().isEmpty ? '' : '<span class="mf-stop-time">${_esc(s.time.trim())}</span>'}
      <span class="mf-stop-title">${_esc(s.title.trim())}</span>
    </div>''');
  }
  if (items.isEmpty) return '';
  return '''
<section class="mf-day-section section">
  <div class="mf-head">
    <span class="mf-script">${_esc(title)}</span>
    <span class="mf-kicker">El programa</span>
    <span class="mf-rule"></span>
  </div>
  <div class="mf-day">
${items.join('\n')}
  </div>
</section>''';
}

String _mfQuote(String quote) =>
    '''
<section class="mf-quote-section section">
  <span class="mf-quote-mark">“</span>
  <p>${_esc(quote)}</p>
</section>''';

String _mfDetails(Invitation inv, String title, String intro, String media) {
  final cards = <String>[];
  for (final d in inv.details) {
    if (d.isEmpty) continue;
    final b = StringBuffer(
      '''
    <article class="mf-card">
      <svg class="mf-mark" viewBox="-14 -14 28 28" aria-hidden="true"><use href="#mf-spark" /></svg>''',
    );
    b.write(
      '\n      <h3>${_esc(d.title.trim().isEmpty ? 'Detalle' : d.title.trim())}</h3>',
    );
    if (d.time.trim().isNotEmpty) {
      b.write('\n      <p class="mf-time">${_esc(d.time.trim())}</p>');
    }
    if (d.place.trim().isNotEmpty) {
      b.write('\n      <p class="mf-place">${_esc(d.place.trim())}</p>');
    }
    if (d.note.trim().isNotEmpty) {
      b.write('\n      <p class="mf-note">${_esc(d.note.trim())}</p>');
    }
    if (isHttpUrl(d.mapUrl)) {
      b.write(
        '\n      <a class="mf-link" href="${_attr(d.mapUrl.trim())}">'
        'Ver ubicación</a>',
      );
    }
    b.write('\n    </article>');
    cards.add(b.toString());
  }
  final place = inv.placeName.trim();
  final address = inv.placeAddress.trim();
  if (place.isNotEmpty || address.isNotEmpty) {
    final query = [place, address].where((s) => s.isNotEmpty).join(', ');
    cards.add('''
    <article class="mf-card">
      <svg class="mf-mark" viewBox="-14 -14 28 28" aria-hidden="true"><use href="#mf-spark" /></svg>
      <h3>El lugar</h3>
      ${place.isEmpty ? '' : '<p class="mf-place">${_esc(place)}</p>'}
      ${address.isEmpty ? '' : '<p class="mf-note">${_esc(address)}</p>'}
      <a class="mf-link" href="${_attr('https://maps.google.com/?q=${Uri.encodeComponent(query)}')}">Ver ubicación</a>
    </article>''');
  }
  if (inv.dressCode.trim().isNotEmpty) {
    cards.add('''
    <article class="mf-card">
      <svg class="mf-mark" viewBox="-14 -14 28 28" aria-hidden="true"><use href="#mf-spark" /></svg>
      <h3>Código de vestimenta</h3>
      <p class="mf-place">${_esc(inv.dressCode.trim())}</p>
    </article>''');
  }
  if (cards.isEmpty) return '';
  final layer = _mfDetailsMedia(media);
  return '''
<section class="mf-details-section section${layer.isEmpty ? '' : ' mf-has-media'}">
$layer
  <div class="mf-details-content">
    <div class="mf-head">
      <span class="mf-script">${_esc(title)}</span>
      <span class="mf-kicker">${_esc(intro)}</span>
      <span class="mf-rule"></span>
    </div>
    <div class="mf-details">
${cards.join('\n')}
    </div>
  </div>
</section>''';
}

/// Foto o vídeo de fondo de toda la invitación: va fijo detrás del contenido.
String _mfPageMedia(String url) {
  if (isVideoUrl(url)) {
    return '<div class="mf-page-media" aria-hidden="true">'
        '<video src="${_attr(url)}" autoplay muted loop playsinline></video>'
        '</div>';
  }
  return '<div class="mf-page-media" aria-hidden="true"><img src="${_attr(url)}" alt="" /></div>';
}

String _mfDetailsMedia(String url) {
  if (url.isEmpty) return '';
  if (isVideoUrl(url)) {
    return '  <div class="mf-details-media" aria-hidden="true">'
        '<video src="${_attr(url)}" autoplay muted loop playsinline></video>'
        '</div>';
  }
  return '  <div class="mf-details-media" aria-hidden="true">'
      '<img src="${_attr(url)}" alt="" /></div>';
}

String _mfFamilies(List<InvitationFamily> families, String title) {
  final blocks = <String>[];
  for (final f in families) {
    if (f.isEmpty) continue;
    final names = f.names
        .where((n) => n.trim().isNotEmpty)
        .map((n) => _esc(n.trim()))
        .join('<br />');
    blocks.add('''
    <div class="mf-family">
      ${f.title.trim().isEmpty ? '' : '<h3>${_esc(f.title.trim())}</h3>'}
      <p>$names</p>
    </div>''');
  }
  if (blocks.isEmpty) return '';
  return '''
<section class="mf-families-section section">
  <div class="mf-head">
    <span class="mf-script">${_esc(title)}</span>
    <span class="mf-kicker">Familia</span>
    <span class="mf-rule"></span>
  </div>
  <div class="mf-families">
${blocks.join('\n')}
  </div>
</section>''';
}

String _mfPhotos(List<String> photos) {
  if (photos.isEmpty) return '';
  final b = StringBuffer('\n<div class="mf-photos">');
  for (var i = 0; i < math.min(3, photos.length); i++) {
    b.write(
      '\n  <figure class="mf-photo" role="button" tabindex="0" '
      'aria-label="Ver foto ${i + 1}">'
      '<img src="${_attr(photos[i])}" alt="Foto ${i + 1}" loading="lazy" />'
      '<span class="mf-photo-zoom" aria-hidden="true">Ver foto '
      '<b>&#8599;</b></span></figure>',
    );
  }
  b.write('\n</div>');
  return b.toString();
}

String _mfHashtag(String tag, String intro) {
  if (tag.isEmpty) return '';
  return '''
<section class="mf-hashtag section">
  <p class="mf-hashtag-script">${_esc(intro)}</p>
  <p class="mf-tag">${_esc(tag)}</p>
</section>''';
}

String _mfRsvp(String thanksDate) =>
    '''
<section class="mf-rsvp section" id="rsvp">
  <div class="mf-head">
    <span class="mf-script">Confirma tu asistencia</span>
    <span class="mf-kicker">RSVP</span>
    <span class="mf-rule"></span>
  </div>
  <p class="mf-rsvp-text">Tu presencia es lo más importante. Confirma antes del ${_esc(thanksDate)} para reservar tu lugar.</p>
  <button class="mf-cta" onclick="confirmarAsistencia(event)">Confirmar por WhatsApp</button>
</section>''';

String _mfFooter(String name, String message) {
  final lines = message
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .map(_esc)
      .join('<br />\n    ');
  return '''
<footer class="mf-footer">
  <div class="petals-bg"><div class="petal"></div><div class="petal"></div><div class="petal"></div></div>
  <p class="mf-footer-names">${_esc(name)}</p>
  <p class="mf-footer-msg">$lines</p>
  <p class="mf-credit">Invitación hecha con amor por <a href="https://hardstreet.com">Hardstreet</a></p>
</footer>''';
}

// ------------------------------------------------------------------
// Piezas que el HTML original tiene fijas y aquí salen de los datos
// ------------------------------------------------------------------

String _dateCapsule(Invitation inv) {
  final date = inv.eventDate;
  final p = date == null ? null : invitationDateParts(date);
  if (p == null) {
    final text = inv.dateText.trim().isEmpty
        ? 'Fecha por confirmar'
        : inv.dateText.trim();
    return '''
            <div class="date-capsule">
              <span class="dc-day"><span class="dc-flourish">✦</span>${_esc(text.toUpperCase())}<span class="dc-flourish">✦</span></span>
            </div>''';
  }
  return '''
            <div class="date-capsule">
              <span class="dc-day"><span class="dc-flourish">✦</span>${_esc(p.weekday.toUpperCase())}<span class="dc-flourish">✦</span></span>
              <div class="dc-row">
                <span class="dc-circle">${p.day}</span>
                <span class="dc-rest">${_esc(p.month.toUpperCase())}<span class="dc-dot">·</span>${p.year}</span>
              </div>
            </div>''';
}

String _polaroids(List<String> photos) {
  if (photos.isEmpty) return '';
  const classes = ['p1', 'p2', 'p3'];
  final b = StringBuffer('\n        <div class="polaroids">');
  for (var i = 0; i < math.min(3, photos.length); i++) {
    b.write(
      '\n          <figure class="polaroid ${classes[i]}">'
      '<img src="${_attr(photos[i])}" alt="Foto ${i + 1}" /></figure>',
    );
  }
  b.write('\n        </div>');
  return b.toString();
}

String _quoteBox(String quote) =>
    '''
        <div class="quote-box">
          <svg class="corner-svg tl small" viewBox="0 0 220 220"><use href="#corner-fl" /></svg>
          <svg class="corner-svg br small" viewBox="0 0 220 220"><use href="#corner-fl" transform="translate(220 220) scale(-1 -1)" /></svg>
          <svg class="quote-rose" viewBox="0 0 24 24"><use href="#rose" transform="translate(12 12) scale(0.9)" /></svg>
          <p class="quote-text">“${_esc(quote)}”</p>
        </div>''';

String _countdown() => '''
        <div class="countdown-wrap">
          <p class="script-faltan">Faltan</p>
          <div class="countdown-box">
            <div class="cd-item">
              <span class="cd-num" id="days">--</span>
              <span class="cd-label">Días</span>
            </div>
            <span class="cd-sep">:</span>
            <div class="cd-item">
              <span class="cd-num" id="hours">--</span>
              <span class="cd-label">Horas</span>
            </div>
            <span class="cd-sep">:</span>
            <div class="cd-item">
              <span class="cd-num" id="minutes">--</span>
              <span class="cd-label">Minutos</span>
            </div>
            <span class="cd-sep">:</span>
            <div class="cd-item">
              <span class="cd-num" id="seconds">--</span>
              <span class="cd-label">Segundos</span>
            </div>
          </div>
        </div>''';

String _families(List<InvitationFamily> families, String title) {
  final cards = <String>[];
  for (final f in families) {
    if (f.isEmpty) continue;
    final names = f.names.where((n) => n.trim().isNotEmpty);
    final title = f.title.trim().isEmpty ? 'Familia' : f.title.trim();
    cards.add('''
        <div class="family-card">
          <svg class="corner-svg tl small" viewBox="0 0 220 220"><use href="#corner-fl" /></svg>
          <h3>${_esc(title)}</h3>
          <svg class="family-heart" viewBox="0 0 24 24"><use href="#heart" /></svg>
${names.map((n) => '          <p class="name">${_esc(n.trim())}</p>').join('\n')}
        </div>''');
  }
  if (cards.isEmpty) return '';
  return '''
    <div class="section families-section">
      <div class="petals-bg"><div class="petal"></div><div class="petal"></div><div class="petal"></div><div class="petal"></div><div class="petal"></div></div>
      <div class="ornament"><div class="ornament-line"></div><div class="ornament-diamond"></div><div class="ornament-line"></div></div>
      <h2 class="families-title">${_esc(title)}</h2>
      <div class="families-grid">
${cards.join('\n')}
      </div>
    </div>''';
}

String _details(Invitation inv, bool waOk, String title, String intro) {
  final cards = <String>[];
  var i = 0;
  for (final d in inv.details) {
    if (d.isEmpty) continue;
    final title = d.title.trim().isEmpty ? 'Detalle' : d.title.trim();
    final b = StringBuffer('''
        <div class="detail-card">
          <svg class="corner-svg tl small" viewBox="0 0 220 220"><use href="#corner-fl" /></svg>
          <svg class="corner-svg br small" viewBox="0 0 220 220"><use href="#corner-fl" transform="translate(220 220) scale(-1 -1)" /></svg>
          <svg class="ribbon" viewBox="0 0 44 52"><use href="#ribbon" /></svg>
          <h3 class="detail-title">${_esc(title)}</h3>
          ${_illustration(d.icon, i)}''');
    if (d.time.trim().isNotEmpty) {
      b.write('\n          <p class="detail-time">${_esc(d.time.trim())}</p>');
    }
    if (d.place.trim().isNotEmpty) {
      b.write(
        '\n          <p class="detail-place">${_esc(d.place.trim())}</p>',
      );
    }
    if (d.note.trim().isNotEmpty) {
      b.write('\n          <p class="detail-note">${_esc(d.note.trim())}</p>');
    }
    if (isHttpUrl(d.mapUrl)) {
      b.write(
        '\n          <a class="btn" href="${_attr(d.mapUrl.trim())}">'
        'Ver ubicación</a>',
      );
    }
    b.write('\n        </div>');
    cards.add(b.toString());
    i++;
  }
  if (waOk) {
    cards.add(invitationComponentBlock(inv, 'rsvp', _rsvpCard()));
  }
  if (cards.isEmpty) return '';
  return '''
    <div class="section details-section">
      <div class="petals-bg"><div class="petal"></div><div class="petal"></div><div class="petal"></div><div class="petal"></div><div class="petal"></div></div>
      <svg class="garland top" viewBox="0 0 400 100"><use href="#garland" /></svg>
      <svg class="sparkle s1" viewBox="-14 -14 28 28"><use href="#sparkle" /></svg>
      <svg class="sparkle s4" viewBox="-14 -14 28 28"><use href="#sparkle" /></svg>
      <h2 class="details-title">${_esc(title)}</h2>
      <svg class="section-divider" viewBox="0 0 260 32"><use href="#divider" /></svg>
      <p class="details-sub">${_esc(intro)}</p>
      <div class="details-list">
${cards.join('\n')}
      </div>
    </div>''';
}

String _rsvpCard() => '''
        <div class="detail-card">
          <svg class="corner-svg tl small" viewBox="0 0 220 220"><use href="#corner-fl" /></svg>
          <svg class="corner-svg br small" viewBox="0 0 220 220"><use href="#corner-fl" transform="translate(220 220) scale(-1 -1)" /></svg>
          <svg class="butterfly" viewBox="0 0 44 44"><use href="#butterfly" /></svg>
          <svg class="ribbon" viewBox="0 0 44 52"><use href="#ribbon" /></svg>
          <h3 class="detail-title">Confirmar asistencia</h3>
          <svg class="detail-illustration" viewBox="0 0 80 62"><use href="#env-illu" transform="translate(4 4) scale(0.95)" /></svg>
          <p class="detail-text">
            Esperamos contar con tu presencia en este día tan especial para mí.
          </p>
          <button class="btn" onclick="confirmarAsistencia(event)">Confirmar</button>
        </div>''';

String _illustration(String icon, int index) {
  final id = switch (icon.trim()) {
    '⛪' || 'church' || 'Iglesia' || 'iglesia' => 'church',
    '🥂' || 'champagne' || 'Brindis' || 'brindis' => 'champagne',
    '👗' || 'couple' || 'Vestimenta' || 'vestimenta' => 'couple',
    '💌' || 'rain-env' || 'Sobre' || 'sobre' => 'rain-env',
    '✉️' || 'env' || 'env-illu' => 'env-illu',
    _ => (const [
      'church',
      'champagne',
      'couple',
      'rain-env',
      'env-illu',
    ])[index % 5],
  };
  final view = switch (id) {
    'church' => '0 0 60 62',
    'champagne' => '0 0 60 52',
    'couple' => '0 0 64 60',
    'rain-env' => '0 0 72 64',
    _ => '0 0 80 62',
  };
  return '<svg class="detail-illustration" viewBox="$view">'
      '<use href="#$id" /></svg>';
}

String _hashtag(String tag, String intro) {
  if (tag.isEmpty) return '';
  return '''
    <div class="section hashtag-section">
      <svg class="sparkle s2" viewBox="-14 -14 28 28"><use href="#sparkle" /></svg>
      <svg class="sparkle s3" viewBox="-14 -14 28 28"><use href="#sparkle" /></svg>
      <svg class="sparkle s5" viewBox="-14 -14 28 28"><use href="#sparkle" /></svg>
      <span class="hashtag-script">${_esc(intro)}</span>
      <p class="hashtag-text">${_esc(tag)}</p>
    </div>''';
}

String _itinerary(List<InvitationStop> stops, String title) {
  final items = <String>[];
  for (final s in stops) {
    if (s.isEmpty) continue;
    items.add('''
        <div class="timeline-item">
          <div class="timeline-dot"></div>
          <p class="timeline-time">${_esc(s.time.trim())}</p>
          <p class="timeline-event">${_esc(s.title.trim())}</p>
        </div>''');
  }
  if (items.isEmpty) return '';
  return '''
    <div class="section itinerary-section">
      <div class="petals-bg"><div class="petal"></div><div class="petal"></div><div class="petal"></div><div class="petal"></div><div class="petal"></div></div>
      <div class="ornament"><div class="ornament-line"></div><div class="ornament-diamond"></div><div class="ornament-line"></div></div>
      <h2 class="itinerary-title">${_esc(title)}</h2>
      <div class="timeline" id="timeline">
${items.join('\n')}
      </div>
    </div>''';
}

String _footer(String name, String message) {
  final lines = message
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .map(_esc)
      .join('<br />\n        ');
  return '''
    <div class="section footer-section">
      <div class="petals-bg"><div class="petal"></div><div class="petal"></div><div class="petal"></div><div class="petal"></div><div class="petal"></div></div>
      <svg class="garland top" viewBox="0 0 400 100"><use href="#garland" /></svg>
      <div class="footer-hearts">💗</div>
      <p class="footer-names">${_esc(name)}</p>
      <p class="footer-message">
        $lines
      </p>
      <div class="footer-credit">
        <span class="footer-credit-heart">💗</span>
        <span class="footer-credit-text">Invitación hecha con amor por</span>
        <a class="footer-credit-brand" href="https://hardstreet.com" title="Hardstreet">Hardstreet</a>
      </div>
    </div>''';
}

// ------------------------------------------------------------------
// Utilidades
// ------------------------------------------------------------------

String _inject(String template, Map<String, String> values) {
  var out = template;
  values.forEach((key, value) => out = out.replaceAll('{{$key}}', value));
  return out;
}

/// Tiñe TODA la familia de rosas del diseño con el acento elegido y, cuando
/// hay un fondo propio, lleva esa misma gama a las secciones, al sobre y a
/// las tarjetas. Los dorados se conservan: son la pareja cromática del
/// diseño y hacen que un acento dorado también se vea coherente.
String _recolor(String source, String accent, {Color? pageBg}) {
  final base = colorOfHex(accent) ?? const Color(0xFFB76E79);
  final deep = _lightness(base, -.12);
  final dark = _lightness(base, -.20);
  final darkest = _lightness(base, -.28);
  final shadow = _lightness(base, -.34);

  final tokens = <String, String>{
    '#b76e79': colorHex(base),
    '#c07d86': colorHex(_lightness(base, .06)),
    '#a95f6a': colorHex(_lightness(base, -.06)),
    '#a2555f': colorHex(_lightness(base, -.10)),
    '#a05c58': colorHex(deep),
    '#9c4a55': colorHex(dark),
    '#91464f': colorHex(darkest),
    '#8f4946': colorHex(dark),
    '#8b4347': colorHex(darkest),
    '#8b5a5b': colorHex(_lightness(base, -.24)),
    'rgba(183,110,121,': 'rgba(${_rgb(base)},',
    'rgba(183, 110, 121,': 'rgba(${_rgb(base)},',
    'rgba(160,92,88,': 'rgba(${_rgb(deep)},',
    'rgba(156,85,82,': 'rgba(${_rgb(dark)},',
    'rgba(120,60,55,': 'rgba(${_rgb(shadow)},',
  };
  if (pageBg != null) tokens.addAll(_backgroundTokens(pageBg));

  var out = source;
  for (final key in tokens.keys.toList()..sort((a, b) => b.length - a.length)) {
    out = out.replaceAll(key, tokens[key]!);
  }
  return out;
}

/// El fondo propio cambia la página Y las secciones; las tarjetas se quedan
/// en un tono claro para que los textos oscuros del diseño sigan legibles.
Map<String, String> _backgroundTokens(Color bg) {
  final light = bg.computeLuminance() > .5;
  final panel = Color.lerp(const Color(0xFFFFFBF7), bg, light ? .16 : .05)!;
  return {
    '#e8cfcd': colorHex(bg),
    '#f4e2df': colorHex(_lightness(bg, .05)),
    '#f6e5e2': colorHex(_lightness(bg, .10)),
    '#dfbfbc': colorHex(_lightness(bg, -.035)),
    '#e2c4c0': colorHex(_lightness(bg, -.025)),
    '#f9ecea': colorHex(panel),
    '#f3dfdc': colorHex(Color.lerp(panel, bg, .35)!),
    '#fdf6f3': colorHex(Color.lerp(panel, Colors.white, .6)!),
    '#f7e9e6': colorHex(Color.lerp(panel, Colors.white, .35)!),
    '#f0d9d5': colorHex(Color.lerp(panel, bg, .12)!),
  };
}

/// Aclara (delta positivo) u oscurece (negativo) un color conservando su
/// tono y saturación.
Color _lightness(Color color, double delta) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness + delta).clamp(.04, .96)).toColor();
}

String _rgb(Color c) =>
    '${(c.r * 255).round()},${(c.g * 255).round()},${(c.b * 255).round()}';

String _coverMedia(String url) {
  if (url.isEmpty) return '';
  if (isVideoUrl(url)) {
    return '<video class="cover-media" src="${_attr(url)}" autoplay muted '
        'loop playsinline></video>';
  }
  return '<img class="cover-media" src="${_attr(url)}" alt="" />';
}

String _extraCss(Invitation inv) {
  final b = StringBuffer(
    '.cover-media { position: absolute; inset: 0; width: 100%; height: 100%;'
    ' object-fit: cover; opacity: 0.45; z-index: 0; pointer-events: none; }\n',
  );
  final bg = colorOfHex(inv.bgColor);
  if (bg != null) {
    final hex = colorHex(bg);
    b
      ..writeln('body { background: $hex; }')
      ..writeln('.envelope { background: $hex; }');
    // Un fondo oscuro necesita que los títulos de las secciones (que van
    // fuera de las tarjetas claras) cambien a marfil para seguir leyéndose.
    if (bg.computeLuminance() < .42) {
      b
        ..writeln('body { color: #FDF6F3; }')
        ..writeln(
          '.families-title, .details-title, .details-sub, .itinerary-title, '
          '.footer-names, .footer-message, .footer-credit, .timeline-event, '
          '.timeline-time { color: #FDF6F3; }',
        )
        ..writeln('.footer-credit-brand { color: #F2C9C4; }');
    }
  }
  b.write(_effectCss(inv));
  return b.toString();
}

String _coverBgMedia(String url) {
  if (url.isEmpty) return '';
  if (isVideoUrl(url)) {
    return '<video class="hs-cover-bg-media" src="${_attr(url)}" autoplay '
        'muted loop playsinline aria-hidden="true"></video>';
  }
  return '<img class="hs-cover-bg-media" src="${_attr(url)}" alt="" '
      'aria-hidden="true" />';
}

/// La portada como pieza de diseño, no como un cambio de color.
///
/// Cada variante tiene su propia composición: una carta doblada, una
/// presentación de XV con corona y número, un arco floral, una noche, un
/// escenario con cortinas o un marco clásico. Todas usan la paleta de la
/// plantilla seleccionada mediante variables CSS, y la apertura sigue siendo
/// la misma (`#envelope` + `openInvitation()`).
String _coverDesign(
  Invitation inv, {
  required String envDate,
  required String envelopeText,
  required String occasion,
  required String bgMedia,
}) {
  final style = inv.coverStyleKey;
  final backdrop = inv.coverBackdropKey;
  final name = _esc(inv.displayTitle.trim());
  final date = _esc(envDate);
  final text = _esc(envelopeText);
  final letterPlace = _esc(
    [
      inv.timeText.trim(),
      inv.placeName.trim(),
    ].where((s) => s.isNotEmpty).join(' · '),
  );
  final occ = _esc(occasion.toUpperCase());
  final initials = _esc(_initials(inv.displayTitle));
  final isXV =
      occasion.toLowerCase().contains('xv') ||
      occasion.toLowerCase().contains('quince');
  final media = bgMedia.isEmpty
      ? ''
      : '<div class="hs-cover-media">${_coverBgMedia(bgMedia)}</div>';
  final label = _attr('Abrir invitación de ${inv.displayTitle.trim()}');
  final scene = switch (style) {
    'carta' => cartaPortadaScene(
      invitationText: text,
      name: name,
      date: date,
      place: letterPlace,
      initials: initials,
    ),
    'xv' =>
      '''
    <div class="hs-xv-glow"></div>
    <div class="hs-xv-confetti">
      <span></span><span></span><span></span><span></span><span></span>
      <span></span><span></span><span></span><span></span><span></span>
    </div>
    <div class="hs-xv-content">
      <span class="hs-xv-crown">&#9819;</span>
      <p class="hs-kicker hs-xv-eyebrow">$occ</p>
      <div class="hs-xv-number">${isXV ? '15' : '&#10022;'}</div>
      <p class="hs-script hs-name hs-xv-name">$name</p>
      <span class="hs-line"></span>
      <p class="hs-date">$date</p>
      <div class="hs-xv-ribbon">$text</div>
      <span class="hs-cta">${isXV ? 'Entrar a mis XV' : 'Abrir la celebración'} <b>&#8594;</b></span>
    </div>''',
    'noche' =>
      '''
    <div class="hs-night-stars"></div>
    <div class="hs-night-moon"></div>
    <div class="hs-night-content">
      <p class="hs-kicker">$text</p>
      <p class="hs-script hs-name hs-night-name">$name</p>
      <span class="hs-line"></span>
      <p class="hs-date">$date</p>
      <span class="hs-cta">Abrir bajo las estrellas <b>&#8594;</b></span>
    </div>''',
    'cortina' =>
      '''
    <div class="hs-curtain hs-curtain-left"></div>
    <div class="hs-curtain hs-curtain-right"></div>
    <div class="hs-stage">
      <span class="hs-stage-mark">&#10022;</span>
      <p class="hs-kicker">$text</p>
      <p class="hs-script hs-name hs-stage-name">$name</p>
      <span class="hs-line"></span>
      <p class="hs-date">$date</p>
      <span class="hs-cta">Abrir el telón <b>&#8594;</b></span>
    </div>''',
    'clasica' =>
      '''
    <div class="hs-clasica-frame">
      <span class="hs-clasica-corner tl">&#10022;</span>
      <span class="hs-clasica-corner tr">&#10022;</span>
      <span class="hs-clasica-corner bl">&#10022;</span>
      <span class="hs-clasica-corner br">&#10022;</span>
      <p class="hs-kicker">$text</p>
      <div class="hs-monogram">$initials</div>
      <span class="hs-line"></span>
      <p class="hs-script hs-name hs-clasica-name">$name</p>
      <p class="hs-date">$date</p>
      <span class="hs-cta">Abrir invitación <b>&#8594;</b></span>
    </div>''',
    _ =>
      '''
    <div class="hs-rosa-arch"></div>
    <span class="hs-flower hs-flower-1">&#10047;</span>
    <span class="hs-flower hs-flower-2">&#10047;</span>
    <span class="hs-flower hs-flower-3">&#10047;</span>
    <span class="hs-flower hs-flower-4">&#10047;</span>
    <div class="hs-rosa-content">
      <p class="hs-kicker">$text</p>
      <p class="hs-script hs-name hs-rosa-name">$name</p>
      <span class="hs-line"></span>
      <p class="hs-date">$date</p>
      <span class="hs-cta">Abrir invitación <b>&#8594;</b></span>
    </div>''',
  };
  final backdropClass = style == 'carta' ? ' hs-carta-bg-$backdrop' : '';
  return '''
<div class="hs-presentation hs-scene-$style$backdropClass" role="group" aria-label="$label">
  $media
  $scene
</div>''';
}

/// Los colores de la portada salen de la plantilla: el rosa de Rosa Pastel
/// y el marfil/dorado de Marfil & Oro. Los estilos oscuros usan una versión
/// profunda de esa misma paleta, no un azul o un vino ajenos.
String _coverDesignCss(Invitation inv) {
  // La portada mantiene la paleta de la PLANTILLA. El fondo personalizado de
  // la invitación sigue siendo para la página y las secciones.
  final bg = inv.design.bg;
  final accent = inv.accentColor;
  final panel = inv.design.panel;
  final ink = inv.design.ink;
  final soft = inv.design.soft;
  final deep = _lightness(Color.lerp(bg, accent, .48)!, -.34);
  final deeper = _lightness(deep, -.22);
  final mid = Color.lerp(bg, deep, .55)!;
  final light = Color.lerp(panel, Colors.white, .58)!;
  final pale = Color.lerp(panel, bg, .18)!;
  final accentSoft = Color.lerp(accent, Colors.white, .5)!;
  final ctaInk = accent.computeLuminance() > .46 ? colorHex(deep) : '#FFF9F3';
  return '''
/* ===== PORTADAS DE PRESENTACIÓN ===== */
body.hs-cover-custom {
  --hs-cover-bg: ${colorHex(bg)};
  --hs-cover-bg-rgb: ${_rgb(bg)};
  --hs-cover-panel: ${colorHex(panel)};
  --hs-cover-ink: ${colorHex(ink)};
  --hs-cover-soft: ${colorHex(soft)};
  --hs-cover-accent: ${colorHex(accent)};
  --hs-cover-accent-rgb: ${_rgb(accent)};
  --hs-cover-accent-soft: ${colorHex(accentSoft)};
  --hs-cover-deep: ${colorHex(deep)};
  --hs-cover-deep-rgb: ${_rgb(deep)};
  --hs-cover-deeper: ${colorHex(deeper)};
  --hs-cover-mid: ${colorHex(mid)};
  --hs-cover-light: ${colorHex(light)};
  --hs-cover-light-rgb: ${_rgb(light)};
  --hs-cover-pale: ${colorHex(pale)};
  --hs-cover-line: rgba(${_rgb(accent)}, .48);
  --hs-cover-cta-ink: $ctaInk;
}

/* Las portadas nuevas sustituyen al sobre original. */
body.hs-cover-custom .envelope::before,
body.hs-cover-custom .envelope::after,
body.hs-cover-custom .envelope > .cover-media,
body.hs-cover-custom .envelope > .envelope-content,
body.hs-cover-custom .envelope > .cover-copy,
body.hs-cover-custom .envelope > .cover-flowers,
body.hs-cover-custom .envelope > .cover-rings,
body.hs-cover-custom .envelope > .garland,
body.hs-cover-custom .envelope > .corner-svg,
body.hs-cover-custom .envelope > .sparkle,
body.hs-cover-custom .envelope > .petal,
body.hs-cover-custom .cover-hit { display: none !important; }

body.hs-cover-custom .envelope {
  overflow: hidden;
  background: var(--hs-cover-deep);
}

.hs-presentation {
  position: absolute;
  inset: 0;
  z-index: 20;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  padding: clamp(1.4rem, 4vw, 3.4rem);
  text-align: center;
  color: var(--hs-cover-ink);
  animation: hsCoverEnter .85s cubic-bezier(.2, .8, .2, 1) both;
}

.hs-cover-media {
  position: absolute;
  inset: 0;
  z-index: 0;
  overflow: hidden;
  opacity: .14;
  pointer-events: none;
}
.hs-cover-bg-media {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.hs-carta-paper,
.hs-xv-content,
.hs-night-content,
.hs-stage,
.hs-rosa-content,
.hs-clasica-frame {
  position: relative;
  z-index: 2;
}
.hs-carta-paper { position: relative; }
.hs-presentation .hs-kicker {
  margin: 0;
  font-family: 'Inter', sans-serif;
  font-size: clamp(.58rem, 1.8vw, .72rem);
  font-weight: 600;
  letter-spacing: .32em;
  line-height: 1.55;
  text-transform: uppercase;
  color: var(--hs-cover-soft);
}
.hs-presentation .hs-script {
  margin: 0;
  font-family: 'Great Vibes', cursive;
  font-weight: 400;
  line-height: .95;
  color: var(--hs-cover-accent);
}
.hs-presentation .hs-name {
  max-width: 100%;
  margin: .45rem 0 .7rem;
  font-size: clamp(3rem, 10vw, 5.2rem);
  line-height: 1.02;
  text-shadow: 0 8px 24px rgba(var(--hs-cover-bg-rgb), .18);
  overflow-wrap: anywhere;
}
.hs-presentation .hs-line {
  display: block;
  width: 62px;
  height: 1px;
  margin: 1rem auto;
  background: var(--hs-cover-accent);
  opacity: .7;
}
.hs-presentation .hs-date {
  margin: 0;
  font-family: 'Cormorant Garamond', serif;
  font-size: clamp(.78rem, 2.2vw, .95rem);
  letter-spacing: .19em;
  line-height: 1.5;
  text-transform: uppercase;
  color: var(--hs-cover-soft);
}
.hs-presentation .hs-cta {
  display: inline-flex;
  align-items: center;
  gap: .65rem;
  margin-top: 1.5rem;
  padding: .76rem 1.35rem;
  border: 1px solid rgba(var(--hs-cover-accent-rgb), .7);
  border-radius: 999px;
  background: var(--hs-cover-accent);
  color: var(--hs-cover-cta-ink);
  font-family: 'Inter', sans-serif;
  font-size: .6rem;
  font-weight: 700;
  letter-spacing: .17em;
  line-height: 1.2;
  text-transform: uppercase;
  box-shadow: 0 12px 26px rgba(var(--hs-cover-deep-rgb), .16);
}
.hs-presentation .hs-cta b { font-size: 1rem; line-height: 0; }

/* ===== CARTA ===== */
${cartaPortadaCss()}

/* ===== XV ===== */
.hs-scene-xv {
  background:
    radial-gradient(circle at 50% 27%, rgba(var(--hs-cover-accent-rgb), .28), transparent 42%),
    linear-gradient(160deg, var(--hs-cover-bg), var(--hs-cover-mid));
}
.hs-xv-glow {
  position: absolute;
  width: min(70vw, 520px);
  aspect-ratio: 1;
  border-radius: 50%;
  background: radial-gradient(circle, rgba(var(--hs-cover-accent-rgb), .2), transparent 68%);
  filter: blur(6px);
  animation: hsCoverGlow 6s ease-in-out infinite;
  pointer-events: none;
}
.hs-xv-content { position: relative; z-index: 2; }
.hs-xv-crown {
  display: block;
  color: var(--hs-cover-accent);
  font-family: Georgia, serif;
  font-size: clamp(1.7rem, 5vw, 2.7rem);
  line-height: 1;
  text-shadow: 0 4px 14px rgba(var(--hs-cover-accent-rgb), .24);
}
.hs-xv-eyebrow { margin-top: .55rem !important; color: var(--hs-cover-accent) !important; }
.hs-xv-number {
  margin: 0 0 1.4rem;
  color: var(--hs-cover-accent);
  font-family: 'Playfair Display', serif;
  font-size: clamp(6rem, 21vw, 10rem);
  font-weight: 400;
  line-height: .9;
  letter-spacing: -.06em;
}
.hs-xv-name { color: var(--hs-cover-ink) !important; }
.hs-xv-ribbon {
  display: inline-block;
  margin-top: 1rem;
  padding: .55rem 1.2rem;
  background: var(--hs-cover-accent);
  color: var(--hs-cover-cta-ink);
  font-family: 'Cormorant Garamond', serif;
  font-size: .72rem;
  letter-spacing: .18em;
  text-transform: uppercase;
  transform: rotate(-1.5deg);
  box-shadow: 0 8px 20px rgba(var(--hs-cover-deep-rgb), .15);
}
.hs-xv-confetti span {
  position: absolute;
  z-index: 1;
  width: 5px;
  height: 11px;
  border-radius: 2px;
  background: var(--hs-cover-accent);
  opacity: .55;
  animation: hsConfetti 6s ease-in-out infinite;
}
.hs-xv-confetti span:nth-child(1) { left: 12%; top: 16%; transform: rotate(22deg); }
.hs-xv-confetti span:nth-child(2) { left: 22%; top: 67%; transform: rotate(-32deg); animation-delay: -1s; }
.hs-xv-confetti span:nth-child(3) { left: 81%; top: 21%; transform: rotate(46deg); animation-delay: -2s; }
.hs-xv-confetti span:nth-child(4) { left: 91%; top: 62%; transform: rotate(-14deg); animation-delay: -3s; }
.hs-xv-confetti span:nth-child(5) { left: 7%; top: 43%; width: 4px; height: 7px; animation-delay: -4s; }
.hs-xv-confetti span:nth-child(6) { left: 72%; top: 84%; width: 4px; height: 8px; animation-delay: -2.5s; }
.hs-xv-confetti span:nth-child(7) { left: 30%; top: 9%; width: 3px; height: 6px; animation-delay: -1.5s; }
.hs-xv-confetti span:nth-child(8) { left: 62%; top: 8%; width: 3px; height: 6px; animation-delay: -3.5s; }
.hs-xv-confetti span:nth-child(9) { left: 16%; top: 82%; width: 3px; height: 6px; animation-delay: -2.2s; }
.hs-xv-confetti span:nth-child(10) { left: 85%; top: 44%; width: 3px; height: 6px; animation-delay: -.8s; }
.hs-scene-xv .hs-cover-media { opacity: .1; }

/* ===== ROSA PASTEL ===== */
.hs-scene-rosa {
  background:
    radial-gradient(ellipse at 50% 42%, rgba(var(--hs-cover-light-rgb), .6), transparent 52%),
    linear-gradient(160deg, var(--hs-cover-bg), var(--hs-cover-mid));
}
.hs-rosa-arch {
  position: absolute;
  width: min(440px, 78vw);
  height: min(560px, 78vh);
  border: 1px solid rgba(var(--hs-cover-accent-rgb), .42);
  border-radius: 50% 50% 10px 10px / 38% 38% 10px 10px;
  box-shadow:
    inset 0 0 0 8px rgba(var(--hs-cover-light-rgb), .18),
    inset 0 0 45px rgba(var(--hs-cover-accent-rgb), .08);
  pointer-events: none;
}
.hs-rosa-arch::before {
  content: '';
  position: absolute;
  inset: 13px;
  border: 1px solid rgba(var(--hs-cover-accent-rgb), .22);
  border-radius: inherit;
}
.hs-rosa-content { position: relative; z-index: 2; }
.hs-rosa-name { color: var(--hs-cover-accent) !important; }
.hs-flower {
  position: absolute;
  z-index: 1;
  color: var(--hs-cover-accent);
  font-size: clamp(1.6rem, 5vw, 2.8rem);
  line-height: 1;
  opacity: .55;
  animation: hsFlowerFloat 7s ease-in-out infinite;
  pointer-events: none;
}
.hs-flower-1 { left: 13%; top: 18%; transform: rotate(-18deg); }
.hs-flower-2 { right: 12%; top: 28%; transform: rotate(22deg); animation-delay: -1.7s; }
.hs-flower-3 { left: 18%; bottom: 16%; transform: rotate(32deg); animation-delay: -3.4s; }
.hs-flower-4 { right: 15%; bottom: 12%; transform: rotate(-26deg); animation-delay: -5.1s; }
.hs-scene-rosa .hs-cover-media { opacity: .12; }

/* ===== NOCHE ===== */
.hs-scene-noche {
  color: var(--hs-cover-light);
  background:
    radial-gradient(ellipse at 50% 34%, var(--hs-cover-mid), transparent 55%),
    linear-gradient(160deg, var(--hs-cover-deep), var(--hs-cover-deeper));
}
.hs-night-stars {
  position: absolute;
  inset: 0;
  z-index: 0;
  opacity: .82;
  background:
    radial-gradient(circle at 14% 22%, rgba(var(--hs-cover-light-rgb), .9) 0 1px, transparent 2px),
    radial-gradient(circle at 27% 68%, rgba(var(--hs-cover-accent-rgb), .8) 0 1px, transparent 2px),
    radial-gradient(circle at 42% 16%, rgba(var(--hs-cover-light-rgb), .8) 0 1px, transparent 2px),
    radial-gradient(circle at 58% 74%, rgba(var(--hs-cover-accent-rgb), .8) 0 1.5px, transparent 2.5px),
    radial-gradient(circle at 72% 28%, rgba(var(--hs-cover-light-rgb), .9) 0 1px, transparent 2px),
    radial-gradient(circle at 86% 60%, rgba(var(--hs-cover-accent-rgb), .8) 0 1px, transparent 2px),
    radial-gradient(circle at 91% 18%, rgba(var(--hs-cover-light-rgb), .9) 0 1px, transparent 2px);
  animation: hsStarTwinkle 6s ease-in-out infinite;
  pointer-events: none;
}
.hs-night-moon {
  position: absolute;
  top: 12%;
  right: 11%;
  z-index: 1;
  width: clamp(64px, 14vw, 112px);
  aspect-ratio: 1;
  border-radius: 50%;
  background: radial-gradient(circle at 34% 32%, var(--hs-cover-light) 0%, var(--hs-cover-accent-soft) 45%, var(--hs-cover-accent) 100%);
  box-shadow:
    0 0 55px rgba(var(--hs-cover-accent-rgb), .25),
    0 0 130px rgba(var(--hs-cover-accent-rgb), .12);
  opacity: .9;
  animation: hsMoonPulse 7s ease-in-out infinite;
  pointer-events: none;
}
.hs-night-content { position: relative; z-index: 2; }
.hs-night-name { color: var(--hs-cover-light) !important; }
.hs-scene-noche .hs-kicker,
.hs-scene-noche .hs-date { color: var(--hs-cover-accent-soft); }
.hs-scene-noche .hs-line { background: var(--hs-cover-accent); }
.hs-scene-noche .hs-cover-media { opacity: .16; filter: brightness(.55) saturate(.8); }

/* ===== CORTINA ===== */
.hs-scene-cortina {
  color: var(--hs-cover-light);
  background:
    radial-gradient(ellipse at 50% 45%, var(--hs-cover-mid), var(--hs-cover-deep) 58%, var(--hs-cover-deeper));
}
.hs-curtain {
  position: absolute;
  top: 0;
  bottom: 0;
  z-index: 1;
  width: clamp(60px, 20vw, 160px);
  background:
    repeating-linear-gradient(90deg, rgba(var(--hs-cover-light-rgb), .1) 0 2px, transparent 2px 15px, rgba(var(--hs-cover-deep-rgb), .2) 15px 27px),
    linear-gradient(90deg, rgba(var(--hs-cover-deep-rgb), .85), rgba(var(--hs-cover-accent-rgb), .45) 52%, rgba(var(--hs-cover-deep-rgb), .8));
  box-shadow: inset 0 0 42px rgba(var(--hs-cover-deep-rgb), .5);
  animation: hsCurtainSway 8s ease-in-out infinite;
  pointer-events: none;
}
.hs-curtain-left { left: 0; transform-origin: left center; }
.hs-curtain-right { right: 0; transform-origin: right center; animation-delay: -2s; }
.hs-stage {
  position: relative;
  z-index: 2;
  width: min(440px, 76vw);
  padding: clamp(2rem, 6vw, 3.3rem) clamp(1.3rem, 5vw, 2.6rem);
  border: 1px solid rgba(var(--hs-cover-accent-rgb), .42);
  background: rgba(var(--hs-cover-deep-rgb), .56);
  box-shadow:
    0 30px 70px rgba(var(--hs-cover-deep-rgb), .4),
    inset 0 0 28px rgba(var(--hs-cover-accent-rgb), .07);
  backdrop-filter: blur(5px);
}
.hs-stage::before,
.hs-stage::after {
  content: '';
  position: absolute;
  width: 16px;
  height: 16px;
  border-color: var(--hs-cover-accent);
  opacity: .8;
}
.hs-stage::before { top: 8px; left: 8px; border-top: 1px solid; border-left: 1px solid; }
.hs-stage::after { right: 8px; bottom: 8px; border-right: 1px solid; border-bottom: 1px solid; }
.hs-stage-mark { display: block; color: var(--hs-cover-accent); font-size: 1.4rem; }
.hs-stage-name { color: var(--hs-cover-light) !important; }
.hs-scene-cortina .hs-kicker,
.hs-scene-cortina .hs-date { color: var(--hs-cover-accent-soft); }
.hs-scene-cortina .hs-cover-media { opacity: .13; filter: brightness(.45) saturate(.8); }

/* ===== CLÁSICA ===== */
.hs-scene-clasica {
  background:
    radial-gradient(circle at 50% 28%, rgba(255, 255, 255, .7), transparent 55%),
    linear-gradient(145deg, var(--hs-cover-light), var(--hs-cover-bg));
}
.hs-clasica-frame {
  position: relative;
  width: min(430px, 84vw);
  padding: clamp(2rem, 6vw, 3.3rem) clamp(1.3rem, 5vw, 2.5rem);
  border: 1px solid rgba(var(--hs-cover-accent-rgb), .55);
  background: rgba(var(--hs-cover-light-rgb), .1);
  color: var(--hs-cover-ink);
  box-shadow: 0 28px 60px rgba(var(--hs-cover-deep-rgb), .16);
}
.hs-clasica-frame::before {
  content: '';
  position: absolute;
  inset: 10px;
  border: 1px solid rgba(var(--hs-cover-accent-rgb), .28);
  pointer-events: none;
}
.hs-clasica-corner {
  position: absolute;
  color: var(--hs-cover-accent);
  font-size: .6rem;
  opacity: .65;
}
.hs-clasica-corner.tl { top: 15px; left: 15px; }
.hs-clasica-corner.tr { top: 15px; right: 15px; }
.hs-clasica-corner.bl { bottom: 15px; left: 15px; }
.hs-clasica-corner.br { bottom: 15px; right: 15px; }
.hs-monogram {
  display: grid;
  place-items: center;
  width: clamp(64px, 16vw, 90px);
  aspect-ratio: 1;
  margin: 1rem auto .8rem;
  border: 1px solid rgba(var(--hs-cover-accent-rgb), .55);
  border-radius: 50%;
  color: var(--hs-cover-accent);
  font-family: 'Cormorant Garamond', serif;
  font-size: clamp(1.2rem, 4vw, 1.7rem);
  letter-spacing: .08em;
}
.hs-clasica-name { color: var(--hs-cover-accent) !important; }
.hs-scene-clasica .hs-cover-media { opacity: .1; }

@keyframes hsCoverEnter {
  from { opacity: 0; transform: translateY(14px) scale(.985); }
  to { opacity: 1; transform: translateY(0) scale(1); }
}
@keyframes hsLetterFloat {
  0%, 100% { transform: rotate(-1.2deg) translateY(0); }
  50% { transform: rotate(-.5deg) translateY(-8px); }
}
@keyframes hsFlowerFloat {
  0%, 100% { transform: translateY(0) rotate(-8deg); }
  50% { transform: translateY(-9px) rotate(5deg); }
}
@keyframes hsCoverGlow {
  0%, 100% { transform: scale(.92); opacity: .7; }
  50% { transform: scale(1.05); opacity: 1; }
}
@keyframes hsStarTwinkle {
  0%, 100% { opacity: .52; }
  50% { opacity: .95; }
}
@keyframes hsMoonPulse {
  0%, 100% { box-shadow: 0 0 55px rgba(var(--hs-cover-accent-rgb), .25), 0 0 130px rgba(var(--hs-cover-accent-rgb), .12); }
  50% { box-shadow: 0 0 75px rgba(var(--hs-cover-accent-rgb), .4), 0 0 160px rgba(var(--hs-cover-accent-rgb), .2); }
}
@keyframes hsCurtainSway {
  0%, 100% { transform: scaleX(1) translateX(0); }
  50% { transform: scaleX(1.025) translateX(4px); }
}
@keyframes hsConfetti {
  0%, 100% { translate: 0 0; opacity: .35; }
  50% { translate: 4px 12px; opacity: .8; }
}

@media (max-width: 600px) {
  .hs-presentation { padding: 1.1rem; }
  .hs-carta-paper { width: min(88vw, 360px); padding-bottom: 5.5rem; }
  .hs-xv-number { font-size: clamp(5.2rem, 25vw, 8rem); }
  .hs-stage { width: min(84vw, 360px); }
  .hs-curtain { width: 15vw; }
  .hs-flower-1 { left: 7%; }
  .hs-flower-2 { right: 6%; }
  .hs-flower-3 { left: 10%; }
  .hs-flower-4 { right: 8%; }
}

@media (prefers-reduced-motion: reduce) {
  .hs-presentation,
  .hs-presentation *,
  .hs-curtain,
  .hs-night-stars { animation: none !important; }
}
''';
}

/// El efecto de ambiente elegido en el editor.
///
/// El documento original trae pétalos, así que los demás efectos se
/// resuelven cambiando el aspecto y el movimiento de esas mismas piezas: la
/// liga sigue siendo el HTML original, sin añadir scripts ni imágenes.
String _effectCss(Invitation inv) {
  final effect = inv.effect.trim().toLowerCase();
  if (effect.isEmpty || effect == 'petalos') return '';
  final accent = inv.accentColor;
  final rgb = _rgb(accent);
  final hex = colorHex(accent);

  if (effect == 'ninguno') {
    return '''
.sparkle, .petals-bg, .envelope > .petal { display: none !important; }
''';
  }

  if (effect == 'destellos') {
    return '''
.petals-bg, .envelope > .petal { display: none !important; }
.sparkle { color: #D9A95E; opacity: 1; animation-duration: 2.2s; }
.sparkle.s1 { width: 26px; }
.sparkle.s4 { width: 28px; }
''';
  }

  if (effect == 'burbujas') {
    return '''
.sparkle { display: none !important; }
.petals-bg .petal, .envelope > .petal {
  width: 16px; height: 16px; border-radius: 50%;
  background: radial-gradient(circle at 32% 28%, rgba(255,255,255,.92), rgba($rgb,.22) 58%, rgba($rgb,.05));
  border: 1px solid rgba(255,255,255,.5);
  box-shadow: 0 0 14px rgba(255,255,255,.28), inset 0 -4px 10px rgba($rgb,.18);
  animation-name: hsBubble;
}
.envelope > .petal { animation-name: hsBubbleUp; }
@keyframes hsBubble {
  0% { transform: translate(0, 40px) scale(.55); opacity: 0; }
  14% { opacity: .7; }
  72% { opacity: .55; }
  100% { transform: translate(26px, -200px) scale(1.15); opacity: 0; }
}
@keyframes hsBubbleUp {
  0% { transform: translate(0, 80vh) scale(.6); opacity: 0; }
  12% { opacity: .7; }
  80% { opacity: .55; }
  100% { transform: translate(24px, -10vh) scale(1.1); opacity: 0; }
}
''';
  }

  if (effect == 'corazones') {
    return '''
.petals-bg .petal, .envelope > .petal {
  width: auto; height: auto; background: none; border: 0; box-shadow: none;
  font-size: 20px; line-height: 1; color: rgba($rgb,.85);
}
.petals-bg .petal::after, .envelope > .petal::after {
  content: '♥'; display: block;
  text-shadow: 0 4px 12px rgba($rgb,.35);
}
''';
  }

  // Confeti: las mismas piezas, ahora rectángulos que caen girando.
  return '''
.petals-bg .petal, .envelope > .petal {
  width: 8px; height: 14px; border-radius: 2px;
  background: linear-gradient(135deg, $hex, #D9A95E);
  animation-name: hsConfettiFall;
}
.petals-bg .petal:nth-of-type(2n), .envelope > .petal:nth-of-type(2n) {
  background: linear-gradient(135deg, #D9A95E, #B8915A);
}
.petals-bg .petal:nth-of-type(3n), .envelope > .petal:nth-of-type(3n) {
  width: 6px; height: 10px;
  background: linear-gradient(135deg, #FFF6E8, rgba($rgb,.9));
}
@keyframes hsConfettiFall {
  0% { transform: translateY(-40px) rotate(0deg); opacity: 0; }
  14% { opacity: .9; }
  100% { transform: translateY(380px) rotate(460deg); opacity: 0; }
}
''';
}

String _dataScript(String name, String dateLabel, DateTime? event, String wa) {
  final info = <String, String>{
    'name': name,
    'date': dateLabel,
    'event': event == null ? '' : _isoLocal(event),
    'wa': wa,
    'rsvp':
        '¡Hola! 🎀 Quiero confirmar mi asistencia a la invitación de '
        '$name.',
  };
  final json = jsonEncode(info).replaceAll('<', r'\u003c');
  return '<script>window.__HS_INV = $json;</script>';
}

String _isoLocal(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}'
    'T${_two(d.hour)}:${_two(d.minute)}:00';

String _two(int v) => v.toString().padLeft(2, '0');

String _cap(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

const String _defaultFamiliesTitle = 'Con mi familia';
const String _defaultDetailsTitle = 'Detalles';
const String _defaultDetailsIntro =
    'Todo lo que necesitas saber para acompañarme';
const String _defaultItineraryTitle = 'Itinerario de Actividades';
const String _defaultHashtagIntro = 'Captura momentos únicos con';
const String _defaultFooterMessage =
    'Tu presencia es el mejor regalo que puedo recibir.\n'
    '¡Te espero con mucho cariño!';

/// El texto propio o, si está vacío, el original de ReynaCoot.
String _textOr(String value, String fallback) {
  final s = value.trim();
  return s.isEmpty ? fallback : s;
}

String _verticalTitle(Invitation inv, String fallbackOccasion) {
  final own = inv.verticalTitle.trim();
  if (own.isNotEmpty) return own;
  return switch (fallbackOccasion.trim().toLowerCase()) {
    'xv' => 'Mis Quinceaños',
    'boda' => 'Nuestra Boda',
    'cumpleaños' => 'Mi Cumpleaños',
    _ => fallbackOccasion.trim(),
  };
}

String _arcText(Invitation inv, String fallbackOccasion) {
  final own = inv.arcTitle.trim();
  return own.isNotEmpty
      ? own
      : _verticalTitle(inv, fallbackOccasion).toUpperCase();
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

String _attr(String s) => _esc(s.trim());

/// Cuando la portada está apagada, la invitación se abre sola.
const String _autoOpen = '''
<script>
document.addEventListener('DOMContentLoaded', function () {
  var env = document.getElementById('envelope');
  if (!env || env.style.display !== 'none') return;
  var card = document.getElementById('invitation');
  if (card) card.classList.add('open');
  if (typeof observeSections === 'function') observeSections();
  if (typeof showProgress === 'function') showProgress();
  if (typeof celebrate === 'function') celebrate(window.innerWidth / 2, window.innerHeight * .4);
  if (typeof startCountdown === 'function' && document.getElementById('days')) {
    startCountdown();
  }
});
</script>''';

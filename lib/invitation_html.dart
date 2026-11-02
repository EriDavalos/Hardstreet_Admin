import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

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
  final music = isHttpUrl(inv.musicUrl) ? inv.musicUrl.trim() : '';
  final bgMedia = isHttpUrl(inv.bgMedia) ? inv.bgMedia.trim() : '';
  final coverOn = inv.sectionOn('cover');
  final wa = inv.rsvpPhone.replaceAll(RegExp(r'[^0-9]'), '');
  final waOk = wa.length >= 8;
  final dateText = inv.dateText.trim();
  final quote = inv.quoteText.trim();
  final hashtag = inv.hashtag.trim();

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
    'POLAROIDS': _polaroids(photos),
    'QUOTE': quote.isEmpty ? '' : _quoteBox(quote),
    'COUNTDOWN': event != null && inv.sectionOn('countdown')
        ? _countdown()
        : '',
    'FAMILIES': inv.sectionOn('families')
        ? _families(
            inv.families,
            _textOr(inv.familiesTitle, _defaultFamiliesTitle),
          )
        : '',
    'DETAILS': inv.sectionOn('details')
        ? _details(
            inv,
            waOk,
            _textOr(inv.detailsTitle, _defaultDetailsTitle),
            _textOr(inv.detailsIntro, _defaultDetailsIntro),
          )
        : '',
    'HASHTAG': inv.sectionOn('hashtag')
        ? _hashtag(hashtag, _textOr(inv.hashtagIntro, _defaultHashtagIntro))
        : '',
    'ITINERARY': inv.sectionOn('itinerary')
        ? _itinerary(
            inv.itinerary,
            _textOr(inv.itineraryTitle, _defaultItineraryTitle),
          )
        : '',
    'FOOTER': inv.sectionOn('footer')
        ? _footer(name, _textOr(inv.footerMessage, _defaultFooterMessage))
        : '',
    'THANKS_DATE': _esc(thanksDate),
    'AUDIO': music.isEmpty
        ? ''
        : '<audio id="bg-music" src="${_attr(music)}" preload="auto" '
              'loop></audio>',
    'MUSIC_BTN': music.isEmpty
        ? ''
        : '<button class="music-btn" id="music-btn" onclick="toggleMusic()" '
              'title="Música" aria-label="Reproducir o pausar música">🎵'
              '</button>',
  });

  final html =
      '''
<!DOCTYPE html>
<html lang="es">
<head>
$head<style>
$css
${_extraCss(inv)}
</style>
</head>
<body>
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
  final music = isHttpUrl(inv.musicUrl) ? inv.musicUrl.trim() : '';
  final bgMedia = isHttpUrl(inv.bgMedia) ? inv.bgMedia.trim() : '';
  final coverOn = inv.sectionOn('cover');
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
    'ENVELOPE_TEXT': _esc(
      _textOr(inv.envelopeText, 'Estás cordialmente invitado'),
    ),
    'ENVELOPE_NAME': _esc(name),
    'ENVELOPE_DATE': _esc(envDate),
    'SEAL': _esc(_initials(name)),
    'INV_CLASS': coverOn ? 'invitation' : 'invitation open',
    'ARC_TEXT': _esc(_arcText(inv, occasion)),
    'MAIN_NAME': _esc(name),
    'INVITE_SUB': _esc(
      inv.subheadline.trim().isEmpty ? 'Nos casamos' : inv.subheadline.trim(),
    ),
    'DATE_LINE': _esc(dateLine),
    'COUNTDOWN': event != null && inv.sectionOn('countdown')
        ? _mfCountdown()
        : '',
    'ITINERARY': inv.sectionOn('itinerary')
        ? _mfItinerary(
            inv.itinerary,
            _textOr(inv.itineraryTitle, 'El día'),
          )
        : '',
    'QUOTE': quote.isEmpty ? '' : _mfQuote(quote),
    'DETAILS': inv.sectionOn('details')
        ? _mfDetails(
            inv,
            _textOr(inv.detailsTitle, 'Los detalles'),
            _textOr(inv.detailsIntro, 'Todo lo que necesitas saber'),
            detailsMedia,
          )
        : '',
    'FAMILIES': inv.sectionOn('families')
        ? _mfFamilies(
            inv.families,
            _textOr(inv.familiesTitle, 'Con la bendición de'),
          )
        : '',
    'PHOTOS': _mfPhotos(photos),
    'HASHTAG': inv.sectionOn('hashtag')
        ? _mfHashtag(hashtag, _textOr(inv.hashtagIntro, 'Comparte tus fotos con'))
        : '',
    'RSVP': waOk ? _mfRsvp(thanksDate) : '',
    'FOOTER': inv.sectionOn('footer')
        ? _mfFooter(name, _textOr(inv.footerMessage, _defaultFooterMessage))
        : '',
    'THANKS_DATE': _esc(thanksDate),
    'AUDIO': music.isEmpty
        ? ''
        : '<audio id="bg-music" src="${_attr(music)}" preload="auto" '
              'loop></audio>',
    'MUSIC_BTN': music.isEmpty
        ? ''
        : '<button class="music-btn" id="music-btn" '
              'onclick="toggleMusic()" title="Música" '
              'aria-label="Reproducir o pausar música">'
              '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">'
              '<path d="M20 4.6v10.2a3 3 0 1 1-1.5-2.6V7.1l-8 1.7v8.3a3 3 0 1 1-1.5-2.6V5.7a1 1 0 0 1 .76-.97l9-1.9A1 1 0 0 1 20 4.6Z"/>'
              '</svg></button>',
  });

  final head = StringBuffer()
    ..writeln('<meta charset="UTF-8" />')
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

  final theme = '''
:root {
  --gold: ${colorHex(accent)};
  --gold-deep: ${colorHex(goldDeep)};
  --paper: ${colorHex(paper)};
  --paper-2: ${colorHex(paperAlt)};
  --line: rgba(${_rgb(accent)}, .45);
}''';

  final html = '''
<!DOCTYPE html>
<html lang="es">
<head>
$head<style>
$kMarfilCss
$theme
${_effectCss(inv)}
</style>
</head>
<body${coverOn ? ' class="at-cover"' : ''}>
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

String _mfQuote(String quote) => '''
<section class="mf-quote-section section">
  <span class="mf-quote-mark">“</span>
  <p>${_esc(quote)}</p>
</section>''';

String _mfDetails(
  Invitation inv,
  String title,
  String intro,
  String media,
) {
  final cards = <String>[];
  for (final d in inv.details) {
    if (d.isEmpty) continue;
    final b = StringBuffer('''
    <article class="mf-card">
      <svg class="mf-mark" viewBox="-14 -14 28 28" aria-hidden="true"><use href="#mf-spark" /></svg>''');
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
      '\n  <figure class="mf-photo">'
      '<img src="${_attr(photos[i])}" alt="Foto ${i + 1}" /></figure>',
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

String _mfRsvp(String thanksDate) => '''
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
  if (waOk) cards.add(_rsvpCard());
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
  final panel = Color.lerp(
    const Color(0xFFFFFBF7),
    bg,
    light ? .16 : .05,
  )!;
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
  if (typeof startCountdown === 'function' && document.getElementById('days')) {
    startCountdown();
  }
});
</script>''';

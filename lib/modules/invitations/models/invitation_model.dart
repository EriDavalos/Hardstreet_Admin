import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:hardstreet_admin/app/app_constants.dart';
import 'package:hardstreet_admin/modules/invitations/components/component_catalog.dart';
import 'package:hardstreet_admin/modules/invitations/components/templates/invitation_templates.dart';

// ==================================================================
// INVITACIONES — plantillas, modelo y contenido de la liga pública
// ==================================================================
// Una invitación es un DOCUMENTO con dos mitades:
//
//   · los datos (textos, fecha, lugar, fotos y el DISEÑO: fondo, color,
//     secciones, familias, detalles, itinerario, música), que es lo que el
//     panel vuelve a abrir para editar;
//   · el HTML ya renderizado por `buildInvitationHtml` (invitation_html.dart),
//     que se guarda en la base y se sirve en la liga /i/<slug>.
//
// El diseño sigue la invitación de Hardstreet/ReynaCoot: portada de SOBRE
// («Abrir invitación»), tarjeta principal con polaroids y cuenta regresiva,
// familias, detalles, hashtag, itinerario, música y pie. Todo eso se
// construye como HTML puro, sin dependencias externas.
//
// Las plantillas están agrupadas por OCASIÓN (XV, Boda, Cumpleaños) para
// elegirlas, pero la invitación NO guarda categoría: `occasion` es solo una
// etiqueta heredada de la plantilla para el encabezado del diseño.
// ==================================================================

const String kInvitationsModuleKey = 'invitations';
const String kInvitationsModuleName = 'Invitaciones';

/// Una PLANTILLA de invitación: paleta y tipografía del diseño ReynaCoot.
class InvitationTemplate {
  const InvitationTemplate({
    required this.key,
    required this.name,
    required this.occasion,
    required this.hint,
    required this.bg,
    required this.bgAlt,
    required this.ink,
    required this.soft,
    required this.accent,
    required this.panel,
    required this.font,
    this.cover = 'sobre',
    this.card = 'panel',
    this.photos = 'polaroid',
    this.ornament = 'floral',
    this.light = false,
  });

  /// Clave que se guarda en la invitación (`template`).
  final String key;

  /// Nombre visible en el catálogo («Sobre · Reyna»).
  final String name;

  /// Ocasión para la que está pensada («XV», «Boda», «Cumpleaños»).
  final String occasion;

  /// Una línea que describe el diseño.
  final String hint;

  final Color bg;
  final Color bgAlt;
  final Color ink;
  final Color soft;
  final Color accent;

  /// Fondo de la tarjeta de contenido (marfil en los diseños claros).
  final Color panel;

  /// Familia tipográfica por defecto (`clasica`, `moderna`, `romantica`).
  final String font;

  /// Composición de la PORTADA: 'sobre' (el sobre con «Abrir
  /// invitación»), 'abierta' (página completa con el nombre, sin sobre) o
  /// 'foto' (portada con la foto de fondo).
  final String cover;

  /// Forma de la tarjeta principal: 'panel' (redondeada), 'papel' (hoja con
  /// doble marco, tipo papel de carta) o 'plano' (sin tarjeta: manda el color
  /// de la página).
  final String card;

  /// Fotos: 'polaroid' (tres inclinadas), 'arco' (una con la parte de arriba
  /// en arco) o 'portada' (foto ancha arriba del nombre).
  final String photos;

  /// Adorno de la invitación: 'floral' (guirnalda y esquinas de flores),
  /// 'linea' (reglas finas y rombos) o 'ninguno'.
  final String ornament;

  /// Diseño CLARO (fondo marfil o pastel) en vez de oscuro.
  final bool light;
}

/// Las siete plantillas: la de Reyna (XV) y las seis paletas anteriores.
const List<InvitationTemplate> kInvitationTemplates = [
  InvitationTemplate(
    key: 'sobre-xv',
    name: 'Rosa Pastel',
    occasion: 'XV',
    hint:
        'Sobre floral rosa, marco con arco, tiara, polaroids, cintas e '
        'ilustraciones. Una portada dulce con confirmación por WhatsApp.',
    bg: Color(0xFFE8CFCD),
    bgAlt: Color(0xFFF3E3E1),
    ink: Color(0xFF5A3F3B),
    soft: Color(0xFF8A6E68),
    accent: Color(0xFFB76E79),
    panel: Color(0xFFFFFBF7),
    font: 'romantica',
    cover: 'sobre',
    card: 'panel',
    photos: 'polaroid',
    ornament: 'floral',
    light: true,
  ),
  InvitationTemplate(
    key: 'boda-marfil',
    name: 'Marfil & Oro',
    occasion: 'Boda',
    hint:
        'Papel marfil, tipografía dorada y sobre con sello de cera. Clásica, '
        'luminosa y con el programa del día en línea.',
    bg: Color(0xFFF8F3E7),
    bgAlt: Color(0xFFF1E8D7),
    ink: Color(0xFF3B352C),
    soft: Color(0xFF7D7263),
    accent: Color(0xFFB99A63),
    panel: Color(0xFFFFFDF8),
    font: 'clasica',
    cover: 'sobre',
    card: 'papel',
    photos: 'polaroid',
    ornament: 'floral',
    light: true,
  ),
];

/// La plantilla [key] (o la primera si no existe: una clave vieja nunca
/// rompe la pantalla).
InvitationTemplate invitationTemplate(String key) {
  final clean = key.trim();
  for (final t in kInvitationTemplates) {
    if (t.key == clean) return t;
  }
  return kInvitationTemplates.first;
}

/// Catálogo agrupado por ocasión, en el orden en que se muestra.
List<({String occasion, List<InvitationTemplate> templates})>
invitationCatalog() {
  final out = <({String occasion, List<InvitationTemplate> templates})>[];
  for (final t in kInvitationTemplates) {
    final i = out.indexWhere((g) => g.occasion == t.occasion);
    if (i < 0) {
      out.add((occasion: t.occasion, templates: [t]));
    } else {
      out[i].templates.add(t);
    }
  }
  return out;
}

/// Familias tipográficas que se pueden elegir dentro de una plantilla.
const List<({String key, String label})> kInvitationFonts = [
  (key: 'clasica', label: 'Elegante'),
  (key: 'moderna', label: 'Moderna'),
  (key: 'romantica', label: 'Manuscrita'),
];

/// Colores de acento que ofrece el diseñador (`#RRGGBB` en mayúsculas).
const List<String> kInvitationAccents = [
  'B76E79',
  'D9A95E',
  'C9A96E',
  'E8A0B4',
  'A8895C',
  '6C8A5A',
  'FF5CA8',
  'D94A8C',
  '5B8DEF',
  '8E6CEF',
  'E07A3F',
  '22A699',
];

/// Las portadas que se pueden combinar con cualquier plantilla.
///
/// La portada es independiente del resto del diseño: cambiar de plantilla no
/// obliga a conservar el mismo sobre, y una portada se puede reutilizar con
/// otro color, otra animación y otros componentes.
const List<String> kInvitationCoverStyles = [
  'rosa',
  'carta',
  'xv',
  'noche',
  'cortina',
  'clasica',
];

/// Fondos de la portada Carta. Son escenas de boda, no solo colores.
const List<({String key, String label, String hint})>
kInvitationCoverBackdrops = [
  (key: 'marfil', label: 'Marfil', hint: 'Papel, rosas y aros dorados'),
  (key: 'jardin', label: 'Jardín', hint: 'Follaje y luz de jardín'),
  (key: 'seda', label: 'Seda', hint: 'Champán y pliegues suaves'),
  (key: 'corte', label: 'Corte', hint: 'Marco doble dorado y filigrana'),
  (key: 'perla', label: 'Perla', hint: 'Marfil perla con filete plateado'),
];

/// Las secciones que se pueden prender/apagar en una invitación.
const List<({String key, String label})> kInvitationSections = [
  (key: 'cover', label: 'Portada (sobre)'),
  (key: 'countdown', label: 'Cuenta regresiva'),
  (key: 'quote', label: 'Frase'),
  (key: 'photos', label: 'Fotos'),
  (key: 'families', label: 'Familias'),
  (key: 'details', label: 'Detalles'),
  (key: 'hashtag', label: 'Hashtag'),
  (key: 'memories', label: 'Recuerdos'),
  (key: 'itinerary', label: 'Itinerario'),
  (key: 'rsvp', label: 'Confirmación'),
  (key: 'footer', label: 'Pie de la invitación'),
  (key: 'music', label: 'Música'),
];

/// Las secciones que se pueden mover dentro del flujo de la invitación.
///
/// La portada, la cuenta regresiva y la música son capas fijas: la primera
/// envuelve la página, la segunda vive dentro de la tarjeta principal y la
/// tercera es el audio de ambiente.
const List<String> kInvitationFlowSections = [
  'families',
  'details',
  'hashtag',
  'itinerary',
  'footer',
];

/// Lee el orden guardado y descarta claves viejas o repetidas.
List<String> _sectionOrderFromJson(Object? raw) {
  final out = <String>[];
  if (raw is! List) return out;
  for (final item in raw) {
    final key = '$item'.trim();
    if (kInvitationFlowSections.contains(key) && !out.contains(key)) {
      out.add(key);
    }
  }
  return out;
}

/// Una familia dentro de la invitación («Papás», «Padrinos»…).
class InvitationFamily {
  const InvitationFamily({this.title = '', this.names = const <String>[]});

  final String title;
  final List<String> names;

  bool get isEmpty =>
      title.trim().isEmpty && names.every((n) => n.trim().isEmpty);

  factory InvitationFamily.fromJson(Object? raw) {
    if (raw is Map) {
      final names = <String>[];
      for (final n in (raw['names'] as List?) ?? const []) {
        final s = '$n'.trim();
        if (s.isNotEmpty) names.add(s);
      }
      return InvitationFamily(
        title: '${raw['title'] ?? ''}'.trim(),
        names: names,
      );
    }
    return InvitationFamily(title: '$raw'.trim());
  }

  Map<String, dynamic> toJson() => {
    'title': title.trim(),
    'names': [for (final n in names) n.trim()],
  };
}

/// Una tarjeta de «Detalles» (misa, recepción, vestimenta, regalo…).
class InvitationDetail {
  const InvitationDetail({
    this.title = '',
    this.time = '',
    this.place = '',
    this.mapUrl = '',
    this.note = '',
    this.icon = '✦',
  });

  final String title;
  final String time;
  final String place;

  /// Liga de Google Maps o similar ('' = sin botón).
  final String mapUrl;

  /// Texto libre debajo del lugar (vestimenta, sugerencia…).
  final String note;

  /// Emoji del icono de la tarjeta.
  final String icon;

  bool get isEmpty =>
      title.trim().isEmpty &&
      time.trim().isEmpty &&
      place.trim().isEmpty &&
      note.trim().isEmpty;

  factory InvitationDetail.fromJson(Object? raw) {
    if (raw is! Map) return const InvitationDetail();
    return InvitationDetail(
      title: '${raw['title'] ?? ''}'.trim(),
      time: '${raw['time'] ?? ''}'.trim(),
      place: '${raw['place'] ?? ''}'.trim(),
      mapUrl: '${raw['mapUrl'] ?? ''}'.trim(),
      note: '${raw['note'] ?? ''}'.trim(),
      icon: '${raw['icon'] ?? '✦'}'.trim().isEmpty
          ? '✦'
          : '${raw['icon']}'.trim(),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title.trim(),
    'time': time.trim(),
    'place': place.trim(),
    'mapUrl': mapUrl.trim(),
    'note': note.trim(),
    'icon': icon.trim(),
  };
}

/// Un momento del itinerario («7:30 PM · Acción de gracias»).
class InvitationStop {
  const InvitationStop({this.time = '', this.title = ''});

  final String time;
  final String title;

  bool get isEmpty => time.trim().isEmpty && title.trim().isEmpty;

  factory InvitationStop.fromJson(Object? raw) {
    if (raw is! Map) return const InvitationStop();
    return InvitationStop(
      time: '${raw['time'] ?? ''}'.trim(),
      title: '${raw['title'] ?? ''}'.trim(),
    );
  }

  Map<String, dynamic> toJson() => {'time': time.trim(), 'title': title.trim()};
}

/// Una INVITACIÓN tal como se guarda y se edita.
class Invitation {
  const Invitation({
    this.id = 0,
    this.title = '',
    this.template = 'sobre-xv',
    this.preset = '',
    this.componentDesigns = const <String, String>{},
    this.occasion = 'XV',
    this.headline = '',
    this.subheadline = '',
    this.dateText = '',
    this.timeText = '',
    this.placeName = '',
    this.placeAddress = '',
    this.message = '',
    this.dressCode = '',
    this.rsvpPhone = '',
    this.accent = '',
    this.font = '',
    this.photos = const <String>[],
    this.bgMedia = '',
    this.detailsMedia = '',
    this.bgColor = '',
    this.effect = '',
    this.coverStyle = '',
    this.coverBackdrop = '',
    this.sections = const <String>[],
    this.sectionOrder = const <String>[],
    this.eventAt = '',
    this.quote = '',
    this.verticalTitle = '',
    this.arcTitle = '',
    this.envelopeText = '',
    this.familiesTitle = '',
    this.detailsTitle = '',
    this.detailsIntro = '',
    this.itineraryTitle = '',
    this.hashtagIntro = '',
    this.memoriesTitle = '',
    this.memoriesIntro = '',
    this.memoriesFolder = '',
    this.footerMessage = '',
    this.families = const <InvitationFamily>[],
    this.details = const <InvitationDetail>[],
    this.itinerary = const <InvitationStop>[],
    this.hashtag = '',
    this.musicUrl = '',
    this.slug = '',
    this.published = false,
    this.updated = '',
  });

  /// 0 = todavía no está guardada.
  final int id;

  /// Nombre INTERNO (el que se ve en el listado del panel).
  final String title;

  final String template;

  /// La plantilla-compuesta elegida (`kInvitationTemplateRecipes`). Vacío =
  /// la combinación de fábrica del documento base.
  final String preset;

  /// Diseños elegidos para cada componente. Las claves que falten usan la
  /// plantilla o el diseño de fábrica.
  final Map<String, String> componentDesigns;

  final String occasion;
  final String headline;
  final String subheadline;
  final String dateText;
  final String timeText;
  final String placeName;
  final String placeAddress;
  final String message;
  final String dressCode;
  final String rsvpPhone;

  /// Acento propio (`#RRGGBB`); vacío = el de la plantilla.
  final String accent;

  /// Tipografía propia (`clasica`/`moderna`/`romantica`); vacío = la de la
  /// plantilla.
  final String font;

  /// Las tres fotos de las polaroids (URLs públicas del Drive). La primera
  /// también es la imagen que se ve al compartir la liga.
  final List<String> photos;

  /// Foto o VÍDEO de fondo de toda la invitación ('' = solo color).
  final String bgMedia;

  /// Foto o vídeo de fondo SOLO para la sección «Los detalles».
  final String detailsMedia;

  /// Color de fondo propio (`#RRGGBB`); vacío = el de la plantilla.
  final String bgColor;

  /// Efecto de ambiente del diseño: `petalos`, `burbujas`, `destellos`,
  /// `corazones`, `confeti` o `ninguno`. Vacío = pétalos.
  final String effect;

  /// Estilo de portada (`kInvitationCoverStyles`). Vacío = el de la
  /// plantilla: Rosa Pastel para la plantilla rosa y Carta para Marfil.
  final String coverStyle;

  /// Fondo de la portada Carta (`kInvitationCoverBackdrops`). Vacío = marfil.
  final String coverBackdrop;

  /// Secciones activas (`kInvitationSections`). Vacío = todas.
  final List<String> sections;

  /// Orden propio de las secciones móviles (`kInvitationFlowSections`).
  /// Vacío = el orden original de la plantilla.
  final List<String> sectionOrder;

  /// Fecha y hora del evento para la cuenta regresiva (`2026-10-10T19:30`).
  final String eventAt;

  /// La frase del recuadro ('' = se usa [message]).
  final String quote;

  /// Textos del diseño. Vacío = el texto original de ReynaCoot.
  final String verticalTitle;
  final String arcTitle;
  final String envelopeText;
  final String familiesTitle;
  final String detailsTitle;
  final String detailsIntro;
  final String itineraryTitle;
  final String hashtagIntro;

  /// Título e introducción de la galería colaborativa «Recuerdos».
  final String memoriesTitle;
  final String memoriesIntro;

  /// Carpeta del Drive donde se guardan las fotos de los invitados.
  /// Vacío = `Recuerdos/<liga>`.
  final String memoriesFolder;
  final String footerMessage;

  final List<InvitationFamily> families;
  final List<InvitationDetail> details;
  final List<InvitationStop> itinerary;

  /// Hashtag del evento (`#ReynaXV2026`).
  final String hashtag;

  /// Música de fondo (mp3 o similar).
  final String musicUrl;

  /// Liga pública (la genera el servidor al publicar).
  final String slug;
  final bool published;
  final String updated;

  factory Invitation.fromJson(Map<String, dynamic> json) {
    final photos = <String>[];
    for (final p in (json['photos'] as List?) ?? const []) {
      final url = '$p'.trim();
      if (url.isNotEmpty && !photos.contains(url)) photos.add(url);
    }
    final design = _designOf(json['design']);
    final storedSections = <String>[
      for (final s in (design['sections'] as List?) ?? const [])
        if ('$s'.trim().isNotEmpty) '$s'.trim(),
    ];
    final sectionVersion = (design['sectionVersion'] as num?)?.toInt() ?? 1;
    final sections = <String>[...storedSections];
    if (sectionVersion < 2 && sections.isNotEmpty) {
      // Las invitaciones guardadas antes de los componentes no conocían la
      // frase, las fotos ni la confirmación: se añaden encendidas para no
      // hacerlas desaparecer al abrir una invitación vieja.
      for (final key in const ['quote', 'photos', 'rsvp']) {
        if (!sections.contains(key)) sections.add(key);
      }
    }
    return Invitation(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: '${json['title'] ?? ''}',
      template: '${json['template'] ?? 'sobre-xv'}',
      preset: '${design['preset'] ?? ''}'.trim(),
      componentDesigns: sanitizeComponentDesigns(design['components']),
      occasion: '${json['occasion'] ?? ''}',
      headline: '${json['headline'] ?? ''}',
      subheadline: '${json['subheadline'] ?? ''}',
      dateText: '${json['dateText'] ?? ''}',
      timeText: '${json['timeText'] ?? ''}',
      placeName: '${json['placeName'] ?? ''}',
      placeAddress: '${json['placeAddress'] ?? ''}',
      message: '${json['message'] ?? ''}',
      dressCode: '${json['dressCode'] ?? ''}',
      rsvpPhone: '${json['rsvpPhone'] ?? ''}',
      accent: '${json['accent'] ?? ''}',
      font: '${json['font'] ?? ''}',
      photos: photos,
      bgMedia: '${design['bgMedia'] ?? ''}'.trim(),
      detailsMedia: '${design['detailsMedia'] ?? ''}'.trim(),
      bgColor: '${design['bgColor'] ?? ''}'.trim(),
      effect: '${design['effect'] ?? ''}'.trim(),
      coverStyle: '${design['coverStyle'] ?? ''}'.trim(),
      coverBackdrop: '${design['coverBackdrop'] ?? ''}'.trim(),
      sections: sections,
      sectionOrder: _sectionOrderFromJson(design['sectionOrder']),
      eventAt: '${design['eventAt'] ?? ''}'.trim(),
      quote: '${design['quote'] ?? ''}'.trim(),
      verticalTitle: '${design['verticalTitle'] ?? ''}'.trim(),
      arcTitle: '${design['arcTitle'] ?? ''}'.trim(),
      envelopeText: '${design['envelopeText'] ?? ''}'.trim(),
      familiesTitle: '${design['familiesTitle'] ?? ''}'.trim(),
      detailsTitle: '${design['detailsTitle'] ?? ''}'.trim(),
      detailsIntro: '${design['detailsIntro'] ?? ''}'.trim(),
      itineraryTitle: '${design['itineraryTitle'] ?? ''}'.trim(),
      hashtagIntro: '${design['hashtagIntro'] ?? ''}'.trim(),
      memoriesTitle: '${design['memoriesTitle'] ?? ''}'.trim(),
      memoriesIntro: '${design['memoriesIntro'] ?? ''}'.trim(),
      memoriesFolder: '${design['memoriesFolder'] ?? ''}'.trim(),
      footerMessage: '${design['footerMessage'] ?? ''}'.trim(),
      families: [
        for (final f in (design['families'] as List?) ?? const [])
          if (!InvitationFamily.fromJson(f).isEmpty)
            InvitationFamily.fromJson(f),
      ],
      details: [
        for (final d in (design['details'] as List?) ?? const [])
          if (!InvitationDetail.fromJson(d).isEmpty)
            InvitationDetail.fromJson(d),
      ],
      itinerary: [
        for (final s in (design['itinerary'] as List?) ?? const [])
          if (!InvitationStop.fromJson(s).isEmpty) InvitationStop.fromJson(s),
      ],
      hashtag: '${design['hashtag'] ?? ''}'.trim(),
      musicUrl: '${design['musicUrl'] ?? ''}'.trim(),
      slug: '${json['slug'] ?? ''}',
      published: json['published'] == true,
      updated: '${json['updated'] ?? ''}',
    );
  }

  /// Lo que se manda a la API. El HTML viaja aparte (lo arma `HsApi`).
  Map<String, dynamic> toJson() => {
    if (id > 0) 'id': id,
    'title': title.trim(),
    'template': template,
    'occasion': occasion.trim(),
    'headline': headline.trim(),
    'subheadline': subheadline.trim(),
    'dateText': dateText.trim(),
    'timeText': timeText.trim(),
    'placeName': placeName.trim(),
    'placeAddress': placeAddress.trim(),
    'message': message.trim(),
    'dressCode': dressCode.trim(),
    'rsvpPhone': rsvpPhone.trim(),
    'accent': accent.trim(),
    'font': font.trim(),
    'photos': photos,
    'published': published,
    'design': {
      'bgMedia': bgMedia.trim(),
      'detailsMedia': detailsMedia.trim(),
      'bgColor': bgColor.trim(),
      'effect': effect.trim(),
      'preset': preset,
      'components': {for (final e in componentDesigns.entries) e.key: e.value},
      'coverStyle': coverStyleKey,
      'coverBackdrop': coverBackdropKey,
      'sections': sections,
      'sectionVersion': 2,
      'sectionOrder': sectionOrder,
      'eventAt': eventAt.trim(),
      'quote': quote.trim(),
      'verticalTitle': verticalTitle.trim(),
      'arcTitle': arcTitle.trim(),
      'envelopeText': envelopeText.trim(),
      'familiesTitle': familiesTitle.trim(),
      'detailsTitle': detailsTitle.trim(),
      'detailsIntro': detailsIntro.trim(),
      'itineraryTitle': itineraryTitle.trim(),
      'hashtagIntro': hashtagIntro.trim(),
      'memoriesTitle': memoriesTitle.trim(),
      'memoriesIntro': memoriesIntro.trim(),
      'memoriesFolder': memoriesFolder.trim(),
      'footerMessage': footerMessage.trim(),
      'families': [for (final f in families) f.toJson()],
      'details': [for (final d in details) d.toJson()],
      'itinerary': [for (final s in itinerary) s.toJson()],
      'hashtag': hashtag.trim(),
      'musicUrl': musicUrl.trim(),
    },
  };

  Invitation copyWith({
    int? id,
    String? title,
    String? template,
    String? preset,
    Map<String, String>? componentDesigns,
    String? occasion,
    String? headline,
    String? subheadline,
    String? dateText,
    String? timeText,
    String? placeName,
    String? placeAddress,
    String? message,
    String? dressCode,
    String? rsvpPhone,
    String? accent,
    String? font,
    List<String>? photos,
    String? bgMedia,
    String? detailsMedia,
    String? bgColor,
    String? effect,
    String? coverStyle,
    String? coverBackdrop,
    List<String>? sections,
    List<String>? sectionOrder,
    String? eventAt,
    String? quote,
    String? verticalTitle,
    String? arcTitle,
    String? envelopeText,
    String? familiesTitle,
    String? detailsTitle,
    String? detailsIntro,
    String? itineraryTitle,
    String? hashtagIntro,
    String? memoriesTitle,
    String? memoriesIntro,
    String? memoriesFolder,
    String? footerMessage,
    List<InvitationFamily>? families,
    List<InvitationDetail>? details,
    List<InvitationStop>? itinerary,
    String? hashtag,
    String? musicUrl,
    String? slug,
    bool? published,
    String? updated,
  }) {
    return Invitation(
      id: id ?? this.id,
      title: title ?? this.title,
      template: template ?? this.template,
      preset: preset ?? this.preset,
      componentDesigns: componentDesigns ?? this.componentDesigns,
      occasion: occasion ?? this.occasion,
      headline: headline ?? this.headline,
      subheadline: subheadline ?? this.subheadline,
      dateText: dateText ?? this.dateText,
      timeText: timeText ?? this.timeText,
      placeName: placeName ?? this.placeName,
      placeAddress: placeAddress ?? this.placeAddress,
      message: message ?? this.message,
      dressCode: dressCode ?? this.dressCode,
      rsvpPhone: rsvpPhone ?? this.rsvpPhone,
      accent: accent ?? this.accent,
      font: font ?? this.font,
      photos: photos ?? this.photos,
      bgMedia: bgMedia ?? this.bgMedia,
      detailsMedia: detailsMedia ?? this.detailsMedia,
      bgColor: bgColor ?? this.bgColor,
      effect: effect ?? this.effect,
      coverStyle: coverStyle ?? this.coverStyle,
      coverBackdrop: coverBackdrop ?? this.coverBackdrop,
      sections: sections ?? this.sections,
      sectionOrder: sectionOrder ?? this.sectionOrder,
      eventAt: eventAt ?? this.eventAt,
      quote: quote ?? this.quote,
      verticalTitle: verticalTitle ?? this.verticalTitle,
      arcTitle: arcTitle ?? this.arcTitle,
      envelopeText: envelopeText ?? this.envelopeText,
      familiesTitle: familiesTitle ?? this.familiesTitle,
      detailsTitle: detailsTitle ?? this.detailsTitle,
      detailsIntro: detailsIntro ?? this.detailsIntro,
      itineraryTitle: itineraryTitle ?? this.itineraryTitle,
      hashtagIntro: hashtagIntro ?? this.hashtagIntro,
      memoriesTitle: memoriesTitle ?? this.memoriesTitle,
      memoriesIntro: memoriesIntro ?? this.memoriesIntro,
      memoriesFolder: memoriesFolder ?? this.memoriesFolder,
      footerMessage: footerMessage ?? this.footerMessage,
      families: families ?? this.families,
      details: details ?? this.details,
      itinerary: itinerary ?? this.itinerary,
      hashtag: hashtag ?? this.hashtag,
      musicUrl: musicUrl ?? this.musicUrl,
      slug: slug ?? this.slug,
      published: published ?? this.published,
      updated: updated ?? this.updated,
    );
  }

  InvitationTemplate get design => invitationTemplate(template);

  /// La plantilla-compuesta activa. Las invitaciones anteriores a este
  /// catálogo no tienen `preset`: caen en la combinación de su documento base.
  InvitationTemplateRecipe get templateRecipe =>
      templateRecipeForInvitation(preset: preset, template: template);

  /// El diseño efectivo de un componente. La portada sigue guardándose en
  /// `coverStyle` para no romper las ligas existentes.
  String componentDesign(String key) {
    final clean = key.trim().toLowerCase();
    if (clean == 'cover') return coverStyleKey;
    final component = invitationComponentForKey(clean);
    if (component == null) return '';
    final own = component.design(componentDesigns[clean] ?? '')?.key;
    if (own != null) {
      return own;
    }
    final fromRecipe = component
        .design(templateRecipe.components[clean] ?? '')
        ?.key;
    return fromRecipe ?? component.fallback;
  }

  /// El acento propio si es válido; si no, el de la plantilla.
  Color get accentColor {
    final own = _colorOf(accent);
    return own ?? design.accent;
  }

  String get accentHex => _hex(accentColor);

  /// El fondo propio si es válido; si no, el de la plantilla.
  Color get backgroundColor {
    final own = _colorOf(bgColor);
    return own ?? design.bg;
  }

  /// La portada efectiva. Las invitaciones viejas no guardaban este campo:
  /// las rosas siguen abriendo con su sobre y Marfil conserva su carta.
  String get coverStyleKey {
    final clean = coverStyle.trim().toLowerCase();
    if (kInvitationCoverStyles.contains(clean)) return clean;
    final recipe = templateRecipe;
    if (kInvitationCoverStyles.contains(recipe.coverStyle)) {
      return recipe.coverStyle;
    }
    return template.trim() == 'boda-marfil' ? 'carta' : 'rosa';
  }

  /// El fondo de la Carta efectivo. Las invitaciones viejas caen en marfil.
  String get coverBackdropKey {
    final clean = coverBackdrop.trim().toLowerCase();
    for (final b in kInvitationCoverBackdrops) {
      if (b.key == clean) return clean;
    }
    final recipe = templateRecipe;
    for (final b in kInvitationCoverBackdrops) {
      if (b.key == recipe.coverBackdrop) return b.key;
    }
    return 'marfil';
  }

  /// Tipografía efectiva (propia o de la plantilla).
  String get fontKey {
    final own = font.trim();
    return own.isEmpty ? design.font : own;
  }

  /// Lo que se pone en grande: los nombres del evento.
  String get displayTitle {
    final head = headline.trim();
    return head.isNotEmpty ? head : title.trim();
  }

  /// «Boda de Ana & Luis» para el listado del panel.
  String get panelName {
    final t = title.trim();
    if (t.isNotEmpty) return t;
    final head = headline.trim();
    return head.isNotEmpty ? head : 'Invitación sin nombre';
  }

  /// ¿Está prendida la sección [key]?
  bool sectionOn(String key) => sections.isEmpty || sections.contains(key);

  /// El orden efectivo de las secciones móviles.
  ///
  /// Marfil usa otro orden original (itinerario antes de detalles); los demás
  /// documentos siguen el orden de ReynaCoot. Las claves que falten se añaden
  /// al final para que una invitación vieja nunca pierda una sección.
  List<String> get flowSectionOrder {
    final defaults = template.trim() == 'boda-marfil'
        ? const ['itinerary', 'details', 'families', 'hashtag', 'footer']
        : const ['families', 'details', 'hashtag', 'itinerary', 'footer'];
    final ordered = <String>[];
    for (final key in sectionOrder) {
      if (kInvitationFlowSections.contains(key) && !ordered.contains(key)) {
        ordered.add(key);
      }
    }
    for (final key in defaults) {
      if (!ordered.contains(key)) ordered.add(key);
    }
    return ordered;
  }

  /// Liga pública ('' si todavía no se ha publicado).
  ///
  /// Es la WEB del estudio con el código de la invitación:
  /// `https://hardstreet.com/?invitation=abc123`. La web (carpeta
  /// `Hardstreet`) reconoce ese parámetro y muestra el HTML guardado, así
  /// que la liga que se comparte es la del sitio y no la de la API.
  String get shareUrl {
    final code = slug.trim();
    if (code.isEmpty) return '';
    final base = AppConstants.publicSiteBase.replaceFirst(RegExp(r'/+$'), '');
    return '$base/?invitation=$code';
  }

  /// ¿Se puede compartir ya? Publicada y con liga.
  bool get shareable => published && slug.trim().isNotEmpty;

  /// Fecha/hora del evento, si `eventAt` es válido.
  DateTime? get eventDate => parseInvitationDate(eventAt);

  /// La frase del recuadro (la de `quote` o, si falta, el mensaje).
  String get quoteText {
    final own = quote.trim();
    return own.isNotEmpty ? own : message.trim();
  }

  /// Una muestra con el diseño [templateKey], para el catálogo y la vista
  /// previa mientras se elige plantilla.
  factory Invitation.sample(String templateKey) {
    final t = invitationTemplate(templateKey);
    final recipe = defaultTemplateRecipeForBase(t.key);
    final (
      :headline,
      :sub,
      :people,
      :message,
      :place,
      :address,
    ) = switch (t.occasion) {
      'Boda' => (
        headline: 'Ana & Luis',
        sub: '¡Nos casamos!',
        people: const [
          InvitationFamily(
            title: 'Padres de la novia',
            names: ['Jorge Lara', 'María Pineda'],
          ),
          InvitationFamily(
            title: 'Padres del novio',
            names: ['Raúl Méndez', 'Lucía Ferrer'],
          ),
        ],
        message:
            'Hay momentos que se vuelven eternos cuando se comparten. '
            'Nos encantaría tenerte en el nuestro.',
        place: 'Hacienda San José',
        address: 'Camino Real 120, Guadalajara',
      ),
      'Cumpleaños' => (
        headline: 'Sofía',
        sub: '¡Cumple 18!',
        people: const [
          InvitationFamily(
            title: 'Mis papás',
            names: ['Diego Ramos', 'Elena Vidal'],
          ),
          InvitationFamily(
            title: 'Mis abuelos',
            names: ['Rosa Vidal', 'Hugo Ramos'],
          ),
        ],
        message:
            'Una noche para celebrar, bailar y brindar juntos. ¡No faltes!',
        place: 'Terraza del Lago',
        address: 'Av. del Lago 44, Guadalajara',
      ),
      _ => (
        headline: 'Valeria',
        sub: 'Estás invitad@ a celebrar conmigo',
        people: const [
          InvitationFamily(
            title: 'Papás',
            names: ['Jose Enrique Coot Ayil', 'Wendy Lulie Ruiz Canche'],
          ),
          InvitationFamily(
            title: 'Padrinos',
            names: ['Marcelino Ruiz Euan', 'Carolina Canche Padrón'],
          ),
        ],
        message:
            'Hoy dejo atrás mi niñez para comenzar un nuevo capítulo, '
            'rodeada del amor de quienes más quiero. Por ser parte de '
            'ellos, es muy importante que estés en mis 15 años.',
        place: 'Salón Jardín Real',
        address: 'Calle 21 #204, Mérida',
      ),
    };
    return Invitation(
      title: headline,
      template: t.key,
      preset: recipe.key,
      componentDesigns: templateRecipeComponents(recipe),
      occasion: t.occasion,
      headline: headline,
      subheadline: sub,
      dateText: 'Sábado 14 de noviembre de 2026',
      timeText: '7:30 pm',
      placeName: place,
      placeAddress: address,
      message: message,
      dressCode: 'Formal',
      rsvpPhone: '5219991234567',
      eventAt: '2026-11-14T19:30',
      families: people,
      details: [
        InvitationDetail(
          title: 'Ceremonia',
          time: '7:30 PM',
          place: 'Iglesia Santa Úrsula',
          icon: '⛪',
        ),
        InvitationDetail(
          title: 'Recepción',
          time: '9:00 PM',
          place: place,
          mapUrl: 'https://maps.google.com/?q=$place',
          icon: '🥂',
        ),
        const InvitationDetail(
          title: 'Código de vestimenta',
          note: 'Formal',
          icon: '👗',
        ),
      ],
      itinerary: const [
        InvitationStop(time: '7:30 PM', title: 'Ceremonia'),
        InvitationStop(time: '9:00 PM', title: 'Recepción'),
        InvitationStop(time: '10:00 PM', title: 'Presentación'),
        InvitationStop(time: '11:00 PM', title: 'Cena'),
        InvitationStop(time: '3:00 AM', title: 'Fin del evento'),
      ],
      hashtag: '#${headline.split(' ').first}2026',
    );
  }

  /// Una muestra creada a partir de una plantilla-compuesta. Conserva los
  /// textos de la ocasión de la base y aplica la paleta, la portada y los
  /// diseños de los componentes de la receta.
  factory Invitation.samplePreset(String presetKey) {
    final recipe =
        invitationTemplateRecipeForKey(presetKey) ??
        defaultTemplateRecipeForBase('sobre-xv');
    final base = Invitation.sample(recipe.baseTemplate);
    return base.copyWith(
      preset: recipe.key,
      occasion: recipe.occasion,
      coverStyle: recipe.coverStyle,
      coverBackdrop: recipe.coverBackdrop,
      accent: recipe.accent,
      bgColor: recipe.bgColor,
      effect: recipe.effect,
      font: recipe.font,
      componentDesigns: templateRecipeComponents(recipe),
    );
  }
}

// ------------------------------------------------------------------
// Utilidades compartidas por el HTML y la vista previa
// ------------------------------------------------------------------

/// `#RRGGBB` de un color.
String colorHex(Color c) => _hex(c);

String _hex(Color c) {
  String two(double v) =>
      (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${two(c.r)}${two(c.g)}${two(c.b)}'.toUpperCase();
}

/// Color de `#RRGGBB` (null si no es válido).
Color? colorOfHex(String raw) => _colorOf(raw);

Color? _colorOf(String raw) {
  final s = raw.trim().replaceAll('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(s)) return null;
  return Color(int.parse('FF$s', radix: 16));
}

/// ¿La dirección es http(s)? (lo único que se acepta en fotos y ligas).
bool isHttpUrl(String url) {
  final s = url.trim();
  return s.startsWith('http://') || s.startsWith('https://');
}

/// ¿El medio de fondo es un vídeo? (mp4/webm/ogv/mov).
bool isVideoUrl(String url) {
  final s = url.trim().toLowerCase().split('?').first.split('#').first;
  return s.endsWith('.mp4') ||
      s.endsWith('.webm') ||
      s.endsWith('.ogv') ||
      s.endsWith('.mov') ||
      s.endsWith('.m4v');
}

/// Fecha de `eventAt` (`2026-10-10T19:30` o `2026-10-10 19:30`).
DateTime? parseInvitationDate(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s.replaceFirst(' ', 'T'));
}

const List<String> _monthsEs = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

const List<String> _weekdaysEs = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
];

/// La fecha larga en español («Sábado 14 de noviembre de 2026»).
String invitationDateLabel(DateTime d) {
  final day = _weekdaysEs[d.weekday - 1];
  final weekday = day.isEmpty
      ? day
      : '${day[0].toUpperCase()}${day.substring(1)}';
  return '$weekday ${d.day} de ${_monthsEs[d.month - 1]} de ${d.year}';
}

/// La hora en formato de 12 horas («7:30 pm»).
String invitationTimeLabel(DateTime d, {bool upper = false}) {
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final suffix = d.hour < 12 ? 'am' : 'pm';
  return '$hour:${d.minute.toString().padLeft(2, '0')} '
      '${upper ? suffix.toUpperCase() : suffix}';
}

/// `2026-11-14T19:30` (lo que guarda y lee la cuenta regresiva).
String invitationIsoMinutes(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}T'
    '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';

/// Lee una hora escrita («7:30 PM», «19:30», «7 PM») de un campo de texto.
({int hour, int minute})? parseInvitationClock(String raw) {
  final m = RegExp(
    r'^\s*(\d{1,2})(?::(\d{2}))?\s*([ap])?\s*\.?\s*m?\s*\.?\s*$',
    caseSensitive: false,
  ).firstMatch(raw);
  if (m == null) return null;
  var hour = int.parse(m.group(1)!);
  final minute = int.parse(m.group(2) ?? '0');
  if (minute > 59 || hour > 23) return null;
  final suffix = m.group(3)?.toLowerCase();
  if (suffix != null && hour >= 1 && hour <= 12) {
    hour = (hour % 12) + (suffix == 'p' ? 12 : 0);
  }
  return (hour: hour, minute: minute);
}

/// Cómo se pinta la fecha en la cápsula de la portada.
({String weekday, String day, String month, String year, String time})
invitationDateParts(DateTime d) {
  final time = d.hour == 0 && d.minute == 0
      ? ''
      : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  return (
    weekday: _weekdaysEs[d.weekday - 1],
    day: '${d.day}',
    month: _monthsEs[d.month - 1],
    year: '${d.year}',
    time: time,
  );
}

// ------------------------------------------------------------------
// Texto plano del editor <-> listas de la invitación
// ------------------------------------------------------------------
// El editor no obliga a llenar formularios anidados: cada bloque se escribe
// en unas líneas con un separador claro. Así se puede pegar y editar rápido
// sin perder nada de lo que se guarda en `design`.
// ------------------------------------------------------------------

/// «Papás: Nombre, Nombre» por línea.
List<InvitationFamily> parseFamiliesText(String raw) {
  final out = <InvitationFamily>[];
  for (final line in raw.split(RegExp(r'\r?\n'))) {
    final s = line.trim();
    if (s.isEmpty) continue;
    final i = s.indexOf(':');
    final title = i >= 0 ? s.substring(0, i).trim() : '';
    final names = (i >= 0 ? s.substring(i + 1) : s)
        .split(',')
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .toList(growable: false);
    if (title.isEmpty && names.isEmpty) continue;
    out.add(InvitationFamily(title: title, names: names));
  }
  return out;
}

String familiesToText(List<InvitationFamily> families) => families
    .where((f) => !f.isEmpty)
    .map(
      (f) => f.names.isEmpty
          ? f.title
          : '${f.title.isEmpty ? 'Familia' : f.title}: '
                '${f.names.join(', ')}',
    )
    .join('\n');

/// «Título | Hora | Lugar | Mapa | Nota | Icono» por línea (solo el título
/// es obligatorio; los campos vacíos se dejan con dos pipes seguidos).
List<InvitationDetail> parseDetailsText(String raw) {
  final out = <InvitationDetail>[];
  for (final line in raw.split(RegExp(r'\r?\n'))) {
    final s = line.trim();
    if (s.isEmpty) continue;
    final parts = s.split('|').map((p) => p.trim()).toList();
    String at(int i) => i < parts.length ? parts[i] : '';
    final detail = InvitationDetail(
      title: at(0),
      time: at(1),
      place: at(2),
      mapUrl: at(3),
      note: at(4),
      icon: at(5).isEmpty ? '✦' : at(5),
    );
    if (!detail.isEmpty) out.add(detail);
  }
  return out;
}

String detailsToText(List<InvitationDetail> details) => details
    .where((d) => !d.isEmpty)
    .map(
      (d) => [
        d.title,
        d.time,
        d.place,
        d.mapUrl,
        d.note,
        d.icon == '✦' ? '' : d.icon,
      ].join(' | ').trim(),
    )
    .join('\n');

/// «Hora | Actividad» por línea.
List<InvitationStop> parseItineraryText(String raw) {
  final out = <InvitationStop>[];
  for (final line in raw.split(RegExp(r'\r?\n'))) {
    final s = line.trim();
    if (s.isEmpty) continue;
    final i = s.indexOf('|');
    final stop = i >= 0
        ? InvitationStop(
            time: s.substring(0, i).trim(),
            title: s.substring(i + 1).trim(),
          )
        : InvitationStop(title: s);
    if (!stop.isEmpty) out.add(stop);
  }
  return out;
}

String itineraryToText(List<InvitationStop> stops) => stops
    .where((s) => !s.isEmpty)
    .map((s) => '${s.time} | ${s.title}'.trim())
    .join('\n');

/// El diseño de una fila de la API: mapa directo o JSON en texto.
Map<String, dynamic> _designOf(Object? raw) {
  if (raw is Map) return raw.cast<String, dynamic>();
  if (raw is String && raw.trim().startsWith('{')) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {
      // Un JSON roto no debe romper la pantalla: se usa el diseño por
      // defecto de la plantilla.
    }
  }
  return const <String, dynamic>{};
}

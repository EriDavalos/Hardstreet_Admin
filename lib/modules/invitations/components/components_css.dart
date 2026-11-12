import 'package:hardstreet_admin/modules/invitations/models/invitation_model.dart';

import 'package:hardstreet_admin/modules/invitations/components/component_catalog.dart';
import 'package:hardstreet_admin/modules/invitations/components/countdown/countdown_component.dart';
import 'package:hardstreet_admin/modules/invitations/components/details/details_component.dart';
import 'package:hardstreet_admin/modules/invitations/components/families/families_component.dart';
import 'package:hardstreet_admin/modules/invitations/components/footer/footer_component.dart';
import 'package:hardstreet_admin/modules/invitations/components/hashtag/hashtag_component.dart';
import 'package:hardstreet_admin/modules/invitations/components/itinerary/itinerary_component.dart';
import 'package:hardstreet_admin/modules/invitations/components/music/music_component.dart';
import 'package:hardstreet_admin/modules/invitations/components/photos/photos_component.dart';
import 'package:hardstreet_admin/modules/invitations/components/quote/quote_component.dart';
import 'package:hardstreet_admin/modules/invitations/components/rsvp/rsvp_component.dart';

/// Envuelve un bloque generado con la clave del componente y su diseño.
///
/// El envoltorio usa `display: contents`, así que no altera el flujo del
/// documento original: sólo añade el gancho que el CSS necesita para
/// cambiar el diseño elegido.
String invitationComponentBlock(Invitation inv, String key, String html) {
  if (html.trim().isEmpty) return '';
  final component = invitationComponentForKey(key);
  if (component == null) return html;
  final design =
      component.design(inv.componentDesign(key))?.key ?? component.fallback;
  return '\n<div class="hs-comp" data-component="$key" '
      'data-design="$design" data-label="${_htmlAttr(component.label)}" '
      'data-flow="${component.flow}">$html</div>';
}

String _htmlAttr(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// CSS de los diseños elegidos. Se añade DESPUÉS del documento original
/// para que las variantes ganen sin tocar el diseño de fábrica.
String invitationComponentCss(Invitation inv) {
  final b = StringBuffer()
    ..writeln('/* ===== COMPONENTES ELEGIDOS ===== */')
    ..writeln(
      '.hs-comp { display: contents; '
      '--hs-comp-accent: ${inv.accentHex}; }',
    );
  final pieces = <(String, String Function(String))>[
    ('countdown', countdownComponentCss),
    ('quote', quoteComponentCss),
    ('photos', photosComponentCss),
    ('families', familiesComponentCss),
    ('details', detailsComponentCss),
    ('hashtag', hashtagComponentCss),
    ('itinerary', itineraryComponentCss),
    ('rsvp', rsvpComponentCss),
    ('footer', footerComponentCss),
    ('music', musicComponentCss),
  ];
  for (final piece in pieces) {
    final design = inv.componentDesign(piece.$1);
    b.write(piece.$2(design));
  }
  return b.toString();
}

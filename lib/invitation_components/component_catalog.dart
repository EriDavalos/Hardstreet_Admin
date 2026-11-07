import 'cover/cover_component.dart';
import 'countdown/countdown_component.dart';
import 'details/details_component.dart';
import 'families/families_component.dart';
import 'footer/footer_component.dart';
import 'hashtag/hashtag_component.dart';
import 'invitation_component.dart';
import 'itinerary/itinerary_component.dart';
import 'music/music_component.dart';
import 'photos/photos_component.dart';
import 'quote/quote_component.dart';
import 'rsvp/rsvp_component.dart';

export 'invitation_component.dart';

// ------------------------------------------------------------------
// CATÁLOGO
// ------------------------------------------------------------------
// El orden de esta lista es el orden del editor y del panel de componentes.
// Cada carpeta es dueña de sus diseños y de sus reglas visuales.
// ------------------------------------------------------------------

const List<InvitationComponent> kInvitationComponents = [
  kCoverComponent,
  kCountdownComponent,
  kQuoteComponent,
  kPhotosComponent,
  kFamiliesComponent,
  kDetailsComponent,
  kHashtagComponent,
  kItineraryComponent,
  kRsvpComponent,
  kFooterComponent,
  kMusicComponent,
];

InvitationComponent? invitationComponentForKey(String key) {
  final clean = key.trim().toLowerCase();
  for (final c in kInvitationComponents) {
    if (c.key == clean) return c;
  }
  return null;
}

InvitationComponent invitationComponent(String key) =>
    invitationComponentForKey(key) ?? kCoverComponent;

String invitationComponentLabel(String key) =>
    invitationComponentForKey(key)?.label ?? key;

/// Un diseño válido para el componente, o el de fábrica.
String invitationComponentDesign(String key, String design) {
  final component = invitationComponentForKey(key);
  if (component == null) return '';
  return component.design(design)?.key ?? component.fallback;
}

String invitationComponentDesignLabel(String key, String design) {
  final component = invitationComponentForKey(key);
  if (component == null) return design;
  return component.labelFor(design);
}

/// Claves de los componentes que tienen un lugar propio y no se reordenan.
const List<String> kFixedInvitationComponents = [
  'cover',
  'countdown',
  'quote',
  'photos',
  'rsvp',
  'music',
];

/// Claves de los componentes que se pueden mover en el flujo.
const List<String> kFlowInvitationComponents = [
  'families',
  'details',
  'hashtag',
  'itinerary',
  'footer',
];

import 'package:flutter/material.dart';

import 'package:hardstreet_admin/modules/invitations/components/invitation_component.dart';

const InvitationComponent kItineraryComponent = InvitationComponent(
  key: 'itinerary',
  label: 'Itinerario',
  hint: 'El programa del día, con horarios y momentos.',
  icon: Icons.route_outlined,
  fallback: 'linea',
  flow: true,
  designs: [
    InvitationComponentDesign(
      key: 'linea',
      label: 'Línea de tiempo',
      hint: 'Una línea vertical con cada momento.',
    ),
    InvitationComponentDesign(
      key: 'tarjetas',
      label: 'Tarjetas',
      hint: 'Momentos en tarjetas de dos columnas.',
    ),
    InvitationComponentDesign(
      key: 'compacto',
      label: 'Programa compacto',
      hint: 'Horarios en una cuadrícula breve.',
    ),
  ],
);

String itineraryComponentCss(String design) {
  if (design == 'tarjetas') {
    return '''
.hs-comp[data-component="itinerary"][data-design="tarjetas"] .timeline {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: .8rem;
  max-width: 620px;
  padding-left: 0;
}
.hs-comp[data-component="itinerary"][data-design="tarjetas"] .timeline::before,
.hs-comp[data-component="itinerary"][data-design="tarjetas"] .timeline-dot {
  display: none;
}
.hs-comp[data-component="itinerary"][data-design="tarjetas"] .timeline-item {
  padding: 1rem 1.05rem;
  border: 1px solid rgba(184, 145, 90, .34);
  border-radius: 10px;
  background: rgba(255, 255, 255, .24);
}
.hs-comp[data-component="itinerary"][data-design="tarjetas"] .mf-day {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: .7rem;
}
.hs-comp[data-component="itinerary"][data-design="tarjetas"] .mf-stop {
  display: block;
  padding: .85rem .9rem;
  border: 1px solid var(--line);
  background: rgba(255, 255, 255, .2);
}
.hs-comp[data-component="itinerary"][data-design="tarjetas"] .mf-stop .mf-dot {
  display: none;
}
@media (max-width: 560px) {
  .hs-comp[data-component="itinerary"][data-design="tarjetas"] .timeline,
  .hs-comp[data-component="itinerary"][data-design="tarjetas"] .mf-day {
    grid-template-columns: 1fr;
  }
}
''';
  }
  if (design == 'compacto') {
    return '''
.hs-comp[data-component="itinerary"][data-design="compacto"] .itinerary-section {
  padding-bottom: 3.2rem;
}
.hs-comp[data-component="itinerary"][data-design="compacto"] .timeline {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: .35rem 1.3rem;
  max-width: 580px;
  padding-left: 0;
}
.hs-comp[data-component="itinerary"][data-design="compacto"] .timeline::before,
.hs-comp[data-component="itinerary"][data-design="compacto"] .timeline-dot {
  display: none;
}
.hs-comp[data-component="itinerary"][data-design="compacto"] .timeline-item {
  padding: .45rem 0;
  border-bottom: 1px solid rgba(184, 145, 90, .25);
}
.hs-comp[data-component="itinerary"][data-design="compacto"] .timeline-time { font-size: .92rem; }
.hs-comp[data-component="itinerary"][data-design="compacto"] .timeline-event { font-size: 1rem; }
.hs-comp[data-component="itinerary"][data-design="compacto"] .mf-day {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: .4rem 1.3rem;
}
.hs-comp[data-component="itinerary"][data-design="compacto"] .mf-stop {
  display: block;
  padding: .45rem 0;
  border-bottom: 1px solid var(--line);
}
.hs-comp[data-component="itinerary"][data-design="compacto"] .mf-stop .mf-dot { display: none; }
@media (max-width: 530px) {
  .hs-comp[data-component="itinerary"][data-design="compacto"] .timeline,
  .hs-comp[data-component="itinerary"][data-design="compacto"] .mf-day {
    grid-template-columns: 1fr;
  }
}
''';
  }
  return '';
}

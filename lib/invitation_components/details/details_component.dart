import 'package:flutter/material.dart';

import '../invitation_component.dart';

const InvitationComponent kDetailsComponent = InvitationComponent(
  key: 'details',
  label: 'Detalles',
  hint: 'Lugar, fecha, vestimenta y demás indicaciones.',
  icon: Icons.event_note_outlined,
  fallback: 'tarjetas',
  flow: true,
  designs: [
    InvitationComponentDesign(
      key: 'tarjetas',
      label: 'Tarjetas',
      hint: 'Tarjetas ilustradas, una por indicación.',
    ),
    InvitationComponentDesign(
      key: 'lista',
      label: 'Lista',
      hint: 'Filas limpias con la información esencial.',
    ),
    InvitationComponentDesign(
      key: 'editorial',
      label: 'Editorial',
      hint: 'Bloques alineados a la izquierda, sin cajas.',
    ),
  ],
);

String detailsComponentCss(String design) {
  if (design == 'lista') {
    return '''
.hs-comp[data-component="details"][data-design="lista"] .details-list {
  gap: .75rem;
  max-width: 580px;
}
.hs-comp[data-component="details"][data-design="lista"] .detail-card {
  padding: 1.35rem 1.25rem !important;
  border-radius: 4px !important;
  background: rgba(255, 255, 255, .38) !important;
  box-shadow: none !important;
  border: 1px solid rgba(160, 92, 88, .22) !important;
}
.hs-comp[data-component="details"][data-design="lista"] .detail-card .corner-svg,
.hs-comp[data-component="details"][data-design="lista"] .detail-card .ribbon,
.hs-comp[data-component="details"][data-design="lista"] .detail-card .butterfly,
.hs-comp[data-component="details"][data-design="lista"] .detail-card .detail-illustration {
  display: none !important;
}
.hs-comp[data-component="details"][data-design="lista"] .detail-title {
  font-family: 'Cormorant Garamond', serif !important;
  font-size: 1.3rem !important;
  letter-spacing: .14em;
  text-transform: uppercase;
}
.hs-comp[data-component="details"][data-design="lista"] .mf-details { max-width: 620px; }
.hs-comp[data-component="details"][data-design="lista"] .mf-card {
  padding: 1.25rem 1.4rem;
  text-align: left;
  background: transparent;
  border: 0;
  border-top: 1px solid var(--line);
}
.hs-comp[data-component="details"][data-design="lista"] .mf-card::before,
.hs-comp[data-component="details"][data-design="lista"] .mf-mark { display: none; }
.hs-comp[data-component="details"][data-design="lista"] .mf-card h3 { font-size: .92rem; }
''';
  }
  if (design == 'editorial') {
    return '''
.hs-comp[data-component="details"][data-design="editorial"] .details-section {
  background: transparent !important;
}
.hs-comp[data-component="details"][data-design="editorial"] .details-list {
  max-width: 700px;
  gap: 0;
}
.hs-comp[data-component="details"][data-design="editorial"] .detail-card {
  padding: 1.6rem .25rem !important;
  border: 0 !important;
  border-top: 1px solid rgba(160, 92, 88, .34) !important;
  border-radius: 0 !important;
  background: transparent !important;
  box-shadow: none !important;
  text-align: left;
}
.hs-comp[data-component="details"][data-design="editorial"] .detail-card:last-child {
  border-bottom: 1px solid rgba(160, 92, 88, .34) !important;
}
.hs-comp[data-component="details"][data-design="editorial"] .detail-card .corner-svg,
.hs-comp[data-component="details"][data-design="editorial"] .detail-card .ribbon,
.hs-comp[data-component="details"][data-design="editorial"] .detail-card .butterfly,
.hs-comp[data-component="details"][data-design="editorial"] .detail-card .detail-illustration {
  display: none !important;
}
.hs-comp[data-component="details"][data-design="editorial"] .detail-title {
  font-family: 'Playfair Display', serif !important;
  font-size: 1.35rem !important;
  letter-spacing: .04em;
}
.hs-comp[data-component="details"][data-design="editorial"] .detail-time {
  font-size: 1.1rem !important;
}
.hs-comp[data-component="details"][data-design="editorial"] .mf-details-section {
  background: transparent;
}
.hs-comp[data-component="details"][data-design="editorial"] .mf-details {
  max-width: 700px;
  gap: 0;
}
.hs-comp[data-component="details"][data-design="editorial"] .mf-card {
  padding: 1.6rem .2rem;
  text-align: left;
  background: transparent;
  border: 0;
  border-top: 1px solid var(--line);
}
.hs-comp[data-component="details"][data-design="editorial"] .mf-card:last-child {
  border-bottom: 1px solid var(--line);
}
.hs-comp[data-component="details"][data-design="editorial"] .mf-card::before,
.hs-comp[data-component="details"][data-design="editorial"] .mf-mark { display: none; }
''';
  }
  return '';
}

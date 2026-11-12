import 'package:flutter/material.dart';

import 'package:hardstreet_admin/modules/invitations/components/invitation_component.dart';

const InvitationComponent kRsvpComponent = InvitationComponent(
  key: 'rsvp',
  label: 'Confirmación',
  hint: 'La tarjeta para confirmar la asistencia por WhatsApp.',
  icon: Icons.mark_email_read_outlined,
  fallback: 'tarjeta',
  designs: [
    InvitationComponentDesign(
      key: 'tarjeta',
      label: 'Tarjeta',
      hint: 'La tarjeta ilustrada con el botón de confirmar.',
    ),
    InvitationComponentDesign(
      key: 'boton',
      label: 'Botón',
      hint: 'Sin caja: un botón directo y el texto breve.',
    ),
    InvitationComponentDesign(
      key: 'minimal',
      label: 'Minimal',
      hint: 'Solo una línea y el enlace de WhatsApp.',
    ),
  ],
);

String rsvpComponentCss(String design) {
  if (design == 'boton') {
    return '''
.hs-comp[data-component="rsvp"] .detail-card {
  background: transparent !important;
  border: 0 !important;
  border-radius: 0 !important;
  box-shadow: none !important;
  padding: 1.3rem .5rem !important;
}
.hs-comp[data-component="rsvp"] .detail-card .corner-svg,
.hs-comp[data-component="rsvp"] .detail-card .ribbon,
.hs-comp[data-component="rsvp"] .detail-card .butterfly,
.hs-comp[data-component="rsvp"] .detail-card .detail-illustration {
  display: none !important;
}
.hs-comp[data-component="rsvp"] .detail-card .btn {
  border-radius: 4px !important;
  min-width: 210px;
}
.hs-comp[data-component="rsvp"] .mf-rsvp {
  padding: 2.4rem 1.2rem 2.8rem;
}
.hs-comp[data-component="rsvp"] .mf-rsvp .mf-head {
  display: none;
}
.hs-comp[data-component="rsvp"] .mf-rsvp .mf-rsvp-text {
  margin: 0 auto;
  max-width: 390px;
}
.hs-comp[data-component="rsvp"] .mf-rsvp .mf-cta {
  margin-top: 1.1rem;
}
''';
  }
  if (design == 'minimal') {
    return '''
.hs-comp[data-component="rsvp"] .detail-card {
  background: transparent !important;
  border: 0 !important;
  border-top: 1px solid var(--hs-comp-accent, #b76e79) !important;
  border-radius: 0 !important;
  box-shadow: none !important;
  padding: 1.2rem 0 !important;
}
.hs-comp[data-component="rsvp"] .detail-card .corner-svg,
.hs-comp[data-component="rsvp"] .detail-card .ribbon,
.hs-comp[data-component="rsvp"] .detail-card .butterfly,
.hs-comp[data-component="rsvp"] .detail-card .detail-illustration,
.hs-comp[data-component="rsvp"] .detail-card .detail-title {
  display: none !important;
}
.hs-comp[data-component="rsvp"] .detail-card .btn {
  background: transparent !important;
  color: var(--hs-comp-accent, #b76e79) !important;
  box-shadow: none !important;
  border: 0 !important;
  border-bottom: 1px solid currentColor !important;
  border-radius: 0 !important;
  padding: .4rem 0 !important;
  min-width: 0;
}
.hs-comp[data-component="rsvp"] .mf-rsvp {
  background: transparent;
  border-top: 1px solid var(--line);
  padding: 2.2rem 1.2rem;
}
.hs-comp[data-component="rsvp"] .mf-rsvp .mf-head {
  display: none;
}
.hs-comp[data-component="rsvp"] .mf-rsvp .mf-rsvp-text {
  max-width: 390px;
}
.hs-comp[data-component="rsvp"] .mf-rsvp .mf-cta {
  background: transparent;
  color: var(--gold-deep);
  border: 0;
  border-bottom: 1px solid var(--line);
  box-shadow: none;
  padding: .4rem 0;
  margin-top: 1rem;
}
''';
  }
  return '';
}

import 'package:flutter/material.dart';

import 'package:hardstreet_admin/modules/invitations/components/invitation_component.dart';

const InvitationComponent kFooterComponent = InvitationComponent(
  key: 'footer',
  label: 'Pie de la invitación',
  hint: 'El cierre, la firma y el crédito de Hardstreet.',
  icon: Icons.favorite_border_rounded,
  fallback: 'firma',
  flow: true,
  designs: [
    InvitationComponentDesign(
      key: 'firma',
      label: 'Firma',
      hint: 'El cierre floral con los nombres en grande.',
    ),
    InvitationComponentDesign(
      key: 'centrado',
      label: 'Centrado',
      hint: 'Un cierre más sobrio, sin guirnalda.',
    ),
    InvitationComponentDesign(
      key: 'minimal',
      label: 'Minimal',
      hint: 'Solo nombres, mensaje y crédito.',
    ),
  ],
);

String footerComponentCss(String design) {
  if (design == 'centrado') {
    return '''
.hs-comp[data-component="footer"][data-design="centrado"] .footer-section {
  background: transparent !important;
  padding-top: 3rem;
}
.hs-comp[data-component="footer"][data-design="centrado"] .footer-section .garland,
.hs-comp[data-component="footer"][data-design="centrado"] .footer-hearts {
  display: none !important;
}
.hs-comp[data-component="footer"][data-design="centrado"] .mf-footer {
  background: transparent;
  padding-top: 2.8rem;
}
''';
  }
  if (design == 'minimal') {
    return '''
.hs-comp[data-component="footer"][data-design="minimal"] .footer-section {
  background: transparent !important;
  padding: 2.6rem 1.2rem 2.2rem;
}
.hs-comp[data-component="footer"][data-design="minimal"] .footer-section .garland,
.hs-comp[data-component="footer"][data-design="minimal"] .footer-hearts,
.hs-comp[data-component="footer"][data-design="minimal"] .petals-bg,
.hs-comp[data-component="footer"][data-design="minimal"] .footer-credit-heart {
  display: none !important;
}
.hs-comp[data-component="footer"][data-design="minimal"] .footer-credit {
  border-top: 1px solid rgba(160, 92, 88, .25);
  padding-top: .9rem;
}
.hs-comp[data-component="footer"][data-design="minimal"] .footer-names {
  font-size: clamp(2rem, 7vw, 3rem) !important;
}
.hs-comp[data-component="footer"][data-design="minimal"] .mf-footer {
  background: transparent;
  border-top: 1px solid var(--line);
  padding: 2.4rem 1.2rem 2rem;
}
.hs-comp[data-component="footer"][data-design="minimal"] .mf-footer .petals-bg {
  display: none;
}
.hs-comp[data-component="footer"][data-design="minimal"] .mf-footer .mf-footer-names {
  font-size: 2.2rem;
}
''';
  }
  return '';
}

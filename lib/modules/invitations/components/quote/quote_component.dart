import 'package:flutter/material.dart';

import 'package:hardstreet_admin/modules/invitations/components/invitation_component.dart';

const InvitationComponent kQuoteComponent = InvitationComponent(
  key: 'quote',
  label: 'Frase',
  hint: 'El mensaje destacado dentro de la tarjeta.',
  icon: Icons.format_quote_rounded,
  fallback: 'comillas',
  designs: [
    InvitationComponentDesign(
      key: 'comillas',
      label: 'Comillas',
      hint: 'El recuadro floral clásico.',
    ),
    InvitationComponentDesign(
      key: 'marco',
      label: 'Marco',
      hint: 'Un marco fino alrededor de la frase.',
    ),
    InvitationComponentDesign(
      key: 'minimal',
      label: 'Minimal',
      hint: 'Sin caja: solo la frase y una línea.',
    ),
  ],
);

String quoteComponentCss(String design) {
  if (design == 'marco') {
    return '''
.hs-comp[data-component="quote"][data-design="marco"] .quote-box {
  background: transparent !important;
  border: 1px solid var(--hs-comp-accent, #b76e79) !important;
  border-radius: 0 !important;
  box-shadow: none !important;
  padding: 1.8rem 1.4rem !important;
}
.hs-comp[data-component="quote"][data-design="marco"] .quote-box .corner-svg,
.hs-comp[data-component="quote"][data-design="marco"] .quote-rose {
  display: none !important;
}
.hs-comp[data-component="quote"][data-design="marco"] .mf-quote-section {
  border-top: 1px solid var(--line);
  border-bottom: 1px solid var(--line);
  padding: 2.4rem 1.2rem;
}
.hs-comp[data-component="quote"][data-design="marco"] .mf-quote-mark {
  display: none;
}
''';
  }
  if (design == 'minimal') {
    return '''
.hs-comp[data-component="quote"][data-design="minimal"] .quote-box {
  background: transparent !important;
  border: 0 !important;
  border-radius: 0 !important;
  box-shadow: none !important;
  padding: .5rem .25rem 1.1rem !important;
}
.hs-comp[data-component="quote"][data-design="minimal"] .quote-box .corner-svg,
.hs-comp[data-component="quote"][data-design="minimal"] .quote-rose {
  display: none !important;
}
.hs-comp[data-component="quote"][data-design="minimal"] .quote-text {
  font-size: 1.3rem !important;
  line-height: 1.8 !important;
}
.hs-comp[data-component="quote"][data-design="minimal"] .mf-quote-section {
  border: 0 !important;
  background: transparent !important;
}
.hs-comp[data-component="quote"][data-design="minimal"] .mf-quote-mark {
  display: none !important;
}
''';
  }
  return '';
}

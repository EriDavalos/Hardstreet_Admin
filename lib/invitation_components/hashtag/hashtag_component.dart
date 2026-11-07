import 'package:flutter/material.dart';

import '../invitation_component.dart';

const InvitationComponent kHashtagComponent = InvitationComponent(
  key: 'hashtag',
  label: 'Hashtag',
  hint: 'La etiqueta para compartir las fotos del evento.',
  icon: Icons.tag_rounded,
  fallback: 'cinta',
  flow: true,
  designs: [
    InvitationComponentDesign(
      key: 'cinta',
      label: 'Cinta',
      hint: 'La banda luminosa con la etiqueta.',
    ),
    InvitationComponentDesign(
      key: 'sello',
      label: 'Sello',
      hint: 'Un marco tipo sello, sin banda de color.',
    ),
    InvitationComponentDesign(
      key: 'minimal',
      label: 'Minimal',
      hint: 'Texto sobre una línea, sin adornos.',
    ),
  ],
);

String hashtagComponentCss(String design) {
  if (design == 'sello') {
    return '''
.hs-comp[data-component="hashtag"][data-design="sello"] .hashtag-section {
  background: transparent !important;
  border-top: 1px solid var(--hs-comp-accent, #b76e79);
  border-bottom: 1px solid var(--hs-comp-accent, #b76e79);
  animation: none !important;
}
.hs-comp[data-component="hashtag"][data-design="sello"] .hashtag-section .sparkle {
  display: none !important;
}
.hs-comp[data-component="hashtag"][data-design="sello"] .hashtag-script {
  color: var(--hs-comp-accent, #b76e79) !important;
  text-shadow: none !important;
}
.hs-comp[data-component="hashtag"][data-design="sello"] .hashtag-text {
  display: inline-block;
  color: var(--hs-comp-accent, #b76e79) !important;
  padding: .55rem 1.1rem;
  border: 1px solid var(--hs-comp-accent, #b76e79);
  text-shadow: none !important;
}
.hs-comp[data-component="hashtag"][data-design="sello"] .mf-hashtag {
  background: transparent;
  border-top: 1px solid var(--line);
  border-bottom: 1px solid var(--line);
}
.hs-comp[data-component="hashtag"][data-design="sello"] .mf-tag {
  display: inline-block;
  padding: .45rem 1rem;
  border: 1px solid var(--line);
}
''';
  }
  if (design == 'minimal') {
    return '''
.hs-comp[data-component="hashtag"][data-design="minimal"] .hashtag-section {
  background: transparent !important;
  animation: none !important;
  border: 0 !important;
}
.hs-comp[data-component="hashtag"][data-design="minimal"] .hashtag-section .sparkle {
  display: none !important;
}
.hs-comp[data-component="hashtag"][data-design="minimal"] .hashtag-script {
  color: var(--hs-comp-accent, #b76e79) !important;
  text-shadow: none !important;
  font-size: 1.25rem;
}
.hs-comp[data-component="hashtag"][data-design="minimal"] .hashtag-text {
  color: inherit !important;
  text-shadow: none !important;
  font-family: 'Cormorant Garamond', serif !important;
  font-size: 1.55rem !important;
  letter-spacing: .12em !important;
  text-transform: none !important;
}
.hs-comp[data-component="hashtag"][data-design="minimal"] .mf-hashtag {
  background: transparent;
  border: 0;
}
''';
  }
  return '';
}

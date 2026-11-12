import 'package:flutter/material.dart';

import 'package:hardstreet_admin/modules/invitations/components/invitation_component.dart';

const InvitationComponent kCountdownComponent = InvitationComponent(
  key: 'countdown',
  label: 'Cuenta regresiva',
  hint: 'Días, horas, minutos y segundos hasta el evento.',
  icon: Icons.timer_outlined,
  fallback: 'cajas',
  designs: [
    InvitationComponentDesign(
      key: 'cajas',
      label: 'Cajas',
      hint: 'Cuatro cápsulas con el tiempo restante.',
    ),
    InvitationComponentDesign(
      key: 'linea',
      label: 'Línea',
      hint: 'Números separados por reglas finas.',
    ),
    InvitationComponentDesign(
      key: 'minimal',
      label: 'Minimal',
      hint: 'Solo los números, sin adornos.',
    ),
  ],
);

String countdownComponentCss(String design) {
  if (design == 'linea') {
    return '''
.hs-comp[data-component="countdown"][data-design="linea"] .countdown-box {
  background: transparent !important;
  border: 0 !important;
  border-top: 1px solid var(--hs-comp-accent, #b76e79) !important;
  border-bottom: 1px solid var(--hs-comp-accent, #b76e79) !important;
  border-radius: 0 !important;
  box-shadow: none !important;
}
.hs-comp[data-component="countdown"][data-design="linea"] .cd-sep {
  color: var(--hs-comp-accent, #b76e79) !important;
  font-weight: 300;
}
.hs-comp[data-component="countdown"][data-design="linea"] .mf-count-row {
  border-top: 1px solid var(--line);
  border-bottom: 1px solid var(--line);
}
.hs-comp[data-component="countdown"][data-design="linea"] .mf-count-box {
  border: 0 !important;
  background: transparent !important;
}
''';
  }
  if (design == 'minimal') {
    return '''
.hs-comp[data-component="countdown"][data-design="minimal"] .script-faltan {
  display: none !important;
}
.hs-comp[data-component="countdown"][data-design="minimal"] .countdown-box {
  background: transparent !important;
  border: 0 !important;
  box-shadow: none !important;
  padding: 0 !important;
}
.hs-comp[data-component="countdown"][data-design="minimal"] .cd-sep {
  display: none !important;
}
.hs-comp[data-component="countdown"][data-design="minimal"] .cd-label {
  letter-spacing: .14em !important;
  opacity: .7;
}
.hs-comp[data-component="countdown"][data-design="minimal"] .mf-count-script {
  display: none !important;
}
.hs-comp[data-component="countdown"][data-design="minimal"] .mf-count-box {
  background: transparent !important;
  border: 0 !important;
}
''';
  }
  return '';
}

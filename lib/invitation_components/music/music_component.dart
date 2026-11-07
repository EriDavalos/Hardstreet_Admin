import 'package:flutter/material.dart';

import '../invitation_component.dart';

const InvitationComponent kMusicComponent = InvitationComponent(
  key: 'music',
  label: 'Música',
  hint: 'El audio de ambiente y su botón de reproducción.',
  icon: Icons.music_note_outlined,
  fallback: 'boton',
  designs: [
    InvitationComponentDesign(
      key: 'boton',
      label: 'Botón',
      hint: 'El botón flotante redondo.',
    ),
    InvitationComponentDesign(
      key: 'disco',
      label: 'Disco',
      hint: 'Un disco con borde y sombra.',
    ),
    InvitationComponentDesign(
      key: 'linea',
      label: 'Línea',
      hint: 'Un botón discreto, sin relleno.',
    ),
  ],
);

String musicComponentCss(String design) {
  if (design == 'disco') {
    return '''
.hs-comp[data-component="music"] .music-btn {
  width: 50px !important;
  height: 50px !important;
  border: 1px solid rgba(255, 255, 255, .8) !important;
  box-shadow: 0 0 0 5px rgba(0, 0, 0, .08), 0 10px 24px rgba(0, 0, 0, .22) !important;
}
''';
  }
  if (design == 'linea') {
    return '''
.hs-comp[data-component="music"] .music-btn {
  background: transparent !important;
  border: 1px solid currentColor !important;
  color: var(--hs-comp-accent, #b76e79) !important;
  box-shadow: none !important;
}
''';
  }
  return '';
}

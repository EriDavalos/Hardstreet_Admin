import 'package:flutter/material.dart';

import 'package:hardstreet_admin/modules/invitations/components/invitation_component.dart';

const InvitationComponent kPhotosComponent = InvitationComponent(
  key: 'photos',
  label: 'Fotos',
  hint: 'Las imágenes de la pareja, la quinceañera o el festejado.',
  icon: Icons.photo_camera_back_outlined,
  fallback: 'polaroid',
  designs: [
    InvitationComponentDesign(
      key: 'polaroid',
      label: 'Polaroids',
      hint: 'Tres fotos inclinadas, como recuerdos.',
    ),
    InvitationComponentDesign(
      key: 'arco',
      label: 'Arco',
      hint: 'Una foto principal con la parte de arriba en arco.',
    ),
    InvitationComponentDesign(
      key: 'mosaico',
      label: 'Mosaico',
      hint: 'Dos columnas rectas y una foto destacada.',
    ),
  ],
);

String photosComponentCss(String design) {
  if (design == 'arco') {
    return '''
.hs-comp[data-component="photos"][data-design="arco"] .polaroids {
  display: block;
  max-width: 260px;
  margin: 0 auto;
}
.hs-comp[data-component="photos"][data-design="arco"] .polaroid {
  display: none;
  width: 100%;
  margin: 0;
  transform: none !important;
}
.hs-comp[data-component="photos"][data-design="arco"] .polaroid.p1 {
  display: block;
  border-radius: 140px 140px 4px 4px;
  padding: 7px 7px 14px;
}
.hs-comp[data-component="photos"][data-design="arco"] .polaroid.p1 img {
  border-radius: 132px 132px 2px 2px;
}
.hs-comp[data-component="photos"][data-design="arco"] .mf-photos {
  display: block;
  max-width: 280px;
}
.hs-comp[data-component="photos"][data-design="arco"] .mf-photo {
  display: none;
}
.hs-comp[data-component="photos"][data-design="arco"] .mf-photo:first-child {
  display: block;
  width: 100%;
  margin: 0;
  transform: none;
  border-radius: 150px 150px 4px 4px;
}
.hs-comp[data-component="photos"][data-design="arco"] .mf-photo:first-child img {
  border-radius: 142px 142px 2px 2px;
}
''';
  }
  if (design == 'mosaico') {
    return '''
.hs-comp[data-component="photos"][data-design="mosaico"] .polaroids {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 9px;
  max-width: 360px;
  margin: 0 auto;
}
.hs-comp[data-component="photos"][data-design="mosaico"] .polaroid {
  width: 100%;
  margin: 0;
  padding: 5px 5px 9px;
  transform: none !important;
}
.hs-comp[data-component="photos"][data-design="mosaico"] .polaroid.p3 {
  grid-column: 1 / -1;
  width: 64%;
  justify-self: center;
}
.hs-comp[data-component="photos"][data-design="mosaico"] .mf-photos {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 9px;
  max-width: 380px;
}
.hs-comp[data-component="photos"][data-design="mosaico"] .mf-photo {
  width: 100%;
  max-width: none;
  margin: 0;
  transform: none !important;
}
.hs-comp[data-component="photos"][data-design="mosaico"] .mf-photo:nth-child(3) {
  grid-column: 1 / -1;
  width: 64%;
  justify-self: center;
}
''';
  }
  return '';
}

import 'package:flutter/material.dart';

import 'package:hardstreet_admin/modules/invitations/components/invitation_component.dart';

const InvitationComponent kFamiliesComponent = InvitationComponent(
  key: 'families',
  label: 'Familias',
  hint: 'Padres, padrinos y personas que acompañan.',
  icon: Icons.groups_2_outlined,
  fallback: 'tarjetas',
  flow: true,
  designs: [
    InvitationComponentDesign(
      key: 'tarjetas',
      label: 'Tarjetas',
      hint: 'Una tarjeta floral por familia.',
    ),
    InvitationComponentDesign(
      key: 'columnas',
      label: 'Dos columnas',
      hint: 'Las familias se reparten en dos columnas.',
    ),
    InvitationComponentDesign(
      key: 'minimal',
      label: 'Lista serena',
      hint: 'Sin tarjetas: nombres y líneas finas.',
    ),
  ],
);

String familiesComponentCss(String design) {
  if (design == 'columnas') {
    return '''
.hs-comp[data-component="families"][data-design="columnas"] .families-grid {
  grid-template-columns: repeat(2, minmax(0, 1fr));
  max-width: 760px;
}
.hs-comp[data-component="families"][data-design="columnas"] .family-card {
  margin: 0;
  height: 100%;
}
.hs-comp[data-component="families"][data-design="columnas"] .mf-families {
  grid-template-columns: repeat(2, minmax(0, 1fr));
  text-align: left;
}
.hs-comp[data-component="families"][data-design="columnas"] .mf-family {
  padding: 1.1rem 1.2rem;
  border-top: 1px solid var(--line);
}
@media (max-width: 620px) {
  .hs-comp[data-component="families"][data-design="columnas"] .families-grid,
  .hs-comp[data-component="families"][data-design="columnas"] .mf-families {
    grid-template-columns: 1fr;
  }
}
''';
  }
  if (design == 'minimal') {
    return '''
.hs-comp[data-component="families"][data-design="minimal"] .families-grid {
  max-width: 620px;
  gap: 0;
}
.hs-comp[data-component="families"][data-design="minimal"] .family-card {
  padding: 1.25rem .4rem;
  background: transparent !important;
  border: 0 !important;
  border-top: 1px solid var(--hs-comp-accent, currentColor) !important;
  border-radius: 0 !important;
  box-shadow: none !important;
}
.hs-comp[data-component="families"][data-design="minimal"] .family-card:last-child {
  border-bottom: 1px solid var(--hs-comp-accent, currentColor) !important;
}
.hs-comp[data-component="families"][data-design="minimal"] .family-card .corner-svg,
.hs-comp[data-component="families"][data-design="minimal"] .family-heart { display: none !important; }
.hs-comp[data-component="families"][data-design="minimal"] .family-card .name {
  font-family: 'Cormorant Garamond', serif !important;
  font-size: 1.15rem !important;
  letter-spacing: .03em;
}
.hs-comp[data-component="families"][data-design="minimal"] .mf-families { gap: 0; }
.hs-comp[data-component="families"][data-design="minimal"] .mf-family {
  padding: 1.15rem 0;
  border-top: 1px solid var(--line);
  text-align: left;
}
.hs-comp[data-component="families"][data-design="minimal"] .mf-family:last-child {
  border-bottom: 1px solid var(--line);
}
''';
  }
  return '';
}

import 'package:flutter/material.dart';

import '../invitation_component.dart';

/// La PORTADA es un componente independiente del resto del diseño.
const InvitationComponent kCoverComponent = InvitationComponent(
  key: 'cover',
  label: 'Portada',
  hint: 'La primera impresión: sobre, carta, XV, noche, cortina o marco.',
  icon: Icons.mark_email_unread_outlined,
  fallback: 'rosa',
  designs: [
    InvitationComponentDesign(
      key: 'rosa',
      label: 'Rosa Pastel',
      hint: 'Arco floral, pétalos y brillo suave.',
    ),
    InvitationComponentDesign(
      key: 'carta',
      label: 'Carta',
      hint: 'Papel doblado, sello de cera y caligrafía.',
    ),
    InvitationComponentDesign(
      key: 'xv',
      label: 'Portada de XV',
      hint: 'Corona, el número 15, listones y confeti.',
    ),
    InvitationComponentDesign(
      key: 'noche',
      label: 'Noche estrellada',
      hint: 'Luna, constelaciones y aire de gala.',
    ),
    InvitationComponentDesign(
      key: 'cortina',
      label: 'Cortina',
      hint: 'Terciopelo, luces y apertura de teatro.',
    ),
    InvitationComponentDesign(
      key: 'clasica',
      label: 'Clásica',
      hint: 'Monograma, doble marco y papel fino.',
    ),
  ],
);

/// Los iconos de las portadas se usan en el selector del editor.
const Map<String, IconData> kCoverIcons = {
  'rosa': Icons.local_florist_outlined,
  'carta': Icons.mail_outline,
  'xv': Icons.workspace_premium_outlined,
  'noche': Icons.auto_awesome,
  'cortina': Icons.theaters_outlined,
  'clasica': Icons.diamond_outlined,
};

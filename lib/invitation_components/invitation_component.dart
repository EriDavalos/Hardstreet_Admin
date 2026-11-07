import 'package:flutter/material.dart';

// ==================================================================
// CATÁLOGO DE COMPONENTES DE INVITACIÓN
// ==================================================================
// Una invitación se arma con componentes. Cada componente (portada,
// familias, detalles, itinerario…) tiene varios DISEÑOS intercambiables.
// Las plantillas del editor son combinaciones de esos diseños.
//
// La clave de un componente coincide con la clave de sección que ya se
// guarda en la invitación (`cover`, `families`, `details`…), así que una
// invitación vieja sigue abriendo sin migración.
// ==================================================================

/// Un diseño concreto de un componente. Su `key` viaja en el documento y
/// selecciona las reglas CSS / el render del componente.
class InvitationComponentDesign {
  const InvitationComponentDesign({
    required this.key,
    required this.label,
    required this.hint,
  });

  final String key;
  final String label;
  final String hint;
}

/// Definición de un objeto editable de la invitación y sus diseños.
class InvitationComponent {
  const InvitationComponent({
    required this.key,
    required this.label,
    required this.hint,
    required this.icon,
    required this.designs,
    required this.fallback,
    this.flow = false,
  });

  final String key;
  final String label;
  final String hint;
  final IconData icon;
  final List<InvitationComponentDesign> designs;

  /// Diseño que se usa cuando la invitación no guardó una elección.
  final String fallback;

  /// ¿Se puede reordenar dentro del flujo de la invitación?
  final bool flow;

  InvitationComponentDesign get defaultDesign => design(fallback)!;

  InvitationComponentDesign? design(String key) {
    final clean = key.trim().toLowerCase();
    for (final d in designs) {
      if (d.key == clean) return d;
    }
    return null;
  }

  String labelFor(String key) => design(key)?.label ?? defaultDesign.label;
}

// ==================================================================
// HARD STREET ADMIN - Agendas: quién ve el detalle de cada evento
// ==================================================================
// El servidor decide cuánto detalle manda (lib/agenda-visibility.ts del
// backend): a un CLIENTE le llegan sus propios eventos completos y los de
// los demás como huecos OCUPADOS (sin cliente, paquete, servicio, nota ni
// lugar, marcados con `busy: true`).
//
// Aquí solo se decide CÓMO se pinta eso: un hueco ocupado se rotula
// "Ocupado" en el calendario, la franja de próximos eventos, el widget y el
// modal de detalle, en vez de mostrar "Sin cliente" o una tarjeta vacía.
// ==================================================================

/// ¿Esta agenda es un hueco OCUPADO sin detalle? (evento de otro cliente).
bool isBusyAgenda(Map<String, dynamic>? agenda) =>
    agenda != null && agenda['busy'] == true;

/// Nombre que se pinta para una agenda en el calendario.
///
/// "Ocupado" si es un hueco sin detalle; si no, el nombre del cliente (o
/// [fallback] cuando la agenda no tiene cliente asignado).
String agendaClientLabel(
  Map<String, dynamic>? agenda, {
  String fallback = 'Evento',
}) {
  if (isBusyAgenda(agenda)) return 'Ocupado';
  final name = (agenda?['clientName'] ?? '').toString().trim();
  return name.isEmpty ? fallback : name;
}

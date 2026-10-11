// ==================================================================
// HARD STREET ADMIN - Utilidades de formato compartidas
// Dinero (MXN) y fechas/horas en español para los módulos del panel.
// ==================================================================

const List<String> kHsMonths = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

const List<String> kHsWeekdays = [
  'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo',
];

/// Inserta separador de miles a la parte entera de un número ya formateado.
String hsThousands(String s) {
  final parts = s.split('.');
  final intPart = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  return parts.length > 1 ? '$intPart.${parts[1]}' : intPart;
}

/// Dinero con moneda: `MXN $12,000` (sin decimales cuando son .00).
String hsMoney(num v, [String currency = 'MXN']) {
  final s = v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
  return '$currency \$${hsThousands(s)}';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Valor que espera el backend para `eventDate`: `yyyy-MM-dd HH:mm:ss`.
String hsDateTimeValue(DateTime d) =>
    '${d.year}-${_two(d.month)}-${_two(d.day)} '
    '${_two(d.hour)}:${_two(d.minute)}:00';

/// `yyyy-MM-dd` (clave corta para agrupar por día).
String hsDateKey(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// Fecha legible: `viernes 10 de octubre de 2026`.
String hsDateLabel(DateTime d) =>
    '${kHsWeekdays[d.weekday - 1]} ${d.day} de ${kHsMonths[d.month - 1]} de ${d.year}';

/// Fecha corta: `10/10/2026`.
String hsShortDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

/// Hora: `18:00`.
String hsTimeLabel(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// Parsea la fecha que devuelve la API (`yyyy-MM-ddTHH:mm:ss`) de forma
/// tolerante; devuelve null si no se puede.
DateTime? hsParseDate(Object? value) {
  if (value == null) return null;
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

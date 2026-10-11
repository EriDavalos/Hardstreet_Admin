import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/hs_format.dart';

void main() {
  group('hsThousands / hsMoney', () {
    test('separa miles y omite decimales en enteros', () {
      expect(hsThousands('12000'), '12,000');
      expect(hsThousands('1234567'), '1,234,567');
      expect(hsMoney(12000), 'MXN \$12,000');
      expect(hsMoney(9950), 'MXN \$9,950');
    });

    test('conserva decimales cuando existen', () {
      expect(hsMoney(1234.5), 'MXN \$1,234.50');
      expect(hsMoney(0), 'MXN \$0');
    });

    test('respeta otra moneda', () {
      expect(hsMoney(500, 'USD'), 'USD \$500');
    });
  });

  group('fechas', () {
    final d = DateTime(2026, 10, 10, 18, 0, 0);

    test('valor para el backend y clave corta', () {
      expect(hsDateTimeValue(d), '2026-10-10 18:00:00');
      expect(hsDateKey(d), '2026-10-10');
    });

    test('etiquetas en español', () {
      expect(hsDateLabel(d), 'sábado 10 de octubre de 2026');
      expect(hsShortDate(d), '10/10/2026');
      expect(hsTimeLabel(d), '18:00');
      expect(hsTimeLabel(DateTime(2026, 1, 5, 9, 5)), '09:05');
    });
  });

  group('hsParseDate', () {
    test('acepta el formato de la API', () {
      expect(hsParseDate('2026-10-10T18:00:00'),
          DateTime(2026, 10, 10, 18, 0, 0));
    });

    test('devuelve null para valores vacíos o inválidos', () {
      expect(hsParseDate(null), isNull);
      expect(hsParseDate(''), isNull);
      expect(hsParseDate('no-es-fecha'), isNull);
    });
  });
}

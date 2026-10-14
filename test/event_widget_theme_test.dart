import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/theme.dart';

/// El widget de eventos vive FUERA de la app (pantalla de inicio de Android y
/// panel de escritorio de Windows), así que cada plataforma lleva su propia
/// copia de la paleta. Esta prueba la compara con el TEMA REAL de la app: si
/// alguien cambia AppTheme y olvida el widget (o al revés), aquí salta.
///
///   Android -> android/app/src/main/res/values/colors.xml
///   Windows -> windows/runner/event_widget.cpp (paletas kLight / kDark)

const String _androidColors =
    'android/app/src/main/res/values/colors.xml';
const String _windowsCpp = 'windows/runner/event_widget.cpp';

/// Colores declarados en un colors.xml (nombre -> color).
Map<String, Color> _readAndroid(String xml) {
  final out = <String, Color>{};
  final re = RegExp(r'<color name="([^"]+)">#([0-9A-Fa-f]{6})</color>');
  for (final m in re.allMatches(xml)) {
    out[m.group(1)!] =
        Color(0xFF000000 | int.parse(m.group(2)!, radix: 16));
  }
  return out;
}

/// Paleta de una de las dos constantes del panel de Windows
/// (`kLight = {...}` o `kDark = {...}`): nombre -> color.
Map<String, Color> _readWindows(String cpp, String constant) {
  final start = cpp.indexOf('EventWidget::Palette $constant = {');
  expect(start, greaterThanOrEqualTo(0), reason: 'falta $constant');
  final end = cpp.indexOf('};', start);
  final block = cpp.substring(start, end);
  final out = <String, Color>{};
  final re = RegExp(r'/\* (\w+)\s*\*/ RGB\((\d+), (\d+), (\d+)\)');
  for (final m in re.allMatches(block)) {
    out[m.group(1)!] = Color.fromARGB(
      255,
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
    );
  }
  return out;
}

/// Color resultante de pintar [top] con transparencia [alpha] SOBRE [base]
/// (así se aplanan la pastilla y las líneas del widget, que en el tema de la
/// app son colores translúcidos).
Color _over(Color top, Color base, double alpha) {
  int channel(Color c, int shift) => (c.toARGB32() >> shift) & 0xFF;
  int mix(int a, int b) => (a * alpha + b * (1 - alpha)).round();
  return Color.fromARGB(
    255,
    mix(channel(top, 16), channel(base, 16)),
    mix(channel(top, 8), channel(base, 8)),
    mix(channel(top, 0), channel(base, 0)),
  );
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

void main() {
  final light = AppTheme.light();
  final dark = AppTheme.dark();

  /// Todo lo que el widget debe compartir con la app, por modo.
  Map<String, Color> expected(ThemeData theme, {required bool isDark}) {
    final scheme = theme.colorScheme;
    final card = theme.cardColor;
    // Las líneas del tema oscuro son blanco al 8 % (se aplanan sobre la
    // tarjeta); la pastilla es la marca al 8 % en claro y al 16 % en oscuro.
    final line = isDark
        ? _over(Colors.white, card, .08)
        : theme.dividerColor;
    final badge = _over(scheme.primary, card, isDark ? .16 : .08);
    return {
      'card': card,
      'border': line,
      'brand': scheme.primary,
      'accent': scheme.primary,
      'text': scheme.onSurface,
      'muted': scheme.onSurfaceVariant,
      'divider': line,
      'badge_bg': badge,
      'add_bg': badge,
      'separator': line,
    };
  }

  test('Android: la paleta del widget es la del tema de la app', () {
    final xml = File(_androidColors).readAsStringSync();
    final colors = _readAndroid(xml);
    final lightExpected = expected(light, isDark: false);
    final darkExpected = expected(dark, isDark: true);

    void same(Color actual, Color want, String what) {
      expect(_hex(actual), _hex(want), reason: '$what del widget vs. la app');
    }

    same(colors['event_widget_bg']!, lightExpected['card']!, 'Tarjeta clara');
    same(colors['event_widget_bg_dark']!, darkExpected['card']!,
        'Tarjeta oscura');
    same(colors['event_widget_border']!, lightExpected['border']!,
        'Borde claro');
    same(colors['event_widget_border_dark']!, darkExpected['border']!,
        'Borde oscuro');
    same(colors['event_widget_accent']!, lightExpected['brand']!,
        'Acento claro');
    same(colors['event_widget_accent_dark']!, darkExpected['brand']!,
        'Acento oscuro');
    same(colors['event_widget_title']!, lightExpected['text']!,
        'Titular claro');
    same(colors['event_widget_title_dark']!, darkExpected['text']!,
        'Titular oscuro');
    same(colors['event_widget_muted']!, lightExpected['muted']!,
        'Secundario claro');
    same(colors['event_widget_muted_dark']!, darkExpected['muted']!,
        'Secundario oscuro');
    same(colors['event_widget_time']!, lightExpected['accent']!,
        'Hora clara');
    same(colors['event_widget_time_dark']!, darkExpected['accent']!,
        'Hora oscura');
    same(colors['event_widget_divider']!, lightExpected['divider']!,
        'Línea clara');
    same(colors['event_widget_divider_dark']!, darkExpected['divider']!,
        'Línea oscura');
    same(colors['event_widget_badge']!, lightExpected['badge_bg']!,
        'Contador claro');
    same(colors['event_widget_badge_dark']!, darkExpected['badge_bg']!,
        'Contador oscuro');
    same(colors['event_widget_add_bg']!, lightExpected['add_bg']!,
        'Botón Agregar claro');
    same(colors['event_widget_add_bg_dark']!, darkExpected['add_bg']!,
        'Botón Agregar oscuro');
  });

  test('Windows: la paleta del panel es la del tema de la app', () {
    final cpp = File(_windowsCpp).readAsStringSync();
    final panelLight = _readWindows(cpp, 'kLight');
    final panelDark = _readWindows(cpp, 'kDark');
    final lightExpected = expected(light, isDark: false);
    final darkExpected = expected(dark, isDark: true);

    lightExpected.forEach((key, want) {
      expect(_hex(panelLight[key]!), _hex(want),
          reason: 'kLight.$key del panel vs. la app');
    });
    darkExpected.forEach((key, want) {
      expect(_hex(panelDark[key]!), _hex(want),
          reason: 'kDark.$key del panel vs. la app');
    });
  });

  test('el widget de Android NO tiene carpeta values-night (no sigue al '
      'sistema)', () {
    final dir = Directory('android/app/src/main/res');
    final night = dir
        .listSync()
        .whereType<Directory>()
        .where((d) => d.path.endsWith('values-night'))
        .toList();
    // Solo se permite el styles.xml del ARRANQUE (fondo de la ventana antes del
    // primer frame). Si apareciera un colors.xml con -night, el widget pasaría
    // a seguir al tema del teléfono en vez del de la app.
    for (final d in night) {
      final files = d.listSync().map((f) => f.path.split(RegExp(r'[/\\]')).last);
      expect(files, isNot(contains('colors.xml')),
          reason: 'un colors.xml en values-night pisaría el modo de la app');
    }
  });
}

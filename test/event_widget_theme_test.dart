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

    // El fondo va MÁS OSCURO que la cardColor del tema (para despegarse del
    // fondo de pantalla) y SIN borde: el trazo se recortaba en las esquinas
    // redondeadas. Los textos y la marca siguen siendo los del tema.
    int lum(Color c) {
      final v = c.toARGB32();
      return ((v >> 16) & 0xFF) + ((v >> 8) & 0xFF) + (v & 0xFF);
    }

    expect(lum(colors['event_widget_bg']!),
        lessThan(lum(lightExpected['card']!)),
        reason: 'la tarjeta clara va más oscura que el blanco de la app');
    expect(lum(colors['event_widget_bg_dark']!),
        lessThan(lum(darkExpected['card']!)),
        reason: 'la tarjeta oscura va más oscura que la de la app');
    for (final f in ['event_widget_bg.xml', 'event_widget_bg_dark.xml']) {
      final svg = File('android/app/src/main/res/drawable/$f').readAsStringSync();
      expect(svg.contains('<stroke'), isFalse,
          reason: '$f ya no dibuja borde');
    }

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

  test('Windows: el panel conserva la identidad de la app y se despega del '
      'escritorio', () {
    final cpp = File(_windowsCpp).readAsStringSync();
    final panelLight = _readWindows(cpp, 'kLight');
    final panelDark = _readWindows(cpp, 'kDark');
    final lightExpected = expected(light, isDark: false);
    final darkExpected = expected(dark, isDark: true);

    /// Luminosidad simple (suma de canales): sirve para comparar "más oscuro".
    int lum(Color c) {
      final v = c.toARGB32();
      return ((v >> 16) & 0xFF) + ((v >> 8) & 0xFF) + (v & 0xFF);
    }

    // (1) Los textos y la marca SIGUEN siendo los del tema: el panel se ve
    //     como la app, no "parecido".
    for (final key in ['brand', 'accent', 'text', 'muted']) {
      expect(_hex(panelLight[key]!), _hex(lightExpected[key]!),
          reason: 'kLight.$key del panel vs. la app');
      expect(_hex(panelDark[key]!), _hex(darkExpected[key]!),
          reason: 'kDark.$key del panel vs. la app');
    }

    // (2) El fondo del panel va MÁS OSCURO que la tarjeta del tema (así el
    //     panel se distingue del escritorio, que es lo que pidió el usuario).
    expect(lum(panelLight['card']!), lessThan(lum(lightExpected['card']!)),
        reason: 'el panel claro debe ir más oscuro que la tarjeta blanca');
    expect(lum(panelDark['card']!), lessThan(lum(darkExpected['card']!)),
        reason: 'el panel oscuro debe ir más oscuro que la tarjeta de la app');

    // (3) Las líneas del listado no se confunden con el fondo.
    for (final key in ['divider', 'separator']) {
      expect(_hex(panelLight[key]!), isNot(_hex(panelLight['card']!)),
          reason: 'kLight.$key debe leerse sobre el fondo');
      expect(_hex(panelDark[key]!), isNot(_hex(panelDark['card']!)),
          reason: 'kDark.$key debe leerse sobre el fondo');
    }

    // (4) SIN borde dibujado: la línea sobre las esquinas redondeadas se
    //     recortaba y se veía sucia. El redondeo lo hace la región de ventana.
    expect(cpp.contains('CreatePen(PS_SOLID, 1, c.border)'), isFalse,
        reason: 'el panel ya no dibuja borde sobre el redondeo');
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

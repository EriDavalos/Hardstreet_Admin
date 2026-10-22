import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/theme.dart';

// Los nombres de las ubicaciones del mapa se ven en un TOOLTIP al pasar el
// mouse (o mantener el dedo). En modo oscuro el fondo era blanco al 12 % y el
// texto blanco: no se leía nada. Aquí se comprueba que el tooltip sigue siendo
// oscuro y opaco en los dos modos.
void main() {
  void expectReadable(ThemeData theme, String mode) {
    final deco = theme.tooltipTheme.decoration! as BoxDecoration;
    expect(deco.color, isNotNull, reason: '$mode: el tooltip tiene fondo');
    expect(
      deco.color!.a,
      1.0,
      reason: '$mode: el fondo es OPACO (antes era blanco al 12 %)',
    );
    expect(
      deco.color!.computeLuminance(),
      lessThan(.2),
      reason: '$mode: fondo oscuro para que el texto blanco se lea',
    );
    expect(theme.tooltipTheme.textStyle!.color, Colors.white);
  }

  test('el tooltip se lee en modo OSCURO', () {
    expectReadable(AppTheme.dark(), 'oscuro');
  });

  test('el tooltip se lee en modo CLARO', () {
    expectReadable(AppTheme.light(), 'claro');
  });
}

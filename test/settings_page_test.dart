import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardstreet_admin/app_settings.dart';
import 'package:hardstreet_admin/pages/settings_page.dart';
import 'package:hardstreet_admin/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La personalización del módulo Configuraciones: el tema (sistema / claro /
/// oscuro) y la PALETA de diseño completa. No hay selector de color suelto.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Configuraciones cambia el tema y NO ofrece un color suelto', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app.theme.mode': 'light'});
    await AppSettings.instance.load();

    await tester.binding.setSurfaceSize(const Size(1200, 900));
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SettingsPage())),
    );
    await tester.pump();

    expect(find.text('Configuraciones'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-theme')), findsOneWidget);
    expect(find.text('Paleta de diseño'), findsOneWidget);
    // «Color de la app» ya no existe: el acento va con la paleta.
    expect(find.text('Color de la app'), findsNothing);
    expect(find.byKey(const ValueKey('settings-accent-verde')), findsNothing);

    // Tema: se elige «Oscuro» y la app queda en modo oscuro al instante.
    await tester.tap(find.text('Oscuro'));
    await tester.pump();
    expect(AppSettings.instance.themeMode, HsThemeMode.dark);
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('app.theme.mode'), 'dark');
  });

  testWidgets('Configuraciones cambia la PALETA entera, no solo un color', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'app.theme.mode': 'dark',
      'app.palette': 'medianoche',
    });
    await AppSettings.instance.load();

    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SettingsPage())),
    );
    await tester.pump();

    final tile = find.byKey(const ValueKey('settings-palette-cobre'));
    expect(tile, findsOneWidget);
    await tester.ensureVisible(tile);
    await tester.pump();
    await tester.tap(tile);
    await tester.pump();

    expect(AppSettings.instance.palette, 'cobre');
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('app.palette'), 'cobre');
    // Fondos, tarjetas y bordes pasan a los de la paleta, y el acento también.
    expect(AppColors.bgDark, HsPalette.cobre.dark.bg);
    expect(AppColors.cardDark, HsPalette.cobre.dark.card);
    expect(AppColors.brand, AppColors.accents['cobre']);
    expect(find.textContaining('Paleta elegida: Cobre'), findsOneWidget);

    // Las paletas extravagantes se fueron; las nuevas están.
    expect(find.byKey(const ValueKey('settings-palette-vino')), findsNothing);
    expect(find.byKey(const ValueKey('settings-palette-marfil')), findsNothing);
    expect(
      find.byKey(const ValueKey('settings-palette-oceano')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-palette-zafiro')),
      findsOneWidget,
    );
  });
}

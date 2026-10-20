import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardstreet_admin/app_settings.dart';
import 'package:hardstreet_admin/pages/settings_page.dart';
import 'package:hardstreet_admin/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La personalización del módulo Configuraciones: el tema (sistema / claro /
/// oscuro) y el color de acento se aplican al instante y quedan guardados.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Configuraciones cambia el tema y el color de la app', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'app.theme.mode': 'light',
      'app.accent': 'azul',
    });
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

    // Tema: se elige «Oscuro» y la app queda en modo oscuro al instante.
    await tester.tap(find.text('Oscuro'));
    await tester.pump();
    expect(AppSettings.instance.themeMode, HsThemeMode.dark);
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('app.theme.mode'), 'dark');

    // Color: se elige de la paleta y se guarda la clave elegida.
    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-accent-verde')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('settings-accent-verde')));
    await tester.pump();
    expect(AppSettings.instance.accent, 'verde');
    expect(sp.getString('app.accent'), 'verde');
    expect(find.text('Color elegido: Verde'), findsOneWidget);

    // La vista previa usa el acento nuevo (no quedó con el color anterior).
    expect(AppColors.brand, AppColors.accents['verde']);
  });
}

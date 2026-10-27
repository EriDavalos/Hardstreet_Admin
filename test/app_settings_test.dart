import 'package:flutter_test/flutter_test.dart';
import 'package:hardstreet_admin/app_settings.dart';
import 'package:hardstreet_admin/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AppSettings carga y persiste el modo oscuro', () async {
    SharedPreferences.setMockInitialValues({'app.dark': true});
    final s = AppSettings.instance;
    await s.load();
    expect(s.dark, isTrue);

    await s.setDark(false);
    expect(s.dark, isFalse);
    final sp = await SharedPreferences.getInstance();
    expect(sp.getBool('app.dark'), isFalse);
  });

  test('AppSettings: sin preferencias guardadas usa false', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Instancia nueva vía re-inicialización manual del singleton.
    final s = AppSettings.instance;
    await s.load();
    expect(s.dark, isFalse);
    await s.setDark(true);
    expect(s.dark, isTrue);
  });

  test('la PALETA se guarda y trae sus superficies y su acento', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final s = AppSettings.instance;
    await s.load();

    await s.setPalette('cobre');
    expect(s.palette, 'cobre');
    // Cobre no es «otro color de botón»: cambian fondo, tarjeta y bordes.
    expect(AppColors.bgLight, HsPalette.cobre.light.bg);
    expect(AppColors.cardLight, HsPalette.cobre.light.card);
    expect(AppColors.lineDark, HsPalette.cobre.dark.line);
    // El acento sale de la paleta; no se elige suelto.
    expect(AppColors.brand, AppColors.accents['cobre']);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('app.palette'), 'cobre');
  });
}

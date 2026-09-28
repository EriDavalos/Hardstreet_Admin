import 'package:flutter_test/flutter_test.dart';
import 'package:hardstreet_admin/app_settings.dart';
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
}

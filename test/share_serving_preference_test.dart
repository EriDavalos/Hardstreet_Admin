import 'package:flutter_test/flutter_test.dart';
import 'package:hardstreet_admin/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El switch de «Archivos compartidos» debe recordar APAGADO igual que
/// ENCENDIDO: si el usuario lo apaga, no puede volver a encenderse solo al
/// entrar al módulo o al reabrir la app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('el switch guarda una preferencia explícita (aunque sea apagado)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final s = AppSettings.instance;
    await s.load();

    // Sin tocar el switch: el servicio puede encenderse solo si hay carpetas.
    expect(s.shareServing, isFalse);
    expect(s.shareServingSet, isFalse);

    await s.setShareServing(false);
    expect(s.shareServing, isFalse);
    expect(s.shareServingSet, isTrue);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getBool('app.share.serving'), isFalse);
    expect(sp.getBool('app.share.serving.set'), isTrue);
  });
}

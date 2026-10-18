import 'package:flutter_test/flutter_test.dart';
import 'package:hardstreet_admin/app_constants.dart';
import 'package:hardstreet_admin/app_settings.dart';
import 'package:hardstreet_admin/drive_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La dirección del drive es AJUSTABLE: en la red de la oficina el nombre
/// público contesta el router con su certificado autofirmado (el celular falla
/// con CERTIFICATE_VERIFY_FAILED), así que ahí se usa la dirección local del
/// servidor. Sin nada guardado, todo sigue como siempre.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => DriveHost.set(null));

  test('sin nada guardado se usa la dirección de fábrica', () {
    expect(DriveHost.isCustom, isFalse);
    expect(DriveHost.base, DriveHost.compiled);
    expect(AppConstants.apiBase, DriveHost.compiled);
  });

  test('lo escrito se normaliza (esquema y barras del final)', () {
    expect(
      DriveHost.normalize('192.168.1.72:4000'),
      'http://192.168.1.72:4000',
    );
    expect(
      DriveHost.normalize('  http://192.168.1.72:4000/  '),
      'http://192.168.1.72:4000',
    );
    expect(
      DriveHost.normalize('https://oriongo.ddns.net//'),
      'https://oriongo.ddns.net',
    );
  });

  test('lo que no es una dirección se rechaza', () {
    expect(DriveHost.normalize(''), isNull);
    expect(DriveHost.normalize('   '), isNull);
    expect(DriveHost.normalize('ftp://192.168.1.72'), isNull);
    expect(DriveHost.normalize('http://'), isNull);
    expect(DriveHost.isValid(''), isTrue); // vacío = usar la de fábrica
    expect(DriveHost.isValid('192.168.1.72'), isTrue);
    expect(DriveHost.isValid('ftp://x'), isFalse);
  });

  test('el respaldo público evita TLS con el mismo nombre', () {
    expect(DriveHost.publicHttp, 'http://oriongo.ddns.net:4000');
    expect(DriveHost.fallbackCandidates, contains(DriveHost.publicHttp));
    expect(DriveHost.fallbackCandidates, contains(DriveHost.lanFallback));
  });

  test('el respaldo de sesión se puede activar y quitar', () {
    expect(DriveHost.usingFallback, isFalse);
    DriveHost.useFallback(DriveHost.publicHttp);
    expect(DriveHost.usingFallback, isTrue);
    expect(AppConstants.apiBase, DriveHost.publicHttp);

    DriveHost.clearFallback();
    expect(DriveHost.usingFallback, isFalse);
    expect(AppConstants.apiBase, DriveHost.compiled);
  });

  test('guardar cambia la dirección del API y borrarla la devuelve', () {
    expect(DriveHost.set('192.168.1.72:4000'), isTrue);
    expect(DriveHost.base, 'http://192.168.1.72:4000');
    expect(DriveHost.isCustom, isTrue);
    // El API entero (drive, miniaturas, compartidos) sale de aquí.
    expect(AppConstants.apiBase, 'http://192.168.1.72:4000');

    expect(DriveHost.set('   '), isTrue); // vacío = fábrica
    expect(DriveHost.isCustom, isFalse);
    expect(AppConstants.apiBase, DriveHost.compiled);
  });

  test('guardar algo inválido NO cambia la dirección', () {
    expect(DriveHost.set('ftp://192.168.1.72'), isFalse);
    expect(DriveHost.isCustom, isFalse);
  });

  test('el respaldo local se activa solo en la sesión y se puede quitar', () {
    expect(DriveHost.usingFallback, isFalse);
    DriveHost.useFallback();
    expect(DriveHost.usingFallback, isTrue);
    expect(DriveHost.base, DriveHost.lanFallback);
    expect(AppConstants.apiBase, DriveHost.lanFallback);

    // Elegir una dirección a mano desactiva el respaldo.
    expect(DriveHost.set('192.168.1.90:4000'), isTrue);
    expect(DriveHost.usingFallback, isFalse);
    expect(DriveHost.base, 'http://192.168.1.90:4000');

    // Y volver a la de fábrica deja la pública, no la local de la sesión.
    expect(DriveHost.set(null), isTrue);
    expect(DriveHost.base, DriveHost.compiled);
  });

  test(
    'AppSettings guarda la dirección (y vuelve a leerla al arrancar)',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final s = AppSettings.instance;

      expect(await s.setDriveHost('192.168.1.72:4000'), isTrue);
      expect(s.driveHost, 'http://192.168.1.72:4000');
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('app.drive.host'), 'http://192.168.1.72:4000');

      // "Reinicio" de la app: la dirección se vuelve a aplicar desde el disco.
      DriveHost.set(null);
      expect(await AppSettings.instance.setDriveHost(''), isTrue);
      expect(sp.getString('app.drive.host'), isNull);
      expect(DriveHost.isCustom, isFalse);
    },
  );
}

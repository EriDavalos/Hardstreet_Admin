import 'package:flutter_test/flutter_test.dart';
import 'package:hardstreet_admin/version_checker.dart';

/// Dónde se descarga la actualización: DEL HUB, que es el único servidor del
/// Drive al que la app tiene que llegar (él busca el nodo que tenga el APK o
/// el EXE).
void main() {
  AppVersionInfo info(Map<String, String> downloads) => AppVersionInfo(
    version: '2.0.0',
    minVersion: '2.0.0',
    notes: '',
    downloads: downloads,
  );

  test('el APK se descarga del HUB, no del nodo que lo publica', () {
    final v = info({
      'android':
          'http://oriongo.ddns.net:4000/downloads/android/app-release.apk',
      'windows':
          'http://oriongo.ddns.net:4000/downloads/desktop/app-release.exe',
    });
    expect(
      v.downloadUrlFor('android', viaBase: 'https://oriongo.ddns.net'),
      'https://oriongo.ddns.net/downloads/android/app-release.apk',
    );
    // La dirección del hub puede llevar puerto y barra final: se respeta el
    // puerto y no se duplica la barra.
    expect(
      v.downloadUrlFor('windows', viaBase: 'http://192.168.1.72:4100/'),
      'http://192.168.1.72:4100/downloads/desktop/app-release.exe',
    );
  });

  test('un enlace externo NO se reescribe', () {
    final v = info({'android': 'https://cdn.ejemplo.com/releases/app.apk'});
    expect(
      v.downloadUrlFor('android', viaBase: 'https://oriongo.ddns.net'),
      'https://cdn.ejemplo.com/releases/app.apk',
    );
  });

  test('sin enlace de esa plataforma usa el que haya, también por el hub', () {
    final v = info({
      'windows':
          'http://oriongo.ddns.net:4000/downloads/desktop/app-release.exe',
    });
    expect(
      v.downloadUrlFor('android', viaBase: 'https://oriongo.ddns.net'),
      'https://oriongo.ddns.net/downloads/desktop/app-release.exe',
    );
  });

  test('sin servidor conocido deja el enlace tal cual', () {
    final v = info({
      'android':
          'http://oriongo.ddns.net:4000/downloads/android/app-release.apk',
    });
    expect(
      v.downloadUrlFor('android'),
      'http://oriongo.ddns.net:4000/downloads/android/app-release.apk',
    );
  });
}

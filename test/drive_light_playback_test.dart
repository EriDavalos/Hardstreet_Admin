import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_base.dart';

// ==================================================================
// CALIDAD LIGERA AL REPRODUCIR
// ==================================================================
// El visor pide `?play=low` cuando el navegador integrado no va a poder con
// el archivo. Antes SOLO miraba el peso (50 MB), así que un .MOV/HEVC de un
// iPhone de 15 MB se mandaba tal cual y el vídeo se quedaba en negro.
// ==================================================================

DriveItem _video(String name, int mb) =>
    DriveItem(name: name, isFolder: false, size: mb * 1024 * 1024);

void main() {
  test('un .MOV/HEVC pequeño también se pide en calidad ligera', () {
    expect(wantsLightPlayback(_video('boda.MOV', 5)), isTrue);
    expect(wantsLightPlayback(_video('boda.mkv', 5)), isTrue);
    expect(wantsLightPlayback(_video('boda.avi', 5)), isTrue);
  });

  test('un MP4 pequeño normal se manda tal cual (sin gastar CPU)', () {
    expect(wantsLightPlayback(_video('boda.mp4', 5)), isFalse);
  });

  test('los vídeos grandes se reencodan y las fotos nunca', () {
    expect(wantsLightPlayback(_video('boda.mp4', 60)), isTrue);
    expect(wantsLightPlayback(_video('foto.jpg', 60)), isFalse);
  });
}

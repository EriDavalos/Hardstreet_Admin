import 'package:audioplayers/audioplayers.dart';

/// CAMPANITA del aviso del paquete.
///
/// Suena dentro de la app cuando `PackageNotificationsService` detecta un aviso
/// NUEVO del estudio («Ya puedes elegir tus fotos», «Servicio terminado»…),
/// además del toast nativo del sistema.
///
/// Es un solo reproductor reutilizado: si llegan dos avisos seguidos no se
/// enciman dos audios, se reinicia el mismo. Todo es «mejor esfuerzo»: si el
/// equipo no tiene audio (o la plataforma no lo permite) el aviso se ve igual.
class NotificationSound {
  NotificationSound._();

  static final AudioPlayer _player = AudioPlayer(playerId: 'hs-aviso');

  /// Asset del tono (declarado en `pubspec.yaml`).
  static const String asset = 'sounds/aviso.wav';

  static Future<void> play() async {
    try {
      await _player.stop();
      await _player.play(AssetSource(asset), volume: 0.8);
    } catch (_) {
      // Sin audio disponible: el aviso se sigue viendo en «Novedades».
    }
  }
}

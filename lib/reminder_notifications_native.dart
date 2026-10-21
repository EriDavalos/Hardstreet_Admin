import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app_constants.dart';

/// true cuando la app corre en web (allí no hay notificaciones nativas).
const bool _kWeb = kIsWeb;

/// Interfaz mínima para poder sustituir el backend de notificaciones en
/// pruebas (sin tocar la plataforma).
abstract class ReminderNotifier {
  Future<void> showAll(List<Map<String, dynamic>> fresh);
}

/// Lo mínimo para avisar de los avisos del PAQUETE (canal aparte). Es una
/// interfaz propia para poder sustituirla en pruebas sin arrastrar los avisos
/// de eventos.
abstract class PackageNotifier {
  Future<void> showPackageAll(List<Map<String, dynamic>> fresh);
}

/// Muestra los avisos como notificaciones NATIVAS (Android, iOS, Windows).
///
/// Windows usa el toast del sistema: el aviso sale aunque el panel esté
/// minimizado o detrás de otra ventana (antes solo se veía en la campanita).
/// En web no hay notificaciones nativas y el aviso vive dentro del panel.
class NativeReminderPlugin implements ReminderNotifier, PackageNotifier {
  NativeReminderPlugin._();
  static final NativeReminderPlugin instance = NativeReminderPlugin._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  /// Canal fijo para que Android agrupe y gestione las notificaciones.
  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
        'reminders',
        'Avisos de eventos',
        channelDescription:
            'Recordatorios de eventos próximos (1 semana / 1 día)',
        importance: Importance.high,
        priority: Priority.high,
      );

  /// Avisos del PAQUETE (fotos disponibles, servicio terminado…). Canal
  /// aparte para que el cliente pueda silenciarlos por separado.
  static const AndroidNotificationDetails _packageDetails =
      AndroidNotificationDetails(
        'paquete',
        'Avisos de mi paquete',
        channelDescription:
            'Fotos disponibles, servicios terminados y avisos del estudio',
        importance: Importance.high,
        priority: Priority.high,
      );

  /// Windows: identidad con la que el sistema agrupa los avisos de la app.
  /// El GUID es el que Windows usa para devolver el toque en la notificación.
  static const WindowsInitializationSettings _windowsSettings =
      WindowsInitializationSettings(
        appName: AppConstants.appName,
        appUserModelId: 'Hardstreet.Platform.Desktop',
        guid: '4b1f7d2e-9c1a-4f3b-8e6d-2a5c7b9e1f34',
      );

  /// Inicializa el plugin y pide el permiso de notificaciones (Android 13+,
  /// iOS). En WINDOWS deja listo el toast nativo: antes el panel solo avisaba
  /// en la campanita y, si estabas en otra ventana, no te enterabas.
  /// Seguro llamar varias veces; si algo falla se marca como no listo y las
  /// notificaciones se omiten sin romper la app.
  Future<void> init() async {
    if (_ready || _kWeb) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
        windows: _windowsSettings,
      );
      await _plugin.initialize(
        settings,
        // Tocar el aviso trae la ventana al frente: en Windows el panel puede
        // estar cerrado (vive en la bandeja) y el toast tiene que servir para
        // volver a él.
        onDidReceiveNotificationResponse: _onNotificationTap,
      );
      if (defaultTargetPlatform == TargetPlatform.android) {
        // Android 13+ (API 33): sin este permiso el sistema DESCARTA la
        // notificación. Si el usuario lo niega, la campanita sigue avisando.
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Canal del runner de Windows que vuelve a mostrar la ventana.
  static const MethodChannel _windowChannel =
      MethodChannel('hardstreet/events_widget');

  /// Al tocar una notificación se pide al sistema que muestre el panel.
  static void _onNotificationTap(NotificationResponse response) {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.windows) return;
    unawaited(
      _windowChannel
          .invokeMethod<bool>('showWindow')
          .catchError((Object _) => false),
    );
  }

  /// Notifica cada aviso nuevo. No lanza nunca.
  @override
  Future<void> showAll(List<Map<String, dynamic>> fresh) =>
      _showAll(fresh, _androidDetails, 0, 'Aviso de evento');

  /// Notifica los avisos nuevos del PAQUETE. Los ids se desplazan para no
  /// chocar con los de los recordatorios en la bandeja del teléfono.
  @override
  Future<void> showPackageAll(List<Map<String, dynamic>> fresh) =>
      _showAll(fresh, _packageDetails, 500000, 'Aviso de tu paquete');

  Future<void> _showAll(
    List<Map<String, dynamic>> fresh,
    AndroidNotificationDetails details,
    int idOffset,
    String fallbackTitle,
  ) async {
    if (_kWeb) return;
    if (!_ready) await init();
    if (!_ready) return;
    for (var i = 0; i < fresh.length; i++) {
      final r = fresh[i];
      final base = (r['id'] is int)
          ? r['id'] as int
          : int.tryParse('${r['id']}') ?? (i + 1);
      try {
        await _plugin.show(
          idOffset + base.abs(),
          '${r['title'] ?? fallbackTitle}',
          '${r['body'] ?? ''}',
          // Android usa el canal de la app; Windows el toast nativo; Apple
          // presenta el aviso aunque la app esté en primer plano.
          NotificationDetails(
            android: details,
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBanner: true,
              presentList: true,
              presentSound: true,
            ),
            macOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBanner: true,
              presentList: true,
              presentSound: true,
            ),
            windows: const WindowsNotificationDetails(),
          ),
        );
      } catch (_) {
        // Mejor esfuerzo: el panel sigue siendo el aviso principal.
      }
    }
  }
}

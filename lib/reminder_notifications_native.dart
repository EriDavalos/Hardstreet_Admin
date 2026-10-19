import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

/// Muestra los avisos de eventos como notificaciones NATIVAS (Android).
///
/// `flutter_local_notifications` soporta Android/iOS/macOS/Linux, pero NO
/// Windows. En Windows el aviso visible es la campanita con badge de la top
/// bar, así que aquí solo se actúa cuando la plataforma tiene soporte real.
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
    channelDescription: 'Recordatorios de eventos próximos (1 semana / 1 día)',
    importance: Importance.high,
    priority: Priority.high,
  );

  /// Avisos del PAQUETE (fotos disponibles, servicio terminado…). Canal
  /// aparte para que el cliente pueda silenciarlos por separado.
  static const AndroidNotificationDetails _packageDetails =
      AndroidNotificationDetails(
    'paquete',
    'Avisos de mi paquete',
    channelDescription: 'Fotos disponibles, servicios terminados y avisos del estudio',
    importance: Importance.high,
    priority: Priority.high,
  );

  /// Inicializa el plugin y pide el permiso de notificaciones (Android 13+).
  /// Seguro llamar varias veces; si algo falla se marca como no listo y las
  /// notificaciones se omiten sin romper la app.
  Future<void> init() async {
    if (_ready || _kWeb) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings);
      // Android 13+ (API 33): sin este permiso el sistema DESCARTA la
      // notificación. Si el usuario lo niega, la campanita sigue avisando.
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (_) {
      _ready = false;
    }
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
          NotificationDetails(android: details),
        );
      } catch (_) {
        // Mejor esfuerzo: el panel sigue siendo el aviso principal.
      }
    }
  }
}



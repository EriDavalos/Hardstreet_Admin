import 'package:flutter_test/flutter_test.dart';
import 'package:hardstreet_admin/notification_sound.dart';
import 'package:hardstreet_admin/package_notifications_service.dart';
import 'package:hardstreet_admin/reminder_notifications_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ==================================================================
// AVISOS DEL PAQUETE: no repetir y no perder el registro
// ==================================================================
// «Avisar al cliente» debe verse UNA vez. El servicio recuerda los ids ya
// notificados EN DISCO, así que al cerrar y volver a abrir la app el mismo
// aviso (si sigue sin leer) no vuelve a saltar. Al cerrar sesión se olvida,
// porque otro usuario del mismo teléfono tiene que recibir los suyos.
// ==================================================================

class _RecordingNotifier implements ReminderNotifier, PackageNotifier {
  final List<List<Map<String, dynamic>>> packages = [];

  @override
  Future<void> showAll(List<Map<String, dynamic>> fresh) async {}

  @override
  Future<void> showPackageAll(List<Map<String, dynamic>> fresh) async {
    packages.add(fresh);
  }
}

Map<String, dynamic> _unread(int id, String title) => {
  'id': id,
  'title': title,
  'body': 'Cuerpo del aviso',
  'isRead': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = PackageNotificationsService.instance;

  /// Cuántas veces sonó la campanita (nada de audio en las pruebas).
  var sounds = 0;

  setUp(() {
    sounds = 0;
    service.sound = () async => sounds++;
  });

  tearDown(() async {
    service.reset();
    service.fetch = () async => (items: <Map<String, dynamic>>[], unread: 0);
    service.notifier = NativeReminderPlugin.instance;
    service.sound = NotificationSound.play;
  });

  test(
    'el mismo aviso no se notifica dos veces, ni tras reabrir la app',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final notifier = _RecordingNotifier();
      service.notifier = notifier;
      service.fetch = () async =>
          (items: [_unread(7, 'Ya puedes elegir tus fotos')], unread: 1);

      service.start();
      await service.refresh();
      expect(
        notifier.packages,
        hasLength(1),
        reason: 'el aviso nuevo se notifica una vez',
      );
      expect(sounds, 1, reason: 'la campanita suena con el aviso nuevo');

      // Otra consulta con el MISMO aviso: nada nuevo.
      await service.refresh();
      expect(notifier.packages, hasLength(1));
      expect(sounds, 1, reason: 'un aviso ya visto no vuelve a sonar');

      // «Cerrar y volver a abrir»: se pierde el set en memoria pero el disco
      // sigue; el aviso, aún sin leer, NO vuelve a notificarse.
      service.forgetNotifiedSession();
      await service.refresh();
      expect(
        notifier.packages,
        hasLength(1),
        reason: 'reabrir la app no repite el aviso ya mostrado',
      );

      // Y quedó guardado en disco.
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('app.notified.package'), '7');
    },
  );

  test('lo que ya avisó el worker nativo (app cerrada) no se repite', () async {
    // El worker de Android escribe en la MISMA preferencia con la app cerrada.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app.notified.package': '11,12',
    });
    final notifier = _RecordingNotifier();
    service.notifier = notifier;
    service.fetch = () async =>
        (items: [_unread(11, 'Ya puedes elegir tus fotos')], unread: 1);

    service.start();
    await service.refresh();
    expect(
      notifier.packages,
      isEmpty,
      reason: 'el teléfono ya la mostró: la app no la repite',
    );
    expect(sounds, 0, reason: 'tampoco suena: ya se avisó antes');
  });

  test('un aviso nuevo que no está en disco sí se notifica', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app.notified.package': '11',
    });
    final notifier = _RecordingNotifier();
    service.notifier = notifier;
    service.fetch = () async =>
        (items: [_unread(13, 'Servicio terminado')], unread: 1);

    service.start();
    await service.refresh();
    expect(notifier.packages, hasLength(1));
  });

  test(
    'cerrar sesión olvida lo notificado (para el siguiente usuario)',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final notifier = _RecordingNotifier();
      service.notifier = notifier;
      service.fetch = () async =>
          (items: [_unread(9, 'Servicio terminado')], unread: 1);

      service.start();
      await service.refresh();
      expect(notifier.packages, hasLength(1));

      service.reset();
      await Future<void>.delayed(Duration.zero);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('app.notified.package'), isNull);
    },
  );
}

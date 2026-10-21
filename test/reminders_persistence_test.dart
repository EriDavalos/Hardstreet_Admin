import 'package:flutter_test/flutter_test.dart';
import 'package:hardstreet_admin/reminder_notifications_native.dart';
import 'package:hardstreet_admin/reminders_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ==================================================================
// AVISOS DE EVENTOS: no repetir y no perder el registro
// ==================================================================
// El aviso de «falta 1 semana / falta 1 día» debe verse UNA vez. Los ids ya
// notificados se guardan EN DISCO, así que:
//   * al cerrar y volver a abrir la app el mismo aviso no vuelve a saltar, y
//   * lo que ya mostró el worker nativo de Android con la app CERRADA (que
//     escribe en la MISMA preferencia) tampoco se repite al abrir.
// ==================================================================

class _RecordingNotifier implements ReminderNotifier {
  final List<List<Map<String, dynamic>>> shown = [];

  @override
  Future<void> showAll(List<Map<String, dynamic>> fresh) async {
    shown.add(fresh);
  }
}

/// Aviso SIN LEER, con la forma que devuelve `/api/reminders`.
Map<String, dynamic> _unread(int id, String title, {String source = 'event'}) => {
      'id': id,
      'title': title,
      'body': 'Cuerpo del aviso',
      'isRead': 0,
      'source': source,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = RemindersService.instance;

  tearDown(() async {
    service.reset();
    service.fetch = () async => <Map<String, dynamic>>[];
    service.notifier = NativeReminderPlugin.instance;
  });

  test('el mismo aviso no se notifica dos veces, ni tras reabrir la app',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final notifier = _RecordingNotifier();
    service.notifier = notifier;
    service.fetch = () async => [_unread(7, 'Falta 1 semana: Boda - Premium')];

    service.start();
    await service.refresh();
    expect(notifier.shown, hasLength(1),
        reason: 'el aviso nuevo se notifica una vez');

    await service.refresh();
    expect(notifier.shown, hasLength(1), reason: 'la misma consulta no repite');

    // «Cerrar y volver a abrir»: se pierde el set en memoria pero el disco
    // sigue; el aviso, aún sin leer, NO vuelve a notificarse.
    service.forgetNotifiedSession();
    await service.refresh();
    expect(notifier.shown, hasLength(1),
        reason: 'reabrir la app no repite el aviso ya mostrado');

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('app.notified.reminders'), '7');
  });

  test('lo que ya avisó el worker nativo (app cerrada) no se repite',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app.notified.reminders': '11,12',
    });
    final notifier = _RecordingNotifier();
    service.notifier = notifier;
    service.fetch = () async => [_unread(11, 'Falta 1 día: Boda - Premium')];

    service.start();
    await service.refresh();
    expect(notifier.shown, isEmpty,
        reason: 'el teléfono ya lo mostró: la app no lo repite');
  });

  test('los avisos de impresión no chocan con los de agenda', () async {
    // Los ids de las dos tablas pueden coincidir: el de impresión se desplaza
    // (1000000 + id) tanto en la bandeja como en el registro.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app.notified.reminders': '9',
    });
    final notifier = _RecordingNotifier();
    service.notifier = notifier;
    service.fetch = () async => [
          _unread(9, 'Un cliente envió fotos a impresión', source: 'print'),
        ];

    service.start();
    await service.refresh();
    expect(notifier.shown, hasLength(1),
        reason: 'es OTRO aviso aunque el id coincida');

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('app.notified.reminders'), '9,1000009');
  });
}

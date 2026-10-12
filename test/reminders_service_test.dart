import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/reminder_notifications_native.dart';
import 'package:hardstreet_admin/reminders_service.dart';

/// Cliente falso que devuelve la lista de avisos dada y registra las
/// llamadas a markRead/markAllRead.
class _FakeBackend {
  _FakeBackend(this.reminders);

  List<Map<String, dynamic>> reminders;
  final List<int> markedRead = <int>[];
  bool markedAll = false;

  MockClient install() {
    return MockClient((request) async {
      final headers = {'content-type': 'application/json'};
      if (request.method == 'GET' && request.url.path.endsWith('/api/reminders')) {
        final unread = reminders.where((r) => _isUnread(r)).length;
        return http.Response(
          '{"reminders": ${_encode(reminders)}, "unread": $unread}',
          200,
          headers: headers,
        );
      }
      if (request.method == 'PUT' && request.url.path.endsWith('/api/reminders')) {
        final body = request.body;
        if (body.contains('"all":true')) {
          markedAll = true;
          for (final r in reminders) {
            r['isRead'] = 1;
          }
        } else {
          final id = int.tryParse(RegExp(r'"id":(\d+)').firstMatch(body)!.group(1)!);
          if (id != null) {
            markedRead.add(id);
            for (final r in reminders) {
              if (_int(r['id']) == id) r['isRead'] = 1;
            }
          }
        }
        final unread = reminders.where((r) => _isUnread(r)).length;
        return http.Response('{"ok":true,"unread":$unread}', 200, headers: headers);
      }
      return http.Response('{"error":"no encontrado"}', 404, headers: headers);
    });
  }

  static bool _isUnread(Map<String, dynamic> r) => _int(r['isRead']) == 0;
  static int? _int(dynamic v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));

  static String _encode(List<Map<String, dynamic>> list) {
    final items = list.map((r) {
      final sb = StringBuffer('{');
      var first = true;
      r.forEach((k, v) {
        if (!first) sb.write(',');
        first = false;
        sb.write('"$k":${v is String ? '"$v"' : v}');
      });
      sb.write('}');
      return sb.toString();
    }).join(',');
    return '[$items]';
  }
}

class _RecordingNotifier implements ReminderNotifier {
  final List<List<Map<String, dynamic>>> shown = <List<Map<String, dynamic>>>[];

  @override
  Future<void> showAll(List<Map<String, dynamic>> fresh) async {
    shown.add(fresh);
  }
}

Map<String, dynamic> _aviso(int id, {bool unread = true}) => {
      'id': id,
      'scheduleId': id * 10,
      'kind': id.isOdd ? '7d' : '1d',
      'title': 'Aviso $id',
      'body': 'Evento en $id días',
      'isRead': unread ? 0 : 1,
      'created': '2026-10-11T08:00:00',
    };

void main() {
  late _FakeBackend backend;
  late _RecordingNotifier notifier;
  late http.Client previousClient;

  setUp(() {
    previousClient = HsApi.client;
    notifier = _RecordingNotifier();
    RemindersService.instance.notifier = notifier;
  });

  tearDown(() {
    RemindersService.instance.reset();
    RemindersService.instance.notifier = NativeReminderPlugin.instance;
    HsApi.client = previousClient;
  });

  test('start() llena la lista y calcula el conteo de no leídos', () async {
    backend = _FakeBackend([_aviso(1), _aviso(2), _aviso(3, unread: false)]);
    HsApi.client = backend.install();

    RemindersService.instance.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(RemindersService.instance.reminders.length, 3);
    expect(RemindersService.instance.unread, 2);
    expect(RemindersService.instance.started, isTrue);
  });

  test('markRead marca optimista y confirma con el servidor', () async {
    backend = _FakeBackend([_aviso(1), _aviso(2)]);
    HsApi.client = backend.install();

    RemindersService.instance.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(RemindersService.instance.unread, 2);

    RemindersService.instance.markRead(1);
    await Future<void>.delayed(Duration.zero);

    expect(RemindersService.instance.unread, 1);
    expect(backend.markedRead, contains(1));
  });

  test('markAllRead deja el conteo en cero y confirma con el servidor', () async {
    backend = _FakeBackend([_aviso(1), _aviso(2), _aviso(3)]);
    HsApi.client = backend.install();

    RemindersService.instance.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    RemindersService.instance.markAllRead();
    await Future<void>.delayed(Duration.zero);

    expect(RemindersService.instance.unread, 0);
    expect(backend.markedAll, isTrue);
  });

  test('notifica los no leídos al iniciar y SOLO los nuevos en cada ciclo', () async {
    backend = _FakeBackend([_aviso(1)]);
    HsApi.client = backend.install();

    // Al iniciar se notifican los avisos NO leÍDOS pendientes: el usuario
    // se entera aunque la app se abra tarde (p. ej. un evento "mañana").
    RemindersService.instance.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.shown.length, 1);
    expect(notifier.shown.single.length, 1);
    expect(_int(notifier.shown.single.single['id']), 1);
    expect(RemindersService.instance.unread, 1);

    // Ya notificado: un refresh con la MISMA lista no vuelve a avisar.
    await RemindersService.instance.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(notifier.shown.length, 1);

    // Llega un aviso NUEVO: en el siguiente ciclo sí se notifica, solo ese.
    backend.reminders.add(_aviso(2));
    await RemindersService.instance.refresh();
    await Future<void>.delayed(Duration.zero);

    expect(notifier.shown.length, 2);
    expect(notifier.shown.last.length, 1);
    expect(_int(notifier.shown.last.single['id']), 2);
  });

  test('stop() detiene el polling; reset() limpia estado y no notifica', () async {
    backend = _FakeBackend([_aviso(1)]);
    HsApi.client = backend.install();

    RemindersService.instance.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(RemindersService.instance.unread, 1);

    RemindersService.instance.stop();
    expect(RemindersService.instance.started, isFalse);

    RemindersService.instance.reset();
    expect(RemindersService.instance.reminders, isEmpty);
    expect(RemindersService.instance.unread, 0);
  });

  test('un fallo de red no lanza: conserva el último estado', () async {
    HsApi.client = MockClient((_) async => http.Response('sin red', 500));
    RemindersService.instance.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(RemindersService.instance.reminders, isEmpty);
    expect(RemindersService.instance.unread, 0);
  });

  test('stop() tras start() cancela el Timer periódico', () async {
    backend = _FakeBackend([_aviso(1)]);
    HsApi.client = backend.install();
    RemindersService.instance.start();
    RemindersService.instance.stop();
    // Si el Timer no se canceló, este delay dispararía un refresh extra.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(RemindersService.instance.started, isFalse);
  });
}

int? _int(dynamic v) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));

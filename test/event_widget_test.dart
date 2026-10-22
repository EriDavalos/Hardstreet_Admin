import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/app_settings.dart';
import 'package:hardstreet_admin/event_widget.dart';
import 'package:hardstreet_admin/hs_access.dart';

Map<String, dynamic> _agenda({
  required String date,
  String packageName = 'Boda - Premium',
  String clientName = 'Ana Ruiz',
  String serviceName = 'Cobertura en evento',
  int serviceId = 3,
}) =>
    {
      'purchasedPackageId': 10,
      'clientName': clientName,
      'packageName': packageName,
      'serviceName': serviceName,
      'serviceId': serviceId,
      'eventDate': date,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 15, 10, 0);

  test('cada evento trae las claves que leen los widgets nativos', () {
    final events = UpcomingEventsWidget.buildEvents(
      [_agenda(date: '2026-10-18 12:00:00')],
      now: now,
    );
    expect(
      events.single.keys.toSet(),
      {
        'id',
        'service',
        'title',
        'subtitle',
        'when',
        'time',
        'day',
        'showDay',
        'at'
      },
      reason: 'Android (EventWidgetProvider) y Windows (event_widget.cpp) '
          'leen EXACTAMENTE estas claves; `id` es la agenda que se abre al '
          'tocar la fila y `service` elige el color de la tarjeta',
    );
    expect(events.single['at'], isA<int>()); // optLong en Kotlin
    expect(events.single['id'], isA<int>());
  });

  test('cada evento lleva el SERVICIO: el widget tiñe la fila con su color',
      () {
    final events = UpcomingEventsWidget.buildEvents(
      [_agenda(date: '2026-10-18 12:00:00', serviceId: 5)],
      now: now,
    );
    expect(events.single['service'], 5);

    // Sin servicio (un aviso) va en 0: color neutro.
    final fromReminders = UpcomingEventsWidget.buildEvents(
      const [],
      reminders: [
        {'title': 'Entrega', 'body': 'Ana Ruiz', 'eventDate': '2026-10-18 09:00:00'},
      ],
      now: now,
    );
    expect(fromReminders.single['service'], 0);
  });

  test('cada evento lleva el ID de su agenda (lo usa el toque del widget)', () {
    final events = UpcomingEventsWidget.buildEvents(
      [
        {
          'id': 77,
          'purchasedPackageId': 10,
          'clientName': 'Ana Ruiz',
          'packageName': 'Boda - Premium',
          'serviceName': 'Cobertura en evento',
          'eventDate': '2026-10-18 12:00:00',
        },
      ],
      now: now,
    );
    expect(events.single['id'], 77);

    // Un aviso NO es una agenda: va sin id (tocar la fila solo abre la app).
    final fromReminders = UpcomingEventsWidget.buildEvents(
      const [],
      reminders: [
        {'title': 'Falta 1 día', 'body': 'Ana', 'eventDate': '2026-10-18 12:00:00'},
      ],
      now: now,
    );
    expect(fromReminders.single['id'], 0);
  });

  test('empuja al widget si el rol puede CREAR agendas (botón "+")', () async {
    final calls = <MethodCall>[];
    const channel = MethodChannel(UpcomingEventsWidget.channelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      HsAccess.reset();
    });

    // Sin permisos cargados (modo degradado) no se esconde nada: el backend
    // revalida de todos modos.
    await UpcomingEventsWidget.publish(
      [_agenda(date: '2026-10-18 12:00:00')],
      now: now,
    );
    var args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['canAdd'], isTrue);

    // Un rol SIN "Crear" en Agendas: el widget esconde el botón.
    calls.clear();
    HsAccess.seedForTest(
      admin: false,
      modules: {
        'agendas': {'read'},
      },
    );
    await UpcomingEventsWidget.publish(
      [_agenda(date: '2026-10-18 12:00:00')],
      now: now,
    );
    args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['canAdd'], isFalse,
        reason: 'sin permiso de crear no se ofrece "Agregar agenda"');
  });

  test('refresh() no vacía el widget antes de tener datos que publicar',
      () async {
    UpcomingEventsWidget.resetForTest();
    final calls = <MethodCall>[];
    const channel = MethodChannel(UpcomingEventsWidget.channelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      UpcomingEventsWidget.resetForTest();
    });

    // Sesión recién abierta (permisos/tema antes de consultar la agenda):
    // empujar una lista vacía dejaría al widget sin eventos.
    await UpcomingEventsWidget.refresh();
    expect(calls, isEmpty);

    // Ya con datos, el refresco (cambio de tema o de permisos) SÍ repinta.
    await UpcomingEventsWidget.publish(
      [_agenda(date: '2026-10-18 12:00:00')],
      now: now,
    );
    await UpcomingEventsWidget.refresh();
    expect(calls, hasLength(2));
    final args = calls.last.arguments as Map<Object?, Object?>;
    expect((args['events'] as List<Object?>), hasLength(1));
  });

  test('los toques del widget nativo llegan a la app (detalle y alta)', () async {
    UpcomingEventsWidget.listen();
    addTearDown(UpcomingEventsWidget.resetForTest);
    UpcomingEventsWidget.requested.value = null;

    Future<void> simulate(Object arguments) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        UpcomingEventsWidget.channelName,
        const StandardMethodCodec()
            .encodeMethodCall(MethodCall('onWidgetTap', arguments)),
        (_) {},
      );
    }

    await simulate({'action': 'agenda', 'id': 12});
    expect(UpcomingEventsWidget.requested.value?.agendaId, 12);
    expect(UpcomingEventsWidget.requested.value?.create, isFalse);

    await simulate({'action': 'new', 'id': 0});
    expect(UpcomingEventsWidget.requested.value?.create, isTrue);
  });

  test('empuja al widget TODOS los eventos y el MODO de la app', () async {
    final calls = <MethodCall>[];
    const channel = MethodChannel(UpcomingEventsWidget.channelName);
    // Canal simulado: aquí se ve lo que la app le manda al widget nativo.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      AppSettings.instance.setDark(false);
    });

    AppSettings.instance.setDark(true); // modo oscuro en la app
    await UpcomingEventsWidget.publish(
      [
        for (var d = 16; d <= 27; d++)
          _agenda(date: '2026-10-$d 10:00:00', packageName: 'Evento $d'),
      ],
      now: now,
    );

    expect(calls, hasLength(1));
    expect(calls.single.method, 'update');
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['dark'], isTrue,
        reason: 'el widget debe pintarse con el modo de la APP');
    expect((args['events'] as List<Object?>), hasLength(12),
        reason: 'se manda TODA la agenda próxima, sin recortar');
  });

  test('arma los próximos eventos: solo futuros, en orden y con su fecha', () {
    final events = UpcomingEventsWidget.buildEvents(
      [
        _agenda(date: '2026-10-20 17:30:00', packageName: 'XV Años - Gold'),
        _agenda(date: '2026-10-02 09:00:00', packageName: 'Evento pasado'),
        _agenda(date: '2026-10-18 12:00:00', packageName: 'Bautizo'),
      ],
      now: now,
    );

    expect(events, hasLength(2), reason: 'el evento pasado ya no se muestra');
    expect(events.first['title'], 'Bautizo'); // 18 oct antes que 20 oct
    expect(events.last['title'], 'XV Años - Gold');
    expect(events.first['subtitle'], 'Ana Ruiz · Cobertura en evento');
    expect(events.first['when'], '18 oct · 12:00');
    expect(events.first['at'],
        DateTime(2026, 10, 18, 12).millisecondsSinceEpoch);
  });

  test('el evento EN CURSO todavía se muestra (1 hora de gracia)', () {
    final events = UpcomingEventsWidget.buildEvents(
      [_agenda(date: '2026-10-15 09:30:00')],
      now: now, // 30 min después de empezar
    );
    expect(events, hasLength(1));
  });

  test('muestra TODA la agenda próxima, sin recortar', () {
    final events = UpcomingEventsWidget.buildEvents(
      [
        for (var d = 16; d <= 30; d++)
          _agenda(date: '2026-10-$d 10:00:00', packageName: 'Evento $d'),
      ],
      now: now,
    );
    expect(events, hasLength(15), reason: 'no se recorta la lista');
    expect(events.first['title'], 'Evento 16');
    expect(events.last['title'], 'Evento 30');
  });

  test('los eventos se catalogan por día: un encabezado por fecha', () {
    final events = UpcomingEventsWidget.buildEvents(
      [
        _agenda(date: '2026-10-16 09:00:00', packageName: 'Mañana A'),
        _agenda(date: '2026-10-16 15:00:00', packageName: 'Mañana B'),
        _agenda(date: '2026-10-17 10:00:00', packageName: 'Siguiente'),
      ],
      now: now,
    );
    expect(events, hasLength(3));
    expect(events.map((e) => e['showDay']).toList(), [true, false, true]);
    expect(events[0]['day'], isNotEmpty);
    expect(events[0]['day'], events[1]['day']); // mismo día = mismo rótulo
    expect(events[2]['day'], isNot(events[0]['day']));
  });

  test('sin agendas usa los AVISOS del servidor como respaldo', () {
    final events = UpcomingEventsWidget.buildEvents(
      const [],
      reminders: [
        {
          'title': 'Falta 1 semana: Boda - Premium',
          'body': 'Ana Ruiz · Cobertura en evento',
          'eventDate': '2026-10-22 19:00:00',
        },
      ],
      now: now,
    );
    expect(events, hasLength(1));
    expect(events.first['title'], 'Falta 1 semana: Boda - Premium');
    expect(events.first['when'], '22 oct · 19:00');
  });

  test('un hueco ajeno enmascarado NO llega al widget (nada de "Ocupado")',
      () {
    final events = UpcomingEventsWidget.buildEvents(
      [
        {
          ..._agenda(date: '2026-10-18 12:00:00'),
          // Lo que manda el servidor a un CLIENTE para los eventos de OTROS.
          'busy': true,
          'clientName': '',
          'packageName': '',
          'serviceName': '',
          'serviceId': null,
        },
      ],
      now: now,
    );
    expect(
      events,
      isEmpty,
      reason: 'El widget de la pantalla de inicio no enseña días solo '
          '"ocupados": esas filas no dicen nada.',
    );
  });

  test('el hueco ajeno se descarta pero los eventos propios sí entran', () {
    final events = UpcomingEventsWidget.buildEvents(
      [
        {
          ..._agenda(date: '2026-10-18 12:00:00'),
          'busy': true,
          'clientName': '',
          'packageName': '',
        },
        _agenda(date: '2026-10-19 15:00:00'),
      ],
      now: now,
    );
    expect(events, hasLength(1));
    expect(events.single['time'], '15:00');
  });

  test('sin eventos devuelve una lista vacía (el widget dice "sin eventos")',
      () {
    expect(UpcomingEventsWidget.buildEvents(const [], now: now), isEmpty);
    expect(
      UpcomingEventsWidget.buildEvents([_agenda(date: '2026-01-01 10:00:00')],
          now: now),
      isEmpty,
    );
  });
}

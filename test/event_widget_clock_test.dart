import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El widget de eventos se actualiza SOLO, sin la app abierta.
///
/// Los widgets nativos (inicio de Android y panel de Windows) guardan el evento
/// con su INSTANTE (`at`) y recalculan el rótulo del día con la hora del
/// dispositivo, además de repintarse por su cuenta cada tanto. Si eso se
/// perdiera, el rótulo empujado por la app envejecería y al día siguiente
/// seguiría diciendo "HOY".
///
/// Es una prueba de FUENTE (como event_widget_theme_test.dart): las dos
/// implementaciones viven fuera de Dart y aquí solo se comprueba que conservan
/// el contrato que hace que el widget se mantenga al día por sí mismo.
const String _androidClock =
    'android/app/src/main/kotlin/com/example/hardstreet_admin/EventWidgetClock.kt';
const String _androidProvider =
    'android/app/src/main/kotlin/com/example/hardstreet_admin/EventWidgetProvider.kt';
const String _androidService =
    'android/app/src/main/kotlin/com/example/hardstreet_admin/EventWidgetService.kt';
const String _androidInfo = 'android/app/src/main/res/xml/event_widget_info.xml';
const String _windowsWidget = 'windows/runner/event_widget.cpp';
const String _windowsHeader = 'windows/runner/event_widget.h';
const String _windowsChannel = 'windows/runner/flutter_window.cpp';

void main() {
  test('Android: el rótulo del día se calcula en el widget, desde `at`', () {
    final clock = File(_androidClock).readAsStringSync();

    // El rótulo sale del instante del evento y de la hora actual (no de un
    // texto ya escrito por la app).
    expect(clock, contains('fun dayLabel(at: Long'));
    expect(clock, contains('HOY · '), reason: 'debe poder rotular HOY');
    expect(clock, contains('MAÑANA · '), reason: 'debe poder rotular MAÑANA');

    // Y descarta lo que ya pasó, con la MISMA hora de gracia de la app.
    expect(clock, contains('GRACE_MS = 60L * 60L * 1000L'),
        reason: 'un evento en curso no debe desaparecer del widget');
    expect(clock,
        contains('dayLabel(e.at, now)'),
        reason: 'cada evento se rotula con su propio instante');
  });

  test('Android: el widget se repinta solo (alarma propia) y usa el cálculo '
      'nativo', () {
    final provider = File(_androidProvider).readAsStringSync();
    final service = File(_androidService).readAsStringSync();
    final info = File(_androidInfo).readAsStringSync();

    // El listado y el contador salen del cálculo nativo, no de lo empujado.
    expect(service, contains('EventWidgetProvider.shownEvents(context)'),
        reason: 'la lista debe rotularse con la hora del teléfono');
    expect(provider, contains('EventWidgetClock.fresh(readEvents(context))'),
        reason: 'el contador y la lista deben compartir el mismo cálculo');
    expect(provider, contains('val count = shownEvents(context).size'));

    // Refresco propio: alarma que vuelve al provider y lo repinta.
    expect(provider, contains('AlarmManager.ELAPSED_REALTIME'));
    expect(provider, contains('setInexactRepeating'),
        reason: 'inexacto: el sistema lo agrupa y no gasta batería');
    expect(provider, contains('if (intent.action == ACTION_REFRESH)'));
    expect(provider, contains('override fun onReceive'));
    expect(provider, contains('cancelRefresh'),
        reason: 'sin widgets colocados no debe quedar la alarma viva');

    // Y el sistema también lo despierta por su cuenta.
    final period =
        RegExp(r'android:updatePeriodMillis="(\d+)"').firstMatch(info);
    expect(period, isNotNull, reason: 'falta updatePeriodMillis');
    expect(int.parse(period!.group(1)!), greaterThan(0),
        reason: 'en 0 el lanzador nunca repintaría el widget por su cuenta');
  });

  test('Windows: el panel recalcula el rótulo y descarta lo vencido', () {
    final cpp = File(_windowsWidget).readAsStringSync();
    final header = File(_windowsHeader).readAsStringSync();
    final channel = File(_windowsChannel).readAsStringSync();

    // El canal le pasa el instante del evento (sin él no hay nada que
    // recalcular).
    expect(channel, contains('event.at_ms = Int64Of(ArgOf(*map, "at"))'));

    // Y el panel lo usa para rotular/vencer con la hora de la computadora.
    expect(header, contains('long long at_ms'));
    expect(cpp, contains('void EventWidget::RefreshNow()'));
    expect(cpp, contains('e.day = DayLabel(source.at_ms, now)'));
    expect(cpp, contains('HOY '), reason: 'debe poder rotular HOY');
    expect(cpp, contains('MA'), reason: 'debe poder rotular MAÑANA');

    // Se repinta solo con su temporizador (el panel puede quedar abierto toda
    // la noche).
    expect(cpp, contains('SetTimer(hwnd_, kRefreshTimerId, kRefreshMs'),
        reason: 'sin temporizador el panel se quedaría con el rótulo viejo');
    expect(cpp, contains('case WM_TIMER'));
    expect(cpp, contains('RefreshByTimer();'));
  });
}

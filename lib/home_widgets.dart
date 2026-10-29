import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_platform.dart';
import 'app_settings.dart';
import 'hs_access.dart';
import 'hs_format.dart';
import 'note_model.dart';

/// Lo que se tocó en el widget de Notas.
@immutable
class NoteWidgetTap {
  const NoteWidgetTap({this.noteId = 0, this.create = false});

  /// Id de la nota tocada (0 = solo abrir el módulo).
  final int noteId;

  /// true si se tocó el botón «Nueva nota».
  final bool create;
}

/// WIDGET de «Notas» (pantalla de inicio de Android).
///
/// Mismo contrato que [UpcomingEventsWidget] pero para notas: la app consulta
/// el API y EMPUJA las notas recientes por el MethodChannel; el widget nativo
/// solo dibuja lo guardado (sobrevive a que la app esté cerrada).
///
///   Canal `hardstreet/notes_widget`:
///     update      { header, dark, count, canCreate, notes: [...] }
///     consumeTap  → {action,id}?  (arranque en frío: asomar la acción pendiente)
///     clearTap    (marca la acción pendiente como ya atendida)
///
/// Sentido inverso: `onWidgetTap { action: 'note'|'note_new', id }` publicado
/// en [requested]; la página de Notas abre esa nota (o el alta).
class NotesWidget {
  NotesWidget._();

  static const String channelName = 'hardstreet/notes_widget';

  static const MethodChannel _channel = MethodChannel(channelName);

  static const String header = 'Notas';

  /// ¿Hay widget nativo que alimentar? (solo Android; en web/escritorio no).
  static bool get supported => isAndroidPlatform;

  /// ¿El rol puede CREAR notas? (decide el botón «+» del widget).
  static bool get canCreate =>
      HsAccess.instance.degraded ||
      HsAccess.instance.can('notes', 'create') ||
      HsAccess.instance.can('Notas', 'create');

  /// Últimas filas publicadas (sondeable en pruebas).
  static List<Map<String, dynamic>> get rows => _rows;
  static List<Map<String, dynamic>> _rows = const [];

  /// Último toque del widget nativo; la página de Notas lo consume y lo deja
  /// en null para que no se repita.
  static final ValueNotifier<NoteWidgetTap?> requested = ValueNotifier(null);

  /// Escucha los toques del widget. Idempotente.
  static void listen() {
    if (kWeb) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onWidgetTap') _applyTap(call.arguments);
      return null;
    });
  }

  /// ¿El widget lanzó la app en frío con una acción de notas? Se pregunta UNA
  /// vez al entrar al panel. SOLO reclama la acción si es suya: si el toque
  /// fue de otro widget, la deja pendiente para que él la consuma.
  static Future<void> consumePending() async {
    if (kWeb) return;
    try {
      final raw = await _channel.invokeMethod<Object?>('consumeTap');
      if (raw is Map && _ownsAction('${raw['action']}')) {
        _applyTap(raw);
        await _channel.invokeMethod<void>('clearTap');
      }
    } catch (_) {
      // Canal no disponible (plataforma sin widget): nada que hacer.
    }
  }

  /// ¿El tipo de acción es de este widget? (los demás widgets también pasan
  /// por el mismo Intent pendiente del arranque en frío).
  static bool _ownsAction(String action) {
    final a = action.toLowerCase();
    return a == 'note' || a == 'note_new';
  }

  static void _applyTap(Object? raw) {
    if (raw is! Map) return;
    requested.value = NoteWidgetTap(
      noteId: (raw['id'] as num?)?.toInt() ?? 0,
      create: '${raw['action']}'.toLowerCase() == 'note_new',
    );
  }

  /// Publica las notas recientes en el widget. No lanza: si el widget no
  /// existe o el canal falla, la app sigue igual.
  static Future<void> publish(
    List<NoteSummary> summaries, {
    DateTime? now,
  }) async {
    if (!supported || kWeb) return;
    _rows = buildRows(summaries, now: now);
    await _push();
  }

  /// Vuelve a mandar lo último publicado (cambio de tema / permisos).
  /// Si esta sesión no publicó nada, no manda nada: empujar vacío borraría
  /// lo que el widget ya mostraba.
  static Future<void> refresh() async {
    if (!_published) return;
    await _push();
  }

  static bool _published = false;

  /// Filas ya formateadas del listado: las FIJADAS primero y dentro de cada
  /// grupo la MÁS RECIENTE arriba. Sin notas no manda filas: el widget dice
  /// «Sin notas todavía».
  static List<Map<String, dynamic>> buildRows(
    List<NoteSummary> summaries, {
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final rows = <_NoteRow>[];
    for (final n in summaries) {
      if (n.id <= 0) continue;
      rows.add(_NoteRow(
        id: n.id,
        title: n.displayTitle,
        sub: n.preview.trim(),
        pinned: n.pinned,
        at: n.updated,
      ));
    }
    rows.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      final aAt = a.at ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = b.at ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bAt.compareTo(aAt); // la más reciente primero
    });
    // Tope sencillo: en el widget no cabe más que un puñado.
    const max = 40;
    return [
      for (final r in rows.take(max))
        {
          'id': r.id,
          'title': r.title,
          'sub': r.sub,
          // Etiqueta corta: «HOY · 29 OCT», «25 oct».
          'when': _when(r.at, now: ref),
        },
    ];
  }

  /// Fecha corta ES de la nota («29 OCT», con HOY/MAÑANA cuando aplica).
  static String _when(DateTime? d, {DateTime? now}) {
    if (d == null) return '';
    return hsDayLabel(d, now ?? DateTime.now());
  }

  static Future<void> _push() async {
    if (kWeb) return;
    try {
      await _channel.invokeMethod<void>('update', {
        'header': header,
        'dark': AppSettings.instance.dark,
        'canCreate': canCreate,
        'count': _rows.length,
        'notes': _rows,
      });
      _published = true;
    } catch (_) {
      // Motor nativo sin widget (mejor esfuerzo).
    }
  }

  /// SOLO PRUEBAS.
  @visibleForTesting
  static void resetForTest() {
    _published = false;
    _rows = const [];
    requested.value = null;
  }
}

/// WIDGET de «Avisos» (pantalla de inicio de Android).
///
/// Lista los avisos recientes de la campanita (eventos, impresión y paquete).
/// Los datos los empuja la app (que ya los consulta cada 15 s en
/// [RemindersService]); el widget no consulta nada por su cuenta.
///
/// Tocar una fila solo TRAE LA APP AL FRENTE: los avisos pueden venir de
/// varias tablas y no todos son un evento abrible; el detalle está en la
/// campanita de la app.
class AvisosWidget {
  AvisosWidget._();

  static const String channelName = 'hardstreet/reminders_widget';

  static const MethodChannel _channel = MethodChannel(channelName);

  static const String header = 'Avisos';

  static bool get supported => isAndroidPlatform;

  /// Últimas filas publicadas (sondeable en pruebas).
  static List<Map<String, dynamic>> get rows => _rows;
  static List<Map<String, dynamic>> _rows = const [];

  /// Publica los avisos. No lanza. [rows] = lo que devuelve
  /// `HsApi.reminders` (id, title, body, eventDate, isRead, source…).
  static Future<void> publish(List<Map<String, dynamic>> reminders) async {
    if (!supported || kWeb) return;
    _rows = buildRows(reminders);
    await _push();
  }

  /// Repinta con lo último publicado (cambio de tema).
  static Future<void> refresh() async {
    if (!_published) return;
    await _push();
  }

  static bool _published = false;

  /// Filas del widget: los avisos más recientes arriba, y los SIN LEER
  /// marcados con «● » en el título (RemoteViews no admite estilos por fila).
  static List<Map<String, dynamic>> buildRows(
    List<Map<String, dynamic>> reminders,
  ) {
    final rows = <_AvisoRow>[];
    for (final r in reminders) {
      final title = (r['title'] ?? '').toString().trim();
      final body = (r['body'] ?? '').toString().trim();
      if (title.isEmpty && body.isEmpty) continue;
      rows.add(_AvisoRow(
        id: (r['id'] as num?)?.toInt() ?? 0,
        title: title.isEmpty ? 'Aviso' : title,
        sub: body,
        unread: (r['isRead'] as num?)?.toInt() == 0,
        at: hsParseDate(r['eventDate']),
      ));
    }
    // Sin fecha queda al final; con fecha, el más nuevo arriba.
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    rows.sort((a, b) => (b.at ?? epoch).compareTo(a.at ?? epoch));
    const max = 40;
    return [
      for (final r in rows.take(max))
        {
          'id': r.id,
          'title': r.unread ? '● ${r.title}' : r.title,
          'sub': r.sub,
          'when': _when(r.at),
        },
    ];
  }

  static String _when(DateTime? d) {
    if (d == null) return '';
    final month = kHsMonths[d.month - 1];
    final short = month.length > 3 ? month.substring(0, 3) : month;
    return '${d.day} $short · ${hsTimeLabel(d)}';
  }

  static Future<void> _push() async {
    if (kWeb) return;
    try {
      await _channel.invokeMethod<void>('update', {
        'header': header,
        'dark': AppSettings.instance.dark,
        'count': _rows.length,
        'avisos': _rows,
      });
      _published = true;
    } catch (_) {
      // Mejor esfuerzo: sin widget nativo la app sigue igual.
    }
  }

  /// SOLO PRUEBAS.
  @visibleForTesting
  static void resetForTest() {
    _published = false;
    _rows = const [];
  }
}

class _NoteRow {
  const _NoteRow({
    required this.id,
    required this.title,
    required this.sub,
    required this.pinned,
    required this.at,
  });

  final int id;
  final String title;
  final String sub;
  final bool pinned;
  final DateTime? at;
}

class _AvisoRow {
  const _AvisoRow({
    required this.id,
    required this.title,
    required this.sub,
    required this.unread,
    required this.at,
  });

  final int id;
  final String title;
  final String sub;
  final bool unread;
  final DateTime? at;
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../hs_api.dart';
import '../hs_format.dart';
import '../widgets/anim.dart';
import '../widgets/common.dart';
import '../widgets/form_dialog.dart';

/// Paleta estable por servicio: cada servicio conserva su color en toda la
/// vista (calendario, panel lateral y modal de detalle).
const List<Color> _agendaPalette = [
  Color(0xFF8B5CF6),
  Color(0xFF10B981),
  Color(0xFFF59E0B),
  Color(0xFF3B82F6),
  Color(0xFFEF4444),
  Color(0xFF14B8A6),
  Color(0xFFEC4899),
  Color(0xFF6366F1),
];

Color _serviceColorOf(int? id) => id == null
    ? const Color(0xFF64748B)
    : _agendaPalette[id.abs() % _agendaPalette.length];

/// Resumen visual de UN día con eventos: color e icono del servicio y cuántos
/// eventos tiene agendados.
typedef _DayEvent = ({Color color, IconData icon, int count});

/// Icono del badge del día a partir del NOMBRE del servicio: así el calendario
/// dice QUÉ hay agendado (video, fotos, álbum, entrega…) y no solo que hay algo.
IconData _serviceIconOf(String name) {
  final n = name.toLowerCase();
  bool has(List<String> keys) => keys.any(n.contains);
  if (has(['video', 'vídeo', 'film', 'camara', 'cámara', 'grabac'])) {
    return Icons.videocam_rounded;
  }
  if (has(['foto', 'retrato', 'sesion', 'sesión', 'book'])) {
    return Icons.photo_camera_rounded;
  }
  if (has(['album', 'álbum', 'impresi', 'revelado'])) {
    return Icons.photo_album_rounded;
  }
  if (has(['transmis', 'stream', 'en vivo', 'envivo'])) {
    return Icons.live_tv_rounded;
  }
  if (has(['dron', 'aere', 'aére'])) return Icons.flight_takeoff_rounded;
  if (has(['entrega', 'envio', 'envío', 'paqueteria', 'paquetería'])) {
    return Icons.local_shipping_rounded;
  }
  if (has(['cabina', 'estudio', 'iluminac'])) {
    return Icons.wb_incandescent_rounded;
  }
  if (has(['maquill', 'peinado', 'estilismo'])) return Icons.brush_rounded;
  if (has(['musica', 'música', 'dj', 'sonido', 'audio'])) {
    return Icons.music_note_rounded;
  }
  return Icons.event_available_rounded;
}

/// Resumen de un servicio con su número de agendas y su clave de filtro.
typedef _ServiceCount = ({int key, int? id, String name, int count});

/// Primer día (lunes) de la semana que contiene a [d].
DateTime _weekStartOf(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

/// ¿La fecha trae HORA real (no es medianoche)? Las agendas sin hora se
/// muestran en la fila de "todo el día" de la vista de semana.
bool _isTimed(DateTime d) => !(d.hour == 0 && d.minute == 0);

/// Módulo AGENDAS con la ESTRUCTURA de Google Calendar:
/// - Barra superior: botón "Hoy", flechas de navegación, título del periodo y
///   conmutador Semana/Mes.
/// - Panel lateral (hoja en móvil): buscador, mini-calendario con puntos en
///   los días que tienen eventos, y filtros por servicio tipo "Mis calendarios".
/// - Vista de SEMANA: encabezados de día (hoy resaltado), fila de eventos de
///   todo el día y rejilla de horas con los eventos colocados por hora de
///   inicio y duración, más la línea roja de "ahora".
/// - Vista de MES: cuadrícula con badges de color e icono del servicio.
/// El calendario ocupa TODA la altura disponible sin desbordar la pantalla.
class AgendasPage extends StatefulWidget {
  const AgendasPage({super.key});

  @override
  State<AgendasPage> createState() => _AgendasPageState();
}

class _AgendasPageState extends State<AgendasPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _all = const [];
  String _query = '';

  /// Claves de servicio OCULTAS (id ?? -1): el panel lateral actúa como
  /// checkboxes "Mis servicios".
  final Set<int> _hidden = {};

  /// Día de referencia del periodo visible (mes o semana).
  late DateTime _anchor;

  /// Mes que muestra el mini-calendario del panel lateral.
  late DateTime _pickerMonth;

  DateTime? _selected;

  /// 0 = mes, 1 = semana; null = decidir según el ancho de la pantalla.
  int? _view;

  /// Vista actual cacheada desde el último build (la usan los botones).
  bool _isWeek = true;

  /// 1 = adelante, -1 = atrás: dirección de la animación de transición.
  int _slideDir = 1;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _anchor = now;
    _pickerMonth = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final agendas = await HsApi.agendas();
      if (!mounted) return;
      setState(() {
        _all = agendas;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar las agendas';
        _loading = false;
      });
    }
  }

  DateTime? _dateOf(Map<String, dynamic> a) => hsParseDate(a['eventDate']);

  /// Servicios con agendas (los que ya tenemos), ordenados por cantidad.
  List<_ServiceCount> get _serviceSummary {
    final map = <int, _ServiceCount>{};
    for (final a in _all) {
      final id = (a['serviceId'] as num?)?.toInt();
      final name = (a['serviceName'] ?? '').toString().trim();
      final key = id ?? -1;
      final prev = map[key];
      map[key] = (
        key: key,
        id: id,
        name: name.isEmpty ? 'Sin servicio específico' : name,
        count: (prev?.count ?? 0) + 1,
      );
    }
    return map.values.toList()..sort((a, b) => b.count.compareTo(a.count));
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    return _all.where((a) {
      final key = (a['serviceId'] as num?)?.toInt() ?? -1;
      if (_hidden.contains(key)) return false;
      if (q.isEmpty) return true;
      final hay = '${a['clientName'] ?? ''} ${a['packageName'] ?? ''} '
              '${a['serviceName'] ?? ''} ${a['description'] ?? ''}'
          .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  /// Días del MES [month] con eventos: color + icono del servicio y cuántos.
  Map<String, _DayEvent> _eventsOfMonth(DateTime month) {
    final out = <String, _DayEvent>{};
    for (final a in _filtered) {
      final d = _dateOf(a);
      if (d == null || d.year != month.year || d.month != month.month) {
        continue;
      }
      final key = hsDateKey(d);
      final prev = out[key];
      if (prev == null) {
        out[key] = (
          color: _serviceColorOf((a['serviceId'] as num?)?.toInt()),
          icon: _serviceIconOf((a['serviceName'] ?? '').toString()),
          count: 1,
        );
      } else {
        out[key] = (
          color: prev.color,
          icon: prev.icon,
          count: prev.count + 1,
        );
      }
    }
    return out;
  }

  Map<String, _DayEvent> get _monthEvents => _eventsOfMonth(_anchor);

  List<Map<String, dynamic>> _eventsOfDay(DateTime day) {
    final key = hsDateKey(day);
    return _filtered
        .where((a) {
          final d = _dateOf(a);
          return d != null && hsDateKey(d) == key;
        })
        .toList()
      ..sort((a, b) => '${a['eventDate']}'.compareTo('${b['eventDate']}'));
  }

  List<Map<String, dynamic>> get _upcoming {
    final now = DateTime.now();
    return (_filtered
            .where((a) {
              final d = _dateOf(a);
              return d != null && d.isAfter(now);
            })
            .toList()
          ..sort(
              (a, b) => '${a['eventDate']}'.compareTo('${b['eventDate']}')))
        .take(4)
        .toList();
  }

  int get _upcomingCount {
    final now = DateTime.now();
    return _filtered.where((a) {
      final d = _dateOf(a);
      return d != null && d.isAfter(now);
    }).length;
  }

  // -----------------------------------------------------------
  // Navegación del periodo
  // -----------------------------------------------------------

  void _shift(int dir) {
    setState(() {
      _slideDir = dir;
      if (_isWeek) {
        _anchor = _anchor.add(Duration(days: 7 * dir));
      } else {
        _anchor = DateTime(_anchor.year, _anchor.month + dir, 1);
      }
      _pickerMonth = DateTime(_anchor.year, _anchor.month);
    });
  }

  void _goToToday() {
    final now = DateTime.now();
    setState(() {
      final target = _isWeek ? now : DateTime(now.year, now.month);
      _slideDir = target.isAfter(_anchor) ? 1 : -1;
      _anchor = target;
      _selected = DateTime(now.year, now.month, now.day);
      _pickerMonth = DateTime(now.year, now.month);
    });
  }

  /// Salta a un día (mini-calendario): mueve el periodo visible si el día
  /// queda fuera y actualiza el selector.
  void _gotoDay(DateTime day) {
    setState(() {
      final oldWeek = _weekStartOf(_anchor);
      final newWeek = _weekStartOf(day);
      if (_isWeek && !newWeek.isAtSameMomentAs(oldWeek)) {
        _slideDir = newWeek.isAfter(oldWeek) ? 1 : -1;
      }
      _anchor = day;
      _selected = day;
      _pickerMonth = DateTime(day.year, day.month);
    });
  }

  String _monthTitle() {
    final name = kHsMonths[_anchor.month - 1];
    return '${name[0].toUpperCase()}${name.substring(1)} ${_anchor.year}';
  }

  String _weekTitle() {
    String cap(String m) => '${m[0].toUpperCase()}${m.substring(1)}';
    final start = _weekStartOf(_anchor);
    final end = start.add(const Duration(days: 6));
    if (start.year == end.year && start.month == end.month) {
      return '${start.day} – ${end.day} de ${cap(kHsMonths[start.month - 1])} '
          '${start.year}';
    }
    if (start.year == end.year) {
      return '${start.day} ${cap(kHsMonths[start.month - 1])} – '
          '${end.day} ${cap(kHsMonths[end.month - 1])} ${start.year}';
    }
    return '${hsShortDate(start)} – ${hsShortDate(end)}';
  }

  /// Al tocar un día del MES: se selecciona y, si tiene eventos, abre el
  /// detalle con el modal estándar del panel.
  void _onDayTap(DateTime day) {
    setState(() {
      _selected = day;
      _pickerMonth = DateTime(day.year, day.month);
    });
    final events = _eventsOfDay(day);
    if (events.isNotEmpty) {
      _showDetail(day, events);
    }
  }

  void _showDetail(DateTime day, List<Map<String, dynamic>> agendas) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black45,
      builder: (_) => _AgendaDetailDialog(date: day, agendas: agendas),
    );
  }

  /// Hoja inferior (móvil) con el panel lateral: buscador, mini-calendario y
  /// filtros por servicio, como el panel de Google Calendar.
  void _openPanelSheet() {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: scheme.surfaceContainerLow,
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetCtx).height * .8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Builder(
              builder: (ctx) => _sidePanel(
                scheme,
                onPickDay: () => Navigator.of(ctx).pop(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------
  // Construcción
  // -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PageContainer(
      title: 'Agendas',
      description: 'Eventos agendados por cliente, paquete y servicio, en '
          'vista de semana con horas o vista de mes.',
      icon: Icons.event_available_rounded,
      expand: true,
      stats: [
        StatPill(
            icon: Icons.event_note_outlined, label: '${_all.length} agendas'),
        StatPill(
            icon: Icons.design_services_outlined,
            label: '${_serviceSummary.length} servicios'),
        StatPill(
            icon: Icons.upcoming_outlined, label: '$_upcomingCount próximas'),
      ],
      child: LayoutBuilder(builder: (context, box) {
        final narrow = box.maxWidth < 860;
        // 1 = semana, 0 = mes; sin elegir aún: semana en escritorio, mes angosto.
        final isWeek = _view != null ? _view == 1 : !narrow;
        _isWeek = isWeek;

        final main = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toolbar(context, isWeek: isWeek, narrow: narrow),
            const SizedBox(height: 10),
            Expanded(child: _body(scheme, isWeek)),
          ],
        );

        // Panel lateral fijo en escritorio; en móvil va en una hoja inferior.
        if (narrow || _loading || _error != null || _all.isEmpty) return main;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 248,
              child: FadeSlideIn(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(right: 2),
                  child: _sidePanel(scheme),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: main),
          ],
        );
      }),
    );
  }

  /// Barra superior tipo Google Calendar: Hoy · ‹ › · título del periodo ·
  /// conmutador Semana/Mes (y botón de filtros en móvil).
  Widget _toolbar(BuildContext context,
      {required bool isWeek, required bool narrow}) {
    final scheme = Theme.of(context).colorScheme;
    final title = isWeek ? _weekTitle() : _monthTitle();
    return Row(
      children: [
        OutlinedButton(
          onPressed: _goToToday,
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: .8)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
          child: const Text('Hoy', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: isWeek ? 'Semana anterior' : 'Mes anterior',
          onPressed: () => _shift(-1),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        IconButton(
          tooltip: isWeek ? 'Semana siguiente' : 'Mes siguiente',
          onPressed: () => _shift(1),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: Offset(.08 * _slideDir, 0),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: Text(
              title,
              key: const ValueKey('agenda-title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SegmentedButton<int>(
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          segments: [
            ButtonSegment(
              value: 1,
              icon: const Icon(Icons.view_week_outlined, size: 18),
              label: narrow ? null : const Text('Semana'),
            ),
            ButtonSegment(
              value: 0,
              icon: const Icon(Icons.calendar_month_outlined, size: 18),
              label: narrow ? null : const Text('Mes'),
            ),
          ],
          selected: {isWeek ? 1 : 0},
          onSelectionChanged: (s) => setState(() => _view = s.first),
        ),
        if (narrow) ...[
          const SizedBox(width: 2),
          IconButton(
            tooltip: 'Filtros y calendario',
            onPressed: _openPanelSheet,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ],
    );
  }

  Widget _body(ColorScheme scheme, bool isWeek) {
    if (_loading) return const ListSkeleton(lines: 5);
    if (_error != null) return _errorCard(scheme);
    if (_all.isEmpty) {
      return const EmptyState(
        icon: Icons.event_busy_outlined,
        title: 'Sin agendas',
        message: 'Todavía no hay eventos agendados. Las agendas se crean desde '
            'los paquetes del cliente (botón "Agendas").',
      );
    }
    return Card(
      key: const ValueKey('agenda-calendar'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: isWeek
            ? _WeekCalendar(
                events: _filtered,
                slideDirection: _slideDir,
                anchor: _anchor,
                selected: _selected,
                onSelectDay: (d) => setState(() {
                  _selected = d;
                  _pickerMonth = DateTime(d.year, d.month);
                }),
                onOpenEvent: (a) {
                  final d = _dateOf(a) ?? DateTime.now();
                  _showDetail(d, [a]);
                },
              )
            : _MonthCalendar(
                month: DateTime(_anchor.year, _anchor.month),
                selected: _selected,
                events: _monthEvents,
                slideDirection: _slideDir,
                onSelect: _onDayTap,
              ),
      ),
    );
  }

  Widget _errorCard(ColorScheme scheme) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off_outlined, size: 40, color: scheme.error),
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );

  /// Panel lateral (columna en escritorio, hoja inferior en móvil):
  /// buscador + mini-calendario + "Mis servicios" + próximos eventos.
  Widget _sidePanel(ColorScheme scheme, {VoidCallback? onPickDay}) {
    final services = _serviceSummary;
    final upcoming = _upcoming;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Buscar cliente, paquete…',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    onPressed: () => setState(() => _query = ''),
                    icon: const Icon(Icons.close, size: 18),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        _MiniPicker(
          month: _pickerMonth,
          selected: _selected,
          events: _eventsOfMonth(_pickerMonth),
          onPrev: () =>
              setState(() => _pickerMonth =
                  DateTime(_pickerMonth.year, _pickerMonth.month - 1)),
          onNext: () =>
              setState(() => _pickerMonth =
                  DateTime(_pickerMonth.year, _pickerMonth.month + 1)),
          onPick: (d) {
            onPickDay?.call();
            _gotoDay(d);
          },
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(Icons.palette_outlined, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Mis servicios',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
            ),
            if (_hidden.isNotEmpty)
              TextButton(
                onPressed: () => setState(() => _hidden.clear()),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                ),
                child: const Text('Mostrar todos', style: TextStyle(fontSize: 11.5)),
              ),
          ],
        ),
        if (services.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Sin servicios registrados.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          )
        else
          for (final s in services)
            _ServiceToggle(
              label: s.name,
              count: s.count,
              color: _serviceColorOf(s.id),
              checked: !_hidden.contains(s.key),
              onChanged: () => setState(() {
                if (!_hidden.remove(s.key)) _hidden.add(s.key);
              }),
            ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.upcoming_outlined, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Próximos eventos',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (upcoming.isEmpty)
          Text(
            'Sin eventos próximos por ahora.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          )
        else
          for (var i = 0; i < upcoming.length; i++)
            StaggeredItem(
              index: i,
              child: _EventTile(
                agenda: upcoming[i],
                showDate: true,
                onTap: () {
                  final d = _dateOf(upcoming[i]) ?? DateTime.now();
                  _showDetail(d, [upcoming[i]]);
                },
              ),
            ),
      ],
    );
  }
}

// =====================================================================
// PANEL LATERAL
// =====================================================================

/// Checkbox de servicio con el color del servicio y su contador: el equivalente
/// a "Mis calendarios" de Google Calendar.
class _ServiceToggle extends StatelessWidget {
  const _ServiceToggle({
    required this.label,
    required this.count,
    required this.color,
    required this.checked,
    required this.onChanged,
  });

  final String label;
  final int count;
  final Color color;
  final bool checked;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onChanged,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              onChanged: (_) => onChanged(),
              activeColor: color,
              fillColor: WidgetStatePropertyAll(color),
              side: BorderSide(
                  color: color.withValues(alpha: .65), width: 1.6),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: checked ? FontWeight.w700 : FontWeight.w500,
                  color: checked ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: .7),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: checked ? color : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mini-calendario del panel lateral: mes compacto con ‹ ›, día de HOY con
/// tinte, día seleccionado con círculo de marca y PUNTO de color en los días
/// que tienen eventos (igual que el picker de Google Calendar).
class _MiniPicker extends StatelessWidget {
  const _MiniPicker({
    required this.month,
    required this.selected,
    required this.events,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
  });

  final DateTime month;
  final DateTime? selected;
  final Map<String, _DayEvent> events;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onPick;

  static const List<String> _labels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday - 1;
    final name = kHsMonths[month.month - 1];

    final cells = <Widget>[
      for (var i = 0; i < leading; i++) const Expanded(child: SizedBox()),
      for (var d = 1; d <= daysInMonth; d++)
        Expanded(
          child: _MiniDay(
            date: DateTime(month.year, month.month, d),
            day: d,
            selected:
                selected != null && hsDateKey(selected!) == hsDateKey(DateTime(month.year, month.month, d)),
            today: hsDateKey(DateTime.now()) ==
                hsDateKey(DateTime(month.year, month.month, d)),
            dot: events[hsDateKey(DateTime(month.year, month.month, d))]?.color,
            onTap: () => onPick(DateTime(month.year, month.month, d)),
          ),
        ),
    ];
    while (cells.length % 7 != 0) {
      cells.add(const Expanded(child: SizedBox()));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${name[0].toUpperCase()}${name.substring(1)} ${month.year}',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
            IconButton(
              tooltip: 'Mini mes anterior',
              onPressed: onPrev,
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            IconButton(
              tooltip: 'Mini mes siguiente',
              onPressed: onNext,
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            for (final l in _labels)
              Expanded(
                child: Center(
                  child: Text(
                    l,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .4,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        for (var row = 0; row < cells.length ~/ 7; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++) cells[row * 7 + col],
            ],
          ),
      ],
    );
  }
}

/// Día del mini-calendario.
class _MiniDay extends StatelessWidget {
  const _MiniDay({
    required this.date,
    required this.day,
    required this.selected,
    required this.today,
    required this.dot,
    required this.onTap,
  });

  final DateTime date;
  final int day;
  final bool selected;
  final bool today;
  final Color? dot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? accent
                      : today
                          ? accent.withValues(alpha: .12)
                          : Colors.transparent,
                ),
              ),
              Text(
                '$day',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected
                      ? FontWeight.w800
                      : today
                          ? FontWeight.w700
                          : FontWeight.w500,
                  color: selected
                      ? Colors.white
                      : today
                          ? accent
                          : scheme.onSurface,
                ),
              ),
              if (dot != null && !selected)
                Positioned(
                  bottom: 2.5,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// VISTA DE SEMANA (estilo Google Calendar)
// =====================================================================

/// Evento colocado en la rejilla de horas.
class _Ev {
  _Ev(this.agenda, this.start, this.end);

  final Map<String, dynamic> agenda;

  /// Minutos desde medianoche.
  final int start;
  final int end;

  /// Columna dentro del grupo de solapados y cuántas columnas hay.
  int col = 0;
  int cols = 1;
}

/// Vista SEMANA: encabezados de día (hoy con círculo de marca), fila de
/// eventos de todo el día, rejilla de 24 horas con scroll (inicia cerca de la
/// primera hora con eventos o de "ahora") y línea roja de hora actual.
/// En pantallas angostas la semana se desplaza en horizontal.
class _WeekCalendar extends StatefulWidget {
  const _WeekCalendar({
    required this.events,
    required this.slideDirection,
    required this.anchor,
    required this.selected,
    required this.onSelectDay,
    required this.onOpenEvent,
  });

  final List<Map<String, dynamic>> events;
  final int slideDirection;

  /// Día de referencia del periodo visible: la semana mostrada se deriva de
  /// AQUÍ (no del día seleccionado), para que ‹ › y "Hoy" naveguen de verdad.
  final DateTime anchor;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<Map<String, dynamic>> onOpenEvent;

  @override
  State<_WeekCalendar> createState() => _WeekCalendarState();
}

class _WeekCalendarState extends State<_WeekCalendar> {
  static const double _hourH = 46;
  static const List<String> _weekLabels = [
    'LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB', 'DOM',
  ];

  /// Hora inicial del scroll: "ahora" (menos una) si la semana contiene hoy,
  /// si no la primera hora con eventos, o 7:00.
  double get _initialHour {
    final now = DateTime.now();
    final days = _weekDays;
    final showsToday =
        days.any((d) => hsDateKey(d) == hsDateKey(now));
    int hour;
    if (showsToday) {
      hour = now.hour - 1;
    } else {
      int? minHour;
      for (final a in widget.events) {
        final d = hsParseDate(a['eventDate']);
        if (d == null || !_isTimed(d)) continue;
        if (!days.any((x) => hsDateKey(x) == hsDateKey(d))) continue;
        if (minHour == null || d.hour < minHour) minHour = d.hour;
      }
      hour = (minHour ?? 7) - 1;
    }
    return hour.clamp(0, 22).toDouble();
  }

  late final ScrollController _scroll =
      ScrollController(initialScrollOffset: _initialHour * _hourH);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<DateTime> get _weekDays {
    final start = _weekStartOf(widget.anchor);
    return [for (var i = 0; i < 7; i++) start.add(Duration(days: i))];
  }

  List<Map<String, dynamic>> _eventsOf(DateTime day, {required bool timed}) {
    final key = hsDateKey(day);
    final out = <Map<String, dynamic>>[];
    for (final a in widget.events) {
      final d = hsParseDate(a['eventDate']);
      if (d == null || hsDateKey(d) != key || _isTimed(d) != timed) continue;
      out.add(a);
    }
    out.sort((a, b) => '${a['eventDate']}'.compareTo('${b['eventDate']}'));
    return out;
  }

  /// Coloca los eventos de un día en columnas (los solapados van lado a lado).
  List<_Ev> _place(List<Map<String, dynamic>> timed) {
    final items = <_Ev>[];
    for (final a in timed) {
      final d = hsParseDate(a['eventDate'])!;
      final start = d.hour * 60 + d.minute;
      items.add(_Ev(a, start, math.min(start + 60, 24 * 60)));
    }
    items.sort((a, b) => a.start != b.start
        ? a.start.compareTo(b.start)
        : b.end.compareTo(a.end));

    final out = <_Ev>[];
    var cluster = <_Ev>[];
    var clusterEnd = 0;
    void flush() {
      if (cluster.isEmpty) return;
      final colEnds = <int>[];
      for (final it in cluster) {
        var placed = false;
        for (var c = 0; c < colEnds.length; c++) {
          if (colEnds[c] <= it.start) {
            it.col = c;
            colEnds[c] = it.end;
            placed = true;
            break;
          }
        }
        if (!placed) {
          it.col = colEnds.length;
          colEnds.add(it.end);
        }
      }
      for (final it in cluster) {
        it.cols = colEnds.length;
        out.add(it);
      }
      cluster = [];
      clusterEnd = 0;
    }

    for (final it in items) {
      if (cluster.isNotEmpty && it.start >= clusterEnd) flush();
      cluster.add(it);
      clusterEnd = math.max(clusterEnd, it.end);
    }
    flush();
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = _weekDays;
    final todayKey = hsDateKey(DateTime.now());
    final selectedKey =
        widget.selected == null ? null : hsDateKey(widget.selected!);

    return LayoutBuilder(builder: (context, box) {
      final gutter = box.maxWidth < 420 ? 36.0 : 44.0;
      final dayW = math.max((box.maxWidth - gutter) / 7, 74.0);
      final totalW = gutter + dayW * 7;

      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Encabezados de día (LUN 19 …; hoy con círculo de marca).
          SizedBox(
            height: 52,
            child: Row(
              children: [
                SizedBox(width: gutter),
                for (final day in days)
                  SizedBox(
                    width: dayW,
                    child: _DayHead(
                      label: _weekLabels[day.weekday - 1],
                      day: day,
                      today: hsDateKey(day) == todayKey,
                      selected: selectedKey == hsDateKey(day),
                      onTap: () => widget.onSelectDay(day),
                    ),
                  ),
              ],
            ),
          ),
          // Eventos de todo el día (agendas sin hora).
          SizedBox(
            height: 30,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: gutter),
                for (final day in days)
                  SizedBox(
                    width: dayW,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(3, 3, 3, 0),
                      child: _AllDayPills(
                        events: _eventsOf(day, timed: false),
                        maxWidth: dayW - 10,
                        onOpen: widget.onOpenEvent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: scheme.outlineVariant.withValues(alpha: .6),
          ),
          // Rejilla de horas con scroll vertical.
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              child: SizedBox(
                height: 24 * _hourH,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TimeGutter(width: gutter, hourHeight: _hourH),
                    for (final day in days)
                      SizedBox(
                        width: dayW,
                        child: _DayColumn(
                          day: day,
                          hourHeight: _hourH,
                          events: _place(_eventsOf(day, timed: true)),
                          now: DateTime.now(),
                          onOpenEvent: widget.onOpenEvent,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );

      // En pantallas angostas la semana se desplaza en horizontal.
      final body = totalW <= box.maxWidth
          ? content
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: totalW, child: content),
            );

      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(.10 * widget.slideDirection, 0),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        layoutBuilder: (current, previous) => Stack(
          children: [...previous, ?current],
        ),
        child: KeyedSubtree(
          key: ValueKey('week-${hsDateKey(days.first)}'),
          child: body,
        ),
      );
    });
  }
}

/// Encabezado de un día: "LUN" + número, con HOY en círculo de marca y el día
/// seleccionado con tinte. Al tocarlo se selecciona el día.
class _DayHead extends StatelessWidget {
  const _DayHead({
    required this.label,
    required this.day,
    required this.today,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final DateTime day;
  final bool today;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: .7,
              color: today ? accent : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: today
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accent,
                        Color.lerp(accent, Colors.black, .18) ?? accent,
                      ],
                    )
                  : null,
              color: today
                  ? null
                  : selected
                      ? accent.withValues(alpha: .13)
                      : Colors.transparent,
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: today || selected ? FontWeight.w800 : FontWeight.w600,
                color: today
                    ? Colors.white
                    : selected
                        ? accent
                        : scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Píldoras de eventos "todo el día" (agendas sin hora) en la fila superior.
class _AllDayPills extends StatelessWidget {
  const _AllDayPills({
    required this.events,
    required this.maxWidth,
    required this.onOpen,
  });

  final List<Map<String, dynamic>> events;
  final double maxWidth;
  final ValueChanged<Map<String, dynamic>> onOpen;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        for (final a in events.take(3))
          Builder(builder: (context) {
            final color = _serviceColorOf((a['serviceId'] as num?)?.toInt());
            final client = (a['clientName'] ?? '').toString().trim();
            final fg = Color.lerp(color, scheme.onSurface, .30)!;
            return GestureDetector(
              onTap: () => onOpen(a),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(6),
                    border:
                        Border.all(color: color.withValues(alpha: .45)),
                  ),
                  child: Text(
                    client.isEmpty ? 'Evento' : client,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ),
              ),
            );
          }),
        if (events.length > 3)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              '+${events.length - 3}',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// Columna de horas de la izquierda ("00:00", "01:00"…).
class _TimeGutter extends StatelessWidget {
  const _TimeGutter({required this.width, required this.hourHeight});

  final double width;
  final double hourHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Column(
        children: [
          for (var h = 0; h < 24; h++)
            SizedBox(
              height: hourHeight,
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    hsTimeLabel(DateTime(2000, 1, 1, h)),
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Columna de un día en la rejilla: líneas de hora, fondo tenue si es hoy,
/// bloques de eventos colocados por hora y la línea roja de "ahora".
class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.hourHeight,
    required this.events,
    required this.now,
    required this.onOpenEvent,
  });

  final DateTime day;
  final double hourHeight;
  final List<_Ev> events;
  final DateTime now;
  final ValueChanged<Map<String, dynamic>> onOpenEvent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = scheme.outlineVariant.withValues(alpha: .5);
    final isToday = hsDateKey(day) == hsDateKey(now);

    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return Stack(
        children: [
          // Líneas horizontales por hora.
          Positioned.fill(
            child: Column(
              children: [
                for (var h = 0; h < 24; h++)
                  Container(
                    height: hourHeight,
                    decoration: BoxDecoration(
                      border: h == 0
                          ? null
                          : Border(top: BorderSide(color: line, width: 1)),
                    ),
                  ),
              ],
            ),
          ),
          if (isToday)
            Positioned.fill(
              child: Container(color: scheme.primary.withValues(alpha: .04)),
            ),
          for (final ev in events) _block(ev, w),
          if (isToday) _nowLine(),
        ],
      );
    });
  }

  Widget _block(_Ev ev, double width) {
    final color = _serviceColorOf((ev.agenda['serviceId'] as num?)?.toInt());
    final client = (ev.agenda['clientName'] ?? '').toString().trim();
    final service = (ev.agenda['serviceName'] ?? '').toString().trim();
    final package = (ev.agenda['packageName'] ?? '').toString().trim();
    final startLabel = hsParseDate(ev.agenda['eventDate']);
    final slotW = width / ev.cols;
    final height = math.max((ev.end - ev.start) / 60 * hourHeight - 3, 22.0);

    return Positioned(
      left: ev.col * slotW + 2,
      width: slotW - 4,
      top: ev.start / 60 * hourHeight + 1,
      height: height,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: .5, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(scale: t, child: child),
        ),
        child: Tooltip(
          message: [
            if (service.isNotEmpty) service,
            if (package.isNotEmpty) package,
          ].join(' · '),
          child: InkWell(
            onTap: () => onOpenEvent(ev.agenda),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color,
                    Color.lerp(color, Colors.black, .18) ?? color,
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: .28),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    client.isEmpty ? 'Evento' : client,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.15,
                    ),
                  ),
                  if (height >= 38 && startLabel != null)
                    Text(
                      hsTimeLabel(startLabel),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: .92),
                        height: 1.25,
                      ),
                    ),
                  if (height >= 60 && service.isNotEmpty)
                    Text(
                      service,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: .85),
                        height: 1.25,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Línea roja de "ahora" (punto a la izquierda de la columna de hoy).
  Widget _nowLine() {
    final top = (now.hour * 60 + now.minute) / 60 * hourHeight;
    return Positioned(
      left: 0,
      right: 0,
      top: top - 1,
      height: 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFEA4335),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          Positioned(
            left: -4,
            top: -3,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFFEA4335),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// VISTA DE MES
// =====================================================================

/// Calendario mensual ADAPTATIVO (sin barra de navegación: la barra superior
/// de la página maneja Hoy/flechas/título): LLENA el alto disponible sin
/// excederlo nunca; si la pantalla es muy baja, hace scroll. Celdas circulares
/// animadas + badge de color e ICONO del servicio en los días con eventos.
class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.selected,
    required this.events,
    required this.slideDirection,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime? selected;

  /// Días del mes visible con eventos: color, icono del servicio y cuántos.
  final Map<String, _DayEvent> events;

  /// 1 = mes siguiente, -1 = mes anterior (dirección de la animación).
  final int slideDirection;
  final ValueChanged<DateTime> onSelect;

  static const List<String> _weekLabels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
  static const double _weekH = 22;
  static const double _gap = 8;
  static const double _minRow = 34;

  /// Tamaño máximo del círculo del día (en pantallas grandes no se estira más).
  static const double _maxCircle = 62;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday - 1; // lunes = 0
    final todayKey = hsDateKey(DateTime.now());

    final cells = <Widget>[];
    for (var i = 0; i < leading; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final date = DateTime(month.year, month.month, d);
      final key = hsDateKey(date);
      cells.add(StaggeredItem(
        index: cells.length,
        child: _DayCell(
          key: ValueKey('day-$key'),
          day: d,
          selected: selected != null && hsDateKey(selected!) == key,
          today: key == todayKey,
          event: events[key],
          onTap: () => onSelect(date),
        ),
      ));
    }
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox.shrink());
    }
    final rows = cells.length ~/ 7;

    /// Cuadrícula del mes. `fill = true` reparte las filas en TODO el alto
    /// disponible (pantalla completa); `false` usa filas de alto mínimo.
    Widget grid({required bool fill}) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          for (var row = 0; row < rows; row++)
            if (fill)
              Expanded(
                child: Row(
                  children: [
                    for (var col = 0; col < 7; col++)
                      Expanded(child: cells[row * 7 + col]),
                  ],
                ),
              )
            else
              SizedBox(
                height: _minRow,
                child: Row(
                  children: [
                    for (var col = 0; col < 7; col++)
                      Expanded(child: cells[row * 7 + col]),
                  ],
                ),
              ),
        ],
      );
    }

    final head = SizedBox(
      height: _weekH,
      child: Row(
        children: [
          for (final w in _weekLabels)
            Expanded(
              child: Center(
                child: Text(
                  w,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return LayoutBuilder(builder: (context, box) {
      final avail = box.maxHeight;
      final freeHeight = avail.isFinite ? avail - _weekH - _gap : 0.0;
      final fits = rows > 0 && freeHeight >= _minRow * rows;

      // Animación de cambio de mes: el mes entrante entra desde el lado hacia
      // el que se navegó, con fade suave.
      final gridWidget = AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0.14 * slideDirection, 0),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, ?current],
        ),
        child: KeyedSubtree(
          key: ValueKey('month-${month.year}-${month.month}'),
          child: fits
              ? SizedBox(height: freeHeight, child: grid(fill: true))
              : grid(fill: false),
        ),
      );

      final body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [head, gridWidget],
      );
      if (fits) return body;
      return SingleChildScrollView(child: body);
    });
  }
}

/// Celda del día: círculo con el número y, si hay eventos, un badge con el
/// COLOR y el ICONO del servicio (degradado, sombra y entrada animada) para que
/// se vea de un vistazo QUÉ hay agendado. Con realce al pasar el mouse y
/// transiciones suaves.
class _DayCell extends StatefulWidget {
  const _DayCell({
    super.key,
    required this.day,
    required this.selected,
    required this.today,
    required this.event,
    required this.onTap,
  });

  final int day;
  final bool selected;
  final bool today;

  /// Eventos del día (null = sin eventos): color, icono y cuántos hay.
  final _DayEvent? event;
  final VoidCallback onTap;

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    final e = widget.event;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: LayoutBuilder(builder: (context, box) {
            // El círculo se adapta al espacio de la celda (nunca desborda).
            final double availH = box.maxHeight - 8;
            final double availW = box.maxWidth - 6;
            final double cap = math.min(availW, _MonthCalendar._maxCircle);
            final double size =
                math.min(math.max(availH, 20.0), math.max(cap, 20.0));
            final double badge = math.min(math.max(size * 0.38, 14.0), 21.0);

            final Color fg;
            final Color border;
            final Gradient? gradient;
            final Color tint;
            if (widget.selected) {
              gradient = LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent,
                  Color.lerp(accent, Colors.black, .28) ?? accent,
                ],
              );
              fg = Colors.white;
              border = accent;
              tint = Colors.transparent;
            } else if (e != null) {
              gradient = null;
              fg = e.color;
              border = e.color.withValues(alpha: _hover ? .85 : .45);
              tint = e.color.withValues(alpha: _hover ? .22 : .10);
            } else {
              gradient = null;
              fg = scheme.onSurface;
              border = widget.today
                  ? accent.withValues(alpha: .55)
                  : Colors.transparent;
              tint = _hover
                  ? scheme.surfaceContainerHighest.withValues(alpha: .9)
                  : Colors.transparent;
            }

            return SizedBox(
              width: size,
              height: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedScale(
                    duration: const Duration(milliseconds: 170),
                    curve: Curves.easeOut,
                    scale: widget.selected ? 1 : (_hover ? 1.04 : .97),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 170),
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        color: gradient == null ? tint : null,
                        gradient: gradient,
                        shape: BoxShape.circle,
                        border: Border.all(color: border, width: 1.4),
                        boxShadow: widget.selected
                            ? [
                                BoxShadow(
                                  color: accent.withValues(alpha: .35),
                                  blurRadius: 9,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${widget.day}',
                        style: TextStyle(
                          fontSize: math.min(math.max(size * 0.36, 11.0), 15.0),
                          fontWeight: widget.selected || e != null
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: fg,
                        ),
                      ),
                    ),
                  ),
                  if (e != null)
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: .55, end: 1),
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutBack,
                        builder: (context, t, child) => Opacity(
                          opacity: t.clamp(0.0, 1.0),
                          child: Transform.scale(scale: t, child: child),
                        ),
                        child: Container(
                          width: badge,
                          height: badge,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                e.color,
                                Color.lerp(e.color, Colors.white, .38) ??
                                    e.color,
                              ],
                            ),
                            border:
                                Border.all(color: scheme.surface, width: 1.6),
                            boxShadow: [
                              BoxShadow(
                                color: e.color.withValues(alpha: .45),
                                blurRadius: 5,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Icon(e.icon, size: badge * .62, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

// =====================================================================
// TARJETA DE EVENTO (panel lateral) Y DETALLE
// =====================================================================

/// Tarjeta compacta de evento para el panel lateral ("Próximos eventos").
class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.agenda,
    required this.onTap,
    this.showDate = false,
  });

  final Map<String, dynamic> agenda;
  final VoidCallback onTap;

  /// true = muestra día/mes (próximos); false = hora (del día elegido).
  final bool showDate;

  static String initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = hsParseDate(agenda['eventDate']);
    final color = _serviceColorOf((agenda['serviceId'] as num?)?.toInt());
    final client = (agenda['clientName'] ?? '').toString().trim();
    final package = (agenda['packageName'] ?? '').toString().trim();
    final service = (agenda['serviceName'] ?? '').toString().trim();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .30)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: color.withValues(alpha: .14),
              child: Text(
                initials(client),
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    client.isEmpty ? 'Sin cliente' : client,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (service.isNotEmpty) service,
                      if (package.isNotEmpty) package,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  date == null
                      ? '--'
                      : (showDate ? hsShortDate(date) : hsTimeLabel(date)),
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 12.5, color: color),
                ),
                if (showDate && date != null)
                  Text(
                    hsTimeLabel(date),
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal de detalle con el DISEÑO ESTÁNDAR del panel (FormDialog): cabecera
/// con icono, título y botón de cerrar ARRIBA A LA DERECHA.
class _AgendaDetailDialog extends StatelessWidget {
  const _AgendaDetailDialog({required this.date, required this.agendas});

  final DateTime date;
  final List<Map<String, dynamic>> agendas;

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      icon: Icons.event_note_outlined,
      title:
          agendas.length == 1 ? 'Detalle de la agenda' : 'Agendas del día',
      subtitle: hsDateLabel(date),
      maxWidth: 480,
      onCancel: () => Navigator.of(context).pop(),
      onSave: () => Navigator.of(context).pop(),
      saveLabel: 'Listo',
      children: [
        for (var i = 0; i < agendas.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _AgendaDetailBlock(agenda: agendas[i]),
        ],
      ],
    );
  }
}

/// Bloque de detalle (cliente, paquete, servicio, hora y nota).
class _AgendaDetailBlock extends StatelessWidget {
  const _AgendaDetailBlock({required this.agenda});

  final Map<String, dynamic> agenda;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = hsParseDate(agenda['eventDate']);
    final color = _serviceColorOf((agenda['serviceId'] as num?)?.toInt());
    final client = (agenda['clientName'] ?? '').toString().trim();
    final package = (agenda['packageName'] ?? '').toString().trim();
    final service = (agenda['serviceName'] ?? '').toString().trim();
    final desc = (agenda['description'] ?? '').toString().trim();

    Widget detailRow(IconData icon, String label, String value,
        {Color? tint}) {
      return Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: tint ?? scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              '$label ',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: tint ?? scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: color.withValues(alpha: .16),
                child: Text(
                  _EventTile.initials(client),
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w800, fontSize: 11.5),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  client.isEmpty ? 'Sin cliente asignado' : client,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  date == null ? '--' : hsTimeLabel(date),
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: color),
                ),
              ),
            ],
          ),
          detailRow(Icons.inventory_2_outlined, 'Paquete',
              package.isEmpty ? '—' : package),
          detailRow(Icons.design_services_outlined, 'Servicio',
              service.isEmpty ? 'Sin servicio específico' : service,
              tint: color),
          if (desc.isNotEmpty) detailRow(Icons.notes_outlined, 'Nota', desc),
        ],
      ),
    );
  }
}

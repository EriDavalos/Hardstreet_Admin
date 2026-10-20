import 'package:flutter/material.dart';

import '../reminders_service.dart';
import '../theme.dart' show AppColors;

/// Campanita de la top bar: muestra el conteo de avisos SIN LEER como badge.
/// Al tocarla abre (y al tocar de nuevo cierra) un PANEL FIJO anclado
/// debajo de la campanita —igual que la franja de "Próximos eventos" de
/// Agendas— en vez de un diálogo modal que tapa toda la pantalla.
///
/// Se suscribe a [RemindersService.instance] y se repinta sola.
class RemindersBell extends StatefulWidget {
  const RemindersBell({super.key});

  @override
  State<RemindersBell> createState() => _RemindersBellState();
}

class _RemindersBellState extends State<RemindersBell> {
  OverlayEntry? _entry;

  bool get _open => _entry != null;

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  void _toggle() {
    if (_open) {
      _close();
    } else {
      _show();
    }
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  void _show() {
    // Al abrir, refresca por si hay avisos nuevos desde el último polling.
    RemindersService.instance.refresh();
    final entry = OverlayEntry(
      // PANEL FIJO: anclado bajo la top bar, esquina derecha (junto a la
      // campanita), sin tapar el contenido de la pantalla.
      builder: (_) => _BellOverlay(
        onDismiss: _close,
        child: _RemindersPanel(onClose: _close),
      ),
    );
    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final service = RemindersService.instance;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final unread = service.unread;
        return IconButton(
          tooltip: _open
              ? 'Cerrar avisos'
              : unread > 0
              ? 'Avisos ($unread sin leer)'
              : 'Avisos de eventos',
          isSelected: _open,
          onPressed: _toggle,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                _open || unread > 0
                    ? Icons.notifications
                    : Icons.notifications_outlined,
              ),
              if (unread > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        width: 1.5,
                      ),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      unread > 9 ? '9+' : '$unread',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Capa del panel: bloquea los taps de FUERA (barrier transparente) para
/// cerrarlo, sin cubrir el panel mismo.
class _BellOverlay extends StatelessWidget {
  const _BellOverlay({required this.onDismiss, required this.child});

  final VoidCallback onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: const SizedBox.expand(),
          ),
        ),
        // Anclado bajo la top bar (60 px) a la derecha, con margen.
        Positioned(top: 66, right: 12, child: child),
      ],
    );
  }
}

/// Panel FIJO de avisos: se expande/plega bajo la campanita con la misma
/// anatomía que los demás paneles del panel (cabecera + lista scrollable).
class _RemindersPanel extends StatelessWidget {
  const _RemindersPanel({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final service = RemindersService.instance;
    final scheme = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context);
    return Material(
      elevation: 14,
      shadowColor: Colors.black.withValues(alpha: .35),
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 380,
          maxHeight: (screen.height * .62).clamp(240.0, 520.0),
        ),
        child: AnimatedBuilder(
          animation: service,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PanelHeader(service: service, onClose: onClose),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                  child: _buildList(context, service),
                ),
              ),
              // Pie: deja claro que se actualiza solo (no hay que recargar).
              Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: .45),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.bolt_rounded, size: 14, color: scheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Se actualiza en tiempo real mientras el panel está abierto',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, RemindersService service) {
    final list = service.reminders;
    if (list.isEmpty) {
      final scheme = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                size: 26,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'No hay avisos por ahora',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 3),
            Text(
              'Aquí llegan los eventos que se acercan (una semana y un día '
              'antes) y los envíos a impresión de los clientes.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) =>
          _ReminderTile(reminder: list[i], service: service),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.service, required this.onClose});

  final RemindersService service;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = service.reminders.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: .12),
            scheme.primary.withValues(alpha: .02),
          ],
        ),
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .45),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              service.unread > 0
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_rounded,
              size: 20,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Avisos de eventos',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                Text(
                  service.unread > 0
                      ? '${service.unread} sin leer · $total en total'
                      : total > 0
                      ? 'Todo leído · $total avisos'
                      : 'Sin avisos por ahora',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (service.unread > 0)
            TextButton.icon(
              // markAllRead() solo dispara la confirmación con el servidor
              // (fire-and-forget): el estado local ya quedó actualizado de
              // forma síncrona, así el botón se repinta al instante.
              onPressed: service.markAllRead,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(Icons.done_all_rounded, size: 15),
              label: const Text('Marcar leídos'),
            ),
          IconButton(
            tooltip: 'Cerrar',
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({required this.reminder, required this.service});

  final Map<String, dynamic> reminder;
  final RemindersService service;

  int? get _id => reminder['id'] is int
      ? reminder['id'] as int
      : int.tryParse('${reminder['id']}');

  bool get _unread => (reminder['isRead'] == 0 || reminder['isRead'] == false);

  String get _title => '${reminder['title'] ?? 'Aviso de evento'}';

  String get _body => '${reminder['body'] ?? ''}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Clave por ID de aviso: permite verificar SU estado en pruebas sin
    // depender de los textos ("leído" vs "no leído") del icono.
    // Cuándo: el aviso trae `kind` ('7d' = falta una semana, '1d' = mañana)
    // y la fecha del evento.
    final kind = (reminder['kind'] ?? '').toString();
    // `source` = 'event' (agenda) o 'print' (un cliente envió fotos a
    // impresión). Los dos llegan en la misma lista, pero se leen en tablas
    // distintas, así que el origen viaja con el aviso.
    final source = (reminder['source'] ?? 'event').toString();
    final isPrint = source == 'print';
    final kindLabel = isPrint
        ? 'Impresión'
        : kind == '1d'
        ? 'Mañana'
        : kind == '7d'
        ? 'Falta 1 semana'
        : 'Próximo evento';
    final eventDate = DateTime.tryParse(
      '${reminder['eventDate'] ?? reminder['created'] ?? ''}',
    );

    return Material(
      key: ValueKey('reminder-$source-${reminder['id']}'),
      color: _unread
          ? scheme.primary.withValues(alpha: .07)
          : scheme.surfaceContainerHighest.withValues(alpha: .28),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          final id = _id;
          if (id != null) service.markRead(id, source: source);
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _unread
                  ? scheme.primary.withValues(alpha: .28)
                  : scheme.outlineVariant.withValues(alpha: .40),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pastilla con el icono del aviso (y el estado de leído).
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _unread
                          ? scheme.primary.withValues(alpha: .14)
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isPrint
                          ? Icons.print_outlined
                          : kind == '1d'
                          ? Icons.event_available_rounded
                          : Icons.event_note_rounded,
                      size: 17,
                      color: _unread ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                  Positioned(
                    right: -3,
                    bottom: -3,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _unread ? Icons.circle : Icons.check_circle_outline,
                        size: 12,
                        color: _unread ? scheme.primary : scheme.outlineVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: _unread
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              fontSize: 13,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isPrint
                                ? AppColors.brand.withValues(alpha: .14)
                                : kind == '1d'
                                ? const Color(0xFFF59E0B).withValues(alpha: .15)
                                : scheme.primary.withValues(alpha: .10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            kindLabel,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: isPrint
                                  ? AppColors.brand
                                  : kind == '1d'
                                  ? const Color(0xFFB45309)
                                  : scheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        _body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.3,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (eventDate != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _whenLabel(eventDate),
                            style: TextStyle(
                              fontSize: 10.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];

  /// "12 oct · 18:30" (o solo la fecha si no tiene hora).
  String _whenLabel(DateTime d) {
    final hora = d.hour == 0 && d.minute == 0
        ? ''
        : ' · ${d.hour.toString().padLeft(2, '0')}:'
              '${d.minute.toString().padLeft(2, '0')}';
    return '${d.day} ${_months[d.month - 1]}$hora';
  }
}

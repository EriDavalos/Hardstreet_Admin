import 'package:flutter/material.dart';

import '../reminders_service.dart';

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
                          horizontal: 4, vertical: 1),
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
        Positioned(
          top: 66,
          right: 12,
          child: child,
        ),
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
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: .30),
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 360,
          maxHeight: (screen.height * .55).clamp(220.0, 480.0),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: AnimatedBuilder(
            animation: service,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PanelHeader(service: service, onClose: onClose),
                const SizedBox(height: 6),
                Flexible(child: _buildList(context, service)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, RemindersService service) {
    final list = service.reminders;
    if (list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'No hay avisos de eventos próximos',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0),
      child: Row(
        children: [
          Icon(Icons.notifications, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Avisos de eventos',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          if (service.unread > 0)
            TextButton(
              // markAllRead() solo dispara la confirmación con el servidor
              // (fire-and-forget): el estado local ya quedó actualizado de
              // forma síncrona, así el botón se repinta al instante.
              onPressed: service.markAllRead,
              child: const Text('Marcar leídos'),
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
    return InkWell(
      key: ValueKey('reminder-${reminder['id']}'),
      onTap: () {
        final id = _id;
        if (id != null) service.markRead(id);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _unread ? Icons.circle : Icons.check_circle_outline,
              size: 16,
              color: _unread ? scheme.primary : scheme.outlineVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    style: TextStyle(
                      fontWeight: _unread ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13.5,
                    ),
                  ),
                  if (_body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      _body,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

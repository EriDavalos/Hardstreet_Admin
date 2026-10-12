import 'package:flutter/material.dart';

import '../reminders_service.dart';

/// Campanita de la top bar: muestra el conteo de avisos SIN LEER como badge.
/// Al tocarla abre un panel con los avisos de eventos próximos (falta una
/// semana / falta un día) y permite marcarlos como leídos.
///
/// Se suscribe a [RemindersService.instance] y se repinta sola.
class RemindersBell extends StatelessWidget {
  const RemindersBell({super.key});

  @override
  Widget build(BuildContext context) {
    final service = RemindersService.instance;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final unread = service.unread;
        return IconButton(
          tooltip: unread > 0
              ? 'Avisos ($unread sin leer)'
              : 'Avisos de eventos',
          onPressed: () => _showPanel(context),
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                unread > 0
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

  void _showPanel(BuildContext context) {
    // Al abrir, refresca por si hay avisos nuevos desde el último polling.
    RemindersService.instance.refresh();
    showDialog<void>(
      context: context,
      builder: (_) => const _RemindersDialog(),
    );
  }
}

class _RemindersDialog extends StatelessWidget {
  const _RemindersDialog();

  @override
  Widget build(BuildContext context) {
    final service = RemindersService.instance;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
        child: Padding(
          padding: const EdgeInsets.all(16),
          // UN solo listener para TODO el diálogo: si solo la lista escuchaba
          // al servicio, el header (con "Marcar leídos") se quedaba obsoleto
          // tras marcar todo: el botón no desaparecía con 0 sin leer.
          child: AnimatedBuilder(
            animation: service,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PanelHeader(service: service),
                const SizedBox(height: 8),
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
  const _PanelHeader({required this.service});

  final RemindersService service;

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
            onPressed: () => Navigator.of(context).maybePop(),
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

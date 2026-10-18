import 'package:flutter/material.dart';

import '../reminders_service.dart';

// ==================================================================
// HARD STREET ADMIN — Widget de NOTIFICACIONES
// ==================================================================
// Un vistazo a los avisos de eventos sin abrir la campanita: los últimos
// avisos con su estado (leído / sin leer) y el conteo arriba. Vive en el
// Dashboard y se repinta solo cuando [RemindersService] recibe algo nuevo.
//
// Tocar un aviso lo marca leído (igual que en la campanita) y el pie dice
// cuándo se actualizó, para que no se dude si está al día.
// ==================================================================

/// Panel listo para el Dashboard: tarjeta con su encabezado, o NADA si no
/// hay avisos (así el tablero no gasta alto cuando no hay nada que avisar).
class NotificationsPanel extends StatelessWidget {
  const NotificationsPanel({super.key, this.compact = false, this.limit = 3});

  final bool compact;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: RemindersService.instance,
      builder: (context, _) {
        if (RemindersService.instance.reminders.isEmpty) {
          return const SizedBox.shrink();
        }
        return Card(
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, compact ? 8 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.notifications_none_rounded,
                      size: 15,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'NOTIFICACIONES',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                NotificationsCard(limit: limit, compact: compact),
              ],
            ),
          ),
        );
      },
    );
  }
}

class NotificationsCard extends StatelessWidget {
  const NotificationsCard({super.key, this.limit = 3, this.compact = false});

  /// Cuántos avisos se enseñan (el resto queda en la campanita).
  final int limit;

  /// Versión densa para las columnas del tablero de escritorio.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final service = RemindersService.instance;

    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final all = service.reminders;
        // Primero los NO leídos: son los que importan al entrar al panel.
        final sorted = [...all]
          ..sort((a, b) {
            final ua = (a['isRead'] == 0) ? 0 : 1;
            final ub = (b['isRead'] == 0) ? 0 : 1;
            return ua.compareTo(ub);
          });
        final rows = sorted.take(limit).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: compact ? 26 : 32,
                  height: compact ? 26 : 32,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    service.unread > 0
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                    size: compact ? 15 : 18,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    service.unread > 0
                        ? '${service.unread} sin leer'
                        : 'Todo al día',
                    style: TextStyle(
                      fontSize: compact ? 11 : 12,
                      fontWeight: FontWeight.w700,
                      color: service.unread > 0
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (service.unread > 0)
                  TextButton(
                    onPressed: service.markAllRead,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 28),
                      textStyle: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('Leer todo'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (rows.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: compact ? 12 : 18),
                child: Column(
                  children: [
                    Icon(
                      Icons.mark_email_read_outlined,
                      size: 22,
                      color: scheme.onSurfaceVariant.withValues(alpha: .6),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sin avisos de eventos',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else
              for (final r in rows) _row(context, service, r),
            if (all.length > rows.length)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '+${all.length - rows.length} más en la campanita',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _row(
    BuildContext context,
    RemindersService service,
    Map<String, dynamic> r,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final unread = r['isRead'] == 0;
    final kind = (r['kind'] ?? '').toString();
    final id = r['id'] is int ? r['id'] as int : int.tryParse('${r['id']}');

    return InkWell(
      key: ValueKey('notif-card-${r['id']}'),
      borderRadius: BorderRadius.circular(10),
      onTap: id == null ? null : () => service.markRead(id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        child: Row(
          children: [
            Icon(
              unread ? Icons.circle : Icons.check_circle_outline,
              size: compact ? 9 : 11,
              color: unread ? scheme.primary : scheme.outlineVariant,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                '${r['title'] ?? 'Aviso de evento'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 11.5 : 12.5,
                  fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: kind == '1d'
                    ? const Color(0xFFF59E0B).withValues(alpha: .16)
                    : scheme.primary.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                kind == '1d'
                    ? 'Mañana'
                    : kind == '7d'
                    ? '1 semana'
                    : 'Aviso',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: kind == '1d'
                      ? const Color(0xFFB45309)
                      : scheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

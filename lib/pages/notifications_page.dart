import 'package:flutter/material.dart';

import '../hs_access.dart';
import '../hs_api.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/common.dart';
import '../widgets/hs_modal.dart';
import '../widgets/hs_toast.dart';

// ==================================================================
// MÓDULO NOTIFICACIONES
// ==================================================================
// Aquí se decide QUIÉN recibe cada aviso del sistema y se mandan avisos
// manuales a los roles elegidos:
//
//   * «Avisar a fechas próximas a agenda»            Cliente y Colaboradores
//   * «Avisar cuando se puedan seleccionar las fotos» Cliente
//   * «Avisar el envío de fotos seleccionadas»        Colaboradores
//   * …y los demás eventos del catálogo del backend.
//
// Cada aviso guarda el MÓDULO al que lleva (`target`): al tocar la
// notificación en la campanita, el panel abre ESA pantalla (Impresiones,
// Mi paquete, Agendas…). El historial muestra lo que ya se envió.
//
// Backend: /api/admin/notifications (permiso sobre el módulo
// «Notificaciones»; el rol Admin y el Superadmin pasan siempre).
// ==================================================================

/// Icono de cada evento (los que manda el backend + respaldo).
IconData _eventIcon(String key) {
  switch (key) {
    case 'agenda-proxima':
      return Icons.event_note_rounded;
    case 'fotos-disponibles':
      return Icons.photo_library_outlined;
    case 'fotos-enviadas':
      return Icons.print_outlined;
    case 'servicio-terminado':
      return Icons.task_alt_rounded;
    case 'paquete-terminado':
      return Icons.inventory_2_outlined;
    case 'impresion-terminada':
      return Icons.local_printshop_outlined;
    case 'aviso-manual':
      return Icons.campaign_outlined;
    default:
      return Icons.notifications_none_rounded;
  }
}

/// Nombre visible del módulo al que lleva un aviso.
const Map<String, String> _targetLabels = {
  'notifications': 'Notificaciones',
  'schedules': 'Agendas',
  'my_package': 'Mi paquete',
  'print': 'Impresiones',
  'clients': 'Clientes',
  'packages': 'Paquetes',
  'finance': 'Finanzas',
  'drive': 'Archivos',
  'shared_files': 'Archivos compartidos',
  'settings': 'Configuraciones',
};

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _events = const [];
  List<Map<String, dynamic>> _roles = const [];
  List<Map<String, dynamic>> _history = const [];

  /// Evento que se está guardando (para no pulsar dos veces).
  String? _busyEvent;

  bool get _canEdit =>
      HsAccess.instance.degraded ||
      HsAccess.instance.can('Notificaciones', 'update');

  bool get _canSend =>
      HsAccess.instance.degraded ||
      HsAccess.instance.can('Notificaciones', 'create');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await HsApi.adminNotifications();
      if (!mounted) return;
      setState(() {
        _events = ((data['events'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        _roles = ((data['roles'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        _history = ((data['history'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudieron cargar las notificaciones';
      });
    }
  }

  List<String> _roleNames(Map<String, dynamic> event) =>
      ((event['roles'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();

  List<int> _roleIds(Map<String, dynamic> event) =>
      ((event['roleIds'] as List?) ?? const [])
          .map((e) => (e as num?)?.toInt() ?? 0)
          .where((e) => e > 0)
          .toList();

  /// Guarda la regla de un evento (roles + encendido/apagado).
  Future<void> _saveRule(
    Map<String, dynamic> event, {
    List<int>? roleIds,
    bool? enabled,
  }) async {
    final key = (event['key'] ?? '').toString();
    if (key.isEmpty || _busyEvent != null) return;
    setState(() => _busyEvent = key);
    try {
      await HsApi.saveNotificationRule(
        eventKey: key,
        roleIds: roleIds ?? _roleIds(event),
        enabled: enabled ?? event['enabled'] != false,
      );
      await _load();
    } catch (_) {
      // La capa de API ya avisó con la notificación roja.
    } finally {
      if (mounted) setState(() => _busyEvent = null);
    }
  }

  /// Diálogo para elegir los roles de un evento.
  Future<void> _pickRoles(Map<String, dynamic> event) async {
    if (!_canEdit) return;
    final state = ValueNotifier<Set<int>>(_roleIds(event).toSet());
    final saved = await showHsModal<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            '¿Quién recibe «${(event['title'] ?? '').toString()}»?',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          content: SizedBox(
            width: 420,
            child: ValueListenableBuilder<Set<int>>(
              valueListenable: state,
              builder: (_, picked, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    (event['description'] ?? '').toString(),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_roles.isEmpty)
                    const Text('No hay roles activos en la empresa.')
                  else
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final r in _roles)
                              CheckboxListTile(
                                key: ValueKey(
                                  'notif-role-${event['key']}-${r['id']}',
                                ),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: picked.contains(
                                  (r['id'] as num?)?.toInt(),
                                ),
                                title: Text((r['name'] ?? '').toString()),
                                onChanged: (on) {
                                  final id = (r['id'] as num?)?.toInt() ?? 0;
                                  final next = {...picked};
                                  if (on == true) {
                                    next.add(id);
                                  } else {
                                    next.remove(id);
                                  }
                                  state.value = next;
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
    // Los controladores/notificadores del diálogo NO se liberan aquí: la
    // animación de salida los sigue usando (mismo criterio que el resto de
    // diálogos del panel).
    final picked = {...state.value};
    if (saved != true) return;
    await _saveRule(event, roleIds: picked.toList());
  }

  /// Envía un aviso manual a los roles elegidos.
  Future<void> _compose() async {
    if (!_canSend) return;
    final manual = _events.firstWhere(
      (e) => (e['key'] ?? '') == 'aviso-manual',
      orElse: () => const <String, dynamic>{},
    );
    final title = TextEditingController();
    final body = TextEditingController();
    final picked = ValueNotifier<Set<int>>(_roleIds(manual).toSet());
    final target = ValueNotifier<String>(
      (manual['target'] ?? 'notifications').toString(),
    );
    final ok = await showHsModal<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text(
            'Enviar aviso',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const ValueKey('notif-send-title'),
                    controller: title,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Título del aviso',
                      hintText: 'Ej. Entrega de fotos el viernes',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('notif-send-body'),
                    controller: body,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Mensaje (opcional)',
                      hintText: 'Un detalle para quien lo reciba…',
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '¿QUIÉN LO RECIBE?',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ValueListenableBuilder<Set<int>>(
                    valueListenable: picked,
                    builder: (_, set, _) => Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final r in _roles)
                          FilterChip(
                            label: Text((r['name'] ?? '').toString()),
                            selected: set.contains((r['id'] as num?)?.toInt()),
                            onSelected: (on) {
                              final id = (r['id'] as num?)?.toInt() ?? 0;
                              final next = {...set};
                              if (on) {
                                next.add(id);
                              } else {
                                next.remove(id);
                              }
                              picked.value = next;
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '¿A QUÉ MÓDULO LLEVA AL TOCARLO?',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ValueListenableBuilder<String>(
                    valueListenable: target,
                    builder: (_, value, _) => DropdownButtonFormField<String>(
                      initialValue: _targetLabels.containsKey(value)
                          ? value
                          : 'notifications',
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Módulo',
                      ),
                      items: [
                        for (final e in _targetLabels.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) => target.value = v ?? 'notifications',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              key: const ValueKey('notif-send-confirm'),
              onPressed: () {
                if (title.text.trim().isEmpty) {
                  HsToast.info('Escribe el título del aviso');
                  return;
                }
                if (picked.value.isEmpty) {
                  HsToast.info('Elige al menos un rol');
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Enviar'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    try {
      await HsApi.sendAdminNotification(
        title: title.text.trim(),
        body: body.text.trim(),
        roleIds: picked.value.toList(),
        target: target.value,
      );
      await _load();
    } catch (_) {
      // La API ya mostró el error.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final automatic =
        _events.where((e) => e['automatic'] != false).toList(growable: false);
    final manual =
        _events.where((e) => e['automatic'] == false).toList(growable: false);
    final enabled = automatic.where((e) => e['enabled'] != false).length;

    return PageContainer(
      module: 'notifications',
      title: 'Notificaciones',
      description:
          'Elige qué roles reciben cada aviso y manda avisos al equipo o a '
          'los clientes. Al tocarlos, abren el módulo que corresponde.',
      icon: Icons.notifications_active_outlined,
      onRefresh: _load,
      stats: [
        StatPill(
          icon: Icons.campaign_outlined,
          label: '${automatic.length} avisos',
        ),
        StatPill(
          icon: Icons.check_circle_outline,
          label: '$enabled encendidos',
        ),
        StatPill(
          icon: Icons.history_rounded,
          label: '${_history.length} enviados',
        ),
      ],
      actions: [
        if (_canSend)
          HsActionButton(
            onPressed: _compose,
            icon: Icons.send_rounded,
            label: 'Enviar aviso',
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading)
            const ListSkeleton(lines: 4, cardHeight: 120)
          else if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 40,
                      color: scheme.error,
                    ),
                    const SizedBox(height: 10),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            _introCard(scheme),
            const SizedBox(height: 14),
            _sectionTitle(scheme, 'Avisos automáticos', Icons.bolt_rounded),
            const SizedBox(height: 8),
            for (final e in automatic) ...[
              _eventCard(scheme, e),
              const SizedBox(height: 10),
            ],
            // El título va UNA vez para todos los avisos manuales (si mañana
            // se agregan más eventos manuales, no se repite el encabezado).
            if (manual.isNotEmpty) ...[
              const SizedBox(height: 6),
              _sectionTitle(
                scheme,
                'Avisos manuales',
                Icons.campaign_outlined,
              ),
              const SizedBox(height: 8),
            ],
            for (final e in manual) ...[
              _eventCard(scheme, e),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 20),
            _sectionTitle(scheme, 'Historial', Icons.history_rounded),
            const SizedBox(height: 8),
            if (_history.isEmpty)
              const EmptyState(
                icon: Icons.history_rounded,
                title: 'Todavía no hay avisos enviados',
                message:
                    'Cuando el sistema o tú manden un aviso, aparecerá aquí '
                    'con sus destinatarios.',
              )
            else
              for (final h in _history.take(12)) _historyTile(scheme, h),
          ],
        ],
      ),
    );
  }

  Widget _introCard(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: .20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.tips_and_updates_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Cada aviso llega a la campanita de los usuarios de los roles '
              'elegidos y, al tocarlo, abre el módulo correspondiente. Sin '
              'configuración se usan los roles recomendados.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(ColorScheme scheme, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.primary),
        const SizedBox(width: 7),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w800,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _eventCard(ColorScheme scheme, Map<String, dynamic> event) {
    final key = (event['key'] ?? '').toString();
    final on = event['enabled'] != false;
    final roleNames = _roleNames(event);
    final configured = event['configured'] == true;
    final busy = _busyEvent == key;
    final target = (event['target'] ?? '').toString();

    return PopIn(
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 12, 10, 12),
        decoration: BoxDecoration(
          color: on
              ? scheme.surface
              : scheme.surfaceContainerHighest.withValues(alpha: .30),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: on
                ? scheme.primary.withValues(alpha: .20)
                : scheme.outlineVariant.withValues(alpha: .5),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (on ? scheme.primary : scheme.onSurfaceVariant)
                    .withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _eventIcon(key),
                size: 20,
                color: on ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (event['title'] ?? key).toString(),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: on ? null : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    (event['description'] ?? '').toString(),
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.3,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (roleNames.isEmpty)
                        _pill(
                          scheme,
                          icon: Icons.person_off_outlined,
                          label: 'Sin destinatarios',
                          color: scheme.error,
                        )
                      else
                        for (final name in roleNames)
                          _pill(
                            scheme,
                            icon: Icons.groups_2_outlined,
                            label: name,
                            color: AppColors.brand,
                          ),
                      if (target.isNotEmpty && _targetLabels.containsKey(target))
                        _pill(
                          scheme,
                          icon: Icons.open_in_new_rounded,
                          label: 'Abre ${_targetLabels[target]}',
                          color: scheme.onSurfaceVariant,
                        ),
                      if (!configured)
                        _pill(
                          scheme,
                          icon: Icons.auto_awesome_outlined,
                          label: 'Recomendado',
                          color: const Color(0xFFD97706),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              children: [
                Switch(
                  key: ValueKey('notif-switch-$key'),
                  value: on,
                  onChanged: (!_canEdit || busy)
                      ? null
                      : (v) => _saveRule(event, enabled: v),
                ),
                IconButton(
                  key: ValueKey('notif-roles-$key'),
                  tooltip: 'Elegir roles',
                  visualDensity: VisualDensity.compact,
                  onPressed: (!_canEdit || busy) ? null : () => _pickRoles(event),
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.manage_accounts_outlined, size: 19),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(
    ColorScheme scheme, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyTile(ColorScheme scheme, Map<String, dynamic> h) {
    final when = _when(h['created']);
    final role = (h['roleName'] ?? '').toString();
    final target = (h['target'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _eventIcon((h['kind'] ?? '').toString()),
            size: 17,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (h['title'] ?? '').toString(),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  [
                    if ((h['userName'] ?? '').toString().trim().isNotEmpty)
                      h['userName'].toString(),
                    if (role.isNotEmpty) role,
                    if (when.isNotEmpty) when,
                    if (_targetLabels.containsKey(target))
                      '→ ${_targetLabels[target]}',
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
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

  static String _when(Object? raw) {
    final d = DateTime.tryParse('${raw ?? ''}');
    if (d == null) return '';
    final hora = d.hour == 0 && d.minute == 0
        ? ''
        : ' ${d.hour.toString().padLeft(2, '0')}:'
              '${d.minute.toString().padLeft(2, '0')}';
    return '${d.day} ${_months[d.month - 1]}$hora';
  }
}

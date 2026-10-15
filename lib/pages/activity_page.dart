import 'package:flutter/material.dart';

import '../hs_api.dart';
import '../hs_format.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/common.dart';

// ==================================================================
// MÓDULO ACTIVIDAD: la bitácora del panel.
//
// Responde a "quién creó, editó o eliminó cada cosa": cada alta, edición o
// baja que pasa por la API deja una fila con el usuario, su rol, el módulo,
// la acción, el registro afectado y la descripción que devolvió el backend.
//
// Backend: GET /api/admin/activity (módulo "Actividad", acción "Ver").
// Es de SOLO LECTURA: aquí no se crea, edita ni elimina nada.
//
// DISEÑO: cada registro es una tarjeta con barra de acento del color de su
// acción, avatar con las INICIALES del usuario y, si el registro trae detalle,
// una flecha con aire propio (en su propio recuadro y separada del texto) que
// gira al abrir; el detalle se despliega dentro de la MISMA tarjeta.
// ==================================================================

/// Filtros de acción disponibles ('' = todas).
const List<(String, String, IconData)> _kActivityFilters = [
  ('', 'Todas', Icons.history_rounded),
  ('create', 'Creaciones', Icons.add_circle_outline),
  ('update', 'Ediciones', Icons.edit_outlined),
  ('delete', 'Eliminaciones', Icons.delete_outline),
];

/// Color + icono de cada acción.
({Color color, IconData icon, String label}) _actionStyle(String action) =>
    switch (action.toLowerCase()) {
      'create' => (
          color: const Color(0xFF10B981),
          icon: Icons.add_circle_outline,
          label: 'Creación',
        ),
      'delete' => (
          color: const Color(0xFFEF4444),
          icon: Icons.delete_outline,
          label: 'Eliminación',
        ),
      'update' => (
          color: AppColors.brand,
          icon: Icons.edit_outlined,
          label: 'Edición',
        ),
      _ => (
          color: const Color(0xFFF59E0B),
          icon: Icons.bolt_outlined,
          label: 'Acción',
        ),
    };

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _entries = const [];
  String _query = '';
  String _action = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await HsApi.activity(
        action: _action.isEmpty ? null : _action,
        limit: 200,
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
        _error = null;
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
        _error = 'No se pudo cargar la bitácora';
        _loading = false;
      });
    }
  }

  /// El buscador filtra lo ya cargado (últimos 200 registros).
  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _entries;
    return _entries.where((e) {
      final hay = [
        e['description'],
        e['userName'],
        e['roleName'],
        e['moduleName'],
        e['entity'],
        e['entityId'],
      ].map((v) => (v ?? '').toString().toLowerCase()).join(' ');
      return hay.contains(q);
    }).toList();
  }

  int _countOf(String action) =>
      _entries.where((e) => (e['action'] ?? '').toString() == action).length;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = _filtered;

    return PageContainer(
      title: 'Actividad',
      description:
          'Bitácora de quién creó, editó o eliminó cada cosa del panel.',
      icon: Icons.history_rounded,
      stats: [
        StatPill(
            icon: Icons.receipt_long_outlined,
            label: '${_entries.length} registros'),
        StatPill(
            icon: Icons.add_circle_outline,
            label: "${_countOf('create')} altas"),
        StatPill(
            icon: Icons.delete_outline,
            label: "${_countOf('delete')} bajas"),
      ],
      actions: [
        HsActionButton(
          primary: false,
          onPressed: _loading ? null : _reload,
          icon: Icons.refresh,
          label: 'Actualizar',
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Buscar por usuario, módulo o descripción…',
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
          // Filtro por tipo de acción: se pide al backend.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, label, icon) in _kActivityFilters)
                FilterChip(
                  selected: _action == value,
                  avatar: Icon(icon,
                      size: 16,
                      color: _action == value ? scheme.primary : null),
                  label: Text(label),
                  onSelected: (_) {
                    if (_action == value) return;
                    _action = value;
                    _reload();
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const ListSkeleton(lines: 5)
          else if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.cloud_off_outlined,
                        size: 40, color: scheme.error),
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
            )
          else if (entries.isEmpty)
            const EmptyState(
              icon: Icons.history_toggle_off_rounded,
              title: 'Sin actividad',
              message:
                  'Aquí aparecerá cada alta, edición o baja que se haga en el '
                  'panel, con el usuario que la hizo.',
            )
          else
            _ActivityTimeline(entries: entries),
        ],
      ),
    );
  }
}

/// La bitácora agrupada por día, del registro más reciente al más antiguo.
/// Cada día lleva una pastilla con su conteo de registros.
class _ActivityTimeline extends StatelessWidget {
  const _ActivityTimeline({required this.entries});

  final List<Map<String, dynamic>> entries;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Conteo por día (para la pastilla del encabezado).
    final counts = <String, int>{};
    for (final e in entries) {
      final d = hsParseDate(e['created']);
      if (d == null) continue;
      final k = hsDateKey(d);
      counts[k] = (counts[k] ?? 0) + 1;
    }

    final children = <Widget>[];
    String? lastDay;

    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final when = hsParseDate(e['created']);
      final day = when == null ? '' : hsDateKey(when);
      if (day.isNotEmpty && day != lastDay) {
        lastDay = day;
        final n = counts[day] ?? 0;
        children.add(Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 18, bottom: 10),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(999),
                  border:
                      Border.all(color: scheme.primary.withValues(alpha: .22)),
                ),
                child: Text(
                  hsDayLabel(when!).toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .7,
                    color: scheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$n ${n == 1 ? 'registro' : 'registros'}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ));
      }
      children.add(StaggeredItem(index: i, child: _ActivityTile(entry: e)));
    }

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// Una fila de la bitácora. Si el backend mandó `details`, la tarjeta se
/// expande para verlos (monto, campos tocados, etc.) y la flecha gira.
class _ActivityTile extends StatefulWidget {
  const _ActivityTile({required this.entry});

  final Map<String, dynamic> entry;

  @override
  State<_ActivityTile> createState() => _ActivityTileState();
}

class _ActivityTileState extends State<_ActivityTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entry = widget.entry;
    final style = _actionStyle((entry['action'] ?? '').toString());
    final when = hsParseDate(entry['created']);
    final user = (entry['userName'] ?? '').toString().trim();
    final role = (entry['roleName'] ?? '').toString().trim();
    final module = (entry['moduleName'] ?? '').toString().trim();
    final entity = (entry['entity'] ?? '').toString().trim();
    final entityId = entry['entityId'];
    final details = _detailsText(entry['details']);

    final meta = [
      if (module.isNotEmpty) module,
      if (entity.isNotEmpty)
        entityId == null ? entity : '$entity #$entityId',
    ].join('  ·  ');

    final head = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Barra de acento de la acción (a toda la altura de la tarjeta).
        Container(
          width: 3,
          height: 62,
          decoration: BoxDecoration(
            color: style.color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 12),
        // Quién lo hizo: iniciales del usuario (o el icono de la acción).
        _ActorBadge(name: user, tint: style.color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (entry['description'] ?? style.label).toString(),
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  meta,
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _MiniChip(
                    icon: Icons.person_outline,
                    label: user.isEmpty ? 'Usuario desconocido' : user,
                    tint: scheme.primary,
                  ),
                  if (role.isNotEmpty)
                    _MiniChip(
                      icon: Icons.badge_outlined,
                      label: role,
                      tint: scheme.onSurfaceVariant,
                    ),
                  _MiniChip(
                    icon: style.icon,
                    label: style.label,
                    tint: style.color,
                  ),
                ],
              ),
            ],
          ),
        ),
        // Hora + flecha. La flecha vive en su PROPIO recuadro y con aire
        // respecto a la hora y al texto: antes quedaba pegada al contenido.
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              when == null ? '' : hsTimeLabel(when),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (details != null) ...[
              const SizedBox(height: 10),
              AnimatedRotation(
                turns: _open ? .5 : 0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _open
                        ? style.color.withValues(alpha: .16)
                        : scheme.surfaceContainerHighest.withValues(alpha: .5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _open
                          ? style.color.withValues(alpha: .45)
                          : scheme.onSurfaceVariant.withValues(alpha: .22),
                    ),
                  ),
                  child: Icon(
                    Icons.expand_more_rounded,
                    size: 20,
                    color: _open ? style.color : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: details == null
                  ? null
                  : () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: head,
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _open && details != null
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(29, 0, 14, 14),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest
                              .withValues(alpha: .35),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color:
                                scheme.onSurfaceVariant.withValues(alpha: .14),
                          ),
                        ),
                        child: Text(
                          details,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  /// `details` del backend (JSON) en una línea legible: "monto: 500 · ...".
  static String? _detailsText(Object? details) {
    if (details == null) return null;
    if (details is Map) {
      final parts = <String>[];
      for (final e in details.entries) {
        final v = e.value;
        if (v == null) continue;
        if (v is Map || v is List) continue; // demasiado ruido
        var s = v.toString();
        if (s.trim().isEmpty || s == 'null') continue;
        if (s.length > 70) s = '${s.substring(0, 70)}…';
        parts.add('${e.key}: $s');
      }
      return parts.isEmpty ? null : parts.join('  ·  ');
    }
    if (details is List) return null;
    final s = details.toString().trim();
    return s.isEmpty ? null : s;
  }
}

/// Avatar "de quién": iniciales del usuario en un círculo con el tinte de la
/// acción; si no hay nombre, el icono de la acción.
class _ActorBadge extends StatelessWidget {
  const _ActorBadge({required this.name, required this.tint});

  final String name;
  final Color tint;

  static String _initials(String name) {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((p) => p.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) {
      final p = parts.first;
      return (p.length >= 2 ? p.substring(0, 2) : p).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint.withValues(alpha: .30)),
      ),
      child: initials.isEmpty
          ? Icon(Icons.person_outline_rounded, size: 18, color: tint)
          : Text(
              initials,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: tint,
              ),
            ),
    );
  }
}

/// Píldora diminuta con icono + texto.
class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.icon,
    required this.label,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tint.withValues(alpha: .22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: tint),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: tint,
            ),
          ),
        ],
      ),
    );
  }
}

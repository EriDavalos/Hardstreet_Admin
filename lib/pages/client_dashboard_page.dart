import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../app_constants.dart';
import '../hs_api.dart';
import '../hs_format.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/common.dart';

// ==================================================================
// DASHBOARD CLIENTE (módulo "Dashboard Cliente"): lo que el CLIENTE ve
// de sus paquetes comprados.
//   - Su paquete seleccionado: estatus, avance de pago y servicios.
//   - "Lo que hemos cumplido": checklist de servicios con su estatus
//     (Entregado ✓ / En proceso ◐ / Pendiente ○).
//   - Acceso a SU carpeta del Drive: la liga `url` del servicio del paquete
//     comprado (la misma que se edita en la pestaña Servicios del paquete).
//     Si la liga apunta a ESTE drive, se abre DENTRO de la app (en la
//     sección Archivos, a la carpeta); si es externa (p. ej. Google Drive)
//     se copia al portapapeles.
// `onOpenDrive(segments)` lo resuelve AdminHome para cambiar de sección.
// ==================================================================

class ClientDashboardPage extends StatefulWidget {
  const ClientDashboardPage({super.key, this.onOpenDrive});

  /// Abre la sección Archivos. [segments] = carpeta destino dentro del
  /// drive (vacío = raíz); null solo si no hay drive disponible.
  final void Function(List<String> segments)? onOpenDrive;

  @override
  State<ClientDashboardPage> createState() => _ClientDashboardPageState();
}

class _ClientDashboardPageState extends State<ClientDashboardPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _packages = const [];
  int _selectedId = 0;

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
      final packages = await HsApi.myPackages();
      if (!mounted) return;
      setState(() {
        _packages = packages;
        if (_selectedId == 0 && packages.isNotEmpty) {
          _selectedId = (packages.first['id'] as num? ?? 0).toInt();
        }
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
        _error = 'No se pudieron cargar tus paquetes';
        _loading = false;
      });
    }
  }

  Map<String, dynamic> get _selected {
    for (final p in _packages) {
      if ((p['id'] as num? ?? 0).toInt() == _selectedId) return p;
    }
    return _packages.isNotEmpty ? _packages.first : const {};
  }

  // ---- Servicios del paquete seleccionado ----

  List<Map<String, dynamic>> get _services {
    final raw = _selected['services'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  static int _statusId(Map<String, dynamic> s) {
    final st = s['status'];
    if (st is Map) return (st['id'] as num? ?? 0).toInt();
    return 0;
  }

  static String _statusName(Map<String, dynamic> s) {
    final st = s['status'];
    if (st is Map) return (st['name'] ?? '').toString();
    return '';
  }

  bool _isDone(Map<String, dynamic> s) {
    final id = _statusId(s);
    if (id != 0) return id == 3 || id == 6; // Entregado / Terminado
    final n = _statusName(s).toLowerCase();
    return n.contains('entregado') || n.contains('terminado');
  }

  bool _isInProgress(Map<String, dynamic> s) {
    final id = _statusId(s);
    if (id != 0) return id == 2;
    return _statusName(s).toLowerCase().contains('proceso');
  }

  // ---- LIGAS del Drive del paquete (service.url) ----

  /// Carpeta dentro de ESTE drive si la liga apunta aquí, si no null.
  /// Acepta `?path=a/b` (la forma del drive) o rutas sobre la misma base.
  static List<String>? ownDrivePathOf(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || !(u.hasScheme && u.host.isNotEmpty)) return null;
    final q = u.queryParameters['path'];
    if (q != null && q.isNotEmpty) {
      return q.split('/').where((s) => s.trim().isNotEmpty).toList();
    }
    final base = Uri.tryParse(AppConstants.apiBase);
    if (base != null &&
        u.host == base.host &&
        u.port == base.port &&
        u.pathSegments.isNotEmpty) {
      return u.pathSegments
          .where((s) => s.isNotEmpty && s != 'files' && s != 'thumb')
          .toList();
    }
    return null;
  }

  /// Ligas únicas de los servicios del paquete: (servicio, url).
  List<(String, String)> get _driveLinks {
    final out = <(String, String)>[];
    final seen = <String>{};
    for (final s in _services) {
      final svc = s['service'];
      if (svc is! Map) continue;
      final url = (svc['url'] ?? '').toString().trim();
      if (url.isEmpty || !seen.add(url)) continue;
      out.add(((svc['name'] ?? 'Servicio').toString(), url));
    }
    return out;
  }

  Future<void> _copy(String url) async {
    // Aviso INMEDIATO (el portapapeles es cortesía y no debe retrasar el UI).
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Enlace copiado')));
    }
    await Clipboard.setData(ClipboardData(text: url));
  }

  void _openLink(String url) {
    final segments = ownDrivePathOf(url);
    if (segments != null) {
      widget.onOpenDrive?.call(segments);
    } else {
      _copy(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final services = _services;
    final done = services.where(_isDone).length;
    final inProgress = services.where(_isInProgress).length;
    final price = ((_selected['price'] as num?) ?? 0).toDouble();
    final paid = ((_selected['paid'] as num?) ?? 0).toDouble();

    return PageContainer(
      title: 'Mi paquete',
      description:
          'Avance de tus paquetes: lo que ya cumplimos y el acceso a tu '
          'carpeta del Drive.',
      icon: Icons.workspace_premium_outlined,
      stats: [
        if (_packages.isNotEmpty)
          StatPill(
            icon: Icons.card_giftcard_outlined,
            label: '${_packages.length} '
                '${_packages.length == 1 ? 'paquete' : 'paquetes'}',
          ),
        if (services.isNotEmpty)
          StatPill(
            icon: Icons.check_circle_outline,
            label: '$done de ${services.length} servicios cumplidos',
          ),
      ],
      actions: [
        OutlinedButton.icon(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading)
            const ListSkeleton(lines: 3, cardHeight: 120)
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
                      onPressed: _load,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          else if (_packages.isEmpty)
            const EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'Aún no tienes paquetes',
              message:
                  'Cuando tu fotógrafo te asigne un paquete, aparecerá aquí '
                  'con su avance y el acceso a tu carpeta del Drive.',
            )
          else ...[
            if (_packages.length > 1) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _packages)
                    ChoiceChip(
                      label: Text(
                        (p['name'] ?? 'Paquete').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      selected:
                          (p['id'] as num? ?? 0).toInt() == _selectedId,
                      onSelected: (_) => setState(
                          () => _selectedId = (p['id'] as num? ?? 0).toInt()),
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            FadeSlideIn(child: _heroCard(scheme, price, paid)),
            if (services.isNotEmpty) ...[
              const SizedBox(height: 18),
              _header(scheme, Icons.checklist_rounded, 'Lo que hemos cumplido'),
              const SizedBox(height: 10),
              _progressCard(scheme, services, done, inProgress),
            ],
            const SizedBox(height: 18),
            _header(scheme, Icons.folder_copy_outlined, 'Mi carpeta del Drive'),
            const SizedBox(height: 10),
            _driveCard(scheme),
          ],
        ],
      ),
    );
  }

  // ==================== Piezas de UI ====================

  Widget _header(ColorScheme scheme, IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 17, color: scheme.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  Widget _heroCard(ColorScheme scheme, double price, double paid) {
    final p = _selected;
    final status = (p['status'] is Map)
        ? ((p['status'] as Map)['name'] ?? '').toString()
        : '';
    final pkg = (p['package'] is Map)
        ? (p['package'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final tier = (pkg['tier'] is Map)
        ? ((pkg['tier'] as Map)['name'] ?? '').toString()
        : '';
    final category = (pkg['packageCategory'] is Map)
        ? ((pkg['packageCategory'] as Map)['name'] ?? '').toString()
        : '';
    final payPct = price > 0 ? (paid / price).clamp(0.0, 1.0) : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.brand, AppColors.brandDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.card_giftcard_rounded,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (p['name'] ?? 'Mi paquete').toString(),
                        style: const TextStyle(
                            fontSize: 16.5, fontWeight: FontWeight.w800),
                      ),
                      if ((p['subtitle'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          (p['subtitle'] ?? '').toString(),
                          style: TextStyle(
                              fontSize: 12.5, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                if (status.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: scheme.primary),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (tier.isNotEmpty) _pill(scheme, Icons.military_tech_outlined, tier),
                if (category.isNotEmpty)
                  _pill(scheme, Icons.category_outlined, category),
                _pill(scheme, Icons.payments_outlined,
                    '${hsMoney(paid)} de ${hsMoney(price)}'),
              ],
            ),
            if (payPct != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: payPct,
                  minHeight: 7,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                payPct >= .999
                    ? 'Paquete liquidado ✓'
                    : 'Faltan ${hsMoney(price - paid)} por cubrir',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: payPct >= .999
                        ? Colors.green
                        : scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pill(ColorScheme scheme, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  /// Checklist de servicios: entregados en VERDE, en curso en AZUL.
  Widget _progressCard(
      ColorScheme scheme, List<Map<String, dynamic>> services, int done, int inProgress) {
    final total = services.length;
    final pct = total > 0 ? done / total : 0.0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$done de $total servicios cumplidos'
                        '${inProgress > 0 ? ' · $inProgress en proceso' : ''}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      '${(pct * 100).round()} %',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: scheme.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 7,
                    color: Colors.green,
                    backgroundColor: Colors.green.withValues(alpha: .14),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final s in services) _serviceRow(scheme, s),
        ],
      ),
    );
  }

  Widget _serviceRow(ColorScheme scheme, Map<String, dynamic> s) {
    final svc = (s['service'] is Map)
        ? (s['service'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final name = (svc['name'] ?? 'Servicio').toString();
    final note = (s['description'] ?? '').toString();
    final done = _isDone(s);
    final progress = _isInProgress(s);
    final color = done
        ? Colors.green
        : progress
            ? const Color(0xFF3B82F6)
            : scheme.onSurfaceVariant;
    final icon = done
        ? Icons.check_circle_rounded
        : progress
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    decoration: done ? TextDecoration.lineThrough : null,
                    color: done ? scheme.onSurfaceVariant : null,
                  ),
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            done
                ? 'Cumplido'
                : progress
                    ? 'En proceso'
                    : (_statusName(s).isEmpty ? 'Pendiente' : _statusName(s)),
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }

  /// Acceso al Drive del paquete: botón principal + liga por servicio.
  Widget _driveCard(ColorScheme scheme) {
    final links = _driveLinks;
    if (links.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(Icons.folder_copy_outlined,
                  size: 26, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Aún no se asigna la carpeta del Drive a tu paquete. '
                  'Tu fotógrafo la vincula desde la pestaña Servicios del '
                  'paquete y aquí aparecerá tu acceso directo.',
                  style: TextStyle(
                      fontSize: 12.5, height: 1.4, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final firstOwn = ownDrivePathOf(links.first.$2) != null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: FilledButton.icon(
              onPressed: () => _openLink(links.first.$2),
              icon: Icon(firstOwn ? Icons.folder_open_outlined : Icons.link,
                  size: 18),
              label: Text(firstOwn ? 'Entrar a mi Drive' : 'Copiar enlace del Drive'),
            ),
          ),
          if (links.length > 1) ...[
            const SizedBox(height: 4),
            const Divider(height: 1),
            for (final (name, url) in links) ...[
              ListTile(
                dense: true,
                leading: Icon(
                  ownDrivePathOf(url) != null
                      ? Icons.folder_outlined
                      : Icons.link,
                  size: 18,
                  color: scheme.primary,
                ),
                title: Text(name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
                subtitle: Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, color: scheme.onSurfaceVariant),
                ),
                trailing: TextButton(
                  onPressed: () => _openLink(url),
                  child: Text(
                      ownDrivePathOf(url) != null ? 'Abrir' : 'Copiar'),
                ),
              ),
            ],
          ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

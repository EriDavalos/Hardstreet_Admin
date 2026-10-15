import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../app_constants.dart';
import '../drive_base.dart';
import '../drive_scope.dart';
import '../hs_api.dart';
import '../hs_format.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/common.dart';
import '../widgets/hs_toast.dart';

// ==================================================================
// MI PAQUETE (módulo "Mi paquete", clave `my_package`; antes se llamaba
// "Dashboard Cliente"): lo que el CLIENTE ve de sus paquetes comprados.
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

  /// Carpetas del Drive COMPARTIDAS con el cliente: la unión de las carpetas
  /// que el estudio le asignó a cada uno de sus paquetes comprados.
  List<Map<String, dynamic>> _sharedPaths = const [];

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
      // Las carpetas compartidas son un extra: si fallan, la vista sigue.
      var shared = const <Map<String, dynamic>>[];
      try {
        final info = await HsApi.myDriveDirectories();
        shared = info.paths;
      } catch (_) {
        // Sin backend nuevo: se muestran las ligas de los servicios.
      }
      if (!mounted) return;
      setState(() {
        _packages = packages;
        _sharedPaths = shared;
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
      // La liga compartida PARA ESTE SERVICIO del paquete manda; la del
      // catálogo queda como respaldo de un backend viejo.
      final url = ((s['shareLink'] ?? '').toString().trim().isNotEmpty
              ? s['shareLink']
              : svc['url'])
          .toString()
          .trim();
      if (url.isEmpty || !seen.add(url)) continue;
      out.add(((svc['name'] ?? 'Servicio').toString(), url));
    }
    return out;
  }

  Future<void> _copy(String url) async {
    // Aviso INMEDIATO (el portapapeles es cortesía y no debe retrasar el UI).
    if (mounted) HsToast.info('Enlace copiado');
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

  /// Abre en el drive (sección Archivos) la carpeta compartida de un paquete.
  void _openShared(String path) {
    final segments = path
        .split('/')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    widget.onOpenDrive?.call(segments);
  }

  /// Abre el selector de fotos/elementos para UN servicio y guarda la lista
  /// que el cliente marque (nada se mueve ni se copia de carpeta).
  Future<void> _pickServiceItems(Map<String, dynamic> s, String name) async {
    final serviceId = (s['id'] as num?)?.toInt() ?? 0;
    if (serviceId == 0) {
      HsToast.info('No se pudo identificar el servicio');
      return;
    }
    // La selección guardada es la fuente de verdad; si el backend todavía no
    // tiene la migración, se arranca vacío en vez de fallar.
    var current = const <String>[];
    try {
      current = await HsApi.myServiceItems(serviceId);
    } catch (_) {
      // Sin backend nuevo: se empieza sin selección.
    }
    if (!mounted) return;
    final picked = await showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ServiceItemsPicker(
        title: name.isEmpty ? 'Servicio' : name,
        initial: current,
      ),
    );
    if (picked == null) return;
    try {
      await HsApi.setMyServiceItems(serviceId, picked);
      HsToast.success('Selección guardada');
      await _load();
    } catch (_) {
      // El error ya se notificó desde la capa de API.
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
          'Avance de tus paquetes: lo que ya cumplimos y las carpetas del '
          'Drive compartidas contigo.',
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
        HsActionButton(
          primary: false,
          onPressed: _loading ? null : _load,
          icon: Icons.refresh,
          label: 'Actualizar',
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
            _header(scheme, Icons.folder_copy_outlined, 'Mi Drive compartido'),
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
    // Opciones de compartir del SERVICIO: carpeta y liga (las define el
    // estudio) y la selección de fotos que hace el propio cliente.
    final shareFolder = (s['shareFolder'] ?? '').toString().trim();
    final shareLink = (s['shareLink'] ?? '').toString().trim();
    final items = (s['items'] as num?)?.toInt() ?? 0;
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
                // Opciones de compartir: en MÓVIL van en UNA fila que se
                // desliza (no apiladas), para no comerse el alto del listado.
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (shareFolder.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => _openShared(shareFolder),
                          icon: const Icon(Icons.folder_open_outlined, size: 16),
                          label: const Text('Abrir carpeta'),
                        ),
                      if (shareLink.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => _openLink(shareLink),
                          icon: const Icon(Icons.link, size: 16),
                          label: const Text('Ver liga'),
                        ),
                      TextButton.icon(
                        onPressed: () => _pickServiceItems(s, name),
                        icon: const Icon(Icons.photo_library_outlined,
                            size: 16),
                        label: Text(items > 0
                            ? 'Mis fotos ($items)'
                            : 'Elegir fotos'),
                      ),
                    ],
                  ),
                ),
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

  /// Acceso al Drive del paquete:
  ///   1. las carpetas COMPARTIDAS con el cliente (lo que ve en su drive),
  ///   2. y las ligas de los servicios del paquete (si las hay).
  Widget _driveCard(ColorScheme scheme) {
    final links = _driveLinks;
    final shared = _sharedPaths;
    if (shared.isEmpty && links.isEmpty) {
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
                  'Aún no se te comparte ninguna carpeta del Drive. Tu '
                  'fotógrafo la asigna al paquete desde el administrador del '
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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (shared.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: FilledButton.icon(
                onPressed: () =>
                    _openShared((shared.first['path'] ?? '').toString()),
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('Entrar a mi Drive'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                shared.length == 1
                    ? 'Carpeta compartida contigo'
                    : '${shared.length} carpetas compartidas contigo',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurfaceVariant),
              ),
            ),
            for (final s in shared)
              ListTile(
                dense: true,
                leading: Icon(Icons.folder_shared_outlined,
                    size: 18, color: scheme.primary),
                title: Text(
                  (s['packageName'] ?? '').toString().isEmpty
                      ? 'Carpeta compartida'
                      : (s['packageName'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  (s['path'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, color: scheme.onSurfaceVariant),
                ),
                trailing: TextButton(
                  onPressed: () => _openShared((s['path'] ?? '').toString()),
                  child: const Text('Abrir'),
                ),
              ),
          ],
          if (links.isNotEmpty) ...[
            if (shared.isNotEmpty)
              const Divider(height: 1)
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: FilledButton.icon(
                  onPressed: () => _openLink(links.first.$2),
                  icon: Icon(
                      ownDrivePathOf(links.first.$2) != null
                          ? Icons.folder_open_outlined
                          : Icons.link,
                      size: 18),
                  label: Text(ownDrivePathOf(links.first.$2) != null
                      ? 'Entrar a mi Drive'
                      : 'Copiar enlace del Drive'),
                ),
              ),
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

/// Selector de elementos/fotos del Drive del CLIENTE para UN servicio:
/// navega SUS carpetas (solo lo compartido) y marca lo que quiera. Se guarda
/// la LISTA de rutas; nada se mueve ni se copia de carpeta.
class _ServiceItemsPicker extends StatefulWidget {
  const _ServiceItemsPicker({required this.title, required this.initial});

  final String title;
  final List<String> initial;

  @override
  State<_ServiceItemsPicker> createState() => _ServiceItemsPickerState();
}

class _ServiceItemsPickerState extends State<_ServiceItemsPicker> {
  List<String> _path = const [];
  List<DriveItem> _items = const [];
  bool _loading = true;
  String? _error;
  bool _started = false;

  /// Rutas ABSOLUTAS marcadas (se conservan al navegar entre carpetas).
  late final Set<String> _picked = {
    for (final p in widget.initial) drivePathNormalize(p),
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final drive = DriveScope.maybeOf(context);
    if (drive == null) {
      setState(() {
        _loading = false;
        _error = 'El Drive no está disponible en esta pantalla';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await drive.listFolderItems(_path);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _abs(String name) => drivePathNormalize([..._path, name].join('/'));

  bool _isImage(DriveItem i) =>
      !i.isFolder &&
      kImageExtensions.any((e) => i.name.toLowerCase().endsWith(e));

  void _toggle(String abs) {
    setState(() {
      if (!_picked.remove(abs)) _picked.add(abs);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final folders = _items.where((i) => i.isFolder).toList();
    final images = _items.where(_isImage).toList();
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(
        'Elegir fotos · ${widget.title}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Navega tus carpetas compartidas y marca los elementos que '
              'quieras para este servicio. Se guarda tu SELECCIÓN: nada se '
              'mueve ni se copia de carpeta.',
              style: TextStyle(
                  fontSize: 12, height: 1.3, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_path.isNotEmpty)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Subir',
                    onPressed: () {
                      setState(() => _path = _path.sublist(0, _path.length - 1));
                      _load();
                    },
                    icon: const Icon(Icons.arrow_upward, size: 18),
                  ),
                Expanded(
                  child: Text(
                    _path.isEmpty ? 'Mi Drive' : _path.join(' / '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${_picked.length} elegidos',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary),
                ),
              ],
            ),
            const Divider(height: 12),
            Expanded(child: _list(scheme, folders, images)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        if (_picked.isNotEmpty)
          TextButton(
            onPressed: () => setState(() => _picked.clear()),
            child: const Text('Limpiar'),
          ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, _picked.toList()..sort()),
          child: const Text('Guardar selección'),
        ),
      ],
    );
  }

  Widget _list(
      ColorScheme scheme, List<DriveItem> folders, List<DriveItem> images) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: scheme.error),
        ),
      );
    }
    if (folders.isEmpty && images.isEmpty) {
      return Center(
        child: Text(
          'Esta carpeta está vacía.',
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
      );
    }
    return ListView(
      children: [
        for (final f in folders)
          ListTile(
            dense: true,
            leading: Icon(Icons.folder_rounded, color: scheme.primary),
            title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              setState(() => _path = [..._path, f.name]);
              _load();
            },
          ),
        for (final img in images)
          CheckboxListTile(
            dense: true,
            value: _picked.contains(_abs(img.name)),
            onChanged: (_) => _toggle(_abs(img.name)),
            title: Text(
              img.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
      ],
    );
  }
}

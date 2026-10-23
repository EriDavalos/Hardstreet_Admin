import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../app_constants.dart';
import '../drive_base.dart' show DriveItem, driveImagePreview, isDriveImageUrl;
import '../drive_scope.dart';
import '../hs_access.dart';
import '../hs_api.dart';
import '../hs_format.dart';
import '../service_icons.dart';
import '../theme.dart' show AppColors;
import '../widgets/anim.dart';
import '../widgets/common.dart';
import '../widgets/drive_thumb.dart';
import '../widgets/hero_photo_banner.dart';
import '../widgets/hs_search_filter.dart';
import '../widgets/photo_backdrop.dart';
import '../widgets/service_photos_sheet.dart';
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

  /// Avisos del paquete (fotos disponibles, servicio terminado…).
  List<Map<String, dynamic>> _notifications = const [];
  int _unread = 0;

  /// FOTOS DEL BANNER de la portada: hasta 10 al azar entre las carpetas
  /// compartidas de los servicios CUMPLIDOS que tienen encendido «Mostrar
  /// banner cliente» (lo enciende el estudio en el servicio del catálogo).
  List<String> _bannerPhotos = const [];

  /// Clave de la última carga del banner (paquete + servicios): evita
  /// volver a listar carpetas en cada reconstrucción.
  String _bannerFor = '';

  /// Foto que el banner está mostrando AHORA (la avisa él): es la que se pinta
  /// desenfocada de fondo de la vista.
  String _ambientPhoto = '';

  /// Búsqueda y filtro de SUS servicios.
  String _serviceQuery = '';
  String _serviceFilter = '';

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
      // Avisos del paquete: si el backend aún no tiene la migración, vacío.
      var notifications = const <Map<String, dynamic>>[];
      var unread = 0;
      try {
        final info = await HsApi.myNotifications();
        notifications = info.items;
        unread = info.unread;
      } catch (_) {
        // Sin avisos: la vista sigue igual.
      }
      if (!mounted) return;
      setState(() {
        _packages = packages;
        _sharedPaths = shared;
        _notifications = notifications;
        _unread = unread;
        if (_selectedId == 0 && packages.isNotEmpty) {
          _selectedId = (packages.first['id'] as num? ?? 0).toInt();
        }
        _loading = false;
        // Al recargar se vuelven a sortear las fotos del banner.
        _bannerFor = '';
      });
      unawaited(_loadBannerPhotos());
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

  /// Servicios CUMPLIDOS del paquete que pueden alimentar el banner: tienen
  /// encendido «Mostrar banner cliente» y una carpeta compartida.
  List<Map<String, dynamic>> get _bannerServices => [
    for (final s in _services)
      if (_isDone(s) &&
          s['service'] is Map &&
          (s['service'] as Map)['showBanner'] == true &&
          (s['shareFolder'] ?? '').toString().trim().isNotEmpty)
        s,
  ];

  /// Arma la ronda de fotos del banner: lista las carpetas compartidas de los
  /// servicios cumplidos y se queda con 10 imágenes AL AZAR.
  ///
  /// Es "mejor esfuerzo": si el drive no está disponible o una carpeta falla,
  /// el banner sigue con la foto del paquete (no se rompe nada).
  Future<void> _loadBannerPhotos() async {
    final services = _bannerServices;
    final pkgId = (_selected['id'] as num? ?? 0).toInt();
    final key = '$pkgId:${services.map((s) => s['id']).join(',')}';
    if (key == _bannerFor) return;
    _bannerFor = key;
    if (services.isEmpty) {
      if (_bannerPhotos.isNotEmpty) {
        setState(() {
          _bannerPhotos = const [];
          _ambientPhoto = '';
        });
      }
      return;
    }
    final drive = DriveScope.maybeOf(context);
    if (drive == null) return;
    final found = <String>[];
    for (final s in services) {
      final rel = (s['shareFolder'] ?? '')
          .toString()
          .split('/')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      if (rel.isEmpty) continue;
      try {
        final items = await drive.listFolderItems(rel);
        for (final DriveItem item in items) {
          if (item.isFolder || !item.isImage) continue;
          final src = drive.thumbSourceIn(rel, item, width: 1400);
          if (src.trim().isNotEmpty) found.add(src);
        }
      } catch (_) {
        // Carpeta sin acceso o drive caído: se usan las demás.
      }
    }
    if (!mounted || _bannerFor != key) return;
    final unique = found.toSet().toList()..shuffle();
    setState(() {
      _bannerPhotos = unique.take(10).toList(growable: false);
      _ambientPhoto = '';
    });
  }

  /// Deja la foto lista ANTES de que el banner la funda: descargada y
  /// decodificada. Si tarda, el banner sigue mostrando la anterior y el cambio
  /// entra con su fundido, en vez de fundir a un hueco y enseñar la nueva de
  /// golpe cuando por fin llega.
  Future<void> _preloadBannerPhoto(String url) async {
    if (!mounted) return;
    final provider = _PackagePhoto.providerFor(url, big: true);
    if (provider == null) return;
    // Si la foto no baja, el banner cambia igual: aquí no hay nada que avisar
    // (DriveThumb ya reintenta y tiene su respaldo).
    await precacheImage(provider, context, onError: (_, _) {});
  }

  /// Foto del FONDO de la vista: la que muestra el banner o, si todavía no hay
  /// fotos de la carpeta, la del paquete.
  ImageProvider? get _ambientProvider {
    final pkg = _selected['package'];
    final own = pkg is Map ? (pkg['urlImage'] ?? '').toString() : '';
    final url = _ambientPhoto.trim().isNotEmpty ? _ambientPhoto : own;
    return _PackagePhoto.providerFor(url, big: true);
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

  /// VERDE de "servicio cumplido": el mismo verde de la paleta del panel.
  static const _doneColor = Color(0xFF16A34A);

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
      final url =
          ((s['shareLink'] ?? '').toString().trim().isNotEmpty
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

  /// Abre el MÓDULO de fotos de UN servicio: ver lo elegido, quitar, agregar
  /// (solo dentro de la carpeta compartida del servicio) y guardar.
  Future<void> _pickServiceItems(Map<String, dynamic> s, String name) async {
    final serviceId = (s['id'] as num?)?.toInt() ?? 0;
    if (serviceId == 0) {
      HsToast.info('No se pudo identificar el servicio');
      return;
    }
    final drive = DriveScope.maybeOf(context);
    if (drive == null) {
      HsToast.info('El Drive no está disponible en esta pantalla');
      return;
    }
    final catalog = (s['service'] is Map)
        ? (s['service'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    var folder = (s['shareFolder'] ?? '').toString().trim();
    var max =
        (s['photosMax'] as num?)?.toInt() ??
        (catalog['photosMax'] as num?)?.toInt() ??
        0;
    var current = const <String>[];
    // Enviado a impresión = solo lectura (las fotos NO se pueden cambiar
    // hasta que el estudio reabra el envío).
    var readOnly =
        s['sentToPrint'] == true ||
        (s['printStatus'] ?? '') == 'sent' ||
        (s['printStatus'] ?? '') == 'finished';
    try {
      final info = await HsApi.myServiceItemsInfo(serviceId);
      current = info.items;
      if (info.folder.isNotEmpty) folder = info.folder;
      if (info.max > 0) max = info.max;
      readOnly = readOnly || info.sent;
    } catch (_) {
      // Backend viejo: se usan los datos del paquete y la lista guardada.
    }
    if (!mounted) return;
    if (folder.isEmpty) {
      HsToast.info(
        'El servicio todavía no tiene carpeta compartida',
        details: 'Tu fotógrafo la asigna desde el administrador del paquete.',
      );
      return;
    }
    final saved = await showServicePhotosSheet(
      context,
      drive: drive,
      serviceId: serviceId,
      serviceName: name.isEmpty ? 'Servicio' : name,
      folder: folder,
      max: max,
      initial: current,
      readOnly: readOnly,
    );
    if (saved == null) return;
    await _load();
  }

  /// Envía a impresión la selección ACTUAL del servicio.
  ///
  /// Después de enviar, el cliente deja de poder modificarla (solo verla)
  /// hasta que el estudio la reabra desde el módulo de impresiones.
  Future<void> _sendToPrint(Map<String, dynamic> s, String name) async {
    final serviceId = (s['id'] as num?)?.toInt() ?? 0;
    final count = (s['items'] as num?)?.toInt() ?? 0;
    if (serviceId == 0 || count == 0) {
      HsToast.info('Elige tus fotos antes de enviarlas');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar a impresión'),
        content: Text(
          'Se enviarán $count ${count == 1 ? 'foto' : 'fotos'} de '
          '«${name.isEmpty ? 'este servicio' : name}» al estudio.\n\n'
          'Después de enviarlas ya no podrás cambiar la selección: solo verla. '
          'Si necesitas cambiar algo, pídele al estudio que reabra el envío.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await HsApi.sendMyPrintRequest(serviceId);
      if (!mounted) return;
      // Se marca el servicio EN EL ACTO: el botón «Enviar a impresión»
      // desaparece aunque la recarga falle o tarde (antes seguía ahí hasta
      // refrescar, y se podía intentar enviar dos veces).
      setState(() {
        _packages = [
          for (final p in _packages)
            {
              ...p,
              if (p['services'] is List)
                'services': [
                  for (final raw in p['services'] as List)
                    if (raw is Map && (raw['id'] as num?)?.toInt() == serviceId)
                      {
                        ...raw.cast<String, dynamic>(),
                        'sentToPrint': true,
                        'printStatus': 'sent',
                      }
                    else
                      raw,
                ],
            },
        ];
      });
      HsToast.success(
        'Fotos enviadas a impresión',
        details: 'El estudio las recortará al formato elegido.',
      );
      await _load();
    } catch (_) {
      // El aviso de error ya lo mostró la API.
    }
  }

  /// Abre lo que anuncia una novedad: selección de fotos del servicio
  /// («Ya puedes elegir tus fotos») o, si no hay servicio, solo la marca
  /// como leída.
  Future<void> _openNotification(Map<String, dynamic> n) async {
    final id = (n['id'] as num?)?.toInt() ?? 0;
    if (n['isRead'] != true && id > 0) await _readNotification(id);
    final kind = (n['kind'] ?? '').toString();
    final serviceId = (n['serviceId'] as num?)?.toInt() ?? 0;
    if (serviceId <= 0) return;
    final svc = _services.firstWhere(
      (s) => (s['id'] as num?)?.toInt() == serviceId,
      orElse: () => const <String, dynamic>{},
    );
    if (svc.isEmpty) return;
    // «Fotos disponibles» (y el cierre de un servicio) llevan a sus fotos;
    // el resto de avisos del paquete ya se está viendo aquí mismo.
    if (kind == 'fotos-disponibles' || kind == 'impresion-terminada') {
      final catalog = (svc['service'] is Map)
          ? (svc['service'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{};
      final name = (catalog['name'] ?? 'Servicio').toString();
      await _pickServiceItems(svc, name);
    }
  }

  /// Marca un aviso como leído (optimista) y confirma con el servidor.
  Future<void> _readNotification(int id) async {
    setState(() {
      _notifications = [
        for (final n in _notifications)
          if ((n['id'] as num?)?.toInt() == id) {...n, 'isRead': true} else n,
      ];
      _unread = _notifications.where((n) => n['isRead'] != true).length;
    });
    try {
      await HsApi.markNotificationsRead(ids: [id]);
    } catch (_) {
      // El próximo refresh lo corrige.
    }
  }

  Future<void> _readAllNotifications() async {
    if (_unread == 0) return;
    setState(() {
      _notifications = [
        for (final n in _notifications) {...n, 'isRead': true},
      ];
      _unread = 0;
    });
    try {
      await HsApi.markNotificationsRead(all: true);
    } catch (_) {
      // idem.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final services = _services;
    final done = services.where(_isDone).length;
    final price = ((_selected['price'] as num?) ?? 0).toDouble();
    final paid = ((_selected['paid'] as num?) ?? 0).toDouble();

    // La FOTO que se está viendo va de fondo de TODA la vista, desenfocada y
    // con un velo encima. Antes se pintaba un halo de color alrededor de la
    // portada: ensuciaba la vista y no dejaba ver la foto. Va detrás del
    // contenido (el héroe del módulo y las tarjetas no se tocan) y cambia con
    // el mismo fundido con el que el banner pasa de foto en foto (cada 6 s).
    return Stack(
      fit: StackFit.expand,
      children: [
        PhotoBackdrop(image: _ambientProvider),
        PageContainer(
          module: 'my_package',
          title: 'Mi paquete',
          description:
              'Avance de tus paquetes: lo que ya cumplimos y las carpetas del '
              'Drive compartidas contigo.',
          icon: Icons.workspace_premium_outlined,
          onRefresh: _load,
          stats: [
            if (_packages.isNotEmpty)
              StatPill(
                icon: Icons.card_giftcard_outlined,
                label:
                    '${_packages.length} '
                    '${_packages.length == 1 ? 'paquete' : 'paquetes'}',
              ),
            if (services.isNotEmpty)
              StatPill(
                icon: Icons.check_circle_outline,
                label: '$done de ${services.length} servicios cumplidos',
              ),
          ],
          // Sin botón de recargar: se recarga deslizando hacia abajo.
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
                  _packagePicker(scheme),
                  const SizedBox(height: 14),
                ],
                FadeSlideIn(child: _heroCard(price, paid)),
                if (_notifications.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _notificationsCard(scheme),
                ],
                if (services.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _servicesSection(scheme, services),
                ],
                const SizedBox(height: 20),
                _sectionTitle(
                  scheme,
                  Icons.folder_copy_outlined,
                  'Mi Drive compartido',
                  trailing:
                      '${_sharedPaths.length} '
                      '${_sharedPaths.length == 1 ? 'carpeta' : 'carpetas'}',
                ),
                const SizedBox(height: 10),
                _driveCard(scheme),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ==================== Piezas de UI ====================

  Widget _sectionTitle(
    ColorScheme scheme,
    IconData icon,
    String label, {
    String? trailing,
  }) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 15, color: scheme.primary),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ),
        if ((trailing ?? '').isNotEmpty)
          Text(
            trailing!,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  // ---------------- Selector de paquete (con su foto) ----------------

  /// Tira horizontal de paquetes cuando el cliente tiene más de uno. Cada
  /// uno lleva su foto, como la tarjeta del catálogo.
  Widget _packagePicker(ColorScheme scheme) {
    final phone = MediaQuery.sizeOf(context).width < 620;
    return SizedBox(
      height: phone ? 76 : 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 2),
        itemCount: _packages.length,
        separatorBuilder: (_, _) => const SizedBox(width: 9),
        itemBuilder: (context, i) {
          final p = _packages[i];
          final id = (p['id'] as num? ?? 0).toInt();
          final on = id == _selectedId;
          final pkg = (p['package'] is Map)
              ? (p['package'] as Map).cast<String, dynamic>()
              : const <String, dynamic>{};
          final photo = (pkg['urlImage'] ?? '').toString().trim();
          final look = HsTierLook.of(
            (pkg['tier'] is Map)
                ? ((pkg['tier'] as Map)['name'] ?? '').toString()
                : '',
          );
          return InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: () {
              setState(() => _selectedId = id);
              unawaited(_loadBannerPhotos());
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: phone ? 190 : 220,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: on
                    ? look.accent.withValues(alpha: .10)
                    : scheme.surfaceContainerHighest.withValues(alpha: .30),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: on
                      ? look.accent.withValues(alpha: .75)
                      : scheme.outlineVariant.withValues(alpha: .45),
                  width: on ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: _PackagePhoto(
                        url: photo,
                        tier: look,
                        emoji: hsCategoryEmoji(
                          (pkg['packageCategory'] is Map)
                              ? ((pkg['packageCategory'] as Map)['name'] ?? '')
                                    .toString()
                              : '',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (p['name'] ?? 'Paquete').toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.2,
                            fontWeight: on ? FontWeight.w800 : FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          (p['status'] is Map)
                              ? ((p['status'] as Map)['name'] ?? '').toString()
                              : '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (on)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 17,
                      color: look.accent,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------- Avisos del paquete ----------------

  static IconData _noticeIcon(String kind) {
    switch (kind) {
      case 'fotos-disponibles':
        return Icons.photo_library_outlined;
      case 'servicio-terminado':
        return Icons.task_alt_rounded;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  static String _noticeWhen(Map<String, dynamic> n) {
    final when = hsParseDate(n['created']);
    return when == null ? '' : hsShortDate(when);
  }

  /// Novedades que el estudio envió al cliente (fotos, cierre de servicio…).
  Widget _notificationsCard(ColorScheme scheme) {
    final items = _notifications.take(4).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.primary.withValues(alpha: .22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.notifications_active_outlined,
                size: 17,
                color: scheme.primary,
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Novedades',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                ),
              ),
              if (_unread > 0)
                TextButton(
                  onPressed: _readAllNotifications,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Marcar leídas'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (final n in items) _noticeRow(scheme, n),
        ],
      ),
    );
  }

  Widget _noticeRow(ColorScheme scheme, Map<String, dynamic> n) {
    final unread = n['isRead'] != true;
    final kind = (n['kind'] ?? '').toString();
    final when = _noticeWhen(n);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      // Tocar la novedad la marca leída y, si es de un servicio, abre SUS
      // fotos: el aviso lleva a la información que anuncia.
      onTap: () => _openNotification(n),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: (unread ? scheme.primary : scheme.onSurfaceVariant)
                    .withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _noticeIcon(kind),
                size: 17,
                color: unread ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          (n['title'] ?? 'Aviso').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: unread
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (unread)
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(left: 6),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  if ((n['body'] ?? '').toString().isNotEmpty)
                    Text(
                      (n['body'] ?? '').toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  if (when.isNotEmpty)
                    Text(
                      when,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: scheme.onSurfaceVariant.withValues(alpha: .8),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  // ==================== Portada del paquete ====================

  Widget _heroCard(double price, double paid) {
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
    final photo = (pkg['urlImage'] ?? '').toString().trim();
    final look = HsTierLook.of(tier);
    final phone = MediaQuery.sizeOf(context).width < 620;
    final folder = _sharedPaths.isNotEmpty
        ? (_sharedPaths.first['path'] ?? '').toString()
        : '';
    // Los DOS datos que importan en la portada: qué toca hacer ahora y cómo
    // va el pago. Antes aquí vivían el conteo de servicios, «Carpeta lista» y
    // la barra de pago: mucha lectura para lo que el cliente necesita ver de
    // un golpe.
    final next = _heroNext(_services);
    final money = _heroMoney(price, paid);

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Container(
        decoration: BoxDecoration(
          gradient: look.gradient,
          border: Border.all(color: look.accent.withValues(alpha: .34)),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---------- Foto del paquete con su información ----------
            SizedBox(
              height: phone ? 196 : 240,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Banner: la foto del paquete o, cuando hay servicios
                  // cumplidos con «Mostrar banner cliente», sus fotos al azar.
                  // La foto del paquete queda SIEMPRE debajo: mientras las
                  // fotos de la carpeta cargan (o si una falla) se sigue
                  // viendo ella, no un banner vacío.
                  HeroPhotoBanner(
                    photos: _bannerPhotos,
                    // Sin la foto descargada NO se funde: el cambio se quedaba
                    // sin transición y la foto aparecía de golpe.
                    preload: _preloadBannerPhoto,
                    // La portada pasa de foto cada 6 s (el fondo de la vista
                    // cambia a la par, con el mismo fundido).
                    every: const Duration(seconds: 6),
                    onPhoto: (url) {
                      if (!mounted || url == _ambientPhoto) return;
                      setState(() => _ambientPhoto = url);
                    },
                    background: _PackagePhoto(
                      url: photo,
                      tier: look,
                      emoji: hsCategoryEmoji(category),
                      big: true,
                    ),
                    builder: (_, url) => _PackagePhoto(
                      url: url,
                      tier: look,
                      emoji: hsCategoryEmoji(category),
                      big: true,
                      // En la portada el recorte tira hacia ARRIBA: en el
                      // banner ancho de la computadora una foto vertical
                      // recortada al centro le corta la cara a la persona.
                      alignment: const Alignment(0, -0.35),
                      // Mientras esta foto carga se ve la del paquete.
                      waiting: const SizedBox.shrink(),
                    ),
                  ),
                  // Velo: arriba para las píldoras, abajo para el título.
                  //
                  // Se pinta 1 px MÁS ALTO que el banner y el clip del Stack
                  // corta el sobrante: con alturas en píxeles fraccionarios
                  // (p. ej. 218 × 1.25 = 272.5) el velo y la foto redondeaban
                  // distinto y quedaba una fina línea de foto sin oscurecer
                  // justo en el borde de abajo, al cambiar de imagen.
                  const Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    bottom: -1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x66000000),
                            Color(0x00000000),
                            Color(0x22000000),
                            Color(0xE6000000),
                          ],
                          stops: [0, .28, .55, 1],
                        ),
                      ),
                    ),
                  ),
                  // Filo de luz en el borde de arriba: da el aire de cristal
                  // al recorte de la foto sin ensuciarla.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: .00),
                            Colors.white.withValues(alpha: .30),
                            Colors.white.withValues(alpha: .00),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 13,
                    right: 13,
                    top: 12,
                    child: Row(
                      children: [
                        if (status.isNotEmpty)
                          _heroPill(
                            icon: Icons.circle,
                            label: status,
                            tint: Colors.white,
                          ),
                        const Spacer(),
                        if (tier.isNotEmpty)
                          _heroPill(
                            icon: Icons.military_tech_outlined,
                            label: tier,
                            tint: look.accentSoft,
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 13,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (category.isNotEmpty)
                          Text(
                            '${hsCategoryEmoji(category)}  ${category.toUpperCase()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: look.accentSoft,
                              fontSize: 10,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        const SizedBox(height: 5),
                        Text(
                          (p['name'] ?? 'Mi paquete').toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            height: 1.08,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if ((p['subtitle'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            (p['subtitle'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .78),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ---------- Pie: lo que sigue + cómo va el pago ----------
            // SIN cajas: antes eran dos tarjetas grandes y «Elige tus fotos»
            // y «Liquidado» pesaban más que la propia foto. Ahora son una
            // línea de estado y un sello de recibo, alineados con el diseño
            // plano del panel.
            Container(
              padding: EdgeInsets.fromLTRB(
                phone ? 14 : 17,
                12,
                phone ? 14 : 17,
                14,
              ),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: .10)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: next ?? const SizedBox.shrink(),
                      ),
                      if (money != null) ...[
                        const SizedBox(width: 10),
                        money,
                      ],
                    ],
                  ),
                  if (folder.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => _openShared(folder),
                        style: FilledButton.styleFrom(
                          backgroundColor: look.accent,
                          foregroundColor: look.dark,
                          minimumSize: const Size(0, 42),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                        ),
                        icon: const Icon(Icons.folder_open_outlined, size: 18),
                        label: const Text('Abrir mi carpeta'),
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

  /// Píldora sobre la foto del paquete.
  Widget _heroPill({
    required IconData icon,
    required String label,
    required Color tint,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .38),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: tint),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  /// El servicio ya se envió a impresión (la selección quedó en solo lectura).
  static bool _sentToPrint(Map<String, dynamic> s) =>
      s['sentToPrint'] == true ||
      (s['printStatus'] ?? '').toString().trim().isNotEmpty;

  /// Dinero en corto, sin el prefijo de la moneda: `MXN $6,000` -> `$6,000`.
  static String _money(double v) => hsMoney(v).replaceFirst('MXN ', '');

  /// QUÉ TOCA HACER AHORA, en una frase. Es el dato más útil de la portada:
  /// primero lo que espera al cliente (elegir o enviar sus fotos), después en
  /// qué va el estudio y, si ya acabó todo, que su paquete está completo.
  Widget? _heroNext(List<Map<String, dynamic>> services) {
    if (services.isEmpty) return null;
    final pickable = services.where(_photoService).toList();
    final waiting = pickable
        .where((s) => _items(s) == 0 && !_sentToPrint(s))
        .length;
    final ready = pickable
        .where((s) => _items(s) > 0 && !_sentToPrint(s))
        .length;
    final working = services.where((s) => !_isDone(s)).length;
    final done = services.where(_isDone).length;

    if (waiting > 0) {
      return _heroNextLine(
        icon: Icons.photo_library_outlined,
        tint: const Color(0xFF8FC2FF),
        title: 'Elige tus fotos',
        hint: waiting == 1
            ? '1 servicio espera tu selección'
            : '$waiting servicios esperan tu selección',
      );
    }
    if (ready > 0) {
      return _heroNextLine(
        icon: Icons.send_rounded,
        tint: const Color(0xFF8FC2FF),
        title: 'Envía tus fotos',
        hint: ready == 1
            ? '1 servicio listo para enviar'
            : '$ready servicios listos para enviar',
      );
    }
    if (working > 0) {
      return _heroNextLine(
        icon: Icons.hourglass_top_rounded,
        tint: const Color(0xFF8FC2FF),
        title: 'En proceso',
        hint: working == 1
            ? '1 servicio en preparación'
            : '$working servicios en preparación',
      );
    }
    if (done > 0) {
      return _heroNextLine(
        icon: Icons.task_alt_rounded,
        tint: const Color(0xFF7BE3B0),
        title: 'Todo entregado',
        hint: 'Todos tus servicios están completos',
      );
    }
    return null;
  }

  /// CÓMO VA EL PAGO, como el renglón de totales de un recibo: «Liquidado»
  /// cuando ya no falta nada o, si no, el monto que falta, con el total y el
  /// porcentaje como apoyo. Sin barra, sin caja y sin gritar.
  Widget? _heroMoney(double price, double paid) {
    if (price <= 0) return null;
    final left = price - paid;
    final paidOff = left <= .5;
    final pct = ((paid / price) * 100).clamp(0, 100).round();
    final tint = paidOff ? const Color(0xFF7BE3B0) : const Color(0xFFFFD98A);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              paidOff
                  ? Icons.verified_rounded
                  : Icons.account_balance_wallet_outlined,
              size: 12,
              color: tint,
            ),
            const SizedBox(width: 4),
            Text(
              paidOff ? 'Liquidado' : 'Faltan ${_money(left)}',
              style: TextStyle(
                color: tint,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          paidOff
              ? 'Pagado ${_money(price)}'
              : 'de ${_money(price)} · $pct %',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .55),
            fontSize: 9.5,
          ),
        ),
      ],
    );
  }

  /// LO QUE SIGUE: icono pequeño + título y una línea de apoyo. Es una línea
  /// de estado, no una tarjeta: no debe competir con la foto de la portada.
  Widget _heroNextLine({
    required IconData icon,
    required Color tint,
    required String title,
    required String hint,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 27,
          height: 27,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: .14),
            shape: BoxShape.circle,
            border: Border.all(color: tint.withValues(alpha: .30)),
          ),
          child: Icon(icon, size: 13, color: tint),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .60),
                  fontSize: 10.5,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== Servicios ====================

  /// ¿Este servicio tiene encendido «Elegir fotos» y una carpeta compartida?
  static bool _photoService(Map<String, dynamic> s) =>
      s['pickPhotos'] == true &&
      (s['shareFolder'] ?? '').toString().trim().isNotEmpty;

  /// Fotos que el cliente ya eligió en este servicio.
  static int _items(Map<String, dynamic> s) =>
      (s['items'] as num?)?.toInt() ?? 0;

  /// ¿Ya puede abrir la carpeta del servicio? («Abrir carpeta» encendido y
  /// una carpeta compartida asignada).
  static bool _canOpenFolder(Map<String, dynamic> s) =>
      s['showFolder'] != false &&
      (s['shareFolder'] ?? '').toString().trim().isNotEmpty;

  /// Peso de la tarjeta según lo que OFRECE: primero los servicios cuyo único
  /// botón es «Abrir carpeta» (lo más simple), después los que además tienen
  /// fotos («Ver fotos» / «Elegir fotos») y al final los que no ofrecen nada.
  static int _actionRank(Map<String, dynamic> s) {
    final photos = _photoService(s);
    final folder = _canOpenFolder(s);
    if (folder && !photos) return 0;
    if (photos) return 1;
    return 2;
  }

  static String _serviceName(Map<String, dynamic> s) =>
      ((s['service'] is Map
              ? ((s['service'] as Map)['name'] ?? '')
              : ''))
          .toString();

  /// Ordena una etapa: primero por su criterio, y a igualdad por nombre.
  List<Map<String, dynamic>> _sorted(
    Iterable<Map<String, dynamic>> list,
    int Function(Map<String, dynamic> a, Map<String, dynamic> b) compare,
  ) {
    final out = list.toList()
      ..sort((a, b) {
        final byRank = compare(a, b);
        if (byRank != 0) return byRank;
        return _serviceName(
          a,
        ).toLowerCase().compareTo(_serviceName(b).toLowerCase());
      });
    return out;
  }

  static int _statusOrder(Map<String, dynamic> s) {
    final id = _statusId(s);
    if (id == 1) return 0; // Pendiente primero
    if (id == 2) return 1; // En proceso
    return 2;
  }

  bool _matchesService(Map<String, dynamic> s) {
    final q = _serviceQuery.trim().toLowerCase();
    final done = _isDone(s);
    if (_serviceFilter == 'fotos' && !_photoService(s)) return false;
    if (_serviceFilter == 'pendientes' && done) return false;
    if (_serviceFilter == 'completados' && !done) return false;
    if (q.isEmpty) return true;
    final svc = (s['service'] is Map)
        ? (s['service'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final hay = '${svc['name'] ?? ''} ${s['description'] ?? ''}'.toLowerCase();
    return hay.contains(q);
  }

  Widget _servicesSection(
    ColorScheme scheme,
    List<Map<String, dynamic>> services,
  ) {
    final doneCount = services.where(_isDone).length;
    final visible = services.where(_matchesService).toList();

    // ORDEN de cada etapa (lo que el cliente puede hacer ya, primero):
    //   * «Elige tus fotos»: los que todavía NO tienen selección (le toca a
    //     él), después los que ya eligieron y solo esperan enviarlas.
    //   * «En proceso»: primero los que ya pueden ABRIR su carpeta.
    //   * «Completados»: primero los que pueden abrir carpeta y, después, los
    //     que ya tienen fotos seleccionadas.
    final photos = _sorted(
      visible.where((s) => !_isDone(s) && _photoService(s)),
      (a, b) {
        final ra = _actionRank(a);
        final rb = _actionRank(b);
        if (ra != rb) return ra.compareTo(rb);
        return (_items(a) == 0 ? 0 : 1).compareTo(_items(b) == 0 ? 0 : 1);
      },
    );
    final pending = _sorted(
      visible.where((s) => !_isDone(s) && !_photoService(s)),
      (a, b) {
        final ra = _actionRank(a);
        final rb = _actionRank(b);
        if (ra != rb) return ra.compareTo(rb);
        return _statusOrder(a).compareTo(_statusOrder(b));
      },
    );
    final completed = _sorted(
      visible.where(_isDone),
      (a, b) {
        final ra = _actionRank(a);
        final rb = _actionRank(b);
        if (ra != rb) return ra.compareTo(rb);
        return (_items(a) > 0 ? 0 : 1).compareTo(_items(b) > 0 ? 0 : 1);
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          scheme,
          Icons.checklist_rounded,
          'Tus servicios',
          trailing: '$doneCount de ${services.length} cumplidos',
        ),
        const SizedBox(height: 12),
        HsSearchFilterBar(
          hint: 'Buscar un servicio…',
          initial: _serviceQuery,
          onChanged: (v) => setState(() => _serviceQuery = v),
          groups: [
            HsFilterGroup(
              id: 'estado',
              title: 'Estado del servicio',
              help: 'Los servicios con «Elegir fotos» aparecen siempre arriba.',
              options: [
                HsFilterOption(
                  value: '',
                  label: 'Todos los servicios',
                  count: services.length,
                  icon: Icons.apps_rounded,
                ),
                HsFilterOption(
                  value: 'fotos',
                  label: 'Puedo elegir fotos',
                  count: services.where(_photoService).length,
                  icon: Icons.photo_library_outlined,
                  color: const Color(0xFF2F6BFF),
                ),
                HsFilterOption(
                  value: 'pendientes',
                  label: 'Todavía en proceso',
                  count: services.length - doneCount,
                  icon: Icons.pending_actions_outlined,
                  color: const Color(0xFF3B82F6),
                ),
                HsFilterOption(
                  value: 'completados',
                  label: 'Completados',
                  count: doneCount,
                  icon: Icons.task_alt_rounded,
                  color: _doneColor,
                ),
              ],
            ),
          ],
          selected: {'estado': _serviceFilter},
          onApply: (filters) =>
              setState(() => _serviceFilter = filters['estado'] ?? ''),
        ),
        const SizedBox(height: 14),
        if (visible.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: .25),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: .45),
              ),
            ),
            child: Text(
              'Ningún servicio coincide con la búsqueda o el filtro.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          )
        else ...[
          // LÍNEA DE TIEMPO: la etapa que ESPERA al cliente va primero y
          // resaltada; después lo que está en marcha y al final lo cumplido.
          if (photos.isNotEmpty)
            _serviceGroup(
              scheme,
              title: 'Elige tus fotos',
              subtitle: 'Te toca a ti: marca tus favoritas.',
              icon: Icons.photo_library_outlined,
              accent: const Color(0xFF2F6BFF),
              services: photos,
              highlight: true,
            ),
          if (pending.isNotEmpty)
            _serviceGroup(
              scheme,
              title: 'En proceso',
              subtitle: 'Lo que estamos preparando. Arriba, lo que ya puedes '
                  'abrir.',
              icon: Icons.pending_actions_outlined,
              accent: const Color(0xFF3B82F6),
              services: pending,
            ),
          if (completed.isNotEmpty)
            _serviceGroup(
              scheme,
              title: 'Completados',
              subtitle: 'Ya entregado. Arriba, con carpeta y con tus fotos.',
              icon: Icons.task_alt_rounded,
              accent: _doneColor,
              services: completed,
            ),
        ],
      ],
    );
  }

  /// Un TRAMO de la línea de tiempo: el nodo de la etapa (icono, título,
  /// cuántos servicios) y, colgando del riel, sus tarjetas.
  ///
  /// El riel se pinta con un [Stack] detrás del contenido y no empieza en el
  /// borde de arriba sino DEBAJO del nodo: así cada etapa continúa el trazo de
  /// la anterior sin cortes, sin necesidad de medir alturas.
  Widget _serviceGroup(
    ColorScheme scheme, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required List<Map<String, dynamic>> services,
    bool highlight = false,
  }) {
    final content = Stack(
      children: [
        // Riel de la línea de tiempo.
        Positioned(
          left: 12,
          top: 27,
          bottom: 2,
          child: Container(
            width: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accent.withValues(alpha: .40),
                  accent.withValues(alpha: .06),
                ],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nodo de la etapa (la etapa urgente va rellena).
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: highlight
                        ? accent
                        : accent.withValues(alpha: .13),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accent.withValues(alpha: highlight ? .95 : .42),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: 13,
                    color: highlight ? Colors.white : accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 3,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: highlight ? accent : scheme.onSurface,
                              ),
                            ),
                            _stageCount(accent, services.length),
                            if (highlight) _stageBadge(accent, 'TE TOCA'),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.3,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final s in services)
              Padding(
                padding: const EdgeInsets.only(left: 34),
                child: _serviceCard(scheme, s),
              ),
            const SizedBox(height: 4),
          ],
        ),
      ],
    );

    // La etapa que ESPERA al cliente se destaca con un fondo tenue: es donde
    // tiene que entrar, y así se ve sin leer una sola línea.
    if (!highlight) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: content,
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(8, 12, 6, 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: .24)),
      ),
      child: content,
    );
  }

  /// Pastilla con cuántos servicios tiene la etapa.
  Widget _stageCount(Color accent, int count) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      '$count',
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: accent,
      ),
    ),
  );

  /// Etiqueta «TE TOCA» de la etapa urgente.
  Widget _stageBadge(Color accent, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
    decoration: BoxDecoration(
      color: accent,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 8.5,
        letterSpacing: .6,
        fontWeight: FontWeight.w900,
        color: Colors.white,
      ),
    ),
  );

  Widget _serviceCard(ColorScheme scheme, Map<String, dynamic> s) {
    final svc = (s['service'] is Map)
        ? (s['service'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final name = (svc['name'] ?? 'Servicio').toString();
    final note = (s['description'] ?? '').toString().trim();
    final shareFolder = (s['shareFolder'] ?? '').toString().trim();
    final shareLink = (s['shareLink'] ?? '').toString().trim();
    final showFolder = s['showFolder'] != false;
    final photosMax =
        (s['photosMax'] as num?)?.toInt() ??
        (svc['photosMax'] as num?)?.toInt() ??
        0;
    final pickOn =
        s['pickPhotos'] == true &&
        HsAccess.instance.canUseDrive &&
        shareFolder.isNotEmpty;
    final canPick = _photoService(s);
    final items = (s['items'] as num?)?.toInt() ?? 0;
    final printStatus = (s['printStatus'] ?? '').toString().trim();
    final sentToPrint = s['sentToPrint'] == true || printStatus.isNotEmpty;
    final done = _isDone(s);
    final progress = _isInProgress(s);
    // Lo CUMPLIDO va en VERDE (antes azul, igual que "en proceso": no se
    // distinguía de un vistazo qué estaba terminado).
    final color = done
        ? _doneColor
        : progress
        ? const Color(0xFF3B82F6)
        : const Color(0xFFD97706);
    final statusLabel = done
        ? 'Cumplido'
        : progress
        ? 'En proceso'
        : (_statusName(s).isEmpty ? 'Pendiente' : _statusName(s));

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        // MISMA receta en todas las etapas: cristal translúcido teñido con el
        // color del estado. Antes solo las cumplidas dejaban ver el fondo (las
        // demás eran opacas) y la lista se veía a parches; el velo del fondo
        // de la vista mantiene el texto legible.
        color: Color.alphaBlend(
          color.withValues(alpha: .07),
          scheme.surface.withValues(alpha: .55),
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: .20)),
                  ),
                  child: Icon(
                    serviceIconOf((svc['icon'] ?? '').toString()),
                    size: 20,
                    color: color,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.2,
                                fontWeight: FontWeight.w800,
                                color: done ? scheme.onSurfaceVariant : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.3,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (canPick) ...[
                        const SizedBox(height: 8),
                        // Panel de la selección de fotos: el avance se lee de
                        // un vistazo (cuántas llevas y su barra), en el mismo
                        // azul de la app que el resto de las acciones.
                        Container(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2F6BFF)
                                .withValues(alpha: .07),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF2F6BFF)
                                  .withValues(alpha: .24),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.photo_library_outlined,
                                    size: 14,
                                    color: Color(0xFF2F6BFF),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      items == 0
                                          ? (photosMax > 0
                                                ? 'Puedes elegir hasta '
                                                      '$photosMax fotos'
                                                : 'Puedes elegir tus fotos')
                                          : photosMax > 0
                                          ? '$items de $photosMax fotos '
                                                'elegidas'
                                          : "$items "
                                                '${items == 1 ? 'foto elegida' : 'fotos elegidas'}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF2F6BFF),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (photosMax > 0) ...[
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(99),
                                  child: LinearProgressIndicator(
                                    value: (items / photosMax).clamp(0.0, 1.0),
                                    minHeight: 5,
                                    color: const Color(0xFF2F6BFF),
                                    backgroundColor: const Color(0xFF2F6BFF)
                                        .withValues(alpha: .16),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (pickOn ||
              (showFolder && shareFolder.isNotEmpty) ||
              shareLink.isNotEmpty) ...[
            const Divider(height: 1),
            _serviceActions(
              scheme: scheme,
              service: s,
              name: name,
              pickOn: pickOn,
              sentToPrint: sentToPrint,
              items: items,
              printStatus: printStatus,
              showFolder: showFolder,
              shareFolder: shareFolder,
              shareLink: shareLink,
            ),
          ],
        ],
      ),
    );
  }

  /// Acciones de un servicio («Ver/Elegir fotos», «Enviar», «Abrir carpeta»).
  ///
  /// En el CELULAR van una debajo de otra: antes el Wrap las partía donde
  /// cabía y quedaban desordenadas (una angosta al lado de otra ancha). Ahora
  /// «Elegir/Ver fotos» y «Abrir carpeta» comparten fila, «Enviar» va debajo
  /// a lo ancho y el aviso dice solo «Enviadas». En escritorio se conserva el
  /// Wrap de siempre.
  Widget _serviceActions({
    required ColorScheme scheme,
    required Map<String, dynamic> service,
    required String name,
    required bool pickOn,
    required bool sentToPrint,
    required int items,
    required String printStatus,
    required bool showFolder,
    required String shareFolder,
    required String shareLink,
  }) {
    final compact = MediaQuery.sizeOf(context).width < 620;
    final pick = pickOn
        ? FilledButton.icon(
            onPressed: () => _pickServiceItems(service, name),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            icon: Icon(
              sentToPrint
                  ? Icons.lock_outline_rounded
                  : items > 0
                  ? Icons.check_circle_outline_rounded
                  : Icons.photo_library_outlined,
              size: 16,
            ),
            label: Text(
              sentToPrint
                  ? 'Ver fotos ($items)'
                  : items > 0
                  ? 'Mis fotos ($items)'
                  : 'Elegir fotos',
            ),
          )
        : null;
    final send = pickOn && items > 0 && !sentToPrint
        ? OutlinedButton.icon(
            onPressed: () => _sendToPrint(service, name),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              textStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Enviar a impresión'),
          )
        : null;
    final chip = sentToPrint
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.warn.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.warn.withValues(alpha: .38)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  printStatus == 'finished'
                      ? Icons.task_alt_rounded
                      : Icons.print_outlined,
                  size: 14,
                  color: AppColors.warn,
                ),
                const SizedBox(width: 5),
                Text(
                  printStatus == 'finished'
                      ? (compact ? 'Terminada' : 'Impresión terminada')
                      : (compact ? 'Enviadas' : 'Enviadas a impresión'),
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.warn,
                  ),
                ),
              ],
            ),
          )
        : null;
    final folder = showFolder && shareFolder.isNotEmpty
        ? OutlinedButton.icon(
            onPressed: () => _openShared(shareFolder),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              textStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: .8),
              ),
            ),
            icon: const Icon(Icons.folder_open_outlined, size: 16),
            label: const Text('Abrir carpeta'),
          )
        : null;
    final link = shareLink.isNotEmpty
        ? TextButton.icon(
            onPressed: () => _openLink(shareLink),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              textStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            icon: const Icon(Icons.link, size: 15),
            label: const Text('Ver liga'),
          )
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pick != null && folder != null)
                  Row(
                    children: [
                      Expanded(child: pick),
                      const SizedBox(width: 8),
                      Expanded(child: folder),
                    ],
                  )
                else if (pick != null)
                  SizedBox(width: double.infinity, child: pick)
                else if (folder != null)
                  SizedBox(width: double.infinity, child: folder),
                if (send != null) ...[const SizedBox(height: 8), send],
                if (chip != null) ...[
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerLeft, child: chip),
                ],
                if (link != null) ...[
                  const SizedBox(height: 2),
                  Align(alignment: Alignment.centerLeft, child: link),
                ],
              ],
            )
          : Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [?pick, ?send, ?chip, ?folder, ?link],
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
              Icon(
                Icons.folder_copy_outlined,
                size: 26,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Aún no se te comparte ninguna carpeta del Drive. Tu '
                  'fotógrafo la asigna al paquete desde el administrador del '
                  'paquete y aquí aparecerá tu acceso directo.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: scheme.onSurfaceVariant,
                  ),
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
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final s in shared)
              ListTile(
                dense: true,
                leading: Icon(
                  Icons.folder_shared_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
                title: Text(
                  (s['packageName'] ?? '').toString().isEmpty
                      ? 'Carpeta compartida'
                      : (s['packageName'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  (s['path'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
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
                    size: 18,
                  ),
                  label: Text(
                    ownDrivePathOf(links.first.$2) != null
                        ? 'Entrar a mi Drive'
                        : 'Copiar enlace del Drive',
                  ),
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
                title: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                trailing: TextButton(
                  onPressed: () => _openLink(url),
                  child: Text(ownDrivePathOf(url) != null ? 'Abrir' : 'Copiar'),
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

/// La FOTO del paquete en «Mi paquete»: la del Drive (miniatura), un enlace
/// externo, o el hueco con el emoji de la categoría sobre el degradado del
/// tier cuando el paquete todavía no tiene foto.
class _PackagePhoto extends StatelessWidget {
  const _PackagePhoto({
    required this.url,
    required this.tier,
    required this.emoji,
    this.big = false,
    this.alignment = Alignment.center,
    this.waiting,
  });

  final String url;
  final HsTierLook tier;
  final String emoji;
  final bool big;

  /// Qué parte de la foto se ve cuando se recorta (la foto siempre llena el
  /// espacio con `cover`). En el banner va un poco hacia arriba.
  final Alignment alignment;

  /// Qué enseñar MIENTRAS la foto carga o si falla. `null` = el hueco con el
  /// emoji sobre el degradado del tier.
  final Widget? waiting;

  /// La MISMA imagen que pinta este widget, ya resuelta: el banner la deja
  /// lista en la caché antes del fundido y de ella sale el fondo de la vista.
  static ImageProvider? providerFor(String url, {bool big = false}) {
    final clean = url.trim();
    if (clean.isEmpty) return null;
    return NetworkImage(_source(clean, big: big));
  }

  /// URL final de la foto: la vista previa del Drive o la liga tal cual.
  static String _source(String clean, {required bool big}) =>
      isDriveImageUrl(clean)
      ? driveImagePreview(clean, width: big ? 1200 : 240)
      : clean;

  @override
  Widget build(BuildContext context) {
    final fallback = _PackagePhotoFallback(tier: tier, emoji: emoji, big: big);
    final wait = waiting ?? fallback;
    final clean = url.trim();
    if (clean.isEmpty) return fallback;
    if (isDriveImageUrl(clean)) {
      return DriveThumb(
        source: _source(clean, big: big),
        isRemote: true,
        big: big,
        rounded: false,
        alignment: alignment,
      );
    }
    return Image.network(
      clean,
      fit: BoxFit.cover,
      alignment: alignment,
      errorBuilder: (_, _, _) => wait,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : wait,
    );
  }
}

class _PackagePhotoFallback extends StatelessWidget {
  const _PackagePhotoFallback({
    required this.tier,
    required this.emoji,
    required this.big,
  });

  final HsTierLook tier;
  final String emoji;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: tier.gradient, color: tier.dark),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: -30,
            top: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tier.accent.withValues(alpha: .10),
              ),
            ),
          ),
          Positioned(
            left: -40,
            bottom: -50,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .04),
              ),
            ),
          ),
          Center(
            child: Text(emoji, style: TextStyle(fontSize: big ? 62 : 26)),
          ),
        ],
      ),
    );
  }
}

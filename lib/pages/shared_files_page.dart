import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app_platform.dart';
import '../drive_base.dart';
import '../hs_api.dart';
import '../hs_format.dart';
import '../local_share_agent.dart';
import '../local_share_service.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/common.dart';
import '../widgets/drive_thumb.dart';
import '../widgets/hs_modal.dart';
import '../widgets/hs_toast.dart';
import 'drive_page.dart' show showDriveImageViewer;

/// Selector de carpeta LOCAL de la computadora. En pruebas se sobreescribe:
/// el diálogo del sistema no se puede manejar desde un widget test.
@visibleForTesting
Future<String?> Function()? debugPickLocalFolder;

/// Servicio de las carpetas LOCALES compartidas (endpoints /api/local/*).
/// En pruebas se puede sustituir por uno con un cliente HTTP falso.
@visibleForTesting
LocalShareService Function()? debugLocalShareService;

// ==================================================================
// MÓDULO "ARCHIVOS COMPARTIDOS"
// ==================================================================
// Un usuario comparte UNA carpeta de SU computadora (o de su Drive) con OTROS
// usuarios. Es INDEPENDIENTE del Drive de los paquetes: aquí no hay clientes
// ni paquetes, solo personas que comparten carpetas entre sí.
//
//   * Lo que YO comparto  -> UNA CARPETA DE MI COMPUTADORA (ruta local: se
//     elige con el diálogo del sistema), con la lista de quiénes la reciben.
//     La MISMA carpeta se comparte a VARIOS usuarios (se puede volver a entrar
//     para sumar o quitar gente).
//   * Lo que me comparten -> las carpetas de otros, con el nombre de quién las
//     comparte. Se ven y se descargan AQUÍ MISMO (solo lectura): este módulo
//     es INDEPENDIENTE del módulo Archivos y NUNCA salta a él.
//
// Las carpetas compartidas se navegan siempre DENTRO de este módulo, den igual
// de dónde vengan: de la computadora del dueño (ruta local absoluta) o de SU
// Drive del servidor (ruta relativa). Las dos las sirve el servidor del drive
// con los endpoints /api/local/* a partir del compartido (solo lectura).
//
// El DISEÑO es el del Drive, a propósito: mismo encabezado con el buscador y
// el conmutador de vista, mismas migas de pan, misma cuadrícula/lista con
// tarjetas y el MISMO visor de imágenes (zoom, flechas, Esc, descargar). La
// única diferencia es que no hay acciones de escritura: estas carpetas son de
// solo lectura y así lo dice la franja de aviso.
//
// ESCRITORIO: se puede compartir y recibir. MÓVIL: solo se ve lo recibido;
// compartir exige elegir una carpeta del equipo (la app lo dice en vez de
// ofrecer un botón que no puede funcionar).
// ==================================================================

/// Vista de las carpetas que me comparten (misma idea que en el Drive).
enum _SharedView { shared, mine }

class SharedFilesPage extends StatefulWidget {
  const SharedFilesPage({super.key});

  @override
  State<SharedFilesPage> createState() => _SharedFilesPageState();
}

class _SharedFilesPageState extends State<SharedFilesPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _shared = const [];
  List<Map<String, dynamic>> _received = const [];
  List<Map<String, dynamic>> _candidates = const [];
  bool _canShare = true;
  bool _canDelete = true;

  /// Cuadrícula (por defecto, como el Drive) o lista.
  bool _grid = true;

  /// Sección que se está viendo: lo que me comparten o lo que yo comparto.
  _SharedView _view = _SharedView.shared;

  /// CARPETA ABIERTA dentro de la sección: null = raíz (el listado).
  Map<String, dynamic>? _open;

  /// Subcarpeta dentro de una carpeta LOCAL recibida.
  List<String> _localPath = const [];

  /// Contenido de la carpeta compartida abierta.
  List<LocalShareItem> _localItems = const [];
  bool _localLoading = false;
  String? _localError;

  /// ESTADO de cada compartido (servidor / computadora del dueño / apagada).
  /// Es lo que deja VER, desde el listado, si una carpeta está funcionando
  /// ahora mismo, sin tener que abrirla para descubrirlo.
  final Map<int, LocalShareStatus> _statuses = {};

  /// Último listado de estados pedido (para descartar respuestas viejas).
  int _statusTicket = 0;

  /// Estado del compartido ABIERTO (para explicar su contenido).
  LocalShareStatus? _openStatus;

  /// Último listado pedido dentro de la carpeta abierta (ver [_loadLocal]).
  int _localTicket = 0;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// En MÓVIL el módulo es de SOLO LECTURA: compartir exige elegir una carpeta
  /// del equipo y eso se hace en la computadora.
  bool get _readOnly => isAndroidPlatform || useLongPressDrag;

  bool get _inside => _open != null;

  /// El filtro del buscador (solo aplica al listado, no dentro de una carpeta:
  /// ahí se navega, igual que en el Drive).
  String? get _filter {
    final q = _searchController.text.trim().toLowerCase();
    return q.isEmpty ? null : q;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // Datos
  // ---------------------------------------------------------------

  Future<void> _load() async {
    // Si el usuario dejó el servicio ENCENDIDO en el switch, se enciende ya
    // (aunque ahora mismo no haya ninguna carpeta compartida a la vista).
    LocalShareAgent.instance.loadManualPreference();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await HsApi.sharedFiles();
      if (!mounted) return;
      setState(() {
        _shared = data.shared;
        _received = data.received;
        _candidates = data.candidates;
        _canShare = data.canShare;
        _canDelete = data.canDelete;
        _loading = false;
      });
      // El AGENTE que sirve mis carpetas de ESTA computadora se enciende (o se
      // apaga) con el listado: compartir una carpeta ya la deja disponible, sin
      // pasos extra, y al dejar de compartir la última se apaga solo.
      // El AGENTE que sirve mis carpetas de ESTA computadora se enciende (o se
      // apaga) con el listado: compartir una carpeta ya la deja disponible, sin
      // pasos extra, y al dejar de compartir la última se apaga solo….
      //
      // …SALVO que el usuario lo haya encendido a mano en el switch: entonces
      // sigue encendido, que es justo lo que pidió al encenderlo.
      if (!_readOnly) {
        if (data.shared.any((s) => s['local'] == true) ||
            LocalShareAgent.instance.manualOn) {
          LocalShareAgent.instance.start();
        } else {
          LocalShareAgent.instance.stop();
        }
      }
      // Y se pregunta al servidor del drive de dónde se sirve CADA carpeta:
      // así el listado muestra "Disponible" / "En tu computadora" / "Apagada"
      // en vez de dejar la duda hasta que se abre.
      unawaited(_refreshStatuses());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar los archivos compartidos';
        _loading = false;
      });
    }
  }

  /// Pregunta al servidor del drive el estado de TODOS los compartidos del
  /// listado (los míos y los recibidos) y lo guarda para pintarlo.
  ///
  /// Va aparte del listado a propósito: si el servidor del drive no contesta,
  /// el módulo sigue funcionando (solo se queda sin el estado).
  Future<void> _refreshStatuses() async {
    final ticket = ++_statusTicket;
    final ids = <int>{
      for (final s in _shared) (s['id'] as num?)?.toInt() ?? 0,
      for (final r in _received) (r['shareId'] as num?)?.toInt() ?? 0,
    }..removeWhere((id) => id <= 0);
    if (ids.isEmpty) {
      if (!mounted) return;
      setState(_statuses.clear);
      return;
    }
    final out = <int, LocalShareStatus>{};
    for (final id in ids) {
      out[id] = await _local.status(id);
    }
    if (!mounted || ticket != _statusTicket) return;
    setState(() {
      _statuses
        ..clear()
        ..addAll(out);
      if (_open != null) _openStatus = out[_shareIdOf(_open!)];
    });
  }

  /// Id del compartido de una entrada del listado (fila mía o recibida).
  int _shareIdOf(Map<String, dynamic> entry) =>
      (entry['shareId'] as num?)?.toInt() ??
      (entry['id'] as num?)?.toInt() ??
      0;

  /// Estado guardado de una entrada (null = todavía sin comprobar).
  LocalShareStatus? _statusOf(Map<String, dynamic> entry) =>
      _statuses[_shareIdOf(entry)];

  /// ¿Puedo compartir desde aquí? (escritorio + permiso del rol).
  bool get _canPickFolder => !_readOnly && _canShare;

  /// ¿Puedo dejar de compartir? (permiso del rol).
  bool get _canUnshare => _canDelete;

  LocalShareService get _local =>
      debugLocalShareService?.call() ?? LocalShareService();

  /// Una entrada por CARPETA recibida (la API manda una fila por dueño).
  List<Map<String, dynamic>> get _receivedFolders {
    final out = <Map<String, dynamic>>[];
    for (final r in _received) {
      final path = '${r['path'] ?? ''}';
      final i = out.indexWhere((o) => '${o['path']}' == path);
      if (i < 0) {
        out.add({
          ...r,
          'owners': List<Map<String, dynamic>>.from(
            ((r['owners'] as List?) ?? const []).whereType<Map>().map(
              (e) => e.cast<String, dynamic>(),
            ),
          ),
        });
      } else {
        final owners = (out[i]['owners'] as List).cast<Map<String, dynamic>>();
        for (final o in ((r['owners'] as List?) ?? const []).whereType<Map>()) {
          final m = o.cast<String, dynamic>();
          if (!owners.any((x) => x['id'] == m['id'])) owners.add(m);
        }
      }
    }
    return out;
  }

  /// Una entrada por CARPETA mía (la API manda una fila por destinatario).
  List<Map<String, dynamic>> get _myFolders {
    final out = <Map<String, dynamic>>[];
    for (final s in _shared) {
      final path = '${s['path'] ?? ''}';
      final i = out.indexWhere((o) => '${o['path']}' == path);
      if (i < 0) {
        // El [shareId] (id de la fila del compartido) es lo que abre la
        // carpeta aquí mismo: con él se pide su contenido al servidor.
        out.add({
          ...s,
          'shareId': s['id'],
          'targets': <Map<String, dynamic>>[s],
        });
      } else {
        (out[i]['targets'] as List).add(s);
      }
    }
    return out;
  }

  /// ¿Coincide con el buscador? (nombre de la carpeta, ruta o persona).
  bool _matches(String haystack) {
    final q = _filter;
    if (q == null) return true;
    return haystack.toLowerCase().contains(q);
  }

  // ---------------------------------------------------------------
  // Navegación
  // ---------------------------------------------------------------

  /// Abre una carpeta recibida: navega su contenido aquí mismo (solo lectura).
  void _openReceived(Map<String, dynamic> r) => _openFolder(r);

  /// Abre el detalle de una carpeta MÍA: a quiénes se la compartí y, debajo,
  /// su contenido (solo lectura).
  void _openMine(Map<String, dynamic> m) => _openFolder(m);

  /// Abre una carpeta compartida DENTRO del módulo (nunca salta a Archivos).
  void _openFolder(Map<String, dynamic> entry) {
    setState(() {
      _open = entry;
      _openStatus = _statusOf(entry);
      _localPath = const [];
      _localItems = const [];
      _localError = null;
      _searchController.clear();
    });
    _loadLocal();
  }

  Future<void> _loadLocal() async {
    final r = _open;
    final shareId = (r?['shareId'] as num?)?.toInt() ?? 0;
    if (r == null) return;
    // Ticket del listado: si mientras cargaba el usuario se fue a otra carpeta
    // (o a otro compartido), la respuesta vieja NO se pinta encima de la
    // nueva: se descarta.
    final ticket = ++_localTicket;
    if (shareId <= 0) {
      // Sin compartido no hay a quién pedirle el contenido: se dice, en vez de
      // dejar la carpeta girando para siempre.
      setState(() {
        _localLoading = false;
        _localItems = const [];
        _localError = 'No se pudo identificar la carpeta compartida';
      });
      return;
    }
    setState(() {
      _localLoading = true;
      _localError = null;
    });
    try {
      // La carpeta puede estar en la computadora del dueño: si su app no está
      // abierta, se EXPLICA (en vez de dejar un error crudo del servidor).
      final status = await _local.status(shareId);
      if (!mounted || ticket != _localTicket) return;
      setState(() => _openStatus = status);
      if (status.servedFrom == 'offline') {
        setState(() {
          _localItems = const [];
          _localLoading = false;
          _localError =
              'Esa carpeta está en la computadora de quien la '
              'comparte: se abre cuando su aplicación esté abierta';
        });
        return;
      }
      // El servidor CONTESTÓ que no puede servirla (el compartido se dio de
      // baja, no tiene base de datos…): se explica en pantalla, en vez de
      // intentar abrirla para que falle con un error crudo.
      if (status.servedFrom == 'unavailable') {
        final why = status.detail?.trim() ?? '';
        setState(() {
          _localItems = const [];
          _localLoading = false;
          _localError = why.isEmpty
              ? 'El servidor del drive no pudo abrir esta carpeta compartida'
              : why;
        });
        return;
      }
      // El servidor del drive no puede resolver el compartido (base de datos
      // sin configurar, o compartido dado de baja): se dice tal cual, con la
      // explicación que manda el servidor.
      if (status.servedFrom == 'unknown' &&
          status.hasDatabase == false &&
          status.detail != null) {
        setState(() {
          _localItems = const [];
          _localLoading = false;
          _localError = status.detail;
        });
        return;
      }
      final data = await _local.list(shareId, _localPath);
      if (!mounted || ticket != _localTicket) return;
      setState(() {
        _localItems = data.items;
        _localLoading = false;
      });
      // Las miniaturas se dejan pedidas ya: al abrir la carpeta se ve la
      // cuadrícula con las fotos en vez de ir apareciendo una por una.
      _warmThumbs(data.items);
    } catch (e) {
      if (!mounted || ticket != _localTicket) return;
      setState(() {
        _localError = '$e';
        _localLoading = false;
      });
    }
  }

  /// Enciende o apaga el SERVICIO DE COMPARTIR (el switch de la tarjeta).
  ///
  /// Encendido, la app sirve las carpetas de ESTA computadora mientras el
  /// panel esté abierto (y lo recuerda para la próxima vez); apagado, los demás
  /// solo verán "Apagada ahora" aunque la carpeta siga compartida.
  Future<void> _setServing(bool on) async {
    final ok = await LocalShareAgent.instance.setManual(on);
    if (!mounted) return;
    if (!ok) {
      // Esta plataforma no puede servir carpetas de la computadora: se dice,
      // en vez de dejar un switch que parece no obedecer.
      HsToast.info(
        'No se puede desde aquí',
        details: _shareProblemText(ShareProblem.unsupported),
      );
      setState(() {});
      return;
    }
    if (on) {
      HsToast.success(
        'Servicio de compartir encendido',
        details:
            'Tu computadora sirve tus carpetas mientras el panel esté '
            'abierto.',
      );
    } else {
      HsToast.info(
        'Servicio de compartir apagado',
        details: 'Tus carpetas de esta computadora dejan de verse.',
      );
    }
    // El estado de cada carpeta cambia al encender o apagar el servicio.
    unawaited(_refreshStatuses());
    setState(() {});
  }

  /// Por qué el servicio de compartir NO está sirviendo (o por qué puede no
  /// servir) dicho en claro. "No me deja prender el switch" casi siempre
  /// tiene un motivo concreto: la app en el navegador, el servidor del drive
  /// sin sesión/base de datos, o un servidor viejo sin los endpoints.
  static String? _shareProblemText(ShareProblem? p) => switch (p) {
    ShareProblem.unsupported =>
      'Desde el navegador (o el celular) no se '
          'pueden servir carpetas de esta computadora: abre el panel en la '
          'app de escritorio para compartirlas.',
    ShareProblem.session =>
      'El servidor del drive no reconoce tu sesión '
          '(contesta 401): sigue encendido y se reintenta, pero nadie verá '
          'tus carpetas hasta que el servidor del drive tenga su base de '
          'datos (DRIVE_DB) y tu sesión siga activa.',
    ShareProblem.oldServer =>
      'El servidor del drive todavía no trae los '
          'endpoints para servir carpetas de tu computadora (contesta 404): '
          'actualízalo (hardstreet-drive) para que tus carpetas se vean.',
    ShareProblem.server =>
      'El servidor del drive está contestando con '
          'errores (5xx): se sigue reintentando. Revisa que esté arriba.',
    null => null,
  };

  /// El switch del servicio en pantalla ANGOSTA: un botón de imagen con su
  /// tooltip (la tarjeta completa no cabe ahí sin desbordar el módulo).
  Widget _serviceSwitchButton(ColorScheme scheme, {required bool compact}) {
    final agent = LocalShareAgent.instance;
    return ListenableBuilder(
      // El servicio se enciende y se apaga SOLO (sesión, servidor viejo): hay
      // que enterarse de las dos cosas, el estado y el motivo.
      listenable: Listenable.merge([agent.serving, agent.problem]),
      builder: (context, _) {
        final on = agent.serving.value;
        final tint = on ? AppColors.ok : AppColors.warn;
        return Tooltip(
          message: !agent.supported
              ? 'Servicio de compartir: solo desde la app de escritorio'
              : on
              ? 'Servicio de compartir ENCENDIDO: tu computadora sirve '
                    'tus carpetas mientras el panel esté abierto. Toca para '
                    'apagarlo.'
              : 'Servicio de compartir APAGADO: tus carpetas de esta '
                    'computadora no se sirven. Toca para encenderlo.',
          child: IconButton.filledTonal(
            key: const ValueKey('share-service-switch-compact'),
            onPressed: agent.supported ? () => _setServing(!on) : null,
            icon: Icon(
              on
                  ? Icons.wifi_tethering_rounded
                  : Icons.wifi_tethering_off_rounded,
              color: tint,
            ),
          ),
        );
      },
    );
  }

  /// El SWITCH del servicio: dice si la app está sirviendo AHORA MISMO las
  /// carpetas de esta computadora y lo enciende o lo apaga.
  Widget _serviceCard(ColorScheme scheme) {
    final agent = LocalShareAgent.instance;
    final local = _myFolders.where((f) => f['local'] == true).length;
    return ListenableBuilder(
      listenable: Listenable.merge([agent.serving, agent.problem]),
      builder: (context, _) {
        final on = agent.serving.value;
        final tint = on ? AppColors.ok : AppColors.warn;
        // Sin soporte (navegador/celular) NO se describe el apagado: lo único
        // que hay que leer es el motivo, que ya dice qué hacer.
        final detail = !agent.supported
            ? ''
            : on
            ? (agent.served > 0
                  ? 'Tu computadora está sirviendo tus carpetas compartidas: ha '
                        'contestado ${agent.served} '
                        '${agent.served == 1 ? 'petición' : 'peticiones'}. '
                        'Sigue encendido mientras el panel esté abierto.'
                  : 'Tu computadora está lista para servir tus carpetas '
                        'compartidas mientras el panel esté abierto.')
            : (local > 0
                  ? 'Está apagado: lo que compartes de esta computadora '
                        '($local ${local == 1 ? 'carpeta' : 'carpetas'}) no se ve '
                        'hasta que lo enciendas.'
                  : 'Apagado: las carpetas de esta computadora no se sirven. '
                        'Enciéndelo cuando compartas una.');
        // Si el rol no puede compartir, se dice AQUÍ mismo: es lo primero que
        // hay que saber cuando "no me deja compartir".
        final permission = _canShare
            ? ''
            : ' Tu rol no tiene permiso para compartir carpetas: pídelo en el '
                  'módulo Roles.';
        // Y el motivo del servicio (si lo hay): es lo que explica por qué el
        // switch no sirve de nada aunque esté encendido.
        final hold = _shareProblemText(agent.problem.value);
        final problemLine = hold == null ? '' : ' $hold';
        return Container(
          // Clave estable: las pruebas (y los atajos) la usan para encontrar el
          // switch del servicio sin depender del diseño.
          key: const ValueKey('share-service-card'),
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: tint.withValues(alpha: .28)),
          ),
          child: Row(
            children: [
              Icon(
                on
                    ? Icons.wifi_tethering_rounded
                    : Icons.wifi_tethering_off_rounded,
                size: 20,
                color: tint,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Flexible(
                          child: Text(
                            'Servicio de compartir',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _ServingPill(
                          on: on,
                          tint: tint,
                          label: !agent.supported
                              ? 'No disponible'
                              : hold == null
                              ? null
                              : 'Con problemas',
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$detail$permission$problemLine',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              // Sin soporte (navegador/celular) el switch va DESHABILITADO y la
              // tarjeta dice por qué: un switch que no hace nada parecía roto.
              Switch.adaptive(
                value: on,
                onChanged: agent.supported ? (v) => _setServing(v) : null,
              ),
            ],
          ),
        );
      },
    );
  }

  void _enterLocalFolder(LocalShareItem item) {
    setState(() => _localPath = [..._localPath, item.name]);
    _loadLocal();
  }

  void _goUp() {
    if (_open == null) return;
    // Dentro de una carpeta compartida se sube nivel a nivel.
    if (_localPath.isNotEmpty) {
      setState(() => _localPath = _localPath.sublist(0, _localPath.length - 1));
      _loadLocal();
      return;
    }
    setState(() {
      _open = null;
      _localPath = const [];
      _localItems = const [];
      _localError = null;
    });
  }

  // ---------------------------------------------------------------
  // Visor y descarga de una carpeta LOCAL
  // ---------------------------------------------------------------

  /// Abre una imagen de la carpeta local en el MISMO visor del Drive.
  Future<void> _viewLocalImage(LocalShareItem item) async {
    final r = _open;
    final shareId = (r?['shareId'] as num?)?.toInt() ?? 0;
    if (shareId <= 0) return;
    final images = _localItems
        .where((i) => !i.isFolder)
        .map((i) => DriveItem(name: i.name, isFolder: false, size: i.size))
        .toList(growable: false);
    final index = images.indexWhere((i) => i.name == item.name);
    if (images.isEmpty) return;
    await showDriveImageViewer(
      context,
      drive: LocalShareDrive(
        service: _local,
        shareId: shareId,
        rel: _localPath,
      ),
      images: images,
      initialIndex: index < 0 ? 0 : index,
      onDownload: (it) => _downloadLocal(it.name),
    );
  }

  /// Descarga un archivo de la carpeta local (diálogo Guardar en escritorio,
  /// carpeta Descargas en Android, el navegador en web).
  Future<void> _downloadLocal(String name) async {
    final r = _open;
    final shareId = (r?['shareId'] as num?)?.toInt() ?? 0;
    if (shareId <= 0) return;
    try {
      final where = await _local.download(shareId, [..._localPath, name], name);
      if (where == null) return;
      HsToast.success(
        where.isEmpty ? 'Descargado: $name' : 'Descargado en $where',
      );
    } catch (e) {
      HsToast.error('No se pudo descargar "$name"', details: '$e');
    }
  }

  // ---------------------------------------------------------------
  // Acciones (compartir)
  // ---------------------------------------------------------------

  /// Compartir una carpeta NUEVA: se elige una CARPETA DE ESTA COMPUTADORA
  /// (aunque esté fuera del Drive) y luego a quiénes se la comparte.
  Future<void> _shareNewFolder() async {
    final picked = await _pickLocalFolder();
    if (picked == null || picked.trim().isEmpty || !mounted) return;
    await _editTargets(picked.trim());
  }

  /// Pide una carpeta del equipo con el diálogo del sistema y devuelve su
  /// ruta absoluta (p. ej. C:\Fotos). En Android no existe: el módulo allí es
  /// de solo lectura y nunca se llega aquí.
  Future<String?> _pickLocalFolder() async {
    final override = debugPickLocalFolder;
    if (override != null) return override();
    if (kWeb || isAndroidPlatform) {
      _snack('Elegir una carpeta del equipo solo funciona en la computadora');
      return null;
    }
    try {
      return await getDirectoryPath(
        confirmButtonText: 'Compartir esta carpeta',
      );
    } catch (e) {
      _snack('No se pudo abrir el selector de carpetas: $e');
      return null;
    }
  }

  /// Editar (sumar/quitar) los usuarios de una carpeta ya compartida.
  Future<void> _editTargets(String path) async {
    // Los que la tienen se piden al servidor: la lista en pantalla puede
    // estar vieja si alguien más compartió mientras tanto.
    var current = <int>[];
    var candidates = _candidates;
    try {
      final info = await HsApi.sharedFileTargets(path);
      current = info.targets;
      candidates = info.candidates;
    } catch (_) {
      // Si falla, se usa lo que ya hay en pantalla.
      current = _shared
          .where((s) => '${s['path']}' == path)
          .map((s) => (s['targetId'] as num?)?.toInt() ?? 0)
          .where((n) => n > 0)
          .toList();
    }
    if (!mounted) return;
    final chosen = await _showTargetsDialog(
      path: path,
      current: current,
      candidates: candidates,
    );
    if (chosen == null || !mounted) return;

    final toAdd = chosen.where((id) => !current.contains(id)).toList();
    final toRemove = current.where((id) => !chosen.contains(id)).toList();
    try {
      if (toAdd.isNotEmpty) {
        await HsApi.shareFolderWith(path: path, userIds: toAdd);
      }
      if (toRemove.isNotEmpty && _canDelete) {
        await HsApi.unshareFolderWith(path: path, userIds: toRemove);
      }
    } catch (_) {
      // El aviso de error ya lo mostró la capa de API.
    }
    await _load();
  }

  /// Quitar TODOS los usuarios de una carpeta (deja de compartirse).
  Future<void> _unshareAll(String path, List<int> targets) async {
    if (targets.isEmpty) return;
    final ok = await showHsModal<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Dejar de compartir?'),
        content: Text(
          'Nadie más verá la carpeta "$path". El contenido no se borra: '
          'sigue en tu Drive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Dejar de compartir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await HsApi.unshareFolderWith(path: path, userIds: targets);
    } catch (_) {
      // Aviso ya mostrado.
    }
    // La carpeta abierta puede quedarse sin destinatarios: se vuelve al listado.
    if (_open != null && '${_open!['path']}' == path) {
      setState(() => _open = null);
    }
    await _load();
  }

  void _snack(String msg) => HsToast.info(msg);

  // ---------------------------------------------------------------
  // Selector de usuarios
  // ---------------------------------------------------------------

  /// Muestra los usuarios y devuelve los marcados (o null si se canceló).
  Future<List<int>?> _showTargetsDialog({
    required String path,
    required List<int> current,
    required List<Map<String, dynamic>> candidates,
  }) async {
    final selected = <int>{...current};
    final search = TextEditingController();

    final result = await showHsModal<List<int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final scheme = Theme.of(ctx).colorScheme;
          final q = search.text.trim().toLowerCase();
          final list = candidates.where((c) {
            if (q.isEmpty) return true;
            final name = '${c['name'] ?? ''}'.toLowerCase();
            final email = '${c['email'] ?? ''}'.toLowerCase();
            return name.contains(q) || email.contains(q);
          }).toList();

          return AlertDialog(
            title: Text('Compartir "$path"'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: search,
                    onChanged: (_) => setSt(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Buscar usuario',
                      prefixIcon: Icon(Icons.search, size: 20),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${selected.length} seleccionado'
                    '${selected.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        candidates.isEmpty
                            ? 'No hay otros usuarios activos con los que compartir.'
                            : 'Ningún usuario coincide con la búsqueda.',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final c in list)
                            CheckboxListTile(
                              dense: true,
                              value: selected.contains(
                                (c['id'] as num?)?.toInt(),
                              ),
                              onChanged: (v) {
                                final id = (c['id'] as num?)?.toInt() ?? 0;
                                setSt(() {
                                  if (v == true) {
                                    selected.add(id);
                                  } else {
                                    selected.remove(id);
                                  }
                                });
                              },
                              title: Text(
                                '${c['name'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                              subtitle: Text(
                                [
                                  if ('${c['role'] ?? ''}'.isNotEmpty)
                                    '${c['role']}',
                                  if ('${c['email'] ?? ''}'.isNotEmpty)
                                    '${c['email']}',
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(selected.toList()..sort()),
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
    search.dispose();
    return result;
  }

  // ---------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCompact = MediaQuery.sizeOf(context).width < 620;
    final hPad = isCompact ? 14.0 : 24.0;

    final received = _receivedFolders;
    final mine = _myFolders;
    final current = _view == _SharedView.shared ? received : mine;

    return PopScope(
      // El botón "atrás" del sistema primero sale de la carpeta abierta.
      canPop: !_inside,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _goUp();
      },
      child: Column(
        children: [
          // ===== Encabezado: el MISMO del Drive (héroe, buscador, vista) =====
          Padding(
            padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 0),
            child: _header(scheme, isCompact, received, mine),
          ),
          // ===== Franja de solo lectura (solo en móvil: allí no se comparte) =
          if (_readOnly)
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 0),
              child: _readOnlyNotice(scheme),
            )
          // ===== Servicio de compartir: el switch que lo enciende =====
          else if (!isCompact)
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 0),
              child: _serviceCard(scheme),
            ),
          const SizedBox(height: 10),
          // ===== Migas de pan (dentro de una carpeta, igual que el Drive) ====
          if (_inside)
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _breadcrumbs(scheme),
              ),
            ),
          // ===== Barra de estado =====
          Padding(
            padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 6),
            child: _statusBar(scheme, current),
          ),
          // ===== Contenido =====
          Expanded(child: _content(scheme, isCompact, received, mine)),
        ],
      ),
    );
  }

  /// Héroe del módulo: tarjeta plana con degradado sutil, círculos de fondo,
  /// icono con anillo, título, descripción y el buscador + conmutador de vista
  /// (idéntico al del Drive).
  Widget _header(
    ColorScheme scheme,
    bool isCompact,
    List<Map<String, dynamic>> received,
    List<Map<String, dynamic>> mine,
  ) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(isCompact ? 18 : 22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: .08),
            scheme.primary.withValues(alpha: .015),
          ],
        ),
        border: Border.all(color: scheme.primary.withValues(alpha: .16)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -52,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .05),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: -46,
            bottom: -64,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .035),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(isCompact ? 16 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PopIn(
                      child: Container(
                        padding: const EdgeInsets.all(3.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: .28),
                          ),
                        ),
                        child: Container(
                          width: isCompact ? 48 : 54,
                          height: isCompact ? 48 : 54,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [AppColors.brand, AppColors.brandDark],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Icon(
                            Icons.folder_shared_outlined,
                            color: Colors.white,
                            size: isCompact ? 24 : 26,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Archivos compartidos',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: isCompact ? 19 : null,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _readOnly
                                ? 'Las carpetas que te comparten otros '
                                      'usuarios. Se ven y se descargan aquí.'
                                : 'Comparte una CARPETA DE TU COMPUTADORA con '
                                      'otros usuarios y abre las que te comparten.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    // Compartir una carpeta nueva (escritorio + permiso).
                    if (!isCompact && _canPickFolder) ...[
                      const SizedBox(width: 16),
                      OutlinedButton.icon(
                        onPressed: _shareNewFolder,
                        icon: const Icon(
                          Icons.create_new_folder_outlined,
                          size: 18,
                        ),
                        label: const Text('Compartir carpeta'),
                      ),
                    ],
                  ],
                ),
                // Acciones del héroe en el CELULAR: en fila propia y en botones
                // de IMAGEN (solo el icono, con el texto de tooltip). Antes iban
                // pegadas al título y en pantalla angosta se desbordaba.
                if (isCompact) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (_canPickFolder)
                        HsActionButton(
                          icon: Icons.create_new_folder_outlined,
                          label: 'Compartir carpeta',
                          onPressed: _shareNewFolder,
                        ),
                      if (_canPickFolder) const SizedBox(width: 10),
                      HsActionButton(
                        icon: Icons.refresh,
                        label: 'Actualizar',
                        primary: false,
                        onPressed: _load,
                      ),
                      // En pantalla angosta el switch del servicio va aquí (en
                      // botón de imagen): la tarjeta completa no cabe sin
                      // desbordar, pero el control sigue a mano.
                      if (isCompact && !_readOnly) ...[
                        const SizedBox(width: 10),
                        _serviceSwitchButton(scheme, compact: true),
                      ],
                    ],
                  ),
                ],
                // Sección: lo que me comparten / lo que yo comparto.
                if (!_inside) ...[
                  const SizedBox(height: 14),
                  // En el celular las etiquetas largas no caben: se usan
                  // nombres cortos para que las dos quepan de una.
                  _ViewTabs(
                    value: _view,
                    received: received.length,
                    mine: mine.length,
                    compact: isCompact,
                    onChanged: (v) => setState(() {
                      _view = v;
                      _open = null;
                      _searchController.clear();
                    }),
                  ),
                ],
                const SizedBox(height: 14),
                // Buscador + conmutador de vista (igual que el Drive).
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: _inside
                              ? 'Buscar en esta carpeta'
                              : 'Buscar carpeta o persona',
                          prefixIcon: const Icon(Icons.search, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Tooltip(
                      message: _grid ? 'Vista de lista' : 'Vista de cuadrícula',
                      child: IconButton.filledTonal(
                        onPressed: () => setState(() => _grid = !_grid),
                        icon: Icon(
                          _grid
                              ? Icons.view_list_rounded
                              : Icons.grid_view_rounded,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _readOnlyNotice(ColorScheme scheme) {
    final color = scheme.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.phone_iphone_rounded, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'En el teléfono este módulo es de SOLO LECTURA: aquí ves lo que '
              'te comparten y lo que compartiste. Para compartir una carpeta '
              'nueva usa la computadora.',
              style: TextStyle(fontSize: 12.5, height: 1.35, color: color),
            ),
          ),
        ],
      ),
    );
  }

  /// Migas de pan: "Compartido conmigo > Carpeta > Subcarpeta".
  Widget _breadcrumbs(ColorScheme scheme) {
    final open = _open!;
    final crumbs = <String>[
      _view == _SharedView.shared ? 'Compartido conmigo' : 'Lo que comparto',
      '${open['path'] ?? ''}',
      ..._localPath,
    ];
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < crumbs.length; i++) ...[
          if (i > 0)
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: i == crumbs.length - 1 ? null : () => _crumbTo(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                crumbs[i],
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: i == crumbs.length - 1
                      ? FontWeight.w800
                      : FontWeight.w600,
                  color: i == crumbs.length - 1
                      ? scheme.onSurface
                      : scheme.primary,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Salta a una miga: 0 = el listado, 1 = la carpeta abierta, 2+ = subcarpetas.
  void _crumbTo(int index) {
    if (index == 0) {
      setState(() {
        _open = null;
        _localPath = const [];
        _localItems = const [];
        _localError = null;
      });
      return;
    }
    if (index == 1) {
      if (_localPath.isEmpty) return;
      setState(() => _localPath = const []);
      _loadLocal();
      return;
    }
    final depth = index - 1;
    if (depth <= 0 || depth > _localPath.length) return;
    setState(() => _localPath = _localPath.sublist(0, depth));
    _loadLocal();
  }

  /// Píldoras de conteo del Drive ("N carpetas", "N personas", filtro).
  ///
  /// En el celular la fila se desliza de lado: con el filtro activo las
  /// píldoras no caben y antes se recortaban.
  Widget _statusBar(ColorScheme scheme, List<Map<String, dynamic>> current) {
    final compact = MediaQuery.sizeOf(context).width < 620;
    final pills = _statusPills(scheme, current, compact: compact);
    if (compact) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 2),
        child: Row(children: pills),
      );
    }
    return Row(children: pills);
  }

  List<Widget> _statusPills(
    ColorScheme scheme,
    List<Map<String, dynamic>> current, {
    required bool compact,
  }) {
    // Dentro de una carpeta compartida se cuenta su contenido (venga del
    // Drive del dueño o de su computadora), no las carpetas del listado.
    final inside = _inside;
    final folders = inside
        ? _localItems.where((i) => i.isFolder).length
        : current.length;
    final images = inside ? _localItems.where((i) => !i.isFolder).length : 0;
    final people = _view == _SharedView.shared
        ? current
              .expand(
                (r) => ((r['owners'] as List?) ?? const []).whereType<Map>(),
              )
              .map((o) => '${o['id']}')
              .toSet()
              .length
        : current
              .expand(
                (m) => ((m['targets'] as List?) ?? const []).whereType<Map>(),
              )
              .map((t) => '${t['targetId']}')
              .toSet()
              .length;

    return [
      _CountPill(
        icon: Icons.folder_rounded,
        label: '$folders carpeta${folders == 1 ? '' : 's'}',
      ),
      const SizedBox(width: 8),
      if (inside) ...[
        _CountPill(
          icon: Icons.image_outlined,
          label: '$images imagen${images == 1 ? '' : 'es'}',
        ),
        const SizedBox(width: 8),
      ],
      _CountPill(
        icon: Icons.people_alt_outlined,
        label: _view == _SharedView.shared
            ? '$people persona${people == 1 ? '' : 's'}'
            : '$people destinatario${people == 1 ? '' : 's'}',
      ),
      if (_filter != null) ...[
        const SizedBox(width: 8),
        _CountPill(
          icon: Icons.filter_alt,
          label: 'filtro: "${_searchController.text.trim()}"',
        ),
      ],
      // El [Spacer] empuja el aviso de error al extremo derecho; dentro de la
      // fila deslizante del celular NO puede ir (no hay ancho acotado).
      if (!compact) const Spacer(),
      if (_error != null)
        _CountPill(
          icon: Icons.cloud_off_outlined,
          label: 'Sin conexión · reintentar',
          color: scheme.error,
          onTap: _load,
        ),
    ];
  }

  Widget _content(
    ColorScheme scheme,
    bool isCompact,
    List<Map<String, dynamic>> received,
    List<Map<String, dynamic>> mine,
  ) {
    if (_loading) return const ListSkeleton(lines: 3, cardHeight: 104);
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.cloud_off_outlined, size: 40, color: scheme.error),
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
        ),
      );
    }
    if (_inside) return _insideContent(scheme, isCompact);
    if (_view == _SharedView.shared) {
      return _folderGrid(
        scheme,
        isCompact,
        entries: [
          for (final r in received)
            if (_matches('${r['path']} ${_ownerNames(r).join(' ')}')) r,
        ],
        empty: EmptyState(
          icon: Icons.inbox_outlined,
          title: 'Nadie te ha compartido carpetas',
          message: _filter != null
              ? 'Ninguna carpeta coincide con la búsqueda.'
              : 'Las carpetas que otros usuarios compartan contigo aparecerán '
                    'aquí para verlas y descargarlas.',
        ),
        onOpen: _openReceived,
      );
    }
    return _folderGrid(
      scheme,
      isCompact,
      entries: [
        for (final m in mine)
          if (_matches('${m['path']} ${_targetNames(m).join(' ')}')) m,
      ],
      empty: EmptyState(
        icon: Icons.outbox_outlined,
        title: 'Todavía no compartes carpetas',
        message: _filter != null
            ? 'Ninguna carpeta coincide con la búsqueda.'
            : _canPickFolder
            ? 'Elige una carpeta de tu computadora y a qué usuarios '
                  'quieres compartírsela. La misma carpeta puede ir a varios.'
            : 'Cuando compartas una carpeta desde la computadora, aquí '
                  'verás a quiénes se la compartiste.',
        actionLabel: _canPickFolder ? 'Compartir carpeta' : null,
        onAction: _canPickFolder ? _shareNewFolder : null,
      ),
      onOpen: _openMine,
    );
  }

  /// Listado de carpetas (recibidas o mías) en cuadrícula o lista.
  Widget _folderGrid(
    ColorScheme scheme,
    bool isCompact, {
    required List<Map<String, dynamic>> entries,
    required EmptyState empty,
    required void Function(Map<String, dynamic>) onOpen,
  }) {
    if (entries.isEmpty) return empty;
    if (_grid) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final minCard = isCompact ? 150.0 : 190.0;
          final crossCount = (constraints.maxWidth / minCard).floor().clamp(
            2,
            8,
          );
          return GridView.builder(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(
              isCompact ? 14 : 24,
              4,
              isCompact ? 14 : 24,
              24,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossCount,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.86,
            ),
            itemCount: entries.length,
            itemBuilder: (context, i) => _FolderCard(
              entry: entries[i],
              shared: _view == _SharedView.shared,
              status: _statusOf(entries[i]),
              onOpen: () => onOpen(entries[i]),
              onUnshare: _view == _SharedView.mine && _canUnshare
                  ? () => _unshareAll(
                      '${entries[i]['path'] ?? ''}',
                      _targetIds(entries[i]),
                    )
                  : null,
            ),
          );
        },
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        isCompact ? 14 : 24,
        4,
        isCompact ? 14 : 24,
        24,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _FolderRow(
          entry: entries[i],
          shared: _view == _SharedView.shared,
          status: _statusOf(entries[i]),
          onOpen: () => onOpen(entries[i]),
          onUnshare: _view == _SharedView.mine && _canUnshare
              ? () => _unshareAll(
                  '${entries[i]['path'] ?? ''}',
                  _targetIds(entries[i]),
                )
              : null,
        ),
      ),
    );
  }

  /// Contenido de la carpeta abierta: la tarjeta de "a quién se la compartí"
  /// (solo en "Lo que comparto") y, debajo, su contenido en SOLO LECTURA.
  ///
  /// Vale igual para una carpeta de la computadora del dueño que para una de
  /// su Drive: las dos se navegan AQUÍ MISMO, sin saltar al módulo Archivos.
  Widget _insideContent(ColorScheme scheme, bool isCompact) {
    final open = _open!;
    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        isCompact ? 14 : 24,
        4,
        isCompact ? 14 : 24,
        24,
      ),
      children: [
        if (_view == _SharedView.mine) ...[
          _shareCard(scheme, open),
          const SizedBox(height: 14),
        ],
        // En "Compartido conmigo" se dice de un vistazo de dónde se está
        // sirviendo la carpeta que se acaba de abrir.
        if (_view == _SharedView.shared &&
            !_localLoading &&
            _openStatus != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _openStatusStrip(scheme),
          ),
        ..._folderBody(scheme),
      ],
    );
  }

  /// Franja con el estado del compartido abierto: la píldora y, a la derecha,
  /// la explicación (útil cuando está apagada o el servidor no la resuelve).
  Widget _openStatusStrip(ColorScheme scheme) {
    final look = _shareStatusLook(scheme, _openStatus);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: look.color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: look.color.withValues(alpha: .28)),
      ),
      child: Row(
        children: [
          Icon(look.icon, size: 16, color: look.color),
          const SizedBox(width: 8),
          Text(
            look.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: look.color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              look.hint,
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ),
          IconButton(
            tooltip: 'Comprobar otra vez',
            visualDensity: VisualDensity.compact,
            onPressed: _refreshStatuses,
            icon: const Icon(Icons.refresh_rounded, size: 17),
          ),
        ],
      ),
    );
  }

  /// Tarjeta de una carpeta MÍA: de dónde salió, quiénes la reciben y las
  /// acciones (elegir usuarios, dejar de compartir).
  Widget _shareCard(ColorScheme scheme, Map<String, dynamic> open) {
    final local = open['local'] == true;
    final targets = ((open['targets'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _typeChip(
                  scheme,
                  local ? 'Carpeta de tu computadora' : 'Carpeta de tu Drive',
                ),
                const Spacer(),
                Text(
                  '${targets.length} '
                  '${targets.length == 1 ? 'usuario' : 'usuarios'}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ShareStatusPill(status: _openStatus),
            const SizedBox(height: 10),
            if (targets.isEmpty)
              Text(
                'Nadie la recibe ahora mismo.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in targets)
                    _PersonChip(
                      label: '${t['targetName'] ?? 'Usuario'}',
                      icon: Icons.person_outline,
                      tint: scheme.primary,
                    ),
                ],
              ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_canPickFolder)
                  OutlinedButton.icon(
                    onPressed: () => _editTargets('${open['path'] ?? ''}'),
                    icon: const Icon(Icons.group_add_outlined, size: 16),
                    label: const Text('Usuarios'),
                  ),
                if (_canUnshare)
                  OutlinedButton.icon(
                    onPressed: () =>
                        _unshareAll('${open['path'] ?? ''}', _targetIds(open)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                      side: BorderSide(
                        color: scheme.error.withValues(alpha: .55),
                      ),
                    ),
                    icon: const Icon(Icons.link_off_rounded, size: 16),
                    label: const Text('Dejar de compartir'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Cuerpo de la carpeta compartida abierta: cargando, error, vacía o su
  /// contenido (carpetas primero, luego imágenes), todo de SOLO LECTURA.
  List<Widget> _folderBody(ColorScheme scheme) {
    if (_localLoading) {
      return const [ListSkeleton(lines: 3, cardHeight: 84)];
    }
    if (_localError != null) {
      // Una carpeta de la COMPUTADORA del dueño la sirve SU app (el servidor
      // solo hace de puente): al fallar, se explica eso, y no que "el servidor
      // tiene que poder abrirla" —eso era falso y mandaba a buscar el problema
      // al lugar equivocado (el servidor NUNCA puede abrir la carpeta de otro
      // equipo; para eso está la app del dueño).
      final local = _open!['local'] == true;
      return [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.cloud_off_outlined, size: 40, color: scheme.error),
                const SizedBox(height: 10),
                Text(_localError!, textAlign: TextAlign.center),
                if (local) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Es una carpeta de la computadora de quien la comparte: la '
                    'sirve SU aplicación, así que esa computadora tiene que '
                    'estar encendida y con la aplicación abierta. Si sigue sin '
                    'abrirse, pídele que la vuelva a compartir.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loadLocal,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    final items = _localItems.where((i) => _matches(i.name)).toList();
    if (items.isEmpty) {
      return [
        EmptyState(
          icon: Icons.folder_open_rounded,
          title: _filter != null ? 'Sin resultados' : 'Esta carpeta está vacía',
          message: _filter != null
              ? 'No hay coincidencias en esta carpeta.'
              : 'La carpeta compartida todavía no tiene archivos.',
        ),
      ];
    }
    // El contenido se pinta TAL CUAL lo hace el módulo Archivos: UNA sola
    // cuadrícula, con las carpetas y las fotos mezcladas en el orden que manda
    // el servidor (carpetas primero y, dentro de cada tipo, por nombre).
    //
    // Antes se partía en dos tramos con sus rótulos ("CARPETAS" / "IMÁGENES") y
    // dos cuadrículas, que es algo que el Drive NO hace: sus carpetas y sus
    // fotos van juntas en la misma rejilla.
    return [
      _localGrid([
        for (final i in items)
          _LocalCard(
            name: i.name,
            folder: i.isFolder,
            size: i.size,
            thumb: i.isFolder ? null : _localThumb(i.name),
            onTap: () => i.isFolder ? _enterLocalFolder(i) : _viewLocalImage(i),
            onDownload: i.isFolder ? null : () => _downloadLocal(i.name),
          ),
      ]),
    ];
  }

  /// URL de la miniatura de una foto de la carpeta compartida abierta.
  ///
  /// Mismo tamaño que usa el módulo Archivos (480 px): el servidor la reduce
  /// UNA vez y la guarda en su caché, así la cuadrícula abre con las fotos ya
  /// listas en vez de con recuadros vacíos.
  String _localThumb(String name, {int width = 480}) {
    final shareId = (_open!['shareId'] as num?)?.toInt() ?? 0;
    return _local.thumbUrl(shareId, [..._localPath, name], width: width);
  }

  /// Cuadrícula de tarjetas con las MISMAS medidas que el módulo Archivos
  /// (tarjeta de 150-190 px, proporción 0.86 y 12 px de separación).
  Widget _localGrid(List<Widget> cards) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    final minCard = compact ? 150.0 : 190.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = (constraints.maxWidth / minCard).floor().clamp(2, 8);
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossCount,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.86,
          children: cards,
        );
      },
    );
  }

  /// Deja PEDIDAS las miniaturas de la carpeta abierta (las primeras [max]).
  ///
  /// Son las mismas direcciones que pide la cuadrícula: pedirlas al abrir la
  /// carpeta hace que, al bajar con el dedo o la rueda, las fotos ya estén
  /// (en RAM y en la caché del servidor) en vez de ir apareciendo una a una.
  /// Se limita el número para no encolar toda una carpeta de cientos.
  void _warmThumbs(List<LocalShareItem> items, {int max = 24}) {
    var asked = 0;
    for (final it in items) {
      if (it.isFolder) continue;
      if (asked >= max) break;
      asked++;
      // Con `onError` la miniatura que falte NO revienta la app ni ensucia el
      // registro: la tarjeta ya tiene su propio marcador con "toca para
      // reintentar".
      precacheImage(
        NetworkImage(_localThumb(it.name)),
        context,
        onError: (_, _) {},
      );
    }
  }

  Widget _typeChip(ColorScheme scheme, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary.withValues(alpha: .25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: scheme.primary,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Ayudas de datos
  // ---------------------------------------------------------------

  List<String> _ownerNames(Map<String, dynamic> r) =>
      ((r['owners'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => '${e['name'] ?? ''}')
          .where((n) => n.isNotEmpty)
          .toList();

  List<String> _targetNames(Map<String, dynamic> m) =>
      ((m['targets'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => '${e['targetName'] ?? ''}')
          .where((n) => n.isNotEmpty)
          .toList();

  List<int> _targetIds(Map<String, dynamic> m) =>
      ((m['targets'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => (e['targetId'] as num?)?.toInt() ?? 0)
          .where((n) => n > 0)
          .toList();
}

// ==================================================================
// Piezas visuales (mismo lenguaje que el Drive)
// ==================================================================

/// Conmutador de sección: "Compartido conmigo" / "Lo que comparto".
class _ViewTabs extends StatelessWidget {
  const _ViewTabs({
    required this.value,
    required this.received,
    required this.mine,
    required this.onChanged,
    this.compact = false,
  });

  final _SharedView value;
  final int received;
  final int mine;
  final ValueChanged<_SharedView> onChanged;

  /// Celular: etiquetas cortas (las largas no caben en la pantalla).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<_SharedView>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
          textStyle: TextStyle(fontSize: compact ? 12 : 14),
        ),
        segments: [
          ButtonSegment(
            value: _SharedView.shared,
            icon: const Icon(Icons.inbox_outlined, size: 18),
            label: Text(
              compact
                  ? 'Recibidos ($received)'
                  : 'Compartido conmigo ($received)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ButtonSegment(
            value: _SharedView.mine,
            icon: const Icon(Icons.outbox_outlined, size: 18),
            label: Text(
              compact ? 'Míos ($mine)' : 'Lo que comparto ($mine)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

/// Tarjeta de carpeta (cuadrícula): el mismo diseño que una carpeta del Drive.
class _FolderCard extends StatelessWidget {
  const _FolderCard({
    required this.entry,
    required this.shared,
    required this.onOpen,
    this.status,
    this.onUnshare,
  });

  final Map<String, dynamic> entry;

  /// true = la recibí (muestra quién la comparte); false = es mía.
  final bool shared;

  /// De dónde se puede servir AHORA (null = todavía sin comprobar).
  final LocalShareStatus? status;

  /// Abre la carpeta AQUÍ MISMO (este módulo nunca salta a Archivos).
  final VoidCallback onOpen;
  final VoidCallback? onUnshare;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final local = entry['local'] == true;
    final path = '${entry['path'] ?? ''}';
    final people = shared
        ? _names(entry, 'owners', 'name')
        : _names(entry, 'targets', 'targetName');

    return _Hover(
      builder: (context, hovered) => Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hovered
                    ? scheme.primary.withValues(alpha: .45)
                    : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        scheme.primary.withValues(alpha: .24),
                        scheme.primary.withValues(alpha: .07),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(14),
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          local
                              ? Icons.computer_rounded
                              : Icons.folder_shared_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const Spacer(),
                      _EntryMenu(onOpen: onOpen, onUnshare: onUnshare),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        local
                            ? 'Carpeta de su computadora'
                            : 'Carpeta del Drive',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      if (people.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          shared
                              ? 'Compartida por ${people.join(', ')}'
                              : 'Con ${people.join(', ')}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _ShareStatusPill(status: status),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fila de carpeta (vista de lista): el mismo diseño que una fila del Drive.
class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.entry,
    required this.shared,
    required this.onOpen,
    this.status,
    this.onUnshare,
  });

  final Map<String, dynamic> entry;
  final bool shared;

  /// De dónde se puede servir AHORA (null = todavía sin comprobar).
  final LocalShareStatus? status;

  /// Abre la carpeta AQUÍ MISMO (este módulo nunca salta a Archivos).
  final VoidCallback onOpen;
  final VoidCallback? onUnshare;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final local = entry['local'] == true;
    final path = '${entry['path'] ?? ''}';
    final people = shared
        ? _names(entry, 'owners', 'name')
        : _names(entry, 'targets', 'targetName');

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        hoverColor: scheme.primary.withValues(alpha: .07),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  local ? Icons.computer_rounded : Icons.folder_shared_outlined,
                  color: scheme.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    Text(
                      people.isEmpty
                          ? (local
                                ? 'Carpeta de su computadora'
                                : 'Carpeta del Drive')
                          : (shared
                                ? 'Compartida por ${people.join(', ')}'
                                : 'Con ${people.join(', ')}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _ShareStatusPill(status: status, dense: true),
              IconButton(
                tooltip: 'Abrir la carpeta',
                visualDensity: VisualDensity.compact,
                onPressed: onOpen,
                icon: const Icon(Icons.chevron_right_rounded, size: 18),
              ),
              if (!shared && onUnshare != null)
                IconButton(
                  tooltip: 'Dejar de compartir',
                  visualDensity: VisualDensity.compact,
                  onPressed: onUnshare,
                  icon: Icon(
                    Icons.link_off_rounded,
                    size: 18,
                    color: scheme.error,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de la cuadrícula de una carpeta compartida: la MISMA forma que las
/// del módulo Archivos (carpeta con su cabecera degradada, o foto con su
/// miniatura, su nombre, su peso y su botón de descargar).
///
/// Es de SOLO LECTURA: no hay renombrar, mover ni borrar, porque el servidor
/// tampoco los ofrece para una carpeta que no es tuya.
class _LocalCard extends StatefulWidget {
  const _LocalCard({
    required this.name,
    required this.folder,
    required this.onTap,
    this.size,
    this.thumb,
    this.onDownload,
  });

  final String name;
  final bool folder;

  /// Peso en bytes (solo fotos).
  final int? size;

  /// URL de la miniatura (solo fotos).
  final String? thumb;
  final VoidCallback onTap;
  final VoidCallback? onDownload;

  @override
  State<_LocalCard> createState() => _LocalCardState();
}

class _LocalCardState extends State<_LocalCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        elevation: _hover ? 6 : null,
        child: InkWell(
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.folder)
                Container(
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        scheme.primary.withValues(alpha: .24),
                        scheme.primary.withValues(alpha: .07),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.folder_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DriveThumb(
                        source: widget.thumb ?? '',
                        isRemote: true,
                        size: double.infinity,
                        big: true,
                        rounded: false,
                      ),
                      if (widget.onDownload != null)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Material(
                            color: Colors.black.withValues(alpha: .45),
                            shape: const CircleBorder(),
                            child: IconButton(
                              tooltip: 'Descargar',
                              visualDensity: VisualDensity.compact,
                              onPressed: widget.onDownload,
                              icon: const Icon(
                                Icons.download_rounded,
                                size: 17,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  widget.folder ? 14 : 12,
                  widget.folder ? 12 : 8,
                  widget.folder ? 14 : 12,
                  widget.folder ? 12 : 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.folder
                          ? 'Carpeta compartida'
                          : widget.size == null
                          ? 'Imagen'
                          : hsBytes(widget.size!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
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
}

/// Menú "⋮" de una carpeta compartida.
class _EntryMenu extends StatelessWidget {
  const _EntryMenu({required this.onOpen, this.onUnshare});

  final VoidCallback onOpen;
  final VoidCallback? onUnshare;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Opciones',
      padding: EdgeInsets.zero,
      splashRadius: 18,
      icon: Icon(Icons.more_vert, size: 18, color: scheme.onSurfaceVariant),
      onSelected: (v) {
        if (v == 'open') onOpen();
        if (v == 'unshare') onUnshare?.call();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'open', child: Text('Abrir la carpeta')),
        if (onUnshare != null)
          const PopupMenuItem(
            value: 'unshare',
            child: Text('Dejar de compartir'),
          ),
      ],
    );
  }
}

/// Envoltorio que indica si el mouse está encima del hijo.
class _Hover extends StatefulWidget {
  const _Hover({required this.builder});

  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(context, _hovered),
    );
  }
}

/// Píldora de conteo (igual que la barra de estado del Drive).
class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.icon,
    required this.label,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color ?? scheme.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return pill;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: pill,
    );
  }
}

/// Píldora con el nombre de una persona (destinatario o dueño).
class _PersonChip extends StatelessWidget {
  const _PersonChip({
    required this.label,
    required this.icon,
    required this.tint,
  });

  final String label;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tint.withValues(alpha: .25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tint),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: tint,
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado de un compartido → etiqueta, icono, color y explicación.
///
/// Vive aparte del widget para que las pruebas puedan comprobar el texto sin
/// abrir la pantalla (mismo criterio que el resto del módulo).
({String label, IconData icon, Color color, String hint}) _shareStatusLook(
  ColorScheme scheme,
  LocalShareStatus? status,
) {
  if (status == null) {
    return (
      label: 'Comprobando…',
      icon: Icons.sync_rounded,
      color: scheme.onSurfaceVariant,
      hint: 'Preguntando al servidor del drive de dónde se sirve esta carpeta.',
    );
  }
  // El MOTIVO manda sobre el "de dónde": si el servidor dijo por qué no puede
  // servirla, eso es lo que hay que leer primero (da igual si la respuesta
  // llegó como estado o como el 404 de un servidor viejo).
  // La base está configurada pero NO responde (o le falta la migración): no es
  // "la carpeta ya no está compartida", y hay que poder verificarlo en la
  // pantalla, que es donde se lee el motivo.
  if (status.reason == 'share-db') {
    return (
      label: 'La base de datos no responde',
      icon: Icons.storage_rounded,
      color: AppColors.warn,
      hint:
          status.detail ??
          'El servidor del drive no pudo consultar los compartidos en su '
              'base de datos: revisa que DRIVE_DB apunte a la misma base del '
              'panel.',
    );
  }
  if (status.reason == 'no-db' || !status.hasDatabase) {
    return (
      label: 'Servidor sin base de datos',
      icon: Icons.storage_rounded,
      color: AppColors.warn,
      hint:
          status.detail ??
          'El servidor del drive no tiene configurada la base de datos '
              '(DRIVE_DB): sin ella no puede resolver las carpetas '
              'compartidas.',
    );
  }
  if (status.reason == 'share-missing' || status.reason == 'share-revoked') {
    return (
      label: 'Ya no está compartida',
      icon: Icons.link_off_rounded,
      color: AppColors.warn,
      hint:
          status.detail ??
          'Ese compartido ya no está activo: pídele a quien te lo '
              'compartió que lo vuelva a compartir. Si acaba de compartirlo, '
              'espera unos segundos y vuelve a intentar.',
    );
  }
  switch (status.servedFrom) {
    case 'server':
      return (
        label: 'Disponible',
        icon: Icons.cloud_done_outlined,
        color: AppColors.ok,
        hint:
            'La carpeta está en el servidor del drive: se ve desde '
            'cualquier lugar, sin depender de la computadora de nadie.',
      );
    case 'agent':
      return (
        label: 'En línea',
        icon: Icons.computer_rounded,
        color: AppColors.ok,
        hint:
            'Es una carpeta de la computadora de quien la comparte y su '
            'aplicación está abierta ahora mismo: se puede ver y descargar.',
      );
    case 'offline':
      return (
        label: 'Apagada ahora',
        icon: Icons.power_off_rounded,
        color: AppColors.warn,
        hint:
            'La carpeta está en la computadora de quien la comparte y su '
            'aplicación no está abierta: se abrirá cuando la vuelva a abrir.',
      );
    case 'unavailable':
      return (
        label: 'No disponible',
        icon: Icons.error_outline_rounded,
        color: AppColors.warn,
        hint:
            status.detail ??
            'El servidor del drive no pudo abrir esta carpeta compartida.',
      );
    default:
      return (
        label: 'Sin comprobar',
        icon: Icons.help_outline_rounded,
        color: scheme.onSurfaceVariant,
        hint:
            status.detail ??
            'No se pudo preguntar al servidor del drive; la carpeta se '
                'intentará abrir igual.',
      );
  }
}

/// Píldora "Encendido / Apagado" del servicio de compartir.
class _ServingPill extends StatelessWidget {
  const _ServingPill({required this.on, required this.tint, this.label});

  final bool on;
  final Color tint;

  /// Texto alternativo (p. ej. "Con problemas"): el servicio está encendido,
  /// pero el servidor del drive no lo deja servir todavía.
  final String? label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: tint.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: tint.withValues(alpha: .32)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          on ? Icons.bolt_rounded : Icons.power_off_rounded,
          size: 12,
          color: tint,
        ),
        const SizedBox(width: 4),
        Text(
          label ?? (on ? 'Encendido' : 'Apagado'),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: tint,
          ),
        ),
      ],
    ),
  );
}

/// Píldora con el estado de un compartido (de un vistazo, sin abrirla).
class _ShareStatusPill extends StatelessWidget {
  const _ShareStatusPill({required this.status, this.dense = false});

  final LocalShareStatus? status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final look = _shareStatusLook(scheme, status);
    return Tooltip(
      message: look.hint,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 7 : 9,
          vertical: dense ? 3 : 4,
        ),
        decoration: BoxDecoration(
          color: look.color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: look.color.withValues(alpha: .32)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(look.icon, size: dense ? 12 : 13, color: look.color),
            const SizedBox(width: 5),
            // La etiqueta se recorta si la tarjeta es angosta (cuadrícula del
            // celular): la píldora NUNCA desborda.
            Flexible(
              child: Text(
                look.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: dense ? 10.5 : 11,
                  fontWeight: FontWeight.w700,
                  color: look.color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nombres de las personas de una entrada ("owners" o "targets").
List<String> _names(Map<String, dynamic> entry, String key, String field) =>
    ((entry[key] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => '${e[field] ?? ''}')
        .where((n) => n.isNotEmpty)
        .toList();

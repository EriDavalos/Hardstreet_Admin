import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import '../app_platform.dart';
import '../hs_api.dart';
import '../local_share_agent.dart';
import '../local_share_service.dart';
import '../share_permissions.dart';
import '../shared_drive.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/common.dart';
import '../widgets/hs_modal.dart';
import '../widgets/hs_pager.dart';
import '../widgets/hs_search_filter.dart';
import '../widgets/hs_toast.dart';
import 'drive_page.dart' show DrivePage;

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

  // Paginación de las carpetas (30 de fábrica; 50/100/200 abajo).
  int _page = 1;
  int _pageSize = kHsDefaultPageSize;
  List<Map<String, dynamic>> _candidates = const [];
  bool _canShare = true;
  bool _canDelete = true;

  /// Cuadrícula (por defecto, como el Drive) o lista.
  bool _grid = true;

  /// La carpeta compartida ABIERTA, con la MISMA vista del Drive.
  ///
  /// Se navega DENTRO de este módulo: la sección cambia de vista, no se abre
  /// otra ventana ni se salta al módulo Archivos.
  SharedDrive? _open;

  /// La carpeta abierta es MÍA (lo que yo comparto) o me la comparten.
  bool _openIsMine = false;

  /// No se pudo abrir la carpeta: el motivo se muestra EN PANTALLA (con el
  /// detalle del servidor y un botón para reintentar).
  ({Map<String, dynamic> entry, String detail, String hint})? _openProblem;

  /// Última apertura pedida. Cada intento se queda con su número y, cuando
  /// termina, si ya se pidió OTRA cosa (o se volvió al listado) se DESCARTA:
  /// así una respuesta que llega tarde no pinta la carpeta que ya dejaste.
  int _openTicket = 0;

  /// Carpeta MARCADA en el listado (un clic con el ratón) y datos del último
  /// clic: en la computadora un clic marca y el DOBLE clic entra, como en el
  /// explorador de Windows. En el celular (dedo) un toque entra directo.
  String? _markedPath;
  String? _lastClickPath;
  DateTime? _lastClickAt;
  PointerDeviceKind _lastPointerKind = PointerDeviceKind.mouse;

  /// Sección que se está viendo: lo que me comparten o lo que yo comparto.
  _SharedView _view = _SharedView.shared;

  /// ESTADO de cada compartido (servidor / computadora del dueño / apagada).
  /// Es lo que deja VER, desde el listado, si una carpeta está funcionando
  /// ahora mismo, sin tener que abrirla para descubrirlo.
  final Map<int, LocalShareStatus> _statuses = {};

  /// Último listado de estados pedido (para descartar respuestas viejas).
  int _statusTicket = 0;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// Filtro del módulo: '' = todos · 'local' = computadora · 'server' = drive.
  String _originFilter = '';

  /// En MÓVIL el módulo es de SOLO LECTURA: compartir exige elegir una carpeta
  /// del equipo y eso se hace en la computadora.
  bool get _readOnly => isAndroidPlatform || useLongPressDrag;

  /// El filtro del buscador (solo aplica al listado de carpetas).
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
        final agent = LocalShareAgent.instance;
        // Si el usuario ya eligió el switch, ESA preferencia manda: apagado
        // sigue apagado aunque haya carpetas locales compartidas. Solo sin
        // preferencia explícita se enciende solo al haber algo que servir.
        if (agent.manualPreferenceKnown) {
          if (agent.manualOn) {
            agent.start();
          } else {
            agent.stop();
          }
        } else if (data.shared.any((s) => s['local'] == true)) {
          agent.start();
        } else {
          agent.stop();
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
        // Si más de un dueño comparte la MISMA carpeta, los permisos se
        // suman: si uno me dio editar, puedo editar.
        out[i]['permissions'] = SharePermissions.fromJson(out[i]['permissions'])
            .merge(SharePermissions.fromJson(r['permissions']))
            .toJson();
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

  /// ¿La carpeta pasa el filtro de origen (computadora / servidor)?
  bool _matchesOrigin(Map<String, dynamic> entry) {
    if (_originFilter.isEmpty) return true;
    final local = entry['local'] == true;
    return _originFilter == 'local' ? local : !local;
  }

  /// Carpetas de la sección visible (una por carpeta).
  List<Map<String, dynamic>> get _currentFolders =>
      _view == _SharedView.shared ? _receivedFolders : _myFolders;

  List<HsFilterGroup> _filterGroups() {
    final folders = _currentFolders;
    final local = folders.where((e) => e['local'] == true).length;
    return [
      HsFilterGroup(
        id: 'origen',
        title: '¿Dónde está la carpeta?',
        help: 'Las de la computadora las sirve la app de su dueño; las del '
            'drive están siempre en el servidor.',
        options: [
          HsFilterOption(
            value: '',
            label: 'Todas',
            count: folders.length,
            icon: Icons.folder_copy_outlined,
          ),
          HsFilterOption(
            value: 'local',
            label: 'En la computadora',
            count: local,
            icon: Icons.computer_rounded,
            color: const Color(0xFF2F6BFF),
          ),
          HsFilterOption(
            value: 'server',
            label: 'En el servidor',
            count: folders.length - local,
            icon: Icons.cloud_outlined,
            color: const Color(0xFF3B82F6),
          ),
        ],
      ),
    ];
  }

  // ---------------------------------------------------------------
  // Navegación
  // ---------------------------------------------------------------

  void _openReceived(Map<String, dynamic> r) => unawaited(_openEntry(r));

  void _openMine(Map<String, dynamic> m) => unawaited(_openEntry(m));

  /// Un clic (o un toque) sobre una carpeta del listado.
  ///
  /// * DEDO (celular): entra directo — ahí no existe el doble clic.
  /// * RATÓN: el primer clic la MARCA; el segundo clic seguido (mismo botón,
  ///   misma carpeta, menos de 400 ms) entra. Así se puede marcar sin abrir,
  ///   como en el explorador de Windows.
  void _onFolderTap(Map<String, dynamic> entry) {
    final path = '${entry['path'] ?? ''}';
    if (_lastPointerKind == PointerDeviceKind.touch) {
      unawaited(_openEntry(entry));
      return;
    }
    final now = DateTime.now();
    final isDouble =
        path == _lastClickPath &&
        _lastClickAt != null &&
        now.difference(_lastClickAt!) < const Duration(milliseconds: 400);
    _lastClickPath = path;
    _lastClickAt = now;
    if (isDouble) {
      _lastClickPath = null;
      _lastClickAt = null;
      unawaited(_openEntry(entry));
      return;
    }
    setState(() => _markedPath = path);
  }

  /// Abre una carpeta compartida con LA MISMA vista del Drive: cuadrícula y
  /// lista, recuadro de selección, clic derecho, arrastrar y soltar, subir,
  /// mover, renombrar, eliminar y visor. Las acciones que se ofrecen salen de
  /// los permisos que concedió quien comparte (el dueño tiene todo).
  Future<void> _openEntry(Map<String, dynamic> entry) async {
    final shareId = _shareIdOf(entry);
    if (shareId <= 0) {
      _snack('No se pudo identificar la carpeta compartida');
      return;
    }
    final ticket = ++_openTicket;
    final label = '${entry['path'] ?? ''}'
        .split(RegExp(r'[\\/]'))
        .where((s) => s.isNotEmpty)
        .lastOrNull;
    final mine = _view == _SharedView.mine;
    // El dueño puede todo; el destinatario, lo que le dieron (la API manda
    // los permisos de cada compartido en el listado).
    var rights = mine
        ? SharePermissions.owner
        : SharePermissions.fromJson(
            entry['permissions'],
            fallback: SharePermissions.readOnly,
          );
    if (!mine && !rights.view) {
      HsToast.error(
        'No puedes ver esa carpeta',
        details: 'Quien la comparte no te dio permiso para verla.',
      );
      return;
    }

    // ¿De dónde se puede servir AHORA? La carpeta puede estar en la
    // computadora del dueño: si su app no está abierta (o el servidor no
    // tiene su base de datos), se EXPLICA en pantalla —con el motivo que dio
    // el servidor y un botón para reintentar—, en vez de un error crudo.
    final service = _local;
    final status = await service.status(shareId);
    // Se pidió otra carpeta (o se volvió al listado) mientras se preguntaba:
    // este intento ya no manda.
    if (!mounted || ticket != _openTicket) return;
    // Los permisos los manda también el SERVIDOR DEL DRIVE, que es quien los
    // exige en cada operación: si los mandó, son ÉSOS. Así la vista ofrece
    // exactamente lo que el servidor va a aceptar, aunque el panel tenga el
    // dato viejo o su base de datos no traiga las columnas de permisos.
    if (!mine && status.permissionsKnown) rights = status.permissions;
    final blocked =
        !status.available &&
        (status.reason != null || status.servedFrom != 'unknown');
    if (blocked) {
      setState(() {
        _open = null;
        _openIsMine = mine;
        _openProblem = (
          entry: entry,
          detail:
              status.detail ??
              'El servidor del drive no puede servir esta carpeta ahora mismo.',
          hint: _problemHint(status),
        );
      });
      return;
    }

    // La carpeta se abre AQUÍ MISMO: cambia la VISTA de esta sección (no se
    // abre otra ventana, ni con otro encabezado, ni se salta a Archivos).
    final drive = SharedDrive(
      service: service,
      shareId: shareId,
      label: label ?? 'Carpeta compartida',
      rights: rights,
      // La miga raíz es el MÓDULO: tocarla vuelve a este listado.
      sectionLabel: mine ? 'Lo que comparto' : 'Compartido conmigo',
    );
    setState(() {
      _open = drive;
      _openIsMine = mine;
      _openProblem = null;
    });
    // La PRIMERA carga se pide YA: el Drive no carga por su cuenta, así que
    // sin esto una carpeta CON contenido se abría vacía.
    unawaited(drive.openPath(const []));
  }

  /// Cierra la carpeta abierta y vuelve al listado del módulo.
  void _closeOpen() {
    if (_open == null && _openProblem == null) return;
    // Lo que estuviera pidiéndose deja de mandar.
    _openTicket++;
    setState(() {
      _open = null;
      _openIsMine = false;
      _openProblem = null;
      _markedPath = null;
      _lastClickPath = null;
      _lastClickAt = null;
    });
    // Lo que pudo cambiar dentro (o el estado del servicio) se pone al día.
    unawaited(_load());
  }

  /// Por qué NO se puede abrir la carpeta, dicho en claro y con la salida.
  static String _problemHint(LocalShareStatus status) {
    // La base de datos del drive: sin ella el servidor no sabe a quién
    // pertenece cada compartido (y el error no es "la carpeta no existe").
    if (status.reason == 'no-db' ||
        status.reason == 'share-db' ||
        !status.hasDatabase) {
      return 'El servidor del drive no tiene su base de datos (DRIVE_DB) a '
          'mano: sin ella no puede resolver las carpetas compartidas.';
    }
    // Las carpetas de la COMPUTADORA las sirve la app de su dueño: el
    // servidor solo hace de puente mientras esa app esté abierta.
    if (status.servedFrom == 'offline' || status.localFolder) {
      return 'La carpeta vive en la computadora de quien la comparte: la sirve '
          'SU aplicación. Pídele que la tenga abierta y vuelve a intentar.';
    }
    return 'Si la carpeta vive en la computadora de quien la comparte, la '
        'sirve SU aplicación (tiene que estar abierta). Si está en el Drive, '
        'revisa que el servidor tenga su base de datos al día.';
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

  // ---------------------------------------------------------------
  // Visor y descarga de una carpeta LOCAL
  // ---------------------------------------------------------------

  /// Descarga una CARPETA compartida completa, en ZIP (el servidor la sirve
  /// archivo por archivo y el ZIP se arma en la app).
  Future<void> _downloadFolder(Map<String, dynamic> entry) async {
    final shareId = _shareIdOf(entry);
    if (shareId <= 0) return;
    final path = '${entry['path'] ?? ''}';
    final label = path
        .split(RegExp(r'[\\/]'))
        .where((s) => s.isNotEmpty)
        .lastOrNull;
    final name = '${(label ?? 'carpeta').trim()}.zip';
    _snack('Preparando la descarga de "${label ?? 'la carpeta'}"…');
    try {
      final where = await _local.downloadFolderZip(
        shareId,
        const [],
        name: name,
      );
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

  /// Editar destinatarios Y SUS PERMISOS de una carpeta ya compartida.
  ///
  /// Los permisos (Ver / Editar / Crear / Descargar) los decide SOLO quien
  /// comparte: son de cada compartido, no del rol del destinatario. La misma
  /// persona puede editar una carpeta y solo ver otra.
  Future<void> _editTargets(String path) async {
    // Los que la tienen se piden al servidor: la lista en pantalla puede
    // estar vieja si alguien más compartió mientras tanto.
    var current = <int>[];
    var permissions = <int, SharePermissions>{};
    var candidates = _candidates;
    try {
      final info = await HsApi.sharedFileTargets(path);
      current = info.targets;
      permissions = info.permissions;
      candidates = info.candidates;
    } catch (_) {
      // Si falla, se usa lo que ya hay en pantalla.
      final rows = _shared.where((s) => '${s['path']}' == path);
      current = rows
          .map((s) => (s['targetId'] as num?)?.toInt() ?? 0)
          .where((n) => n > 0)
          .toList();
      for (final s in rows) {
        final id = (s['targetId'] as num?)?.toInt() ?? 0;
        if (id > 0) {
          permissions[id] = SharePermissions.fromJson(s['permissions']);
        }
      }
    }
    if (!mounted) return;
    final chosen = await _showPermissionsDialog(
      path: path,
      current: current,
      currentPermissions: permissions,
      candidates: candidates,
    );
    if (chosen == null || !mounted) return;

    final toRemove = current.where((id) => !chosen.containsKey(id)).toList();
    try {
      // Todos los elegidos viajan con SUS permisos: el servidor actualiza los
      // que ya la tenían (sin duplicar) y agrega los nuevos.
      if (chosen.isNotEmpty) {
        await HsApi.shareFolderWith(
          path: path,
          userIds: chosen.keys.toList(),
          permissions: chosen,
        );
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
    await _load();
  }

  void _snack(String msg) => HsToast.info(msg);

  // ---------------------------------------------------------------
  // Selector de usuarios
  // ---------------------------------------------------------------

  /// Usuarios + PERMISOS de cada uno. Devuelve el mapa elegido (con sus
  /// permisos) o null si se canceló.
  Future<Map<int, SharePermissions>?> _showPermissionsDialog({
    required String path,
    required List<int> current,
    required Map<int, SharePermissions> currentPermissions,
    required List<Map<String, dynamic>> candidates,
  }) async {
    final selected = <int>{...current};
    final rights = <int, SharePermissions>{
      for (final id in current)
        id: currentPermissions[id] ?? SharePermissions.readOnly,
    };
    final search = TextEditingController();

    /// Enciende/apaga UN permiso. "Ver" es la base: sin ver no hay nada más,
    /// y dar cualquier otro permiso implica poder ver.
    void setPerm(int id, String key, bool on) {
      var p = rights[id] ?? SharePermissions.readOnly;
      p = switch (key) {
        'view' =>
          on
              ? p.copyWith(view: true)
              : const SharePermissions(
                  view: false,
                  edit: false,
                  create: false,
                  download: false,
                ),
        'edit' => p.copyWith(edit: on, view: on || p.view),
        'create' => p.copyWith(create: on, view: on || p.view),
        'download' => p.copyWith(download: on, view: on || p.view),
        _ => p,
      };
      rights[id] = p;
    }

    final result = await showHsModal<Map<int, SharePermissions>>(
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
              width: 500,
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
                  // El CONTEO va en su propio texto: es lo que se mira de un
                  // vistazo al ir marcando usuarios.
                  Row(
                    children: [
                      Text(
                        '${selected.length} seleccionado'
                        '${selected.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '· cada uno con sus permisos',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
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
                            _TargetPermissionsTile(
                              candidate: c,
                              enabled: selected.contains(
                                (c['id'] as num?)?.toInt(),
                              ),
                              rights:
                                  rights[(c['id'] as num?)?.toInt() ?? 0] ??
                                  SharePermissions.readOnly,
                              onEnabled: (on) {
                                final id = (c['id'] as num?)?.toInt() ?? 0;
                                setSt(() {
                                  if (on) {
                                    selected.add(id);
                                    rights.putIfAbsent(
                                      id,
                                      () => SharePermissions.readOnly,
                                    );
                                  } else {
                                    selected.remove(id);
                                  }
                                });
                              },
                              onPerm: (key, on) => setSt(
                                () => setPerm(
                                  (c['id'] as num?)?.toInt() ?? 0,
                                  key,
                                  on,
                                ),
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
                onPressed: () => Navigator.of(ctx).pop({
                  for (final id in selected)
                    id: rights[id] ?? SharePermissions.readOnly,
                }),
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

    // ===== Carpeta compartida ABIERTA: la MISMA vista del Drive, AQUÍ MISMO
    // (la sección cambia de vista; no se abre otra ventana).
    final open = _open;
    if (open != null) {
      return DrivePage(
        drive: open,
        title: open.label,
        subtitle: _openIsMine
            ? 'Lo que comparto · toca las migas para subir'
            : 'Compartido conmigo · toca las migas para subir',
        onBack: _closeOpen,
        backTooltip: 'Volver a Archivos compartidos',
        // La miga raíz de este drive es ESTE módulo: vuelve al listado.
        onRootTap: _closeOpen,
        // Se abre con la vista que el usuario tenía puesta en el listado.
        initialGrid: _grid,
      );
    }
    // ===== No se pudo abrir: el motivo, en pantalla =====
    // ATRÁS vuelve al listado (no cierra el módulo): es una "ventana" más.
    final problem = _openProblem;
    if (problem != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _closeOpen();
        },
        child: _openProblemView(scheme, isCompact, problem),
      );
    }

    final received = _receivedFolders;
    final mine = _myFolders;
    final current = _view == _SharedView.shared ? received : mine;

    return Column(
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
        // ===== Barra de estado =====
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 6),
          child: _statusBar(scheme, current),
        ),
        // ===== Contenido =====
        // Se recarga DESLIZANDO hacia abajo (no hay botón de recargar): el
        // gesto funciona también con el ratón, así que vale en todas las
        // pantallas —como en el resto de los módulos—.
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _content(scheme, isCompact, received, mine),
          ),
        ),
      ],
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
                      // Sin botón de recargar: en el celular se recarga
                      // deslizando hacia abajo (RefreshIndicator).
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
                    _page = 1;
                    _searchController.clear();
                  }),
                ),
                const SizedBox(height: 14),
                // Buscador + filtros + conmutador de vista (igual que el Drive).
                HsSearchFilterBar(
                  hint: 'Buscar carpeta o persona',
                  controller: _searchController,
                  onChanged: (_) => setState(() => _page = 1),
                  groups: _filterGroups(),
                  selected: {'origen': _originFilter},
                  onApply: (filters) => setState(() {
                    _originFilter = filters['origen'] ?? '';
                    _page = 1;
                  }),
                  trailing: Tooltip(
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// La carpeta no se pudo abrir: se dice QUÉ pasó (con el motivo del
  /// servidor) y qué hace falta para verla, con un botón para reintentar.
  Widget _openProblemView(
    ColorScheme scheme,
    bool isCompact,
    ({Map<String, dynamic> entry, String detail, String hint}) problem,
  ) {
    final name = '${problem.entry['path'] ?? ''}'
        .split(RegExp(r'[\\/]'))
        .where((s) => s.isNotEmpty)
        .lastOrNull;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        isCompact ? 14 : 24,
        24,
        isCompact ? 14 : 24,
        24,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.folder_off_outlined,
                          size: 26,
                          color: scheme.error,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            name == null
                                ? 'No se pudo abrir la carpeta'
                                : 'No se pudo abrir "$name"',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // El motivo TAL CUAL lo dio el servidor del drive.
                    Text(
                      problem.detail,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: .07),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: scheme.primary.withValues(alpha: .22),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              problem.hint,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => unawaited(_openEntry(problem.entry)),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Reintentar'),
                        ),
                        TextButton.icon(
                          onPressed: _closeOpen,
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: const Text('Volver a Archivos compartidos'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
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
    final folders = current.length;
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
    if (_view == _SharedView.shared) {
      return _folderGrid(
        scheme,
        isCompact,
        entries: [
          for (final r in received)
            if (_matchesOrigin(r) &&
                _matches('${r['path']} ${_ownerNames(r).join(' ')}'))
              r,
        ],
        empty: EmptyState(
          icon: Icons.inbox_outlined,
          title: 'Nadie te ha compartido carpetas',
          message: _filter != null || _originFilter.isNotEmpty
              ? 'Ninguna carpeta coincide con la búsqueda o el filtro.'
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
          if (_matchesOrigin(m) &&
              _matches('${m['path']} ${_targetNames(m).join(' ')}'))
            m,
      ],
      empty: EmptyState(
        icon: Icons.outbox_outlined,
        title: 'Todavía no compartes carpetas',
        message: _filter != null || _originFilter.isNotEmpty
            ? 'Ninguna carpeta coincide con la búsqueda o el filtro.'
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
    // Paginado: la cuadrícula/lista muestra la página actual y la barra va
    // fija ABAJO, para no perderla al bajar entre carpetas.
    final rows = HsPages(
      total: entries.length,
      page: _page,
      pageSize: _pageSize,
    ).slice(entries);
    final footer = Padding(
      padding: EdgeInsets.fromLTRB(
        isCompact ? 14 : 24,
        0,
        isCompact ? 14 : 24,
        isCompact ? 6 : 10,
      ),
      child: HsPager(
        total: entries.length,
        page: _page,
        pageSize: _pageSize,
        onPage: (p) => setState(() => _page = p),
        onPageSize: (n) => setState(() {
          _pageSize = n;
          _page = 1;
        }),
      ),
    );
    Widget body;
    if (_grid) {
      body = LayoutBuilder(
        builder: (context, constraints) {
          final minCard = isCompact ? 150.0 : 190.0;
          final crossCount = (constraints.maxWidth / minCard).floor().clamp(
            2,
            8,
          );
          return GridView.builder(
            controller: _scrollController,
            // Mismo ritmo que la cuadrícula del Drive: mismos márgenes, mismo
            // espacio entre tarjetas y mismo alto relativo al ancho.
            padding: EdgeInsets.fromLTRB(
              isCompact ? 14 : 24,
              4,
              isCompact ? 14 : 24,
              isCompact ? 150 : 110,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossCount,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              // Alto FIJO: la tarjeta lleva la ficha del compartido, quién lo
              // comparte y su estado; en una tarjeta angosta el texto ocupa
              // más renglones y con altura proporcional se recortaba. Ahora
              // que permisos y estado van en una fila, las tarjetas quedan
              // parecidas a las del Drive.
              mainAxisExtent: isCompact ? 226 : 232,
            ),
            itemCount: rows.length,
            itemBuilder: (context, i) => Listener(
              // El TIPO de puntero decide si un clic entra (dedo) o solo marca
              // (ratón, donde el doble clic es el que entra).
              onPointerDown: (e) => _lastPointerKind = e.kind,
              child: _FolderCard(
                entry: rows[i],
                shared: _view == _SharedView.shared,
                status: _statusOf(rows[i]),
                marked: _markedPath == '${rows[i]['path'] ?? ''}',
                onTap: () => _onFolderTap(rows[i]),
                onOpen: () => onOpen(rows[i]),
                onEdit: _view == _SharedView.mine && _canPickFolder
                    ? () => _editTargets('${rows[i]['path'] ?? ''}')
                    : null,
                onUnshare: _view == _SharedView.mine && _canUnshare
                    ? () => _unshareAll(
                        '${rows[i]['path'] ?? ''}',
                        _targetIds(rows[i]),
                      )
                    : null,
                onDownload: _canDownload(rows[i])
                    ? () => _downloadFolder(rows[i])
                    : null,
              ),
            ),
          );
        },
      );
    } else {
      body = ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(
          isCompact ? 14 : 24,
          4,
          isCompact ? 14 : 24,
          24,
        ),
        itemCount: rows.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Listener(
            onPointerDown: (e) => _lastPointerKind = e.kind,
            child: _FolderRow(
              entry: rows[i],
              shared: _view == _SharedView.shared,
              status: _statusOf(rows[i]),
              marked: _markedPath == '${rows[i]['path'] ?? ''}',
              onTap: () => _onFolderTap(rows[i]),
              onOpen: () => onOpen(rows[i]),
              onEdit: _view == _SharedView.mine && _canPickFolder
                  ? () => _editTargets('${rows[i]['path'] ?? ''}')
                  : null,
              onUnshare: _view == _SharedView.mine && _canUnshare
                  ? () => _unshareAll(
                      '${rows[i]['path'] ?? ''}',
                      _targetIds(rows[i]),
                    )
                  : null,
              onDownload: _canDownload(rows[i])
                  ? () => _downloadFolder(rows[i])
                  : null,
            ),
          ),
        ),
      );
    }
    return Column(
      children: [
        Expanded(child: body),
        footer,
      ],
    );
  }

  /// ¿Puedo descargar esta carpeta? (en las mías, siempre).
  bool _canDownload(Map<String, dynamic> entry) =>
      _view == _SharedView.mine ||
      SharePermissions.fromJson(entry['permissions']).download;

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

/// Permisos que resumen una entrada del listado.
///
/// En una carpeta MÍA, la unión de lo que di a cada destinatario; en una
/// RECIBIDA, lo que puedo hacer yo (sumando a todos los dueños).
SharePermissions _entryPermissions(Map<String, dynamic> entry, bool shared) {
  if (shared) return SharePermissions.fromJson(entry['permissions']);
  var out = const SharePermissions(
    view: false,
    edit: false,
    create: false,
    download: false,
  );
  for (final t in ((entry['targets'] as List?) ?? const [])) {
    if (t is Map) out = out.merge(SharePermissions.fromJson(t['permissions']));
  }
  return out;
}

/// Iconos compactos de los permisos (con su tooltip), para la ficha.
class _PermIcons extends StatelessWidget {
  const _PermIcons({required this.perms});

  final SharePermissions perms;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = <(IconData, String)>[
      if (perms.view) (Icons.visibility_outlined, 'Ver'),
      if (perms.download) (Icons.download_rounded, 'Descargar'),
      if (perms.edit) (Icons.edit_outlined, 'Editar'),
      if (perms.create) (Icons.create_new_folder_outlined, 'Crear'),
    ];
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final e in entries)
          Tooltip(
            message: e.$2,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(e.$1, size: 12, color: scheme.primary),
            ),
          ),
      ],
    );
  }
}

/// Una fila del diálogo de permisos: el usuario y, si está elegido, lo que
/// podrá hacer en ESA carpeta.
class _TargetPermissionsTile extends StatelessWidget {
  const _TargetPermissionsTile({
    required this.candidate,
    required this.enabled,
    required this.rights,
    required this.onEnabled,
    required this.onPerm,
  });

  final Map<String, dynamic> candidate;
  final bool enabled;
  final SharePermissions rights;
  final ValueChanged<bool> onEnabled;
  final void Function(String key, bool on) onPerm;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget chip(String key, String label, bool value) => Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 4),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 11.5)),
        selected: value,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onSelected: enabled ? (v) => onPerm(key, v) : null,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Checkbox(
                value: enabled,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => onEnabled(v == true),
              ),
              // El NOMBRE también marca y desmarca: con el dedo o el ratón se
              // toca la fila, no el cuadradito.
              Expanded(
                child: InkWell(
                  onTap: () => onEnabled(!enabled),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${candidate['name'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                        Text(
                          [
                            if ('${candidate['role'] ?? ''}'.isNotEmpty)
                              '${candidate['role']}',
                            if ('${candidate['email'] ?? ''}'.isNotEmpty)
                              '${candidate['email']}',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (enabled)
                Text(
                  rights.label.isEmpty ? 'Sin acceso' : rights.label,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (enabled)
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Wrap(
                children: [
                  chip('view', 'Ver', rights.view),
                  chip('edit', 'Editar', rights.edit),
                  chip('create', 'Crear', rights.create),
                  chip('download', 'Descargar', rights.download),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

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
    required this.onTap,
    required this.onOpen,
    this.marked = false,
    this.status,
    this.onUnshare,
    this.onEdit,
    this.onDownload,
  });

  final Map<String, dynamic> entry;

  /// true = la recibí (muestra quién la comparte); false = es mía.
  final bool shared;

  /// Un clic/toque sobre la tarjeta (marca o entra, según el puntero).
  final VoidCallback onTap;

  /// Abre la carpeta AQUÍ MISMO (este módulo nunca salta a Archivos).
  final VoidCallback onOpen;

  /// Marcada con un clic (en la computadora el doble clic es el que entra).
  final bool marked;

  /// De dónde se puede servir AHORA (null = todavía sin comprobar).
  final LocalShareStatus? status;

  /// Elegir qué usuarios la reciben (solo en una carpeta MÍA).
  final VoidCallback? onEdit;
  final VoidCallback? onUnshare;

  /// Descargar la carpeta entera (ZIP).
  final VoidCallback? onDownload;

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
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: marked
                    ? scheme.primary
                    : hovered
                    ? scheme.primary.withValues(alpha: .45)
                    : Colors.transparent,
                width: 2.5,
              ),
              // La carpeta MARCADA se tiñe: se distingue de la que solo tiene
              // el ratón encima (esa lleva un borde suave).
              color: marked ? scheme.primary.withValues(alpha: .10) : null,
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
                      _EntryMenu(
                        onOpen: onOpen,
                        onEdit: onEdit,
                        onUnshare: onUnshare,
                        onDownload: onDownload,
                      ),
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
                      const SizedBox(height: 6),
                      // La FICHA del compartido va AQUÍ, en el listado: de dónde
                      // es la carpeta, quién la comparte (o quién la recibe) y
                      // si se puede servir ahora mismo. Antes esto salía dentro
                      // de la carpeta abierta.
                      Row(
                        children: [
                          Flexible(
                            child: _typeChip(
                              scheme,
                              local
                                  ? (shared
                                        ? 'Carpeta de su computadora'
                                        : 'Carpeta de tu computadora')
                                  : (shared
                                        ? 'Carpeta del Drive'
                                        : 'Carpeta de tu Drive'),
                            ),
                          ),
                        ],
                      ),
                      if (people.isNotEmpty) ...[
                        const SizedBox(height: 4),
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
                      const SizedBox(height: 6),
                      // Permisos y estado en UNA fila compacta: la tarjeta se
                      // lee como la del Drive (nombre + ficha corta) y no se
                      // alarga con tres renglones sueltos.
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Lo que se concedió (o lo que YO puedo hacer): se ve
                          // en el listado sin abrir el diálogo de permisos.
                          _PermIcons(
                            perms: _entryPermissions(entry, shared),
                          ),
                          _ShareStatusPill(status: status),
                        ],
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
    required this.onTap,
    required this.onOpen,
    this.marked = false,
    this.status,
    this.onUnshare,
    this.onEdit,
    this.onDownload,
  });

  final Map<String, dynamic> entry;
  final bool shared;

  /// Un clic/toque sobre la fila (marca o entra, según el puntero).
  final VoidCallback onTap;

  /// Abre la carpeta AQUÍ MISMO (este módulo nunca salta a Archivos).
  final VoidCallback onOpen;

  /// Marcada con un clic (en la computadora el doble clic es el que entra).
  final bool marked;

  /// De dónde se puede servir AHORA (null = todavía sin comprobar).
  final LocalShareStatus? status;

  /// Elegir qué usuarios la reciben (solo en una carpeta MÍA).
  final VoidCallback? onEdit;
  final VoidCallback? onUnshare;

  /// Descargar la carpeta entera (ZIP).
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // En un teléfono la fila lleva el nombre, la ficha, el estado y el menú:
    // los iconos de permisos NO caben (el estado, sí: se recorta solo).
    final compact = MediaQuery.sizeOf(context).width < 620;
    final local = entry['local'] == true;
    final path = '${entry['path'] ?? ''}';
    final people = shared
        ? _names(entry, 'owners', 'name')
        : _names(entry, 'targets', 'targetName');

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: marked ? scheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      color: marked ? scheme.primary.withValues(alpha: .08) : null,
      child: InkWell(
        onTap: onTap,
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
                    const SizedBox(height: 3),
                    // La ficha del compartido vive en el LISTADO: de dónde es
                    // la carpeta y quién la comparte (o quién la recibe).
                    Row(
                      children: [
                        Flexible(
                          child: _typeChip(
                            scheme,
                            local
                                ? (shared
                                      ? 'Carpeta de su computadora'
                                      : 'Carpeta de tu computadora')
                                : (shared
                                      ? 'Carpeta del Drive'
                                      : 'Carpeta de tu Drive'),
                          ),
                        ),
                        if (people.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              shared
                                  ? 'Compartida por ${people.join(', ')}'
                                  : 'Con ${people.join(', ')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 8),
                _PermIcons(perms: _entryPermissions(entry, shared)),
              ],
              const SizedBox(width: 8),
              // Va FLEXIBLE: una etiqueta larga ("Servidor sin base de datos")
              // se recorta en vez de desbordar la fila.
              Flexible(child: _ShareStatusPill(status: status, dense: true)),
              // El mismo menú "⋮" del Drive: Ver, Descargar, Permisos y
              // Eliminar (dejar de compartir).
              _EntryMenu(
                onOpen: onOpen,
                onEdit: onEdit,
                onUnshare: onUnshare,
                onDownload: onDownload,
              ),
              IconButton(
                tooltip: 'Ver el contenido',
                visualDensity: VisualDensity.compact,
                onPressed: onOpen,
                icon: const Icon(Icons.chevron_right_rounded, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip con la FICHA de un compartido ("Carpeta de tu computadora", "Carpeta
/// del Drive"…): se pinta en el LISTADO, junto a la carpeta, para saber de un
/// vistazo de dónde es sin tener que abrirla.
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
      // En una tarjeta angosta (celular) la ficha se recorta: nunca desborda.
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: scheme.primary,
      ),
    ),
  );
}

/// Menú "⋮" de una carpeta compartida: dice, con sus iconos, QUÉ se puede
/// hacer con esa carpeta.
///
/// Es el mismo menú de las tarjetas del Drive. Para una carpeta que YO comparto
/// salen las cuatro acciones —**Ver** el contenido, **Descargar** la carpeta,
/// **Editar** los usuarios que la reciben y **Eliminar** el compartido— y en
/// una que me comparten, las que sí se pueden: Ver y Descargar (ahí el servidor
/// no ofrece escritura, así que no se finge que se puede).
class _EntryMenu extends StatelessWidget {
  const _EntryMenu({
    required this.onOpen,
    this.onEdit,
    this.onUnshare,
    this.onDownload,
  });

  final VoidCallback onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onUnshare;
  final VoidCallback? onDownload;

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
        if (v == 'edit') onEdit?.call();
        if (v == 'unshare') onUnshare?.call();
        if (v == 'download') onDownload?.call();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'open',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.visibility_outlined, size: 18),
            title: Text('Ver el contenido'),
          ),
        ),
        if (onDownload != null)
          const PopupMenuItem(
            value: 'download',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.download_rounded, size: 18),
              title: Text('Descargar'),
            ),
          ),
        if (onEdit != null)
          const PopupMenuItem(
            value: 'edit',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.admin_panel_settings_outlined, size: 18),
              title: Text('Editar destinatarios'),
              subtitle: Text(
                'Permisos: ver, editar, crear y descargar',
                style: TextStyle(fontSize: 10.5),
              ),
            ),
          ),
        if (onUnshare != null)
          const PopupMenuItem(
            value: 'unshare',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline_rounded, size: 18),
              title: Text('Eliminar el compartido'),
            ),
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

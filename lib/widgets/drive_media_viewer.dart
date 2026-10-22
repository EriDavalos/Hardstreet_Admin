import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

import '../app_platform.dart';
import '../drive_base.dart';
import '../open_file.dart';
import '../theme.dart';
import '../webview_env.dart';
import '../window_fullscreen.dart';
import 'drive_file_visuals.dart';
import 'drive_web_player.dart';
import 'hs_modal.dart';

// ==================================================================
// VISOR DE ARCHIVOS DEL DRIVE (todo lo que NO es una foto)
// ==================================================================
// Antes, al tocar un vídeo o un PDF el panel abría el visor de imágenes y
// quedaba una superficie negra: el visor solo sabía de fotos. Aquí vive lo
// que sí sabe abrir cada tipo:
//
//   * VÍDEO y AUDIO → reproductor HTML5 (navegador integrado), que ya trae
//     controles, volumen, pantalla completa y "seguir cargando" solo. El
//     archivo se sirve por HTTP desde el drive y se reproduce sin descargarlo
//     entero (un vídeo grande empieza en segundos).
//   * TEXTO → se lee aquí mismo (txt, csv, json, md, log…).
//   * PDF → se ve en el navegador integrado de la computadora (el de Android
//     no sabe pintar PDF: allí se ofrece descargarlo).
//   * CUALQUIER OTRO (zip, docx, psd…) → no hay visor que valga: se dice tal
//     cual y se ofrece DESCARGARLO o ABRIRLO con el programa del sistema.
//
// El reproductor es inyectable ([debugFilePlayerBuilder]) porque el navegador
// integrado no existe en el entorno de pruebas.
// ==================================================================

/// Fuente ya resuelta para el visor: la URL del archivo (http/https) y, si
/// vive en el disco de esta computadora, también su ruta.
@immutable
class DriveViewTarget {
  const DriveViewTarget({
    required this.item,
    required this.source,
    required this.isRemote,
    this.localPath = '',
    this.poster = '',
  });

  final DriveItem item;

  /// URL lista para el navegador integrado (`http(s)://…` o `file://…`).
  final String source;

  /// Ruta en el disco (vacía si el archivo se sirve por red).
  final String localPath;

  /// true = se sirve por RED (drive del servidor o carpeta compartida).
  final bool isRemote;

  /// Miniatura que el reproductor enseña MIENTRAS carga el vídeo (el primer
  /// fotograma que ya genera el servidor). Vacío = no hay póster.
  final String poster;

  DriveItemKind get kind => item.kind;
}

/// Reproductor de mentira para las pruebas: el navegador integrado no existe
/// en el entorno de pruebas y, sin esto, abrir un vídeo en un test reventaría.
@visibleForTesting
Widget Function(BuildContext context, DriveViewTarget target)?
debugFilePlayerBuilder;

/// Lectura de mentira para las pruebas: leer un archivo de verdad dentro de un
/// `testWidgets` no termina nunca (el reloj del test está simulado).
@visibleForTesting
Future<String> Function(DriveViewTarget target)? debugTextLoader;

/// Posturas que pide la PANTALLA COMPLETA del visor.
///
/// Un vídeo horizontal gira el teléfono a apaisado; uno vertical se queda de
/// pie. `null` (salir de pantalla completa, un audio sin imagen o medidas
/// todavía desconocidas) deja todas las posturas libres.
@visibleForTesting
List<DeviceOrientation>? fullscreenOrientationsFor({required bool? horizontal}) {
  if (horizontal == null) return null;
  return horizontal
      ? const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]
      : const [DeviceOrientation.portraitUp];
}

/// Abre el archivo [item] con el visor que le corresponde.
///
/// [playlist] (opcional) son los vídeos/audios de la misma carpeta, para poder
/// pasar al siguiente sin salir; [initialIndex] es el que se abre.
Future<void> showDriveFileViewer(
  BuildContext context, {
  required DriveBase drive,
  required DriveItem item,
  List<DriveItem> playlist = const <DriveItem>[],
  int initialIndex = 0,
  Future<void> Function(DriveItem item)? onDownload,
}) {
  final list = playlist.isEmpty ? <DriveItem>[item] : playlist;
  return showHsModal<void>(
    context: context,
    builder: (_) => DriveFileViewer(
      drive: drive,
      items: list,
      initialIndex: initialIndex.clamp(0, list.length - 1),
      onDownload: onDownload,
    ),
  );
}

class DriveFileViewer extends StatefulWidget {
  const DriveFileViewer({
    super.key,
    required this.drive,
    required this.items,
    required this.initialIndex,
    this.onDownload,
  });

  final DriveBase drive;

  /// Archivos entre los que se puede pasar (los vídeos/audios de la carpeta).
  final List<DriveItem> items;
  final int initialIndex;
  final Future<void> Function(DriveItem item)? onDownload;

  @override
  State<DriveFileViewer> createState() => _DriveFileViewerState();
}

class _DriveFileViewerState extends State<DriveFileViewer> {
  late int _index = widget.initialIndex;

  /// Texto del archivo (solo para los tipos de texto).
  String? _text;
  bool _loadingText = false;
  String? _textError;

  /// Lo que dijo el navegador integrado al no poder abrir el archivo.
  String? _playerError;

  /// Se está abriendo con el sistema (descarga + lanzar el programa).
  bool _opening = false;

  /// Entorno de WebView2 ya preparado (Windows) y si ya se intentó.
  ///
  /// En una instalación de Windows (Archivos de programa) el WebView no puede
  /// usar la carpeta de datos de junto al .exe. Se crea uno propio, escribible,
  /// y el reproductor no se pinta hasta tenerlo: si no, el `<video>` nacía en
  /// un WebView que nunca llegó a arrancar (pantalla negra en el release).
  WebViewEnvironment? _webEnv;
  bool _webReady = false;

  /// Pantalla completa del VISOR: se ocultan la barra superior y las flechas
  /// para que el vídeo ocupe todo. El botón de pantalla completa del
  /// reproductor HTML llama aquí (en la app la API del navegador no siempre
  /// existe; en Windows el WebView no la atiende).
  bool _immersive = false;

  /// ¿El vídeo es HORIZONTAL? Lo avisa el propio reproductor HTML en cuanto
  /// conoce las dimensiones reales del archivo. En pantalla completa el
  /// teléfono gira a apaisado solo si el vídeo es horizontal; si es vertical
  /// se queda de pie.
  bool? _videoLandscape;

  DriveItem get _item => widget.items[_index];

  bool get _canMove => widget.items.length > 1;

  /// ¿Esta plataforma puede GIRAR la pantalla? (teléfono/tableta)
  bool get _canRotate => isAndroidPlatform || isIOSPlatform;

  void _toggleFullscreen({bool? horizontal}) {
    if (!mounted) return;
    // WEB: el panel ya ocupa toda la ventana; lo que falta es la pantalla
    // completa del NAVEGADOR. Hay que pedirla desde la página: el reproductor
    // vive en un iframe y, si se pide desde dentro, el navegador solo la
    // aplica al recuadro del iframe (por eso "no hacía nada").
    if (kWeb) {
      unawaited(driveWebToggleFullscreen());
      return;
    }
    final next = !_immersive;
    setState(() => _immersive = next);
    // WINDOWS: la ventana de verdad pasa a pantalla completa (sin bordes y
    // sobre el monitor). En Android se esconden las barras del sistema.
    if (isWindowsPlatform) unawaited(hsSetWindowFullscreen(next));
    SystemChrome.setEnabledSystemUIMode(
      next ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    // TELÉFONO: en pantalla completa se gira según el vídeo (ver
    // [_applyFullscreenOrientation]). Al salir vuelven todas las posturas.
    _applyFullscreenOrientation(
      next ? (horizontal ?? _videoLandscape) : null,
    );
    // El GIRO puede devolver las barras del sistema a su sitio: se vuelven a
    // ocultar un instante después para que la pantalla quede limpia del todo.
    if (next && _canRotate) {
      Timer(const Duration(milliseconds: 450), () {
        if (!mounted || !_immersive) return;
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      });
    }
  }

  /// Gira el TELÉFONO en pantalla completa: apaisado para un vídeo horizontal y
  /// vertical para uno de pie. Con `null` (salir de pantalla completa, o un
  /// audio sin imagen) se devuelven todas las posturas.
  ///
  /// Antes no se tocaba la orientación: un vídeo horizontal se veía en una
  /// franja pequeña en medio de la pantalla vertical y "no se ponía del todo".
  void _applyFullscreenOrientation(bool? horizontal) {
    if (!_canRotate) return;
    final orientations = fullscreenOrientationsFor(horizontal: horizontal);
    unawaited(
      SystemChrome.setPreferredOrientations(
        orientations ?? DeviceOrientation.values,
      ),
    );
  }

  /// Lee (ancho, alto) que manda el reproductor HTML y dice si el vídeo es
  /// horizontal. `null` cuando todavía no se conocen las medidas.
  static bool? _videoIsHorizontal(List<dynamic> args) {
    if (args.length < 2) return null;
    final w = double.tryParse('${args[0]}') ?? 0;
    final h = double.tryParse('${args[1]}') ?? 0;
    if (w <= 0 || h <= 0) return null;
    return w > h;
  }

  @override
  void initState() {
    super.initState();
    _prepare();
    _bootWebView();
  }

  /// Duración REAL del vídeo, leída del servidor.
  ///
  /// La "calidad ligera" llega en MP4 FRAGMENTADO y no trae la duración en la
  /// cabecera: el navegador ve `Infinity`, la barra no avanza y el total sale
  /// mal. El servidor la calcula con ffmpeg y la manda en `X-Video-Duration`;
  /// aquí se le pasa al reproductor para que la barra use los minutos de
  /// verdad desde el primer segundo.
  Future<void> _applyDuration(
    InAppWebViewController controller,
    DriveViewTarget target,
  ) async {
    if (kWeb || !target.isRemote || target.item.kind != DriveItemKind.video) {
      return;
    }
    try {
      // Se pregunta por el ORIGINAL (sin `play=low`): el HEAD no tiene que
      // arrancar el reencodado, solo dar la duración.
      final uri = Uri.parse(target.source);
      final query = Map<String, String>.from(uri.queryParameters)
        ..remove('play');
      final head = await http
          .head(uri.replace(queryParameters: query.isEmpty ? null : query))
          .timeout(const Duration(seconds: 6));
      final seconds =
          double.tryParse(head.headers['x-video-duration'] ?? '') ?? 0;
      if (seconds <= 0) return;
      await controller.evaluateJavascript(
        source:
            'window.hsSetDuration&&hsSetDuration('
            '${seconds.toStringAsFixed(3)})',
      );
    } catch (_) {
      // Sin duración se usa la que diga el navegador, como antes.
    }
  }

  /// Prepara el entorno del navegador integrado (solo Windows lo necesita).
  Future<void> _bootWebView() async {
    final env = await sharedWebViewEnvironment();
    if (!mounted) return;
    setState(() {
      _webEnv = env;
      _webReady = true;
    });
  }

  @override
  void dispose() {
    // El visor se cierra (o cambia de archivo) sin salir de pantalla completa:
    // las barras del sistema vuelven a su sitio.
    if (_immersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      // Cerrar el visor en pantalla completa devuelve la ventana a su sitio;
      // si no, el panel entero se quedaría sin bordes.
      if (isWindowsPlatform) unawaited(hsSetWindowFullscreen(false));
    }
    // Si se cierra el visor en pantalla completa, el teléfono no puede quedar
    // clavado en apaisado: se devuelven todas las posturas.
    _applyFullscreenOrientation(null);
    super.dispose();
  }

  void _prepare() {
    _playerError = null;
    _text = null;
    _textError = null;
    // Otro archivo = otras medidas: se vuelven a preguntar al cargar.
    _videoLandscape = null;
    if (_item.kind == DriveItemKind.text) unawaited(_loadText());
  }

  void _move(int delta) {
    if (!_canMove) return;
    final next = (_index + delta) % widget.items.length;
    setState(() {
      _index = next < 0 ? next + widget.items.length : next;
      _prepare();
    });
  }

  /// Fuente del archivo para el navegador integrado.
  DriveViewTarget _target(DriveItem item) {
    // Los vídeos GRANDES se piden en CALIDAD LIGERA: el servidor los reencoda
    // al vuelo (720p) y el reproductor empieza en segundos, en vez de esperar a
    // que cruce el archivo entero por la conexión de quien comparte.
    final raw = widget.drive.playSource(item);
    // Póster: la misma miniatura del listado, a más resolución. Hace que el
    // reproductor no quede en negro mientras llega el primer fotograma.
    final poster = widget.drive.isRemote && widget.drive.canThumb(item)
        ? widget.drive.thumbSource(item, width: 1280)
        : '';
    if (widget.drive.isRemote || kWeb) {
      return DriveViewTarget(
        item: item,
        source: raw,
        isRemote: true,
        poster: poster,
      );
    }
    // Drive del DISCO (una carpeta real del equipo): el navegador necesita un
    // `file://`, no una ruta de Windows.
    return DriveViewTarget(
      item: item,
      source: Uri.file(raw).toString(),
      localPath: raw,
      isRemote: false,
      poster: poster,
    );
  }

  /// Lee el archivo de TEXTO (por red o del disco) para enseñarlo aquí.
  Future<void> _loadText() async {
    final item = _item;
    final target = _target(item);
    setState(() {
      _loadingText = true;
      _textError = null;
    });
    try {
      final fake = debugTextLoader;
      if (fake != null) {
        final body = await fake(target);
        if (!mounted || item.name != _item.name) return;
        setState(() {
          _text = body;
          _loadingText = false;
        });
        return;
      }
      String body;
      if (target.isRemote) {
        final res = await http
            .get(Uri.parse(target.source))
            .timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) {
          throw 'El servidor contestó ${res.statusCode}';
        }
        body = _decodeText(res.bodyBytes);
      } else {
        body = _decodeText(await File(target.localPath).readAsBytes());
      }
      if (!mounted || item.name != _item.name) return;
      setState(() {
        // Un archivo enorme no se pinta entero: los primeros 200 000
        // caracteres ya dejan leerlo (y avisan de que hay más).
        _text = body.length > 200000 ? '${body.substring(0, 200000)}…' : body;
        _loadingText = false;
      });
    } catch (e) {
      if (!mounted || item.name != _item.name) return;
      setState(() {
        _loadingText = false;
        _textError = '$e';
      });
    }
  }

  /// Texto de los bytes: se respeta el UTF-8 y, si viene con otra codificación
  /// (un CSV de Excel), se cae a latin-1 en vez de romper los acentos.
  static String _decodeText(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  /// Abre el archivo con el programa del sistema (descargándolo si hace falta).
  Future<void> _openWithSystem(DriveItem item) async {
    final target = _target(item);
    setState(() => _opening = true);
    final ok = target.isRemote
        ? await hsOpenUrlFile(target.source, name: item.name)
        : await hsOpenLocalFile(target.localPath);
    if (!mounted) return;
    setState(() => _opening = false);
    if (!ok) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('No se pudo abrir "${item.name}"')),
      );
    }
  }

  /// ¿Se puede intentar VER aquí mismo este archivo?
  bool get _canPreview => switch (_item.kind) {
    DriveItemKind.video || DriveItemKind.audio => true,
    // El navegador integrado de Android no sabe pintar PDF.
    DriveItemKind.pdf => !isAndroidPlatform,
    DriveItemKind.text => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return PopScope(
      // ATRÁS sale primero de pantalla completa; el visor se cierra después.
      canPop: !_immersive,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !_immersive) return;
        _toggleFullscreen();
      },
      child: Dialog.fullscreen(
        backgroundColor: const Color(0xFF101014),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: _body(item)),
            if (!_immersive) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 8, 8, 12),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: SafeArea(bottom: false, child: _bar(item)),
                ),
              ),
              if (_canMove) ..._arrows(),
            ] else
              // Salida visible: con la barra oculta no habría forma de volver
              // (ESC y ATRÁS también salen).
              Positioned(
                top: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: _RoundAction(
                      icon: Icons.fullscreen_exit_rounded,
                      tooltip: 'Salir de pantalla completa',
                      onTap: _toggleFullscreen,
                    ),
                  ),
                ),
              ),
            if (_playerError != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(top: false, child: _errorBar(item)),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _arrows() => [
    Positioned(
      left: 6,
      top: 0,
      bottom: 0,
      child: Center(
        child: _RoundAction(
          icon: Icons.chevron_left,
          tooltip: 'Anterior',
          onTap: () => _move(-1),
        ),
      ),
    ),
    Positioned(
      right: 6,
      top: 0,
      bottom: 0,
      child: Center(
        child: _RoundAction(
          icon: Icons.chevron_right,
          tooltip: 'Siguiente',
          onTap: () => _move(1),
        ),
      ),
    ),
  ];

  Widget _body(DriveItem item) {
    final target = _target(item);
    switch (item.kind) {
      case DriveItemKind.video:
      case DriveItemKind.audio:
      case DriveItemKind.pdf:
        if (!_canPreview) return _noPreview(item);
        return _player(target);
      case DriveItemKind.text:
        return _textView();
      case DriveItemKind.image:
        // Una foto se abre en SU visor (con zoom y flechas).
        return _noPreview(
          item,
          message: 'Las fotos se abren en el visor de imágenes.',
        );
      default:
        return _noPreview(item);
    }
  }

  Widget _player(DriveViewTarget target) {
    final build = debugFilePlayerBuilder;
    if (build != null) return build(context, target);
    final html = _playerHtml(target, nativeShell: !kWeb);
    // En la WEB no existe el WebView nativo: se incrusta el mismo HTML en un
    // iframe. Antes el visor intentaba abrir InAppWebView y el vídeo no
    // cargaba (solo funcionaba en escritorio).
    if (kWeb) {
      return driveWebPlayer(
        context,
        html: html,
        cacheKey:
            '${target.item.name.hashCode}-${target.source.hashCode}-${target.poster.hashCode}',
      );
    }
    // El navegador todavía no tiene su carpeta de datos lista: se espera (es
    // cuestión de milisegundos) antes de crear el WebView. Sin esto, en el
    // release instalado el WebView se creaba con la carpeta de junto al .exe
    // —que no se puede escribir— y el vídeo no llegaba a verse nunca.
    if (!_webReady) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    return InAppWebView(
      webViewEnvironment: _webEnv,
      key: ValueKey('drive-file-player-${target.item.name}'),
      initialData: InAppWebViewInitialData(
        data: html,
        baseUrl: WebUri('about:blank'),
      ),
      // El botón de pantalla completa del reproductor pide al PANEL que oculte
      // sus barras (la API de pantalla completa del navegador no funciona en
      // el WebView de Windows).
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'hsPlayerFullscreen',
          // El reproductor manda las medidas del vídeo: con eso se decide si
          // el teléfono tiene que girar a apaisado o quedarse de pie.
          callback: (args) {
            final horizontal = _videoIsHorizontal(args);
            if (mounted) _toggleFullscreen(horizontal: horizontal);
            return null;
          },
        );
        // Dimensiones reales en cuanto el archivo las conoce: aunque la
        // pantalla completa se pida desde la barra de la app (no desde el
        // reproductor), se sabe para dónde girar.
        controller.addJavaScriptHandler(
          handlerName: 'hsPlayerMeta',
          callback: (args) {
            final landscape = _videoIsHorizontal(args);
            if (!mounted) return null;
            setState(() => _videoLandscape = landscape);
            // Si ya está en pantalla completa y todavía no se había girado
            // (el vídeo no había dado sus medidas), se gira AHORA.
            if (_immersive && landscape != null) {
              _applyFullscreenOrientation(landscape);
            }
            return null;
          },
        );
      },
      // La página ya tiene montado el reproductor: se le pasa la duración real
      // (el HTML la usa para el total y para la barra).
      onLoadStop: (controller, _) {
        unawaited(_applyDuration(controller, target));
      },
      initialSettings: InAppWebViewSettings(
        // Sin un toque previo: el vídeo empieza al abrirlo (es lo que el
        // usuario acaba de pedir) y suena con los controles del navegador.
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        transparentBackground: true,
        supportZoom: false,
      ),
      onReceivedError: (controller, request, error) {
        // El documento en sí es local; lo que puede fallar es el ARCHIVO (el
        // vídeo, el PDF): eso sí se cuenta, porque es la causa de que la
        // pantalla se quede vacía.
        if (request.url.toString() != target.source) return;
        if (!mounted) return;
        setState(() => _playerError = error.description);
      },
    );
  }

  /// HTML del reproductor.
  ///
  /// Los controles, el volumen y la pantalla completa los pone el navegador,
  /// pero el ESTADO (cargando / listo / no se pudo) lo pinta esta capa: antes
  /// la pantalla quedaba negra hasta que el vídeo arrancaba. El póster es la
  /// miniatura que el servidor ya generó, así se ve de qué vídeo se trata
  /// mientras carga.
  static String _playerHtml(
    DriveViewTarget target, {
    bool nativeShell = false,
  }) {
    final src = _htmlEscape(target.source);
    // ¿CALIDAD LIGERA? = el servidor reencoda AL VUELO (`?play=low`) y cada
    // petición es un ffmpeg nuevo: no se puede saltar a un byte como en un
    // archivo. Adelantar se hace pidiendo otra vez el vídeo desde ese segundo
    // (`&t=`) y llevando la cuenta del salto (`baseOff`).
    final lightJs = target.source.contains('play=low') ? 'true' : 'false';
    // La URL como literal de JS: la barra de avance la reusa al adelantar.
    final srcJson = jsonEncode(target.source).replaceAll('</', r'<\/');
    // La URL ORIGINAL (la misma sin `play=low`). Es el plan B si el
    // reencodado no se puede reproducir: sin esto, un vídeo GRANDE que el
    // servidor no alcanzó a reencodar (sin ffmpeg, o con los reencodados
    // ocupados) se quedaba en negro con el aviso de error, aunque el original
    // sí se podía ver.
    final fallbackJson = jsonEncode(_withoutLightPlayback(target.source))
        .replaceAll('</', r'<\/');
    // PDF: el visor del navegador integrado (iframe), no un <video>.
    if (target.kind == DriveItemKind.pdf) {
      return '<!doctype html><html><head><meta charset="utf-8">'
          '<meta name="viewport" content="width=device-width, initial-scale=1">'
          '<meta name="color-scheme" content="dark">'
          '<style>html,body{margin:0;height:100%;background:#0a0a0f}'
          'iframe{width:100%;height:100%;border:0;background:#0a0a0f}'
          '</style></head><body><iframe src="$src"></iframe></body></html>';
    }
    final isAudio = target.kind == DriveItemKind.audio;
    final posterUrl = target.poster.isEmpty ? '' : _htmlEscape(target.poster);
    final posterAttr = posterUrl.isEmpty ? '' : ' poster="$posterUrl"';
    final accent = _hexColor(AppColors.brand);
    // En el navegador la pantalla completa la da la propia API del navegador.
    // Dentro de la app (WebView), sobre todo en Windows, esa API no la atiende
    // el anfitrión: allí se le pide al visor de Flutter que oculte sus barras.
    final nativeFs = nativeShell ? 'true' : 'false';
    if (isAudio) {
      return '<!doctype html><html><head><meta charset="utf-8">'
          '<meta name="viewport" content="width=device-width, initial-scale=1">'
          '<meta name="color-scheme" content="dark">'
          '<style>'
          'html,body{margin:0;height:100%;overflow:hidden;background:#08080d;'
          'font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif}'
          '.stage{position:relative;width:100%;height:100%;display:flex;'
          'align-items:center;justify-content:center;background:radial-gradient('
          '760px 420px at 50% 38%,#191d2b,#08080d 72%)}'
          '.audio-card{display:flex;flex-direction:column;align-items:center;'
          'gap:18px;padding:30px 34px;border-radius:26px;'
          'background:rgba(255,255,255,.055);border:1px solid rgba(255,255,255,.10);'
          'box-shadow:0 24px 70px rgba(0,0,0,.45)}'
          '.disc{width:104px;height:104px;border-radius:50%;display:flex;'
          'align-items:center;justify-content:center;font-size:44px;color:#e8efff;'
          'background:radial-gradient(circle at 34% 28%,#44557a,#121722 70%);'
          'box-shadow:0 14px 36px rgba(0,0,0,.45),'
          'inset 0 0 0 11px rgba(255,255,255,.045)}'
          '.label{font-size:11px;letter-spacing:.18em;text-transform:uppercase;'
          'color:#8f9bb3;font-weight:700}'
          'audio{width:min(540px,82vw);outline:none;accent-color:$accent}'
          '#status{position:absolute;left:50%;bottom:64px;transform:translateX(-50%);'
          'padding:7px 13px;border-radius:999px;background:rgba(8,10,16,.72);'
          'border:1px solid rgba(255,255,255,.12);color:#e8edff;font-size:12.5px;'
          'transition:opacity .2s;pointer-events:none}'
          '#error{display:none;position:absolute;inset:0;align-items:center;'
          'justify-content:center;flex-direction:column;gap:8px;text-align:center;'
          'color:#ffd9a8;background:rgba(6,7,11,.78);padding:24px}'
          '#error b{color:#fff;font-size:15px}'
          '#error span{font-size:12.5px;color:#c9c9d4;max-width:430px}'
          '</style></head><body><div class="stage">'
          '<div class="audio-card"><div class="disc">♪</div>'
          '<div class="label">Audio</div>'
          '<audio id="media" src="$src" controls autoplay preload="metadata">'
          '</audio></div>'
          '<div id="status">Cargando audio…</div>'
          '<div id="error"><b>No se pudo reproducir este archivo</b>'
          '<span>Puede que el formato no sea compatible. Descárgalo o ábrelo con '
          'el programa de tu computadora.</span></div></div><script>'
          'var m=document.getElementById("media"),'
          's=document.getElementById("status"),'
          'e=document.getElementById("error");'
          'function hide(){s.style.opacity="0"}'
          'm.addEventListener("canplay",hide);m.addEventListener("playing",hide);'
          'm.addEventListener("error",function(){hide();e.style.display="flex"});'
          // Un audio en caché puede haber cargado ANTES de estos manejadores.
          'if(m.readyState>=2)hide();'
          'try{var p=m.play();if(p&&p.catch)p.catch(function(){})}catch(_){}'
          '</script></body></html>';
    }
    final posterDiv = posterUrl.isEmpty
        ? '<div class="poster" id="poster"></div>'
        : "<div class=\"poster\" id=\"poster\" style=\"background-image:url('$posterUrl')\"></div>";
    return '<!doctype html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<meta name="color-scheme" content="dark">'
        '<meta name="theme-color" content="#05060a">'
        '<style>'
        ':root{--accent:$accent;--ease:cubic-bezier(.22,.61,.36,1)}'
        '*{box-sizing:border-box}'
        'html,body{margin:0;height:100%;overflow:hidden;background:#05060a;'
        'font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;'
        '-webkit-user-select:none;user-select:none;'
        '-webkit-tap-highlight-color:transparent}'
        '.stage{position:relative;width:100%;height:100%;display:flex;'
        'align-items:center;justify-content:center;overflow:hidden;'
        'touch-action:manipulation;background:radial-gradient('
        '1200px 700px at 50% 30%,#12151f 0%,#05060a 72%)}'
        // PÓSTER con vida propia: se ve mientras el vídeo carga y se desvanece
        // (con un leve zoom) en cuanto hay imagen. Antes el fondo era negro.
        '.poster{position:absolute;inset:0;z-index:0;background-position:center;'
        'background-size:cover;opacity:1;'
        'transition:opacity .55s ease,transform 1.4s var(--ease)}'
        '.poster:after{content:"";position:absolute;inset:0;'
        'background:linear-gradient(to top,rgba(0,0,0,.62),rgba(0,0,0,.10))}'
        '.poster.hide{opacity:0;transform:scale(1.06)}'
        'video{position:relative;z-index:1;width:100%;height:100%;'
        'object-fit:contain;background:#000;display:block;outline:none;'
        'opacity:0;transition:opacity .4s ease}'
        'video.ready{opacity:1}'
        // BOTÓN CENTRAL: cuadrado redondeado con el ACENTO de la app (el mismo
        // color de los botones), plano y legible sobre cualquier vídeo. Se
        // centra con translate: no depende de su tamaño ni deja margen raro.
        '.big-play{position:absolute;z-index:6;left:50%;top:50%;width:84px;'
        'height:84px;padding:0;border:0;border-radius:22px;cursor:pointer;'
        'color:#fff;display:flex;align-items:center;justify-content:center;'
        'background:var(--accent);'
        'box-shadow:0 12px 28px rgba(0,0,0,.38),'
        'inset 0 1px 0 rgba(255,255,255,.26);opacity:0;'
        'pointer-events:none;transform:translate(-50%,-50%) scale(.88);'
        'transition:opacity .24s ease,transform .3s var(--ease),'
        'filter .2s ease,box-shadow .25s ease}'
        '.big-play.show{opacity:1;pointer-events:auto;'
        'transform:translate(-50%,-50%) scale(1)}'
        '.big-play:hover{filter:brightness(1.07);'
        'transform:translate(-50%,-50%) scale(1.04);'
        'box-shadow:0 16px 36px rgba(0,0,0,.45),'
        'inset 0 1px 0 rgba(255,255,255,.3)}'
        '.big-play:active{transform:translate(-50%,-50%) scale(.96)}'
        '.big-play:focus-visible{outline:2px solid #fff;outline-offset:4px}'
        '.big-play svg{width:30px;height:30px;margin-left:3px;fill:#fff}'
        // El aviso de carga va SIEMPRE por encima del vídeo (z-index).
        '.spinner{display:none;position:absolute;z-index:4;left:50%;top:50%;'
        'width:48px;height:48px;margin:-24px 0 0 -24px;border-radius:50%;'
        'border:3px solid rgba(255,255,255,.14);border-top-color:var(--accent);'
        'animation:spin .85s linear infinite;'
        'filter:drop-shadow(0 6px 18px rgba(0,0,0,.6))}'
        '@keyframes spin{to{transform:rotate(360deg)}}'
        '.status{position:absolute;z-index:5;left:50%;bottom:110px;'
        'transform:translateX(-50%);display:flex;align-items:center;gap:9px;'
        'padding:8px 14px;border-radius:999px;background:rgba(8,10,16,.62);'
        'backdrop-filter:blur(14px);-webkit-backdrop-filter:blur(14px);'
        'border:1px solid rgba(255,255,255,.12);color:#eef2ff;font-size:12.5px;'
        'letter-spacing:.2px;opacity:1;transition:opacity .25s ease;'
        'pointer-events:none;white-space:nowrap}'
        '.status .dot{width:7px;height:7px;border-radius:50%;'
        'background:var(--accent);box-shadow:0 0 12px var(--accent);'
        'animation:pulse 1.5s ease-in-out infinite}'
        '@keyframes pulse{0%,100%{opacity:.4;transform:scale(.82)}'
        '50%{opacity:1;transform:scale(1.16)}}'
        // AVISO DE SONIDO: si el navegador bloquea el arranque CON audio, el
        // vídeo igual empieza (mudo, siempre permitido) y este botón lo activa.
        '.sound{position:absolute;z-index:8;left:50%;'
        'bottom:calc(72px + env(safe-area-inset-bottom));'
        'transform:translateX(-50%);display:none;align-items:center;gap:8px;'
        'padding:9px 15px;border:1px solid rgba(255,255,255,.16);'
        'border-radius:999px;background:rgba(8,10,16,.82);color:#eef2ff;'
        'font-family:inherit;font-size:12.5px;font-weight:600;cursor:pointer;'
        'backdrop-filter:blur(14px);-webkit-backdrop-filter:blur(14px);'
        'box-shadow:0 10px 30px rgba(0,0,0,.45);'
        'transition:background .2s ease,transform .2s ease}'
        '.sound.show{display:flex}'
        '.sound:hover{background:rgba(22,26,40,.92);'
        'transform:translateX(-50%) scale(1.03)}'
        // BARRA INFERIOR estilo YouTube: barra de progreso a todo el ancho,
        // que engorda al pasar el mouse, y debajo los controles.
        '.controls{position:absolute;z-index:7;left:0;right:0;bottom:0;'
        'padding:0 clamp(10px,2.4vw,22px) calc(8px + env(safe-area-inset-bottom));'
        'background:linear-gradient(to top,rgba(3,4,8,.94),'
        'rgba(3,4,8,.56) 46%,transparent);opacity:0;'
        'transform:translateY(10px);'
        'transition:opacity .3s ease,transform .34s var(--ease)}'
        '.controls.show{opacity:1;transform:none}'
        '.seekwrap{position:relative;display:flex;align-items:center;'
        'height:20px;margin-bottom:2px}'
        '#seek{flex:1 1 auto;min-width:70px;width:100%;height:4px;margin:0;'
        '--played:0%;--buffered:0%;background:linear-gradient(to right,'
        'var(--accent) 0 var(--played),rgba(255,255,255,.5) var(--played) '
        'var(--buffered),rgba(255,255,255,.2) var(--buffered) 100%);'
        'transition:height .18s ease}'
        '.seekwrap:hover #seek,.seekwrap:focus-within #seek{height:6px}'
        'input[type=range]{-webkit-appearance:none;appearance:none;outline:none;'
        'border-radius:999px;cursor:pointer;padding:0;border:0}'
        '#seek::-webkit-slider-thumb{-webkit-appearance:none;width:13px;'
        'height:13px;border-radius:50%;background:#fff;border:0;'
        'box-shadow:0 0 0 0 rgba(255,255,255,.22);'
        'transition:box-shadow .18s ease,transform .18s ease}'
        '.seekwrap:hover #seek::-webkit-slider-thumb{'
        'box-shadow:0 0 0 7px rgba(255,255,255,.16)}'
        '#seek::-moz-range-thumb{width:13px;height:13px;border-radius:50%;'
        'background:#fff;border:0}'
        '.row{display:flex;align-items:center;gap:5px;padding-top:2px}'
        '.cbtn{width:38px;height:38px;flex:0 0 auto;border:0;border-radius:12px;'
        'background:transparent;color:#f2f5ff;display:flex;align-items:center;'
        'justify-content:center;cursor:pointer;padding:0;font:inherit;'
        'transition:background .18s,transform .18s var(--ease)}'
        '.cbtn:hover{background:rgba(255,255,255,.1)}'
        '.cbtn:active{transform:scale(.9)}'
        '.cbtn svg{width:21px;height:21px;fill:currentColor;'
        'transition:transform .22s var(--ease),opacity .2s}'
        '.cbtn:hover svg{transform:scale(1.06)}'
        '.i-pause,.i-muted,.i-exit{display:none}'
        '#play.playing .i-play{display:none}'
        '#play.playing .i-pause{display:block}'
        '#mute.off .i-vol{display:none}'
        '#mute.off .i-muted{display:block}'
        '#full.on .i-full{display:none}'
        '#full.on .i-exit{display:block}'
        '.time{font-size:12px;color:#e9eefc;font-variant-numeric:tabular-nums;'
        'letter-spacing:.2px;white-space:nowrap;padding:0 4px}'
        '.time .dim{color:rgba(255,255,255,.5)}'
        '.grow{flex:1 1 auto}'
        '.volbox{display:flex;align-items:center;flex:0 0 auto}'
        '#vol{width:0;height:4px;opacity:0;margin:0;'
        '--v:100%;background:linear-gradient(to right,'
        'rgba(255,255,255,.95) var(--v),rgba(255,255,255,.24) var(--v));'
        'transition:width .26s var(--ease),opacity .2s ease}'
        '.volbox:hover #vol,.volbox:focus-within #vol{width:76px;opacity:1}'
        '.volbox:hover #mute,.volbox:focus-within #mute{margin-right:4px}'
        '#speed{width:auto;min-width:46px;padding:0 10px;font-size:12px;'
        'font-weight:600;letter-spacing:.2px}'
        // MENÚ DE VELOCIDAD: cristal, entra con escala desde su botón.
        '.menu{position:absolute;z-index:9;right:clamp(10px,2.4vw,22px);'
        'bottom:calc(58px + env(safe-area-inset-bottom));min-width:134px;'
        'padding:6px;border-radius:16px;background:rgba(14,16,24,.92);'
        'backdrop-filter:blur(20px) saturate(1.3);'
        '-webkit-backdrop-filter:blur(20px) saturate(1.3);'
        'border:1px solid rgba(255,255,255,.12);'
        'box-shadow:0 22px 60px rgba(0,0,0,.6);opacity:0;'
        'transform:translateY(8px) scale(.95);transform-origin:bottom right;'
        'pointer-events:none;'
        'transition:opacity .2s ease,transform .26s var(--ease)}'
        '.menu.open{opacity:1;transform:none;pointer-events:auto}'
        '.menu button{display:flex;width:100%;align-items:center;'
        'justify-content:space-between;gap:14px;padding:9px 11px;border:0;'
        'border-radius:10px;background:transparent;color:#eef2ff;'
        'font-size:12.5px;font-family:inherit;cursor:pointer;'
        'transition:background .15s}'
        '.menu button:hover{background:rgba(255,255,255,.1)}'
        '.menu button.on{color:var(--accent);font-weight:700}'
        '.menu .tick{opacity:0;transition:opacity .2s}'
        '.menu button.on .tick{opacity:1}'
        // DOBLE TOQUE (celular): círculo que aparece desde el lado tocado,
        // como en YouTube, con el salto de 10 s.
        '.tap{position:absolute;top:50%;z-index:6;width:104px;height:104px;'
        'margin-top:-52px;border-radius:50%;background:rgba(255,255,255,.16);'
        'backdrop-filter:blur(8px);-webkit-backdrop-filter:blur(8px);'
        'display:flex;flex-direction:column;align-items:center;'
        'justify-content:center;gap:2px;color:#fff;font-size:11px;'
        'font-weight:700;letter-spacing:.3px;opacity:0;pointer-events:none;'
        'transform:scale(.6);'
        'transition:opacity .3s ease,transform .3s var(--ease)}'
        '.tap.left{left:8%}.tap.right{right:8%}'
        '.tap.show{opacity:1;transform:scale(1)}'
        '.tap svg{width:22px;height:22px;fill:#fff}'
        '#error{display:none;position:absolute;z-index:9;left:50%;top:50%;'
        'transform:translate(-50%,-50%);width:min(420px,86vw);'
        'flex-direction:column;align-items:center;gap:8px;padding:26px 24px;'
        'border-radius:22px;text-align:center;color:#ffd9a8;'
        'background:rgba(12,14,22,.92);backdrop-filter:blur(18px);'
        '-webkit-backdrop-filter:blur(18px);'
        'border:1px solid rgba(255,255,255,.10);'
        'box-shadow:0 24px 70px rgba(0,0,0,.55)}'
        '#error b{color:#fff;font-size:15px}'
        '#error span{font-size:12.5px;color:#c9c9d4;line-height:1.4}'
        '@media (max-width:520px){'
        '.big-play{width:72px;height:72px;border-radius:19px}'
        '.big-play svg{width:26px;height:26px}'
        '.status{bottom:102px;font-size:11.5px}'
        '.time{font-size:11.5px}.cbtn{width:34px;height:34px}'
        '.tap{width:88px;height:88px;margin-top:-44px}}'
        '</style></head><body><div class="stage" id="stage">'
        '$posterDiv'
        '<video id="media" src="$src"$posterAttr playsinline '
        'preload="auto"></video>'
        '<div id="spinner" class="spinner" style="display:block"></div>'
        '<div id="status" class="status"><span class="dot"></span>'
        '<span id="statusText">Cargando vídeo…</span></div>'
        '<button id="sound" class="sound" type="button">'
        'Toca para activar el sonido</button>'
        '<div class="tap left" id="tapL">'
        '<svg viewBox="0 0 24 24"><path d="M12 5l-7 7 7 7z"/>'
        '<path d="M19 5l-7 7 7 7z"/></svg><span>10 s</span></div>'
        '<div class="tap right" id="tapR">'
        '<svg viewBox="0 0 24 24"><path d="M12 5l7 7-7 7z"/>'
        '<path d="M5 5l7 7-7 7z"/></svg><span>10 s</span></div>'
        '<button id="big" class="big-play" type="button" aria-label="Reproducir">'
        '<svg viewBox="0 0 24 24"><path d="M8 5.5v13l11-6.5z"/></svg></button>'
        '<div id="error"><b>No se pudo reproducir este archivo</b>'
        '<span>Puede que el formato no sea compatible. Descárgalo o ábrelo con '
        'el programa de tu computadora.</span></div>'
        '<div id="controls" class="controls show">'
        '<div class="seekwrap"><input id="seek" type="range" min="0" max="1000" '
        'value="0" aria-label="Posición del vídeo"></div>'
        '<div class="row">'
        '<button id="play" class="cbtn" type="button" aria-label="Reproducir">'
        '<svg class="i-play" viewBox="0 0 24 24">'
        '<path d="M8 5.5v13l11-6.5z"/></svg>'
        '<svg class="i-pause" viewBox="0 0 24 24">'
        '<path d="M7 5h3.4v14H7zM13.6 5H17v14h-3.4z"/></svg></button>'
        '<div class="volbox" id="volbox">'
        '<button id="mute" class="cbtn" type="button" aria-label="Silenciar">'
        '<svg class="i-vol" viewBox="0 0 24 24">'
        '<path d="M4 9h3l4.5-4v14L7 15H4z"/></svg>'
        '<svg class="i-muted" viewBox="0 0 24 24">'
        '<path d="M4 9h3l4.5-4v14L7 15H4z"/>'
        '<path d="M15 9.5l5 5m0-5l-5 5" fill="none" stroke="currentColor" '
        'stroke-width="1.8" stroke-linecap="round"/></svg></button>'
        '<input id="vol" type="range" min="0" max="1" step="0.05" value="1" '
        'aria-label="Volumen"></div>'
        '<span class="time"><span id="cur">0:00</span><span class="dim"> / '
        '</span><span id="dur">--:--</span></span>'
        '<div class="grow"></div>'
        '<button id="speed" class="cbtn" type="button" title="Velocidad" '
        'aria-label="Velocidad">1x</button>'
        '<button id="full" class="cbtn" type="button" '
        'aria-label="Pantalla completa" title="Pantalla completa">'
        '<svg class="i-full" viewBox="0 0 24 24">'
        '<path d="M4 9V4h5v2H6v3zM15 4h5v5h-2V6h-3z'
        'M4 15h2v3h3v2H4zm14 0h2v5h-5v-2h3z"/></svg>'
        '<svg class="i-exit" viewBox="0 0 24 24">'
        '<path d="M5 16h3v3h2v-5H5v2zm3-8H5v2h5V5H8v3z'
        'm6 11h2v-3h3v-2h-5v5zm2-11V5h-2v5h5V8h-3z"/></svg></button>'
        '</div></div>'
        '<div id="speedMenu" class="menu" role="menu">'
        '<button type="button" id="sp05">0.5x<span class="tick">&#10003;</span>'
        '</button>'
        '<button type="button" id="sp10">Normal<span class="tick">&#10003;</span>'
        '</button>'
        '<button type="button" id="sp125">1.25x<span class="tick">&#10003;</span>'
        '</button>'
        '<button type="button" id="sp15">1.5x<span class="tick">&#10003;</span>'
        '</button>'
        '<button type="button" id="sp20">2x<span class="tick">&#10003;</span>'
        '</button>'
        '</div></div><script>'
        'var m=document.getElementById("media"),'
        'stage=document.getElementById("stage"),'
        'big=document.getElementById("big"),'
        // OJO: NO llamarla `status`. En el navegador `window.status` es una
        // propiedad especial del window: `var status = elemento` guarda el
        // TEXTO del elemento, no el elemento, y `status.style.opacity`
        // revienta.
        'statusEl=document.getElementById("status"),'
        'statusText=document.getElementById("statusText"),'
        'spinner=document.getElementById("spinner"),'
        'err=document.getElementById("error"),'
        'controls=document.getElementById("controls"),'
        'play=document.getElementById("play"),'
        'seek=document.getElementById("seek"),cur=document.getElementById("cur"),'
        'dur=document.getElementById("dur"),mute=document.getElementById("mute"),'
        'vol=document.getElementById("vol"),full=document.getElementById("full");'
        // Elementos nuevos: si la página es de una versión anterior (o una
        // prueba sin DOM real) devuelve un objeto mudo en vez de reventar.
        'function el(id){var e=document.getElementById(id);'
        'if(e)return e;return{style:{setProperty:function(){}},'
        'classList:{add:function(){},remove:function(){}},'
        'addEventListener:function(){},textContent:"",value:"0",innerHTML:""}}'
        'var poster=el("poster"),tapL=el("tapL"),tapR=el("tapR"),'
        'speedBtn=el("speed"),speedMenu=el("speedMenu"),volbox=el("volbox"),'
        'soundBtn=el("sound"),menuOpen=false;'
        'var nativeShell=$nativeFs;'
        // La calidad ligera NO se puede adelantar por bytes: se pide otra vez
        // el vídeo con `&t=<segundos>` y se lleva la cuenta en `baseOff`.
        'var lightStream=$lightJs,baseSrc=$srcJson,baseOff=0,'
        'fallbackSrc=$fallbackJson,retriedOriginal=false;'
        'var seeking=false,timer=null,bufferingNow=false,errShown=false,'
        'autoMuted=false;'
        // DURACIÓN DE VERDAD (MP4 fragmentado sin cabecera). El visor manda la
        // duración real por [hsSetDuration].
        'var knownDuration=0,lastTime=-1,lastMove=Date.now();'
        'function total(){if(knownDuration>0)return knownDuration;'
        // Sin la duración real (los vídeos que viven en la PC del dueño no la
        // mandan en el HEAD), el fragmento dice solo lo que QUEDA: el total es
        // lo saltado + lo que queda. Antes se tomaba el fragmento como total
        // y, al adelantar, el tiempo y la barra volvían a cero.
        'if(lightStream&&baseOff>0&&isFinite(m.duration)&&m.duration>0)'
        'return baseOff+m.duration;'
        'return isFinite(m.duration)&&m.duration>0?m.duration:0}'
        'window.hsSetDuration=function(v){v=Number(v);if(!(v>0))return;'
        'knownDuration=v;dur.textContent=fmt(v);paintBar()};'
        // ¿El vídeo AVANZA? (sirve para no enseñar el giro de carga encima de
        // un vídeo que se está reproduciendo bien).
        'function moving(){if(m.paused)return false;'
        'if(m.currentTime>lastTime+0.02){'
        'lastTime=m.currentTime;lastMove=Date.now();return true}'
        'return Date.now()-lastMove<1200}'
        'function fmt(n){if(!isFinite(n)||n<0)return "--:--";'
        'var s=Math.floor(n%60),h=Math.floor(n/3600),mm=Math.floor(n/60)%60;'
        'return (h?h+":"+String(mm).padStart(2,"0"):mm)+":"+'
        'String(s).padStart(2,"0")}'
        'function showBig(on){if(on)big.classList.add("show");'
        'else big.classList.remove("show")}'
        'function icon(){if(m.paused)play.classList.remove("playing");'
        'else play.classList.add("playing");'
        'if(m.muted||m.volume===0)mute.classList.add("off");'
        'else mute.classList.remove("off");'
        'showBig(m.paused&&!errShown)}'
        'function show(t){statusText.textContent=t;statusEl.style.opacity="1"}'
        'function hide(){statusEl.style.opacity="0"}'
        // Cuánto del vídeo ya está en el búfer (0..99 %).
        'function bufferedPct(){try{var d=total();if(d>0){var b=m.buffered;'
        'for(var i=0;i<b.length;i++){'
        'if(b.start(i)<=m.currentTime+.5&&b.end(i)>=m.currentTime){'
        'return Math.min(99,Math.round((baseOff+b.end(i))/d*100))}}}}catch(_){}'
        'return 0}'
        'function loadLabel(){var p=bufferedPct();'
        'return "Cargando vídeo…"+(p?" "+p+" %":"")}'
        // Pinta la barra: visto (marca), descargado (claro) y resto (tenue).
        'function paintBar(){'
        'var d=total();'
        'var p=d>0?Math.min(100,(baseOff+m.currentTime)/d*100):0;'
        'var b=Math.max(p,bufferedPct());'
        'seek.style.setProperty("--played",p.toFixed(2)+"%");'
        'seek.style.setProperty("--buffered",b.toFixed(2)+"%")}'
        'function paintVol(){var v=m.muted?0:Math.round(m.volume*100);'
        'vol.style.setProperty("--v",v+"%")}'
        'function buffering(){bufferingNow=true;spinner.style.display="block";'
        'show(loadLabel())}'
        'function ready(){bufferingNow=false;spinner.style.display="none";'
        'hide();m.classList.add("ready");poster.classList.add("hide")}'
        // El estado se deduce del vídeo MISMO: si ya hay imagen (o está en
        // pausa) no hay nada que "cargar", aunque un evento `stalled` tardío
        // hubiera encendido el aviso.
        'function syncStatus(){if(m.error)return;'
        'if(!m.paused&&moving()){bufferingNow=false;'
        'spinner.style.display="none";hide();return}'
        'if(m.seeking||(!m.paused&&(bufferingNow||m.readyState<3))){'
        'bufferingNow=true;spinner.style.display="block";show(loadLabel())}'
        'else if(m.readyState>=2){bufferingNow=false;'
        'spinner.style.display="none";hide()}}'
        // Los controles NO se esconden solos mientras se reproduce: la barra
        // de carga tiene que quedar a la vista.
        'function poke(){controls.classList.add("show");clearTimeout(timer)}'
        'function playNow(){'
        // Si venía MUDO por el arranque automático, este primer toque del
        // usuario es la ocasión de devolverle el sonido.
        'if(autoMuted){autoMuted=false;m.muted=false;'
        'soundBtn.classList.remove("show");icon();paintVol()}'
        'try{var p=m.play();'
        'if(p&&p.catch)p.catch(function(){showBig(true);hide()})}'
        'catch(_){showBig(true);hide()}}'
        'function toggle(){if(m.paused){playNow()}else{m.pause()}}'
        // ARRANQUE AUTOMÁTICO. Los navegadores (y WebView2) bloquean el
        // arranque CON SONIDO si el usuario no tocó nada: antes eso dejaba el
        // póster quieto. Si el primer intento falla se arranca EN MUDO (eso
        // siempre está permitido) y se ofrece activar el sonido con un toque.
        'function mutedStart(){'
        'm.muted=true;autoMuted=true;icon();paintVol();'
        'try{var p=m.play();'
        'if(p&&p.then)p.then(function(){ready();'
        'soundBtn.classList.add("show")}).catch(function(){'
        'showBig(true);hide()});'
        'else{soundBtn.classList.add("show")}'
        '}catch(_){showBig(true);hide()}}'
        'function autoplay(){'
        'try{var p=m.play();'
        'if(p&&p.catch)p.catch(mutedStart);'
        '}catch(_){mutedStart()}}'
        // ADELANTAR: archivo normal = currentTime; calidad ligera = otra
        // petición con `t=`.
        'function applySeek(t){'
        'var d=total();if(!(d>0))return;if(!(t>=0))t=0;'
        'if(d>0&&t>d-0.4)t=Math.max(0,d-0.4);'
        'if(!lightStream){m.currentTime=t;return}'
        'var wasPlaying=!m.paused;'
        'baseOff=t;lastTime=-1;'
        'if(d>0)seek.value=String(t/d*1000);'
        'cur.textContent=fmt(t);'
        'buffering();'
        'm.src=baseSrc+(baseSrc.indexOf("?")>=0?"&":"?")+"t="+t.toFixed(2);'
        'if(wasPlaying){'
        'try{var p=m.play();if(p&&p.catch)p.catch(function(){})}catch(_){}'
        '}else{'
        'm.pause();'
        'm.addEventListener("canplay",function(){m.pause()},{once:true})}}'
        'function jump(delta){var d=total();if(!(d>0))return;'
        'var t=Math.max(0,Math.min(d-0.5,baseOff+m.currentTime+delta));'
        'if(d>0)seek.value=String(t/d*1000);'
        'applySeek(t)}'
        // ---- DOBLE TOQUE = ±10 s (como YouTube en el celular) --------------
        'var touchMode=("ontouchstart" in window),lastTap=0,singleTimer=null;'
        'function ripple(node){node.classList.add("show");'
        'setTimeout(function(){node.classList.remove("show")},520)}'
        'function onSurface(ev){'
        'var now=Date.now();'
        'var rect=stage.getBoundingClientRect?'
        'stage.getBoundingClientRect():{left:0,width:0};'
        'var x=(ev&&typeof ev.clientX==="number"?ev.clientX:0)-(rect.left||0);'
        'if(touchMode&&lastTap>0&&now-lastTap<360){'
        'lastTap=0;if(singleTimer){clearTimeout(singleTimer);singleTimer=null}'
        'var right=x>(rect.width||0)/2;'
        'ripple(right?tapR:tapL);'
        'jump(right?10:-10);return}'
        'lastTap=now;if(singleTimer)clearTimeout(singleTimer);'
        'if(touchMode){singleTimer=setTimeout(function(){'
        'singleTimer=null;toggle()},200)}else{toggle()}}'
        // ---- VELOCIDAD ----------------------------------------------------
        'var rates=[["sp05","0.5x",0.5],["sp10","Normal",1],'
        '["sp125","1.25x",1.25],["sp15","1.5x",1.5],["sp20","2x",2]];'
        'function markRate(){for(var i=0;i<rates.length;i++){'
        'var b=el(rates[i][0]);'
        'if(Math.abs((m.playbackRate||1)-rates[i][2])<0.01)b.classList.add("on");'
        'else b.classList.remove("on")}}'
        'function closeMenu(){menuOpen=false;speedMenu.classList.remove("open")}'
        'for(var i=0;i<rates.length;i++)(function(r){'
        'var b=el(r[0]);b.addEventListener("click",function(){'
        'try{m.playbackRate=r[2]}catch(_){}'
        'speedBtn.textContent=r[1];markRate();closeMenu()})})(rates[i]);'
        'speedBtn.addEventListener("click",function(ev){'
        'if(ev&&ev.stopPropagation)ev.stopPropagation();'
        'menuOpen=!menuOpen;'
        'if(menuOpen)speedMenu.classList.add("open");'
        'else speedMenu.classList.remove("open")});'
        'm.addEventListener("loadedmetadata",function(){'
        'dur.textContent=fmt(total());paintBar();'
        // Medidas reales del archivo: la app las guarda para girar la pantalla
        // en pantalla completa aunque se pida desde la barra del visor.
        'if(window.flutter_inappwebview&&window.flutter_inappwebview.callHandler)'
        'try{window.flutter_inappwebview.callHandler("hsPlayerMeta",'
        'm.videoWidth||0,m.videoHeight||0)}catch(_){}'
        // Si el servidor NO pudo reencodar desde `t` mandó el vídeo desde el
        // principio: se corrige la cuenta para no mentir con la barra. Solo se
        // corrige cuando el fragmento dura TODO el vídeo; si dura lo que queda
        // (o no se conoce el total), el salto se respetó y el tiempo sigue.
        'if(lightStream&&baseOff>0&&knownDuration>0&&'
        'isFinite(m.duration)&&m.duration>0){'
        'var frag=m.duration;'
        'var whole=Math.abs(frag-knownDuration)<=1.5;'
        'var remain=Math.abs(frag-Math.max(0,knownDuration-baseOff));'
        'if(whole&&remain>2){baseOff=0;seek.value="0";'
        'cur.textContent=fmt(0)}}'
        '});'
        'm.addEventListener("loadeddata",ready);'
        'm.addEventListener("canplay",ready);'
        'm.addEventListener("playing",function(){ready();icon();poke()});'
        'm.addEventListener("pause",function(){icon();'
        'controls.classList.add("show");clearTimeout(timer)});'
        'm.addEventListener("waiting",buffering);'
        'm.addEventListener("stalled",buffering);'
        'm.addEventListener("seeking",buffering);'
        'm.addEventListener("seeked",function(){syncStatus();paintBar()});'
        'm.addEventListener("progress",function(){paintBar();'
        'if(bufferingNow)syncStatus()});'
        'm.addEventListener("play",function(){poke();closeMenu()});'
        'm.addEventListener("ended",function(){icon();syncStatus();paintBar()});'
        'm.addEventListener("timeupdate",function(){if(seeking)return;'
        'cur.textContent=fmt(baseOff+m.currentTime);'
        'var d=total();'
        'if(d>0)seek.value=String(Math.min(1000,(baseOff+m.currentTime)/d*1000));'
        'paintBar()});'
        'm.addEventListener("error",function(){'
        // PLAN B: si el reencodado (calidad ligera) no se puede reproducir se
        // pide el ORIGINAL UNA vez.
        'if(lightStream&&!retriedOriginal){'
        'retriedOriginal=true;lightStream=false;baseOff=0;lastTime=-1;'
        'm.src=fallbackSrc;'
        'try{if(m.load)m.load();'
        'var p=m.play();if(p&&p.catch)p.catch(function(){})}catch(_){}'
        'return}'
        'errShown=true;ready();showBig(false);'
        'spinner.style.display="none";err.style.display="flex"});'
        'seek.addEventListener("input",function(){seeking=true;'
        'seek.style.setProperty("--played",Number(seek.value)/10+"%");'
        'var d=total();'
        'if(d>0)cur.textContent=fmt(d*seek.value/1000)});'
        'seek.addEventListener("change",function(){var d=total();'
        'var t=d>0?d*seek.value/1000:0;applySeek(t);seeking=false});'
        'play.addEventListener("click",toggle);'
        'big.addEventListener("click",toggle);'
        'm.addEventListener("click",onSurface);'
        'mute.addEventListener("click",function(){m.muted=!m.muted;'
        'autoMuted=false;icon();paintVol();'
        'if(!m.muted)soundBtn.classList.remove("show")});'
        'soundBtn.addEventListener("click",function(){'
        'm.muted=false;autoMuted=false;if(m.volume===0)m.volume=1;'
        'icon();paintVol();soundBtn.classList.remove("show");'
        'try{var p=m.play();if(p&&p.catch)p.catch(function(){})}catch(_){}});'
        'vol.addEventListener("input",function(){m.volume=Number(vol.value);'
        'm.muted=m.volume===0;icon();paintVol()});'
        // ---- PANTALLA COMPLETA --------------------------------------------
        // En la WEB el reproductor vive en un IFRAME: pedir la pantalla
        // completa desde dentro solo la aplica al recuadro del iframe (el
        // botón "cumplía" pero no se agrandaba nada). Se pide al IFRAME mismo
        // o a la página que lo contiene; el recuadro local es el último
        // recurso.
        'function parentDoc(){try{'
        'if(window.parent&&window.parent!==window&&window.parent.document)'
        'return window.parent.document}catch(_){}return null}'
        'function frameEl(){try{return window.frameElement||null}catch(_){}'
        'return null}'
        // fsOn recuerda que la pedimos nosotros: si el navegador no avisa del
        // cambio (o el documento padre no se puede leer), el botón sigue
        // sirviendo para SALIR en vez de pedirla otra vez.
        'var fsOn=false;'
        'function rawFs(){try{var pd=parentDoc();'
        'if(pd&&(pd.fullscreenElement||pd.webkitFullscreenElement))return true}'
        'catch(_){}'
        'return !!(document.fullscreenElement||document.webkitFullscreenElement)}'
        'function isFs(){return fsOn||rawFs()}'
        'function tryFs(node,next){'
        'if(!node)return next();'
        'var req=node.requestFullscreen||node.webkitRequestFullscreen;'
        'if(!req)return next();'
        'try{var p=req.call(node);'
        'if(p&&p.catch)p.catch(function(){next()});}catch(_){return next()}}'
        'function enterFs(){'
        'fsOn=true;'
        'tryFs(frameEl(),function(){'
        'var pd=parentDoc();'
        'tryFs(pd&&(pd.documentElement||pd.body),function(){'
        'tryFs(stage,function(){'
        'if(m.webkitEnterFullscreen)try{m.webkitEnterFullscreen()}'
        'catch(_){}})})})}'
        'function exitFs(){'
        'fsOn=false;'
        'var pd=parentDoc();'
        'if(pd&&pd.fullscreenElement&&pd.exitFullscreen){'
        'try{pd.exitFullscreen();return}catch(_){}}'
        'if(pd&&pd.webkitFullscreenElement&&pd.webkitExitFullscreen){'
        'try{pd.webkitExitFullscreen();return}catch(_){}}'
        'if(document.fullscreenElement&&document.exitFullscreen){'
        'try{document.exitFullscreen();return}catch(_){}}'
        'if(document.webkitFullscreenElement&&document.webkitExitFullscreen){'
        'try{document.webkitExitFullscreen();return}catch(_){}}'
        'if(m.webkitExitFullscreen)try{m.webkitExitFullscreen()}catch(_){}}'
        'function fullSync(){'
        'fsOn=rawFs();'
        'if(fsOn)full.classList.add("on");else full.classList.remove("on")}'
        'full.addEventListener("click",function(){'
        // App de escritorio/celular: el visor de Flutter oculta sus barras
        // (en Windows la API del navegador integrado no hace nada).
        'if(nativeShell){'
        'if(window.flutter_inappwebview&&window.flutter_inappwebview.callHandler)'
        // Las medidas viajan con el aviso: la app gira el TELÉFONO a apaisado
        // solo si el vídeo es horizontal (uno vertical se queda de pie).
        'window.flutter_inappwebview.callHandler("hsPlayerFullscreen",'
        'm.videoWidth||0,m.videoHeight||0);'
        'return}'
        'if(isFs()){exitFs();return}'
        'enterFs()});'
        'document.addEventListener("fullscreenchange",fullSync);'
        'document.addEventListener("webkitfullscreenchange",fullSync);'
        'try{var pdoc=parentDoc();if(pdoc){'
        'pdoc.addEventListener("fullscreenchange",fullSync);'
        'pdoc.addEventListener("webkitfullscreenchange",fullSync);}}catch(_){}'
        'stage.addEventListener("mousemove",poke);'
        'stage.addEventListener("touchstart",poke);'
        'document.addEventListener("keydown",function(ev){'
        'if(ev.key===" "||ev.key==="k"){ev.preventDefault();toggle()}'
        'else if(ev.key==="ArrowRight"){jump(5)}'
        'else if(ev.key==="ArrowLeft"){jump(-5)}'
        'else if(ev.key==="f"){full.click()}'
        'else if(ev.key==="m"){mute.click()}'
        'else if(ev.key==="Escape"){closeMenu()}});'
        'seek.value="0";vol.value=String(m.volume);icon();paintBar();'
        'paintVol();markRate();poke();'
        'if(m.readyState>=2)ready();'
        // Descarga completa en caché: los eventos pueden haber ocurrido ANTES
        // de estos manejadores. Este sondeo sincroniza el estado real.
        'setInterval(function(){icon();syncStatus()},600);'
        'autoplay();'
        // RED DE SEGURIDAD: si el reencodado no entregó NI UN fotograma en
        // 25 s, se prueba el ORIGINAL igual.
        'setTimeout(function(){'
        'if(!retriedOriginal&&lightStream&&m.readyState<2){'
        'retriedOriginal=true;lightStream=false;baseOff=0;lastTime=-1;'
        'show("Probando el archivo original…");'
        'm.src=fallbackSrc;'
        'try{if(m.load)m.load();'
        'var p=m.play();if(p&&p.catch)p.catch(function(){})}catch(_){}'
        '}},25000);'
        '</script></body></html>';
  }

  /// Color del acento en hexadecimal (#RRGGBB) para el CSS del reproductor.
  static String _hexColor(Color color) {
    final argb = color.toARGB32();
    return '#${argb.toRadixString(16).padLeft(8, '0').substring(2)}';
  }

  /// Quita el `play=low` de una URL: deja la del ARCHIVO ORIGINAL.
  ///
  /// Se usa como plan B del reproductor cuando el reencodado al vuelo falla.
  /// No se toca nada más de la query (el `apikey` de la sesión se conserva).
  static String _withoutLightPlayback(String url) {
    if (!url.contains('play=low')) return url;
    var out = url.replaceAllMapped(
      RegExp(r'([?&])play=low(&|$)'),
      (m) => m[2] == '&' ? m[1]! : '',
    );
    // Si el parámetro iba al final queda un `?` o `&` colgando.
    out = out.replaceAll(RegExp(r'[?&]+$'), '');
    return out;
  }

  static String _htmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  Widget _textView() {
    final scheme = Theme.of(context).colorScheme;
    if (_loadingText) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    final text = _text;
    if (text == null) return _noPreview(_item, message: _textError);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 74, 16, 20),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(14),
        child: Scrollbar(
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.45,
                color: scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Ficha de un archivo que NO se puede ver aquí: qué es y qué se puede hacer
  /// con él (descargarlo o abrirlo con el programa de la computadora).
  Widget _noPreview(DriveItem item, {String? message}) {
    final scheme = Theme.of(context).colorScheme;
    final color = driveKindColor(item.kind, scheme);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(driveKindIcon(item.kind), size: 46, color: color),
              ),
              const SizedBox(height: 16),
              Text(
                driveKindChip(item),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message ??
                    'Este tipo de archivo no tiene vista previa en el panel: '
                        'puedes descargarlo o abrirlo con el programa de tu '
                        'computadora.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  if (widget.onDownload != null)
                    FilledButton.icon(
                      onPressed: () => widget.onDownload!(item),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Descargar'),
                    ),
                  if (hsCanOpenWithSystem)
                    OutlinedButton.icon(
                      onPressed: _opening ? null : () => _openWithSystem(item),
                      icon: _opening
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Abrir con el sistema'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar(DriveItem item) {
    final meta = <String>[
      driveKindChip(item),
      if (item.size != null) _sizeLabel(item.size!),
      if (_canMove) '${_index + 1} de ${widget.items.length}',
    ].join(' · ');
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60, fontSize: 11.5),
              ),
            ],
          ),
        ),
        if (_canPreview)
          _RoundAction(
            icon: Icons.fullscreen_rounded,
            tooltip: 'Pantalla completa',
            onTap: _toggleFullscreen,
          ),
        if (_canPreview && widget.onDownload != null) const SizedBox(width: 6),
        if (widget.onDownload != null)
          _RoundAction(
            icon: Icons.download_rounded,
            tooltip: 'Descargar',
            onTap: () => widget.onDownload!(item),
          ),
        const SizedBox(width: 6),
        _RoundAction(
          icon: Icons.close_rounded,
          tooltip: 'Cerrar',
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }

  /// El archivo no se pudo abrir: se dice por qué y se ofrece la salida.
  Widget _errorBar(DriveItem item) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'No se pudo abrir: ${_playerError ?? ''}',
              maxLines: 2,
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontSize: 11.5,
              ),
            ),
          ),
          if (hsCanOpenWithSystem)
            TextButton.icon(
              onPressed: _opening ? null : () => _openWithSystem(item),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.open_in_new_rounded, size: 17),
              label: const Text('Abrir con el sistema'),
            ),
          if (widget.onDownload != null)
            TextButton.icon(
              onPressed: () => widget.onDownload!(item),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.download_rounded, size: 17),
              label: const Text('Descargar'),
            ),
        ],
      ),
    );
  }
}

/// HTML del reproductor, para poder verificarlo en pruebas sin un WebView.
@visibleForTesting
String debugDrivePlayerHtml(
  DriveViewTarget target, {
  bool nativeShell = false,
}) => _DriveFileViewerState._playerHtml(target, nativeShell: nativeShell);

/// Botón redondo semitransparente del visor (el mismo lenguaje del visor de
/// imágenes).
class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .14),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, size: 20, color: Colors.white),
      ),
    );
  }
}

String _sizeLabel(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

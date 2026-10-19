import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

import '../app_platform.dart';
import '../drive_base.dart';
import '../open_file.dart';
import 'drive_file_visuals.dart';
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
  });

  final DriveItem item;

  /// URL lista para el navegador integrado (`http(s)://…` o `file://…`).
  final String source;

  /// Ruta en el disco (vacía si el archivo se sirve por red).
  final String localPath;

  /// true = se sirve por RED (drive del servidor o carpeta compartida).
  final bool isRemote;

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

  DriveItem get _item => widget.items[_index];

  bool get _canMove => widget.items.length > 1;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  void _prepare() {
    _playerError = null;
    _text = null;
    _textError = null;
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
    final raw = widget.drive.fullSource(item);
    if (widget.drive.isRemote || kWeb) {
      return DriveViewTarget(item: item, source: raw, isRemote: true);
    }
    // Drive del DISCO (una carpeta real del equipo): el navegador necesita un
    // `file://`, no una ruta de Windows.
    return DriveViewTarget(
      item: item,
      source: Uri.file(raw).toString(),
      localPath: raw,
      isRemote: false,
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
    return Dialog.fullscreen(
      backgroundColor: const Color(0xFF101014),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: _body(item)),
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
          if (_playerError != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(top: false, child: _errorBar(item)),
            ),
        ],
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
    return InAppWebView(
      key: ValueKey('drive-file-player-${target.item.name}'),
      initialData: InAppWebViewInitialData(
        data: _playerHtml(target),
        baseUrl: WebUri('about:blank'),
      ),
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

  /// HTML del reproductor: los controles, el volumen y la pantalla completa
  /// los pone el navegador (y él mismo sigue cargando el archivo por partes).
  static String _playerHtml(DriveViewTarget target) {
    final src = _htmlEscape(target.source);
    final media = target.kind == DriveItemKind.audio
        ? '<audio src="$src" controls autoplay></audio>'
        : '<video src="$src" controls autoplay playsinline></video>';
    return '<!doctype html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<style>html,body{margin:0;height:100%;background:#101014;'
        'display:flex;align-items:center;justify-content:center}'
        'video{width:100%;height:100%;object-fit:contain;background:#000}'
        'audio{width:min(520px,92%)}</style></head><body>$media</body></html>';
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
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 11.5),
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

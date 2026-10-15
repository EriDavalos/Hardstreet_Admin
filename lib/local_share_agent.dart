import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_constants.dart';
import 'app_platform.dart';
import 'app_settings.dart';
import 'hs_api.dart';

// ==================================================================
// HARD STREET ADMIN - Agente de carpetas compartidas
// ==================================================================
// Compartir una carpeta DE ESTA COMPUTADORA (p. ej. C:\Fotos) no puede hacerlo
// el servidor: esa carpeta no está en el servidor. Lo hace la APP, que sí la
// ve, y lo hace SIN abrir ningún puerto: el agente se conecta HACIA AFUERA al
// servidor del drive y espera ahí sus peticiones (long polling). El servidor
// reenvía lo que piden los demás usuarios y este agente lo contesta leyendo el
// disco. Para el usuario final es como una carpeta compartida de red, pero sin
// configurar el router ni la IP.
//
// Reglas:
//   * SOLO LECTURA: listar y leer archivos. Nunca se escribe ni se borra nada.
//   * SOLO se sirven rutas DENTRO de la carpeta compartida que el servidor
//     pide (se revalida aquí, aunque el servidor ya lo valida).
//   * Si la sesión no sirve (401/403) o el usuario cierra sesión, se detiene.
// ==================================================================

/// Respuesta que el agente manda al servidor: bytes crudos + cómo interpretarlos.
@immutable
class AgentReply {
  const AgentReply({
    this.bytes = const [],
    this.mime = 'application/octet-stream',
    this.name = '',
    this.status = 200,
    this.error = '',
  });

  final List<int> bytes;
  final String mime;
  final String name;
  final int status;
  final String error;
}

class LocalShareAgent {
  LocalShareAgent._();
  static final LocalShareAgent instance = LocalShareAgent._();

  /// Cliente HTTP (inyectable en pruebas).
  @visibleForTesting
  http.Client client = http.Client();

  /// Cuánto se espera entre reintentos cuando el servidor no contesta.
  @visibleForTesting
  Duration retryDelay = const Duration(seconds: 4);

  /// Tope de un archivo servido (una foto enorme no se manda entera).
  static const int maxFileBytes = 64 * 1024 * 1024;

  bool _running = false;
  bool get running => _running;

  /// ¿Está el servicio sirviendo AHORA MISMO? (lo pinta el switch del módulo)
  ///
  /// Es un `ValueNotifier` porque el servicio también se enciende y se apaga
  /// solo (al quedarse sin la sesión, por ejemplo): la pantalla que lo muestra
  /// tiene que enterarse sin que nadie toque el switch.
  final ValueNotifier<bool> serving = ValueNotifier<bool>(false);

  /// ¿Lo encendió el usuario a mano? (switch del módulo "Archivos
  /// compartidos") Encendido a mano NO se apaga al quedarse sin carpetas
  /// compartidas: sigue esperando peticiones mientras la app esté abierta.
  bool _manual = false;
  bool get manualOn => _manual;

  /// Temporizador de la espera entre reintentos (para poder cancelarla).
  Timer? _retry;
  Completer<void>? _sleeping;

  /// Cuántas peticiones se contestaron (para pruebas y para no quedar mudos).
  int _served = 0;
  int get served => _served;

  /// El agente solo tiene sentido en una COMPUTADORA: es la que tiene las
  /// carpetas. En el celular/web no hay nada que compartir (además el módulo
  /// allí es de solo lectura).
  bool get supported => !kIsWeb && !isAndroidPlatform;

  /// Arranca el agente (idempotente). No lanza: si falla, reintenta.
  void start() {
    if (_running || !supported) return;
    _running = true;
    serving.value = true;
    unawaited(_loop());
  }

  /// Lo detiene (al cerrar sesión o al apagar el switch). La espera en curso se
  /// queda colgada hasta que el servidor la cierra sola; no se vuelve a pedir
  /// trabajo.
  void stop() {
    // La espera entre reintentos se CANCELA: si no, al apagarlo quedaba un
    // temporizador colgado esperando para volver a preguntar.
    _cancelSleep();
    if (!_running) return;
    _running = false;
    serving.value = false;
  }

  /// Espera entre reintentos, CANCELABLE (la cancela [stop]).
  Future<void> _sleep(Duration d) {
    final done = Completer<void>();
    _sleeping = done;
    _retry = Timer(d, () {
      _retry = null;
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }

  void _cancelSleep() {
    _retry?.cancel();
    _retry = null;
    final waiting = _sleeping;
    _sleeping = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
  }

  /// Enciende o apaga el servicio A MANO (el switch del módulo) y lo recuerda.
  ///
  /// Es distinto que compartir una carpeta: encendido aquí, el servicio sigue
  /// esperando peticiones mientras la app esté abierta —aunque ahora mismo no
  /// haya ninguna carpeta compartida— y se vuelve a encender al abrir la app.
  Future<void> setManual(bool on) async {
    if (!supported) return;
    _manual = on;
    if (on) {
      start();
    } else {
      stop();
    }
    await AppSettings.instance.setShareServing(on);
  }

  /// Lee la preferencia del switch (al entrar al panel) y, si estaba
  /// encendido, arranca el servicio sin esperar a nada más.
  bool loadManualPreference() {
    if (!supported) return false;
    _manual = AppSettings.instance.shareServing;
    if (_manual) start();
    return _manual;
  }

  /// Al arrancar la app con sesión restaurada o al volver a entrar.
  void restart() {
    stop();
    start();
  }

  /// Arranca o detiene el agente según si ESTE usuario comparte carpetas de su
  /// computadora. Lo llama la app al entrar al panel y después de compartir o
  /// de dejar de compartir, así el agente está encendido justo cuando hace
  /// falta (y no antes).
  Future<void> syncWithShares() async {
    if (!supported) return;
    // El switch manda: si el usuario lo dejó encendido, el servicio se enciende
    // aunque no haya carpetas compartidas a la vista.
    if (loadManualPreference()) return;
    try {
      final data = await HsApi.sharedFiles();
      final hasLocal = data.shared.any((s) => s['local'] == true);
      if (hasLocal) {
        start();
      } else {
        stop();
      }
    } catch (_) {
      // Sin datos (red, permisos): se deja como está.
    }
  }

  Uri _u(String path, [Map<String, String>? query]) =>
      Uri.parse('${AppConstants.apiBase}$path')
          .replace(queryParameters: query);

  Map<String, String> get _headers => {
        if ((HsSession.token ?? '').isNotEmpty) 'Apikey': HsSession.token!,
      };

  /// Bucle del agente: pregunta por trabajo, contesta y vuelve a preguntar.
  Future<void> _loop() async {
    while (_running) {
      try {
        final r = await client
            .post(_u('/api/local/agent/wait'), headers: _headers)
            .timeout(const Duration(seconds: 40));
        if (!_running) return;
        if (r.statusCode == 200) {
          await _serve(r.body);
          continue;
        }
        if (r.statusCode == 401 || r.statusCode == 403) {
          // La sesión ya no sirve: se detiene hasta el próximo login (y el
          // switch lo refleja: el servicio ya no está sirviendo).
          _running = false;
          serving.value = false;
          return;
        }
        // 204 (nada pendiente) u otro: se vuelve a preguntar enseguida.
      } catch (_) {
        // Sin red o servidor caído: se espera y se reintenta.
        await _sleep(retryDelay);
      }
    }
  }

  /// Contesta UNA petición del servidor (listar o leer un archivo).
  Future<void> _serve(String body) async {
    Map<String, dynamic>? request;
    try {
      final data = jsonDecode(body);
      if (data is Map) {
        final raw = data['request'];
        if (raw is Map) request = raw.cast<String, dynamic>();
      }
    } catch (_) {
      return; // respuesta ilegible: se ignora y se sigue
    }
    if (request == null) return;
    final id = '${request['id'] ?? ''}';
    if (id.isEmpty) return;

    final reply = await describeRequest(
      op: '${request['op'] ?? ''}',
      root: '${request['root'] ?? ''}',
      path: '${request['path'] ?? ''}',
    );
    await _reply(id, reply);
  }

  /// Arma la respuesta de una petición. Público y puro (salvo la lectura del
  /// disco) para poder verificarlo en pruebas sin red.
  @visibleForTesting
  Future<AgentReply> describeRequest({
    required String op,
    required String root,
    required String path,
  }) async {
    try {
      final target = resolveInside(root, path);
      if (op == 'list') {
        final dir = Directory(target);
        if (!await dir.exists()) {
          return const AgentReply(
            status: 404,
            error: 'La carpeta ya no existe en esta computadora',
          );
        }
        final folders = <Map<String, dynamic>>[];
        await for (final e in dir.list(followLinks: false)) {
          final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
          if (name.startsWith('.')) continue;
          if (e is Directory) {
            folders.add({
              'name': name,
              'isFolder': true,
              'modified': await _modifiedMs(e),
              'childCount': await _childCount(e),
            });
          } else if (e is File && _isImage(name)) {
            final st = await e.stat();
            folders.add({
              'name': name,
              'isFolder': false,
              'modified': st.modified.millisecondsSinceEpoch,
              'size': st.size,
            });
          }
        }
        folders.sort((a, b) => '${a['name']}'
            .toLowerCase()
            .compareTo('${b['name']}'.toLowerCase()));
        return AgentReply(
          bytes: utf8.encode(jsonEncode({'folders': folders})),
          mime: 'application/json',
        );
      }
      if (op == 'file') {
        final file = File(target);
        if (!await file.exists()) {
          return const AgentReply(
            status: 404,
            error: 'El archivo ya no existe en esta computadora',
          );
        }
        final st = await file.stat();
        if (st.size > maxFileBytes) {
          return const AgentReply(
            status: 413,
            error: 'El archivo es demasiado grande para compartirlo',
          );
        }
        final name = target.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).last;
        return AgentReply(
          bytes: await file.readAsBytes(),
          mime: _mimeOf(name),
          name: name,
        );
      }
      return const AgentReply(status: 400, error: 'Petición no soportada');
    } catch (e) {
      return AgentReply(status: 500, error: 'No se pudo leer: $e');
    }
  }

  /// Resuelve [path] RELATIVO dentro de [root], sin escapes: ni `..`, ni otra
  /// unidad, ni rutas absolutas. Revienta si la ruta se sale.
  @visibleForTesting
  String resolveInside(String root, String path) {
    final base = _normalize(root);
    if (base.isEmpty) throw StateError('Sin carpeta compartida');
    final raw = path.replaceAll('\\', '/').trim();
    // Lo que pide el servidor es SIEMPRE una ruta RELATIVA dentro del
    // compartido: una absoluta ("C:/...", "/etc") sería un error y se rechaza
    // en vez de reinterpretarla.
    if (raw.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(raw)) {
      throw StateError('Ruta inválida');
    }
    final segments = raw
        .split('/')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s != '.')
        .toList();
    for (final s in segments) {
      if (s == '..' || s.contains(':')) {
        throw StateError('Ruta inválida');
      }
    }
    final target = segments.isEmpty ? base : '$base/${segments.join('/')}';
    final norm = _normalize(target);
    if (norm != base && !norm.startsWith('$base/')) {
      throw StateError('Ruta fuera de la carpeta compartida');
    }
    return norm;
  }

  /// Ruta absoluta normalizada con '/' (para comparar prefijos sin sorpresas).
  static String _normalize(String raw) {
    var s = raw.replaceAll('\\', '/').trim();
    while (s.length > 3 && s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (RegExp(r'^[A-Za-z]:$').hasMatch(s)) s = '$s/';
    return s;
  }

  static bool _isImage(String name) =>
      RegExp(r'\.(jpe?g|png|gif|webp|bmp)$', caseSensitive: false).hasMatch(name);

  static String _mimeOf(String name) {
    final ext = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      default:
        return 'application/octet-stream';
    }
  }

  static Future<int> _modifiedMs(FileSystemEntity e) async {
    try {
      return (await e.stat()).modified.millisecondsSinceEpoch;
    } catch (_) {
      return 0;
    }
  }

  /// ¿Cuántos hijos "válidos" tiene la carpeta? (los mismos que se listarían).
  static Future<int> _childCount(Directory dir) async {
    try {
      var n = 0;
      await for (final e in dir.list(followLinks: false)) {
        final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (name.startsWith('.')) continue;
        if (e is Directory || (e is File && _isImage(name))) n++;
      }
      return n;
    } catch (_) {
      return 0;
    }
  }

  /// Manda la respuesta al servidor (bytes crudos; la URL lleva el cómo).
  Future<void> _reply(String id, AgentReply reply) async {
    final uri = _u('/api/local/agent/reply', {
      'id': id,
      'status': '${reply.status}',
      if (reply.mime.isNotEmpty) 'mime': reply.mime,
      if (reply.name.isNotEmpty) 'name': reply.name,
      if (reply.error.isNotEmpty) 'error': reply.error,
    });
    try {
      await client
          .post(
            uri,
            headers: {
              ..._headers,
              'Content-Type': 'application/octet-stream',
            },
            body: Uint8List.fromList(reply.bytes),
          )
          .timeout(const Duration(seconds: 120));
      _served++;
    } catch (_) {
      // Si el servidor ya no espera, no hay nada que hacer: se sigue.
    }
  }
}

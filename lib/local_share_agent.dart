import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

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
//   * LEE (listar, miniaturas, archivos) y, si quien comparte dio permiso,
//     ESCRIBE: crear carpeta, subir, renombrar, mover, copiar y eliminar.
//     El servidor decide con los permisos del COMPARTIDO; aquí se revalida
//     que toda ruta quede DENTRO de la carpeta compartida.
//   * Las subidas de otros usuarios llegan como una URL temporal del
//     servidor: este equipo baja el archivo y lo escribe en el disco.
//   * Si la sesión no sirve (401/403) o el usuario cierra sesión, se detiene.
// ==================================================================

/// Motivos por los que el servicio de compartir NO está sirviendo.
///
/// Existe porque "no me deja prender el switch" casi SIEMPRE tiene un motivo
/// concreto, y antes se veía como si el switch no obedeciera: la app en el
/// navegador (no puede leer el disco), el servidor del drive que no reconoce
/// la sesión, o un servidor viejo sin los endpoints del agente. El módulo
/// muestra el motivo en la propia tarjeta del switch.
enum ShareProblem {
  /// Esta plataforma (navegador, celular) no puede servir carpetas del equipo.
  unsupported,

  /// El servidor del drive no reconoce la sesión (contesta 401/403).
  session,

  /// El servidor del drive no tiene los endpoints del agente (404/405/501):
  /// es una versión vieja y hay que actualizarlo.
  oldServer,

  /// El servidor del drive contestó con un error suyo (5xx).
  server,
}

/// Respuesta que el agente manda al servidor: bytes crudos + cómo interpretarlos.
@immutable
class AgentReply {
  const AgentReply({
    this.bytes = const [],
    this.mime = 'application/octet-stream',
    this.name = '',
    this.status = 200,
    this.error = '',
    this.rawWidth = 0,
    this.rawHeight = 0,
  });

  final List<int> bytes;
  final String mime;
  final String name;
  final int status;
  final String error;

  /// Si [bytes] son PÍXELES CRUDOS (RGBA) ya reducidos, sus medidas. El servidor
  /// los convierte a JPEG (`sharp`): así una miniatura no obliga a subir el
  /// original de varios MB por la conexión de quien comparte.
  final int rawWidth;
  final int rawHeight;

  /// ¿La respuesta son píxeles crudos? (ver [rawWidth]).
  bool get isRawRgba => rawWidth > 0 && rawHeight > 0;

  /// MIME con el que viajan los píxeles crudos.
  static const String rawMime = 'application/x-raw-rgba';
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

  /// Tope de UNA respuesta del agente (lo que el proxy deja pasar sin cortarla).
  /// Una miniatura reducida nunca se acerca: 320 px son ~0,5 MB.
  static const int maxReplyBytes = 8 * 1024 * 1024;

  /// Tamaño de CADA trozo de la respuesta ([_reply] parte lo que pese más).
  ///
  /// 512 KB deja aire debajo del límite de 1 MB que traen los proxies de
  /// fábrica (`client_max_body_size 1m`). Se partía el cuerpo por esa razón:
  /// las fotos grandes se cortaban al subir la respuesta, la app se tragaba el
  /// error y el usuario veía miniaturas que no cargan, una vista previa en
  /// blanco y descargas que fallaban justo por encima de 1 MB.
  static const int replyChunkBytes = 512 * 1024;

  /// Cuánto se espera la respuesta de UN trozo (512 KB dan de sobra; si un
  /// trozo se atasca, se reintenta o se abandona en vez de colgar 5 minutos).
  static const Duration replyChunkTimeout = Duration(seconds: 60);

  /// Trozo mínimo al partir de nuevo una respuesta rechazada (413): por debajo
  /// de esto, partir no arregla nada (el problema no es el tamaño).
  static const int minReplyChunkBytes = 2 * 1024;


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

  /// Solo PRUEBAS: fuerza si esta plataforma puede servir carpetas.
  @visibleForTesting
  bool? debugSupported;

  /// El agente solo tiene sentido en una COMPUTADORA: es la que tiene las
  /// carpetas. En el celular/web no hay nada que compartir (además el módulo
  /// allí es de solo lectura).
  bool get supported => debugSupported ?? (!kIsWeb && !isAndroidPlatform);

  /// POR QUÉ el servicio no está sirviendo ahora mismo (null = sin problema).
  ///
  /// Lo pinta la tarjeta del switch: encender y que no pase nada visible era
  /// justo lo que hacía pensar que el switch estaba roto.
  final ValueNotifier<ShareProblem?> problem =
      ValueNotifier<ShareProblem?>(null);

  /// Arranca el agente (idempotente). No lanza: si falla, reintenta.
  void start() {
    if (!supported) {
      problem.value = ShareProblem.unsupported;
      return;
    }
    if (_running) return;
    problem.value = null;
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
    // Apagado a propósito: los motivos pasajeros (sesión, servidor) dejan de
    // mostrarse. El de "esta plataforma no puede servir carpetas" NO depende
    // del switch: apagarlo no cambia que el navegador no vea el disco.
    if (problem.value != ShareProblem.unsupported) problem.value = null;
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
  /// Devuelve `false` si esta plataforma no puede servir carpetas (navegador,
  /// celular): en ese caso deja el motivo en [problem] para poder explicarlo.
  Future<bool> setManual(bool on) async {
    if (!supported) {
      problem.value = ShareProblem.unsupported;
      return false;
    }
    _manual = on;
    if (on) {
      problem.value = null;
      start();
    } else {
      stop();
    }
    await AppSettings.instance.setShareServing(on);
    return true;
  }

  /// Lee la preferencia del switch (al entrar al panel) y, si estaba
  /// encendido, arranca el servicio sin esperar a nada más.
  bool loadManualPreference() {
    if (!supported) {
      problem.value = ShareProblem.unsupported;
      return false;
    }
    _manual = AppSettings.instance.shareServing;
    if (_manual) start();
    return _manual;
  }

  /// ¿El usuario ya eligió el switch (aunque lo haya dejado apagado)?
  ///
  /// Cuando la preferencia es explícita, el agente NO se enciende solo por
  /// tener carpetas locales: si lo apagó, sigue apagado al entrar y salir del
  /// módulo y al reabrir la app.
  bool get manualPreferenceKnown => AppSettings.instance.shareServingSet;

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
    // El switch manda en los DOS sentidos: encendido sirve aunque no haya
    // carpetas a la vista; apagado NO se vuelve a encender solo porque exista
    // una carpeta local compartida.
    loadManualPreference();
    if (manualPreferenceKnown) {
      if (_manual) { start(); }
      else { stop(); }
      return;
    }
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
  ///
  /// Reglas del bucle (todas nacieron de fallas reales):
  ///   * el switch manda: una sesión rechazada o un servidor viejo NO apagan
  ///     el servicio —antes un 401 lo apagaba de golpe y el switch se caía
  ///     solo, justo cuando el usuario acababa de encenderlo—; se explica el
  ///     motivo y se SIGUE intentando;
  ///   * nunca se pregunta en bucle apretado: cualquier respuesta que no sea
  ///     trabajo contesta con una espera ([retryDelay]);
  ///   * un 5xx o una red caída son pasajeros: se reintenta sin gritar.
  Future<void> _loop() async {
    while (_running) {
      final watch = Stopwatch()..start();
      try {
        final r = await client
            .post(_u('/api/local/agent/wait'), headers: _headers)
            .timeout(const Duration(seconds: 40));
        if (!_running) return;
        watch.stop();
        final code = r.statusCode;
        if (code == 200) {
          problem.value = null;
          await _serve(r.body);
          continue;
        }
        if (code == 204) {
          // Nada pendiente. Si el servidor contestó AL INSTANTE (no esperó),
          // eso no es una espera: se deja respirar antes de volver a preguntar
          // para no golpearlo en bucle apretado. Tras una espera de verdad, se
          // vuelve a preguntar enseguida.
          problem.value = null;
          if (watch.elapsedMilliseconds < 1000) {
            await _sleep(const Duration(seconds: 1));
          }
          continue;
        }
        if (code == 401 || code == 403) {
          problem.value = ShareProblem.session;
        } else if (code == 404 || code == 405 || code == 501) {
          problem.value = ShareProblem.oldServer;
        } else if (code >= 500) {
          problem.value = ShareProblem.server;
        } else {
          problem.value = null;
        }
      } catch (_) {
        // Sin red o servidor caído: se espera y se reintenta (es pasajero, no
        // se deja un motivo en pantalla por eso).
        await _sleep(retryDelay);
        continue;
      }
      await _sleep(retryDelay);
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

    // La app SIEMPRE contesta, aunque la lectura se atasque: si se queda
    // callada, el servidor espera minutos y el usuario ve "tardó demasiado"
    // sin saber por qué. Con este tope, la respuesta (con su motivo) llega a
    // tiempo.
    AgentReply reply;
    try {
      reply = await describeRequest(
        op: '${request['op'] ?? ''}',
        root: '${request['root'] ?? ''}',
        path: '${request['path'] ?? ''}',
        width: int.tryParse('${request['w'] ?? ''}') ?? 0,
        // Escritura: nombre nuevo, destino, lista y archivo temporal.
        name: '${request['name'] ?? ''}',
        to: '${request['to'] ?? ''}',
        names: [
          for (final n in ((request['names'] as List?) ?? const [])) '$n',
        ],
        overwrite: '${request['overwrite'] ?? ''}' == '1',
        url: '${request['url'] ?? ''}',
      ).timeout(_readTimeout('${request['op'] ?? ''}'));
    } on TimeoutException {
      reply = const AgentReply(
        status: 504,
        error:
            'La lectura tardó demasiado en esta computadora (¿la carpeta está '
            'en la nube, en un disco desconectado o la foto es enorme?)',
      );
    } catch (e) {
      // Un error inesperado tampoco puede dejar al servidor esperando.
      reply = AgentReply(status: 500, error: 'No se pudo leer: $e');
    }
    await _reply(id, reply);
  }

  /// Tope de una lectura: un listado es rápido; una foto grande por un disco
  /// lento necesita más, pero nunca minutos.
  static Duration _readTimeout(String op) => switch (op) {
    'list' => const Duration(seconds: 20),
    'thumb' => const Duration(seconds: 45),
    // Escribir (sobre todo una subida, que baja el archivo del servidor)
    // puede tardar más que leer: una foto grande por un disco/enlace lento.
    'put' || 'copy' => const Duration(seconds: 240),
    _ => const Duration(seconds: 120),
  };

  /// Arma la respuesta de una petición. Público y puro (salvo la lectura del
  /// disco) para poder verificarlo en pruebas sin red.
  @visibleForTesting
  Future<AgentReply> describeRequest({
    required String op,
    required String root,
    required String path,
    int width = 0,
    String name = '',
    String to = '',
    List<String> names = const [],
    bool overwrite = false,
    String url = '',
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
          } else if (e is File) {
            // TODO lo que hay en la carpeta, no solo fotos: antes un vídeo o
            // un PDF que estuviera ahí no aparecía en el panel (y por tanto
            // era imposible verlo). `kind` es el mismo valor que usa el
            // servidor del drive y que `DriveItemKind` en la app.
            final st = await e.stat();
            folders.add({
              'name': name,
              'isFolder': false,
              'modified': st.modified.millisecondsSinceEpoch,
              'size': st.size,
              'kind': _kindOf(name),
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
      if (op == 'file' || op == 'thumb') {
        final file = File(target);
        if (!await file.exists()) {
          return const AgentReply(
            status: 404,
            error: 'El archivo ya no existe en esta computadora',
          );
        }
        final st = await file.stat();
        if (st.size > maxFileBytes) {
          return AgentReply(
            status: 413,
            error:
                'El archivo pesa ${(st.size / (1024 * 1024)).round()} MB y el '
                'compartido entrega hasta '
                '${maxFileBytes ~/ (1024 * 1024)} MB. Cópialo al Drive para '
                'poder verlo desde cualquier parte',
          );
        }
        final name = target.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).last;
        // MINIATURA: la foto se reduce AQUÍ, antes de mandarla. Subir el
        // original de varios MB solo para pintar 480 px es lo que hacía que
        // las fotos "tardaran demasiado" en las carpetas compartidas.
        if (op == 'thumb' && width > 0) {
          final original = await file.readAsBytes();
          // El cuerpo de la respuesta NO puede pasarse del límite del proxy: si
          // al reducir todavía sale enorme (una vista previa de 1600 px son
          // varios MB de píxeles), se reduce a la mitad y se vuelve a probar.
          // Antes, cuando no cabía, el proxy cortaba la respuesta y el servidor
          // se quedaba esperando minutos: el usuario veía "tardó demasiado".
          var w = width;
          while (true) {
            final small = await shrinkToRgba(original, w);
            if (small == null) break;
            if (small.bytes.length <= maxReplyBytes) {
              return AgentReply(
                bytes: small.bytes,
                mime: AgentReply.rawMime,
                name: name,
                rawWidth: small.width,
                rawHeight: small.height,
              );
            }
            // Todavía no cabe: la mitad de ancho (hasta un mínimo legible).
            if (w <= 32) break;
            w = (w / 2).round();
          }
          // No se pudo reducir y el original tampoco cabe: se explica en vez de
          // mandar un cuerpo que el proxy va a cortar en silencio.
          if (st.size > maxReplyBytes) {
            return const AgentReply(
              status: 413,
              error: 'La foto es demasiado grande para hacer la miniatura',
            );
          }
        }
        return AgentReply(
          bytes: await file.readAsBytes(),
          mime: _mimeOf(name),
          name: name,
        );
      }
      // ==================== ESCRITURA ====================
      if (op == 'mkdir') {
        final dir = Directory(_inside(root, path, _safeName(name)));
        if (await dir.exists()) {
          return const AgentReply(
            status: 409,
            error: 'Ya existe una carpeta con ese nombre',
          );
        }
        await dir.create();
        return _jsonReply({'ok': true, 'name': _safeName(name)});
      }
      if (op == 'put') {
        if (url.isEmpty) {
          return const AgentReply(status: 400, error: 'Falta el archivo');
        }
        final clean = _safeName(name);
        // El archivo que otro usuario subió está en el servidor: se baja y se
        // escribe AQUÍ, en la computadora del dueño.
        final r = await client
            .get(
              Uri.parse('${AppConstants.apiBase}$url'),
              headers: _headers,
            )
            .timeout(const Duration(minutes: 4));
        if (r.statusCode != 200) {
          return AgentReply(
            status: r.statusCode == 404 ? 410 : 502,
            error: 'No se pudo bajar el archivo para guardarlo (HTTP ${r.statusCode})',
          );
        }
        final dir = Directory(target);
        if (!await dir.exists()) {
          return const AgentReply(
            status: 404,
            error: 'La carpeta ya no existe en esta computadora',
          );
        }
        final saved = await _uniqueIn(dir, clean, false, overwrite: overwrite);
        await File('${dir.path}/$saved').writeAsBytes(r.bodyBytes, flush: true);
        return _jsonReply({'ok': true, 'name': saved});
      }
      if (op == 'rename') {
        final clean = _safeName(name);
        final from = FileSystemEntity.typeSync(target) ==
                FileSystemEntityType.directory
            ? Directory(target) as FileSystemEntity
            : File(target) as FileSystemEntity;
        if (!await from.exists()) {
          return const AgentReply(
            status: 404,
            error: 'El elemento ya no existe en esta computadora',
          );
        }
        final parent = target.substring(0, target.lastIndexOf('/'));
        final dest = '$parent/$clean';
        if (FileSystemEntity.typeSync(dest) != FileSystemEntityType.notFound) {
          return const AgentReply(
            status: 409,
            error: 'Ya existe un elemento con ese nombre',
          );
        }
        await from.rename(dest);
        return _jsonReply({'ok': true, 'name': clean});
      }
      if (op == 'delete') {
        var deleted = 0;
        final errors = <String>[];
        for (final raw in names) {
          final clean = _safeName(raw);
          final dest = _inside(root, path, clean);
          try {
            final type = FileSystemEntity.typeSync(dest);
            if (type == FileSystemEntityType.notFound) continue;
            if (type == FileSystemEntityType.directory) {
              await Directory(dest).delete(recursive: true);
            } else {
              await File(dest).delete();
            }
            deleted++;
          } catch (_) {
            errors.add('No se pudo eliminar "$clean"');
          }
        }
        return _jsonReply({'ok': true, 'deleted': deleted, 'errors': errors});
      }
      if (op == 'move' || op == 'copy') {
        final destDir = Directory(resolveInside(root, to));
        if (!await destDir.exists()) {
          return const AgentReply(
            status: 404,
            error: 'La carpeta de destino ya no existe en esta computadora',
          );
        }
        var done = 0;
        final errors = <String>[];
        for (final raw in names) {
          final clean = _safeName(raw);
          final src = _inside(root, path, clean);
          final type = FileSystemEntity.typeSync(src);
          if (type == FileSystemEntityType.notFound) continue;
          final isDir = type == FileSystemEntityType.directory;
          // Una carpeta no puede meterse dentro de sí misma.
          if (isDir && _normalize(destDir.path).startsWith('${_normalize(src)}/')) {
            errors.add('No puedes mover "$clean" dentro de sí misma');
            continue;
          }
          try {
            final saved = await _uniqueIn(
              destDir,
              clean,
              isDir,
              overwrite: overwrite && op == 'move',
            );
            final dest = '${destDir.path}/$saved';
            if (op == 'move') {
              await (isDir ? Directory(src) : File(src)).rename(dest);
            } else if (isDir) {
              await _copyDir(Directory(src), Directory(dest));
            } else {
              await File(src).copy(dest);
            }
            done++;
          } catch (e) {
            errors.add(
              'No se pudo ${op == 'move' ? 'mover' : 'copiar'} "$clean"',
            );
          }
        }
        return _jsonReply({
          'ok': true,
          (op == 'move' ? 'moved' : 'copied'): done,
          'errors': errors,
        });
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

  /// Une [path] + [name] DENTRO de [root] (sin escapes).
  String _inside(String root, String path, String name) =>
      resolveInside(root, path.isEmpty ? name : '$path/$name');

  /// Nombre de archivo/carpeta seguro: sin separadores, sin `..` ni unidad.
  static String _safeName(String raw) {
    final clean = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
    if (clean.isEmpty || clean == '.' || clean == '..') {
      throw StateError('Nombre inválido');
    }
    return clean;
  }

  /// Nombre libre en [dir] ("foto.jpg" → "foto (1).jpg") salvo [overwrite].
  static Future<String> _uniqueIn(
    Directory dir,
    String name,
    bool isFolder, {
    bool overwrite = false,
  }) async {
    if (overwrite) return name;
    final dot = isFolder ? -1 : name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var candidate = name;
    var i = 1;
    while (FileSystemEntity.typeSync('${dir.path}/$candidate') !=
        FileSystemEntityType.notFound) {
      candidate = '$base ($i)$ext';
      i++;
    }
    return candidate;
  }

  /// Copia recursiva (carpetas y archivos de CUALQUIER tipo, igual que el
  /// Drive: si solo se copiaran fotos, un vídeo se perdería al copiar).
  static Future<void> _copyDir(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final e in src.list(followLinks: false)) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (name.startsWith('.')) continue;
      final d = '${dst.path}/$name';
      if (e is Directory) {
        await _copyDir(e, Directory(d));
      } else if (e is File) {
        await e.copy(d);
      }
    }
  }

  /// Respuesta JSON de una operación de escritura.
  static AgentReply _jsonReply(Map<String, dynamic> data) => AgentReply(
    bytes: utf8.encode(jsonEncode(data)),
    mime: 'application/json',
  );

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

  /// Tipo del archivo por su extensión: `image`, `video`, `audio`, `pdf`,
  /// `text` u `other` (los mismos valores que manda el servidor del drive).
  static String _kindOf(String name) {
    if (_isImage(name)) return 'image';
    final ext = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    const video = {
      'mp4', 'm4v', 'mov', 'webm', 'mkv', 'avi', '3gp', 'wmv', 'mpeg',
      'mpg', 'ogv',
    };
    const audio = {
      'mp3', 'm4a', 'wav', 'ogg', 'oga', 'aac', 'flac', 'opus',
    };
    const text = {
      'txt', 'csv', 'json', 'md', 'log', 'xml', 'yml', 'yaml', 'ini', 'srt',
      'vtt',
    };
    if (video.contains(ext)) return 'video';
    if (audio.contains(ext)) return 'audio';
    if (ext == 'pdf') return 'pdf';
    if (text.contains(ext)) return 'text';
    return 'other';
  }

  /// Tipo MIME del archivo.
  ///
  /// Importa de verdad para los VÍDEOS: el navegador integrado (el reproductor
  /// del panel) se niega a reproducir un `<video>` servido como
  /// `application/octet-stream`. Si el archivo no es de un tipo conocido, se
  /// manda el genérico y se ofrece descargarlo.
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
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'mkv':
        return 'video/x-matroska';
      case 'avi':
        return 'video/x-msvideo';
      case '3gp':
        return 'video/3gpp';
      case 'wmv':
        return 'video/x-ms-wmv';
      case 'mpeg':
      case 'mpg':
        return 'video/mpeg';
      case 'ogv':
        return 'video/ogg';
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
        return 'audio/mp4';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
      case 'oga':
        return 'audio/ogg';
      case 'aac':
        return 'audio/aac';
      case 'flac':
        return 'audio/flac';
      case 'opus':
        return 'audio/opus';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
      case 'log':
      case 'srt':
      case 'vtt':
        return 'text/plain';
      case 'csv':
        return 'text/csv';
      case 'json':
        return 'application/json';
      case 'md':
        return 'text/markdown';
      case 'xml':
        return 'application/xml';
      case 'zip':
        return 'application/zip';
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

  /// ¿Cuántos hijos "válidos" tiene la carpeta? (los mismos que se listarían:
  /// carpetas y archivos de cualquier tipo).
  static Future<int> _childCount(Directory dir) async {
    try {
      var n = 0;
      await for (final e in dir.list(followLinks: false)) {
        final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (name.startsWith('.')) continue;
        if (e is Directory || e is File) n++;
      }
      return n;
    } catch (_) {
      return 0;
    }
  }

  /// Reduce una imagen a [maxWidth] de ancho y devuelve sus píxeles CRUDOS
  /// (RGBA) con las medidas del resultado; null si no se pudo (no es una
  /// imagen, formato no soportado o plataforma sin decodificador).
  ///
  /// Se usa el decodificador del propio Flutter (`dart:ui`), que respeta la
  /// orientación EXIF y escala DURANTE el decodificado: una foto de 6000 px no
  /// llega a ocupar su tamaño completo en memoria. El JPEG final lo hace el
  /// servidor, que es quien manda la calidad.
  @visibleForTesting
  Future<({List<int> bytes, int width, int height})?> shrinkToRgba(
    List<int> original,
    int maxWidth,
  ) async {
    if (kIsWeb || original.isEmpty || maxWidth <= 0) return null;
    try {
      final codec = await ui.instantiateImageCodec(
        Uint8List.fromList(original),
        targetWidth: maxWidth,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final width = image.width;
      final height = image.height;
      image.dispose();
      codec.dispose();
      if (data == null) return null;
      return (
        bytes: data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        ),
        width: width,
        height: height,
      );
    } catch (_) {
      return null;
    }
  }

  /// Parte una respuesta en trozos de como mucho [maxBytes]. Puro y público
  /// para poder verificarlo sin red; una respuesta vacía es UN trozo vacío
  /// (el servidor espera al menos una petición).
  @visibleForTesting
  static List<Uint8List> replyChunks(List<int> bytes, {int? maxBytes}) {
    final size = maxBytes ?? replyChunkBytes;
    if (bytes.isEmpty) return [Uint8List(0)];
    if (size <= 0) return [Uint8List.fromList(bytes)];
    final out = <Uint8List>[];
    for (var i = 0; i < bytes.length; i += size) {
      final end = (i + size < bytes.length) ? i + size : bytes.length;
      out.add(Uint8List.fromList(bytes.sublist(i, end)));
    }
    return out;
  }

  /// Manda la respuesta al servidor (bytes crudos; la URL lleva el cómo).
  ///
  /// Va en TROZOS (`seq` + `last`) para no chocar con el límite de cuerpo de
  /// los proxies: un solo cuerpo de varios MB se cortaba y el servidor se
  /// quedaba esperando. Cada trozo se confirma antes de mandar el siguiente, y
  /// se reintenta EL TROZO, no la respuesta entera.
  Future<void> _reply(String id, AgentReply reply) async {
    // La lista es MUTABLE: si el servidor (un proxy delante de él) rechaza un
    // trozo por tamaño, se parte en dos y se sigue. Así la respuesta funciona
    // también con un proxy más estrecho de lo normal.
    final chunks = List<Uint8List>.from(replyChunks(reply.bytes));
    for (var i = 0; i < chunks.length;) {
      final uri = _u('/api/local/agent/reply', {
        'id': id,
        'seq': '$i',
        'last': i == chunks.length - 1 ? '1' : '0',
        'status': '${reply.status}',
        if (reply.mime.isNotEmpty) 'mime': reply.mime,
        if (reply.name.isNotEmpty) 'name': reply.name,
        if (reply.error.isNotEmpty) 'error': reply.error,
        if (reply.isRawRgba) 'fmt': 'rgba',
        if (reply.isRawRgba) 'w': '${reply.rawWidth}',
        if (reply.isRawRgba) 'h': '${reply.rawHeight}',
      });
      var sent = false;
      var tooBig = false;
      var gone = false;
      for (var attempt = 0; attempt < 3 && !sent && _running; attempt++) {
        try {
          final r = await client
              .post(
                uri,
                headers: {
                  ..._headers,
                  'Content-Type': 'application/octet-stream',
                },
                body: chunks[i],
              )
              .timeout(replyChunkTimeout);
          // 404 = el servidor ya dio la petición por perdida: no sirve seguir.
          // 413 = el cuerpo no pasó: se parte el trozo (si se puede).
          if (r.statusCode == 404) {
            gone = true;
            break;
          }
          if (r.statusCode == 413) {
            tooBig = true;
            break;
          }
          if (r.statusCode >= 200 && r.statusCode < 300) sent = true;
        } catch (_) {
          // Corte pasajero del enlace: se reintenta el mismo trozo.
        }
        if (!sent) await _sleep(Duration(seconds: 1 + attempt));
      }
      if (gone) {
        debugPrint('Agente: la petición $id ya no existe en el servidor');
        return;
      }
      if (sent) {
        i++;
        continue;
      }
      if (tooBig) {
        // El proxy no deja pasar cuerpos de ese tamaño: se vuelve a partir TODO
        // lo que queda a la mitad del trozo rechazado (así no se repite el
        // rechazo en cada trozo) y se sigue. Si ya es diminuto, el problema no
        // es el tamaño: se abandona y el servidor explicará el motivo.
        final cur = chunks[i];
        if (cur.length <= minReplyChunkBytes) {
          debugPrint(
            'Agente: el servidor rechaza hasta los trozos de '
            '${cur.length ~/ 1024} KB de la respuesta $id',
          );
          return;
        }
        final rest = <int>[];
        for (final c in chunks.sublist(i)) {
          rest.addAll(c);
        }
        chunks
          ..removeRange(i, chunks.length)
          ..addAll(replyChunks(rest, maxBytes: (cur.length / 2).floor()));
        continue;
      }
      debugPrint(
        'Agente: no se pudo mandar el trozo ${i + 1}/${chunks.length} '
        'de la respuesta $id',
      );
      return;
    }
    _served++;
  }
}

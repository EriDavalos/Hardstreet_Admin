// ==================================================================
// ACTUALIZADOR INTERNO: descarga la nueva versión DENTRO de la app
// (con barra de progreso) y la instala sin pasar por el navegador:
//   - Android: descarga el .apk y dispara el instalador del sistema
//     (FileProvider + ACTION_VIEW) vía MethodChannel.
//   - Windows: descarga el setup .exe y lo lanza con /SILENT; la app
//     se cierra para liberar los archivos y el instalador la relanza.
// ==================================================================
import 'dart:async';
import 'dart:io' if (dart.library.io) 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app_platform.dart';

/// Progreso de la descarga: [received] bytes leídos y [total] del servidor
/// (-1 cuando el servidor no informa el tamaño).
typedef UpdateProgress = void Function(int received, int total);

/// Error controlable del actualizador (mensaje apto para el usuario).
class AppUpdateException implements Exception {
  const AppUpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// El usuario canceló la descarga en curso (no es un error).
class AppUpdateCancelled implements Exception {
  const AppUpdateCancelled();
}

class AppUpdater {
  AppUpdater._();

  /// Canal nativo que abre el instalador del sistema con un .apk.
  static const MethodChannel _installer = MethodChannel('hardstreet/installer');

  /// Descarga real (inyectable en pruebas, igual que HsApi.client).
  static Future<File> Function(
    String url, {
    String? fileName,
    required UpdateProgress onProgress,
  })
  downloadFn = download;

  /// Instalación real (inyectable en pruebas).
  static Future<void> Function(File file) installFn = install;

  /// Cliente HTTP de la descarga activa (para poder cancelarla).
  static HttpClient? _active;
  static bool _cancelled = false;

  /// Señal explícita de cancelación: al cerrar el HttpClient con force, el
  /// stream del socket puede morir en silencio (sin error ni cierre) y
  /// addStream quedaría colgado. Esta señal aborta el bucle sin depender
  /// del socket.
  static Completer<void>? _cancelSignal;

  /// Cancela la descarga en curso (si la hay). El bucle de lectura se
  /// aborta vía [_cancelSignal]; la propia `sub.cancel()` cierra la
  /// conexión HTTP limpia (NO se fuerza el socket: cerrarlo antes deja
  /// la cancelación colgada en el teardown de dart:io).
  static void cancelDownload() {
    _cancelled = true;
    _cancelSignal?.complete();
    _active = null;
  }

  /// Carpeta donde viven las descargas: dentro del caché temporal propio
  /// (la desinstalación de Windows ya limpia hardstreet_cache).
  ///
  /// En Android NO se usa `Directory.systemTemp`: la VM de Dart lo resuelve
  /// a `/data/data/<pkg>/code_cache`, que el FileProvider del instalador no
  /// expone (de ahí el "Failed to find configured root that contains ...").
  /// `getTemporaryDirectory()` devuelve el caché normal de la app, que sí
  /// está declarado en `res/xml/file_paths.xml` (etiqueta `cache-path`).
  static Future<Directory> updatesDir() async {
    final base = isAndroidPlatform
        ? await getTemporaryDirectory()
        : Directory.systemTemp;
    final dir = Directory(
      [
        base.path,
        'hardstreet_cache',
        'updates',
      ].join(Platform.pathSeparator),
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Descarga [url] a un archivo temporal informando progreso por cada
  /// chunk. Lanza [AppUpdateException] (error) o [AppUpdateCancelled].
  static Future<File> download(
    String url, {
    required UpdateProgress onProgress,
    String? fileName,
  }) async {
    if (kWeb) {
      throw const AppUpdateException('Las descargas no existen en web.');
    }
    _cancelled = false;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    _active = client;
    File? part; // fuera del try: el catch de cancelación debe verla
    final cancel = Completer<void>();
    _cancelSignal = cancel;
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close().timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        unawaited(resp.drain<void>().catchError((_) {}));
        throw AppUpdateException(
          'El servidor respondió HTTP ${resp.statusCode}.',
        );
      }
      final total = resp.contentLength; // -1 si es desconocido
      final dir = await updatesDir();
      final name = fileName?.isNotEmpty == true ? fileName! : _nameFromUrl(url);
      part = File([dir.path, '$name.part'].join(Platform.pathSeparator));
      final file = File([dir.path, name].join(Platform.pathSeparator));
      final sink = part.openWrite();
      var received = 0;

      // Lectura por subscription (NO addStream): así la cancelación puede
      // abortar sin depender de que el socket cierre limpio.
      final done = Completer<void>();
      final sub = resp.listen(
        (chunk) {
          received += chunk.length;
          sink.add(chunk);
          onProgress(received, total);
        },
        onError: (Object e) {
          if (!done.isCompleted) done.completeError(e);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      try {
        // Si cancela, la señal gana la carrera aunque el socket esté mudo.
        await Future.any<void>([done.future, cancel.future]);
        if (_cancelled) {
          throw const AppUpdateCancelled();
        }
        await sink.flush();
        await sink.close();
      } catch (e) {
        await sub.cancel();
        try {
          await sink.close();
        } catch (_) {}
        if (_cancelled || e is AppUpdateCancelled) {
          throw const AppUpdateCancelled();
        }
        rethrow;
      }
      if (received == 0) {
        try {
          await part.delete();
        } catch (_) {}
        throw const AppUpdateException('El servidor envió un archivo vacío.');
      }
      if (await file.exists()) await file.delete();
      await part.rename(file.path);
      return file;
    } on AppUpdateCancelled {
      try {
        await part?.delete();
      } catch (_) {}
      rethrow;
    } on AppUpdateException {
      rethrow;
    } on TimeoutException {
      throw const AppUpdateException(
        'El servidor tardó demasiado en responder.',
      );
    } catch (e) {
      if (_cancelled) throw const AppUpdateCancelled();
      throw AppUpdateException('No se pudo descargar: $e');
    } finally {
      if (identical(_active, client)) _active = null;
      if (identical(_cancelSignal, cancel)) _cancelSignal = null;
      client.close(force: true);
    }
  }

  /// Nombre del archivo a partir de la URL (último segmento del path).
  static String _nameFromUrl(String url) {
    final segs = Uri.tryParse(url)?.pathSegments.where((s) => s.isNotEmpty);
    final name = (segs?.isNotEmpty ?? false) ? segs!.last : '';
    if (name.isEmpty) {
      return isAndroidPlatform
          ? 'app-release.apk'
          : 'app-release.exe';
    }
    return name;
  }

  /// Instala el archivo descargado en la plataforma actual:
  /// - Android: el instalador del sistema se abre SOBRE la app (el usuario
  ///   confirma "Instalar" ahí; la app queda viva detrás).
  /// - Windows: lanza el setup en silencioso. La app DEBE cerrarse para
  ///   que el instalador pueda reemplazar sus archivos.
  static Future<void> install(File file) async {
    if (kWeb) {
      throw const AppUpdateException('La instalación no existe en web.');
    }
    if (isAndroidPlatform) {
      try {
        await _installer.invokeMethod<void>('installApk', {'path': file.path});
      } on PlatformException catch (e) {
        throw AppUpdateException(
          e.message ?? 'No se pudo abrir el instalador.',
        );
      } on MissingPluginException {
        throw const AppUpdateException(
          'Esta build no tiene el instalador integrado.',
        );
      }
    } else if (isWindowsPlatform) {
      await Process.start(file.path, const [
        '/SILENT',
        '/SP-',
        '/NOCANCEL',
      ], mode: ProcessStartMode.detached);
      // El setup necesita reemplazar NUESTROS archivos: la app se cierra
      // para liberarlos. El instalador la relanza al terminar (el .iss
      // tiene un [Run] sin skipifsilent para instalaciones silenciosas).
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      exit(0);
    } else {
      throw AppUpdateException(
        'Plataforma $platformName sin instalador automático.',
      );
    }
  }
}

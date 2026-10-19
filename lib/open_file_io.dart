import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// ¿Se puede abrir con OTRA aplicación? Solo en una computadora (Windows,
/// macOS o Linux): ahí existe el \"abrir con\" del sistema.
bool get canOpenWithSystem =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Lanza [path] con la aplicación predeterminada del sistema. `false` si no
/// se pudo (sin programa asociado, sin permiso…).
Future<bool> openLocalFile(String path) async {
  final clean = path.trim();
  if (clean.isEmpty) return false;
  try {
    if (Platform.isWindows) {
      // `start` es del cmd; el primer argumento vacío es el TÍTULO de la
      // ventana (sin él, cmd se come la ruta entre comillas).
      await Process.start('cmd', ['/c', 'start', '', clean]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [clean]);
    } else {
      await Process.start('xdg-open', [clean]);
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Baja [url] a la carpeta temporal de la app (troceado, sin cargar el archivo
/// entero en memoria) y lo abre con su programa predeterminado.
///
/// Es lo que permite VER un PDF, un Word o un ZIP que está en el Drive: la
/// app no sabe pintarlos, el programa del sistema sí.
Future<bool> openUrlFile(String url, {required String name}) async {
  final clean = url.trim();
  if (clean.isEmpty || !canOpenWithSystem) return false;
  final client = http.Client();
  try {
    final dir = Directory(
      [Directory.systemTemp.path, 'hardstreet_abrir'].join(Platform.pathSeparator),
    );
    await dir.create(recursive: true);
    final file = File([dir.path, _safeName(name)].join(Platform.pathSeparator));
    final request = http.Request('GET', Uri.parse(clean));
    final res = await client.send(request).timeout(const Duration(minutes: 5));
    if (res.statusCode != 200) return false;
    final sink = file.openWrite();
    await res.stream.pipe(sink);
    final opened = await openLocalFile(file.path);
    return opened;
  } catch (_) {
    return false;
  } finally {
    client.close();
  }
}

/// Nombre de archivo seguro para la carpeta temporal (el del Drive puede traer
/// caracteres que Windows no admite).
String _safeName(String name) {
  final clean = name
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'^\.+'), '')
      .trim();
  return clean.isEmpty ? 'archivo' : clean;
}

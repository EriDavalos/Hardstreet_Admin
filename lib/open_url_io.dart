import 'dart:io';

/// Abre [url] con el navegador del sistema (Windows, macOS o Linux).
Future<bool> openUrl(String url) async {
  if (!url.startsWith('http://') && !url.startsWith('https://')) return false;
  try {
    if (Platform.isWindows) {
      // `start` es del cmd; el primer argumento vacío es el título (si no,
      // cmd se come la URL entre comillas).
      await Process.start('cmd', ['/c', 'start', '', url]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [url]);
    } else {
      await Process.start('xdg-open', [url]);
    }
    return true;
  } catch (_) {
    return false;
  }
}

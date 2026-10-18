import 'dart:io';

/// Escribe [html] en un archivo temporal y lo abre con el navegador del
/// sistema. Devuelve false si no se pudo (sin permiso, sin navegador…).
Future<bool> openHtmlInBrowser(String html) async {
  try {
    final dir = await Directory.systemTemp.createTemp('hardstreet-tarjeta');
    final file = File('${dir.path}${Platform.pathSeparator}tarjeta.html');
    await file.writeAsString(html);
    if (Platform.isWindows) {
      // `start` es del cmd; el primer argumento vacío es el título (si no,
      // cmd se come la ruta entre comillas).
      await Process.start('cmd', ['/c', 'start', '', file.path]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [file.path]);
    } else {
      await Process.start('xdg-open', [file.path]);
    }
    return true;
  } catch (_) {
    return false;
  }
}

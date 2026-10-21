/// Stub NO-web: en Windows/Android se guarda en la carpeta de Descargas, nunca
/// esta función.
void triggerBrowserDownload(List<int> bytes, String filename) {
  throw UnsupportedError('Descarga del navegador solo disponible en web');
}

/// En la app (no web) siempre sabemos si es un celular con
/// [isAndroidPlatform]/[isIOSPlatform]; el navegador no aplica.
bool isMobileBrowser() => false;

/// Stub NO-web: en Windows/Android se usa el diálogo Guardar de file_selector,
/// nunca esta función.
void triggerBrowserDownload(List<int> bytes, String filename) {
  throw UnsupportedError('Descarga del navegador solo disponible en web');
}

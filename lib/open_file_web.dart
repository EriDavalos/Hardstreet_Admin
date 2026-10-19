// En el navegador no hay \"abrir con otra aplicación\": el archivo se descarga
// y el usuario decide qué hacer con él.
bool get canOpenWithSystem => false;

Future<bool> openLocalFile(String path) async => false;

Future<bool> openUrlFile(String url, {required String name}) async => false;

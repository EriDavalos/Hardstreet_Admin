import 'open_file_io.dart' if (dart.library.js_interop) 'open_file_web.dart';

// ==================================================================
// ABRIR UN ARCHIVO CON LA APLICACIÓN DEL SISTEMA
// ==================================================================
// El Drive muestra fotos, vídeos, PDF y texto dentro de la app, pero un ZIP,
// un Word o un PSD no tienen visor propio: lo que se hace con ellos es
// abrirlos con el programa que el sistema tenga para ese tipo de archivo.
//
// En el ESCRITORIO eso es lanzar el archivo (el mismo camino que usa
// `open_html.dart` para ver una tarjeta en el navegador) y en el NAVEGADOR no
// existe: allí solo se puede descargar. Android tampoco entra por aquí: sus
// archivos remotos necesitan un `content://` que esta app no publica.
// ==================================================================

/// ¿Esta plataforma sabe abrir archivos con otra aplicación?
bool get hsCanOpenWithSystem => canOpenWithSystem;

/// Abre un archivo que YA está en el disco con su programa predeterminado.
/// `false` si no se pudo.
Future<bool> hsOpenLocalFile(String path) => openLocalFile(path);

/// Baja [url] a una carpeta temporal y la abre con su programa
/// predeterminado. `false` si no se pudo (o si la plataforma no sabe).
Future<bool> hsOpenUrlFile(String url, {required String name}) =>
    openUrlFile(url, name: name);

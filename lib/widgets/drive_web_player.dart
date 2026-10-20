// Selector del reproductor del visor según la plataforma.
//
// En la web NO existe el WebView nativo de `flutter_inappwebview`: abrir un
// vídeo con él dejaba la pantalla vacía. En su lugar se incrusta un iframe con
// el MISMO HTML del reproductor (controles propios, póster y errores), usando
// un platform view de Flutter Web.
export 'drive_web_player_stub.dart'
    if (dart.library.js_interop) 'drive_web_player_web.dart';

import 'dart:js_interop';

import 'package:web/web.dart' as web;

// ==================================================================
// SALVAVIDAS DEL ATRÁS EN EL NAVEGADOR (implementado en la APP)
// ==================================================================
// En la web el panel vive en UNA entrada del historial, que el motor de Flutter
// vuelve a empujar DESPUÉS de cada atrás. En el teléfono eso no alcanza: Chrome
// descarta las entradas que se empujan *dentro* de la propia acción de atrás
// (su defensa contra páginas que secuestran el botón). El gesto se saltaba esa
// entrada, la pestaña se quedaba sin historial propio y Android la cerraba:
// salías del panel y volvías al inicio del navegador.
//
// Aquí se deja SIEMPRE una entrada de salvavidas debajo de la actual, escrita
// con la forma que el motor reconoce como «la entrada desde la que se llegó a la
// app»: al pulsar atrás se cae en ella, el motor rearma la suya y el gesto llega
// a la cadena de `BackNav` (cerrar la foto, subir de carpeta, volver al módulo,
// preguntar antes de salir) en vez de salirse.
//
// Dos detalles son los que lo hacen funcionar:
//   1. Se empuja en un `setTimeout`, NUNCA dentro del propio atrás: es la
//      entrada que Chrome sí conserva.
//   2. Se vuelve a armar con el PRIMER TOQUE del usuario, que es cuando el
//      navegador ya no puede marcarla como descartable.
//
// Está escrito en Dart a propósito: así viaja dentro de `main.dart.js` y no hace
// falta publicar también el `index.html` para que el teléfono lo reciba.
// ==================================================================

bool _enabled = false;
bool _armedAtStart = false;
bool _armedWithGesture = false;
bool _listening = false;
bool _listeningPops = false;

/// Arma (o desarma) el salvavidas. Lo llama el panel al montarse y al salir.
void applyWebBackGuard({required bool enabled}) {
  _enabled = enabled;
  if (!enabled) return;
  _listenGestures();
  _listenPops();
  if (_armedAtStart) return;
  _armedAtStart = true;
  _pushGuard();
}

/// El primer toque dentro del panel vuelve a armar con gesto del usuario.
void _listenGestures() {
  if (_listening) return;
  _listening = true;
  void onGesture(web.Event _) {
    if (!_enabled || _armedWithGesture) return;
    _armedWithGesture = true;
    _pushGuard();
  }

  for (final name in const <String>['pointerdown', 'touchstart', 'keydown']) {
    web.window.addEventListener(name, onGesture.toJS);
  }
}

/// Deja el par [salvavidas][actual] encima de la entrada del motor.
///
/// La de abajo lleva la marca `origin` (la que el motor lee como «entrada de
/// origen»); la de arriba clona el estado del motor (`flutter`) para que el
/// primer atrás caiga justo en el salvavidas.
void _pushGuard() {
  web.window.setTimeout(
    (() {
      final current = web.window.history.state;
      final JSAny mine = _isFlutterState(current)
          ? current!
          : <String, Object?>{'flutter': true}.jsify()!;
      final url = web.window.location.href;
      web.window.history.pushState(
        <String, Object?>{'origin': true, 'state': null}.jsify(),
        '',
        url,
      );
      web.window.history.pushState(mine, '', url);
    }).toJS,
    0.toJS,
  );
}

/// ¿El estado es uno de los que escribe el motor de Flutter?
bool _isFlutterState(JSAny? state) {
  if (state == null) return false;
  final value = state.dartify();
  return value is Map && value['flutter'] == true;
}

/// ¿El estado es una entrada de ORIGEN (la marca `origin`)? La escribe el
/// motor al arrancar y la escribe este salvavidas al armar el par.
bool _isOriginState(JSAny? state) {
  if (state == null) return false;
  final value = state.dartify();
  return value is Map && value['origin'] == true;
}

///
/// RESCATE TRAS CADA ATRÁS.
///
/// El motor de Flutter re-arma su entrada cuando el atrás cae en la de
/// origen, pero lo hace SINCRÓNICAMENTE dentro del propio gesto — el caso
/// EXACTO que Chrome en el teléfono descarta a veces (su defensa contra
/// páginas que secuestran el botón). Si el teléfono tira esa re-arma, la
/// app queda parada sobre la entrada de origen SIN NADA encima: el
/// siguiente atrás sale de la app al inicio del navegador. Este rescate
/// conserva el trabajo que el motor no pudo:
///
///   * Escucha TODOS los popstate (fue atrás el usuario o el motor).
///   * En un `setTimeout` (la vía que Chrome SÍ respeta, verificada en el
///     teléfono) mira dónde quedó la pestaña: si aún está parada sobre una
///     entrada de origen —el motor no logró poner su entrada encima— la
///     re-pone él mismo, de la misma forma que lo haría el motor.
///   * Si el motor logró re-armar (es lo normal), aquí no se hace NADA: la
///     entrada quedó ya como «flutter» y el salvavidas sigue intacto abajo.
///
/// Sin este paso: los anteriores atrás (ver fotos, subir de carpeta) no
/// desarmaban nada por sí mismos, PERO si el teléfono descartaba UNA re-
/// arma, el par quedaba roto para SIEMPRE: por eso fallaba «después de
/// seleccionar fotos» y no al entrar directo.
void _listenPops() {
  if (_listeningPops) return;
  _listeningPops = true;
  void onPop(web.Event _) {
    if (!_enabled) return;
    web.window.setTimeout(() {
      if (!_enabled) return;
      final state = web.window.history.state;
      // El motor logró re-armar: la entrada quedó como «flutter».
      if (_isFlutterState(state)) return;
      // Quedamos parados sobre una entrada de origen (el motor no logró
      // poner la suya encima): reponemos la del motor.
      if (!_isOriginState(state)) return;
      web.window.history.pushState(
        <String, Object?>{'flutter': true}.jsify()!,
        '',
        web.window.location.href,
      );
    }.toJS, 0.toJS);
  }

  web.window.addEventListener('popstate', onPop.toJS);
}

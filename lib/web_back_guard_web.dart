import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

// ==================================================================
// EL ATRÁS DEL NAVEGADOR (solo web)
// ==================================================================
// En el APK el atrás es del sistema y lo atiende la cadena de `BackNav` a
// través del `PopScope` raíz. En la WEB el atrás es del NAVEGADOR, y el motor
// de Flutter también lo escucha para sincronizar la URL. Eso es lo que rompía
// el gesto:
//
//   · El motor vive en modo de UNA entrada (`WidgetsApp` pide
//     `selectSingleEntryHistory`): al caer en su entrada «origin» repone la
//     suya y entrega `popRoute`… pero si cae en una «flutter» cree que el
//     usuario escribió otra URL y hace `pushRoute` (la app «salta» de nivel),
//     y si cae en una entrada cualquiera hace `history.go(-1)`, que SACA de la
//     página. Cualquier entrada nuestra metida en medio lo descoloca.
//   · El teléfono, además, descarta los `pushState` hechos dentro del gesto,
//     así que una «reserva» de entradas se GASTA un paso por cada atrás.
//
// Por eso el atrás ya no se negocia: la app se queda con el gesto.
//
//   1. **Navigation API** (Chrome/Android): el evento `navigate` de un atrás
//      dentro del mismo documento llega con `cancelable == true`. Se cancela:
//      el historial NO se mueve y el gesto se entrega a la app.
//   2. **Respaldo**: se escucha `popstate` ANTES que el motor (el guardia se
//      instala en `main()`, antes de que exista el `Navigator`, que es quien
//      registra el suyo), se corta la propagación para que el motor no lo
//      interprete como cambio de URL, se repone la entrada y se entrega el
//      gesto con el MISMO mensaje que usa el atrás del sistema.
//
// En los dos caminos el atrás llega a la app UNA vez por gesto: cerrar el
// visor de fotos/vídeos, cerrar un modal que abrió otro modal, subir de
// carpeta y volver al módulo funcionan como niveles, igual que en el APK.
//
// Está escrito en Dart a propósito: viaja dentro de `main.dart.js`, así que
// basta con publicar la build de la web para que el teléfono lo reciba.

bool _enabled = false;
bool _installed = false;

/// Instala el guardia. Se llama en `main()`, ANTES de `runApp`: así el
/// `popstate` se registra antes que el del motor y se puede cortar.
/// Fuera de la web y en las pruebas no hace nada.
void installWebBackGuardImpl() {
  if (_installed) return;
  _installed = true;
  _listenNavigate();
  _listenPops();
}

/// Arma (o desarma) el guardia: solo actúa con el PANEL en pantalla; en el
/// login y en el arranque el atrás sigue siendo del navegador.
void applyWebBackGuardImpl({required bool enabled}) {
  _enabled = enabled;
  // El primer armado viene después de que el motor escribió sus entradas:
  // si quedamos a un atrás de salir, se repone la del motor.
  if (enabled) _heal();
}

// ------------------------------------------------------------------
// 1) Navigation API: cancelar el gesto (el historial no se mueve)
// ------------------------------------------------------------------

extension type _Navigation(JSObject _) implements JSObject {
  external void addEventListener(String type, JSAny listener);
  external _NavEntry get currentEntry;
}

extension type _NavEntry(JSObject _) implements JSObject {
  external int? get index;
}

extension type _NavigateEvent(JSObject _) implements JSObject {
  external bool get cancelable;
  external String get navigationType;
  external _NavDestination get destination;
  external void preventDefault();
}

extension type _NavDestination(JSObject _) implements JSObject {
  external bool get sameDocument;
  external int? get index;
}

_Navigation? _navigationApi() {
  final JSAny? nav = globalContext.getProperty<JSAny?>('navigation'.toJS);
  if (nav == null) return null;
  return nav as _Navigation;
}

void _listenNavigate() {
  final nav = _navigationApi();
  if (nav == null) return;
  nav.addEventListener(
    'navigate',
    ((JSAny event) {
      if (!_enabled) return;
      final _NavigateEvent e = event as _NavigateEvent;
      // Solo ATRÁS dentro del mismo documento: un `push`/`replace` (lo que
      // hace el motor al cambiar de ruta) o una recarga no se tocan.
      if (e.navigationType != 'traverse') return;
      if (!e.destination.sameDocument) return;
      final to = e.destination.index;
      final from = nav.currentEntry.index;
      if (to != null && from != null && to >= from) return;
      // Sin licencia para cancelar, el navegador se moverá: lo atiende el
      // respaldo de `popstate`.
      if (!e.cancelable) return;
      e.preventDefault();
      _deliverBack();
    }).toJS,
  );
}

// ------------------------------------------------------------------
// 2) Respaldo: `popstate` propio (el motor no lo toca)
// ------------------------------------------------------------------

/// Estado que el motor reconoce como suyo. Se repone siempre para que, si el
/// guardia se desarma (cerrar sesión), el motor siga viendo su mundo intacto.
JSAny _flutterState() => <String, Object?>{'flutter': true}.jsify()!;

bool _isFlutterState(JSAny? state) {
  if (state == null) return false;
  final value = state.dartify();
  return value is Map && value['flutter'] == true;
}

/// «origin» es la entrada que el motor deja DEBAJO de la suya: caer en ella
/// significa que el siguiente atrás ya sale de la app.
bool _isOriginState(JSAny? state) {
  if (state == null) return false;
  final value = state.dartify();
  return value is Map && value['origin'] == true;
}

/// Vuelve a dejar una entrada del motor encima.
void _heal() {
  if (!_enabled) return;
  final state = web.window.history.state;
  if (_isFlutterState(state)) return;
  // Solo se repone cuando estamos a un atrás de salir (o sobre una entrada
  // propia): si hay otra cosa, no se toca.
  if (state != null && !_isOriginState(state)) return;
  web.window.history.pushState(_flutterState(), '', web.window.location.href);
}

void _listenPops() {
  // `true` = fase de captura. Al registrarse antes que el motor, este corre
  // primero y puede cortar la propagación.
  web.window.addEventListener(
    'popstate',
    ((web.Event event) {
      if (!_enabled) return;
      // El gesto es de la app: el motor no debe interpretarlo como un cambio
      // de URL (`pushRoute`) ni devolverse otra vez (`go(-1)`).
      event.stopImmediatePropagation();
      // Se repone la entrada y, si el navegador ignora el `pushState` dentro
      // del gesto, se reintenta fuera de él.
      _heal();
      web.window.setTimeout((() => _heal()).toJS, 120.toJS);
      web.window.setTimeout((() => _heal()).toJS, 700.toJS);
      _deliverBack();
    }).toJS,
    true.toJS,
  );

  // El teléfono congela los temporizadores en segundo plano: al volver, se
  // revisa otra vez por si el gesto se quedó sin reponer.
  web.window.addEventListener('visibilitychange', ((web.Event _) {
    if (!_enabled) return;
    if (web.document.visibilityState == 'visible') _heal();
  }).toJS);
}

/// Entrega el atrás a la app por el mismo mensaje que manda el motor cuando el
/// atrás es del sistema (`flutter/navigation` → `popRoute`): cierra el diálogo
/// o el visor, sube de carpeta, vuelve al módulo y pregunta antes de salir.
void _deliverBack() {
  ServicesBinding.instance.channelBuffers.push(
    SystemChannels.navigation.name,
    const JSONMethodCodec().encodeMethodCall(MethodCall('popRoute')),
    (_) {},
  );
}

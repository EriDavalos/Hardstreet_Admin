import 'package:hardstreet_admin/app/back_nav.dart';
import 'package:hardstreet_admin/app/web_back_guard_stub.dart'
    if (dart.library.js_interop) 'package:hardstreet_admin/app/web_back_guard_web.dart';

// ==================================================================
// EL ATRÁS DEL NAVEGADOR (solo web)
// ==================================================================
// En la web el atrás lo disputan dos: el navegador y el MOTOR de Flutter (que
// escucha `popstate` para sincronizar la URL y puede acabar navegando él:
// `pushRoute` si cree que cambió la URL, o `go(-1)`, que saca de la página).
//
// El salvavidas vive en `web_back_guard_web.dart` (o sea, DENTRO de
// `main.dart.js`: viaja con el mismo archivo que publicas). Se instala en
// `main()` —antes de que exista el `Navigator`, que es quien registra el
// `popstate` del motor— y se queda con el gesto: lo cancela con la Navigation
// API cuando el navegador lo permite y, si no, corta la propagación del
// `popstate` y entrega el atrás a la app por el mismo mensaje que el atrás del
// sistema (`popRoute`).
//
// Aquí solo se avisa cuándo debe estar ARMADO: con el PANEL en pantalla (con
// sesión). En el login y en la intro no se arma: ahí el atrás sigue siendo del
// navegador, como siempre. En Android, Windows, iOS y en las pruebas no hace
// nada: allí el atrás lo atiende el sistema.
// ==================================================================

/// Instala el salvavidas. Se llama en `main()`, antes de `runApp`.
void installWebBackGuard() => installWebBackGuardImpl();

/// Arma (o desarma) el salvavidas.
void setWebBackGuard({required bool enabled}) {
  // El guardia del atrás ([BackNavGuard]) necesita saber si el PANEL está
  // abierto: así un atrás sin pasos se queda en el panel en vez de apagar la
  // app (en la web eso te sacaba al inicio del navegador).
  BackNavGuard.panelIsOpen = enabled;
  applyWebBackGuardImpl(enabled: enabled);
}

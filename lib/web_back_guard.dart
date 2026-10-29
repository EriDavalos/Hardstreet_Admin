import 'web_back_guard_stub.dart'
    if (dart.library.js_interop) 'web_back_guard_web.dart';

// ==================================================================
// SALVAVIDAS DEL ATRÁS EN EL NAVEGADOR
// ==================================================================
// El panel vive en UNA entrada del historial del navegador. En el teléfono,
// Chrome descarta las entradas que se empujan dentro de la propia acción de
// atrás, así que el gesto se escapaba y la pestaña salía del panel (volvía al
// inicio del navegador). El salvavidas se escribe en `web/index.html`; aquí
// solo se le avisa cuándo debe estar armado: cuando el PANEL está en pantalla
// (con sesión). En el login y en la intro no se arma: ahí el atrás sigue
// siendo del navegador, como siempre.
// ==================================================================

/// Arma (o desarma) el salvavidas del historial. En Android, Windows, iOS y en
/// las pruebas no hace nada: allí el atrás lo atiende el sistema.
void setWebBackGuard({required bool enabled}) =>
    applyWebBackGuard(enabled: enabled);

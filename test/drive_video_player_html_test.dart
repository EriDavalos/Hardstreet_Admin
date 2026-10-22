import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_base.dart';
import 'package:hardstreet_admin/widgets/drive_media_viewer.dart';

// ==================================================================
// EL REPRODUCTOR DE VÍDEO DEL VISOR
// ==================================================================
// Se verifica el HTML que se inyecta en el navegador integrado: póster
// mientras carga, aviso de "Cargando…", los controles PROPIOS estilo YouTube
// (barra, tiempo, volumen, velocidad, pantalla completa, doble toque ±10 s) y
// que un PDF use el visor del navegador (iframe) en vez de un <video>.
// ==================================================================

DriveViewTarget target(String name, {String poster = ''}) => DriveViewTarget(
  item: DriveItem(name: name, isFolder: false),
  source: 'https://drive.test/files/$name?token=a&b=1',
  isRemote: true,
  poster: poster,
);

// DOM de mentira para EJECUTAR el script del reproductor sin navegador: solo
// lo que toca (elementos, eventos, un <video> que se deja gobernar).
const _harnessHead = r'''
const _mk = (id) => ({
  id,
  _h: {},
  style: { setProperty() {}, opacity: '', display: '', pointerEvents: '' },
  classList: { _s: new Set(), add(c) { this._s.add(c); }, remove(c) { this._s.delete(c); }, contains(c) { return this._s.has(c); } },
  addEventListener(n, f) { (this._h[n] || (this._h[n] = [])).push(f); },
  innerHTML: '',
  textContent: '',
  value: '0',
});
const _ids = ['media','stage','big','status','statusText','spinner','error','controls','play','seek','cur','dur','mute','vol','full',
  'poster','tapL','tapR','speed','speedMenu','volbox','sound','sp05','sp10','sp125','sp15','sp20'];
const _els = {};
for (const _i of _ids) _els[_i] = _mk(_i);
const MEDIA = _els.media;
MEDIA.paused = true;
MEDIA.currentTime = 0;
MEDIA.duration = NaN;
MEDIA.readyState = 4;
MEDIA.muted = false;
MEDIA.volume = 1;
MEDIA.error = null;
MEDIA.seeking = false;
MEDIA.buffered = { length: 0, start() { return 0; }, end() { return 0; } };
MEDIA.play = () => Promise.resolve();
MEDIA.pause = () => { MEDIA.paused = true; };
MEDIA.playbackRate = 1;
// Zona del reproductor de 400x300: el doble toque decide izquierda/derecha.
_els.stage.getBoundingClientRect = () => ({ left: 0, top: 0, width: 400, height: 300 });
// El celular/tablet tiene toques: activa el doble toque para adelantar.
globalThis.ontouchstart = null;
globalThis.document = {
  getElementById: (i) => _els[i],
  addEventListener() {},
  fullscreenElement: null,
};
globalThis.window = globalThis;
globalThis.setInterval = () => 0;
// Los temporizadores no deben dejar vivo el proceso de node en las pruebas.
globalThis.setTimeout = () => 0;
const _fire = (e, n, ev) => { for (const f of (e._h[n] || [])) f(ev); };
const _ok = (c, msg) => {
  if (!c) {
    console.error('FALLO: ' + msg);
    process.exit(1);
  }
};
''';

// Lo que tiene que pasar al adelantar un vídeo en CALIDAD LIGERA: se pide otra
// vez el vídeo desde ese segundo y la barra cuenta desde el salto.
const _lightTail = r'''
window.hsSetDuration(120);
_ok(_els.dur.textContent === '2:00', 'la duración total se pinta: ' + _els.dur.textContent);
MEDIA.paused = false;
_fire(MEDIA, 'playing');
_els.seek.value = '500';
_fire(_els.seek, 'input');
_fire(_els.seek, 'change');
_ok(
  /[?&]t=60\.00$/.test(MEDIA.src || ''),
  'adelantar pide el vídeo desde ese segundo: ' + MEDIA.src
);
_ok(
  _els.cur.textContent === '1:00',
  'el tiempo mostrado es absoluto: ' + _els.cur.textContent
);
MEDIA.currentTime = 5;
_fire(MEDIA, 'timeupdate');
_ok(
  _els.cur.textContent === '1:05',
  'el tiempo sigue contando desde el salto: ' + _els.cur.textContent
);
_ok(
  Math.abs(Number(_els.seek.value) - (65 / 120) * 1000) < 1,
  'la barra usa el tiempo absoluto: ' + _els.seek.value
);
// Si el servidor NO pudo reencodar desde t (mandó el vídeo entero), la barra
// se corrige en vez de señalar un minuto que no es.
_els.seek.value = '250';
_fire(_els.seek, 'change');
MEDIA.duration = 120;
MEDIA.currentTime = 0;
_fire(MEDIA, 'loadedmetadata');
_ok(
  _els.seek.value === '0',
  'sin reencodado desde t vuelve a la cuenta real: ' + _els.seek.value
);
console.log('OK');
''';

// Si el reencodado (calidad ligera) NO se puede reproducir, el reproductor
// prueba UNA vez el archivo ORIGINAL; solo si ese también falla, avisa.
const _lightFailTail = r'''
_fire(MEDIA, 'error');
_ok(
  MEDIA.src === 'https://drive.test/files/boda.mp4?view=1',
  'cae al original sin play=low: ' + MEDIA.src
);
_ok(
  _els.error.style.display !== 'flex',
  'el primer fallo no enseña el aviso: ' + _els.error.style.display
);
_fire(MEDIA, 'error');
_ok(
  _els.error.style.display === 'flex',
  'si el ORIGINAL tampoco abre, ahí sí se avisa'
);
console.log('OK');
''';

// DOBLE TOQUE (como YouTube en el celular): dos toques seguidos a la derecha
// adelantan 10 s y a la izquierda atrasan 10 s, sin recargar el archivo.
const _doubleTapTail = r'''
window.hsSetDuration(120);
MEDIA.currentTime = 0;
_fire(MEDIA, 'click', { clientX: 330 });
_fire(MEDIA, 'click', { clientX: 330 });
_ok(
  Math.abs(MEDIA.currentTime - 10) < 0.01,
  'doble toque a la derecha adelanta 10 s: ' + MEDIA.currentTime
);
_ok(
  _els.tapR.classList.contains('show'),
  'el circulo de la derecha aparece'
);
_fire(MEDIA, 'click', { clientX: 60 });
_fire(MEDIA, 'click', { clientX: 60 });
_ok(
  Math.abs(MEDIA.currentTime) < 0.01,
  'doble toque a la izquierda atrasa 10 s: ' + MEDIA.currentTime
);
_ok(
  _els.tapL.classList.contains('show'),
  'el circulo de la izquierda aparece'
);
// La velocidad se elige desde el menu y se aplica al video.
_fire(_els.sp15, 'click');
_ok(MEDIA.playbackRate === 1.5, 'velocidad 1.5x: ' + MEDIA.playbackRate);
_ok(_els.speed.textContent === '1.5x', 'el boton dice 1.5x: ' + _els.speed.textContent);
_ok(
  _els.sp15.classList.contains('on'),
  'la opcion elegida queda marcada'
);
console.log('OK');
''';

// ARRANQUE AUTOMÁTICO: si el navegador rechaza el play CON sonido, el vídeo
// arranca en MUDO (siempre permitido) y se ofrece activar el sonido.
const _autoplayTail = r'''
let calls = 0;
MEDIA.paused = true;
MEDIA.muted = false;
MEDIA.play = () => {
  calls++;
  return calls === 1
    ? Promise.reject(new Error('autoplay con sonido bloqueado'))
    : Promise.resolve();
};
autoplay();
await Promise.resolve();
await Promise.resolve();
await Promise.resolve();
_ok(calls === 2, 'reintenta en mudo: ' + calls);
_ok(MEDIA.muted === true, 'el video arranca en mudo');
_ok(_els.sound.classList.contains('show'), 'se ofrece activar el sonido');
_ok(_els.mute.classList.contains('off'), 'el boton de silencio queda apagado');
_fire(_els.sound, 'click');
_ok(MEDIA.muted === false, 'el toque devuelve el sonido: ' + MEDIA.muted);
_ok(!_els.sound.classList.contains('show'), 'el aviso desaparece');
_ok(calls === 3, 'vuelve a reproducir con sonido: ' + calls);
console.log('OK');
''';

// PANTALLA COMPLETA EN LA WEB: el reproductor vive en un IFRAME. Se pide al
// iframe mismo; si el navegador lo niega, a la PAGINA que lo contiene. Pedirla
// solo al elemento de dentro (lo que hacía antes) no agrandaba nada.
const _fullscreenTail = r'''
const _pdoc = {
  documentElement: { requestFullscreen() { return Promise.resolve(); } },
  fullscreenElement: null,
  addEventListener() {},
  exitFullscreen() { this.exited = true; return Promise.resolve(); },
};
globalThis.parent = { document: _pdoc };
let frameCalls = 0, pageCalls = 0;
_pdoc.documentElement.requestFullscreen = () => { pageCalls++; return Promise.resolve(); };
globalThis.frameElement = {
  requestFullscreen() { frameCalls++; return Promise.resolve(); },
};
_fire(_els.full, 'click');
_ok(frameCalls === 1, 'se pide la pantalla completa al iframe: ' + frameCalls);
_ok(pageCalls === 0, 'no hace falta la pagina si el iframe la acepta');
// El navegador avisa con `fullscreenchange`: el boton cambia a "salir".
_pdoc.fullscreenElement = {};
fullSync();
_ok(_els.full.classList.contains('on'), 'el boton avisa que esta en pantalla completa');
// Salir: la pantalla completa la tiene el documento PADRE.
_pdoc.exited = false;
_fire(_els.full, 'click');
_ok(_pdoc.exited === true, 'el segundo toque sale de pantalla completa');
_pdoc.fullscreenElement = null;
fullSync();
_ok(!_els.full.classList.contains('on'), 'el boton vuelve a su estado normal');
// Si el navegador RECHAZA el iframe, se pide a la pagina.
frameCalls = 0; pageCalls = 0;
globalThis.frameElement = {
  requestFullscreen() { frameCalls++; return Promise.reject(new Error('no')); },
};
_fire(_els.full, 'click');
await Promise.resolve();
await Promise.resolve();
_ok(frameCalls === 1, 'intenta el iframe primero: ' + frameCalls);
_ok(pageCalls === 1, 'si el iframe falla, pide la pagina: ' + pageCalls);
console.log('OK');
''';

// SIN la duración real (los vídeos que viven en la PC del dueño no la mandan
// en el HEAD), el fragmento solo dice lo que QUEDA. Antes se tomaba como total
// y al adelantar el tiempo volvía a 0 aunque el vídeo siguiera en el salto.
const _lightNoTotalTail = r'''
MEDIA.duration = 120; // el primer tramo sí trae su duración
MEDIA.paused = false;
_fire(MEDIA, 'playing');
_els.seek.value = '500';
_fire(_els.seek, 'change');
_ok(
  /[?&]t=60\.00$/.test(MEDIA.src || ''),
  'adelantar pide el vídeo desde el segundo 60: ' + MEDIA.src
);
_ok(
  _els.cur.textContent === '1:00',
  'el tiempo del salto es 1:00: ' + _els.cur.textContent
);
// Llega el fragmento NUEVO: dura solo lo que queda (60 s), no el total.
MEDIA.duration = 60;
MEDIA.currentTime = 0;
_fire(MEDIA, 'loadedmetadata');
_ok(
  _els.cur.textContent === '1:00',
  'el tiempo NO se reinicia: ' + _els.cur.textContent
);
_ok(
  _els.dur.textContent === '2:00',
  'el total se deduce (salto + lo que queda): ' + _els.dur.textContent
);
MEDIA.currentTime = 5;
_fire(MEDIA, 'timeupdate');
_ok(
  _els.cur.textContent === '1:05',
  'sigue contando desde el salto: ' + _els.cur.textContent
);
_ok(
  Math.abs(Number(_els.seek.value) - (65 / 120) * 1000) < 1,
  'la barra usa el total correcto: ' + _els.seek.value
);
console.log('OK');
''';

// Un archivo normal (no reencodado): salta con `currentTime`, sin recargar.
const _plainTail = r'''
window.hsSetDuration(120);
MEDIA.paused = false;
_fire(MEDIA, 'playing');
_els.seek.value = '500';
_fire(_els.seek, 'change');
_ok(
  Math.abs(MEDIA.currentTime - 60) < 0.01,
  'un archivo normal salta con currentTime: ' + MEDIA.currentTime
);
_ok(MEDIA.src === undefined, 'no se recarga el vídeo: ' + MEDIA.src);
console.log('OK');
''';

/// `node` disponible (para validar la SINTAXIS del script del reproductor).
String? _nodePath() {
  try {
    final r = Process.runSync('node', ['--version']);
    return r.exitCode == 0 ? 'node' : null;
  } catch (_) {
    return null;
  }
}

void main() {
  // Un error de sintaxis en el JS no lo detecta ninguna aserción de texto:
  // el navegador deja de ejecutar TODO el script, el vídeo se queda
  // "Cargando vídeo…" para siempre y ningún control responde (ni la pantalla
  // completa). Eso ya pasó una vez, así que aquí se compila de verdad.
  final node = _nodePath();
  test('los scripts de vídeo y audio compilan sin errores de sintaxis', () {
    final dir = Directory.systemTemp.createTempSync('hs_player');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final (label, html) in [
      ('vídeo', debugDrivePlayerHtml(target('boda.mp4'))),
      ('audio', debugDrivePlayerHtml(target('tema.mp3'))),
    ]) {
      final script = RegExp(r'<script>([\s\S]*)</script>')
          .firstMatch(html)
          ?.group(1);
      expect(script, isNotNull, reason: 'falta el script del $label');
      final js = File('${dir.path}/$label.js')..writeAsStringSync(script!);
      final r = Process.runSync(node!, ['--check', js.path]);
      expect(r.exitCode, 0, reason: 'script de $label: ${r.stderr}');
    }
  }, skip: node == null ? 'node no está instalado' : false);

  test('el vídeo lleva póster, controles y aviso de carga', () {
    final html = debugDrivePlayerHtml(
      target('boda.mp4', poster: 'https://drive.test/thumb/boda.mp4?w=1280'),
    );

    expect(html, contains('<video'));
    expect(html, contains('poster="https://drive.test/thumb/boda.mp4?w=1280"'));
    expect(html, contains('playsinline'));
    expect(html, contains('object-fit:contain'));
    // Controles PROPIOS (modernos y iguales en WebView y web), no los del
    // navegador: reproducir, barra de avance, tiempo, volumen y pantalla
    // completa.
    expect(html, contains('id="controls"'));
    expect(html, contains('id="play"'));
    expect(html, contains('id="seek"'));
    expect(html, contains('id="vol"'));
    expect(html, contains('id="full"'));
    // Y el botón grande de reproducir sobre el póster.
    expect(html, contains('class="big-play"'));
    // VISTA MODERNA estilo YouTube: póster que se desvanece, botón central
    // con animación, menú de velocidad y barra fina que engorda al pasar el
    // mouse.
    expect(html, contains('id="poster"'));
    expect(html, contains('.poster.hide'));
    expect(html, contains('id="speedMenu"'));
    expect(html, contains('id="sp15"'));
    expect(html, contains('.seekwrap:hover #seek'));
    expect(html, contains('id="tapR"'));
    expect(html, contains('function onSurface(ev)'));
    expect(html, contains('jump(right?10:-10)'));
    // Arranca solo; si el navegador bloquea el sonido, en mudo con aviso.
    expect(html, contains('function autoplay()'));
    expect(html, contains('id="sound"'));
    expect(html, contains('Toca para activar el sonido'));
    // BOTÓN CENTRAL con el diseño de la APP: cuadrado redondeado, color de
    // acento y centrado con translate (sin márgenes que lo descoloquen).
    final big = RegExp(r'\.big-play\{[^}]*\}')
        .firstMatch(html)
        ?.group(0)
        ?.toString();
    expect(big, isNotNull, reason: 'falta el estilo del botón central');
    expect(big, contains('background:var(--accent)'));
    expect(big, contains('border-radius:22px'));
    expect(big, contains('translate(-50%,-50%)'));
    expect(
      big,
      isNot(contains('backdrop-filter')),
      reason: 'el botón central ya no es de cristal: es plano como la app',
    );
    // Estado legible mientras el archivo viaja (antes: pantalla negra).
    expect(html, contains('Cargando vídeo…'));
    expect(html, contains('addEventListener("loadeddata"'));
    expect(html, contains('addEventListener("waiting"'));
    // Descarga anticipada: con `metadata` el reproductor se quedaba sin búfer
    // a media reproducción y el vídeo se congelaba sin avisar.
    expect(html, contains('preload="auto"'));
    // El giro de carga NO puede quedar debajo del <video> (z-index).
    expect(html, contains('.spinner{display:none;position:absolute;z-index:4'));
    // Al buscar o al agotarse el búfer también se avisa, y dice cuánto lleva.
    expect(html, contains('addEventListener("seeking",buffering)'));
    expect(html, contains('bufferedPct()'));
    // BARRA DE CARGA con lo visto, lo descargado y lo que falta, siempre a la
    // vista mientras se reproduce (no se esconde sola a los 2,8 s).
    expect(html, contains('--played'));
    expect(html, contains('--buffered'));
    expect(html, contains('paintBar()'));
    expect(html, isNot(contains('controls.classList.remove("show")')));
    // La calidad ligera llega en MP4 fragmentado SIN duración: el visor recibe
    // la duración real del servidor y la usa para el total y la barra.
    expect(html, contains('hsSetDuration'));
    expect(html, contains('knownDuration'));
    expect(html, contains('function total()'));
    // Y el giro de carga se oculta si el tiempo AVANZA (no solo por
    // readyState: un MP4 fragmentado casi nunca llega a 3).
    expect(html, contains('function moving()'));
    expect(html, contains('!m.paused&&moving()'));
    // Error explicado, no un recuadro vacío.
    expect(html, contains('No se pudo reproducir este archivo'));
    // El elemento del aviso NO se guarda en una variable llamada `status`:
    // `window.status` es una propiedad especial del navegador y guardaría el
    // TEXTO del elemento, rompiendo el manejador que oculta el aviso.
    expect(html, isNot(contains('status=document.getElementById("status")')));
    expect(html, contains('statusEl=document.getElementById("status")'));
    // Al terminar de cargar, el aviso y el botón grande se sincronizan con el
    // estado real del vídeo (aunque los eventos hayan llegado antes).
    expect(html, contains('syncStatus()'));
    expect(html, contains('setInterval(function(){icon();syncStatus()}'));
    // El HTML se escapa (la URL trae &).
    expect(html, contains('token=a&amp;b=1'));
  });

  // La CALIDAD LIGERA (`?play=low`) se reencoda al vuelo: cada petición es un
  // ffmpeg nuevo y el servidor NO puede saltar a un byte. Mover `currentTime`
  // hacía que el navegador pidiera el vídeo otra vez desde el principio y se
  // veía cómo el vídeo VOLVÍA A EMPEZAR. Ahora adelantar pide el vídeo con
  // `&t=<segundos>` y la barra lleva la cuenta del salto.
  test('en calidad ligera ADELANTAR pide el vídeo desde ese segundo', () {
    final html = debugDrivePlayerHtml(
      DriveViewTarget(
        item: DriveItem(name: 'boda.mp4', isFolder: false),
        source: 'https://drive.test/files/boda.mp4?view=1&play=low',
        isRemote: true,
      ),
    );
    expect(html, contains('var lightStream=true'));
    expect(html, contains('function applySeek(t)'));
    // El salto va al SERVIDOR con `t=`; el `currentTime` solo se usa en los
    // archivos normales (que sí soportan Range).
    expect(html, contains('+"t="+t.toFixed(2)'));
    expect(html, contains('if(!lightStream){m.currentTime=t;return}'));
    // Los tiempos y la barra son ABSOLUTOS (lo ya saltado + lo del tramo).
    expect(html, contains('baseOff+m.currentTime'));
    expect(html, contains('window.hsSetDuration'));
    // Las flechas del teclado también adelantan (no reinician).
    expect(html, contains('jump(5)'));
    expect(html, contains('jump(-5)'));
    // Un archivo normal sigue usando el salto nativo del navegador.
    expect(
      debugDrivePlayerHtml(target('boda.mp4')),
      contains('var lightStream=false'),
    );
  });

  test(
    'ejecutado de verdad: adelantar NO reinicia el vídeo y la barra no miente',
    () {
      final dir = Directory.systemTemp.createTempSync('hs_seek');
      addTearDown(() => dir.deleteSync(recursive: true));
      final ligero = DriveViewTarget(
        item: const DriveItem(name: 'boda.mp4', isFolder: false),
        source: 'https://drive.test/files/boda.mp4?view=1&play=low',
        isRemote: true,
      );
      for (final (label, html, tail) in [
        ('ligero', debugDrivePlayerHtml(ligero), _lightTail),
        ('normal', debugDrivePlayerHtml(target('boda.mp4')), _plainTail),
      ]) {
        final script = RegExp(r'<script>([\s\S]*)</script>')
            .firstMatch(html)
            ?.group(1);
        expect(script, isNotNull, reason: 'falta el script del vídeo ($label)');
        final js = File('${dir.path}/$label.mjs')
          ..writeAsStringSync('$_harnessHead\n$script\n$tail');
        final r = Process.runSync(node!, [js.path]);
        expect(r.exitCode, 0, reason: 'seek ($label): ${r.stdout}${r.stderr}');
        expect('${r.stdout}', contains('OK'));
      }
    },
    skip: node == null ? 'node no está instalado' : false,
  );

  test('ejecutado de verdad: sin duración total, adelantar no reinicia el tiempo', () {
    final dir = Directory.systemTemp.createTempSync('hs_no_total');
    addTearDown(() => dir.deleteSync(recursive: true));
    final html = debugDrivePlayerHtml(
      DriveViewTarget(
        item: const DriveItem(name: 'boda.mp4', isFolder: false),
        source: 'https://drive.test/files/boda.mp4?view=1&play=low',
        isRemote: true,
      ),
    );
    final script = RegExp(r'<script>([\s\S]*)</script>')
        .firstMatch(html)
        ?.group(1);
    expect(script, isNotNull);
    final js = File('${dir.path}/no_total.mjs')
      ..writeAsStringSync('$_harnessHead\n$script\n$_lightNoTotalTail');
    final r = Process.runSync(node!, [js.path]);
    expect(r.exitCode, 0, reason: 'sin total: ${r.stdout}${r.stderr}');
    expect('${r.stdout}', contains('OK'));
  }, skip: node == null ? 'node no está instalado' : false);

  test('ejecutado de verdad: un fallo del reencodado cae al original', () {
    final dir = Directory.systemTemp.createTempSync('hs_fallback');
    addTearDown(() => dir.deleteSync(recursive: true));
    final html = debugDrivePlayerHtml(
      DriveViewTarget(
        item: const DriveItem(name: 'boda.mp4', isFolder: false),
        source: 'https://drive.test/files/boda.mp4?view=1&play=low',
        isRemote: true,
      ),
    );
    final script = RegExp(r'<script>([\s\S]*)</script>')
        .firstMatch(html)
        ?.group(1);
    expect(script, isNotNull);
    final js = File('${dir.path}/fallback.mjs')
      ..writeAsStringSync('$_harnessHead\n$script\n$_lightFailTail');
    final r = Process.runSync(node!, [js.path]);
    expect(r.exitCode, 0, reason: 'fallback: ${r.stdout}${r.stderr}');
    expect('${r.stdout}', contains('OK'));
  }, skip: node == null ? 'node no está instalado' : false);

  // Un vídeo GRANDE se pide reencodado (`?play=low`). Si el servidor no puede
  // reencodarlo (sin ffmpeg o con los reencodados ocupados) o el navegador no
  // acepta el MP4 fragmentado, el visor se quedaba en negro con "No se pudo
  // reproducir". Ahora reintenta con el archivo ORIGINAL una vez.
  test('si la calidad ligera falla, prueba el vídeo ORIGINAL', () {
    final html = debugDrivePlayerHtml(
      DriveViewTarget(
        item: const DriveItem(name: 'boda.mp4', isFolder: false),
        source: 'https://drive.test/files/boda.mp4?view=1&play=low',
        isRemote: true,
      ),
    );
    expect(html, contains('retriedOriginal'));
    expect(
      html,
      contains('fallbackSrc="https://drive.test/files/boda.mp4?view=1"'),
      reason: 'el plan B es la URL sin play=low (con el token intacto)',
    );
  });

  test('ejecutado de verdad: doble toque ±10 s y menú de velocidad', () {
    final dir = Directory.systemTemp.createTempSync('hs_taps');
    addTearDown(() => dir.deleteSync(recursive: true));
    final html = debugDrivePlayerHtml(target('boda.mp4'));
    final script = RegExp(r'<script>([\s\S]*)</script>')
        .firstMatch(html)
        ?.group(1);
    expect(script, isNotNull);
    final js = File('${dir.path}/taps.mjs')
      ..writeAsStringSync('$_harnessHead\n$script\n$_doubleTapTail');
    final r = Process.runSync(node!, [js.path]);
    expect(r.exitCode, 0, reason: 'taps: ${r.stdout}${r.stderr}');
    expect('${r.stdout}', contains('OK'));
  }, skip: node == null ? 'node no está instalado' : false);

  test('ejecutado de verdad: arranque automático (mudo si bloquean el sonido)', () {
    final dir = Directory.systemTemp.createTempSync('hs_autoplay');
    addTearDown(() => dir.deleteSync(recursive: true));
    final html = debugDrivePlayerHtml(target('boda.mp4'));
    final script = RegExp(r'<script>([\s\S]*)</script>')
        .firstMatch(html)
        ?.group(1);
    expect(script, isNotNull);
    final js = File('${dir.path}/autoplay.mjs')
      ..writeAsStringSync('$_harnessHead\n$script\n$_autoplayTail');
    final r = Process.runSync(node!, [js.path]);
    expect(r.exitCode, 0, reason: 'autoplay: ${r.stdout}${r.stderr}');
    expect('${r.stdout}', contains('OK'));
  }, skip: node == null ? 'node no está instalado' : false);

  test('ejecutado de verdad: la pantalla completa se pide al iframe o a la página', () {
    final dir = Directory.systemTemp.createTempSync('hs_fs');
    addTearDown(() => dir.deleteSync(recursive: true));
    final html = debugDrivePlayerHtml(target('boda.mp4'));
    final script = RegExp(r'<script>([\s\S]*)</script>')
        .firstMatch(html)
        ?.group(1);
    expect(script, isNotNull);
    final js = File('${dir.path}/fullscreen.mjs')
      ..writeAsStringSync('$_harnessHead\n$script\n$_fullscreenTail');
    final r = Process.runSync(node!, [js.path]);
    expect(r.exitCode, 0, reason: 'pantalla completa: ${r.stdout}${r.stderr}');
    expect('${r.stdout}', contains('OK'));
  }, skip: node == null ? 'node no está instalado' : false);

  test('el audio usa su tarjeta y el aviso correcto', () {
    final html = debugDrivePlayerHtml(target('tema.mp3'));
    expect(html, contains('<audio'));
    expect(html, contains('audio-card'));
    expect(html, contains('Cargando audio…'));
    expect(html, isNot(contains('<video')));
  });

  test('en la app el botón de pantalla completa llama al panel', () {
    final web = debugDrivePlayerHtml(target('boda.mp4'));
    // En el navegador manda la API de pantalla completa del navegador.
    expect(web, contains('var nativeShell=false'));
    expect(web, contains('requestFullscreen'));
    // El reproductor de la web vive en un IFRAME: la pantalla completa se
    // pide al iframe o a la página que lo contiene. Pedirla solo al elemento
    // de dentro no agrandaba nada (el botón "no hacía nada").
    expect(web, contains('window.frameElement'));
    expect(web, contains('function enterFs()'));
    expect(web, contains('parentDoc()'));
    // Y el botón cambia a "salir de pantalla completa".
    expect(web, contains('class="i-exit"'));
    expect(web, contains('#full.on .i-exit{display:block}'));

    // En la app (WebView de Windows/Android) esa API no existe o no la atiende
    // el anfitrión: se le pide al visor de Flutter que oculte sus barras.
    final app = debugDrivePlayerHtml(target('boda.mp4'), nativeShell: true);
    expect(app, contains('var nativeShell=true'));
    expect(app, contains('callHandler("hsPlayerFullscreen",'));
    // Viajan las medidas del vídeo: con ellas la app gira el TELÉFONO a
    // apaisado solo si el vídeo es horizontal.
    expect(app, contains('m.videoWidth||0,m.videoHeight||0'));
    // Y se avisan en cuanto el archivo las conoce (aunque la pantalla completa
    // se pida desde la barra del visor, no desde el reproductor).
    expect(app, contains('callHandler("hsPlayerMeta"'));
  });

  test('un PDF se muestra con el visor del navegador, no como vídeo', () {
    final html = debugDrivePlayerHtml(target('contrato.pdf'));
    expect(html, contains('<iframe'));
    expect(html, isNot(contains('<video')));
  });
}

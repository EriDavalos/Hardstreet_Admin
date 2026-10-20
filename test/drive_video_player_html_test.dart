import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_base.dart';
import 'package:hardstreet_admin/widgets/drive_media_viewer.dart';

// ==================================================================
// EL REPRODUCTOR DE VÍDEO DEL VISOR
// ==================================================================
// Se verifica el HTML que se inyecta en el navegador integrado: póster
// mientras carga, aviso de "Cargando…", controles nativos y que un PDF use el
// visor del navegador (iframe) en vez de un <video>.
// ==================================================================

DriveViewTarget target(String name, {String poster = ''}) => DriveViewTarget(
  item: DriveItem(name: name, isFolder: false),
  source: 'https://drive.test/files/$name?token=a&b=1',
  isRemote: true,
  poster: poster,
);

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
  test(
    'los scripts de vídeo y audio compilan sin errores de sintaxis',
    () {
      final dir = Directory.systemTemp.createTempSync('hs_player');
      addTearDown(() => dir.deleteSync(recursive: true));
      for (final (label, html) in [
        ('vídeo', debugDrivePlayerHtml(target('boda.mp4'))),
        ('audio', debugDrivePlayerHtml(target('tema.mp3'))),
      ]) {
        final script = RegExp(
          r'<script>([\s\S]*)</script>',
        ).firstMatch(html)?.group(1);
        expect(script, isNotNull, reason: 'falta el script del $label');
        final js = File('${dir.path}/$label.js')
          ..writeAsStringSync(script!);
        final r = Process.runSync(node!, ['--check', js.path]);
        expect(r.exitCode, 0, reason: 'script de $label: ${r.stderr}');
      }
    },
    skip: node == null ? 'node no está instalado' : false,
  );

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

    // En la app (WebView de Windows/Android) esa API no existe o no la atiende
    // el anfitrión: se le pide al visor de Flutter que oculte sus barras.
    final app = debugDrivePlayerHtml(target('boda.mp4'), nativeShell: true);
    expect(app, contains('var nativeShell=true'));
    expect(app, contains('callHandler("hsPlayerFullscreen")'));
  });

  test('un PDF se muestra con el visor del navegador, no como vídeo', () {
    final html = debugDrivePlayerHtml(target('contrato.pdf'));
    expect(html, contains('<iframe'));
    expect(html, isNot(contains('<video')));
  });
}

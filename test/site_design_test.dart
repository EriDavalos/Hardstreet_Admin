import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardstreet_admin/site_design.dart';
import 'package:hardstreet_admin/widgets/package_designer.dart';

// ==================================================================
// DISEÑO DEL SITIO — el panel y la web deben ver LO MISMO
// ==================================================================
// El diseñador del panel (Paquetes → Diseñar cards) escribe un documento y la
// web lo aplica al cargar (`Hardstreet/gallery/assets/site.js`). Si los dos
// lados se separan, el panel mostraría una cosa y la página otra: estas pruebas
// lo impiden.
//
//   1. Los DEFAULTS son idénticos en los dos archivos (se leen de site.js).
//   2. Si se agrega un campo al diseño, tiene que estar en los dos (la
//      comparación es por CLAVES, no solo por valores).
//   3. Utilidades de color y el propio diálogo del diseñador.
// ==================================================================

/// Ruta del diseño de la web, relativa a la raíz del panel Flutter.
const String _siteJsPath = '../Hardstreet/gallery/assets/site.js';

/// ¿Existe la web junto al panel? (si el panel se compila solo, se salta).
bool get _webAvailable => File(_siteJsPath).existsSync();

/// Extrae y decodifica `const SITE_DESIGN_DEFAULT = { … };` de site.js.
///
/// Se recorta contando llaves (los valores del diseño no llevan llaves dentro)
/// y se adapta el literal de JavaScript a JSON: comillas simples, claves sin
/// comillas y comas finales.
Map<String, dynamic> readWebDesignDefaults() {
  final text = File(_siteJsPath).readAsStringSync();
  final marker = text.indexOf('SITE_DESIGN_DEFAULT = {');
  expect(marker, greaterThanOrEqualTo(0),
      reason: 'site.js debería declarar SITE_DESIGN_DEFAULT');
  final start = text.indexOf('{', marker);
  var depth = 0;
  var end = -1;
  for (var i = start; i < text.length; i++) {
    final ch = text[i];
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) {
        end = i + 1;
        break;
      }
    }
  }
  expect(end, greaterThan(0), reason: 'El objeto de defaults quedó sin cerrar');

  // Literal de JS → JSON. (En Dart la sustitución de grupos de una expresión
  // regular se hace con replaceAllMapped, no con `$1`.)
  var js = text.substring(start, end);
  // Comentarios de línea, por si el objeto se comenta en el futuro.
  js = js.replaceAllMapped(RegExp(r'//[^\n]*'), (_) => '');
  // Comas finales: válidas en JS, ilegales en JSON (en el diseño no hay
  // arreglos, así que basta con las que quedan justo antes de cerrar).
  js = js.replaceAllMapped(RegExp(r',\s*}'), (_) => '}');
  // El diseño se escribe con comillas simples…
  js = js.replaceAll("'", '"');
  // …y con claves sin comillas.
  js = js.replaceAllMapped(RegExp(r'(\w+)\s*:'), (m) => '"${m[1]}":');
  return (jsonDecode(js) as Map).cast<String, dynamic>();
}

/// Abre el diseñador en una pantalla del tamaño pedido (en pantallas anchas el
/// diálogo enseña controles y vista previa a la vez) y deja el diseño elegido
/// en [onSaved].
Future<void> _pumpDesigner(
  WidgetTester tester, {
  Size size = const Size(1300, 950),
  void Function(SiteDesign?)? onSaved,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: ElevatedButton(
          onPressed: () async {
            final d = await showPackageDesigner(ctx,
                design: SiteDesign.defaults);
            onSaved?.call(d);
          },
          child: const Text('abrir'),
        ),
      ),
    ),
  ));
}

/// Baja por los controles hasta que el widget exista (el ListView es perezoso:
/// lo que queda fuera de pantalla no está construido).
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    140,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('defaults del diseño (panel ⇄ web)', () {
    test('los defaults del panel son EXACTAMENTE los de la web', () {
      if (!_webAvailable) {
        markTestSkipped('La web no está junto al panel: $_siteJsPath');
        return;
      }
      final web = readWebDesignDefaults();
      final panel = SiteDesign.defaults.toJson();

      // Mismas CLAVES (si alguien agrega un campo en un lado, falla aquí).
      expect((web['card'] as Map).keys.toSet(),
          (panel['card'] as Map).keys.toSet(),
          reason: 'El diseño de tarjetas tiene campos distintos en cada lado');
      expect((web['tiers'] as Map).keys.toSet(),
          (panel['tiers'] as Map).keys.toSet());
      for (final key in (web['tiers'] as Map).keys) {
        expect(((web['tiers'] as Map)[key] as Map).keys.toSet(),
            ((panel['tiers'] as Map)[key] as Map).keys.toSet(),
            reason: 'El tier "$key" tiene campos distintos en cada lado');
      }

      // Y mismos VALORES.
      expect(web['card'], panel['card']);
      expect(web['tiers'], panel['tiers']);
      expect((web['brand'] as Map)['gold'], (panel['brand'] as Map)['gold']);
      expect((web['brand'] as Map)['goldLight'],
          (panel['brand'] as Map)['goldLight']);
    });

    test('los tiers del diseño son los que usa la web', () {
      if (!_webAvailable) {
        markTestSkipped('La web no está junto al panel: $_siteJsPath');
        return;
      }
      final web = readWebDesignDefaults();
      final tierKeys = ((web['tiers'] as Map).keys.cast<String>()).toSet();
      expect(tierKeys, SiteDesign.defaults.tiers.keys.toSet());
      expect(tierKeys, containsAll(kTierLabels.keys));
    });
  });

  group('colores', () {
    test('hex ⇄ Color (con y sin #, corto y largo)', () {
      expect(hsColorHex(hsHexColor('#C9A96E')), '#C9A96E');
      expect(hsColorHex(hsHexColor('c9a96e')), '#C9A96E');
      expect(hsColorHex(hsHexColor('#FFF')), '#FFFFFF');
    });

    test('un valor inválido no rompe: cae al respaldo', () {
      expect(hsHexColor('#zzzzzz', Colors.grey), Colors.grey);
      expect(hsHexColor('', Colors.grey), Colors.grey);
      expect(hsHexColor('no-es-color', Colors.grey), Colors.grey);
    });
  });

  group('lectura tolerante del diseño guardado', () {
    test('texto JSON válido', () {
      final d = SiteDesign.fromJsonText(jsonEncode({
        'brand': {'gold': '#123456'},
        'card': {'radius': 4, 'showPrice': false, 'priceLabel': 'Inversión'},
        'tiers': {
          'premium': {'accent': '#111111', 'badgeFilled': false},
        },
      }));
      expect(d.gold, '#123456');
      expect(d.card.radius, 4);
      expect(d.card.showPrice, isFalse);
      expect(d.card.priceLabel, 'Inversión');
      expect(d.tierOf('Premium').accent, '#111111');
      expect(d.tierOf('Premium').badgeFilled, isFalse);
      // Lo que no venía, se queda con el default (nunca queda a medias).
      expect(d.goldLight, SiteDesign.defaults.goldLight);
      expect(d.card.columns, SiteDesign.defaults.card.columns);
    });

    test('basura, null o vacío → defaults', () {
      expect(SiteDesign.fromJsonText(null).card.columns,
          SiteDesign.defaults.card.columns);
      expect(SiteDesign.fromJsonText('{no es json').card.radius,
          SiteDesign.defaults.card.radius);
      expect(SiteDesign.fromJsonText('[1,2,3]').card.radius,
          SiteDesign.defaults.card.radius);
    });

    test('el ida y vuelta por JSON no pierde nada', () {
      final json = SiteDesign.defaults.toJson();
      expect(SiteDesign.fromJson(json).toJson(), json);
    });
  });

  group('diseñador de tarjetas', () {
    testWidgets('abre, deja editar la paleta de un tier y devuelve el diseño',
        (tester) async {
      SiteDesign? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showPackageDesigner(ctx,
                    design: SiteDesign.defaults);
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Diseñador de tarjetas'), findsOneWidget);

      // En pantalla angosta el diálogo se divide en pestañas: la vista previa
      // enseña la tarjeta tal como quedará en la web.
      await tester.tap(find.text('Vista previa'));
      await tester.pumpAndSettle();
      expect(find.text('Así se verá en la web'), findsOneWidget);
      await tester.tap(find.text('Diseño'));
      await tester.pumpAndSettle();

      // Pestaña de un tier: el badge del Gold arranca relleno y se apaga.
      expect(SiteDesign.defaults.tierOf('gold').badgeFilled, isTrue);
      await tester.tap(find.byKey(const ValueKey('design-tab-gold')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Badge relleno (degradado)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar diseño'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.tierOf('gold').badgeFilled, isFalse);
      // Y lo que no se tocó sigue igual.
      expect(result!.tierOf('premium').badgeFilled, isTrue);
      expect(result!.card, SiteDesign.defaults.card);
    });

    testWidgets(
        'la vista previa (card y fila) enseña el tier que se está ajustando',
        (tester) async {
      await _pumpDesigner(tester, size: const Size(1300, 950));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      // De entrada la muestra va en Premium, en la CARD y en la FILA…
      expect(find.text('PREMIUM'), findsOneWidget);
      expect(find.text('Boda Full'), findsNWidgets(2));
      // …y al abrir la pestaña de Gold, la CARD y la FILA se pintan con Gold
      // (antes la fila salía siempre en Gold y la tarjeta siempre en Premium).
      await tester.tap(find.byKey(const ValueKey('design-tab-gold')));
      await tester.pumpAndSettle();
      expect(find.text('PREMIUM'), findsNothing);
      expect(find.text('GOLD'), findsOneWidget);
      expect(find.text('XV Años Gold'), findsNWidgets(2));

      // Y se puede mirar otro tier sin dejar de ajustar el que se edita.
      await tester.tap(find.byKey(const ValueKey('design-preview-tier-basic')));
      await tester.pumpAndSettle();
      expect(find.text('BASIC'), findsOneWidget);
      expect(find.text('Sesión Básica'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('la foto y la animación elegidas se ven y se guardan',
        (tester) async {
      SiteDesign? result;
      await _pumpDesigner(
        tester,
        size: const Size(1300, 950),
        onSaved: (d) => result = d,
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      // Sin foto no hay hueco de foto en la vista previa.
      expect(find.text('Foto del paquete'), findsNothing);

      // Banda arriba: la foto aparece en la tarjeta (y su alto se ajusta).
      await _scrollTo(tester, find.byKey(const ValueKey('design-image-top')));
      await tester.tap(find.byKey(const ValueKey('design-image-top')));
      await tester.pumpAndSettle();
      expect(find.text('Foto del paquete'), findsOneWidget);
      expect(find.text('Alto de la banda'), findsOneWidget);

      // Animación: zoom, y se puede repetir desde la vista previa.
      await _scrollTo(tester, find.byKey(const ValueKey('design-anim-zoom')));
      await tester.tap(find.byKey(const ValueKey('design-anim-zoom')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Repetir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar diseño'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.card.imageMode, 'top');
      expect(result!.card.animMode, 'zoom');
      // Lo que no se tocó sigue con su valor de siempre.
      expect(result!.card.animStagger, SiteDesign.defaults.card.animStagger);
    });

    testWidgets('el degradado de la foto se personaliza (color y dirección)',
        (tester) async {
      SiteDesign? result;
      await _pumpDesigner(
        tester,
        size: const Size(1300, 950),
        onSaved: (d) => result = d,
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      // Los controles del velo salen cuando la foto va DE FONDO.
      await _scrollTo(tester, find.byKey(const ValueKey('design-image-bg')));
      await tester.tap(find.byKey(const ValueKey('design-image-bg')));
      await tester.pumpAndSettle();

      // Dirección: con el CÍRCULO (la rosa de flechas ya no existe).
      final dial = find.byKey(const ValueKey('design-fade-angle'));
      await _scrollTo(tester, dial);
      final c = tester.getCenter(dial);
      await tester.dragFrom(c + const Offset(0, -50), const Offset(0, 50));
      await tester.pumpAndSettle();

      // Color del velo: una muestra de un toque.
      await _scrollTo(
        tester,
        find.byKey(const ValueKey(r'design-fade-color-#1B2A4A')),
      );
      await tester.tap(
        find.byKey(const ValueKey(r'design-fade-color-#1B2A4A')),
      );
      await tester.pumpAndSettle();
      // Y la vista previa del degradado está a la vista.
      expect(
        find.byKey(const ValueKey('design-fade-preview')),
        findsOneWidget,
      );

      await tester.tap(find.text('Guardar diseño'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.card.imageMode, 'bg');
      expect(result!.card.imageFadeColor, '#1B2A4A');
      // El círculo fijó una dirección propia (0..359, ya no -1).
      expect(result!.card.imageFadeAngle, inInclusiveRange(0, 359));
      // Lo que no se tocó sigue igual.
      expect(result!.card.imageFade, SiteDesign.defaults.card.imageFade);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la dirección del velo se fija con el CÍRCULO de grados', (
      tester,
    ) async {
      SiteDesign? result;
      await _pumpDesigner(
        tester,
        size: const Size(1300, 950),
        onSaved: (d) => result = d,
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      // Los controles del velo salen con la foto DE FONDO.
      await _scrollTo(tester, find.byKey(const ValueKey('design-image-bg')));
      await tester.tap(find.byKey(const ValueKey('design-image-bg')));
      await tester.pumpAndSettle();

      // La rosa de flechas se retiró: la dirección se fija SOLO con el
      // círculo (era el mismo ajuste dos veces).
      expect(
        find.byKey(const ValueKey('design-fade-from-top')),
        findsNothing,
        reason: 'los botones de dirección ya no están',
      );

      final angle = find.byKey(const ValueKey('design-fade-angle'));
      await _scrollTo(tester, angle);
      // En el preset «arriba» (0°) el punto está arriba del círculo: se
      // arrastra hacia la derecha para poner ~90°.
      final center = tester.getCenter(angle);
      await tester.dragFrom(center + const Offset(0, -50), const Offset(50, 0));
      await tester.pumpAndSettle();
      // El círculo DICE los grados: ya no es un slider a ciegas.
      expect(
        find.textContaining('°'),
        findsWidgets,
        reason: 'el dial muestra el ángulo en el centro',
      );

      await tester.tap(find.text('Guardar diseño'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      // El círculo movió el ángulo: manda sobre la dirección guardada.
      expect(result!.card.imageFadeAngle, isNot(-1));
      expect(
        result!.card.imageFadeAngle,
        inInclusiveRange(0, 359),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('las paradas del desvanecido se ARRASTRAN sobre la tarjeta',
        (tester) async {
      SiteDesign? result;
      await _pumpDesigner(tester, onSaved: (d) => result = d);
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      // Con la foto de fondo aparece la sombra y, encima de la tarjeta, sus dos
      // asas (antes solo se podía con los sliders).
      await _scrollTo(tester, find.byKey(const ValueKey('design-image-bg')));
      await tester.tap(find.byKey(const ValueKey('design-image-bg')));
      await tester.pumpAndSettle();

      final fin = find.byKey(const ValueKey('design-shadow-end'));
      await _scrollTo(tester, fin);
      expect(fin, findsOneWidget);

      // Arrastrar hacia ARRIBA estira el degradado (la parada de fin sube).
      await tester.drag(fin, const Offset(0, -40));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar diseño'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(
        result!.card.imageShadowEnd,
        greaterThan(const SiteCardDesign().imageShadowEnd),
        reason: 'la parada movida a mano llega al diseño',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('los campos de color abren la PALETA y aplican lo elegido', (
      tester,
    ) async {
      SiteDesign? result;
      await _pumpDesigner(tester, onSaved: (d) => result = d);
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      // Tocar la muestra del color "Dorado" abre la paleta (antes el cuadrito
      // no se podía tocar y no salía ninguna paleta).
      final swatch = find.byKey(
        const ValueKey('design-color-swatch-Dorado'),
      );
      await _scrollTo(tester, swatch);
      await tester.tap(swatch);
      await tester.pumpAndSettle();
      expect(find.text('Muestras'), findsOneWidget);

      // Un toque en una muestra de la paleta la elige.
      await tester.tap(find.byKey(const ValueKey('design-palette-#EF4444')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar diseño'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.gold.toUpperCase(), '#EF4444');
      expect(tester.takeException(), isNull);
    });

    test('la sombra de la foto se guarda y se lee acotada (0..1)', () {
      const base = SiteCardDesign();
      // De fábrica SÍ hay sombra (es el desvanecido negro de la foto), con sus
      // dos paradas: dónde empieza y dónde se apaga.
      expect(base.imageShadow, .55);
      expect(base.imageShadowStart, .08);
      expect(base.imageShadowEnd, .72);
      final conSombra = SiteDesign.defaults.copyWith(
        card: base.copyWith(
          imageMode: 'bg',
          imageShadow: .45,
          imageFadeAngle: 200,
        ),
      );
      final vuelta = SiteDesign.fromJsonText(
        jsonEncode(conSombra.toJson()),
      );
      expect(vuelta.card.imageShadow, .45);
      // Un valor absurdo se acota, no revienta la tarjeta.
      final raro = SiteDesign.fromJsonText(
        jsonEncode({
          'card': {
            'imageShadow': 7.5,
            'imageShadowStart': .2,
            'imageShadowEnd': .9,
          },
        }),
      );
      expect(raro.card.imageShadow, 1);
    });

    test('un diseño guardado ANTES de la sombra la estrena con los defaults',
        () {
      // Guardado con la versión vieja (sin las paradas): el degradado negro se
      // enciende solo, en vez de quedarse apagado para siempre.
      final viejo = SiteDesign.fromJsonText(
        jsonEncode({
          'card': {'imageMode': 'bg', 'imageShadow': 0},
        }),
      );
      expect(viejo.card.imageShadow, SiteCardDesign().imageShadow);
      expect(viejo.card.imageShadowStart, SiteCardDesign().imageShadowStart);
      // Pero un 0 GUARDADO a propósito (con sus paradas) se respeta.
      final apagada = SiteDesign.fromJsonText(
        jsonEncode({
          'card': {
            'imageShadow': 0,
            'imageShadowStart': .08,
            'imageShadowEnd': .72,
          },
        }),
      );
      expect(apagada.card.imageShadow, 0);
    });

    test('el velo guardado se lee tolerante (color raro → default)', () {
      final d = SiteDesign.fromJsonText(jsonEncode({
        'card': {'imageFadeColor': 'no-es-color', 'imageFadeFrom': 'lateral'},
      }));
      expect(d.card.imageFadeColor, SiteDesign.defaults.card.imageFadeColor);
      expect(d.card.imageFadeFrom, SiteDesign.defaults.card.imageFadeFrom);
      // Direcciones nuevas (las 8) y ángulo: se leen y se normalizan.
      final nuevo = SiteDesign.fromJsonText(jsonEncode({
        'card': {
          'imageFadeFrom': 'topLeft',
          'imageFadeAngle': 400,
        },
      }));
      expect(nuevo.card.imageFadeFrom, 'topLeft');
      expect(nuevo.card.imageFadeAngle, 40); // 400 % 360
      final libre = SiteDesign.fromJsonText(jsonEncode({
        'card': {'imageFadeAngle': -1},
      }));
      expect(libre.card.imageFadeAngle, -1); // sigue a la dirección
      expect(
        SiteDesign.fromJsonText(
          jsonEncode({
            'card': {'imageFadeColor': '#1b2a4a', 'imageFadeFrom': 'top'},
          }),
        ).card.imageFadeColor,
        '#1B2A4A',
      );
    });

    test('el fondo con degradado se guarda y se lee acotado', () {
      const base = SiteCardDesign();
      expect(base.imageFadeStart, .15);
      expect(base.imageFadeEnd, .85);
      expect(base.cardBgFrom, kCardBgFrom);
      expect(base.cardBgTo, kCardBgTo);
      expect(base.cardBgGradient, isFalse);
      expect(base.cardBgAngle, 135);

      final d = SiteDesign.defaults.copyWith(
        card: base.copyWith(
          imageMode: 'fade',
          imageFadeStart: .3,
          imageFadeEnd: .75,
          cardBgFrom: '#123456',
          cardBgTo: '#654321',
          cardBgGradient: true,
          cardBgAngle: 400,
        ),
      );
      final vuelta = SiteDesign.fromJsonText(jsonEncode(d.toJson()));
      expect(vuelta.card.imageMode, 'fade');
      expect(vuelta.card.imageFadeStart, .3);
      expect(vuelta.card.imageFadeEnd, .75);
      expect(vuelta.card.cardBgFrom, '#123456');
      expect(vuelta.card.cardBgGradient, isTrue);
      expect(vuelta.card.cardBgAngle, 40); // 400 % 360

      // Valores absurdos: se acotan y el fin nunca queda antes que el inicio.
      final raro = SiteDesign.fromJsonText(jsonEncode({
        'card': {
          'imageMode': 'fade',
          'imageFadeStart': 1.4,
          'imageFadeEnd': -2,
          'cardBgAngle': -30,
          'cardBgFrom': 'no-es-color',
        },
      }));
      expect(raro.card.imageFadeStart, .95);
      expect(raro.card.imageFadeEnd, 1);
      expect(raro.card.cardBgAngle, 135);
      expect(raro.card.cardBgFrom, kCardBgFrom);
    });

    test('un modo de foto o de animación desconocido cae al default', () {
      final d = SiteDesign.fromJsonText(jsonEncode({
        'card': {'imageMode': 'flotando', 'animMode': 'explotar', 'animMs': 'raro'},
      }));
      expect(d.card.imageMode, SiteDesign.defaults.card.imageMode);
      expect(d.card.animMode, SiteDesign.defaults.card.animMode);
      expect(d.card.animMs, SiteDesign.defaults.card.animMs);
    });

    testWidgets('el fondo con degradado se ajusta y se guarda', (tester) async {
      SiteDesign? result;
      await _pumpDesigner(tester, onSaved: (d) => result = d);
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      // El estilo nuevo está entre las opciones de la foto.
      final chip = find.byKey(const ValueKey('design-image-fade'));
      await _scrollTo(tester, chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();

      // Encima de la tarjeta salen las DOS asas del desvanecido (se ve /
      // desaparece), como las de la sombra.
      final fin = find.byKey(const ValueKey('design-fade-end'));
      await _scrollTo(tester, fin);
      expect(fin, findsOneWidget);
      expect(
        find.byKey(const ValueKey('design-fade-start')),
        findsOneWidget,
      );

      // El fondo se puede poner en degradado: aparece el segundo color.
      final fondo = find.text('Fondo en degradado');
      await _scrollTo(tester, fondo);
      await tester.tap(fondo);
      await tester.pumpAndSettle();
      expect(find.text('Fondo (color 2)'), findsOneWidget);

      // Arrastrar el asa de «desaparece» hacia arriba estira el desvanecido.
      await _scrollTo(tester, fin);
      await tester.drag(fin, const Offset(0, -40));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar diseño'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.card.imageMode, 'fade');
      expect(result!.card.cardBgGradient, isTrue);
      expect(
        result!.card.imageFadeEnd,
        greaterThan(const SiteCardDesign().imageFadeEnd),
        reason: 'la parada movida a mano llega al diseño',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancelar no devuelve diseño (no se guarda nada)',
        (tester) async {
      SiteDesign? result;
      var closed = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showPackageDesigner(ctx,
                    design: SiteDesign.defaults);
                closed = true;
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(result, isNull);
    });
  });
}

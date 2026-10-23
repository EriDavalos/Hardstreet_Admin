import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/hs_access.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';
import 'package:hardstreet_admin/theme.dart';

/// PNG 1x1 válido: los archivos del drive se decodifican de verdad.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/'
  'q842iQAAAABJRU5ErkJggg==',
);

/// Permisos del módulo Archivos que devuelve el backend falso.
void _installMock(List<String> actions) {
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    if (request.url.path.endsWith('/api/admin/permission')) {
      return http.Response(
        jsonEncode({
          'isAdmin': false,
          'modules': [
            {
              'key': 'drive',
              'name': 'Archivos',
              'order': 3,
              'actions': actions,
            },
          ],
        }),
        200,
        headers: headers,
      );
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 60)),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

/// Abre el Drive en un TELÉFONO (390 × 844) con [files] fotos y una carpeta.
Future<void> _pumpPhone(
  WidgetTester tester, {
  List<String> actions = const ['read', 'create', 'update', 'delete'],
  ThemeData? theme,
}) async {
  late Directory tmp;
  await tester.runAsync(() async {
    tmp = await Directory.systemTemp.createTemp('hardstreet_drive_phone');
  });
  for (var i = 0; i < 24; i++) {
    File('${tmp.path}/foto_${i.toString().padLeft(2, '0')}.png')
        .writeAsBytesSync(_png);
  }
  Directory('${tmp.path}/Bodas').createSync();
  // La carpeta también tiene contenido: así se puede hacer scroll DENTRO de
  // ella (para comprobar que la ruta se queda fija arriba).
  for (var i = 0; i < 24; i++) {
    File('${tmp.path}/Bodas/boda_${i.toString().padLeft(2, '0')}.png')
        .writeAsBytesSync(_png);
  }
  // Camino largo (para comprobar que la ruta se acorta con «…»).
  Directory('${tmp.path}/Bodas/Sesion/Previa').createSync(recursive: true);

  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final previous = HsApi.client;
  _installMock(actions);
  addTearDown(() {
    HsApi.client = previous;
    HsAccess.reset();
  });
  HsAccess.reset();
  await HsAccess.load();

  final drive = DriveService.testRoot(tmp);
  await tester.pumpWidget(
    MaterialApp(theme: theme, home: Scaffold(body: DrivePage(drive: drive))),
  );
  await _settle(tester);
  addTearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });
}

void main() {
  testWidgets('en celular el encabezado del módulo se va con el scroll', (
    tester,
  ) async {
    await _pumpPhone(tester);

    // El encabezado (título + búsqueda) está DENTRO del mismo scroll.
    final search = find.text('Buscar en esta carpeta');
    expect(search, findsOneWidget);
    final before = tester.getTopLeft(search).dy;

    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -260));
    await tester.pump(const Duration(milliseconds: 400));

    final after = tester.getTopLeft(search).dy;
    expect(
      after,
      lessThan(before - 100),
      reason: 'la tarjeta del módulo sube con el contenido',
    );
    // Y las fotos siguen ahí (la cuadrícula no se fue).
    expect(find.text('foto_00.png'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en celular el botón de crear es FIJO y tiene las dos opciones', (
    tester,
  ) async {
    await _pumpPhone(tester);

    // Solo el icono (sin texto): se identifica por su tooltip.
    final fab = find.byTooltip('Agregar');
    expect(fab, findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);

    // Al bajar sigue a la vista (no viaja con el encabezado).
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('Agregar'), findsOneWidget);

    await tester.tap(find.byTooltip('Agregar'));
    // Se usan pumps acotados: el módulo tiene animaciones decorativas que no
    // se detienen, así que `pumpAndSettle` nunca regresa.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Nueva carpeta'), findsWidgets);
    expect(find.text('Subir archivos'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el botón fijo es circular, sin contorno y con ripple redondo', (
    tester,
  ) async {
    await _pumpPhone(tester);

    final fab = find.byTooltip('Agregar');
    final material = tester.widget<Material>(
      find.descendant(of: fab, matching: find.byType(Material)),
    );
    expect(material.shape, isA<CircleBorder>());
    expect(
      material.clipBehavior,
      isNot(Clip.none),
      reason: 'sin recorte el resaltado se veía cuadrado',
    );

    final box =
        tester.widget<DecoratedBox>(
          find.descendant(of: fab, matching: find.byType(DecoratedBox)).first,
        ).decoration as BoxDecoration;
    expect(box.shape, BoxShape.circle);
    expect(box.border, isNull, reason: 'el botón ya no lleva contorno');
  });

  testWidgets('sin permiso de crear no hay botón fijo', (tester) async {
    await _pumpPhone(tester, actions: const ['read']);
    expect(find.byTooltip('Agregar'), findsNothing);
  });

  testWidgets('en celular la ruta de la RAÍZ se PEGA arriba al bajar', (
    tester,
  ) async {
    await _pumpPhone(tester);

    // En la raíz la miga tiene su propia barra, dentro del scroll.
    final bar = find.byKey(const ValueKey('drive-crumbs'));
    expect(bar, findsOneWidget);
    final crumb = find.descendant(of: bar, matching: find.text('Mi Drive'));
    expect(crumb, findsOneWidget);
    final crumbY = tester.getTopLeft(crumb).dy;
    expect(crumbY, greaterThan(0), reason: 'en su sitio, bajo el encabezado');

    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -400),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 400));

    // La tarjeta del módulo se fue con el scroll (ya ni se construye) y la
    // miga quedó FIJA arriba.
    expect(
      find.text('Buscar en esta carpeta'),
      findsNothing,
      reason: 'el encabezado del módulo sí se va con el scroll',
    );
    final pinnedY = tester.getTopLeft(
      find.descendant(
        of: find.byKey(const ValueKey('drive-crumbs')),
        matching: find.text('Mi Drive'),
      ),
    ).dy;
    expect(pinnedY, lessThan(crumbY), reason: 'la barra subió a pegarse');
    expect(pinnedY, inInclusiveRange(0, 80), reason: 'sigue a la vista, arriba');
    expect(tester.takeException(), isNull);
  });

  // La barra de ruta NO debe verse como una franja: su fondo tiene que ser el
  // MISMO de la página (antes usaba `surface`, otro tono) y no puede dibujar
  // contorno ni sombra propios —eso era la "línea de separación" de arriba.
  testWidgets('la barra de ruta se funde con el fondo y no dibuja líneas', (
    tester,
  ) async {
    final theme = AppTheme.light();
    await _pumpPhone(tester, theme: theme);

    final bar = find.byKey(const ValueKey('drive-crumbs'));
    final page = theme.scaffoldBackgroundColor;
    expect(
      page,
      isNot(theme.colorScheme.surface),
      reason: 'la prueba solo vale si el tema distingue página y superficie',
    );

    final fondos = tester
        .widgetList<ColoredBox>(
          find.ancestor(of: bar, matching: find.byType(ColoredBox)),
        )
        .map((b) => b.color)
        .toList();
    expect(fondos, contains(page), reason: 'el fondo es el de la página');
    expect(
      fondos,
      isNot(contains(theme.colorScheme.surface)),
      reason: 'con otro tono se veía la franja',
    );

    // Sin elevación, sin tinte y sin borde: la barra no pinta ningún filo.
    final material = tester.widget<Material>(
      find.ancestor(of: bar, matching: find.byType(Material)).first,
    );
    expect(material.type, MaterialType.transparency);
    expect(material.elevation, 0);
    final bordes = tester
        .widgetList<DecoratedBox>(
          find.ancestor(of: bar, matching: find.byType(DecoratedBox)),
        )
        .map((b) => b.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.border != null)
        .toList();
    expect(bordes, isEmpty, reason: 'ningún contorno en la barra de ruta');
    expect(tester.takeException(), isNull);
  });

  testWidgets('la barra de ruta resalta la carpeta al pasar el ratón', (
    tester,
  ) async {
    await _pumpPhone(tester);

    // La barra se pinta sobre un Material: ahí es donde el InkWell dibuja el
    // resaltado del ratón (antes iba sobre un `Container` opaco, así que la
    // tinta quedaba tapada y al pasar el ratón no se veía nada).
    final bar = find.byKey(const ValueKey('drive-crumbs'));
    expect(
      find.ancestor(of: bar, matching: find.byType(Material)),
      findsWidgets,
    );
    final crumb = find
        .ancestor(of: find.text('Mi Drive'), matching: find.byType(InkWell))
        .first;
    final ink = tester.widget<InkWell>(crumb);
    expect(
      ink.hoverColor,
      isNotNull,
      reason: 'las migas tienen que destacarse al pasar el ratón',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('en celular, dentro de una carpeta la ruta también se pega', (
    tester,
  ) async {
    await _pumpPhone(tester);

    await tester.tap(find.text('Bodas'));
    await _settle(tester);
    // La vista anterior se desvanece (AnimatedSwitcher): se deja terminar.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final crumbs = find.byKey(const ValueKey('drive-crumbs'));
    expect(crumbs, findsOneWidget);
    final crumbY = tester.getTopLeft(
      find.descendant(of: crumbs, matching: find.text('Mi Drive')),
    ).dy;

    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -260),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 400));

    // Al bajar, la ruta se queda pegada arriba (antes se perdía con el
    // encabezado y ya no se podía volver a la carpeta padre).
    final after = find.descendant(
      of: find.byKey(const ValueKey('drive-crumbs')),
      matching: find.text('Mi Drive'),
    );
    expect(after, findsOneWidget);
    expect(
      tester.getTopLeft(after).dy,
      lessThan(crumbY),
      reason: 'la ruta sube a pegarse arriba, no se oculta',
    );
    expect(
      tester.getTopLeft(after).dy,
      inInclusiveRange(0, 80),
      reason: 'la barra queda fija arriba de la pantalla',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ruta larga: se acorta con «…» y las dos últimas carpetas', (
    tester,
  ) async {
    await _pumpPhone(tester);

    Future<void> openFolder(String name) async {
      await tester.tap(find.text(name));
      await _settle(tester);
      // La vista anterior se desvanece (AnimatedSwitcher): se deja terminar.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }

    await openFolder('Bodas');
    await openFolder('Sesion');
    await openFolder('Previa');

    final crumbs = find.byKey(const ValueKey('drive-crumbs'));
    expect(crumbs, findsOneWidget);
    expect(
      find.descendant(of: crumbs, matching: find.text('Mi Drive')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: crumbs, matching: find.text('…')),
      findsOneWidget,
      reason: 'las carpetas de en medio se resumen',
    );
    expect(
      find.descendant(of: crumbs, matching: find.text('Sesion')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: crumbs, matching: find.text('Previa')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: crumbs, matching: find.text('Bodas')),
      findsNothing,
      reason: 'con el camino largo la primera carpeta ya no se lista',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('en celular la tarjeta del título ya no tiene "Nueva carpeta"', (
    tester,
  ) async {
    await _pumpPhone(tester);

    // El botón de crear del título de la tarjeta desapareció: la creación vive
    // en el botón fijo. (La hoja del botón se abre con su propio texto.)
    expect(find.byTooltip('Nueva carpeta'), findsNothing);
    expect(find.text('Nueva carpeta'), findsNothing);
  });

  testWidgets('en celular la cuadrícula va a DOS columnas', (tester) async {
    await _pumpPhone(tester);
    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    // Dos columnas: la tarjeta es casi cuadrada y la miniatura se aprecia
    // (con tres quedaba angosta).
    expect(delegate.crossAxisCount, 2);
    expect(delegate.childAspectRatio, lessThan(1));
  });

  testWidgets(
    'en celular la vista de lista no lleva la línea suelta del encabezado',
    (tester) async {
      await _pumpPhone(tester);

      await tester.tap(find.byTooltip('Vista de lista'));
      await tester.pump(const Duration(milliseconds: 400));

      // Cada fila es su propia tarjeta: no hay Divider pegado al encabezado
      // (esa era la línea que se veía justo arriba del listado).
      expect(find.byType(Divider), findsNothing);
      expect(find.text('foto_00.png'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}

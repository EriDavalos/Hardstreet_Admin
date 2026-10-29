// ==================================================================
// BOTÓN ATRÁS (una sola cadena)
// ==================================================================
// Bug reportado: en la WEB el atrás del navegador sacaba de la app aunque
// estuvieras dentro de una carpeta, y en cualquier plataforma no volvía al
// módulo de inicio ni preguntaba antes de salir.
//
// Aquí se comprueba la cadena completa, con el MISMO mensaje que mandan Android
// y el motor web al pulsar atrás (`popRoute`): deseleccionar → carpeta padre →
// sub-vista → módulo de inicio → «¿Salir?».
// ==================================================================
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/back_nav.dart';
import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/hs_access.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';
import 'package:hardstreet_admin/theme.dart';

/// PNG 1x1 válido: las fotos del drive se decodifican de verdad.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/'
  'q842iQAAAABJRU5ErkJggg==',
);

/// Permisos del módulo Archivos que devuelve el backend falso.
void _installMock() {
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
              'actions': const ['read', 'create', 'update', 'delete'],
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

/// El MISMO mensaje que manda Android (y el motor web) al pulsar ATRÁS.
/// Devuelve si ALGUIEN lo atendió: en la web, un `false` es lo que hace que la
/// app se cierre.
Future<bool> _pressBack(WidgetTester tester) async {
  bool handled = false;
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (data) {
      if (data == null) return;
      handled = const JSONMethodCodec().decodeEnvelope(data) == true;
    },
  );
  await _settle(tester);
  return handled;
}

/// Monta el Drive como lo hace el panel: un `PopScope` raíz que NUNCA deja
/// salir por su cuenta y que entrega el gesto a la cadena ([BackNav]).
Future<DriveService> _pumpDrive(
  WidgetTester tester, {
  VoidCallback? onBack,
  bool rootPopScope = true,
}) async {
  late Directory tmp;
  await tester.runAsync(() async {
    tmp = await Directory.systemTemp.createTemp('hardstreet_back_nav');
  });
  addTearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });
  File('${tmp.path}/foto_00.png').writeAsBytesSync(_png);
  File('${tmp.path}/foto_01.png').writeAsBytesSync(_png);
  Directory('${tmp.path}/Bodas').createSync();
  File('${tmp.path}/Bodas/boda_00.png').writeAsBytesSync(_png);

  final drive = DriveService.testRoot(tmp);
  // TELÉFONO: el ancho lo lee MediaQuery de la vista (no del surface).
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final page = Scaffold(
    body: DrivePage(drive: drive, onBack: onBack),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: rootPopScope
          ? PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                BackNav.handle();
              },
              child: page,
            )
          // SIN el `PopScope` raíz: es el estado que dejaba el atrás sin
          // atender (y la app se cerraba). Lo cubre el guardia.
          : page,
    ),
  );
  await _settle(tester);
  return drive;
}

void main() {
  setUp(() {
    BackNav.resetForTest();
    HsAccess.reset();
  });
  tearDown(() {
    BackNav.resetForTest();
    HsAccess.reset();
  });

  group('cadena del atrás', () {
    test('atiende primero el paso más específico (el último registrado)', () {
      final order = <String>[];
      bool a() {
        order.add('panel');
        return false;
      }

      bool b() {
        order.add('carpeta');
        return true;
      }

      BackNav.add(a);
      BackNav.add(b);
      expect(BackNav.handle(), isTrue);
      expect(order, ['carpeta'], reason: 'se detiene al consumir el gesto');

      BackNav.remove(b);
      expect(BackNav.handle(), isFalse);
      expect(order, ['carpeta', 'panel']);
    });

    test('un paso roto no deja el atrás sin atender', () {
      expect(
        () => BackNav.add(() => throw StateError('roto')),
        returnsNormally,
      );
      BackNav.add(() => false);
      // El error se reporta, pero la cadena sigue y contesta.
      expect(BackNav.handle(), isFalse);
    });
  });

  group('guardia del atrás', () {
    test(
      'atiende cuando hay pantallas y deja pasar si la cadena está vacía',
      () async {
        var steps = 0;
        BackNav.add(() {
          steps++;
          return true;
        });
        expect(await BackNavGuard.instance.didPopRoute(), isTrue);
        expect(steps, 1);

        BackNav.resetForTest();
        expect(
          await BackNavGuard.instance.didPopRoute(),
          isFalse,
          reason:
              'sin panel montado (login/arranque) el atrás es del navegador',
        );
      },
    );
  });

  group('Drive', () {
    setUp(() {
      _installMock();
    });

    testWidgets('dentro de una carpeta el atrás SUBE (no saca de la app)', (
      tester,
    ) async {
      final drive = await _pumpDrive(tester);
      expect(drive.path, isEmpty);

      await tester.tap(find.text('Bodas').first);
      await _settle(tester);
      expect(drive.path, ['Bodas']);

      await _pressBack(tester);
      expect(drive.path, isEmpty, reason: 'vuelve a la carpeta padre');
      expect(find.byType(DrivePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con fotos seleccionadas el atrás primero deselecciona', (
      tester,
    ) async {
      await _pumpDrive(tester);

      await tester.longPress(find.text('foto_00.png').first);
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('selection-count')),
        findsOneWidget,
        reason: 'la foto quedó seleccionada',
      );

      await _pressBack(tester);
      expect(
        find.byKey(const ValueKey('selection-count')),
        findsNothing,
        reason: 'el atrás deselecciona antes de moverse de sitio',
      );
      // La barra de selección se dibuja con la fuente de prueba (cuadros de
      // 1em) y desborda unos píxeles: es del FONT falso, no del atrás. Se
      // consume para que no quede pendiente.
      tester.takeException();
    });

    testWidgets('en la raíz de una sub-vista el atrás vuelve al listado', (
      tester,
    ) async {
      var closed = 0;
      await _pumpDrive(tester, onBack: () => closed++);

      await _pressBack(tester);
      expect(closed, 1, reason: 'Archivos compartidos cierra la carpeta');
      expect(tester.takeException(), isNull);
    });

    testWidgets('después de VER y cerrar una foto, el atrás sube de carpeta', (
      tester,
    ) async {
      final drive = await _pumpDrive(tester);
      await tester.tap(find.text('Bodas').first);
      await _settle(tester);
      expect(drive.path, ['Bodas']);

      // Se abre el visor de la foto y se cierra con su botón…
      await tester.tap(find.text('boda_00.png').first);
      await _settle(tester);
      expect(
        find.byTooltip('Cerrar'),
        findsWidgets,
        reason: 'el visor de la foto quedó abierto',
      );
      await tester.tap(find.byTooltip('Cerrar').first);
      await _settle(tester);

      // …y el atrás DEBE subir de carpeta, no sacar de la app.
      await _pressBack(tester);
      expect(
        drive.path,
        isEmpty,
        reason: 'tras ver una foto el atrás sigue volviendo a la carpeta padre',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin PopScope raíz, el guardia evita que la app se cierre', (
      tester,
    ) async {
      // Monta el guardia como lo hace `main` (después de `WidgetsApp`).
      BackNavGuard.install();
      final drive = await _pumpDrive(tester, rootPopScope: false);
      await tester.tap(find.text('Bodas').first);
      await _settle(tester);
      expect(drive.path, ['Bodas']);

      final handled = await _pressBack(tester);
      expect(
        handled,
        isTrue,
        reason: 'un popRoute sin atender es lo que cierra la app en la web',
      );
      expect(
        drive.path,
        isEmpty,
        reason: 'el guardia entrega el gesto a la cadena: sube de carpeta',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('en la raíz del módulo el atrás NO sale: decide el panel', (
      tester,
    ) async {
      final drive = await _pumpDrive(tester);

      expect(await _pressBack(tester), isTrue);
      expect(drive.path, isEmpty);
      expect(
        find.byType(DrivePage),
        findsOneWidget,
        reason:
            'sin nada que deshacer el gesto pasa al panel, no cierra la app',
      );
      expect(tester.takeException(), isNull);
    });
  });
}

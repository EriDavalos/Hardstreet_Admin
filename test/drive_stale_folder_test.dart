import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/drive_api_service.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';

// ==================================================================
// IR Y VOLVER ENTRE CARPETAS MIENTRAS UNA ESTÁ CARGANDO
//
// Bug reportado: al entrar a una carpeta y regresar a una anterior, mientras
// la de ahora carga seguían a la vista las fotos de la carpeta anterior —como
// si siguieran cargando— y, cuando por fin llegaba la respuesta de la carpeta
// que se dejó, se pintaba encima con su nombre de carpeta equivocado.
//
// La regla: al cambiar de carpeta NO se muestran los elementos de la anterior
// y la respuesta de una carpeta que ya se dejó se DESCARTA.
// ==================================================================

/// Servidor del drive falso con una carpeta que TARDA a propósito: así se
/// reproduce "entrar, y volver antes de que llegue la respuesta".
class _DriveMock {
  _DriveMock({required this.slow});

  /// Carpeta cuya respuesta se queda esperando hasta [release].
  final String slow;
  final Completer<void> release = Completer<void>();

  MockClient client() => MockClient((request) async {
    final path = request.url.queryParameters['path'] ?? '';
    if (path == slow) await release.future;
    final List<Map<String, dynamic>> folders;
    if (path.isEmpty) {
      folders = [
        {'name': slow, 'isFolder': true},
        {'name': 'Otra', 'isFolder': true},
      ];
    } else if (path == slow) {
      folders = [
        {'name': 'Dentro', 'isFolder': true},
      ];
    } else {
      folders = const [];
    }
    return http.Response(
      jsonEncode({'folders': folders}),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

List<String> _names(DriveApiService d) =>
    d.items.map((i) => i.name).toList(growable: false);

void main() {
  // El drive remoto solo se pide CON sesión (sin `Apikey` el servidor lo
  // rechaza): estas pruebas simulan un usuario ya logueado.
  setUp(() => HsSession.token = 'tok-test');
  tearDown(() {
    DriveApiService.client = http.Client();
    HsSession.clear();
  });

  test(
    'sin sesión NO se pide nada al servidor (ni error de arranque)',
    () async {
      var calls = 0;
      DriveApiService.client = MockClient((request) async {
        calls++;
        return http.Response(jsonEncode({'folders': const []}), 200);
      });
      HsSession.clear(); // como al abrir la app antes del login
      final drive = DriveApiService(baseUrl: 'http://drive.test');
      await drive.refresh();

      expect(
        calls,
        0,
        reason: 'la petición saldría sin token y el servidor la rechaza',
      );
      expect(
        drive.error,
        isNull,
        reason: 'no hay error que mostrar: aún no hay sesión',
      );
      expect(drive.waitingSession, isTrue);

      // Entra la sesión: el listado se pide y ya se ve el contenido.
      HsSession.token = 'tok-test';
      await drive.refresh();
      expect(calls, 1);
      expect(drive.waitingSession, isFalse);
      expect(drive.error, isNull);
    },
  );

  test(
    'la respuesta de la carpeta que se dejó NO pinta encima sus fotos',
    () async {
      final mock = _DriveMock(slow: 'Lenta');
      DriveApiService.client = mock.client();
      final drive = DriveApiService(baseUrl: 'http://drive.test');
      await drive.refresh();
      expect(_names(drive), containsAll(['Lenta', 'Otra']));

      // Se entra a la carpeta lenta: queda cargando.
      final entering = drive.openFolder('Lenta');
      // Mientras carga la NUEVA no se ven los elementos de la anterior.
      expect(drive.loading, isTrue);
      expect(
        _names(drive),
        isEmpty,
        reason: 'los elementos de la carpeta anterior no deben seguir ahí',
      );

      // El usuario vuelve a la raíz antes de que llegue esa respuesta…
      await drive.goUp();
      expect(_names(drive), containsAll(['Lenta', 'Otra']));
      expect(drive.loading, isFalse);

      // …y por fin llega la de la carpeta que se dejó: se DESCARTA.
      mock.release.complete();
      await entering;
      expect(
        _names(drive),
        containsAll(['Lenta', 'Otra']),
        reason: 'el contenido de «Lenta» no debe aparecer en la raíz',
      );
      expect(_names(drive), isNot(contains('Dentro')));
      expect(drive.loadedPath, '');
      expect(drive.loading, isFalse);
    },
  );

  test(
    'al cambiar de CUENTA el drive vuelve a la RAÍZ, no a la carpeta anterior',
    () async {
      // Bug reportado: se veían las carpetas de una empresa, se cerraba sesión
      // y al entrar con el Superadministrador el módulo Archivos abría en la
      // carpeta de la cuenta ANTERIOR (que para él no existe).
      final asked = <String>[];
      DriveApiService.client = MockClient((request) async {
        final p = request.url.queryParameters['path'] ?? '';
        asked.add(p);
        return http.Response(
          jsonEncode({
            'folders': [
              {'name': 'Empresa', 'isFolder': true},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final drive = DriveApiService(baseUrl: 'http://drive.test');
      await drive.refresh();
      await drive.openFolder('Empresa');
      expect(drive.path, ['Empresa']);

      // Nueva sesión (otra cuenta u otra empresa activa).
      HsSession.clear();
      HsSession.token = 'otro-token';
      drive.resetSession();

      expect(drive.path, isEmpty);
      expect(drive.loadedPath, isNull);
      expect(drive.items, isEmpty);

      await drive.refresh();
      expect(
        asked.last,
        '',
        reason: 'la primera petición de la sesión nueva va a SU raíz',
      );
      expect(drive.path, isEmpty);
    },
  );

  testWidgets('al cambiar de carpeta se ve el cargador, no lo de la anterior', (
    tester,
  ) async {
    final mock = _DriveMock(slow: 'Lenta');
    DriveApiService.client = mock.client();
    final drive = DriveApiService(baseUrl: 'http://drive.test');

    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DrivePage(drive: drive)),
      ),
    );
    // La raíz carga (la red del mock responde al instante).
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Lenta'), findsOneWidget);
    expect(find.text('Otra'), findsOneWidget);

    // Se entra a la carpeta lenta: carga SIN dejar a la vista lo anterior.
    await tester.tap(find.text('Lenta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.text('Otra'),
      findsNothing,
      reason: 'las carpetas de la raíz no deben seguir a la vista',
    );

    // Llega la respuesta: ahora sí se ve el contenido de la carpeta.
    mock.release.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Dentro'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

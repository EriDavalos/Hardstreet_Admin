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
// DRIVE — LA CARPETA COMPARTIDA ES LA RAÍZ DEL CLIENTE
//
// Tres cosas que se veían mal:
//
//   1. al entrar a la carpeta compartida, las migas mostraban el camino del
//      estudio («Mi Drive > XV > ReynaCoot») en vez de «Mi Drive > ReynaCoot»;
//   2. la tarjeta decía «0 elementos» aunque dentro hubiera 2 (el listado de la
//      raíz no puede contar el contenido de una compartida ANIDADA);
//   3. y, para cualquiera, con una carpeta cargando NO se podía entrar a otra
//      hasta que terminara: con fotos de por medio, un buen rato.
// ==================================================================

/// Respuesta del servidor del drive falso.
http.Response _res(List<Map<String, dynamic>> folders) => http.Response(
      jsonEncode({'folders': folders}),
      200,
      headers: {'content-type': 'application/json'},
    );

/// Servidor FALSO. `Lenta` siempre se queda esperando a [release] y la raíz lo
/// hace a partir de la llamada [slowRootFrom] (así se reproduce «volver a la
/// raíz y, mientras recarga, entrar a otra carpeta»).
class _Mock {
  _Mock({this.slowRootFrom = 99});

  /// Número de petición de la raíz a partir de la cual se espera a [release].
  final int slowRootFrom;

  /// Cuántos elementos tiene DENTRO la carpeta compartida (el cliente puede
  /// subir o borrar los suyos: el servidor es quien lleva la cuenta).
  int reynaItems = 2;

  final Completer<void> release = Completer<void>();
  int rootCalls = 0;

  MockClient client() => MockClient((request) async {
        final path = request.url.queryParameters['path'] ?? '';
        switch (path) {
          case '':
            rootCalls++;
            if (rootCalls >= slowRootFrom) await release.future;
            return _res([
              {'name': 'XV', 'isFolder': true, 'childCount': 5},
              {'name': 'Lenta', 'isFolder': true, 'childCount': 1},
              {'name': 'Otra', 'isFolder': true, 'childCount': 1},
            ]);
          case 'XV/ReynaCoot':
            // La carpeta COMPARTIDA, con SU contenido de verdad.
            return _res([
              {'name': 'Seleccion', 'isFolder': true},
              for (var i = 1; i < reynaItems; i++)
                {'name': 'IMG_$i.jpg', 'isFolder': false, 'size': 10},
            ]);
          case 'XV/ReynaCoot/Seleccion':
            return _res([
              {'name': 'IMG_2.jpg', 'isFolder': false, 'size': 10},
            ]);
          case 'Lenta':
            await release.future;
            return _res([
              {'name': 'DentroLenta', 'isFolder': true},
            ]);
          case 'Otra':
            return _res([
              {'name': 'DentroOtra', 'isFolder': true},
            ]);
          default:
            return _res(const []);
        }
      });
}

/// Deja correr la red real y avanza las animaciones.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 60)),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpPage(WidgetTester tester, DriveApiService drive) async {
  await tester.binding.setSurfaceSize(const Size(1280, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: DrivePage(drive: drive))),
  );
  await _settle(tester);
}

void main() {
  // El drive remoto solo se pide CON sesión.
  setUp(() => HsSession.token = 'tok-test');
  tearDown(() {
    DriveApiService.client = http.Client();
    HsSession.clear();
  });

  test('la compartida anidada dice cuántos elementos tiene DENTRO', () async {
    final mock = _Mock();
    DriveApiService.client = mock.client();
    final drive = DriveApiService(baseUrl: 'http://drive.test');

    await drive.setSharedRoots(['XV/ReynaCoot'], isClient: true);

    // En la raíz del cliente se ve UNA carpeta, con el nombre de SU carpeta.
    expect(drive.items.map((i) => i.name), ['ReynaCoot']);
    // Y con el contenido de verdad: antes decía 0 teniendo 2 dentro.
    final reyna = drive.items.single;
    expect(reyna.childCount, 2);
    expect(reyna.countKnown, isTrue,
        reason: 'el conteo se consultó a la carpeta compartida');
  });

  test('el conteo de la compartida se mantiene al día al refrescar', () async {
    final mock = _Mock();
    DriveApiService.client = mock.client();
    final drive = DriveApiService(baseUrl: 'http://drive.test');
    await drive.setSharedRoots(['XV/ReynaCoot'], isClient: true);
    expect(drive.items.single.childCount, 2);

    // El cliente agrega una foto a SU carpeta: la próxima carga del drive ya
    // no puede repetir el número viejo.
    mock.reynaItems = 3;
    await drive.refresh();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(drive.items.single.childCount, 3,
        reason: 'la tarjeta se pone al día sola, no solo al abrir la app');
  });

  test('tocar dos veces la misma carpeta no la mete dentro de sí misma',
      () async {
    final mock = _Mock();
    DriveApiService.client = mock.client();
    final drive = DriveApiService(baseUrl: 'http://drive.test');
    await drive.refresh();

    // Segundo toque mientras la primera sigue cargando (el doble clic).
    final first = drive.openFolder('Lenta');
    final second = drive.openFolder('Lenta');
    mock.release.complete();
    await Future.wait([first, second]);

    expect(drive.path, ['Lenta'],
        reason: 'nunca "Lenta / Lenta": el toque va sobre lo que se VE');
  });

  testWidgets('el cliente ve su carpeta como raíz: "Mi Drive > ReynaCoot"',
      (tester) async {
    final mock = _Mock();
    DriveApiService.client = mock.client();
    final drive = DriveApiService(baseUrl: 'http://drive.test');
    await drive.setSharedRoots(['XV/ReynaCoot'], isClient: true);
    await _pumpPage(tester, drive);

    // La tarjeta de su carpeta compartida, con lo que tiene dentro.
    expect(find.text('ReynaCoot'), findsOneWidget);
    expect(find.text('2 elementos'), findsOneWidget,
        reason: 'antés decía "0 elementos" teniendo 2 fotos dentro');

    await tester.tap(find.text('ReynaCoot'));
    await _settle(tester);
    expect(drive.path, ['XV', 'ReynaCoot']);
    expect(drive.locationLabel, 'ReynaCoot',
        reason: 'el encabezado tampoco enseña el camino del estudio');
    expect(find.text('XV'), findsNothing,
        reason: 'el cliente no ve de qué carpeta del estudio salió la suya');
    // Encabezado ("Mi Drive" + el nombre como subtítulo) y las migas: la raíz
    // (Mi Drive) + SU carpeta, sin la carpeta del estudio por medio.
    expect(find.text('ReynaCoot'), findsNWidgets(2),
        reason: 'subtítulo del encabezado + miga');
    expect(find.text('Mi Drive'), findsNWidgets(2),
        reason: 'título del encabezado + miga de la raíz del cliente');

    // Y desde ahí se vuelve a SU raíz con las migas.
    await tester.tap(find.text('Mi Drive').last);
    await _settle(tester);
    expect(drive.path, isEmpty);
    expect(find.text('ReynaCoot'), findsOneWidget);
  });

  testWidgets('mientras una carpeta carga se puede entrar a otra',
      (tester) async {
    // La raíz responde al instante la 1ª vez (la del arranque) y a partir de
    // la 2ª se queda esperando: es la recarga que deja todo colgado.
    final mock = _Mock(slowRootFrom: 2);
    DriveApiService.client = mock.client();
    final drive = DriveApiService(baseUrl: 'http://drive.test');
    await _pumpPage(tester, drive);

    // 1) Se entra a la carpeta lenta: queda cargando (sin respuesta).
    await tester.tap(find.text('Lenta'));
    await tester.pump();
    expect(drive.path, ['Lenta']);
    expect(drive.loading, isTrue);

    // 2) Se vuelve a la raíz: se ve el listado que ya se conocía mientras
    //    la recarga sigue en el aire.
    await tester.tap(find.text('Mi Drive').last);
    await _settle(tester);
    expect(drive.loading, isTrue, reason: 'la raíz sigue recargando');
    expect(find.text('Otra'), findsOneWidget,
        reason: 'el listado conocido se ve al instante');

    // 3) Con la raíz TODAVÍA cargando se entra a otra carpeta: antes este
    //    toque se IGNORABA hasta que terminara la carga.
    await tester.tap(find.text('Otra'));
    await _settle(tester);
    expect(drive.path, ['Otra']);
    expect(find.text('DentroOtra'), findsOneWidget);

    // 4) Y la respuesta que quedó pendiente NO pinta encima.
    mock.release.complete();
    await _settle(tester);
    expect(drive.path, ['Otra']);
    expect(find.text('DentroOtra'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

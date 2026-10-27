// ==================================================================
// SEGUNDO PLANO: SOLO AVISOS, Y AL VOLVER SE RECARGA TODO
// ==================================================================
// Con la app en segundo plano (otra ventana al frente o minimizada) el panel
// no puede seguir consultando lo mismo que cuando está a la vista: solo los
// avisos necesitan enterarse de algo. Además se sueltan las imágenes
// decodificadas, que son lo que más RAM ocupa. Al volver —un clic en la
// ventana— la sección se vuelve a cargar completa.
// ==================================================================
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hardstreet_admin/app_awake.dart';
import 'package:hardstreet_admin/drive_api_service.dart';
import 'package:hardstreet_admin/drive_scope.dart';
import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/hs_access.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/main.dart';
import 'package:hardstreet_admin/pages/client_dashboard_page.dart';

/// Mete una imagen de verdad en la caché de RAM (una foto ya cargada): se
/// dibuja un cuadradito y se resuelve, en vez de decodificar un archivo.
Future<void> _loadFakePhoto(WidgetTester tester) async {
  final cache = PaintingBinding.instance.imageCache;
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 4, 4),
      Paint()..color = const Color(0xFF00FF00),
    );
    final image = await recorder.endRecording().toImage(4, 4);
    final completer = OneFrameImageStreamCompleter(
      Future<ImageInfo>.value(ImageInfo(image: image)),
    );
    cache.putIfAbsent('foto-de-prueba', () => completer);
    // Un respiro para que el completador emita y la foto quede "cargada".
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });
}

Map<String, dynamic> _mod(String key, String name, {required int order}) => {
  'key': key,
  'name': name,
  'order': order,
  'categoryKey': null,
  'categoryName': null,
  'categoryOrder': null,
  'actions': const ['read'],
};

Future<Directory> _tempDir(WidgetTester tester) async {
  late Directory tmp;
  await tester.runAsync(() async {
    tmp = await Directory.systemTemp.createTemp('hardstreet_awake');
  });
  addTearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });
  return tmp;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HsAccess.reset();
    // En la app de verdad esto lo hace el arranque (`HardStreetAdminApp`), que
    // en estas pruebas no está montado: aquí solo se dibuja el panel.
    AppAwake.instance.start();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  tearDown(() {
    HsAccess.reset();
    HsSession.clear();
    // El estado se deja como al arrancar: los demás archivos de prueba corren
    // con la app a la vista.
    AppAwake.instance.debugSetAwake(true);
  });

  testWidgets('en segundo plano se sueltan las imágenes y al volver avisa', (
    tester,
  ) async {
    await _loadFakePhoto(tester);
    final cache = PaintingBinding.instance.imageCache;
    expect(cache.currentSize, greaterThan(0), reason: 'la foto quedó en RAM');

    AppAwake.instance.debugSetAwake(false);
    expect(AppAwake.instance.awake, isFalse);
    expect(
      cache.currentSize,
      0,
      reason: 'en segundo plano la memoria de imágenes se suelta',
    );

    final antes = AppAwake.instance.resumed.value;
    AppAwake.instance.debugSetAwake(true);
    expect(AppAwake.instance.awake, isTrue);
    expect(
      AppAwake.instance.resumed.value,
      antes + 1,
      reason: 'volver a la app avisa para recargar todo',
    );
    // Repetir el mismo estado no cuenta como un regreso nuevo.
    AppAwake.instance.debugSetAwake(true);
    expect(AppAwake.instance.resumed.value, antes + 1);
  });

  testWidgets('en segundo plano no se consulta y al volver se recarga todo', (
    tester,
  ) async {
    final tmp = await _tempDir(tester);
    final previous = HsApi.client;
    final pedidos = <String>[];
    HsApi.client = MockClient((request) async {
      final headers = {'content-type': 'application/json'};
      final path = request.url.path;
      pedidos.add(path);
      if (path.endsWith('/api/admin/permission')) {
        return http.Response(
          jsonEncode({
            'isAdmin': false,
            'modules': [
              _mod('my_package', 'Mi paquete', order: 1),
              _mod('drive', 'Archivos', order: 2),
            ],
          }),
          200,
          headers: headers,
        );
      }
      if (path.endsWith('/api/my/packages')) {
        return http.Response(
          jsonEncode({'purchasedPackages': const []}),
          200,
          headers: headers,
        );
      }
      return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
    });
    addTearDown(() => HsApi.client = previous);

    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      DriveScope(
        drive: DriveService.testRoot(tmp),
        child: MaterialApp(
          home: AdminHome(dark: false, onToggleTheme: () {}, onLogout: () {}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ClientDashboardPage), findsOneWidget);

    int paquetes() =>
        pedidos.where((p) => p.endsWith('/api/my/packages')).length;
    final cargado = paquetes();
    expect(
      cargado,
      greaterThan(0),
      reason: 'la sección pide sus datos al abrir',
    );

    // 1. SEGUNDO PLANO (otra ventana al frente o minimizada).
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(AppAwake.instance.awake, isFalse);

    final quieto = pedidos.length;
    await tester.pump(const Duration(seconds: 30));
    expect(
      pedidos.length,
      quieto,
      reason: 'en segundo plano el panel no consulta nada',
    );

    // 2. VUELVE LA APP (un clic en la ventana): todo se recarga.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(AppAwake.instance.awake, isTrue);
    expect(find.byType(ClientDashboardPage), findsOneWidget);
    expect(
      paquetes(),
      greaterThan(cargado),
      reason: 'al volver la sección vuelve a pedir sus datos',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('al volver el DRIVE también vuelve a pedir su listado', (
    tester,
  ) async {
    final previousApi = HsApi.client;
    HsApi.client = MockClient((request) async {
      final headers = {'content-type': 'application/json'};
      if (request.url.path.endsWith('/api/admin/permission')) {
        return http.Response(
          jsonEncode({
            'isAdmin': false,
            'modules': [
              _mod('my_package', 'Mi paquete', order: 1),
              _mod('drive', 'Archivos', order: 2),
            ],
          }),
          200,
          headers: headers,
        );
      }
      return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
    });
    addTearDown(() => HsApi.client = previousApi);

    final antesCliente = DriveApiService.client;
    final pedidos = <http.BaseRequest>[];
    DriveApiService.client = MockClient((request) async {
      pedidos.add(request);
      return http.Response(
        jsonEncode({'path': const [], 'folders': const []}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(() => DriveApiService.client = antesCliente);

    HsSession.token = 'tok-test';
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      DriveScope(
        drive: DriveApiService(baseUrl: 'http://drive.test'),
        child: MaterialApp(
          home: AdminHome(dark: false, onToggleTheme: () {}, onLogout: () {}),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final cargado = pedidos.length;
    expect(cargado, greaterThan(0), reason: 'al abrir pide el listado');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      pedidos.length,
      greaterThan(cargado),
      reason: 'al volver el Drive vuelve a pedir su listado',
    );
    expect(tester.takeException(), isNull);
  });
}

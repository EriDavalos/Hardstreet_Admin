import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/app_updater.dart';
import 'package:hardstreet_admin/widgets/force_update_dialog.dart';

/// Tamaño legible para los textos del modal (25 MB / 100 MB).
const _mb25 = 25 * 1024 * 1024;
const _mb100 = 100 * 1024 * 1024;

Future<void> _openDialog(
  WidgetTester tester, {
  required bool optional,
  String url = 'http://example.com/HardstreetAdmin-setup.exe',
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Center(
        child: FilledButton(
          onPressed: () => ForceUpdateDialog.show(
            ctx,
            currentVersion: '1.0.0',
            requiredVersion: '1.5.0',
            notes: 'Cambios importantes',
            downloadUrl: url,
            optional: optional,
          ),
          child: const Text('abrir'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    // Los fakes se reemplazan por los reales en cada prueba.
    AppUpdater.downloadFn = AppUpdater.download;
    AppUpdater.installFn = AppUpdater.install;
  });

  testWidgets('Obligatorio: barra de progreso con MB y porcentaje, luego instala', (tester) async {
    final pending = Completer<File>();
    File? installed;
    AppUpdater.downloadFn = (url, {fileName, required onProgress}) {
      onProgress(_mb25, _mb100);
      return pending.future;
    };
    AppUpdater.installFn = (file) async => installed = file;

    await _openDialog(tester, optional: false);
    expect(find.text('Actualización requerida'), findsOneWidget);
    expect(find.text('Descargar e instalar (.exe)'), findsOneWidget);
    expect(find.text('Cambios importantes'), findsOneWidget);

    await tester.tap(find.text('Descargar e instalar (.exe)'));
    await tester.pump();

    // Fase descargando: barra con progreso Y texto con MB + porcentaje.
    expect(find.text('Descargando actualización'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('25.0 MB de 100.0 MB (25%)'), findsOneWidget);

    // Termina la descarga → instala (installFn registrado, sin salir de la app).
    final fake = File('C:/tmp/fake-update.exe');
    pending.complete(fake);
    await tester.pumpAndSettle();
    expect(installed, same(fake));
  });

  testWidgets('La barra de progreso ocupa el ancho del modal (420px)', (tester) async {
    final pending = Completer<File>();
    AppUpdater.downloadFn = (url, {fileName, required onProgress}) {
      onProgress(_mb25, _mb100);
      return pending.future;
    };
    AppUpdater.installFn = (file) async {};
    addTearDown(() => pending.completeError(const AppUpdateCancelled()));

    // Viewport ancho (1400px): si el modal se estirara al espacio
    // disponible, la barra mediría mucho más que el interior del modal.
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: ForceUpdateDialog(
            currentVersion: '1.0.0',
            requiredVersion: '2.0.0',
            notes: '',
            downloadUrl: 'http://example.com/setup.exe',
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Descargar e instalar (.exe)'));
    await tester.pump();

    // El interior del modal es FIJO (420 - padding 28 x 2 = 364), no el
    // viewport de 1400px: ni el contenido ni la barra se estiran.
    final content = tester.getSize(find.byType(Column));
    expect(content.width, 420 - 56);

    // La barra ocupa exactamente el ancho del modal (mismo tamaño).
    final bar = tester.getSize(find.byType(LinearProgressIndicator));
    expect(bar.width, content.width);
    expect(bar.height, 8);
  });

  testWidgets('Opcional: Cancelar durante la descarga vuelve al inicio', (tester) async {
    final pending = Completer<File>();
    AppUpdater.downloadFn = (url, {fileName, required onProgress}) {
      onProgress(_mb25, _mb100);
      return pending.future;
    };
    AppUpdater.installFn = (file) async {};

    await _openDialog(tester, optional: true, url: 'http://example.com/setup.exe');
    expect(find.text('Actualización disponible'), findsOneWidget);

    await tester.tap(find.text('Descargar e instalar (.exe)'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // El modal opcional ofrece Cancelar; al pulsarlo, el stream activo se
    // cancela y el futuro responde AppUpdateCancelled → fase idle.
    expect(find.text('Cancelar'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    pending.completeError(const AppUpdateCancelled());
    await tester.pumpAndSettle();

    expect(find.text('Actualización disponible'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Descargar e instalar (.exe)'), findsOneWidget);
  });

  testWidgets('Obligatorio: sin botón Cancelar durante la descarga', (tester) async {
    final pending = Completer<File>();
    AppUpdater.downloadFn = (url, {fileName, required onProgress}) {
      onProgress(_mb25, _mb100);
      return pending.future;
    };
    AppUpdater.installFn = (file) async {};
    addTearDown(() => pending.completeError(const AppUpdateCancelled()));

    await _openDialog(tester, optional: false);
    await tester.tap(find.text('Descargar e instalar (.exe)'));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Cancelar'), findsNothing);
  });

  testWidgets('Obligatorio: la ventana no se puede cerrar con Esc', (tester) async {
    AppUpdater.downloadFn = (url, {fileName, required onProgress}) async {
      throw const AppUpdateCancelled();
    };
    AppUpdater.installFn = (file) async {};

    await _openDialog(tester, optional: false);

    // Esc intenta cerrar la ruta actual: PopScope canPop=false lo bloquea.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Actualización requerida'), findsOneWidget);
  });

  testWidgets('Error de descarga: mensaje del servidor y Reintentar funciona', (tester) async {
    var attempts = 0;
    AppUpdater.downloadFn = (url, {fileName, required onProgress}) async {
      attempts++;
      if (attempts == 1) {
        throw const AppUpdateException('El servidor respondió HTTP 404.');
      }
      onProgress(_mb100, _mb100);
      return File('C:/tmp/ok.exe');
    };
    AppUpdater.installFn = (file) async {};

    await _openDialog(tester, optional: false);

    await tester.tap(find.text('Descargar e instalar (.exe)'));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo descargar'), findsOneWidget);
    expect(find.text('El servidor respondió HTTP 404.'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    // Tras instalar (Android-style: installFn regresa) se confirma el éxito.
    expect(find.text('Instalación iniciada'), findsOneWidget);
  });

  testWidgets('Sin URL de descarga: botón deshabilitado con aviso', (tester) async {
    await _openDialog(tester, optional: false, url: '');
    // El botón existe pero DESHABILITADO (onPressed: null).
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Descargar e instalar (.exe)'),
    );
    expect(button.onPressed, isNull);
    expect(
      find.text('El servidor no publicó el enlace de descarga aún.'),
      findsOneWidget,
    );
  });
}

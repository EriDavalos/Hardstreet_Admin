import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';

void main() {
  testWidgets('Panel de subidas: conteo, tiempo real y barra global',
      (WidgetTester tester) async {
    late Directory tmp;
    late Directory src;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('hardstreet_uploads_test');
      src = await Directory.systemTemp.createTemp('hardstreet_uploads_src');
    });
    addTearDown(() async {
      await tmp.delete(recursive: true);
      await src.delete(recursive: true);
    });

    final drive = DriveService.testRoot(tmp);

    // Viewport tipo laptop (DrivePage lo requiere) dentro de un Scaffold
    // (el Scaffold normal lo aporta AdminShell).
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DrivePage(drive: drive))),
    );
    // El constructor dispara refresh(); dejar que termine el I/O real.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));

    // Estado inicial: sin panel (no hay jobs).
    expect(find.text('Mi Drive'), findsOneWidget);
    expect(find.byKey(const ValueKey('uploads_card')), findsNothing);

    // Estado intermedio INYECTADO: 1 en carga (al 40%), 1 completada.
    final uploading = DriveUploadJob(
      id: 'j1',
      name: 'en-curso.jpg',
      thumb: '',
      total: 1000,
    );
    uploading.sent = 400;
    final done = DriveUploadJob(
      id: 'j2',
      name: 'lista.jpg',
      thumb: '',
      total: 2000,
    )..status = 'done';
    drive.addUploadJob(done); // quedará segunda en la lista
    drive.addUploadJob(uploading); // la más reciente arriba
    await tester.pump();

    // El panel aparece con el conteo correcto (TODAS las fotos en el
    // header, no solo la activa).
    expect(find.byKey(const ValueKey('uploads_card')), findsOneWidget);
    expect(find.text('Subiendo 2 fotos…'), findsOneWidget);
    expect(find.text('1 completada'), findsOneWidget);
    // Progreso global: 400 de 1000 bytes en curso -> 40 %.
    expect(find.text('40 %'), findsOneWidget);
    // Fila en carga con su porcentaje individual.
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('lista.jpg'), findsOneWidget);

    // Avance en TIEMPO REAL: sin await entre medias, solo notificaciones.
    uploading.sent = 900;
    drive.notifyUploadProgress();
    await tester.pump();
    expect(find.text('90 %'), findsOneWidget);
    expect(find.text('90%'), findsOneWidget);

    // Al terminar: pasa a "completadas" y permite limpiar.
    drive.finishUploadJob(uploading);
    await tester.pump();
    expect(find.text('2 subidas completadas'), findsOneWidget);

    drive.clearFinishedUploads();
    await tester.pump();
    expect(find.byKey(const ValueKey('uploads_card')), findsNothing);
  });
}

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
    expect(find.text('1 de 2 fotos'), findsOneWidget);
    // Progreso del LOTE: 1 de 2 fotos subidas -> 50% subidas y "1/2 fotos"
    // (no los bytes en curso: lo que se quiere saber es cuántas faltan).
    expect(find.text('50% subidas'), findsOneWidget);
    expect(find.text('1/2 fotos'), findsOneWidget);
    // La fila en carga sigue con su porcentaje individual (por bytes).
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('lista.jpg'), findsOneWidget);

    // Avance en TIEMPO REAL: sin await entre medias, solo notificaciones.
    // La BARRA del lote no se mueve (0 fotos nuevas terminadas), pero la fila
    // de esa foto sí.
    uploading.sent = 900;
    drive.notifyUploadProgress();
    await tester.pump();
    expect(find.text('50% subidas'), findsOneWidget);
    expect(find.text('90%'), findsOneWidget);

    // Al terminar: el lote queda al 100% y permite limpiar.
    drive.finishUploadJob(uploading);
    await tester.pump();
    expect(find.text('2 subidas completadas'), findsOneWidget);
    expect(find.text('100% subidas'), findsOneWidget);
    expect(find.text('2/2 fotos'), findsOneWidget);

    drive.clearFinishedUploads();
    await tester.pump();
    expect(find.byKey(const ValueKey('uploads_card')), findsNothing);
  });

  testWidgets('Un lote de 100 fotos: se ven (y cuentan) todas, no 30',
      (WidgetTester tester) async {
    late Directory tmp;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('hardstreet_batch_test');
    });
    addTearDown(() => tmp.delete(recursive: true));

    final drive = DriveService.testRoot(tmp);
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DrivePage(drive: drive))),
    );
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));

    // Un lote de 100 fotos, TODAS registradas de una (como hace el drive al
    // subir una selección grande): ninguna puede perderse de la lista.
    final batch = drive.newUploadBatch();
    for (var i = 0; i < 100; i++) {
      drive.addUploadJob(DriveUploadJob(
        id: 'u$i',
        name: 'foto-$i.jpg',
        thumb: '',
        total: 10,
        batch: batch,
      ));
    }
    await tester.pump();

    expect(find.text('Subiendo 100 fotos…'), findsOneWidget);
    expect(find.text('0 de 100 fotos'), findsOneWidget);
    expect(find.text('0% subidas'), findsOneWidget);
    expect(find.text('0/100 fotos'), findsOneWidget);

    // Se van terminando: la lista conserva las 31 hechas Y las 69 en cola (antes
    // el panel recortaba a 30 y las que esperaban turno desaparecían).
    for (var i = 0; i < 31; i++) {
      drive.finishUploadJob(drive.uploadJobById('u$i')!);
    }
    await tester.pump();

    expect(drive.uploadJobs.length, 100,
        reason: 'las fotos del lote no se pueden soltar de la lista');
    expect(drive.uploadJobs.where((j) => j.status == 'uploading').length, 69);
    expect(find.text('Subiendo 69 fotos…'), findsNothing,
        reason: 'el encabezado cuenta el lote COMPLETO (100), no las activas');
    expect(find.text('Subiendo 100 fotos…'), findsOneWidget);
    expect(find.text('31 de 100 fotos'), findsOneWidget);
    expect(find.text('31% subidas'), findsOneWidget);
    expect(find.text('31/100 fotos'), findsOneWidget);

    // Termina el lote: 100/100.
    for (var i = 31; i < 100; i++) {
      drive.finishUploadJob(drive.uploadJobById('u$i')!);
    }
    await tester.pump();
    expect(find.text('100 subidas completadas'), findsOneWidget);
    expect(find.text('100% subidas'), findsOneWidget);
    expect(find.text('100/100 fotos'), findsOneWidget);
  });

  testWidgets('Fila con error: muestra el motivo y el botón Resubir',
      (WidgetTester tester) async {
    final job = DriveUploadJob(
      id: 'j1',
      name: 'falla.jpg',
      thumb: '',
      total: 100,
    )
      ..status = 'error'
      ..error = 'HTTP 500';
    var resubidas = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploadJobTile(job: job, onRetry: () => resubidas++),
        ),
      ),
    );

    expect(find.textContaining('HTTP 500'), findsOneWidget);
    expect(find.text('Resubir'), findsOneWidget);

    await tester.tap(find.text('Resubir'));
    await tester.pump();
    expect(resubidas, 1, reason: 'Resubir debe reintentar ese archivo');
  });
}

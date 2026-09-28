import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/pages/drive_page.dart';
import 'package:hardstreet_admin/widgets/confirm_dialog.dart';

void main() {
  testWidgets('confirmDelete muestra y devuelve true al confirmar',
      (tester) async {
    var confirmed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: FilledButton(
              onPressed: () async {
                confirmed = await confirmDelete(ctx, title: '¿Eliminar "a.jpg"?');
              },
              child: const Text('borrar'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('borrar'));
    await tester.pumpAndSettle();

    expect(find.text('¿Eliminar "a.jpg"?'), findsOneWidget);
    expect(find.text('Esta acción no se puede deshacer.'), findsOneWidget);

    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  testWidgets('Panel: subir duplicados pregunta renombrar/sobrescribir',
      (tester) async {
    late Directory tmp;
    late Directory src;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('hardstreet_dup_test');
      src = await Directory.systemTemp.createTemp('hardstreet_dup_src');
    });
    addTearDown(() async {
      // Windows puede mantener el archivo bloqueado un instante (AV/indexador):
      // la limpieza es best-effort.
      try { await tmp.delete(recursive: true); } catch (_) {}
      try { await src.delete(recursive: true); } catch (_) {}
    });
    final drive = DriveService.testRoot(tmp);

    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DrivePage(drive: drive))),
    );
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    // Sube una foto la primera vez (sin duplicados).
    final f1 = File([src.path, 'dup.jpg'].join('/'))
      ..writeAsBytesSync([1, 2, 3]);
    await tester.runAsync(() => drive.uploadFromPaths([f1.path]));
    await tester.pump();

    // Segunda vez con el MISMO nombre: filterExisting lo detecta.
    final dups = await tester.runAsync(
        () => drive.filterExisting(['dup.jpg']));
    expect(dups, contains('dup.jpg'));

    // Y al subir con overwrite, NO se crea "(1)": reemplaza.
    await tester.runAsync(
        () => drive.uploadFromPaths([f1.path], overwrite: true));
    final names = drive.items.map((i) => i.name);
    expect(names, contains('dup.jpg'));
    expect(names, isNot(contains('dup (1).jpg')));
  });
}

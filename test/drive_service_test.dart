import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_service.dart';

void main() {
  group('DriveService (sistema de archivos temporal)', () {
    late DriveService drive;
    // Directorio aparte para archivos fuente: la raíz del drive TAMBIÉN es
    // una carpeta real, y todo lo que se cree dentro quedaría listado.
    late String srcBase;

    setUp(() async {
      final tmp = await Directory.systemTemp.createTemp('hardstreet_drive_test');
      drive = DriveService.testRoot(tmp);
      final srcTmp =
          await Directory.systemTemp.createTemp('hardstreet_drive_src');
      srcBase = srcTmp.path;
    });

    File srcFile(String name, List<int> bytes) =>
        File([srcBase, name].join('/'))..writeAsBytesSync(bytes);

    test('createFolder, openFolder y listing', () async {
      await drive.createFolder('ReynaCoot');
      await drive.openFolder('ReynaCoot');
      await drive.createFolder('Fiesta');
      await drive.uploadFromPaths([]);

      expect(drive.path, ['ReynaCoot']);
      expect(drive.items.map((i) => i.name), contains('Fiesta'));
      expect(drive.items.every((i) => i.isFolder), isTrue);
    });

    test('uploadFromPaths copia imágenes y evita duplicados', () async {
      final src = srcFile('src.jpg', [1, 2, 3]);
      final saved = await drive.uploadFromPaths([src.path]);
      expect(saved, 1);
      expect(drive.items.map((i) => i.name), contains('src.jpg'));

      // Mismo archivo otra vez -> crea "src (1).jpg" en vez de sobrescribir
      await drive.uploadFromPaths([src.path]);
      expect(drive.items.map((i) => i.name), contains('src (1).jpg'));
    });

    test('solo lista imágenes con extensiones conocidas', () async {
      await drive.uploadFromPaths([srcFile('foto.png', [9]).path]);
      final txt = File([srcBase, 'notas.txt'].join('/'))
        ..writeAsStringSync('hola');
      await drive.uploadFromPaths([txt.path]);

      await drive.refresh();
      final names = drive.items.map((i) => i.name).toList();
      expect(names, contains('foto.png'));
      expect(names, isNot(contains('notas.txt')));
    });

    test('rename y delete funcionan', () async {
      await drive.createFolder('Vieja');
      final item = drive.items.single;
      await drive.rename(item, 'Nueva');
      expect(drive.items.single.name, 'Nueva');

      await drive.delete(drive.items.single);
      expect(drive.items, isEmpty);
    });

    test('openPath y goUp navegan la jerarquía', () async {
      await drive.createFolder('ReynaCoot');
      await drive.openFolder('ReynaCoot');
      await drive.createFolder('SesionPrevia');
      await drive.openFolder('SesionPrevia');
      expect(drive.path, ['ReynaCoot', 'SesionPrevia']);

      await drive.goUp();
      expect(drive.path, ['ReynaCoot']);

      await drive.openPath(const []);
      expect(drive.path, isEmpty);
    });

    test('moveItems mueve archivos y carpetas a otra carpeta', () async {
      await drive.uploadFromPaths([srcFile('a.jpg', [1]).path]);
      await drive.createFolder('Destino');
      await drive.createFolder('Sub');
      await drive.openFolder('Sub');
      await drive.uploadFromPaths([srcFile('deep.jpg', [2]).path]);
      await drive.goUp();

      final res = await drive.moveItems(['a.jpg', 'Sub'], ['Destino']);
      expect(res.moved, 2);
      expect(res.errors, isEmpty);
      expect(drive.items.map((i) => i.name), isNot(contains('a.jpg')));
      expect(drive.items.map((i) => i.name), isNot(contains('Sub')));

      await drive.openFolder('Destino');
      expect(drive.items.map((i) => i.name), containsAll(['a.jpg', 'Sub']));
      await drive.openFolder('Sub');
      expect(drive.items.map((i) => i.name), contains('deep.jpg'));
    });

    test('moveItems renombra si hay colisión en el destino', () async {
      final src = srcFile('a.jpg', [1]);
      await drive.uploadFromPaths([src.path]);
      await drive.createFolder('Destino');
      await drive.openFolder('Destino');
      await drive.uploadFromPaths([src.path]); // a.jpg ya existe ahí
      await drive.goUp();

      final res = await drive.moveItems(['a.jpg'], ['Destino']);
      expect(res.moved, 1);
      expect(res.errors, isEmpty);
      await drive.openFolder('Destino');
      expect(drive.items.map((i) => i.name),
          containsAll(['a.jpg', 'a (1).jpg']));
    });

    test('moveItems no permite mover una carpeta dentro de sí misma',
        () async {
      await drive.createFolder('Carpeta');
      final res = await drive.moveItems(['Carpeta'], ['Carpeta']);
      expect(res.moved, 0);
      expect(res.errors, isNotEmpty);
      expect(drive.items.single.name, 'Carpeta');
    });

    test('copyItems copia archivos y carpetas recursivamente', () async {
      await drive.uploadFromPaths([srcFile('b.png', [1]).path]);
      await drive.createFolder('Sub');
      await drive.openFolder('Sub');
      await drive.uploadFromPaths([srcFile('deep.jpg', [2]).path]);
      await drive.goUp();
      await drive.createFolder('Destino');

      final res = await drive.copyItems(['b.png', 'Sub'], ['Destino']);
      expect(res.copied, 2);
      expect(res.errors, isEmpty);

      // El origen queda intacto (es copia, no movimiento)
      expect(drive.items.map((i) => i.name), containsAll(['b.png', 'Sub']));

      await drive.openFolder('Destino');
      expect(drive.items.map((i) => i.name), containsAll(['b.png', 'Sub']));
      await drive.openFolder('Sub');
      expect(drive.items.map((i) => i.name), contains('deep.jpg'));
    });

    test('copyItems no permite copiar una carpeta dentro de sí misma',
        () async {
      await drive.createFolder('Carpeta');
      final res = await drive.copyItems(['Carpeta'], ['Carpeta']);
      expect(res.copied, 0);
      expect(res.errors, isNotEmpty);
    });

    test('deleteItems elimina archivos y carpetas en lote', () async {
      await drive.uploadFromPaths([srcFile('a.jpg', [1]).path]);
      await drive.createFolder('Sub');
      await drive.openFolder('Sub');
      await drive.uploadFromPaths([srcFile('deep.jpg', [2]).path]);
      await drive.goUp();

      // "inexistente.jpg" se ignora silenciosamente
      final res =
          await drive.deleteItems(['a.jpg', 'Sub', 'inexistente.jpg']);
      expect(res.deleted, 2);
      expect(res.errors, isEmpty);
      expect(drive.items, isEmpty);
    });
  });
}

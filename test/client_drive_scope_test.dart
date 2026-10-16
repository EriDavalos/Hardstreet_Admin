import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/drive_service.dart';

/// El drive de un CLIENTE solo muestra las carpetas que el estudio le
/// comparte en sus paquetes; el resto del Drive no existe para él.
void main() {
  group('Alcance compartido del drive (cliente)', () {
    late DriveService drive;
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hardstreet_scope_test');
      for (final n in ['ReynaCoot', 'Cliente', 'Privado']) {
        await Directory([root.path, n].join('/')).create(recursive: true);
      }
      await Directory([root.path, 'ReynaCoot', 'SesionPrevia'].join('/'))
          .create(recursive: true);
      await Directory([root.path, 'Privado', 'Intimo'].join('/'))
          .create(recursive: true);
      drive = DriveService.testRoot(root);
      await drive.refresh();
    });

    List<String> names() => drive.items.map((i) => i.name).toList();

    test('el equipo del estudio ve TODO el drive', () async {
      expect(drive.scoped, isFalse);
      expect(names(), containsAll(['ReynaCoot', 'Cliente', 'Privado']));
    });

    test('compartiendo 2 paquetes se ven SOLO esas 2 carpetas', () async {
      await drive.setSharedRoots(['ReynaCoot', 'Cliente'], isClient: true);

      expect(drive.scoped, isTrue);
      expect(names(), hasLength(2));
      expect(names(), containsAll(['ReynaCoot', 'Cliente']));
      expect(names(), isNot(contains('Privado')));

      // No se puede entrar a una carpeta que NO se comparte.
      await drive.openFolder('Privado');
      expect(drive.path, isEmpty);
      expect(names(), hasLength(2));

      // Dentro de una compartida se navega con normalidad.
      await drive.openFolder('ReynaCoot');
      expect(drive.path, ['ReynaCoot']);
      expect(names(), contains('SesionPrevia'));

      // Y volver a la raíz deja a la vista solo lo compartido.
      await drive.goUp();
      expect(names(), hasLength(2));
    });

    test('sin carpetas compartidas el cliente no ve NADA', () async {
      await drive.setSharedRoots(const [], isClient: true);

      expect(drive.scoped, isTrue);
      expect(drive.items, isEmpty);

      // Tampoco por ruta directa (p. ej. el enlace de un servicio viejo).
      await drive.openPath(const ['Privado']);
      expect(drive.path, isEmpty);
      expect(drive.items, isEmpty);
    });

    test('la ruta compartida se normaliza y se ve con SU nombre', () async {
      await drive.setSharedRoots(
        ['/ReynaCoot/SesionPrevia/', 'Cliente', 'Cliente'],
        isClient: true,
      );
      // `ReynaCoot/SesionPrevia` se ve como `SesionPrevia` (su carpeta: la
      // `ReynaCoot` del estudio es solo el camino, no se muestra).
      expect(drive.sharedRoots, ['SesionPrevia', 'Cliente']);
      expect(names(), hasLength(2));
      expect(names(), containsAll(['SesionPrevia', 'Cliente']));
      expect(names(), isNot(contains('ReynaCoot')));
    });

    test('una carpeta compartida ANIDADA se ve como SU carpeta, no como la '
        'carpeta del estudio que la contiene', () async {
      // Es el caso real: al cliente se le comparte `XV/ReynaCoot` y veía la
      // carpeta `XV` del estudio —con todo lo que hay dentro (las carpetas
      // anteriores, hasta la XV)— en vez de su carpeta.
      await Directory([root.path, 'XV'].join('/')).create(recursive: true);
      await Directory([root.path, 'XV', 'ReynaCoot'].join('/'))
          .create(recursive: true);
      await Directory([root.path, 'XV', 'Ana'].join('/')).create(
          recursive: true);
      await Directory([root.path, 'XV', 'ReynaCoot', 'Seleccion'].join('/'))
          .create(recursive: true);
      await drive.refresh();

      await drive.setSharedRoots(['XV/ReynaCoot'], isClient: true);

      // En SU raíz se ve UNA carpeta, con su nombre: nada de `XV`.
      expect(names(), ['ReynaCoot']);

      // Al abrirla se entra a la carpeta REAL (XV/ReynaCoot) y se ve su
      // contenido completo (no el de XV).
      await drive.openFolder('ReynaCoot');
      expect(drive.path, ['XV', 'ReynaCoot']);
      expect(names(), contains('Seleccion'));
      expect(names(), isNot(contains('Ana')),
          reason: 'la carpeta hermana del estudio no se ve');

      // Y para atrás se vuelve a SU raíz, nunca a la carpeta del estudio.
      await drive.goUp();
      expect(drive.path, isEmpty);
      expect(names(), ['ReynaCoot']);

      // Las migas tampoco muestran el camino hacia su carpeta.
      await drive.openPath(const ['XV', 'ReynaCoot', 'Seleccion']);
      expect(drive.hiddenPathPrefix, 1);
    });

    test('el cliente ve TODAS sus compartidas (de todos sus paquetes)',
        () async {
      await Directory([root.path, 'XV'].join('/')).create(recursive: true);
      await Directory([root.path, 'XV', 'ReynaCoot'].join('/'))
          .create(recursive: true);
      await drive.refresh();

      // Una anidada de un paquete y otra del primer nivel de otro paquete.
      await drive.setSharedRoots(['XV/ReynaCoot', 'Cliente'], isClient: true);
      expect(names(), containsAll(['ReynaCoot', 'Cliente']));
      expect(names(), isNot(contains('XV')));
    });

    test('al dejar de compartir, el drive vuelve a mostrarse completo',
        () async {
      await drive.setSharedRoots(['ReynaCoot'], isClient: true);
      expect(names(), hasLength(1));

      await drive.setSharedRoots(const [], isClient: false);
      expect(drive.scoped, isFalse);
      expect(names(), hasLength(3));
    });
  });
}

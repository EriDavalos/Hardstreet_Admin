import 'package:flutter_test/flutter_test.dart';

import 'package:hardstreet_admin/app_constants.dart';
import 'package:hardstreet_admin/drive_base.dart';
import 'package:hardstreet_admin/hs_api.dart';

// ==================================================================
// FOTOS DEL DRIVE EN EL PANEL: ¿redimensionada o tal cual?
// ==================================================================
// El servidor del Drive es el ÚNICO que sabe entregar una versión reducida de
// una foto (`/thumb/<ruta>?w=N`). Las miniaturas del panel (módulo Sitio web,
// secciones y galerías) tienen que pedir ESA versión cuando la foto es del
// Drive interno —una original pesa varios MB y para un recuadro de 60 px no
// hace falta— y usar el enlace REAL cuando es de cualquier otro sitio (una foto
// externa, o una ruta del propio sitio como `images/…`).
// ==================================================================

void main() {
  group('URL de una foto para verla en el panel', () {
    test('una foto del Drive interno se pide REDIMENSIONADA', () {
      expect(
        driveImagePreview(
          'https://oriongo.ddns.net/files/XV/ReynaCoot.jpg',
          width: 320,
        ),
        'https://oriongo.ddns.net/thumb/XV/ReynaCoot.jpg?w=320',
      );
      // Con puerto: la miniatura se pide por RUTA (sin la query del archivo).
      // Sin sesión no se agrega token (aquí no hay ninguna).
      expect(
        driveImagePreview(
          'http://oriongo.ddns.net:4000/files/a/b.jpg?apikey=SECRETO',
          width: 160,
        ),
        'http://oriongo.ddns.net:4000/thumb/a/b.jpg?w=160',
      );
      // Las subcarpetas y los nombres raros (espacios, acentos) van enteros.
      expect(
        driveImagePreview('https://oriongo.ddns.net/files/XV Años/foto 1.jpg'),
        'https://oriongo.ddns.net/thumb/XV%20A%C3%B1os/foto%201.jpg?w=320',
      );
    });

    test('desde la red de casa el Drive también es interno', () {
      expect(
        driveImagePreview('http://192.168.1.70:4000/files/a/b.jpg'),
        'http://192.168.1.70:4000/thumb/a/b.jpg?w=320',
      );
      expect(
        driveImagePreview('http://localhost:4000/files/a/b.jpg', width: 100),
        'http://localhost:4000/thumb/a/b.jpg?w=100',
      );
    });

    test('el ancho queda dentro de lo razonable', () {
      expect(driveImagePreview('https://oriongo.ddns.net/files/a.jpg', width: 0),
          endsWith('?w=32'));
      expect(
          driveImagePreview('https://oriongo.ddns.net/files/a.jpg',
              width: 99999),
          endsWith('?w=2048'));
    });

    test('la miniatura lleva el token: el servidor sabe de qué EMPRESA es', () {
      addTearDown(() => HsSession.token = null);
      HsSession.token = 'jwt-de-prueba';
      expect(
        driveImagePreview(
          'https://oriongo.ddns.net/files/Boda/Ana.jpg',
          width: 640,
        ),
        'https://oriongo.ddns.net/thumb/Boda/Ana.jpg?w=640&apikey=jwt-de-prueba',
        reason:
            'sin el token, /thumb busca la foto en la RAÍZ y la portada de la '
            'categoría/paquete sale en blanco',
      );
    });

    test('cualquier OTRO enlace se usa tal cual', () {
      // Una foto de fuera, aunque su ruta lleve `/files/`.
      const deFuera = 'https://otro.com/files/foto.jpg';
      expect(driveImagePreview(deFuera), deFuera);
      expect(isDriveImageUrl(deFuera), isFalse);
      // Una foto del propio sitio y un valor vacío: no hay miniatura que pedir.
      expect(driveImagePreview('images/banner.jpg'), 'images/banner.jpg');
      expect(driveImagePreview(''), '');
      // El host del Drive sin `/files/` no es una foto del Drive.
      expect(
        driveImagePreview('https://oriongo.ddns.net/api/space'),
        'https://oriongo.ddns.net/api/space',
      );
    });

    test('el host interno es el configurado en la app', () {
      expect(AppConstants.apiBase, contains('oriongo.ddns.net'),
          reason: 'por defecto el Drive es oriongo.ddns.net');
      expect(isDriveImageUrl('${AppConstants.apiBase}/files/XV/a.jpg'), isTrue);
    });
  });
}

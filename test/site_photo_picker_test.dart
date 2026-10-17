import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/drive_api_service.dart';
import 'package:hardstreet_admin/drive_scope.dart';
import 'package:hardstreet_admin/pages/site_page.dart';
import 'package:hardstreet_admin/web_content.dart';
import 'package:hardstreet_admin/widgets/drive_thumb.dart';

// ==================================================================
// SELECTOR DE FOTOS DEL MÓDULO SITIO WEB
// ==================================================================
// El Sitio web usa el MISMO selector de fotos que los demás módulos
// (`widgets/drive_photo_picker.dart`): rejilla con miniatura, vista previa y
// contador. Navega SU PROPIA carpeta sin mover el drive (el módulo Archivos
// sigue en la suya) y la miniatura se pide con ESA carpeta: si se pidiera con la
// del módulo Archivos, dentro de una subcarpeta apuntaría a otro archivo (404) y
// el recuadro saldría vacío.
// ==================================================================

/// Drive del servidor con un cliente HTTP falso: el árbol XV/ReynaCoot.jpg y
/// nada más. El módulo Archivos, de fondo, está en OTRA carpeta (así se
/// comprueba que la miniatura no sale de la carpeta que el drive tenga abierta).
DriveApiService _remoteDrive() {
  DriveApiService.client = MockClient((request) async {
    final p = request.url.queryParameters['path'] ?? '';
    final folders = <Map<String, dynamic>>[
      if (request.url.path == '/api/drive' && p == '')
        {'name': 'XV', 'isFolder': true, 'childCount': 1},
      if (request.url.path == '/api/drive' && p == 'XV')
        {'name': 'ReynaCoot.jpg', 'isFolder': false, 'size': 12},
    ];
    return http.Response(
      jsonEncode({'folders': folders}),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  final drive = DriveApiService(baseUrl: 'https://drive.test');
  drive.path = const ['Otra'];
  return drive;
}

/// Doble del contenido del sitio: sin nada guardado, sin categorías.
class _FakeSiteApi implements SiteContentApi {
  @override
  Future<SiteContent> load() async => SiteContent.empty;

  @override
  Future<void> save(SiteContent content) async {}

  @override
  Future<SiteContext> context() async =>
      const SiteContext(categories: [], gold: '#C9A96E', stored: true);
}

void main() {
  group('selector de fotos del sitio', () {
    Future<DriveApiService> pumpPicker(
      WidgetTester tester, {
      Size size = const Size(1500, 4000),
    }) async {
      final drive = _remoteDrive();
      addTearDown(() => DriveApiService.client = http.Client());
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        DriveScope(
          drive: drive,
          child: MaterialApp(
            home: Scaffold(
              body: SitePage(api: _FakeSiteApi(), supported: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return drive;
    }

    /// Abre el selector de fotos de la sección Portada (su imagen de fondo).
    ///
    /// Las dos cosas que se tocan ("Editar" y el botón de la foto) pueden
    /// quedar fuera de la ventana en una pantalla baja: se llevan a la vista
    /// antes del toque, como haría el usuario al desplazarse.
    Future<void> openPicker(WidgetTester tester) async {
      final card = find.byKey(const ValueKey('site-section-hero'));
      final edit = find.descendant(of: card, matching: find.text('Editar'));
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();
      final pick = find.descendant(
          of: card, matching: find.byTooltip('Elegir una foto del Drive'));
      await tester.ensureVisible(pick);
      await tester.pumpAndSettle();
      await tester.tap(pick);
      await tester.pumpAndSettle();
    }

    /// Entra a la carpeta XV dentro del selector.
    Future<void> enterXV(WidgetTester tester) async {
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('XV')));
      await tester.pumpAndSettle();
    }

    testWidgets('dentro de una carpeta la miniatura es la de ESA carpeta',
        (tester) async {
      await pumpPicker(tester);
      await openPicker(tester);

      // La raíz del Drive: la carpeta, y ya.
      expect(find.text('Fotos del Drive'), findsOneWidget);
      expect(find.text('XV'), findsWidgets);

      // Se entra a XV: la foto se ve con su miniatura (del servidor, con la
      // carpeta en la que está de verdad).
      await enterXV(tester);

      final thumb = tester.widget<DriveThumb>(find.byType(DriveThumb));
      expect(thumb.source, contains('/thumb/XV/ReynaCoot.jpg'),
          reason: 'la miniatura tiene que ser la de la carpeta que se está '
              'viendo, no la que tenga abierta el módulo Archivos');
      expect(thumb.source, isNot(contains('Otra')));
      expect(thumb.isRemote, isTrue,
          reason: 'el drive del servidor se pinta como imagen remota');
      expect(thumb.big, isTrue,
          reason: 'la cuadrícula muestra la miniatura en grande, no una fila '
              'de lista');
      expect(tester.takeException(), isNull);
    });

    testWidgets('el selector entra en una ventana normal del panel',
        (tester) async {
      await pumpPicker(tester, size: const Size(1024, 720));
      await openPicker(tester);
      await enterXV(tester);

      expect(find.byKey(const ValueKey('drive-photo-ReynaCoot.jpg')),
          findsOneWidget);
      // Dentro de XV ya no hay subcarpetas que mostrar.
      expect(find.byIcon(Icons.folder_rounded), findsNothing);
      expect(find.text('Esta carpeta no tiene fotos.'), findsNothing);
      // Sin desbordes ni errores de "layout" en la ventana de verdad.
      expect(tester.takeException(), isNull);
    });

    testWidgets('la foto se previsualiza en grande desde su propio botón',
        (tester) async {
      await pumpPicker(tester);
      await openPicker(tester);
      await enterXV(tester);

      // El botón de previsualizar abre la foto en grande (la versión reducida
      // del servidor) sin salir del selector.
      await tester.tap(find.byKey(
          const ValueKey('drive-photo-preview-ReynaCoot.jpg')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('drive-photo-preview-image')),
          findsOneWidget);
      final big = tester.widget<DriveThumb>(
          find.byKey(const ValueKey('drive-photo-preview-image')));
      expect(big.source, contains('/thumb/XV/ReynaCoot.jpg'));
      expect(big.contain, isTrue, reason: 'en el visor la foto no se recorta');

      // Desde ahí mismo se elige la foto…
      await tester.tap(find.text('Elegir esta foto'));
      await tester.pumpAndSettle();
      expect(find.text('Quitar'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('drive-photo-preview-close')));
      await tester.pumpAndSettle();

      // …y el selector ya la cuenta como elegida.
      expect(find.text('1 elegida'), findsOneWidget);
      await tester.tap(find.text('Usar estas fotos'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(
            TextField, 'https://oriongo.ddns.net/files/XV/ReynaCoot.jpg'),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('al agregar la foto se guarda su URL pública (sin token)',
        (tester) async {
      await pumpPicker(tester);
      await openPicker(tester);
      await enterXV(tester);

      await tester.tap(find.byKey(
          const ValueKey('drive-photo-ReynaCoot.jpg')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Usar estas fotos'));
      await tester.pumpAndSettle();

      // El campo de la imagen quedó con la ruta pública del archivo.
      expect(find.widgetWithText(TextField, 'https://oriongo.ddns.net/files/XV/ReynaCoot.jpg'),
          findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}

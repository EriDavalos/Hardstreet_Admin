import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/app_settings.dart';
import 'package:hardstreet_admin/drive_base.dart';
import 'package:hardstreet_admin/drive_scope.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/local_share_agent.dart';
import 'package:hardstreet_admin/local_share_service.dart';
import 'package:hardstreet_admin/pages/shared_files_page.dart';

/// Drive de prueba: un árbol fijo para el selector de carpetas.
class _FakeDrive extends DriveBase {
  @override
  Future<void> refresh() async {}

  @override
  Future<List<String>> listChildFolders(List<String> rel) async {
    if (rel.isEmpty) return const ['Bodas', 'XV Años'];
    if (rel.length == 1 && rel.first == 'Bodas') {
      return const ['Ana Ruiz', 'Luis Gómez'];
    }
    return const <String>[];
  }

  @override
  List<String> listFolders(List<String> rel) => const <String>[];

  @override
  String absolutePathOf(DriveItem item) => [...path, item.name].join('/');

  @override
  Future<int> uploadFromPaths(
    List<String> sources, {
    bool overwrite = false,
  }) async => 0;

  @override
  Future<void> createFolder(String name) async {}

  @override
  Future<void> rename(DriveItem item, String newName) async {}

  @override
  Future<void> delete(DriveItem item) async {}

  @override
  Future<({int moved, List<String> errors})> moveItems(
    List<String> names,
    List<String> targetPath,
  ) async => (moved: 0, errors: const <String>[]);

  @override
  Future<({int copied, List<String> errors})> copyItems(
    List<String> names,
    List<String> targetPath,
  ) async => (copied: 0, errors: const <String>[]);

  @override
  Future<({int deleted, List<String> errors})> deleteItems(
    List<String> names,
  ) async => (deleted: 0, errors: const <String>[]);

  @override
  Future<void> retryUpload(String jobId) async {}
}

/// Instala un backend falso del módulo y devuelve las peticiones recibidas.
List<Map<String, dynamic>> _installMock({
  List<Map<String, dynamic>>? shared,
  List<Map<String, dynamic>>? received,
  List<Map<String, dynamic>>? candidates,
  List<int> targets = const [],
}) {
  final calls = <Map<String, dynamic>>[];
  final sharedList =
      shared ??
      [
        {
          'id': 1,
          'ownerId': 3,
          'ownerName': 'Yusef Ali',
          'targetId': 4,
          'targetName': 'Marta Soto',
          'path': 'Bodas/Ana Ruiz',
          'created': '2026-10-14T10:00:00',
        },
      ];
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    if (request.url.path.endsWith('/api/admin/shared-files')) {
      if (request.method == 'GET') {
        final folder = request.url.queryParameters['folder'];
        if (folder != null && folder.isNotEmpty) {
          return http.Response(
            jsonEncode({
              'ok': true,
              'item': {
                'path': folder,
                'targets': [
                  for (final id in targets)
                    {'id': id, 'name': 'Usuario $id', 'shareId': id},
                ],
              },
              'candidates': candidates ?? _defaultCandidates,
              'canShare': true,
              'canDelete': true,
            }),
            200,
            headers: headers,
          );
        }
        return http.Response(
          jsonEncode({
            'ok': true,
            'item': {
              'shared': sharedList,
              'received': received ?? _defaultReceived,
              'candidates': candidates ?? _defaultCandidates,
            },
            'canShare': true,
            'canDelete': true,
          }),
          200,
          headers: headers,
        );
      }
      final body = (jsonDecode(request.body) as Map).cast<String, dynamic>();
      calls.add({'method': request.method, ...body});
      return http.Response(
        jsonEncode({'ok': true, 'message': 'Listo', 'item': null}),
        request.method == 'POST' ? 201 : 200,
        headers: headers,
      );
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
  return calls;
}

/// Servidor del DRIVE falso: responde SOLO /api/local/list con un árbol fijo.
class _DriveMock {
  final called = <String>[];

  LocalShareService service() => LocalShareService(
    baseUrl: 'http://drive.test',
    client: MockClient((request) async {
      called.add(request.url.path);
      final path = request.url.queryParameters['path'] ?? '';
      Map<String, dynamic> body;
      switch (path) {
        case '':
          body = {
            'local': true,
            'path': '',
            'folders': [
              {'name': 'Bodas', 'isFolder': true},
              {'name': 'foto.jpg', 'isFolder': false, 'size': 1024},
            ],
          };
          break;
        case 'Bodas':
          body = {
            'local': true,
            'path': 'Bodas',
            'folders': [
              {'name': 'Ana', 'isFolder': true},
            ],
          };
          break;
        default:
          body = {'local': true, 'path': path, 'folders': const []};
      }
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

const _defaultCandidates = [
  {
    'id': 4,
    'name': 'Marta Soto',
    'email': 'marta@x.com',
    'role': 'Colaborador',
  },
  {'id': 5, 'name': 'Ana Ruiz', 'email': 'ana@x.com', 'role': 'Cliente'},
];

/// Lo RECIBIDO por defecto: una carpeta del DRIVE del dueño y una carpeta LOCAL
/// de su computadora. Las dos se navegan AQUÍ MISMO (el módulo nunca salta a
/// Archivos), así que las dos traen el [shareId] con el que se pide contenido.
const _defaultReceived = [
  {
    'shareId': 5,
    'path': 'Estudio 2026',
    'owners': [
      {'id': 9, 'name': 'Yusef Ali'},
    ],
  },
  {
    'shareId': 7,
    'path': r'D:\Eventos\2026',
    'local': true,
    'owners': [
      {'id': 9, 'name': 'Yusef Ali'},
    ],
  },
];

/// Monta el módulo y devuelve el drive falso: con él se comprueba que el
/// módulo NO mueve el Drive de la app (Archivos y Archivos compartidos no se
/// mezclan).
Future<_FakeDrive> _pump(
  WidgetTester tester, {
  Size size = const Size(1280, 900),
  _FakeDrive? drive,
}) async {
  final fake = drive ?? _FakeDrive();
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    DriveScope(
      drive: fake,
      child: const MaterialApp(home: Scaffold(body: SharedFilesPage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  return fake;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Texto DENTRO del diálogo abierto (los nombres también salen en las
/// tarjetas de la página, detrás).
Finder _inDialog(String text) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

void main() {
  setUp(() => HsApi.client = http.Client());
  tearDown(() async {
    HsApi.client = http.Client();
    debugPickLocalFolder = null;
    debugLocalShareService = null;
    // El servicio de compartir es un SINGLETON: si una prueba lo enciende, la
    // siguiente no puede heredarlo encendido (ni la preferencia guardada).
    LocalShareAgent.instance.stop();
    await LocalShareAgent.instance.setManual(false);
  });

  testWidgets('el diseño es el del Drive: buscador, vista y cuadrícula', (
    tester,
  ) async {
    _installMock();
    await _pump(tester);

    expect(find.text('Archivos compartidos'), findsOneWidget);
    // Encabezado con buscador y conmutador de vista, como el Drive.
    expect(find.text('Buscar carpeta o persona'), findsOneWidget);
    expect(find.byTooltip('Vista de lista'), findsOneWidget);
    // Barra de estado del Drive: "N carpetas" y "N personas".
    expect(find.textContaining('carpetas'), findsWidgets);
    expect(find.textContaining('persona'), findsWidgets);
    // Las dos secciones del módulo.
    expect(find.textContaining('Compartido conmigo'), findsOneWidget);
    expect(find.textContaining('Lo que comparto'), findsOneWidget);
    // Las carpetas recibidas, con quién las comparte.
    expect(find.text('Estudio 2026'), findsOneWidget);
    expect(find.textContaining('Compartida por Yusef Ali'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin nada compartido invita a compartir una carpeta', (
    tester,
  ) async {
    _installMock(shared: const [], received: const []);
    await _pump(tester);

    expect(find.text('Nadie te ha compartido carpetas'), findsOneWidget);
    await _tap(tester, find.textContaining('Lo que comparto'));
    expect(find.text('Todavía no compartes carpetas'), findsOneWidget);
    expect(find.text('Compartir carpeta'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en la computadora un clic MARCA la carpeta y el doble clic '
      'entra', (tester) async {
    final mock = _DriveMock();
    debugLocalShareService = mock.service;
    _installMock();
    await _pump(tester);

    // Un clic con el RATÓN deja la carpeta marcada, sin entrar (como el
    // explorador de Windows); el segundo clic seguido entra.
    await tester.tap(find.text('Estudio 2026'), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('Bodas'), findsNothing, reason: 'un clic no entra');

    await tester.tap(find.text('Estudio 2026'), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Bodas'), findsOneWidget);
    expect(mock.called, contains('/api/local/list'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('la vista de lista muestra las mismas carpetas', (tester) async {
    _installMock();
    await _pump(tester);

    await _tap(tester, find.byTooltip('Vista de lista'));
    expect(find.text('Estudio 2026'), findsOneWidget);
    expect(find.text(r'D:\Eventos\2026'), findsOneWidget);
    expect(find.byTooltip('Vista de cuadrícula'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('comparte una CARPETA LOCAL de la computadora con varios '
      'usuarios', (tester) async {
    final calls = _installMock(shared: const [], received: const []);
    // El diálogo del sistema se simula: elige una carpeta del equipo.
    debugPickLocalFolder = () async => r'C:\Fotos\Bodas';
    await _pump(tester);

    await _tap(tester, find.text('Compartir carpeta').first);
    // La ruta LOCAL va directo al diálogo de usuarios (no se navega el Drive).
    expect(find.text(r'Compartir "C:\Fotos\Bodas"'), findsOneWidget);
    await _tap(tester, find.text('Marta Soto'));
    await _tap(tester, find.text('Ana Ruiz'));
    expect(find.text('2 seleccionados'), findsOneWidget);
    await _tap(tester, find.text('Guardar'));

    final posts = calls.where((c) => c['method'] == 'POST').toList();
    expect(posts, hasLength(1));
    expect(posts.first['path'], r'C:\Fotos\Bodas');
    expect((posts.first['userIds'] as List).toSet(), {4, 5});
  });

  testWidgets(
    'una carpeta LOCAL recibida se NAVEGA aquí mismo (solo lectura)',
    (tester) async {
      final mock = _DriveMock();
      debugLocalShareService = mock.service;
      _installMock();
      await _pump(tester);

      // Se abre la carpeta local desde su tarjeta.
      await _tap(tester, find.text(r'D:\Eventos\2026'));
      // Migas del Drive dentro de la carpeta.
      expect(find.text('Compartido conmigo'), findsWidgets);
      expect(find.text('Bodas'), findsOneWidget);
      expect(find.text('foto.jpg'), findsOneWidget);
      // SOLO LECTURA: no hay acciones de escritura en ninguna parte. Lo único
      // que se puede hacer (además de ver) es DESCARGAR.
      expect(find.byTooltip('Nueva carpeta'), findsNothing);
      await _tap(tester, find.byTooltip('Opciones').last);
      expect(find.text('Ver'), findsOneWidget);
      expect(find.text('Descargar'), findsOneWidget);
      expect(find.text('Renombrar'), findsNothing);
      expect(find.text('Eliminar'), findsNothing);
      // Se cierra el menú para poder seguir navegando.
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      expect(mock.called, contains('/api/local/list'));

      // Se entra a la subcarpeta: se pide al servidor del DRIVE con la subruta.
      await _tap(tester, find.text('Bodas'));
      expect(find.text('Ana'), findsOneWidget);

      // Y se vuelve con las migas de pan.
      await _tap(tester, find.text('Compartido conmigo').last);
      expect(find.text('Estudio 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('una carpeta recibida del DRIVE se navega AQUÍ MISMO (sin '
      'saltar al módulo Archivos)', (tester) async {
    final mock = _DriveMock();
    debugLocalShareService = mock.service;
    _installMock();
    final drive = await _pump(tester);

    // Se abre la carpeta DEL DRIVE desde su tarjeta.
    await _tap(tester, find.text('Estudio 2026'));
    // Su contenido se ve dentro de "Archivos compartidos": no hay aviso de
    // abrirla en Archivos ni se mueve el Drive de la app.
    expect(find.text('Esta carpeta vive en el Drive'), findsNothing);
    expect(find.text('Bodas'), findsOneWidget);
    expect(find.text('foto.jpg'), findsOneWidget);
    expect(drive.path, isEmpty);
    expect(mock.called, contains('/api/local/list'));

    // Se entra a la subcarpeta (la ruta va con la subruta al servidor).
    await _tap(tester, find.text('Bodas'));
    expect(find.text('Ana'), findsOneWidget);

    // Y se vuelve con las migas de pan al listado del módulo.
    await _tap(tester, find.text('Compartido conmigo').last);
    expect(find.text('Estudio 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dentro de la carpeta NO se separa en CARPETAS e IMÁGENES: se '
      'muestran como en el Drive, en una sola cuadrícula', (tester) async {
    final mock = _DriveMock();
    debugLocalShareService = mock.service;
    _installMock();
    await _pump(tester);

    await _tap(tester, find.text('Estudio 2026'));

    // Las carpetas y las fotos están en la MISMA cuadrícula (un solo
    // GridView) y en el orden que manda el servidor: carpetas y luego fotos.
    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('Bodas'), findsOneWidget);
    expect(find.text('foto.jpg'), findsOneWidget);
    // Y NO hay rótulos de grupo: el Drive no los pone.
    expect(find.text('CARPETAS'), findsNothing);
    expect(find.text('IMÁGENES'), findsNothing);
    expect(find.text('IMAGEN'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('una respuesta que llega TARDE no pinta el compartido que ya '
      'dejaste', (tester) async {
    // La carpeta del Drive (share=5) responde medio segundo después; la otra
    // (share=7) responde al instante.
    debugLocalShareService = () => LocalShareService(
      baseUrl: 'http://drive.test',
      client: MockClient((request) async {
        final share = request.url.queryParameters['share'];
        if (share == '5') {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          return http.Response(
            jsonEncode({
              'local': true,
              'path': '',
              'folders': [
                {'name': 'TARDIA', 'isFolder': true},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'local': true,
            'path': '',
            'folders': [
              {'name': 'RAPIDA', 'isFolder': true},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    _installMock();
    await _pump(tester);

    // Se abre la lenta y, SIN esperarla, se vuelve y se abre la otra.
    await tester.tap(find.text('Estudio 2026'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(
      find.textContaining('Compartido conmigo').last,
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.tap(find.text(r'D:\Eventos\2026'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('RAPIDA'), findsOneWidget);

    // Llega la respuesta vieja: se descarta, no se pinta en esta carpeta.
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('TARDIA'), findsNothing);
    expect(find.text('RAPIDA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('si el servidor no puede abrir una carpeta de la COMPUTADORA '
      'lo explica', (tester) async {
    // El servidor del drive es otro equipo (o la carpeta se movió): se dice
    // POR QUÉ no se ve, en vez de dejar la calle sin salida.
    debugLocalShareService = () => LocalShareService(
      baseUrl: 'http://drive.test',
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'error':
                'La carpeta no existe (ni en el Drive ni en la '
                'computadora de quien la compartió)',
          }),
          404,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    _installMock();
    await _pump(tester);

    await _tap(tester, find.text(r'D:\Eventos\2026'));
    // El mensaje del SERVIDOR se muestra tal cual (no un "HTTP 404").
    expect(
      find.textContaining('computadora de quien la compartió'),
      findsWidgets,
    );
    // Y se explica qué hace falta para poder verla: la carpeta la sirve la app
    // del dueño (el servidor solo hace de puente), así que se nombra eso y no
    // que "el servidor tiene que poder abrirla".
    expect(find.textContaining('la sirve SU aplicación'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lo que comparto: la ficha y las cuatro acciones salen EN EL '
      'LISTADO (no dentro de la carpeta)', (tester) async {
    final mock = _DriveMock();
    debugLocalShareService = mock.service;
    final calls = _installMock(targets: const [4]);
    final drive = await _pump(tester);

    await _tap(tester, find.textContaining('Lo que comparto'));
    expect(find.text('Bodas/Ana Ruiz'), findsOneWidget);
    // La ficha del compartido (de dónde es y con quién) vive en la tarjeta.
    expect(find.text('Carpeta de tu Drive'), findsOneWidget);
    expect(find.textContaining('Con Marta Soto'), findsOneWidget);

    // El menú de la tarjeta dice qué se puede hacer: Ver, Descargar, Editar y
    // Eliminar (las mismas acciones del Drive).
    await _tap(tester, find.byTooltip('Opciones').first);
    expect(find.text('Ver el contenido'), findsOneWidget);
    expect(find.text('Descargar'), findsOneWidget);
    expect(find.text('Editar destinatarios'), findsOneWidget);
    expect(find.text('Eliminar el compartido'), findsOneWidget);

    // Editar: sumar y quitar usuarios.
    await _tap(tester, find.text('Editar destinatarios'));
    expect(find.text('1 seleccionado'), findsOneWidget);
    await _tap(tester, _inDialog('Ana Ruiz'));
    expect(find.text('2 seleccionados'), findsOneWidget);
    await _tap(tester, _inDialog('Marta Soto'));
    expect(find.text('1 seleccionado'), findsOneWidget);
    await _tap(tester, _inDialog('Guardar'));

    final posts = calls.where((c) => c['method'] == 'POST').toList();
    expect(posts, hasLength(1));
    expect(posts.first['userIds'], [5]);
    final dels = calls.where((c) => c['method'] == 'DELETE').toList();
    expect(dels, hasLength(1));
    expect(dels.first['userIds'], [4]);

    // Y la carpeta se abre AQUÍ MISMO (sin saltar a Archivos) y sin repetir la
    // ficha: dentro solo se ve el contenido.
    await _tap(tester, find.text('Bodas/Ana Ruiz'));
    expect(find.text('Bodas'), findsOneWidget);
    expect(drive.path, isEmpty);
    expect(find.text('Verla en Archivos'), findsNothing);
    expect(find.text('Carpeta de tu Drive'), findsNothing);
  });

  testWidgets('dejar de compartir se pide desde el menú de la tarjeta', (
    tester,
  ) async {
    debugLocalShareService = _DriveMock().service;
    final calls = _installMock();
    await _pump(tester);

    await _tap(tester, find.textContaining('Lo que comparto'));
    await _tap(tester, find.byTooltip('Opciones').first);
    await _tap(tester, find.text('Eliminar el compartido'));
    expect(find.text('¿Dejar de compartir?'), findsOneWidget);
    await _tap(tester, find.text('Dejar de compartir').last);

    final dels = calls.where((c) => c['method'] == 'DELETE').toList();
    expect(dels, hasLength(1));
    expect(dels.first['path'], 'Bodas/Ana Ruiz');
    expect((dels.first['userIds'] as List), contains(4));
  });

  testWidgets('Descargar una carpeta compartida pide su contenido (y si '
      'falla lo avisa sin caerse)', (tester) async {
    // El menú de la tarjeta descarga la CARPETA entera: se recorre su
    // contenido para armar el ZIP. Si el servidor no puede abrirla, se avisa
    // —no se deja un botón que no hace nada—.
    final asked = <String>[];
    debugLocalShareService = () => LocalShareService(
      baseUrl: 'http://drive.test',
      client: MockClient((request) async {
        asked.add(request.url.path);
        if (request.url.path == '/api/local/status') {
          return http.Response(
            jsonEncode({'local': true, 'db': true, 'servedFrom': 'server'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'error': 'La carpeta no existe'}),
          404,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    _installMock();
    await _pump(tester);

    await _tap(tester, find.byTooltip('Opciones').first);
    await _tap(tester, find.text('Descargar'));
    expect(asked, contains('/api/local/list'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('la ficha de cada compartido se ve en el listado (cuadrícula y '
      'lista) y no al abrir la carpeta', (tester) async {
    debugLocalShareService = _DriveMock().service;
    _installMock();
    await _pump(tester);

    // Cuadrícula: cada carpeta dice de dónde es.
    expect(find.text('Carpeta del Drive'), findsOneWidget);
    expect(find.text('Carpeta de su computadora'), findsOneWidget);

    // Y en la vista de lista también (la de "Lo que comparto" dice "tuya").
    await _tap(tester, find.byTooltip('Vista de lista'));
    expect(find.text('Carpeta del Drive'), findsOneWidget);
    expect(find.text('Carpeta de su computadora'), findsOneWidget);
    await _tap(tester, find.textContaining('Lo que comparto'));
    expect(find.text('Carpeta de tu Drive'), findsOneWidget);

    // Al abrir la carpeta, la ficha se queda en el listado.
    await _tap(tester, find.textContaining('Compartido conmigo'));
    await _tap(tester, find.text('Estudio 2026'));
    expect(find.text('Carpeta del Drive'), findsNothing);
    expect(find.text('Carpeta de su computadora'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dentro de la carpeta la vista de LISTA es la del Drive', (
    tester,
  ) async {
    final mock = _DriveMock();
    debugLocalShareService = mock.service;
    _installMock();
    await _pump(tester);

    // Se conmuta a lista ANTES de entrar: dentro también se respeta.
    await _tap(tester, find.byTooltip('Vista de lista'));
    await _tap(tester, find.text('Estudio 2026'));

    // Las MISMAS filas del Drive: nombre, peso y el menú de lo que se puede
    // hacer con cada elemento (ver y descargar).
    expect(find.byType(GridView), findsNothing);
    expect(find.text('Bodas'), findsOneWidget);
    expect(find.text('foto.jpg'), findsOneWidget);
    expect(find.text('Carpeta'), findsOneWidget);
    // La fila de la FOTO es la que ofrece Descargar (una carpeta compartida de
    // otra persona es de solo lectura: ahí solo se puede ver).
    await _tap(tester, find.byTooltip('Opciones').last);
    expect(find.text('Ver'), findsOneWidget);
    expect(find.text('Descargar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('el ZIP de una carpeta compartida recorre sus subcarpetas', () async {
    // El servidor solo entrega archivo por archivo: la app recorre la carpeta
    // (y sus subcarpetas) y arma el ZIP. Aquí se comprueba esa travesía.
    final asked = <String>[];
    final service = LocalShareService(
      baseUrl: 'http://drive.test',
      client: MockClient((request) async {
        asked.add(request.url.path);
        if (request.url.path == '/api/local/list') {
          final sub = request.url.queryParameters['path'] ?? '';
          final folders = sub == ''
              ? [
                  {'name': 'Bodas', 'isFolder': true},
                  {'name': 'foto.jpg', 'isFolder': false, 'size': 4},
                ]
              : [
                  {'name': 'Ana.jpg', 'isFolder': false, 'size': 2},
                ];
          return http.Response(
            jsonEncode({'local': true, 'path': sub, 'folders': folders}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        // /api/local/file → los bytes de la imagen pedida.
        final name = (request.url.queryParameters['path'] ?? '')
            .split('/')
            .last;
        return http.Response.bytes(name == 'Ana.jpg' ? [9, 9] : [1, 2, 3], 200);
      }),
    );

    final bytes = await service.folderZipBytes(7, const []);
    final archive = ZipDecoder().decodeBytes(bytes);
    expect(asked.where((p) => p == '/api/local/list'), isNotEmpty);
    // Las subcarpetas viajan como carpetas, y cada foto con sus bytes.
    expect(
      archive.files.map((f) => f.name),
      containsAll(['Bodas/', 'Bodas/Ana.jpg', 'foto.jpg']),
    );
    final foto = archive.files.firstWhere((f) => f.name == 'foto.jpg');
    final ana = archive.files.firstWhere((f) => f.name == 'Bodas/Ana.jpg');
    expect(foto.isFile, isTrue);
    expect(foto.content, [1, 2, 3]);
    expect(ana.content, [9, 9]);
  });

  testWidgets('en el CELULAR el módulo se ve completo y sin desbordes', (
    tester,
  ) async {
    // Pantalla real de teléfono (390 lógicos): el módulo debe caber sin
    // "overflow" (los avisos amarillos/negros de RenderFlex harían fallar
    // `takeException`). El ancho lógico se fija con la vista del tester.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    _installMock();
    await _pump(tester, size: const Size(390, 844));

    expect(find.text('Archivos compartidos'), findsOneWidget);
    expect(find.text('Buscar carpeta o persona'), findsOneWidget);
    expect(find.byTooltip('Vista de lista'), findsOneWidget);
    // En el celular las acciones van como botones de imagen… pero NO hay
    // botón de recargar: se recarga deslizando hacia abajo (RefreshIndicator),
    // como en el resto de los módulos.
    expect(find.byTooltip('Actualizar'), findsNothing);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    // Y las carpetas recibidas siguen a la vista.
    expect(find.text('Estudio 2026'), findsOneWidget);
    expect(find.text(r'D:\Eventos\2026'), findsOneWidget);

    // La vista de lista también cabe.
    await _tap(tester, find.byTooltip('Vista de lista'));
    expect(tester.takeException(), isNull);

    // El switch del servicio sigue a mano, en botón de imagen (la tarjeta
    // completa no cabe en un teléfono).
    final agent = LocalShareAgent.instance;
    agent.client = MockClient(
      (_) async => throw http.ClientException('sin red'),
    );
    agent.retryDelay = const Duration(seconds: 5);
    final sw = find.byKey(const ValueKey('share-service-switch-compact'));
    expect(sw, findsOneWidget);

    await _tap(tester, sw);
    expect(
      agent.manualOn,
      isTrue,
      reason: 'desde el celular también se enciende',
    );

    // Y se apaga otra vez: así el servicio no deja nada colgando al terminar.
    await _tap(tester, sw);
    expect(agent.manualOn, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el buscador filtra las carpetas', (tester) async {
    _installMock();
    await _pump(tester);

    await tester.enterText(find.byType(TextField).first, 'eventos');
    await tester.pump();
    expect(find.text('Estudio 2026'), findsNothing);
    expect(find.text(r'D:\Eventos\2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('si el servidor falla ofrece reintentar', (tester) async {
    HsApi.client = MockClient(
      (request) async => http.Response(
        jsonEncode({'ok': false, 'message': 'Módulo no disponible'}),
        500,
        headers: {'content-type': 'application/json'},
      ),
    );
    await _pump(tester);

    expect(find.text('Módulo no disponible'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el listado MUESTRA de dónde se sirve cada carpeta', (
    tester,
  ) async {
    // El compartido 5 está en el servidor del drive (siempre disponible) y el
    // 7 en la computadora de su dueño con la app abierta: se dice en la
    // tarjeta, sin tener que abrirla para descubrirlo.
    debugLocalShareService = () => LocalShareService(
      baseUrl: 'http://drive.test',
      client: MockClient((request) async {
        if (request.url.path == '/api/local/status') {
          final share = request.url.queryParameters['share'];
          return http.Response(
            jsonEncode(
              share == '5'
                  ? {
                      'local': false,
                      'onServer': true,
                      'online': false,
                      'db': true,
                      'servedFrom': 'server',
                    }
                  : {
                      'local': true,
                      'onServer': false,
                      'online': true,
                      'db': true,
                      'servedFrom': 'agent',
                    },
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'local': true, 'path': '', 'folders': const []}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    _installMock();
    await _pump(tester);

    expect(find.text('Disponible'), findsOneWidget);
    expect(find.text('En línea'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('si el servidor del drive no tiene base de datos lo DICE', (
    tester,
  ) async {
    // Antes el módulo decía "la carpeta no existe" y mandaba a buscar el
    // problema al lugar equivocado: lo que falta es configurar DRIVE_DB.
    debugLocalShareService = () => LocalShareService(
      baseUrl: 'http://drive.test',
      client: MockClient((request) async {
        if (request.url.path == '/api/local/status') {
          return http.Response(
            jsonEncode({
              'local': false,
              'db': false,
              'servedFrom': 'unknown',
              'reason': 'no-db',
              'detail':
                  'El servidor del drive no tiene configurada la '
                  'base de datos (DRIVE_DB)',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('sin base de datos', 503);
      }),
    );
    _installMock();
    await _pump(tester);

    expect(find.text('Servidor sin base de datos'), findsWidgets);

    // Y al intentar abrirla se explica con el mismo detalle (no un "404").
    await _tap(tester, find.text(r'D:\Eventos\2026'));
    expect(find.textContaining('DRIVE_DB'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el switch enciende y apaga el SERVICIO de compartir', (
    tester,
  ) async {
    // Lo que pidió el usuario: un switch en el propio módulo para encender el
    // servicio que sirve las carpetas de ESTA computadora y que SIGA encendido
    // mientras la app esté abierta (no solo mientras se comparte algo).
    final agent = LocalShareAgent.instance;
    // Sin red en la prueba: el agente se queda esperando entre reintentos (sin
    // contestar a nadie) mientras se comprueba el switch.
    agent.client = MockClient(
      (_) async => throw http.ClientException('sin red'),
    );
    agent.retryDelay = const Duration(seconds: 5);
    addTearDown(() async {
      await agent.setManual(false);
      agent.stop();
    });

    _installMock();
    await _pump(tester);

    final card = find.byKey(const ValueKey('share-service-card'));
    expect(card, findsOneWidget);
    expect(find.text('Servicio de compartir'), findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('Apagado')),
      findsOneWidget,
    );
    expect(agent.manualOn, isFalse);

    // Se enciende: queda anotado que el servicio va encendido.
    await _tap(
      tester,
      find.descendant(of: card, matching: find.byType(Switch)),
    );

    expect(agent.manualOn, isTrue);
    expect(AppSettings.instance.shareServing, isTrue);

    // El servicio quedó ENCENDIDO: sirviendo ahora mismo.
    expect(agent.running, isTrue);
    expect(agent.serving.value, isTrue);
    expect(
      find.descendant(of: card, matching: find.text('Encendido')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Switch>(
            find.descendant(of: card, matching: find.byType(Switch)),
          )
          .value,
      isTrue,
    );

    // Y se apaga desde el switch: deja de servir sus carpetas, y se recuerda
    // apagado (el servicio no se enciende solo al volver a abrir la app).
    await _tap(
      tester,
      find.descendant(of: card, matching: find.byType(Switch)),
    );

    expect(agent.manualOn, isFalse);
    expect(agent.serving.value, isFalse);
    expect(AppSettings.instance.shareServing, isFalse);
    expect(
      find.descendant(of: card, matching: find.text('Apagado')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin soporte (navegador/celular) el switch se DESHABILITA y '
      'dice por qué', (tester) async {
    // El navegador (y el celular) no pueden leer el disco de la computadora:
    // antes el switch se dejaba tocar y no hacía nada —parecía roto—; ahora va
    // deshabilitado y la tarjeta explica qué hacer.
    final agent = LocalShareAgent.instance;
    agent.debugSupported = false;
    agent.client = MockClient(
      (_) async => throw http.ClientException('sin red'),
    );
    addTearDown(() async {
      agent.stop();
      agent.debugSupported = null;
    });

    _installMock();
    await _pump(tester);

    final card = find.byKey(const ValueKey('share-service-card'));
    expect(card, findsOneWidget);
    final sw = tester.widget<Switch>(
      find.descendant(of: card, matching: find.byType(Switch)),
    );
    expect(sw.onChanged, isNull, reason: 'no se puede encender desde aquí');
    expect(sw.value, isFalse);
    // Y la salida concreta, en la propia tarjeta.
    expect(
      find.textContaining('no se pueden servir carpetas de esta computadora'),
      findsWidgets,
    );
    expect(find.textContaining('app de escritorio'), findsWidgets);
    expect(agent.problem.value, ShareProblem.unsupported);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un servidor viejo que dice "ya no está activa" también se '
      'explica', (tester) async {
    // El servidor del drive todavía sin actualizar contesta 404 con "La carpeta
    // compartida no existe o ya no está activa" (el compartido se dio de baja).
    // Antes ese texto se mostraba crudo; ahora se dice QUÉ pasó y qué hacer.
    debugLocalShareService = () => LocalShareService(
      baseUrl: 'http://drive.test',
      client: MockClient((request) async {
        if (request.url.path == '/api/local/status') {
          return http.Response(
            jsonEncode({
              'error': 'La carpeta compartida no existe o ya no está activa',
            }),
            404,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('no encontrado', 404);
      }),
    );
    _installMock();
    await _pump(tester);

    // En la tarjeta se ve el estado, no un error de red.
    expect(find.text('Ya no está compartida'), findsWidgets);

    // Y al abrirla se abre el motivo que dio el servidor.
    await _tap(tester, find.text('Estudio 2026'));
    expect(find.textContaining('ya no está activa'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hardstreet_admin/drive_base.dart';
import 'package:hardstreet_admin/drive_scope.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/pages/companies_page.dart';

// ==================================================================
// EMPRESAS: el Superadministrador ve cada empresa con su carpeta raíz,
// sus administradores y sus conteos, y puede elegir con cuál trabaja.
// ==================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, dynamic>> requested;

  void installMock() {
    requested = [];
    HsApi.client = MockClient((request) async {
      const headers = {'content-type': 'application/json'};
      final path = request.url.path;
      if (path.endsWith('/api/admin/companies') && request.method == 'GET') {
        requested.add({
          'company': request.headers['x-company-id'] ?? '',
        });
        return http.Response(
          jsonEncode({
            'ok': true,
            'companies': [
              {
                'id': 1,
                'name': 'Hardstreet',
                'slug': 'hardstreet',
                'folderPath': '',
                'active': true,
                'users': 12,
                'clients': 9,
                'admins': [
                  {
                    'id': 1,
                    'name': 'Hardstreet Inc',
                    'email': 'admin@hardstreet.com',
                  },
                ],
              },
              {
                'id': 2,
                'name': 'Estudio Aurora',
                'slug': 'aurora',
                'folderPath': 'aurora',
                'active': true,
                'users': 3,
                'clients': 1,
                'admins': [
                  {
                    'id': 20,
                    'name': 'Ana Ruiz',
                    'email': 'ana@aurora.com',
                  },
                ],
              },
              {
                'id': 3,
                'name': 'Estudio Cerrado',
                'slug': 'cerrado',
                'folderPath': 'cerrado',
                'active': false,
                'users': 0,
                'clients': 0,
                'admins': <Map<String, dynamic>>[],
              },
            ],
          }),
          200,
          headers: headers,
        );
      }
      return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
    });
  }

  setUp(() {
    installMock();
    HsSession.token = 'token-de-prueba';
    HsSession.user = {
      'email': 'super@hardstreet.com',
      'role': 'Superadmin',
      'isSuperAdmin': true,
    };
    HsSession.activeCompanyId = 2;
  });

  tearDown(() {
    HsSession.clear();
  });

  testWidgets('muestra carpeta raíz, administradores y estado de cada empresa',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CompaniesPage())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hardstreet'), findsOneWidget);
    expect(find.text('Estudio Aurora'), findsOneWidget);
    // La primera empresa vive en la raíz del Drive; la segunda en su carpeta.
    expect(find.text('Drive (raíz)'), findsOneWidget);
    expect(find.text('Drive /aurora'), findsOneWidget);
    // Administradores y conteos.
    expect(find.textContaining('ana@aurora.com'), findsOneWidget);
    expect(find.text('3 usuarios'), findsOneWidget);
    // La inactiva se distingue y no ofrece "Trabajar aquí".
    expect(find.text('Inactiva'), findsOneWidget);
    expect(find.text('Sin administrador asignado'), findsOneWidget);
    // Marca de contexto sobre la empresa con la que se está trabajando.
    expect(find.text('Trabajando aquí'), findsOneWidget);
  });

  testWidgets('las peticiones llevan la empresa activa en X-Company-Id',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CompaniesPage())),
    );
    await tester.pumpAndSettle();

    expect(requested, isNotEmpty);
    expect(requested.first['company'], '2',
        reason: 'el backend recorta por la empresa activa del Superadmin');
  });

  testWidgets('"Trabajar aquí" cambia la empresa activa', (tester) async {
    HsSession.activeCompanyId = null;
    var changed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompaniesPage(onCompanyChanged: () => changed++),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Primera tarjeta (Hardstreet).
    await tester.tap(find.text('Trabajar aquí').first);
    await tester.pumpAndSettle();

    expect(HsSession.activeCompanyId, 1);
    expect(changed, 1, reason: 'el panel debe remontar el módulo actual');
  });

  testWidgets('la carpeta raíz se ELIGE navegando el Drive', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Como en la app: el DriveScope va POR ENCIMA de MaterialApp, así los
    // diálogos (que viven en el Navigator) también lo heredan.
    await tester.pumpWidget(
      DriveScope(
        drive: _TestDrive(),
        child: const MaterialApp(home: Scaffold(body: CompaniesPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nueva empresa'));
    await tester.pumpAndSettle();

    // El formulario ya no obliga a escribir la carpeta a mano.
    final pick = find.text('Seleccionar carpeta del Drive');
    expect(pick, findsOneWidget);
    await tester.ensureVisible(pick);
    await tester.pumpAndSettle();
    await tester.tap(pick);
    await tester.pumpAndSettle();

    expect(find.text('Carpeta raíz de la empresa'), findsOneWidget);
    // Se navega a la carpeta que será la raíz de la empresa.
    await tester.tap(find.text('XV').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usar esta carpeta'));
    await tester.pumpAndSettle();

    // El campo queda con la carpeta elegida (relativa a la raíz del Drive).
    expect(find.text('XV'), findsOneWidget);
  });
}

/// Drive de prueba sin red: la raíz tiene la carpeta `XV`.
class _TestDrive extends DriveBase {
  @override
  Future<void> refresh() async {}

  @override
  Future<List<String>> listChildFolders(List<String> rel) async =>
      rel.isEmpty ? const <String>['XV'] : const <String>[];

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

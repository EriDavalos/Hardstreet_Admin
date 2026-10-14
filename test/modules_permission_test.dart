import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hardstreet_admin/drive_scope.dart';
import 'package:hardstreet_admin/drive_service.dart';
import 'package:hardstreet_admin/hs_access.dart';
import 'package:hardstreet_admin/hs_api.dart';
import 'package:hardstreet_admin/main.dart';

/// Módulos que reporta el servidor: los tres nuevos (Conexión, Configuraciones
/// y Reportes) MÁS los de siempre. "Reportes" y "Agendas" vienen con "Ver";
/// "Configuraciones" y "Conexión" sin ningún permiso.
Map<String, dynamic> _module(
  String key,
  String name,
  List<String> actions, {
  int order = 1,
}) =>
    {
      'key': key,
      'name': name,
      'order': order,
      'categoryKey': 'administration',
      'categoryName': 'Administración',
      'categoryOrder': 2,
      'actions': actions,
    };

void _installMock() {
  HsApi.client = MockClient((request) async {
    final headers = {'content-type': 'application/json'};
    final path = request.url.path;
    if (path.endsWith('/api/admin/permission')) {
      return http.Response(
        jsonEncode({
          'isAdmin': false,
          'modules': [
            _module('dashboard', 'Dashboard', ['read'], order: 1),
            _module('agendas', 'Agendas', ['read'], order: 4),
            _module('reports', 'Reportes', ['read'], order: 14),
            _module('settings', 'Configuraciones', const [], order: 13),
            _module('connection', 'Conexión', const [], order: 12),
          ],
        }),
        200,
        headers: headers,
      );
    }
    return http.Response(jsonEncode({'ok': true}), 200, headers: headers);
  });
}

void main() {
  testWidgets(
      'Conexión / Configuraciones / Reportes se rigen por el permiso "Ver"',
      (tester) async {
    late Directory tmp;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('hardstreet_modules_test');
    });
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final previous = HsApi.client;
    _installMock();
    addTearDown(() {
      HsApi.client = previous;
      HsAccess.reset();
    });
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      DriveScope(
        drive: DriveService.testRoot(tmp),
        child: MaterialApp(
          home: AdminHome(
            dark: false,
            onToggleTheme: () {},
            onLogout: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // El menú se arma con los permisos REALES del rol.
    expect(find.text('Reportes'), findsOneWidget,
        reason: 'tiene "Ver": el módulo aparece en el menú');
    expect(find.text('Conexión'), findsNothing,
        reason: 'sin "Ver" el módulo no se ofrece');
    expect(find.text('Configuraciones'), findsNothing,
        reason: 'sin "Ver" el módulo no se ofrece');
    // Los de siempre siguen igual (Agendas también vive en los accesos
    // rápidos del Dashboard, de ahí que se busque "al menos uno").
    expect(find.text('Agendas'), findsWidgets);

    await tester.runAsync(() async {
      tmp.deleteSync(recursive: true);
    });
  });
}

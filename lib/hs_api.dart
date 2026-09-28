// ==================================================================
// HARD STREET ADMIN - Cliente de la API Hardstreet (misma API que la web)
// Base: AppConstants.apiBase (Hardstreet-Backend, puerto 4000)
// Auth: header Authorization: Bearer <token> (igual que la web)
// ==================================================================
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_constants.dart';

/// Respuesta de GET /api/admin/meta.
class HsMeta {
  HsMeta({required this.modules, required this.permissions});

  /// [{ id, name, url, order, actions: [{ id, key, label }] }]
  final List<Map<String, dynamic>> modules;

  /// [{ id, key, label }]
  final List<Map<String, dynamic>> permissions;

  /// Parser TOLERANTE: acepta el formato nuevo (modules[] plano con
  /// actions[]) y el árbol viejo ({ tree: [{ label, children: [...] }] }).
  /// Así el modal de permisos funciona aunque el backend esté en otra
  /// versión (Vercel sin redeploy).
  static HsMeta fromJson(Map<String, dynamic> data) {
    final catalog = ((data['permissions'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();

    List<Map<String, dynamic>> raw;
    if (data['modules'] is List) {
      raw = (data['modules'] as List)
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    } else if (data['tree'] is List) {
      // Formato VIEJO: aplanar los grupos del árbol.
      final flat = <Map<String, dynamic>>[];
      for (final group in (data['tree'] as List)) {
        if (group is! Map) continue;
        for (final c in ((group['children'] as List?) ?? const [])) {
          if (c is Map) flat.add(c.cast<String, dynamic>());
        }
      }
      raw = flat;
    } else {
      raw = const [];
    }
    return HsMeta(modules: raw, permissions: catalog);
  }
}

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Sesión en memoria (el token vive mientras la app esté abierta).
class HsSession {
  static String? token;
  static Map<String, dynamic>? user;

  static bool get isLogged => token != null && token!.isNotEmpty;

  static String get displayName {
    final u = user ?? const {};
    final name = (u['name'] ?? '').toString();
    final lastname = (u['lastname'] ?? '').toString();
    final full = '$name $lastname'.trim();
    if (full.isNotEmpty) return full;
    return (u['email'] ?? '').toString();
  }

  static String get role => (user?['role'] ?? '').toString();

  static bool get isAdmin => role.toLowerCase() == 'admin';

  static void clear() {
    token = null;
    user = null;
  }
}

class HsApi {
  HsApi._();

  /// Callback global: se dispara cuando el servidor responde 401 con una
  /// sesión ya establecida (token expirado/inválido, p. ej. al abrir la app
  /// con "Recordarme" después de días). La app debe regresar al login.
  static void Function()? onUnauthorized;

  /// Base del CRUD: backend de Vercel (AppConstants.crudApiBase).
  /// Independiente del drive (AppConstants.apiBase / DRIVE_API).
  static String get base {
    var b = AppConstants.crudApiBase;
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return b;
  }

  static Uri _u(String path, [Map<String, String>? query]) =>
      Uri.parse('$base$path').replace(queryParameters: query);

  static Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        if (HsSession.isLogged) 'Authorization': 'Bearer ${HsSession.token}',
      };

  static Future<dynamic> _run(
    Future<http.Response> Function() fn, {
    int timeout = 20,
    String path = '',
  }) async {
    late http.Response r;
    try {
      r = await fn().timeout(Duration(seconds: timeout));
    } on TimeoutException {
      throw ApiException('El servidor tardó demasiado en responder');
    } catch (e) {
      throw ApiException('No hay conexión con el servidor ($base)');
    }
    dynamic body;
    try {
      body = jsonDecode(r.body);
    } catch (_) {
      body = null;
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      // Token expirado o inválido con sesión activa: avisar a la app para
      // regresar al login (NO aplica al propio intento de login).
      if (r.statusCode == 401 && path != '/api/auth/login') {
        HsSession.clear();
        onUnauthorized?.call();
      }
      final msg = (body is Map ? body['error'] : null)?.toString();
      throw ApiException(
        (msg == null || msg.isEmpty)
            ? 'Error HTTP ${r.statusCode}'
            : msg,
        statusCode: r.statusCode,
      );
    }
    return body;
  }

  static Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _run(() => http.get(_u(path, query), headers: _headers()), path: path);

  static Future<dynamic> post(String path, Map<String, dynamic> body) => _run(
        () => http.post(_u(path), headers: _headers(), body: jsonEncode(body)),
        path: path,
      );

  static Future<dynamic> put(String path, Map<String, dynamic> body) => _run(
        () => http.put(_u(path), headers: _headers(), body: jsonEncode(body)),
        path: path,
      );

  static Future<dynamic> delete(String path) =>
      _run(() => http.delete(_u(path), headers: _headers()), path: path);

  // ---------------- Auth ----------------

  /// Login real contra /api/auth/login (la misma que usa la web).
  static Future<Map<String, dynamic>> login(String email, String password) async {
    final data = await post('/api/auth/login', {'email': email, 'password': password});
    HsSession.token = (data['token'] ?? '').toString();
    HsSession.user = (data['user'] as Map?)?.cast<String, dynamic>();
    if (!HsSession.isLogged) throw ApiException('El servidor no devolvió token');
    return HsSession.user ?? const {};
  }

  static Future<void> logout() async {
    try {
      await post('/api/auth/logout', {});
    } catch (_) {
      // el logout del servidor es cortesía: el token se descarta igual
    }
    HsSession.clear();
  }

  // ---------------- Módulos (sidebar) ----------------

  static Future<List<Map<String, dynamic>>> modules() async {
    final data = await get('/api/modules');
    return ((data['modules'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  // ---------------- Usuarios ----------------

  static Future<List<Map<String, dynamic>>> adminUsers() async {
    final data = await get('/api/admin/users');
    return ((data['users'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  static Future<void> createUser(Map<String, dynamic> body) =>
      post('/api/admin/users', body);

  static Future<void> updateUser(Map<String, dynamic> body) =>
      put('/api/admin/users', body);

  static Future<void> deleteUser(int id) => delete('/api/admin/users?id=$id');

  // ---------------- Roles ----------------

  /// Cada rol: { id, name, permissions: [ { moduleId, permissionId } ] }
  static Future<List<Map<String, dynamic>>> roles() async {
    final data = await get('/api/admin/roles');
    return ((data['roles'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  static Future<void> createRole(Map<String, dynamic> body) =>
      post('/api/admin/roles', body);

  static Future<void> updateRole(Map<String, dynamic> body) =>
      put('/api/admin/roles', body);

  static Future<void> deleteRole(int id) => delete('/api/admin/roles?id=$id');

  /// Metadatos para el modal de permisos: módulos de la BD (sin submódulos)
  /// + catálogo de acciones. GET /api/admin/meta
  ///
  /// Compatibilidad: si un módulo llega SIN lista de acciones (backend viejo
  /// o módulo sin permisos asignados), hereda el catálogo completo de
  /// acciones para que el modal siempre muestre chips seleccionables.
  static Future<HsMeta> adminMeta() async {
    final data = (await get('/api/admin/meta') as Map?) ?? const {};
    final meta = HsMeta.fromJson(data.cast<String, dynamic>());
    final catalog = meta.permissions;
    final modules = [
      for (final m in meta.modules)
        if (((m['actions'] as List?) ?? const []).isEmpty && catalog.isNotEmpty)
          {...m, 'actions': catalog}
        else
          m,
    ];
    return HsMeta(modules: modules, permissions: meta.permissions);
  }

  // ---------------- Clientes ----------------

  static Future<List<Map<String, dynamic>>> clients() async {
    final data = await get('/api/admin/clients');
    return ((data['clients'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  static Future<void> createClient(Map<String, dynamic> body) =>
      post('/api/admin/clients', body);

  static Future<void> updateClient(Map<String, dynamic> body) =>
      put('/api/admin/clients', body);

  static Future<void> deleteClient(int id) => delete('/api/admin/clients?id=$id');

  /// Paquetes del cliente: { purchasedPackages: [...], catalog: [...] }
  static Future<Map<String, dynamic>> clientPackages(int userId) async {
    final data = await get('/api/admin/client-packages', query: {'userId': '$userId'});
    return (data as Map).cast<String, dynamic>();
  }

  /// Asignar compra existente al cliente.
  static Future<void> assignPurchasedPackage(int userId, int purchasedPackageId) =>
      post('/api/admin/client-packages', {
        'userId': userId,
        'purchasedPackageId': purchasedPackageId,
      });

  /// Crear compra nueva desde el catálogo y asignarla.
  static Future<void> addPackageFromCatalog(int userId, int packageId) =>
      post('/api/admin/client-packages', {'userId': userId, 'packageId': packageId});

  /// Quitar el paquete del cliente (baja del vínculo).
  static Future<void> removeClientPackage(int userId, int usersPackageId) =>
      post('/api/admin/client-packages', {
        'userId': userId,
        'usersPackageId': usersPackageId,
      });
}

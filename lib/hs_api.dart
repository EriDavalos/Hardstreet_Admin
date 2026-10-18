// ==================================================================
// HARD STREET ADMIN - Cliente de la API Hardstreet (misma API que la web)
// Base: AppConstants.apiBase (Hardstreet-Backend, puerto 4000)
// Auth: header Authorization: Bearer <token> (igual que la web)
// ==================================================================
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_constants.dart';
import 'site_design.dart';
import 'web_content.dart';
import 'widgets/hs_toast.dart';

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

/// Un módulo con sus acciones (respuesta de /api/admin/permission).
/// `key` = modules.module (drive, users, rols...); `name` = modules.name.
///
/// `order` y `categoryOrder` ordenan el menú (menor = arriba); `categoryName`
/// es el encabezado del grupo (p. ej. "Operación") o null si el módulo va
/// SUELTO (como Dashboard).
typedef HsModulePerms = ({
  String key,
  String name,
  Set<String> actions,
  int? order,
  String? categoryKey,
  String? categoryName,
  int? categoryOrder,
});

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.details});
  final String message;
  final int? statusCode;

  /// Detalle técnico que manda el backend (`details`): el motivo concreto del
  /// error (qué permiso falta, qué campo está mal…). Se muestra como segunda
  /// línea de la notificación roja.
  final String? details;

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

  /// Ruta ACTUAL del drive dentro del panel (carpetas desde la raíz).
  /// La escribe DrivePage al navegar; los diálogos la leen para cerrarse
  /// solos si cambia la carpeta mientras están abiertos.
  static List<String>? route;
}

class HsApi {
  HsApi._();

  /// Callback global: se dispara cuando el servidor responde 401 con una
  /// sesión ya establecida (token expirado/inválido, p. ej. al abrir la app
  /// con "Recordarme" después de días). La app debe regresar al login.
  static void Function()? onUnauthorized;

  /// Callback global: se dispara cuando se guardan permisos de un rol
  /// (RolesPage). El sidebar se recarga para aplicar los cambios AL INSTANTE
  /// (módulos sin "Ver" se ocultan sin reiniciar la app).
  static void Function()? onPermissionsChanged;

  /// Base del CRUD: backend de Vercel (AppConstants.crudApiBase).
  /// Independiente del drive (AppConstants.apiBase / DRIVE_API).
  static String get base {
    var b = AppConstants.crudApiBase;
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return b;
  }

  /// Cliente HTTP de la app. Es inyectable: las pruebas lo reemplazan por
  /// un `MockClient` para no tocar la red. En producción es el de
  /// `package:http` (mismo comportamiento de siempre).
  static http.Client client = http.Client();

  static Uri _u(String path, [Map<String, String>? query]) =>
      Uri.parse('$base$path').replace(queryParameters: query);

  static Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        if (HsSession.isLogged) 'Authorization': 'Bearer ${HsSession.token}',
      };

  /// Primer texto no vacío de la lista (`message`, luego `error`).
  static String? _firstText(List<Object?> values) {
    for (final v in values) {
      final s = (v ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  static Future<dynamic> _run(
    Future<http.Response> Function() fn, {
    int timeout = 20,
    String path = '',
    bool notify = false,
  }) async {
    late http.Response r;
    try {
      r = await fn().timeout(Duration(seconds: timeout));
    } on TimeoutException {
      const msg = 'El servidor tardó demasiado en responder';
      if (notify) HsToast.error(msg);
      throw ApiException(msg);
    } catch (e) {
      final msg = 'No hay conexión con el servidor ($base)';
      if (notify) HsToast.error(msg);
      throw ApiException(msg);
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
      final map = body is Map ? body : null;
      // El backend manda { code, message, details }; `error` se acepta como
      // respaldo para no romper con un backend viejo.
      final msg = _firstText([map?['message'], map?['error']]) ??
          'Error HTTP ${r.statusCode}';
      final details = _firstText([map?['details']]);
      if (notify) HsToast.error(msg, details: details);
      throw ApiException(msg, statusCode: r.statusCode, details: details);
    }
    // ÉXITO: el backend describe la operación en `message` → aviso verde.
    // Solo en las escrituras (crear/editar/eliminar), no en las lecturas.
    if (notify && body is Map) {
      final msg = _firstText([body['message']]);
      if (msg != null) {
        HsToast.success(msg, details: _firstText([body['details']]));
      }
    }
    return body;
  }

  static Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _run(() => client.get(_u(path, query), headers: _headers()), path: path);

  /// Escritura. [notify] = true hace que el mensaje del backend salga en la
  /// notificación lateral (verde al éxito, rojo al error).
  static Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    bool notify = true,
  }) =>
      _run(
        () => client.post(_u(path), headers: _headers(), body: jsonEncode(body)),
        path: path,
        notify: notify,
      );

  static Future<dynamic> put(
    String path,
    Map<String, dynamic> body, {
    bool notify = true,
  }) =>
      _run(
        () => client.put(_u(path), headers: _headers(), body: jsonEncode(body)),
        path: path,
        notify: notify,
      );

  static Future<dynamic> delete(String path, {bool notify = true}) => _run(
        () => client.delete(_u(path), headers: _headers()),
        path: path,
        notify: notify,
      );

  /// DELETE con cuerpo (lo pide el módulo Archivos compartidos: la carpeta
  /// y a qué usuarios se le quita no caben cómodos en la URL).
  static Future<dynamic> deleteBody(
    String path,
    Map<String, dynamic> body, {
    bool notify = true,
  }) =>
      _run(
        () => client.delete(_u(path),
            headers: _headers(), body: jsonEncode(body)),
        path: path,
        notify: notify,
      );

  // ---------------- Auth ----------------

  /// Login real contra /api/auth/login (la misma que usa la web).
  static Future<Map<String, dynamic>> login(String email, String password) async {
    // El login no es un "crear/editar/eliminar": su error se muestra en la
    // propia pantalla, no como notificación lateral.
    final data = await post('/api/auth/login',
        {'email': email, 'password': password},
        notify: false);
    HsSession.token = (data['token'] ?? '').toString();
    HsSession.user = (data['user'] as Map?)?.cast<String, dynamic>();
    if (!HsSession.isLogged) throw ApiException('El servidor no devolvió token');
    return HsSession.user ?? const {};
  }

  static Future<void> logout() async {
    try {
      await post('/api/auth/logout', {}, notify: false);
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

  static Future<void> updateRole(Map<String, dynamic> body) async {
    await put('/api/admin/roles', body);
    // Guardar permisos puede cambiar qué módulos se ven: notificar al panel.
    onPermissionsChanged?.call();
  }

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
    // Compatibilidad: si un módulo llega SIN la clave `actions` (backend viejo
    // que no filtra por módulo), hereda el catálogo completo. Si la clave SÍ
    // existe pero viene vacía, se respeta: ese módulo no admite acciones.
    final modules = [
      for (final m in meta.modules)
        if (!m.containsKey('actions') && catalog.isNotEmpty)
          {...m, 'actions': catalog}
        else
          m,
    ];
    return HsMeta(modules: modules, permissions: meta.permissions);
  }

  // ---------------- Catálogo de paquetes ----------------

  /// Catálogo completo: [{ id, name, subtitle, description, price, currency,
  /// tierId, tierName, tierNum, categoryId, categoryName, isExtern,
  /// urlImage, serviceIds, serviceNames }]
  static Future<List<Map<String, dynamic>>> adminPackages() async {
    final data = await get('/api/admin/packages');
    return ((data['packages'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  static Future<void> createPackage(Map<String, dynamic> body) =>
      post('/api/admin/packages', body);

  static Future<void> updatePackage(Map<String, dynamic> body) =>
      put('/api/admin/packages', body);

  static Future<void> deletePackage(int id) =>
      delete('/api/admin/packages?id=$id');

  /// Tiers del catálogo: [{ id, name, tier }]
  static Future<List<Map<String, dynamic>>> tiers() async {
    final data = await get('/api/tiers');
    return ((data['tiers'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// Categorías de paquetes: [{ id, name, icon, urlImage }]
  static Future<List<Map<String, dynamic>>> packageCategories() async {
    final data = await get('/api/categories');
    return ((data['categories'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// Crea una categoría del catálogo (Boda, XV Años, Bautizo…), con su foto
  /// opcional (un enlace o una foto del Drive).
  ///
  /// Requiere permiso de CREAR en el módulo "Paquetes" (las categorías son
  /// parte del catálogo, igual que en el menú).
  static Future<void> createPackageCategory(
    String name, {
    String? urlImage,
  }) => post('/api/admin/categories', {
    'name': name,
    if ((urlImage ?? '').trim().isNotEmpty) 'urlImage': urlImage!.trim(),
  });

  /// Renombra una categoría del catálogo.
  static Future<void> updatePackageCategory(Map<String, dynamic> body) =>
      put('/api/admin/categories', body);

  /// Da de baja una categoría (baja lógica: deja de listarse).
  static Future<void> deletePackageCategory(int id) =>
      delete('/api/admin/categories?id=$id');

  /// Servicios disponibles para incluir en paquetes:
  /// [{ id, name, description, icon, url }]
  static Future<List<Map<String, dynamic>>> services() async {
    final data = await get('/api/services');
    return ((data['services'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  // ---------------- Servicios (catálogo, módulo "Servicios") ----------------

  /// Catálogo completo para el módulo Servicios (incluye url).
  static Future<List<Map<String, dynamic>>> adminServices() async {
    final data = await get('/api/admin/services');
    return ((data['services'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// Crea un servicio { name, description?, icon?, url? }.
  static Future<void> createService(Map<String, dynamic> body) =>
      post('/api/admin/services', body);

  /// Actualiza un servicio { id, ...campos }.
  static Future<void> updateService(Map<String, dynamic> body) =>
      put('/api/admin/services', body);

  /// Baja lógica de un servicio.
  static Future<void> deleteService(int id) =>
      delete('/api/admin/services?id=$id');

  /// Edita la liga base del Drive de un servicio. Se usa DESDE la pestaña
  /// Servicios del paquete comprado del cliente (es opcional).
  static Future<void> updateServiceUrl(int serviceId, String url) =>
      post('/api/admin/package-progress', {
        'action': 'actualizar-servicio-url',
        'serviceId': serviceId,
        'url': url,
      });

  /// Comparte con el cliente una CARPETA del Drive y/o una LIGA para UN
  /// servicio del paquete (`serviceId` = id del servicio DEL PAQUETE). Las
  /// dos son opcionales; vacío = se quita esa opción.
  /// Guarda las opciones de compartir de UN servicio del paquete: la carpeta y
  /// la liga, y QUÉ le sale al cliente ([pickPhotos] = «Elegir fotos»,
  /// [showFolder] = «Abrir carpeta»).
  static Future<void> updateServiceShare(
    int serviceId, {
    String folder = '',
    String link = '',
    bool pickPhotos = false,
    bool showFolder = true,
  }) =>
      post('/api/admin/package-progress', {
        'action': 'actualizar-servicio-share',
        'serviceId': serviceId,
        'folder': folder,
        'link': link,
        'pickPhotos': pickPhotos,
        'showFolder': showFolder,
      });

  /// Los elementos/fotos que YO (cliente) marqué para un servicio de mi
  /// paquete. Devuelve la lista de rutas del Drive.
  static Future<List<String>> myServiceItems(int serviceId) async {
    final data = await get('/api/my/service-items',
        query: {'serviceId': '$serviceId'});
    return ((data['items'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
  }

  /// REEMPLAZA mi selección de elementos/fotos de ese servicio.
  static Future<List<String>> setMyServiceItems(
      int serviceId, List<String> paths) async {
    final data = await put('/api/my/service-items', {
      'serviceId': serviceId,
      'paths': paths,
    });
    return ((data['items'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
  }

  // ---------------- Cliente ----------------

  /// MIS paquetes comprados → GET /api/my/packages.
  /// Devuelve [{ id, name, subtitle, price, paid, currency, status:{name},
  ///   package:{ tier:{name}, packageCategory:{name}, urlImage },
  ///   services:[{ id, description, status:{name},
  ///               service:{ name, icon, url } }] }]
  static Future<List<Map<String, dynamic>>> myPackages() async {
    final data = await get('/api/my/packages');
    return ((data['purchasedPackages'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// MIS permisos (para el menú): GET /api/admin/permission (antes
  /// "my-permissions"). Devuelve { isAdmin, modules: [{ key, name, actions }] }.
  static Future<({bool isAdmin, List<HsModulePerms> modules})>
      myPermissions() async {
    final data = await get('/api/admin/permission') as Map? ?? const {};
    final modules = <HsModulePerms>[];
    for (final m in ((data['modules'] as List?) ?? const [])) {
      if (m is! Map) continue;
      final key = (m['key'] ?? '').toString().toLowerCase().trim();
      final name = (m['name'] ?? '').toString().trim();
      if (key.isEmpty && name.isEmpty) continue;
      int? asInt(Object? v) =>
          v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));
      String? asStr(Object? v) {
        final s = (v ?? '').toString().trim();
        return s.isEmpty ? null : s;
      }

      modules.add((
        key: key,
        name: name,
        actions: ((m['actions'] as List?) ?? const [])
            .map((a) => a.toString().toLowerCase())
            .toSet(),
        order: asInt(m['order']),
        categoryKey: asStr(m['categoryKey']),
        categoryName: asStr(m['categoryName']),
        categoryOrder: asInt(m['categoryOrder']),
      ));
    }
    return (isAdmin: data['isAdmin'] == true, modules: modules);
  }

  /// Carpeta del Drive COMPARTIDA con el cliente del paquete (pestaña Drive
  /// del administrador del paquete). `path` vacío deja de compartir.
  ///
  /// Deja UNA sola carpeta: para compartir VARIAS usa [addPackageDrivePath]
  /// y [removePackageDrivePath].
  static Future<void> setPackageDrivePath({
    required int purchasedPackageId,
    required String path,
  }) =>
      post('/api/admin/package-progress', {
        'action': 'compartir-directorio',
        'purchasedPackageId': purchasedPackageId,
        'path': path,
      });

  /// Suma UNA carpeta del Drive a las compartidas con el cliente del paquete
  /// (un paquete puede compartir varias).
  static Future<void> addPackageDrivePath({
    required int purchasedPackageId,
    required String path,
  }) =>
      post('/api/admin/package-progress', {
        'action': 'agregar-directorio',
        'purchasedPackageId': purchasedPackageId,
        'path': path,
      });

  /// Deja de compartir UNA carpeta del paquete (las demás siguen igual).
  static Future<void> removePackageDrivePath({
    required int purchasedPackageId,
    required String path,
  }) =>
      post('/api/admin/package-progress', {
        'action': 'quitar-directorio',
        'purchasedPackageId': purchasedPackageId,
        'path': path,
      });

  /// Comparte UNA carpeta del Drive DIRECTAMENTE con el CLIENTE: la ve en
  /// TODOS sus paquetes (no solo en el que se está administrando).
  static Future<void> addClientDrivePath({
    required int purchasedPackageId,
    required String path,
  }) =>
      post('/api/admin/package-progress', {
        'action': 'agregar-directorio-cliente',
        'purchasedPackageId': purchasedPackageId,
        'path': path,
      });

  /// Deja de compartir UNA carpeta compartida con el CLIENTE.
  static Future<void> removeClientDrivePath({
    required int purchasedPackageId,
    required String path,
  }) =>
      post('/api/admin/package-progress', {
        'action': 'quitar-directorio-cliente',
        'purchasedPackageId': purchasedPackageId,
        'path': path,
      });

  /// Carpetas del Drive COMPARTIDAS con el usuario logueado.
  ///
  /// `isClient` = true cuando su drive debe limitarse a esas carpetas (los
  /// paquetes comprados definen lo que ve). El Admin nunca se limita.
  /// `paths` = [{ packageId, packageName, path }].
  ///
  /// Endpoint: GET /api/my/drive
  static Future<({bool isClient, List<Map<String, dynamic>> paths})>
      myDriveDirectories() async {
    final data = (await get('/api/my/drive') as Map?) ?? const {};
    final paths = ((data['paths'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    return (isClient: data['isClient'] == true, paths: paths);
  }

  // ---------------- Diseño del sitio (tarjetas y portada) -------------

  /// Diseño GUARDADO del sitio (tarjetas de paquetes y portada).
  ///
  /// Endpoint: GET /api/admin/site
  /// Si la tabla `site_config` todavía no existe (o nadie ha diseñado nada)
  /// devuelve los valores por defecto del sitio.
  static Future<({SiteDesign design, Map<String, dynamic>? landing})>
      siteDesign() async {
    final data = (await get('/api/admin/site') as Map?) ?? const {};
    final landing = (data['landing'] as Map?)?.cast<String, dynamic>();
    return (
      design: SiteDesign.fromJsonText(data['design']),
      landing: landing,
    );
  }

  /// Guarda el diseño de las tarjetas (permiso de actualizar en "Paquetes").
  ///
  /// Endpoint: PUT /api/admin/site — lo que se guarda aquí lo aplica la web
  /// EN VIVO (GET /api/site), sin volver a publicar el sitio.
  static Future<void> saveSiteDesign(SiteDesign design) =>
      put('/api/admin/site', {'design': design.toJson()});

  /// Guarda el CONTENIDO de la portada: textos, imágenes y secciones.
  /// Permiso de actualizar en el módulo "Sitio web".
  ///
  /// Endpoint: PUT /api/admin/site con el documento `landing`. Con la base
  /// vacía sólo viaja lo que se cambió (lo demás se sigue leyendo del HTML del
  /// sitio); en cuanto la base tiene contenido, viaja el documento COMPLETO.
  static Future<void> saveSiteContent(SiteContent content) =>
      put('/api/admin/site', {'landing': content.toJson()});

  // ---------------- Archivos compartidos ----------------

  /// MIS archivos compartidos y los que OTROS me compartieron, más la lista
  /// de usuarios con los que se puede compartir.
  ///
  /// Endpoint: GET /api/admin/shared-files
  static Future<
      ({
        List<Map<String, dynamic>> shared,
        List<Map<String, dynamic>> received,
        List<Map<String, dynamic>> candidates,
        bool canShare,
        bool canDelete,
      })> sharedFiles() async {
    final data = (await get('/api/admin/shared-files') as Map?) ?? const {};
    final item = (data['item'] as Map?)?.cast<String, dynamic>() ?? const {};
    List<Map<String, dynamic>> list(Object? raw) =>
        ((raw as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
    return (
      shared: list(item['shared']),
      received: list(item['received']),
      candidates: list(item['candidates']),
      canShare: data['canShare'] != false,
      canDelete: data['canDelete'] != false,
    );
  }

  /// A quién le tengo compartida YA la carpeta [folder] (y los candidatos).
  ///
  /// Endpoint: `GET /api/admin/shared-files?folder=<ruta>`
  static Future<({
    List<int> targets,
    List<Map<String, dynamic>> candidates,
    bool canShare,
    bool canDelete,
  })> sharedFileTargets(String folder) async {
    final data = (await get('/api/admin/shared-files',
            query: {'folder': folder}) as Map?) ??
        const {};
    final item = (data['item'] as Map?)?.cast<String, dynamic>() ?? const {};
    final targets = ((item['targets'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => (e['id'] as num?)?.toInt() ?? 0)
        .where((n) => n > 0)
        .toList();
    final candidates = ((data['candidates'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    return (
      targets: targets,
      candidates: candidates,
      canShare: data['canShare'] != false,
      canDelete: data['canDelete'] != false,
    );
  }

  /// Comparte la carpeta [path] con [userIds] (los que falten se suman).
  ///
  /// Endpoint: POST /api/admin/shared-files
  static Future<void> shareFolderWith({
    required String path,
    required List<int> userIds,
  }) =>
      post('/api/admin/shared-files', {
        'path': path,
        'userIds': userIds,
      });

  /// Deja de compartir la carpeta [path] con [userIds].
  ///
  /// Endpoint: DELETE /api/admin/shared-files
  static Future<void> unshareFolderWith({
    required String path,
    required List<int> userIds,
  }) =>
      deleteBody('/api/admin/shared-files', {
        'path': path,
        'userIds': userIds,
      });

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

  // ---------------- Abonos de paquete ----------------

  /// Registros (abonos) de un paquete comprado o de TODOS los de un cliente:
  /// `[{ id, purchasedPackageId, amount, description, created }]`.
  static Future<List<Map<String, dynamic>>> packagePayments({
    int? userId,
    int? purchasedPackageId,
  }) async {
    final data = await get('/api/admin/package-payments', query: {
      if (userId != null) 'userId': '$userId',
      if (purchasedPackageId != null) 'purchasedPackageId': '$purchasedPackageId',
    });
    return ((data['payments'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// Suma un abono al paquete y devuelve el nuevo total pagado.
  static Future<num> addPackagePayment({
    required int purchasedPackageId,
    required num amount,
    String description = '',
  }) async {
    final data = await post('/api/admin/package-payments', {
      'purchasedPackageId': purchasedPackageId,
      'amount': amount,
      'description': description,
    });
    return (data is Map && data['paid'] is num) ? data['paid'] as num : 0;
  }

  /// Quita (baja lógica) un abono y devuelve el nuevo total pagado.
  static Future<num> deletePackagePayment(int id) async {
    final data = await delete('/api/admin/package-payments?id=$id');
    return (data is Map && data['paid'] is num) ? data['paid'] as num : 0;
  }

  // -------- Administración del paquete del cliente --------

  /// Todo lo que necesita el modal del paquete: servicios con su estado,
  /// movimientos (abonos, inversiones, gastos, ahorros, abonos externos),
  /// totales (incluye `disponible` = abonado - gastado - ahorro +
  /// abono externo) y si el paquete se puede finalizar (con el motivo si no).
  ///
  /// Endpoint: GET /api/admin/package-progress
  static Future<Map<String, dynamic>> packageProgress(
      int purchasedPackageId) async {
    final data = await get('/api/admin/package-progress',
        query: {'purchasedPackageId': '$purchasedPackageId'});
    return (data as Map).cast<String, dynamic>();
  }

  /// Da por TERMINADO un servicio del paquete (estado Entregado + fecha).
  static Future<void> completePackageService(int serviceId,
          {String description = ''}) =>
      post('/api/admin/package-progress', {
        'action': 'completar-servicio',
        'serviceId': serviceId,
        if (description.isNotEmpty) 'description': description,
      });

  /// Reabre un servicio que ya estaba terminado.
  static Future<void> reopenPackageService(int serviceId) =>
      post('/api/admin/package-progress', {
        'action': 'reabrir-servicio',
        'serviceId': serviceId,
      });

  /// Cambia la descripción (avance) de un servicio.
  static Future<void> updatePackageService(int serviceId,
          {required String description}) =>
      post('/api/admin/package-progress', {
        'action': 'actualizar-servicio',
        'serviceId': serviceId,
        'description': description,
      });

  /// Registra un movimiento del paquete:
  /// `inversion`, `gasto`, `ahorro` o `abono_externo`.
  static Future<void> addPackageMovement({
    required int purchasedPackageId,
    required String kind,
    required num amount,
    String description = '',
    int? userId,
  }) =>
      post('/api/admin/package-progress', {
        'action': 'movimiento',
        'purchasedPackageId': purchasedPackageId,
        'kind': kind,
        'amount': amount,
        'description': description,
        'userId': ?userId,
      });

  /// Reparte un pago entre colaboradores y empleados del paquete. Cuenta como
  /// gasto, pero cada parte queda registrada como `pago` con su destinatario.
  ///
  /// `mode` = 'iguales' (partes iguales de `total` entre `userIds`) o
  /// 'numeracion' (un monto por usuario en `parts`).
  static Future<Map<String, dynamic>> splitPackagePayment({
    required int purchasedPackageId,
    required String mode,
    num total = 0,
    List<int> userIds = const [],
    List<Map<String, dynamic>> parts = const [],
    String description = '',
  }) async {
    final data = await post('/api/admin/package-progress', {
      'action': 'repartir-pago',
      'purchasedPackageId': purchasedPackageId,
      'mode': mode,
      'total': total,
      'userIds': userIds,
      'parts': parts,
      'description': description,
    });
    return ((data as Map?) ?? const {}).cast<String, dynamic>();
  }

  /// Edita un movimiento o un abono del historial. Solo se permite mientras
  /// el paquete NO esté finalizado (el backend lo vuelve a validar).
  /// `source` = 'movement' (inversión/gasto/ahorro/abono externo) o
  /// 'payment' (abono; en este caso `kind` se ignora).
  static Future<void> editPackageMovement(
    int id, {
    String source = 'movement',
    String? kind,
    num? amount,
    String? description,
  }) =>
      post('/api/admin/package-progress', {
        'action': 'editar-movimiento',
        'movementId': id,
        'source': source,
        'kind': ?kind,
        'amount': ?amount,
        'description': ?description,
      });

  /// Quita un movimiento o un abono del historial.
  /// `source` = 'movement' (inversión/gasto/abono externo) o 'payment'.
  static Future<void> deletePackageMovement(int id,
          {String source = 'movement'}) =>
      post('/api/admin/package-progress', {
        'action': 'quitar-movimiento',
        'movementId': id,
        'source': source,
      });

  /// Finaliza el paquete (el backend valida servicios y pago completos).
  static Future<void> finishClientPackage(int purchasedPackageId) =>
      post('/api/admin/package-progress', {
        'action': 'finalizar',
        'purchasedPackageId': purchasedPackageId,
      });

  /// Reabre un paquete finalizado.
  static Future<void> reopenClientPackage(int purchasedPackageId) =>
      post('/api/admin/package-progress', {
        'action': 'reabrir-paquete',
        'purchasedPackageId': purchasedPackageId,
      });

  // ---------------- Finanzas (módulo "Finanzas") ----------------

  /// Todo lo monetario del negocio, en una sola llamada:
  /// `{ currency, totals, packages, months, movements }`.
  ///
  /// - `totals`: ganancias (abonos cobrados), porCobrar, facturado,
  ///   disponible (abonado - gastado - ahorro + abono externo), ahorro,
  ///   inversiones, gastos y abonoExterno.
  /// - `packages`: el dinero de CADA paquete activo, con su cliente.
  /// - `months`: últimos 6 meses (ganancias vs. gastos/inversiones/ahorro).
  /// - `movements`: los movimientos INDIVIDUALES (con paquete y cliente) que
  ///   la tabla de Finanzas usa para desglosar cada fila.
  ///
  /// Endpoint: GET /api/admin/finance
  static Future<Map<String, dynamic>> finance() async {
    final data = await get('/api/admin/finance');
    return (data as Map).cast<String, dynamic>();
  }

  /// Registra un movimiento DESDE el módulo Finanzas:
  /// `gasto`, `inversion`, `ahorro` o `abono_externo` (por defecto ahorro).
  ///
  /// SIN `purchasedPackageId` el movimiento es GENERAL (del negocio, sin
  /// paquete): es lo que el módulo usa por defecto y no obliga a elegir
  /// paquete. El porcentaje se calcula en la app sobre el `disponible`.
  /// Endpoint: POST /api/admin/finance
  static Future<void> addFinanceMovement({
    int? purchasedPackageId,
    required String kind,
    required num amount,
    String description = '',
  }) =>
      post('/api/admin/finance', {
        'purchasedPackageId': ?purchasedPackageId,
        'kind': kind,
        'amount': amount,
        'description': description,
      });

  /// Destina un monto al AHORRO. Sin paquete el ahorro es del NEGOCIO
  /// (movimiento general); con paquete se aparta de ese paquete.
  /// Atajo de [addFinanceMovement] con kind = 'ahorro'.
  static Future<void> addSavings({
    int? purchasedPackageId,
    required num amount,
    String description = '',
  }) =>
      addFinanceMovement(
        purchasedPackageId: purchasedPackageId,
        kind: 'ahorro',
        amount: amount,
        description: description,
      );

  // ---------------- Agendas ----------------

  /// Agendas de evento: todas, las de un cliente o las de un paquete comprado.
  /// Cada una: `{ id, purchasedPackageId, userId, clientName, packageName,
  /// serviceId, serviceName, eventDate, description }`.
  static Future<List<Map<String, dynamic>>> agendas({
    int? userId,
    int? purchasedPackageId,
    String? from,
    String? to,
  }) async {
    final data = await get('/api/admin/agendas', query: {
      if (userId != null) 'userId': '$userId',
      if (purchasedPackageId != null) 'purchasedPackageId': '$purchasedPackageId',
      'from': ?from,
      'to': ?to,
    });
    return ((data['agendas'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// Crea una agenda `{ purchasedPackageId, serviceId, eventDate, description }`.
  /// `eventDate` viaja como `yyyy-MM-dd HH:mm:ss`.
  static Future<void> createAgenda(Map<String, dynamic> body) =>
      post('/api/admin/agendas', body);

  /// Actualiza una agenda `{ id, serviceId?, eventDate?, description? }`.
  static Future<void> updateAgenda(Map<String, dynamic> body) =>
      put('/api/admin/agendas', body);

  /// Baja lógica de una agenda.
  static Future<void> deleteAgenda(int id) =>
      delete('/api/admin/agendas?id=$id');

  // ---------------- Avisos de eventos (recordatorios) ----------------

  /// Mis avisos de eventos próximos (falta 1 semana / falta 1 día).
  /// Cada uno: `{ id, scheduleId, kind, title, body, eventDate, isRead,
  /// created }`. `kind` es '7d' (falta una semana) o '1d' (mañana).
  static Future<List<Map<String, dynamic>>> reminders() async {
    final data = await get('/api/reminders');
    return ((data['reminders'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// Marca UN aviso como leído.
  static Future<void> markReminderRead(int id) =>
      put('/api/reminders', {'id': id});

  /// Marca TODOS mis avisos como leídos.
  static Future<void> markAllRemindersRead() =>
      put('/api/reminders', {'all': true}, notify: false);

  // ---------------- Bitácora de actividad (logger) ----------------

  /// Registro de quién creó, editó o eliminó cada cosa.
  /// Cada entrada: `{ id, userId, userName, roleName, module, moduleName,
  ///   action, entity, entityId, description, details, ip, created }`.
  /// Endpoint: GET /api/admin/activity (permiso "Ver" sobre Actividad).
  static Future<List<Map<String, dynamic>>> activity({
    String? module,
    String? action,
    String? entity,
    int? userId,
    String? query,
    int limit = 100,
    int offset = 0,
  }) async {
    final data = await get('/api/admin/activity', query: {
      'module': ?module,
      'action': ?action,
      'entity': ?entity,
      if (userId != null) 'userId': '$userId',
      'q': ?query,
      'limit': '$limit',
      'offset': '$offset',
    });
    return ((data['entries'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }
}

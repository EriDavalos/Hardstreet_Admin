import 'hs_api.dart';

/// Permisos del usuario logueado, cargados de /api/admin/permission.
///
/// REGLAS (decididas con el usuario):
/// - `read`  → "Ver": sin él, el módulo NO aparece en el menú y las demás
///   acciones del módulo no se conceden.
/// - `create` → oculta el botón "Nuevo X"; `update` → oculta Editar;
///   `delete` → oculta Eliminar (en el front; el backend SIEMPRE revalida).
/// - Si el backend falla o aún no despliega el endpoint: el menú queda
///   COMPLETO (modo degradado, como antes) para no romper el panel.
class HsAccess {
  HsAccess._({
    required this.admin,
    required this.perms,
    required this.degraded,
    this.loading = false,
  });

  /// Permisos sin cargar aún (primer frame): NO bloquear la UI.
  final bool loading;

  /// true si el servidor respondió isAdmin=true.
  final bool admin;

  /// moduleName normalizado → set de acciones.
  final Map<String, Set<String>> perms;

  /// true cuando no se pudo consultar (backend viejo / sin conexión): todo
  /// visible, igual que el comportamiento previo.
  final bool degraded;

  static HsAccess _instance =
      HsAccess._(admin: true, perms: const {}, degraded: true, loading: true);
  static final List<void Function()> _listeners = [];

  /// Estado actual (caché en memoria; el sidebar no debe ser async).
  static HsAccess get instance => _instance;

  static void addListener(void Function() fn) => _listeners.add(fn);
  static void removeListener(void Function() fn) => _listeners.remove(fn);

  static void _update(HsAccess next) {
    _instance = next;
    for (final fn in List.of(_listeners)) {
      fn();
    }
  }

  /// Descarga los permisos del usuario. No lanza: ante error entra en modo
  /// degradado (todo visible).
  static Future<void> load() async {
    try {
      final p = await HsApi.myPermissions();
      // Registrar cada módulo por CLAVE (modules.module: home, drive,
      // users, rols...) Y por NOMBRE visible (Inicio, Archivos, Usuarios...):
      // la UI puede preguntar con cualquiera de las dos formas.
      final map = <String, Set<String>>{};
      for (final m in p.modules) {
        final actions = m.actions;
        if (actions.isEmpty) continue;
        if (m.key.isNotEmpty) map[_norm(m.key)] = actions;
        if (m.name.isNotEmpty) map[_norm(m.name)] = actions;
      }
      _update(HsAccess._(
        admin: p.isAdmin,
        perms: map,
        degraded: false,
        loading: false,
      ));
    } catch (_) {
      _update(HsAccess._(
        admin: true,
        perms: const {},
        degraded: true,
        loading: false,
      ));
    }
  }

  static void reset() {
    _update(HsAccess._(
      admin: true,
      perms: const {},
      degraded: true,
      loading: true,
    ));
  }

  /// Normaliza para comparar: minúsculas y sin acentos ("Categorías" ==
  /// "categorias").
  static String _norm(String s) {
    final out = StringBuffer();
    for (final c in s.toLowerCase().runes) {
      const map = {
        0xE1: 'a', // á
        0xE9: 'e', // é
        0xED: 'i', // í
        0xF3: 'o', // ó
        0xFA: 'u', // ú
        0xFC: 'u', // ü
      };
      final repl = map[c];
      out.write(repl ?? String.fromCharCode(c));
    }
    return out.toString();
  }

  Set<String>? _actionsOf(String module) {
    if (degraded) return null;
    // Acepta la CLAVE ("drive") o el NOMBRE ("Archivos"), ambos
    // normalizados; el mapa los registra bajo las dos formas.
    return perms[_norm(module)];
  }

  /// ¿El módulo aparece en el menú? (requiere "read"; admin incluido).
  bool canSee(String module) => _actionsOf(module)?.contains('read') ?? false;

  /// ¿Tiene la acción [action] sobre [module]? (admin incluido).
  bool can(String module, String action) =>
      _actionsOf(module)?.contains(action) ?? false;
}

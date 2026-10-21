import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, Brightness;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_constants.dart';
import 'drive_host.dart';
import 'hs_api.dart';
import 'theme.dart' show AppColors;

/// Modo de apariencia de la app (módulo Configuraciones).
///
/// `system` sigue al tema del teléfono/equipo; `light` y `dark` lo fijan.
enum HsThemeMode { system, light, dark }

/// Configuraciones persistentes de la app (modo oscuro, sesión, etc.).
/// Usa shared_preferences: funciona en Windows, Android y WEB (localStorage),
/// así que las preferencias sobreviven al cierre de la app en cualquier
/// plataforma.
///
/// SESIÓN PERSISTENTE ("Recordarme"): al marcar la casilla en el login se
/// guarda el token + usuario (token JWT, no la contraseña). Al abrir la app
/// se restaura [HsSession] y el usuario entra directo al panel; si el token
/// ya expiró, la primera llamada a la API devolverá 401 y la app pedirá
/// iniciar sesión de nuevo.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _kDark = 'app.dark';
  static const _kThemeMode = 'app.theme.mode';
  static const _kAccent = 'app.accent';
  static const _kRemember = 'app.remember';
  static const _kToken = 'app.token';
  static const _kUser = 'app.user';
  static const _kShareServing = 'app.share.serving';
  static const _kShareServingSet = 'app.share.serving.set';
  static const _kDriveHost = 'app.drive.host';

  /// Copia del token y de la base del CRUD para el AVISO EN SEGUNDO PLANO
  /// (Android): el worker nativo consulta los avisos del paquete aunque la app
  /// esté cerrada. Es una copia aparte de "Recordarme": los avisos llegan
  /// aunque el usuario no haya pedido recordar la sesión.
  static const _kNotifyToken = 'app.notify.token';
  static const _kNotifyBase = 'app.notify.base';

  bool _loaded = false;

  /// Apariencia: claro/oscuro/sistema y color de acento. Se aplica en TODO el
  /// panel (botones, selección, acentos) y se guarda al instante.
  ///
  /// De fábrica manda el **modo del sistema**: la app se ve como el teléfono o
  /// la computadora hasta que el usuario elija claro u oscuro a mano.
  HsThemeMode _themeMode = HsThemeMode.system;
  String _accent = AppColors.defaultAccent;

  // ---- Servicio de compartir (switch de "Archivos compartidos") ----
  bool _shareServing = false;

  /// ¿El usuario ya eligió encendido/apagado? Si nunca tocó el switch, el
  /// servicio puede encenderse solo cuando hay carpetas locales compartidas.
  /// Si lo apagó a propósito, se queda apagado aunque haya carpetas.
  bool _shareServingSet = false;

  // ---- Sesión persistente ("Recordarme") ----
  bool _remember = false;
  String? _savedToken;
  Map<String, dynamic>? _savedUser;

  /// true cuando ya se leyeron las preferencias del disco/storage.
  bool get loaded => _loaded;

  /// Modo de apariencia elegido (persistente).
  HsThemeMode get themeMode => _themeMode;

  /// Clave del color de acento elegido ("azul", "violeta"…).
  String get accent => _accent;

  /// ¿La app se ve OSCURA ahora? (el menú rápido lo usa para el icono y el
  /// widget nativo para su paleta). Con el modo "sistema" sigue al equipo.
  bool get dark {
    if (_themeMode == HsThemeMode.dark) return true;
    if (_themeMode == HsThemeMode.light) return false;
    try {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
    } catch (_) {
      // Sin binding (arranque muy temprano): se asume claro.
      return false;
    }
  }

  /// ¿El usuario encendió el SERVICIO DE COMPARTIR? (persistente)
  ///
  /// Encendido, la app sigue sirviendo las carpetas de ESTA computadora aunque
  /// no quede ningún compartido a la vista, y lo sigue haciendo en la próxima
  /// apertura: es lo que pide el switch del módulo "Archivos compartidos".
  bool get shareServing => _shareServing;

  /// ¿La preferencia del switch es EXPLÍCITA (la eligió el usuario)?
  bool get shareServingSet => _shareServingSet;

  /// Dirección del servidor del drive guardada por el usuario, o `null` si se
  /// usa la de fábrica ([DriveHost.compiled]).
  String? get driveHost => DriveHost.custom;

  /// ¿Hay sesión guardada para restaurar automáticamente?
  bool get hasSavedSession => _remember && (_savedToken?.isNotEmpty ?? false);

  /// Restaura la sesión guardada en la memoria de [HsSession].
  void restoreSession() {
    if (!hasSavedSession) return;
    HsSession.token = _savedToken;
    // Pasa por setUser: de ahí salen la empresa de la sesión y si es
    // Superadministrador (una sesión restaurada tiene que saberlo).
    HsSession.setUser(_savedUser);
  }

  /// Guarda (o borra) la sesión según el valor de [remember].
  /// Se llama tras un login exitoso.
  Future<void> saveSession({
    required bool remember,
    String? token,
    Map<String, dynamic>? user,
  }) async {
    _remember = remember;
    if (remember && token != null && token.isNotEmpty) {
      _savedToken = token;
      _savedUser = user;
    } else {
      _savedToken = null;
      _savedUser = null;
    }
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_kRemember, _remember);
      // El worker nativo del teléfono necesita el token y la base del CRUD
      // para avisar con la app cerrada, haya "Recordarme" o no.
      if (token != null && token.isNotEmpty) {
        await sp.setString(_kNotifyToken, token);
        await sp.setString(_kNotifyBase, AppConstants.crudApiBase);
      }
      if (_remember && _savedToken != null) {
        await sp.setString(_kToken, _savedToken!);
        await sp.setString(
          _kUser,
          jsonEncode(_savedUser ?? const <String, dynamic>{}),
        );
      } else {
        await sp.remove(_kToken);
        await sp.remove(_kUser);
      }
    } catch (_) {
      // Sin storage: la sesión vale solo para esta ejecución.
    }
    notifyListeners();
  }

  /// Cierra la sesión y borra lo persistido (Cerrar sesión).
  Future<void> clearSession() async {
    _remember = false;
    _savedToken = null;
    _savedUser = null;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_kRemember, false);
      await sp.remove(_kToken);
      await sp.remove(_kUser);
      // Sin sesión no hay avisos que llevar al teléfono (el worker nativo
      // para solo al ver que ya no hay token).
      await sp.remove(_kNotifyToken);
    } catch (_) {
      /* noop */
    }
    notifyListeners();
  }

  /// Carga las preferencias guardadas (idempotente).
  Future<void> load() async {
    if (_loaded) return;
    try {
      final sp = await SharedPreferences.getInstance();
      // Apariencia: primero el modo nuevo; las instalaciones viejas solo
      // tienen el interruptor de modo oscuro (se respeta como preferencia).
      final savedMode = sp.getString(_kThemeMode);
      _themeMode = switch (savedMode) {
        'system' => HsThemeMode.system,
        'dark' => HsThemeMode.dark,
        'light' => HsThemeMode.light,
        // Sin preferencia nueva: el MODO DEL SISTEMA es el de fábrica. Solo
        // las instalaciones viejas —que únicamente tienen el interruptor de
        // modo oscuro— conservan su elección.
        _ => switch (sp.getBool(_kDark)) {
          null => HsThemeMode.system,
          final d => d ? HsThemeMode.dark : HsThemeMode.light,
        },
      };
      final savedAccent = sp.getString(_kAccent);
      if (savedAccent != null && AppColors.accents.containsKey(savedAccent)) {
        _accent = savedAccent;
      }
      AppColors.setBrand(AppColors.accents[_accent]!);
      // La base del CRUD la lee el worker nativo de avisos (Android): se
      // actualiza en cada arranque por si cambió la compilación.
      await sp.setString(_kNotifyBase, AppConstants.crudApiBase);
      _shareServing = sp.getBool(_kShareServing) ?? false;
      // Las instalaciones viejas no tienen esta marca: si el switch estaba
      // apagado se sigue pudiendo encender solo al haber carpetas; si estaba
      // encendido, se respeta como preferencia explícita.
      _shareServingSet =
          sp.getBool(_kShareServingSet) ??
          (sp.getBool(_kShareServing) ?? false);
      // Antes que nada: la dirección del servidor. Los servicios del drive la
      // leen al construirse, así que tiene que estar puesta ya al arrancar.
      DriveHost.set(sp.getString(_kDriveHost));
      _remember = sp.getBool(_kRemember) ?? false;
      _savedToken = sp.getString(_kToken);
      // Instalaciones anteriores a los avisos en segundo plano: el worker
      // nativo necesita el token y todavía no lo tiene. Se copia en cada
      // arranque con sesión guardada, sin esperar a un login nuevo.
      if (_savedToken != null && _savedToken!.isNotEmpty) {
        await sp.setString(_kNotifyToken, _savedToken!);
      }
      final userJson = sp.getString(_kUser);
      if (userJson != null) {
        try {
          final decoded = jsonDecode(userJson);
          if (decoded is Map) _savedUser = decoded.cast<String, dynamic>();
        } catch (_) {
          /* usuario corrupto: se ignora */
        }
      }
      if (!hasSavedSession) {
        _savedToken = null;
        _savedUser = null;
      }
      _loaded = true;
      notifyListeners();
    } catch (_) {
      // Sin storage disponible: defaults en memoria.
      _loaded = true;
      notifyListeners();
    }
  }

  /// Guarda la dirección del servidor del drive (vacío = la de fábrica).
  ///
  /// Se aplica al instante: los servicios resuelven la base en cada petición.
  /// Devuelve `false` si lo escrito no es una dirección válida.
  Future<bool> setDriveHost(String? value) async {
    if (!DriveHost.set(value)) return false;
    try {
      final sp = await SharedPreferences.getInstance();
      final saved = DriveHost.custom;
      if (saved == null) {
        await sp.remove(_kDriveHost);
      } else {
        await sp.setString(_kDriveHost, saved);
      }
    } catch (_) {
      // Sin storage: el cambio vale solo para esta sesión.
    }
    notifyListeners();
    return true;
  }

  /// Enciende o apaga el servicio de compartir y lo recuerda.
  Future<void> setShareServing(bool value) async {
    // Si el valor YA está y la preferencia ya era explícita, no hay nada que
    // escribir: volver a esperar el storage desde un cierre de modal podía
    // dejar la operación colgada. El primer apagado (cuando el servicio se
    // encendió solo) SÍ se guarda: queda como preferencia explícita.
    if (_shareServing == value && _shareServingSet) return;
    _shareServing = value;
    _shareServingSet = true;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_kShareServing, value);
      await sp.setBool(_kShareServingSet, true);
    } catch (_) {
      // Sin storage: el cambio vale solo para esta sesión.
    }
  }

  /// Cambia el modo de apariencia (sistema/claro/oscuro) y lo guarda.
  Future<void> setThemeMode(HsThemeMode value) async {
    if (_themeMode == value) return;
    _themeMode = value;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kThemeMode, value.name);
      // Se mantiene el booleano viejo al día: si alguien vuelve a una versión
      // anterior, al menos conserva claro/oscuro.
      await sp.setBool(_kDark, value == HsThemeMode.dark);
    } catch (_) {
      // Sin storage: el cambio vale solo para esta sesión.
    }
  }

  /// Cambia el COLOR DE ACENTO (clave de la paleta) y lo guarda.
  Future<void> setAccent(String key) async {
    final color = AppColors.accents[key];
    if (color == null) return;
    _accent = key;
    AppColors.setBrand(color);
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kAccent, key);
    } catch (_) {
      // Sin storage: el cambio vale solo para esta sesión.
    }
  }

  /// Cambia el modo oscuro (atajo del menú): fija claro u oscuro.
  Future<void> setDark(bool value) =>
      setThemeMode(value ? HsThemeMode.dark : HsThemeMode.light);

  /// Compatibilidad con el resto de la app: un bool oscuro (widgets nativos)
  /// sigue leyendo el modo guardado [dark].
  Future<void> setDarkLegacy(bool value) => setDark(value);
}

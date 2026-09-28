import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hs_api.dart';

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
  static const _kRemember = 'app.remember';
  static const _kToken = 'app.token';
  static const _kUser = 'app.user';

  bool _loaded = false;
  bool _dark = false;

  // ---- Sesión persistente ("Recordarme") ----
  bool _remember = false;
  String? _savedToken;
  Map<String, dynamic>? _savedUser;

  /// true cuando ya se leyeron las preferencias del disco/storage.
  bool get loaded => _loaded;

  /// ¿Modo oscuro activado? (persistente)
  bool get dark => _dark;

  /// ¿Hay sesión guardada para restaurar automáticamente?
  bool get hasSavedSession => _remember && (_savedToken?.isNotEmpty ?? false);

  /// Restaura la sesión guardada en la memoria de [HsSession].
  void restoreSession() {
    if (!hasSavedSession) return;
    HsSession.token = _savedToken;
    HsSession.user = _savedUser;
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
    } catch (_) {/* noop */}
    notifyListeners();
  }

  /// Carga las preferencias guardadas (idempotente).
  Future<void> load() async {
    if (_loaded) return;
    try {
      final sp = await SharedPreferences.getInstance();
      _dark = sp.getBool(_kDark) ?? false;
      _remember = sp.getBool(_kRemember) ?? false;
      _savedToken = sp.getString(_kToken);
      final userJson = sp.getString(_kUser);
      if (userJson != null) {
        try {
          final decoded = jsonDecode(userJson);
          if (decoded is Map) _savedUser = decoded.cast<String, dynamic>();
        } catch (_) {/* usuario corrupto: se ignora */}
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

  /// Cambia el modo oscuro y lo guarda al instante.
  Future<void> setDark(bool value) async {
    if (_dark == value) return;
    _dark = value;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_kDark, value);
    } catch (_) {
      // Sin storage: el cambio vale solo para esta sesión.
    }
  }
}

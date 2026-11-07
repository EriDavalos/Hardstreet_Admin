import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'invitation_templates.dart';

// ==================================================================
// PLANTILLAS DEL USUARIO — almacenamiento local
// ==================================================================
// El catálogo de fábrica vive en el código. Las plantillas que crea el
// usuario se guardan aquí como JSON en shared_preferences: funcionan en
// Windows, Android y WEB (localStorage), sin tocar la base de datos de las
// invitaciones ni el HTML público.
//
// La plantilla guarda una FOTO del diseño (base, portada, colores, fuente y
// componentes). Al aplicarla, el editor sigue permitiendo cambiar cada pieza.
// ==================================================================

class InvitationTemplateStore {
  InvitationTemplateStore._();

  static const String storageKey = 'invitation.templates.custom.v1';

  static bool _loaded = false;
  static Future<void>? _loading;

  /// Las plantillas guardadas en este equipo.
  static List<InvitationTemplateRecipe> get recipes =>
      customInvitationTemplateRecipes;

  static InvitationTemplateRecipe? find(String key) {
    final recipe = invitationTemplateRecipeForKey(key);
    return recipe?.custom == true ? recipe : null;
  }

  /// Carga una sola vez el catálogo local. Es seguro llamarlo desde varias
  /// pantallas al mismo tiempo.
  static Future<void> load() {
    if (_loaded) return Future<void>.value();
    final running = _loading;
    if (running != null) return running;
    final future = _read();
    _loading = future;
    return future.whenComplete(() => _loading = null);
  }

  /// Genera una clave estable y única para una plantilla nueva.
  static String newKey(String name) {
    final slug = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'custom-${slug.isEmpty ? 'plantilla' : slug}-'
        '${DateTime.now().microsecondsSinceEpoch}';
  }

  /// Crea o reemplaza una plantilla y la deja disponible en el catálogo.
  static Future<void> save(InvitationTemplateRecipe recipe) async {
    await load();
    final saved = recipe.custom ? recipe : recipe.copyWith(custom: true);
    final next = <InvitationTemplateRecipe>[
      for (final current in customInvitationTemplateRecipes)
        if (current.key != saved.key) current,
      saved,
    ];
    registerInvitationTemplateRecipes(next);
    await _persist(next);
  }

  static Future<void> delete(String key) async {
    await load();
    final clean = key.trim();
    final next = [
      for (final current in customInvitationTemplateRecipes)
        if (current.key != clean) current,
    ];
    registerInvitationTemplateRecipes(next);
    await _persist(next);
  }

  /// Solo para pruebas: vuelve a leer el storage en el siguiente `load`.
  static void resetForTest() {
    _loaded = false;
    _loading = null;
    registerInvitationTemplateRecipes(const []);
  }

  static Future<void> _read() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(storageKey);
      if (raw == null || raw.trim().isEmpty) {
        registerInvitationTemplateRecipes(const []);
      } else {
        final decoded = jsonDecode(raw);
        final byKey = <String, InvitationTemplateRecipe>{};
        if (decoded is List) {
          for (final item in decoded) {
            final recipe = InvitationTemplateRecipe.fromJson(item);
            if (recipe != null) byKey[recipe.key] = recipe;
          }
        }
        registerInvitationTemplateRecipes(byKey.values);
      }
    } catch (_) {
      // Sin storage o con un JSON roto: el catálogo de fábrica sigue
      // funcionando y no se rompe la pantalla.
      registerInvitationTemplateRecipes(const []);
    }
    _loaded = true;
  }

  static Future<void> _persist(List<InvitationTemplateRecipe> recipes) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        storageKey,
        jsonEncode([for (final recipe in recipes) recipe.toJson()]),
      );
    } catch (_) {
      // Sin storage la plantilla sigue disponible durante esta sesión.
    }
  }
}

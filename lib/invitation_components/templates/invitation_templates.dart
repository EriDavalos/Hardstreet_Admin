import '../component_catalog.dart';

// ==================================================================
// PLANTILLAS = COMBINACIONES DE COMPONENTES
// ==================================================================
// Una plantilla no duplica el documento: elige una base visual (Rosa o
// Marfil), una portada y un diseño para cada componente. El editor puede
// cambiar después cualquier pieza sin perder los textos ni las fotos.
// ==================================================================

class InvitationTemplateRecipe {
  const InvitationTemplateRecipe({
    required this.key,
    required this.name,
    required this.occasion,
    required this.hint,
    required this.baseTemplate,
    required this.coverStyle,
    this.coverBackdrop = '',
    this.accent = '',
    this.bgColor = '',
    this.effect = '',
    this.font = '',
    this.components = const {},
    this.custom = false,
  });

  final String key;
  final String name;
  final String occasion;
  final String hint;

  /// Documento base que aporta la tipografía y la estructura del HTML.
  final String baseTemplate;

  final String coverStyle;
  final String coverBackdrop;

  /// Valores propios de la plantilla. Vacío = los de la base.
  final String accent;
  final String bgColor;
  final String effect;
  final String font;

  /// Diseños elegidos para esta combinación. Las claves que falten usan el
  /// diseño de fábrica del componente.
  final Map<String, String> components;

  /// La plantilla la creó el usuario y vive en este equipo, no en el
  /// catálogo de fábrica.
  final bool custom;

  Map<String, dynamic> toJson() => {
    'key': key,
    'name': name,
    'occasion': occasion,
    'hint': hint,
    'baseTemplate': baseTemplate,
    'coverStyle': coverStyle,
    'coverBackdrop': coverBackdrop,
    'accent': accent,
    'bgColor': bgColor,
    'effect': effect,
    'font': font,
    'components': {for (final e in components.entries) e.key: e.value},
  };

  /// Lee una plantilla guardada y descarta cualquier valor que ya no exista
  /// en el catálogo. Devuelve `null` si no tiene clave o nombre.
  static InvitationTemplateRecipe? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = '${raw['name'] ?? ''}'.trim();
    var key = '${raw['key'] ?? ''}'.trim().toLowerCase();
    if (name.isEmpty || key.isEmpty) return null;
    key = key.replaceAll(RegExp(r'[^a-z0-9_-]'), '-');
    if (!key.startsWith('custom-')) key = 'custom-$key';

    final base = '${raw['baseTemplate'] ?? ''}'.trim().toLowerCase();
    final baseTemplate = base == 'boda-marfil' ? 'boda-marfil' : 'sobre-xv';
    final rawCover = '${raw['coverStyle'] ?? ''}'.trim().toLowerCase();
    const covers = {'rosa', 'carta', 'xv', 'noche', 'cortina', 'clasica'};
    final coverStyle = covers.contains(rawCover)
        ? rawCover
        : (baseTemplate == 'boda-marfil' ? 'carta' : 'rosa');
    final rawBackdrop = '${raw['coverBackdrop'] ?? ''}'.trim().toLowerCase();
    const backdrops = {'marfil', 'jardin', 'seda'};
    final coverBackdrop = backdrops.contains(rawBackdrop)
        ? rawBackdrop
        : (baseTemplate == 'boda-marfil' ? 'marfil' : '');
    final components = sanitizeComponentDesigns(raw['components']);
    components.remove('cover');
    const effects = {
      'petalos',
      'burbujas',
      'destellos',
      'corazones',
      'confeti',
      'ninguno',
    };
    const fonts = {'clasica', 'moderna', 'romantica'};
    final effect = '${raw['effect'] ?? ''}'.trim().toLowerCase();
    final font = '${raw['font'] ?? ''}'.trim().toLowerCase();
    return InvitationTemplateRecipe(
      key: key,
      name: name,
      occasion: '${raw['occasion'] ?? ''}'.trim(),
      hint: '${raw['hint'] ?? ''}'.trim(),
      baseTemplate: baseTemplate,
      coverStyle: coverStyle,
      coverBackdrop: coverBackdrop,
      accent: _recipeColor(raw['accent']),
      bgColor: _recipeColor(raw['bgColor']),
      effect: effects.contains(effect) ? effect : '',
      font: fonts.contains(font) ? font : '',
      components: components,
      custom: true,
    );
  }

  InvitationTemplateRecipe copyWith({
    String? key,
    String? name,
    String? occasion,
    String? hint,
    String? baseTemplate,
    String? coverStyle,
    String? coverBackdrop,
    String? accent,
    String? bgColor,
    String? effect,
    String? font,
    Map<String, String>? components,
    bool? custom,
  }) {
    return InvitationTemplateRecipe(
      key: key ?? this.key,
      name: name ?? this.name,
      occasion: occasion ?? this.occasion,
      hint: hint ?? this.hint,
      baseTemplate: baseTemplate ?? this.baseTemplate,
      coverStyle: coverStyle ?? this.coverStyle,
      coverBackdrop: coverBackdrop ?? this.coverBackdrop,
      accent: accent ?? this.accent,
      bgColor: bgColor ?? this.bgColor,
      effect: effect ?? this.effect,
      font: font ?? this.font,
      components: components ?? this.components,
      custom: custom ?? this.custom,
    );
  }
}

String _recipeColor(Object? raw) {
  final value = '${raw ?? ''}'.trim().replaceAll('#', '').toUpperCase();
  return RegExp(r'^[0-9A-F]{6}$').hasMatch(value) ? value : '';
}

const List<InvitationTemplateRecipe> kInvitationTemplateRecipes = [
  InvitationTemplateRecipe(
    key: 'rosa-clasica',
    name: 'Rosa Pastel',
    occasion: 'XV',
    hint:
        'La combinación clásica: sobre rosa, portada floral y tarjetas '
        'ilustradas. Ideal para XV y celebraciones dulces.',
    baseTemplate: 'sobre-xv',
    coverStyle: 'rosa',
    components: {},
  ),
  InvitationTemplateRecipe(
    key: 'marfil-clasica',
    name: 'Marfil & Oro',
    occasion: 'Boda',
    hint:
        'Papel marfil, sello de cera y carta inclinada. Una base elegante '
        'para bodas con detalles dorados.',
    baseTemplate: 'boda-marfil',
    coverStyle: 'carta',
    coverBackdrop: 'marfil',
    components: {},
  ),
];

InvitationTemplateRecipe? invitationTemplateRecipeForKey(String key) {
  final clean = key.trim().toLowerCase();
  for (final t in allInvitationTemplateRecipes) {
    if (t.key == clean) return t;
  }
  return null;
}

// ------------------------------------------------------------------
// Plantillas del usuario
// ------------------------------------------------------------------
// El catálogo de fábrica es constante. Las plantillas creadas en el editor
// viven en este registro, que el almacenamiento local vuelve a llenar al
// abrir la app. Así el modelo y el HTML no necesitan saber de storage.
// ------------------------------------------------------------------

final List<InvitationTemplateRecipe> _customInvitationTemplateRecipes = [];

List<InvitationTemplateRecipe> get customInvitationTemplateRecipes =>
    List.unmodifiable(_customInvitationTemplateRecipes);

List<InvitationTemplateRecipe> get allInvitationTemplateRecipes => [
  ...kInvitationTemplateRecipes,
  ..._customInvitationTemplateRecipes,
];

bool isCustomInvitationTemplate(String key) {
  final clean = key.trim().toLowerCase();
  return _customInvitationTemplateRecipes.any((r) => r.key == clean);
}

/// Reemplaza las plantillas del usuario. Se protegen las claves de fábrica:
/// una plantilla personalizada nunca puede pisar una receta incluida.
void registerInvitationTemplateRecipes(
  Iterable<InvitationTemplateRecipe> recipes,
) {
  final builtinKeys = kInvitationTemplateRecipes.map((r) => r.key).toSet();
  final seen = <String>{};
  _customInvitationTemplateRecipes
    ..clear()
    ..addAll(
      recipes.where(
        (r) =>
            r.custom &&
            r.key.isNotEmpty &&
            !builtinKeys.contains(r.key) &&
            seen.add(r.key),
      ),
    );
}

/// La combinación de fábrica para un documento base.
InvitationTemplateRecipe defaultTemplateRecipeForBase(String baseTemplate) {
  final clean = baseTemplate.trim().toLowerCase();
  if (clean == 'boda-marfil') {
    return kInvitationTemplateRecipes.firstWhere(
      (t) => t.key == 'marfil-clasica',
    );
  }
  return kInvitationTemplateRecipes.firstWhere((t) => t.key == 'rosa-clasica');
}

InvitationTemplateRecipe templateRecipeForInvitation({
  required String preset,
  required String template,
}) {
  return invitationTemplateRecipeForKey(preset) ??
      defaultTemplateRecipeForBase(template);
}

/// El mapa completo de diseños de la plantilla, incluidas las piezas que
/// no personaliza. Así una plantilla nueva no depende de valores viejos.
Map<String, String> templateRecipeComponents(InvitationTemplateRecipe recipe) {
  final out = <String, String>{};
  for (final component in kInvitationComponents) {
    out[component.key] = invitationComponentDesign(
      component.key,
      recipe.components[component.key] ?? '',
    );
  }
  out['cover'] = recipe.coverStyle;
  return out;
}

/// Lee un mapa de componentes y deja solo claves y diseños conocidos.
Map<String, String> sanitizeComponentDesigns(Object? raw) {
  final out = <String, String>{};
  if (raw is! Map) return out;
  for (final entry in raw.entries) {
    final key = '${entry.key}'.trim().toLowerCase();
    final component = invitationComponentForKey(key);
    if (component == null) continue;
    final design = component.design('${entry.value}')?.key;
    if (design == null) continue;
    out[key] = design;
  }
  return out;
}

import 'package:flutter/material.dart';

/// Superficies de UNA paleta, para el modo claro y el oscuro.
///
/// Una paleta no es un color de acento más: cambia el FONDO de la app, las
/// tarjetas, la barra lateral y los bordes. Por eso cada una trae su juego
/// claro y su juego oscuro, pensados para que el texto se lea igual de bien.
class HsSurfaces {
  const HsSurfaces({
    required this.bg,
    required this.surface,
    required this.card,
    required this.sidebar,
    required this.line,
  });

  /// Fondo de la app (scaffold y franjas de las barras del sistema).
  final Color bg;

  /// Superficie base del [ColorScheme] (hojas, menús, campos).
  final Color surface;

  /// Tarjetas, diálogos y menús.
  final Color card;

  /// Barra lateral / panel de navegación.
  final Color sidebar;

  /// Bordes y divisores.
  final Color line;
}

/// PALETA COMPLETA del panel.
///
/// Antes había un solo acento configurable sobre las mismas superficies
/// (azul noche + blanco). Ahora se elige un diseño ENTERO: cada paleta cambia
/// el fondo, las tarjetas, la barra lateral y —de paso— el acento, así que la
/// app se ve distinta de verdad, no solo con otro color de botón.
class HsPalette {
  const HsPalette({
    required this.key,
    required this.name,
    required this.hint,
    required this.accentKey,
    required this.light,
    required this.dark,
  });

  /// Clave persistida (`app.palette`).
  final String key;

  /// Nombre visible en Configuraciones.
  final String name;

  /// Una línea que describe el diseño.
  final String hint;

  /// Acento que trae la paleta (clave de [AppColors.accents]).
  final String accentKey;

  final HsSurfaces light;
  final HsSurfaces dark;

  Color get accent =>
      AppColors.accents[accentKey] ?? AppColors.accents['azul']!;

  /// El azul de la marca: la paleta de fábrica.
  static const medianoche = HsPalette(
    key: 'medianoche',
    name: 'Medianoche',
    hint: 'Azul cobalto sobre azul noche',
    accentKey: 'azul',
    light: HsSurfaces(
      bg: Color(0xFFF7F9FC),
      surface: Color(0xFFFFFFFF),
      card: Color(0xFFFFFFFF),
      sidebar: Color(0xFFF4F6FB),
      line: Color(0xFFE5EAF2),
    ),
    dark: HsSurfaces(
      bg: Color(0xFF0C111C),
      surface: Color(0xFF151B29),
      card: Color(0xFF1A2233),
      sidebar: Color(0xFF0F1420),
      line: Color(0xFF2A3346),
    ),
  );

  /// Grafito: gris acero y acento plomizo. Neutro, sin tinte azul.
  static const grafito = HsPalette(
    key: 'grafito',
    name: 'Grafito',
    hint: 'Gris acero neutro, sin azul',
    accentKey: 'grafito',
    light: HsSurfaces(
      bg: Color(0xFFF5F6F8),
      surface: Color(0xFFFFFFFF),
      card: Color(0xFFFFFFFF),
      sidebar: Color(0xFFEDEFF2),
      line: Color(0xFFDFE3E9),
    ),
    dark: HsSurfaces(
      bg: Color(0xFF0B0C0E),
      surface: Color(0xFF16181C),
      card: Color(0xFF1C1F24),
      sidebar: Color(0xFF101216),
      line: Color(0xFF2C3037),
    ),
  );

  /// Esmeralda: verde profundo sobre casi negro con tinte verde.
  static const esmeralda = HsPalette(
    key: 'esmeralda',
    name: 'Esmeralda',
    hint: 'Verde profundo sobre negro verdoso',
    accentKey: 'menta',
    light: HsSurfaces(
      bg: Color(0xFFF4F8F6),
      surface: Color(0xFFFFFFFF),
      card: Color(0xFFFFFFFF),
      sidebar: Color(0xFFECF2EF),
      line: Color(0xFFDCE7E2),
    ),
    dark: HsSurfaces(
      bg: Color(0xFF08120F),
      surface: Color(0xFF101D19),
      card: Color(0xFF14231E),
      sidebar: Color(0xFF0B1713),
      line: Color(0xFF253A33),
    ),
  );

  /// Amatista: violeta sobre azul noche con tinte morado.
  static const amatista = HsPalette(
    key: 'amatista',
    name: 'Amatista',
    hint: 'Violeta profundo sobre noche morada',
    accentKey: 'violeta',
    light: HsSurfaces(
      bg: Color(0xFFF7F5FB),
      surface: Color(0xFFFFFFFF),
      card: Color(0xFFFFFFFF),
      sidebar: Color(0xFFF1EDF8),
      line: Color(0xFFE4DEF0),
    ),
    dark: HsSurfaces(
      bg: Color(0xFF0E0A18),
      surface: Color(0xFF180F28),
      card: Color(0xFF1E1430),
      sidebar: Color(0xFF120D1E),
      line: Color(0xFF34264D),
    ),
  );

  /// Zafiro: azul marino muy profundo con acento índigo. Más frío y serio que
  /// Medianoche, que es cobalto.
  static const zafiro = HsPalette(
    key: 'zafiro',
    name: 'Zafiro',
    hint: 'Azul marino profundo e índigo',
    accentKey: 'indigo',
    light: HsSurfaces(
      bg: Color(0xFFF4F6FC),
      surface: Color(0xFFFFFFFF),
      card: Color(0xFFFFFFFF),
      sidebar: Color(0xFFECF0FA),
      line: Color(0xFFDEE4F4),
    ),
    dark: HsSurfaces(
      bg: Color(0xFF070C1A),
      surface: Color(0xFF0F1628),
      card: Color(0xFF151E34),
      sidebar: Color(0xFF0A1020),
      line: Color(0xFF24304C),
    ),
  );

  /// Océano: petróleo verdoso con acento cian. Frío y limpio.
  static const oceano = HsPalette(
    key: 'oceano',
    name: 'Océano',
    hint: 'Petróleo y cian, fresco y sobrio',
    accentKey: 'cian',
    light: HsSurfaces(
      bg: Color(0xFFF3F8FA),
      surface: Color(0xFFFFFFFF),
      card: Color(0xFFFFFFFF),
      sidebar: Color(0xFFE9F2F7),
      line: Color(0xFFD6E6EE),
    ),
    dark: HsSurfaces(
      bg: Color(0xFF05121A),
      surface: Color(0xFF0C1B25),
      card: Color(0xFF112430),
      sidebar: Color(0xFF07161E),
      line: Color(0xFF1E3644),
    ),
  );

  /// Cobre: neutros cálidos (arena y piedra) con acento cobre. El contrapunto
  /// cálido de Grafito, sin caer en el dorado.
  static const cobre = HsPalette(
    key: 'cobre',
    name: 'Cobre',
    hint: 'Arena cálida y cobre',
    accentKey: 'cobre',
    light: HsSurfaces(
      bg: Color(0xFFFAF7F3),
      surface: Color(0xFFFFFFFF),
      card: Color(0xFFFFFFFF),
      sidebar: Color(0xFFF3EDE6),
      line: Color(0xFFE6DACE),
    ),
    dark: HsSurfaces(
      bg: Color(0xFF13100D),
      surface: Color(0xFF1D1915),
      card: Color(0xFF241F1A),
      sidebar: Color(0xFF171310),
      line: Color(0xFF3A312A),
    ),
  );

  /// Todas las paletas, en el orden en que se ofrecen.
  static const List<HsPalette> all = [
    medianoche,
    zafiro,
    grafito,
    oceano,
    esmeralda,
    amatista,
    cobre,
  ];

  /// Paleta por clave; sin clave (o con una que ya no existe) la de fábrica.
  static HsPalette byKey(String? key) {
    for (final palette in all) {
      if (palette.key == key) return palette;
    }
    return medianoche;
  }
}

/// Paleta y tema de HardStreet Admin.
///
/// Fondos, tarjetas, barra lateral y acento salen de la PALETA VIGENTE
/// ([HsPalette]): cambiarla en Configuraciones repinta todo el panel sin tocar
/// cada pantalla.
class AppColors {
  /// COLORES DE ACENTO que se pueden elegir en Configuraciones.
  ///
  /// Cada PALETA trae el suyo (ver [HsPalette.accentKey]): «Medianoche» el
  /// azul de marca, «Grafito» el plomo, «Cobre» el cobre… No se elige suelto en
  /// Configuraciones; cambiar de paleta es cambiar de diseño entero.
  static const Map<String, Color> accents = {
    'azul': Color(0xFF2F6BFF),
    'indigo': Color(0xFF4F46E5),
    'violeta': Color(0xFF7C3AED),
    'rosa': Color(0xFFDB2777),
    'rojo': Color(0xFFDC2626),
    'naranja': Color(0xFFEA580C),
    'ambar': Color(0xFFD97706),
    'verde': Color(0xFF16A34A),
    'menta': Color(0xFF10B981),
    'teal': Color(0xFF0D9488),
    'cian': Color(0xFF0891B2),
    'grafito': Color(0xFF5C6B7A),
    'cobre': Color(0xFFA65B2A),
  };

  // ---- Colores de DATOS (Almacenamiento) ----
  // Cada dato (archivos, carpetas, cuota, disco, libre) tiene su color, pero
  // todos salen de la MISMA paleta de la app: no hay azules ni naranjas
  // sueltos que no se puedan elegir en Configuraciones. Las claves nuevas
  // ('ambar', 'menta', 'cian') aparecen también en el selector de acento.
  static Color get dataFiles => accents['cian']!;
  static Color get dataFolders => accents['indigo']!;
  static Color get dataQuota => accents['violeta']!;
  static Color get dataDisk => accents['ambar']!;
  static Color get dataFree => accents['menta']!;
  static Color get danger => accents['rojo']!;

  /// Paleta de diseño VIGENTE (la elige Configuraciones).
  static HsPalette _palette = HsPalette.medianoche;
  static HsPalette get palette => _palette;

  /// Cambia la PALETA completa (fondos, tarjetas, barra lateral y bordes).
  static void setPalette(HsPalette palette) => _palette = palette;

  /// Acento VIGENTE. No es `const` a propósito: Configuraciones lo cambia y
  /// las ~120 referencias del panel (iconos, chips, gradientes) se pintan con
  /// el color nuevo sin tocar cada pantalla.
  static Color _brand = Color(0xFF2F6BFF);
  static Color get brand => _brand;
  static Color get brandDark => Color.lerp(_brand, Colors.black, .28)!;

  /// Cambia el acento (lo llama la paleta elegida en Configuraciones).
  static void setBrand(Color color) => _brand = color;

  // ---- Superficies de la paleta vigente ----
  // Son getters (no constantes): al cambiar de paleta, todo lo que ya las usa
  // se repinta en el siguiente build.
  static Color get bgLight => _palette.light.bg;
  static Color get bgDark => _palette.dark.bg;
  static Color get surfaceLight => _palette.light.surface;
  static Color get surfaceDark => _palette.dark.surface;
  static Color get cardLight => _palette.light.card;
  static Color get cardDark => _palette.dark.card;
  static Color get sidebarLight => _palette.light.sidebar;
  static Color get sidebarDark => _palette.dark.sidebar;
  static Color get lineLight => _palette.light.line;
  static Color get lineDark => _palette.dark.line;

  /// Estados: algo que YA funciona (sigue el acento) y algo que necesita
  /// atención (ámbar). Los usa, por ejemplo, la píldora de estado de las
  /// carpetas compartidas ("Disponible" / "Apagada ahora").
  static Color get ok => _brand;
  static const warn = Color(0xFFD97706);
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: Brightness.light,
      surface: AppColors.surfaceLight,
    );
    // El primario visible (botones, selección, enlaces) es el acento vigente;
    // el resto del esquema se deriva del mismo seed para armonía.
    return _base(scheme.copyWith(primary: AppColors.brand)).copyWith(
      scaffoldBackgroundColor: AppColors.bgLight,
      cardColor: AppColors.cardLight,
      dividerColor: AppColors.lineLight,
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: Brightness.dark,
      surface: AppColors.surfaceDark,
    );
    // Igual en oscuro: el primario coincide con el acento vigente.
    return _base(scheme.copyWith(primary: AppColors.brand)).copyWith(
      scaffoldBackgroundColor: AppColors.bgDark,
      cardColor: AppColors.cardDark,
      dividerColor: AppColors.lineDark.withValues(alpha: .55),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ThemeData _base(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    final line = (isDark ? AppColors.lineDark : AppColors.lineLight);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppColors.bgDark : AppColors.cardLight,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        // DISEÑO PLANO: sin elevación ni sombras; solo borde y superficie.
        elevation: 0,
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: line.withValues(alpha: .45)),
        ),
        margin: EdgeInsets.zero,
      ),
      // Botones y diálogos sin sombra (flat).
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppColors.cardDark : AppColors.cardLight,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: line.withValues(alpha: .45)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: line.withValues(alpha: .45)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: .04)
            : AppColors.sidebarLight,
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant.withValues(alpha: .8),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: line.withValues(alpha: .6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: line.withValues(alpha: .6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.brand, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: line.withValues(alpha: .7)),
      ),
      // Tooltip SIEMPRE oscuro con texto BLANCO. En modo oscuro el fondo era
      // blanco al 12 %: el texto blanco se perdía sobre él (los nombres de las
      // ubicaciones del mapa no se leían al pasar el mouse).
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2B3140) : const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: .10)),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

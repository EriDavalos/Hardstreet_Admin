import 'package:flutter/material.dart';

/// Paleta y tema de HardStreet Admin.
/// Azules corporativos sobre superficies neutras, con soporte claro/oscuro.
class AppColors {
  /// COLORES DE ACENTO que se pueden elegir en Configuraciones.
  ///
  /// El elegido pinta los botones, la selección y los acentos de TODO el
  /// panel (la app escucha el cambio y reconstruye el tema al instante).
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

  /// El azul de la marca: el acento de fábrica.
  static const String defaultAccent = 'azul';

  /// Acento VIGENTE. No es `const` a propósito: Configuraciones lo cambia y
  /// las ~120 referencias del panel (iconos, chips, gradientes) se pintan con
  /// el color nuevo sin tocar cada pantalla.
  static Color _brand = Color(0xFF2F6BFF);
  static Color get brand => _brand;
  static Color get brandDark => Color.lerp(_brand, Colors.black, .28)!;

  /// Cambia el acento (lo llama [AppSettings.setAccent]).
  static void setBrand(Color color) => _brand = color;

  static const sidebarLight = Color(0xFFF4F6FB);
  static const sidebarDark = Color(0xFF0F1420);
  static const surfaceDark = Color(0xFF151B29);
  static const cardDark = Color(0xFF1A2233);

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
    );
    // El primario visible (botones, selección, enlaces) es el azul del botón;
    // el resto del esquema se deriva del mismo seed para armonía.
    return _base(scheme.copyWith(primary: AppColors.brand)).copyWith(
      scaffoldBackgroundColor: const Color(0xFFF7F9FC),
      cardColor: Colors.white,
      dividerColor: const Color(0xFFE5EAF2),
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
    // Igual en oscuro: el primario coincide con el azul del botón.
    return _base(scheme.copyWith(primary: AppColors.brand)).copyWith(
      scaffoldBackgroundColor: const Color(0xFF0C111C),
      cardColor: AppColors.cardDark,
      dividerColor: Colors.white.withValues(alpha: .08),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ThemeData _base(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF0C111C) : Colors.white,
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
        color: isDark ? AppColors.cardDark : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .45)),
        ),
        margin: EdgeInsets.zero,
      ),
      // Botones y diálogos sin sombra (flat).
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppColors.cardDark : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .45)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .45)),
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
            : const Color(0xFFF4F6FA),
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant.withValues(alpha: .8),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .5),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .5),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.brand, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: .12)
              : const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

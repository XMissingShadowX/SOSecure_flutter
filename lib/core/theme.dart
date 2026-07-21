import 'package:flutter/material.dart';

// Conversión matemática exacta (OKLCH -> sRGB) de las variables CSS de app/globals.css
// del proyecto Next.js — no son aproximaciones. Ver :root (dark, default) y html.light
// en globals.css para los valores OKLCH originales.
class AppColors {
  // Modo claro (html.light en globals.css)
  static const lightBackground = Color(0xFFF6F9FC);
  static const lightForeground = Color(0xFF090B0F);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightPrimary = Color(0xFF008C75);
  static const lightSecondary = Color(0xFFEBEFF5);
  static const lightMuted = Color(0xFFEBEFF5);
  static const lightMutedForeground = Color(0xFF4F5661);
  static const lightBorder = Color(0xFFDADEE5);

  // Modo oscuro (:root en globals.css — es el default de la web)
  static const darkBackground = Color(0xFF05070B);
  static const darkForeground = Color(0xFFEBEFF5);
  static const darkCard = Color(0xFF0D1014);
  static const darkPrimary = Color(0xFF00CCB2);
  static const darkSecondary = Color(0xFF1C222B);
  static const darkMuted = Color(0xFF151B24);
  static const darkMutedForeground = Color(0xFF88909C);
  static const darkBorder = Color(0xFF232933);

  // Compartidos entre ambos temas (mismo H/C, solo cambia L levemente entre modos para
  // --safe; --destructive y --warning son idénticos en luz/oscuridad en globals.css)
  static const destructive = Color(0xFFDF000D);
  static const warning = Color(0xFFEF9900);
  static const lightSafe = Color(0xFF008B1D);
  static const darkSafe = Color(0xFF31AA40);
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.lightPrimary,
      onPrimary: AppColors.lightBackground,
      secondary: AppColors.lightSecondary,
      onSecondary: AppColors.lightForeground,
      tertiary: AppColors.lightSafe,
      onTertiary: AppColors.lightBackground,
      error: AppColors.destructive,
      onError: AppColors.lightBackground,
      surface: AppColors.lightCard,
      onSurface: AppColors.lightForeground,
      surfaceContainerHighest: AppColors.lightMuted,
      onSurfaceVariant: AppColors.lightMutedForeground,
      outline: AppColors.lightBorder,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.lightBackground,
      // Material 3 aplica un tinte de superficie automático sobre los Card según
      // colorScheme.surfaceTint — como no lo definimos explícitamente, mezclaba un tinte
      // por defecto que apagaba nuestros colores custom (ej. el verde de "safe" se veía
      // gris verdoso). Se desactiva para que los colores del tema web se vean tal cual.
      cardTheme: const CardThemeData(surfaceTintColor: Colors.transparent),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.darkPrimary,
      onPrimary: AppColors.darkBackground,
      secondary: AppColors.darkSecondary,
      onSecondary: AppColors.darkForeground,
      tertiary: AppColors.darkSafe,
      onTertiary: AppColors.darkBackground,
      error: AppColors.destructive,
      onError: AppColors.darkBackground,
      surface: AppColors.darkCard,
      onSurface: AppColors.darkForeground,
      surfaceContainerHighest: AppColors.darkMuted,
      onSurfaceVariant: AppColors.darkMutedForeground,
      outline: AppColors.darkBorder,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.darkBackground,
      cardTheme: const CardThemeData(surfaceTintColor: Colors.transparent),
    );
  }
}

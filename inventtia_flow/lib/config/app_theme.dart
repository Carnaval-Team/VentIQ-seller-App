import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  /// Semilla original de marca. Solo alimenta `ColorScheme.fromSeed`; NO se usa
  /// directamente en la UI. Los tonos de marca visibles (abajo) son los que
  /// `tonalSpot` genera a partir de esta semilla, fijados como constantes para
  /// que los gradientes escritos a mano coincidan con `scheme.primary`.
  static const Color _seed = Color(0xFF1565C0);

  // Familia primaria = tonos del palette de `tonalSpot` (seed 0xFF1565C0).
  // primary == scheme.primary (tone 40) → gradientes y botones idénticos.
  static const Color primary = Color(0xFF405F90); // tone 40
  static const Color primaryLight = Color(0xFF5A79AC); // tone 50
  static const Color primaryDark = Color(0xFF274777); // tone 30
  static const Color accent = Color(0xFF00BCD4);
  static const Color success = Color(0xFF43A047);
  static const Color warning = Color(0xFFFB8C00);
  static const Color error = Color(0xFFE53935);
  static const Color surface = Color(0xFFF5F7FA);
  static const Color cardBg = Colors.white;
  static const Color textPrimary = Color(0xFF1A237E);
  static const Color textSecondary = Color(0xFF546E7A);
  static const Color border = Color(0xFFE0E6ED);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: GoogleFonts.interTextTheme(),
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        border: _outline(scheme.outline),
        enabledBorder: _outline(scheme.outline),
        focusedBorder: _outline(scheme.primary, width: 2),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      extensions: const [AppSemanticColors.defaults],
    );
  }

  static OutlineInputBorder _outline(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
}

/// Colores semánticos que Material 3 `ColorScheme` no cubre (estados de éxito/
/// aviso, color de acento secundario y las variantes claras/oscuras usadas en
/// gradientes). Se exponen como `ThemeExtension` — la forma M3 correcta de
/// extender el tema. Acceso: `Theme.of(context).extension<AppSemanticColors>()!`.
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  final Color success;
  final Color warning;
  final Color accent;
  final Color primaryLight;
  final Color primaryDark;

  const AppSemanticColors({
    required this.success,
    required this.warning,
    required this.accent,
    required this.primaryLight,
    required this.primaryDark,
  });

  static const AppSemanticColors defaults = AppSemanticColors(
    success: AppTheme.success,
    warning: AppTheme.warning,
    accent: AppTheme.accent,
    primaryLight: AppTheme.primaryLight,
    primaryDark: AppTheme.primaryDark,
  );

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? accent,
    Color? primaryLight,
    Color? primaryDark,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      accent: accent ?? this.accent,
      primaryLight: primaryLight ?? this.primaryLight,
      primaryDark: primaryDark ?? this.primaryDark,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
    );
  }
}

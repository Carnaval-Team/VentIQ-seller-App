import 'package:flutter/material.dart';

/// Colores consistentes de VentIQ basados en la app principal
class AppColors {
  // Colores principales
  static const Color primary = Color(0xFF4A90E2);
  static const Color primaryDark = Color(0xFF357ABD);
  static const Color secondary = Color(0xFF6B7280);
  static const Color background = Color(0xFFF8F9FA);

  // Colores de estado
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFFF6B35);
  static const Color error = Colors.red;
  static const Color info = Color(0xFF4A90E2);

  // Colores de texto
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textLight = Color(0xFF9CA3AF);
  static const Color black87 = Color(0xDD000000); // 87% opacity black

  // Colores de superficie
  static const Color surface = Colors.white;
  static const Color surfaceVariant = Color(0xFFF3F4F6);
  static const Color border = Color(0xFFE5E7EB);

  // Colores grises
  static const MaterialColor grey = Colors.grey;

  // Gradientes
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryDark],
  );

  static const LinearGradient successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [success, Color(0xFF059669)],
  );
}

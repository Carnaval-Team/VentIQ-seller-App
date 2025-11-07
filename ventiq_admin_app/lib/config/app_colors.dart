import 'package:flutter/material.dart';

/// Colores consistentes de VentIQ basados en la app principal
class AppColors {
  // Colores principales
  static const Color primary = Color(0xFF194B8C);
  static const Color primaryDark = Color(0xFF123A6B);
  static const Color secondary = Color(0xFF6B7280);
  static const Color background = Color(0xFFF8F9FA);

  // Colores de estado
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFFF6B35);
  static const Color error = Colors.red;
  static const Color info = Color(0xFF4A90E2);

  // Colores específicos para promociones
  static const Color promotionDiscount = Color(0xFF10B981); // Verde para descuentos
  static const Color promotionCharge = Color(0xFFFF6B35); // Naranja para recargos
  static const Color promotionActive = Color(0xFF10B981); // Verde para activas
  static const Color promotionInactive = Color(0xFFFF6B35); // Naranja para inactivas
  static const Color promotionExpired = Color(0xFF6B7280); // Gris para vencidas

  // Colores de fondo con mejor contraste
  static const Color promotionDiscountBg = Color(0xFFECFDF5); // Fondo verde claro
  static const Color promotionChargeBg = Color(0xFFFFF7ED); // Fondo naranja claro
  static const Color promotionActiveBg = Color(0xFFECFDF5); // Fondo verde claro
  static const Color promotionInactiveBg = Color(0xFFFFF7ED); // Fondo naranja claro
  static const Color promotionExpiredBg = Color(0xFFF9FAFB); // Fondo gris claro

  // Colores adicionales para estados
  static const Color active = Color(0xFF10B981); // Verde para elementos activos
  static const Color inactive = Color(0xFFFF6B35); // Naranja para elementos inactivos
  static const Color expired = Color(0xFF6B7280); // Gris para elementos vencidos
  static const Color neutral = Color(0xFF4A90E2); // Azul neutro
  static const Color usage = Color(0xFF4A90E2); // Azul para uso/estadísticas
  static const Color limit = Color(0xFFFF6B35); // Naranja para límites

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

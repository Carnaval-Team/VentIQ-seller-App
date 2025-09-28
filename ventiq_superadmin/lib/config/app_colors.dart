import 'package:flutter/material.dart';

class AppColors {
  // Colores principales - Optimizados para web/desktop
  static const Color primary = Color(0xFF2E7D32); // Verde VentIQ
  static const Color primaryLight = Color(0xFF4CAF50);
  static const Color primaryDark = Color(0xFF1B5E20);
  
  // Colores secundarios
  static const Color secondary = Color(0xFF1976D2); // Azul
  static const Color secondaryLight = Color(0xFF42A5F5);
  static const Color secondaryDark = Color(0xFF0D47A1);
  
  // Colores de estado
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);
  
  // Colores de fondo - Optimizados para desktop
  static const Color background = Color(0xFFF8F9FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF5F5F5);
  
  // Colores de texto
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textHint = Color(0xFFBDBDBD);
  
  // Colores específicos para dashboard
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color cardShadow = Color(0x1A000000);
  static const Color divider = Color(0xFFE0E0E0);
  
  // Gradientes para web
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFFF8F9FA), Color(0xFFE3F2FD)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  
  // Colores para gráficos
  static const List<Color> chartColors = [
    Color(0xFF4CAF50), // Verde
    Color(0xFF2196F3), // Azul
    Color(0xFFFF9800), // Naranja
    Color(0xFF9C27B0), // Púrpura
    Color(0xFFFF5722), // Rojo-naranja
    Color(0xFF607D8B), // Azul gris
    Color(0xFFFFC107), // Ámbar
    Color(0xFF795548), // Marrón
  ];
}

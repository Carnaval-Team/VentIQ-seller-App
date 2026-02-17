import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../services/user_preferences_service.dart';

/// Enum para los modos de tema disponibles
enum AppThemeMode {
  system, // Sigue el tema del sistema
  light, // Siempre claro
  dark, // Siempre oscuro
}

class ThemeProvider extends ChangeNotifier {
  final UserPreferencesService _preferencesService = UserPreferencesService();

  AppThemeMode _appThemeMode = AppThemeMode.system;
  bool _isInitialized = false;

  AppThemeMode get appThemeMode => _appThemeMode;
  bool get isInitialized => _isInitialized;

  /// Obtiene el ThemeMode efectivo de Flutter basado en la configuración
  ThemeMode get themeMode {
    switch (_appThemeMode) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
    }
  }

  /// Determina si el modo oscuro está activo actualmente
  /// Toma en cuenta el modo del sistema si está en 'system'
  bool get isDarkMode {
    if (_appThemeMode == AppThemeMode.dark) return true;
    if (_appThemeMode == AppThemeMode.light) return false;
    // Si es system, verificar el brillo del sistema
    final brightness =
        SchedulerBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark;
  }

  ThemeProvider() {
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final modeString = await _preferencesService.getThemeMode();
    _appThemeMode = _stringToAppThemeMode(modeString);
    _isInitialized = true;
    notifyListeners();
  }

  AppThemeMode _stringToAppThemeMode(String mode) {
    switch (mode) {
      case 'dark':
        return AppThemeMode.dark;
      case 'light':
        return AppThemeMode.light;
      case 'system':
      default:
        return AppThemeMode.system;
    }
  }

  String _appThemeModeToString(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.dark:
        return 'dark';
      case AppThemeMode.light:
        return 'light';
      case AppThemeMode.system:
        return 'system';
    }
  }

  /// Establece el modo de tema
  Future<void> setAppThemeMode(AppThemeMode mode) async {
    if (_appThemeMode == mode) return;
    _appThemeMode = mode;
    await _preferencesService.setThemeMode(_appThemeModeToString(mode));
    notifyListeners();
  }

  /// Establece el modo de tema usando ThemeMode de Flutter (para compatibilidad)
  Future<void> setThemeMode(ThemeMode mode) async {
    switch (mode) {
      case ThemeMode.system:
        await setAppThemeMode(AppThemeMode.system);
        break;
      case ThemeMode.light:
        await setAppThemeMode(AppThemeMode.light);
        break;
      case ThemeMode.dark:
        await setAppThemeMode(AppThemeMode.dark);
        break;
    }
  }

  /// Cicla entre los modos: system -> light -> dark -> system
  Future<void> cycleTheme() async {
    switch (_appThemeMode) {
      case AppThemeMode.system:
        await setAppThemeMode(AppThemeMode.light);
        break;
      case AppThemeMode.light:
        await setAppThemeMode(AppThemeMode.dark);
        break;
      case AppThemeMode.dark:
        await setAppThemeMode(AppThemeMode.system);
        break;
    }
  }

  /// Toggle simple entre claro y oscuro (ignora system)
  Future<void> toggleTheme() async {
    if (isDarkMode) {
      await setAppThemeMode(AppThemeMode.light);
    } else {
      await setAppThemeMode(AppThemeMode.dark);
    }
  }

  /// Método legacy para compatibilidad
  Future<void> setDarkMode(bool isDark) async {
    await setAppThemeMode(isDark ? AppThemeMode.dark : AppThemeMode.light);
  }

  /// Obtiene el nombre amigable del modo actual
  String get currentModeName {
    switch (_appThemeMode) {
      case AppThemeMode.system:
        return 'Automático';
      case AppThemeMode.light:
        return 'Claro';
      case AppThemeMode.dark:
        return 'Oscuro';
    }
  }

  /// Obtiene el icono correspondiente al modo actual
  IconData get currentModeIcon {
    switch (_appThemeMode) {
      case AppThemeMode.system:
        return Icons.brightness_auto;
      case AppThemeMode.light:
        return Icons.light_mode;
      case AppThemeMode.dark:
        return Icons.dark_mode;
    }
  }
}

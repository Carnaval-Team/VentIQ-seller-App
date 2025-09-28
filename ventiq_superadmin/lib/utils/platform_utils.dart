import 'package:universal_platform/universal_platform.dart';

class PlatformUtils {
  /// Detecta si la aplicación se está ejecutando en web
  static bool get isWeb => UniversalPlatform.isWeb;
  
  /// Detecta si la aplicación se está ejecutando en móvil (Android o iOS)
  static bool get isMobile => UniversalPlatform.isAndroid || UniversalPlatform.isIOS;
  
  /// Detecta si la aplicación se está ejecutando en desktop (Windows, macOS o Linux)
  static bool get isDesktop => 
      UniversalPlatform.isWindows || 
      UniversalPlatform.isMacOS || 
      UniversalPlatform.isLinux;
  
  /// Detecta si es Android específicamente
  static bool get isAndroid => UniversalPlatform.isAndroid;
  
  /// Detecta si es iOS específicamente
  static bool get isIOS => UniversalPlatform.isIOS;
  
  /// Detecta si es Windows específicamente
  static bool get isWindows => UniversalPlatform.isWindows;
  
  /// Detecta si es macOS específicamente
  static bool get isMacOS => UniversalPlatform.isMacOS;
  
  /// Detecta si es Linux específicamente
  static bool get isLinux => UniversalPlatform.isLinux;
  
  /// Retorna el nombre de la plataforma actual
  static String get platformName {
    if (UniversalPlatform.isWeb) return 'Web';
    if (UniversalPlatform.isAndroid) return 'Android';
    if (UniversalPlatform.isIOS) return 'iOS';
    if (UniversalPlatform.isWindows) return 'Windows';
    if (UniversalPlatform.isMacOS) return 'macOS';
    if (UniversalPlatform.isLinux) return 'Linux';
    return 'Unknown';
  }
  
  /// Determina si se debe usar un layout optimizado para pantallas grandes
  static bool shouldUseDesktopLayout(double screenWidth) {
    return (isWeb || isDesktop) && screenWidth > 768;
  }
  
  /// Determina el número de columnas para grids según la plataforma y tamaño
  static int getGridColumns(double screenWidth) {
    if (screenWidth > 1400) return 6;
    if (screenWidth > 1200) return 5;
    if (screenWidth > 900) return 4;
    if (screenWidth > 600) return 3;
    return 2;
  }
  
  /// Determina el padding apropiado según la plataforma
  static double getScreenPadding() {
    if (isDesktop || isWeb) return 24.0;
    return 16.0;
  }
}

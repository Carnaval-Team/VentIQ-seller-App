import 'package:flutter/foundation.dart';

class PlatformUtils {
  /// Verifica si la aplicación se está ejecutando en la plataforma web
  static bool get isWeb => kIsWeb;
  
  /// Verifica si la aplicación se está ejecutando en móvil (Android o iOS)
  static bool get isMobile => !kIsWeb;
  
  /// Verifica si la aplicación se está ejecutando en desktop (Windows, macOS, Linux)
  static bool get isDesktop => !kIsWeb && (defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux);
}

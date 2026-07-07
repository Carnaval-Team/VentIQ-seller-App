import 'package:flutter/material.dart';
import '../services/store_config_service.dart';

/// Helper centralizado para decisiones de navegación que dependen de banderas
/// globales (modo restaurante, cuenta activa, etc.). Consolidar la lógica
/// aquí evita duplicarla en cada `_onBottomNavTap` de las pantallas.
class NavigationHelper {
  NavigationHelper._();

  /// Navega al "Home" según el contexto:
  ///
  ///  - Si modo restaurante **está activado**, va SIEMPRE a `/mesas`
  ///    (la grilla de mesas es el home funcional del restaurante, también
  ///    cuando hay una cuenta activa: si el vendedor quiere seguir
  ///    agregando, abre la mesa → la cuenta y desde ahí vuelve a
  ///    /categories).
  ///  - Si modo restaurante está desactivado, va a `/categories` como antes.
  ///
  /// Devuelve un Future por si quieres encadenar; ignorar el await es seguro.
  static Future<void> goHome(BuildContext context, {bool removeStack = true}) {
    final modoRestaurante = StoreConfigService.modoRestauranteSync;

    final route = modoRestaurante ? '/mesas' : '/categories';

    if (removeStack) {
      return Navigator.pushNamedAndRemoveUntil(context, route, (r) => false);
    }
    return Navigator.pushNamed(context, route);
  }
}

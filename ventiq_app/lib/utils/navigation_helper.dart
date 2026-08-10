import 'package:flutter/material.dart';
import '../services/store_config_service.dart';
import '../services/user_preferences_service.dart';

/// Helper centralizado para decisiones de navegación que dependen de banderas
/// globales (modo restaurante, cuenta activa, etc.). Consolidar la lógica
/// aquí evita duplicarla en cada `_onBottomNavTap` de las pantallas.
class NavigationHelper {
  NavigationHelper._();

  /// Destino home según rol de sesión y modo restaurante.
  /// Gerente/supervisor (solo gestión) → `/admin-home`.
  static Future<String> homeRoute() async {
    final inventoryOnly =
        await UserPreferencesService().isInventoryOnlySession();
    if (inventoryOnly) return '/admin-home';
    final modoRestaurante = StoreConfigService.modoRestauranteSync;
    return modoRestaurante ? '/mesas' : '/categories';
  }

  /// Navega al "Home" según el contexto:
  ///
  ///  - Sesión gerente/supervisor → `/admin-home` (sin venta).
  ///  - Si modo restaurante **está activado**, va a `/mesas`.
  ///  - Si no, va a `/categories`.
  static Future<void> goHome(BuildContext context, {bool removeStack = true}) async {
    final route = await homeRoute();

    if (!context.mounted) return;
    if (removeStack) {
      await Navigator.pushNamedAndRemoveUntil(context, route, (r) => false);
    } else {
      await Navigator.pushNamed(context, route);
    }
  }
}

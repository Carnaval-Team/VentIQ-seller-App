import 'package:flutter/material.dart';
import '../services/store_config_service.dart';
import '../services/mesa_cuenta_service.dart';

/// Helper centralizado para decisiones de navegación que dependen de banderas
/// globales (modo restaurante, cuenta activa, etc.). Consolidar la lógica
/// aquí evita duplicarla en cada `_onBottomNavTap` de las pantallas.
class NavigationHelper {
  NavigationHelper._();

  /// Navega al "Home" según el contexto:
  ///
  ///  - Si modo restaurante **está activado** y NO hay una cuenta de mesa
  ///    activa, va a `/mesas` (la grilla de mesas reemplaza el catálogo
  ///    como home funcional del restaurante).
  ///  - Si modo restaurante está activado y SÍ hay una cuenta activa
  ///    (vendedor agregando productos), va a `/categories` para que pueda
  ///    seguir agregando.
  ///  - Si modo restaurante está desactivado, va a `/categories` como antes.
  ///
  /// Devuelve un Future por si quieres encadenar; ignorar el await es seguro.
  static Future<void> goHome(BuildContext context, {bool removeStack = true}) {
    final modoRestaurante = StoreConfigService.modoRestauranteSync;
    final tieneCuentaActiva = MesaCuentaService().activeCuentaId != null;

    String route;
    if (modoRestaurante && !tieneCuentaActiva) {
      route = '/mesas';
    } else {
      route = '/categories';
    }

    if (removeStack) {
      return Navigator.pushNamedAndRemoveUntil(context, route, (r) => false);
    }
    return Navigator.pushNamed(context, route);
  }
}

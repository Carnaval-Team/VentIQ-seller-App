import 'permissions_service.dart';
import 'subscription_guard_service.dart';
import 'subscription_service.dart';
import 'consignacion_service.dart';

/// Punto único para invalidar los cachés en memoria de los servicios
/// singleton. En Flutter Web los singletons sobreviven a la navegación SPA,
/// por lo que su caché puede mostrar datos de una tienda/sesión anterior si
/// no se invalida explícitamente.
///
/// - Al CERRAR SESIÓN: usar [clearForLogout] (limpia todo, incluyendo datos
///   que no dependen de la tienda como roles-por-tienda).
/// - Al CAMBIAR DE TIENDA: usar [clearForStoreSwitch] (limpia lo que depende
///   de la tienda seleccionada, pero conserva lo que es propio del usuario).
class SessionCacheManager {
  /// Invalida los cachés que dependen de la tienda seleccionada.
  /// Los roles-por-tienda se conservan (no cambian al cambiar de tienda).
  static Future<void> clearForStoreSwitch() async {
    // Rol individual + almacén asignado (dependen de la tienda actual).
    PermissionsService().clearCache();

    // Suscripción (se resuelve por tienda).
    SubscriptionService().invalidateCache();
    await SubscriptionGuardService().clearCache();

    // Consignaciones cacheadas por tienda.
    ConsignacionService.clearAllCache();

    print('🧹 SessionCacheManager: cachés por tienda invalidados');
  }

  /// Invalida TODOS los cachés en memoria. Usar solo al cerrar sesión.
  static Future<void> clearForLogout() async {
    // Todo el caché de permisos, incluyendo roles-por-tienda.
    PermissionsService().clearAllCache();

    SubscriptionService().invalidateCache();
    await SubscriptionGuardService().clearCache();

    ConsignacionService.clearAllCache();

    print('🧹 SessionCacheManager: todos los cachés invalidados (logout)');
  }
}

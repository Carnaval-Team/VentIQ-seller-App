import 'store_config_service.dart';

/// Contexto de venta en curso, dentro de una tienda con modo restaurante.
///
/// `modo_restaurante` (flag de tienda, en `StoreConfigService`) dice que la
/// tienda **puede** vender por mesa. No dice que la venta que el vendedor está
/// haciendo ahora mismo sea de mesa: desde el drawer existe "Venta de
/// Mostrador", que es una venta normal — no hay mesa ni comensal — y por tanto
/// debe comportarse como el flujo de siempre (preorden local, checkout que pide
/// cliente, botón de carrito hacia `/preorder`).
///
/// Antes toda la app decidía mirando sólo el flag de tienda, así que entrando
/// por mostrador el carrito seguía siendo "Mesas", el checkout pedía mesa y —lo
/// más grave— los productos se persistían en la cuenta abierta de la última
/// mesa atendida (`OrderService.addItemToCurrentOrder` veía `activeCuentaId`).
///
/// Este servicio guarda ese matiz en memoria y expone [flujoMesaActivo], que es
/// lo que deben consultar los consumidores en lugar de
/// `StoreConfigService.modoRestauranteSync`.
///
/// Deliberadamente **no** se persiste: es un contexto de la sesión de venta, no
/// una preferencia. Al reiniciar la app una tienda de restaurante vuelve a su
/// flujo natural (mesas).
///
/// Tampoco se toca la cuenta de mesa activa al entrar en mostrador: se ignora
/// mientras dure la venta puntual, de forma que el mesero pueda volver a su
/// cuenta pulsando "Mesas y Comensales" sin haber perdido nada.
class SalesModeService {
  SalesModeService._internal();
  static final SalesModeService _instance = SalesModeService._internal();
  factory SalesModeService() => _instance;

  static bool _mostradorActivo = false;

  /// `true` mientras el vendedor esté haciendo una venta de mostrador puntual
  /// en una tienda con modo restaurante activado.
  static bool get mostradorActivo => _mostradorActivo;

  /// `true` sólo cuando la venta en curso es por mesa: la tienda tiene modo
  /// restaurante **y** no estamos en una venta de mostrador.
  ///
  /// Es el reemplazo de `StoreConfigService.modoRestauranteSync` en toda la
  /// lógica de navegación, etiquetas y persistencia de items.
  static bool get flujoMesaActivo =>
      StoreConfigService.modoRestauranteSync && !_mostradorActivo;

  /// Entra en venta de mostrador (desde el drawer → "Venta de Mostrador").
  ///
  /// No tiene efecto si la tienda no está en modo restaurante: allí el flujo
  /// normal ya es el de mostrador.
  static void activarMostrador() {
    if (!StoreConfigService.modoRestauranteSync) return;
    if (_mostradorActivo) return;
    _mostradorActivo = true;
    print('🧾 Venta de mostrador activada (se ignora el flujo de mesas)');
  }

  /// Vuelve al flujo de mesas (al entrar a Mesas o a una cuenta de mesa).
  static void salirDeMostrador() {
    if (!_mostradorActivo) return;
    _mostradorActivo = false;
    print('🍽️ Venta de mostrador cerrada (vuelve el flujo de mesas)');
  }
}

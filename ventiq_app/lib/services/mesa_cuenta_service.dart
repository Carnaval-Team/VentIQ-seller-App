import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/mesa_cuenta.dart';
import '../models/order.dart';
import '../models/payment_method.dart';
import 'user_preferences_service.dart';

/// Servicio para gestionar **cuentas abiertas** de mesas en modo restaurante.
///
/// Una "cuenta abierta" es el carrito persistido en BD de una mesa antes de
/// "cerrar nota" (checkout). Permite que múltiples vendedores la vean, que
/// sobreviva a cierres de app y que NO toque inventario hasta el cobro.
///
/// Wrappers de las RPCs definidas en `mesa_cuenta_abierta.sql`:
///   - fn_abrir_cuenta_mesa
///   - fn_listar_cuentas_mesa
///   - fn_obtener_cuenta_mesa
///   - fn_agregar_item_cuenta_mesa
///   - fn_actualizar_item_cuenta_mesa
///   - fn_actualizar_metodo_pago_item_cuenta
///   - fn_eliminar_item_cuenta_mesa
///   - fn_cancelar_cuenta_mesa
///   - fn_marcar_cuenta_cerrada (invocada por OrderService post-venta)
class MesaCuentaService {
  MesaCuentaService._internal();
  static final MesaCuentaService _instance = MesaCuentaService._internal();
  factory MesaCuentaService() => _instance;

  final SupabaseClient _supabase = Supabase.instance.client;
  final UserPreferencesService _userPrefs = UserPreferencesService();

  /// Estado en memoria para la pantalla de cuenta activa.
  /// El listener UI puede leer esto sincronamente para evitar refetches.
  int? _activeCuentaId;
  int? _activeMesaId;
  String? _activeMesaNumero;
  String? _activeMesaZona;

  int? get activeCuentaId => _activeCuentaId;
  int? get activeMesaId => _activeMesaId;
  String? get activeMesaNumero => _activeMesaNumero;
  String? get activeMesaZona => _activeMesaZona;

  void setActive({
    required int idCuenta,
    required int idMesa,
    String? mesaNumero,
    String? mesaZona,
  }) {
    _activeCuentaId = idCuenta;
    _activeMesaId = idMesa;
    _activeMesaNumero = mesaNumero;
    _activeMesaZona = mesaZona;
    print('🍽️ Cuenta activa: $idCuenta (Mesa $idMesa - $mesaNumero / zona $mesaZona)');
  }

  void clearActive() {
    if (_activeCuentaId != null) {
      print('🍽️ Cuenta activa limpiada (era $_activeCuentaId)');
    }
    _activeCuentaId = null;
    _activeMesaId = null;
    _activeMesaNumero = null;
    _activeMesaZona = null;
  }

  // ----------------------------------------------------------------------
  // RPCs
  // ----------------------------------------------------------------------

  /// Abre una cuenta nueva en la mesa indicada. Si ya hay una abierta y
  /// `forzarNueva` es false, devuelve la existente.
  Future<int> abrirCuenta({
    required int idMesa,
    int? numeroComensales,
    bool forzarNueva = false,
  }) async {
    final idTpv = await _userPrefs.getIdTpv();
    final idVendedor = await _userPrefs.getIdSeller();

    final response = await _supabase.rpc(
      'fn_abrir_cuenta_mesa',
      params: {
        'p_id_mesa': idMesa,
        'p_id_tpv': idTpv,
        'p_id_vendedor': idVendedor,
        'p_numero_comensales': numeroComensales,
        'p_forzar_nueva': forzarNueva,
      },
    );

    if (response is num) {
      return response.toInt();
    }
    if (response is List && response.isNotEmpty && response.first is num) {
      return (response.first as num).toInt();
    }
    throw Exception('fn_abrir_cuenta_mesa devolvió formato inesperado: $response');
  }

  /// Lista cuentas abiertas en una mesa (estado=1).
  Future<List<MesaCuenta>> listarCuentasMesa(int idMesa) async {
    final response = await _supabase.rpc(
      'fn_listar_cuentas_mesa',
      params: {'p_id_mesa': idMesa},
    );

    if (response is! List) return <MesaCuenta>[];
    return response
        .whereType<Map>()
        .map((row) => MesaCuenta.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// Trae el detalle completo de una cuenta (cabecera + items + producto info).
  Future<MesaCuenta> obtenerCuenta(int idCuenta) async {
    final response = await _supabase.rpc(
      'fn_obtener_cuenta_mesa',
      params: {'p_id_cuenta': idCuenta},
    );

    if (response is Map) {
      return MesaCuenta.fromJson(Map<String, dynamic>.from(response));
    }
    throw Exception('fn_obtener_cuenta_mesa devolvió formato inesperado: $response');
  }

  /// Devuelve la cuenta activa cacheada (si la hay) recargada desde BD.
  /// Útil tras agregar items para refrescar la pantalla.
  Future<MesaCuenta?> reloadActive() async {
    if (_activeCuentaId == null) return null;
    return obtenerCuenta(_activeCuentaId!);
  }

  /// Agrega un item a la cuenta. Si ya existe el mismo (producto+variante+
  /// presentación+ubicación+método de pago) la cantidad se acumula.
  Future<int> agregarItem({
    required int idCuenta,
    required int idProducto,
    required double cantidad,
    required double precioUnitario,
    int? idVariante,
    int? idOpcionVariante,
    int? idPresentacion,
    int? idUbicacion,
    double? precioBase,
    int? idMetodoPago,
    Map<String, dynamic>? promotionData,
    Map<String, dynamic>? inventoryData,
    String? notas,
    String? skuProducto,
    String? skuUbicacion,
  }) async {
    final response = await _supabase.rpc(
      'fn_agregar_item_cuenta_mesa',
      params: {
        'p_id_cuenta': idCuenta,
        'p_id_producto': idProducto,
        'p_cantidad': cantidad,
        'p_precio_unitario': precioUnitario,
        'p_id_variante': idVariante,
        'p_id_opcion_variante': idOpcionVariante,
        'p_id_presentacion': idPresentacion,
        'p_id_ubicacion': idUbicacion,
        'p_precio_base': precioBase,
        'p_id_metodo_pago': idMetodoPago,
        'p_promotion_data': promotionData,
        'p_inventory_data': inventoryData,
        'p_notas': notas,
        'p_sku_producto': skuProducto,
        'p_sku_ubicacion': skuUbicacion,
      },
    );

    if (response is num) return response.toInt();
    if (response is List && response.isNotEmpty && response.first is num) {
      return (response.first as num).toInt();
    }
    throw Exception('fn_agregar_item_cuenta_mesa devolvió formato inesperado: $response');
  }

  /// Atajo para agregar un `OrderItem` (el del flujo local) a la cuenta abierta.
  /// Mantiene la consolidación que ya hace `OrderService.addItemToCurrentOrder`.
  Future<int> agregarOrderItem({
    required int idCuenta,
    required OrderItem item,
  }) async {
    final inv = item.inventoryData ?? const {};
    return agregarItem(
      idCuenta: idCuenta,
      idProducto: item.producto.id,
      cantidad: item.cantidad,
      precioUnitario: item.precioUnitario,
      idVariante: item.variante?.id,
      idOpcionVariante: inv['id_opcion_variante'] is num
          ? (inv['id_opcion_variante'] as num).toInt()
          : null,
      idPresentacion: inv['id_presentacion'] is num
          ? (inv['id_presentacion'] as num).toInt()
          : null,
      idUbicacion: inv['id_ubicacion'] is num
          ? (inv['id_ubicacion'] as num).toInt()
          : null,
      precioBase: item.precioBase,
      idMetodoPago: item.paymentMethod?.id,
      promotionData: item.promotionData,
      inventoryData: item.inventoryData,
      skuProducto: inv['sku_producto'] as String?,
      skuUbicacion: inv['sku_ubicacion'] as String?,
    );
  }

  Future<void> actualizarCantidad({
    required int idItem,
    required double cantidad,
  }) async {
    await _supabase.rpc(
      'fn_actualizar_item_cuenta_mesa',
      params: {'p_id_item': idItem, 'p_cantidad': cantidad},
    );
  }

  Future<void> actualizarMetodoPagoItem({
    required int idItem,
    required PaymentMethod? metodo,
  }) async {
    // Si paymentMethod es el "Pago Regular (Efectivo)" especial (id=999) lo
    // tratamos como null para que sea capturado al cerrar la nota.
    final id = (metodo == null || metodo.id == 999) ? null : metodo.id;
    await _supabase.rpc(
      'fn_actualizar_metodo_pago_item_cuenta',
      params: {'p_id_item': idItem, 'p_id_metodo_pago': id},
    );
  }

  Future<void> eliminarItem(int idItem) async {
    await _supabase.rpc(
      'fn_eliminar_item_cuenta_mesa',
      params: {'p_id_item': idItem},
    );
  }

  /// Cancela la cuenta sin generar venta. Los items se conservan como
  /// histórico (estado=3) por si se quiere auditar.
  Future<void> cancelarCuenta(int idCuenta) async {
    await _supabase.rpc(
      'fn_cancelar_cuenta_mesa',
      params: {'p_id_cuenta': idCuenta},
    );
    if (_activeCuentaId == idCuenta) clearActive();
  }

  /// Vincula la cuenta a una operación de venta y la marca cerrada.
  /// Lo invoca `OrderService` cuando termina exitosamente el checkout.
  Future<void> marcarCerrada({
    required int idCuenta,
    required int idOperacionVenta,
  }) async {
    await _supabase.rpc(
      'fn_marcar_cuenta_cerrada',
      params: {
        'p_id_cuenta': idCuenta,
        'p_id_operacion_venta': idOperacionVenta,
      },
    );
    // Limpiar la cuenta activa si era esta. Si no se limpia, NavigationHelper
    // cree que sigue habiendo cuenta abierta y al pulsar Home manda a
    // /categories en lugar de /mesas.
    if (_activeCuentaId == idCuenta) clearActive();
  }
}

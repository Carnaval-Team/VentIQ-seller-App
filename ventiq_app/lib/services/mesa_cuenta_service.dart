import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/mesa_cuenta.dart';
import '../models/order.dart';
import '../models/payment_method.dart';
import '../models/pedido_resultado.dart';
import '../money/mesa_v1.dart';
import '../money/product_currency_order.dart';
import '../utils/uuid_generator.dart';
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

  /// Última cuenta abierta del TPV, para el atajo del botón de carrito.
  ///
  /// En modo restaurante la preorden local no se usa (el carrito vive en BD por
  /// mesa), así que el botón lleva aquí en lugar de a una preorden vacía.
  ///
  /// Devuelve `null` si no hay ninguna abierta o si falla la consulta: el
  /// llamador cae al comportamiento de siempre en vez de quedarse bloqueado.
  Future<UltimaCuentaAbierta?> ultimaCuentaAbierta() async {
    try {
      final idTpv = await _userPrefs.getIdTpv();
      if (idTpv == null) return null;

      final response = await _supabase.rpc(
        'fn_ultima_cuenta_abierta_tpv',
        params: {'p_id_tpv': idTpv},
      );

      if (response is! Map) return null;
      final mapa = Map<String, dynamic>.from(response);

      if (mapa['status'] != 'success') return null;
      if (mapa['id_cuenta'] == null) return null;

      return UltimaCuentaAbierta.fromJson(mapa);
    } catch (e) {
      print('⚠️ No se pudo leer la última cuenta abierta: $e');
      return null;
    }
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

  // ══════════════════════════════════════════════════════════════════════
  // Fase 2 · pedir != cobrar
  //
  // `pedirItem` es la ruta nueva: además de agregar la línea, clasifica el
  // producto, mueve el inventario del almacén correcto (barra o cocina) y
  // dispara la comanda si el plato va a cocina.
  //
  // `agregarItem` (arriba) sigue existiendo y no cambia: las líneas que crea
  // quedan con stock_movido = false y se descuentan al cobrar, como siempre.
  // Es la vía de escape si algo va mal con la ruta nueva.
  // ══════════════════════════════════════════════════════════════════════

  /// Pide un item: lo agrega a la cuenta, descuenta inventario y manda a
  /// cocina si corresponde.
  ///
  /// Devuelve el jsonb completo de `fn_pedir_item_cuenta`, que trae el origen
  /// resuelto, si se movió stock, y los datos de la comanda cuando la hay.
  /// Lanza [PedidoException] si la RPC responde con `status: error`, para que
  /// la UI pueda distinguir "no hay stock" de "esta cocina no atiende a este
  /// TPV" y mostrar el mensaje correcto.
  Future<PedidoResultado> pedirItem({
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
    String? uuidVendedor,
    bool forzarSinStock = false,
  }) async {
    // `_v2` convierte la cantidad a equivalente base. Si no está, no se llama
    // la función con clave ni la anterior: las dos pierden esa conversión
    // hasta que el script 17 haga que la de clave delegue en v2.
    const fnNueva = 'fn_pedir_item_cuenta_v2';
    var fnUsada = fnNueva;
    final params = <String, dynamic>{
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
      'p_uuid_vendedor': uuidVendedor,
      'p_forzar_sin_stock': forzarSinStock,
    };

    dynamic response;
    try {
      response = await _supabase.rpc(fnNueva, params: params);
    } catch (e) {
      if (!_isRpcUnavailable(e, fnNueva)) rethrow;
      print(
        '⚠️ $fnNueva no disponible ($e). '
        'No se pide con la función que pierde la cantidad en base.',
      );
      throw Exception(
        '$fnNueva no está disponible. No se pidió el plato.',
      );
    }

    final mapa = _comoMapa(response);
    if (mapa == null) {
      throw Exception('$fnUsada devolvió formato inesperado: $response');
    }

    if (mapa['status'] != 'success') {
      throw PedidoException.fromJson(mapa);
    }

    return PedidoResultado.fromJson(mapa);
  }

  /// Atajo con un `OrderItem`, equivalente a [agregarOrderItem] pero por la
  /// ruta de Fase 2.
  Future<PedidoResultado> pedirOrderItem({
    required int idCuenta,
    required OrderItem item,
    String? uuidVendedor,
    bool forzarSinStock = false,
  }) async {
    if (item.seleccion != null) {
      return _pedirProductoV1(idCuenta: idCuenta, item: item);
    }
    final inv = item.inventoryData ?? const {};
    return pedirItem(
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
      uuidVendedor: uuidVendedor,
      forzarSinStock: forzarSinStock,
    );
  }

  /// La línea nueva no usa el pedido que une por producto.
  Future<PedidoResultado> _pedirProductoV1({
    required int idCuenta,
    required OrderItem item,
  }) async {
    final seleccion = item.seleccion;
    if (seleccion == null) {
      throw ProductCurrencyException('SNAPSHOT_INVALID');
    }
    final politica = await _userPrefs.getPoliticaMoneda() ?? <String, dynamic>{};
    final revision = politica['revision'];
    final constancia = politica['constancia'];
    if (revision is! Map || constancia is! Map) {
      throw Exception('Falta la constancia. La linea no se pidio.');
    }
    try {
      final response = await _supabase.rpc(
        'fn_m01_pedir_item_mesa_v1',
        params: {
          'p_solicitud': {
            'version_monetaria': 'producto-v1',
            'client_uuid': seleccion.idLineaCliente,
            'id_cuenta': '$idCuenta',
            'id_revision': '${revision['id']}',
            'id_constancia': '${constancia['id']}',
            'dispositivo': constancia['dispositivo'],
            'huella': constancia['huella'],
            'linea': seleccion.toJson(),
          },
        },
      );
      final mapa = _comoMapa(response);
      if (mapa == null || mapa['status'] != 'success') {
        throw Exception('La linea nueva no se pidio');
      }
      return PedidoResultado.fromJson(mapa);
    } catch (error) {
      if (_esDenegacion(error) || _isRpcUnavailable(error, 'fn_m01_pedir_item_mesa_v1')) {
        throw Exception('La linea nueva no se pidio por la via anterior');
      }
      rethrow;
    }
  }

  bool _esDenegacion(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('42501') ||
        text.contains('permission denied') ||
        text.contains('acceso denegado') ||
        text.contains('insufficient_privilege');
  }

  /// Cancela un item ya pedido.
  ///
  /// Si el plato **no** se sirvió, devuelve el stock y cancela la comanda. Si
  /// ya se sirvió, se retira de la cuenta como merma y [motivo] es obligatorio
  /// (la RPC responde `MOTIVO_REQUERIDO` si falta).
  Future<CancelacionResultado> cancelarItemPedido({
    required int idItem,
    String? motivo,
    String? versionMonetaria,
  }) async {
    if (versionMonetaria == 'producto-v1') {
      final clave = 'mesa-cancel-$idItem';
      final guardado = await _userPrefs.leerIntentoVentaV1(clave);
      final uuid = guardado?['client_uuid']?.toString() ?? UuidGenerator.v4();
      await _userPrefs.guardarIntentoVentaV1(clave, {'client_uuid': uuid});
      try {
        final response = await _supabase.rpc(
          'fn_m01_cancelar_item_mesa_v1',
          params: {
            'p_solicitud': {
              'version_monetaria': 'producto-v1',
              'client_uuid': uuid,
              'id_item': '$idItem',
              'motivo': motivo,
            },
          },
        );
        final mapa = _comoMapa(response);
        if (mapa == null || mapa['status'] != 'success') {
          throw Exception('La linea nueva no se cancelo');
        }
        return CancelacionResultado.fromJson(mapa);
      } catch (error) {
        throw Exception('La linea nueva no se cancelo por la via anterior');
      }
    }
    // `_v2` devuelve el stock a la presentación base. Si no está, no se llama
    // la función anterior.
    const fnNueva = 'fn_cancelar_item_pedido_v2';
    var fnUsada = fnNueva;
    final params = <String, dynamic>{'p_id_item': idItem, 'p_motivo': motivo};

    dynamic response;
    try {
      response = await _supabase.rpc(fnNueva, params: params);
    } catch (e) {
      if (!_isRpcUnavailable(e, fnNueva)) rethrow;
      print(
        '⚠️ $fnNueva no disponible ($e). '
        'No se cancela con la función sin conversión a base.',
      );
      throw Exception(
        '$fnNueva no está disponible. No se canceló el plato.',
      );
    }

    final mapa = _comoMapa(response);
    if (mapa == null) {
      throw Exception('$fnUsada devolvió formato inesperado: $response');
    }

    if (mapa['status'] != 'success') {
      throw PedidoException.fromJson(mapa);
    }

    return CancelacionResultado.fromJson(mapa);
  }

  /// Detecta el error de PostgREST cuando una RPC nueva (`_v2`) todavía no
  /// está aplicada en el backend (PGRST202 / "could not find the function" /
  /// "schema cache"), para caer a la función viva del mismo nombre sin tratarlo
  /// como fallo de negocio. Mismo criterio que
  /// `AutoSyncService._isRpcUnavailable`.
  bool _isRpcUnavailable(Object error, String functionName) {
    final text = error.toString().toLowerCase();
    if (text.contains('42501') ||
        text.contains('insufficient_privilege') ||
        text.contains('permission denied') ||
        text.contains('acceso denegado')) {
      return false;
    }
    final fn = functionName.toLowerCase();
    return text.contains('pgrst202') ||
        text.contains('could not find the function') ||
        text.contains('schema cache') ||
        (text.contains('does not exist') && text.contains(fn));
  }

  /// Normaliza la respuesta de una RPC que devuelve jsonb: Supabase puede
  /// entregarla como Map o como lista de un elemento.
  Map<String, dynamic>? _comoMapa(dynamic response) {
    if (response is Map) return Map<String, dynamic>.from(response);
    if (response is List && response.isNotEmpty && response.first is Map) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    return null;
  }

  Future<void> actualizarCantidad({
    required int idItem,
    required double cantidad,
    String? versionMonetaria,
  }) async {
    if (!MesaV1.permiteEditar(versionMonetaria)) {
      throw Exception('La cantidad de la linea nueva no se cambia aqui');
    }
    await _supabase.rpc(
      'fn_actualizar_item_cuenta_mesa',
      params: {'p_id_item': idItem, 'p_cantidad': cantidad},
    );
  }

  Future<void> actualizarMetodoPagoItem({
    required int idItem,
    required PaymentMethod? metodo,
  }) async {
    // 999 ("Pago Regular Efectivo") ya es un método real del catálogo; se
    // envía su id como cualquier otro.
    final id = metodo?.id;
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

  /// Cierra una cuenta producto-v1. No registra la venta ni el cobro por la vía anterior.
  Future<int> finalizarCuentaV1({
    required int idCuenta,
    int? idCliente,
  }) async {
    final clave = 'mesa-cierre-$idCuenta';
    final guardado = await _userPrefs.leerIntentoVentaV1(clave);
    final venta = guardado?['client_uuid']?.toString() ?? UuidGenerator.v4();
    final pago = guardado?['client_uuid_pago']?.toString() ?? UuidGenerator.v4();
    final solicitud = MesaV1.solicitudCierre(
      clientUuid: venta,
      clientUuidPago: pago,
      idCuenta: idCuenta,
      idCliente: idCliente,
    );
    await _userPrefs.guardarIntentoVentaV1(clave, solicitud);
    try {
      final response = await _supabase.rpc(
        'fn_m01_finalizar_cuenta_v1',
        params: {'p_solicitud': solicitud},
      );
      final mapa = _comoMapa(response);
      final id = mapa?['id_operacion'];
      if (mapa == null || mapa['status'] != 'success' || id is! num) {
        throw Exception('La cuenta nueva no se cerro');
      }
      if (_activeCuentaId == idCuenta) clearActive();
      return id.toInt();
    } catch (error) {
      throw Exception('La cuenta nueva no se cerro por la via anterior');
    }
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

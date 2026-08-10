import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/uuid_generator.dart';
import 'connectivity_service.dart';
import 'offline_database_service.dart';
import 'user_preferences_service.dart';

/// Tipos de operaciones Admin Lite encolables offline.
class AdminOpType {
  static const priceUpdate = 'price_update';
  static const stockAdjustment = 'stock_adjustment';
  static const reception = 'reception';
  static const productCreate = 'product_create';
}

/// Servicio de gestión de inventario/productos desde Caja (online + cola offline).
class AdminInventoryService {
  static final AdminInventoryService _instance =
      AdminInventoryService._internal();
  factory AdminInventoryService() => _instance;
  AdminInventoryService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final OfflineDatabaseService _db = OfflineDatabaseService();
  final UserPreferencesService _prefs = UserPreferencesService();
  final ConnectivityService _connectivity = ConnectivityService();

  /// Lista productos del cache offline (Admin Lite stock/productos).
  Future<List<Map<String, dynamic>>> listCachedProducts({
    String? query,
  }) async {
    if (query != null && query.trim().isNotEmpty) {
      return _db.searchProducts(query.trim(), limit: 100);
    }
    final grouped = await _db.getProductsGroupedByCategory();
    final all = <Map<String, dynamic>>[];
    for (final list in grouped.values) {
      all.addAll(list);
    }
    all.sort(
      (a, b) => (a['denominacion']?.toString() ?? '').compareTo(
        b['denominacion']?.toString() ?? '',
      ),
    );
    return all;
  }

  Future<List<Map<String, dynamic>>> listCachedCategories() {
    return _db.getCategories();
  }

  /// Actualiza precio de venta y/o costo. Offline → cola; online → RPC/tablas.
  Future<void> updateProductPrices({
    required int productId,
    int? presentationId,
    double? precioVentaCup,
    double? precioCostoUsd,
  }) async {
    final clientUuid = UuidGenerator.v4();
    final payload = {
      'id_producto': productId,
      'id_presentacion': presentationId,
      'precio_venta_cup': precioVentaCup,
      'precio_costo_usd': precioCostoUsd,
    };

    await _applyPriceLocally(payload);

    if (_connectivity.isConnected) {
      try {
        await _syncPriceUpdate(clientUuid, payload);
        return;
      } catch (e) {
        print('⚠️ AdminInventory: fallo online precio, encolando: $e');
      }
    }

    await _db.enqueueAdminOp(
      clientUuid: clientUuid,
      opType: AdminOpType.priceUpdate,
      payload: await _stampPayload(payload),
    );
  }

  /// Ajuste de inventario (cantidad nueva absoluta).
  Future<void> adjustStock({
    required int productId,
    required int? presentationId,
    required int? locationId,
    required double cantidadAnterior,
    required double cantidadNueva,
    required String motivo,
    String observaciones = '',
  }) async {
    if (locationId == null) {
      throw Exception(
        'El producto no tiene ubicación de inventario en cache. '
        'Sincroniza productos online e intenta de nuevo.',
      );
    }

    final user = _supabase.auth.currentUser;
    final clientUuid = UuidGenerator.v4();
    final payload = {
      'id_producto': productId,
      'id_presentacion': presentationId,
      'id_ubicacion': locationId,
      'cantidad_anterior': cantidadAnterior,
      'cantidad_nueva': cantidadNueva,
      'motivo': motivo,
      'observaciones': observaciones,
      'uuid_usuario': user?.id,
    };

    await _applyStockDeltaLocally(
      productId: productId,
      delta: cantidadNueva - cantidadAnterior,
    );

    if (_connectivity.isConnected) {
      try {
        await _syncStockAdjustment(clientUuid, payload);
        return;
      } catch (e) {
        print('⚠️ AdminInventory: fallo online ajuste, encolando: $e');
      }
    }

    await _db.enqueueAdminOp(
      clientUuid: clientUuid,
      opType: AdminOpType.stockAdjustment,
      payload: await _stampPayload(payload),
    );
  }

  /// Recepción simple (uno o más productos).
  Future<void> registerReception({
    required List<Map<String, dynamic>> productos,
    required String entregadoPor,
    required String recibidoPor,
    String observaciones = '',
    String monedaFactura = 'USD',
    double montoTotal = 0,
  }) async {
    final storeId = await _prefs.getIdTienda();
    final userId =
        _supabase.auth.currentUser?.id ?? await _prefs.getUserId();
    if (storeId == null || userId == null) {
      throw Exception('Sin tienda o usuario autenticado');
    }

    final clientUuid = UuidGenerator.v4();
    final payload = {
      'id_tienda': storeId,
      'entregado_por': entregadoPor,
      'recibido_por': recibidoPor,
      'observaciones': observaciones,
      'moneda_factura': monedaFactura,
      'monto_total': montoTotal,
      'motivo': 1,
      'productos': productos,
      'uuid': userId,
    };

    for (final p in productos) {
      final id = (p['id_producto'] as num?)?.toInt();
      final qty = (p['cantidad'] as num?)?.toDouble() ?? 0;
      if (id != null && qty != 0) {
        await _applyStockDeltaLocally(productId: id, delta: qty);
      }
    }

    if (_connectivity.isConnected && _supabase.auth.currentUser != null) {
      try {
        await _syncReception(clientUuid, payload);
        return;
      } catch (e) {
        print('⚠️ AdminInventory: fallo online recepción, encolando: $e');
      }
    }

    await _db.enqueueAdminOp(
      clientUuid: clientUuid,
      opType: AdminOpType.reception,
      payload: await _stampPayload(payload),
    );
  }

  /// Alta rápida de producto (datos básicos).
  Future<void> createProductQuick({
    required String denominacion,
    required double precioVentaCup,
    double precioCostoUsd = 0,
    int? idCategoria,
  }) async {
    final storeId = await _prefs.getIdTienda();
    final user = _supabase.auth.currentUser;
    if (storeId == null) throw Exception('Sin tienda');

    final clientUuid = UuidGenerator.v4();
    final payload = {
      'id_tienda': storeId,
      'denominacion': denominacion,
      'precio_venta_cup': precioVentaCup,
      'precio_costo_usd': precioCostoUsd,
      'id_categoria': idCategoria,
      'uuid': user?.id,
    };

    if (_connectivity.isConnected) {
      try {
        await _syncProductCreate(clientUuid, payload);
        return;
      } catch (e) {
        print('⚠️ AdminInventory: fallo online alta producto, encolando: $e');
      }
    }

    // Offline: producto temporal negativo en cache para poder venderlo después
    // de sync (el id real llegará al sincronizar catálogo).
    final tempId = -DateTime.now().millisecondsSinceEpoch;
    await _db.mergeSections({
      'products': {
        '_pending': [
          {
            'id': tempId,
            'denominacion': denominacion,
            'precio': precioVentaCup,
            'cantidad': 0,
            'pending_create_uuid': clientUuid,
          },
        ],
      },
    });

    await _db.enqueueAdminOp(
      clientUuid: clientUuid,
      opType: AdminOpType.productCreate,
      payload: await _stampPayload(payload),
    );
  }

  /// Sube todas las ops admin pendientes. Retorna cuántas se sincronizaron.
  Future<int> syncPendingOps() async {
    final pending = await _db.getPendingAdminOps();
    if (pending.isEmpty) return 0;

    var ok = 0;
    for (final op in pending) {
      final uuid = op['client_uuid'] as String;
      final type = op['op_type'] as String;
      final payload = Map<String, dynamic>.from(op['payload'] as Map);
      try {
        switch (type) {
          case AdminOpType.priceUpdate:
            await _syncPriceUpdate(uuid, payload);
            break;
          case AdminOpType.stockAdjustment:
            await _syncStockAdjustment(uuid, payload);
            break;
          case AdminOpType.reception:
            await _syncReception(uuid, payload);
            break;
          case AdminOpType.productCreate:
            await _syncProductCreate(uuid, payload);
            break;
          default:
            throw Exception('Tipo de op desconocido: $type');
        }
        await _db.markAdminOpSynced(uuid);
        ok++;
      } catch (e) {
        await _db.markAdminOpError(uuid, e.toString());
        print('❌ AdminInventory sync $type ($uuid): $e');
      }
    }
    return ok;
  }

  Future<int> pendingCount() => _db.countPendingAdminOps();

  Future<Map<String, dynamic>> _stampPayload(
    Map<String, dynamic> payload,
  ) async {
    final stamped = Map<String, dynamic>.from(payload);
    stamped['offline_user_id'] ??= _supabase.auth.currentUser?.id;
    stamped['offline_store_id'] ??= await _prefs.getOfflineInventoryStoreId();
    return stamped;
  }

  // --- Local cache helpers ---

  Future<void> _applyPriceLocally(Map<String, dynamic> payload) async {
    final productId = (payload['id_producto'] as num).toInt();
    final venta = (payload['precio_venta_cup'] as num?)?.toDouble();
    final product = await _db.getProductById(productId);
    if (product == null) return;

    if (venta != null) {
      product['precio'] = venta;
      // Actualizar también en detalles si existen
      final detalles = product['detalles_completos'];
      if (detalles is Map) {
        final precios = detalles['precios'];
        if (precios is Map) {
          precios['precio_venta_cup'] = venta;
        }
      }
    }

    // Re-guardar producto en su categoría
    final grouped = await _db.getProductsGroupedByCategory();
    for (final entry in grouped.entries) {
      final list = entry.value;
      for (var i = 0; i < list.length; i++) {
        if (list[i]['id'] == productId) {
          list[i] = product;
          await _db.mergeSections({'products': grouped});
          return;
        }
      }
    }
  }

  Future<void> _applyStockDeltaLocally({
    required int productId,
    required double delta,
  }) async {
    await _prefs.updateProductInventoryInCache(
      productId,
      null,
      // updateProductInventoryInCache resta; para sumar pasamos negativo
      (-delta).toInt(),
    );
  }

  // --- Remote sync ---

  Future<void> _syncPriceUpdate(
    String clientUuid,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _supabase.rpc(
        'fn_admin_caja_actualizar_precios_offline',
        params: {
          'p_client_uuid': clientUuid,
          'p_id_producto': payload['id_producto'],
          'p_id_presentacion': payload['id_presentacion'],
          'p_precio_venta_cup': payload['precio_venta_cup'],
          'p_precio_costo_usd': payload['precio_costo_usd'],
        },
      );
    } catch (e) {
      // Fallback directo a tablas si el RPC aún no está desplegado
      print('⚠️ fn_admin_caja_actualizar_precios_offline: $e — fallback');
      final productId = (payload['id_producto'] as num).toInt();
      final venta = (payload['precio_venta_cup'] as num?)?.toDouble();
      final costo = (payload['precio_costo_usd'] as num?)?.toDouble();
      final presentationId = (payload['id_presentacion'] as num?)?.toInt();

      if (venta != null) {
        final today = DateTime.now().toIso8601String().substring(0, 10);
        final existing = await _supabase
            .from('app_dat_precio_venta')
            .select('id')
            .eq('id_producto', productId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (existing != null) {
          await _supabase
              .from('app_dat_precio_venta')
              .update({
                'precio_venta_cup': venta,
                'fecha_desde': today,
                'fecha_hasta': null,
              })
              .eq('id', existing['id']);
        } else {
          await _supabase.from('app_dat_precio_venta').insert({
            'id_producto': productId,
            'precio_venta_cup': venta,
            'fecha_desde': today,
          });
        }
      }

      if (costo != null && presentationId != null) {
        await _supabase
            .from('app_dat_producto_presentacion')
            .update({'precio_promedio': costo})
            .eq('id', presentationId);
      } else if (costo != null) {
        await _supabase
            .from('app_dat_producto_presentacion')
            .update({'precio_promedio': costo})
            .eq('id_producto', productId)
            .eq('es_base', true);
      }
    }
  }

  Future<void> _syncStockAdjustment(
    String clientUuid,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _supabase.rpc(
        'fn_admin_caja_ajuste_inventario_offline',
        params: {
          'p_client_uuid': clientUuid,
          'p_id_producto': payload['id_producto'],
          'p_id_ubicacion': payload['id_ubicacion'],
          'p_id_presentacion': payload['id_presentacion'],
          'p_cantidad_anterior': payload['cantidad_anterior'],
          'p_cantidad_nueva': payload['cantidad_nueva'],
          'p_motivo': payload['motivo'] ?? 'Ajuste desde Caja',
          'p_observaciones': payload['observaciones'] ?? '',
          'p_uuid_usuario': payload['uuid_usuario'],
        },
      );
    } catch (e) {
      print('⚠️ fn_admin_caja_ajuste_inventario_offline: $e — fallback');
      // Tipo operación ajuste: buscar id o usar 0 y dejar que falle con mensaje claro
      await _supabase.rpc(
        'fn_insertar_ajuste_inventario2',
        params: {
          'p_id_producto': payload['id_producto'],
          'p_id_ubicacion': payload['id_ubicacion'],
          'p_id_presentacion': payload['id_presentacion'],
          'p_cantidad_anterior': payload['cantidad_anterior'],
          'p_cantidad_nueva': payload['cantidad_nueva'],
          'p_motivo': payload['motivo'] ?? 'Ajuste desde Caja',
          'p_observaciones':
              '${payload['observaciones'] ?? ''} [caja:$clientUuid]',
          'p_uuid_usuario': payload['uuid_usuario'],
          'p_id_tipo_operacion': await _resolveAjusteTipoOperacionId(),
        },
      );
    }
  }

  Future<int> _resolveAjusteTipoOperacionId() async {
    try {
      final row = await _supabase
          .from('app_nom_tipo_operacion')
          .select('id')
          .ilike('denominacion', '%ajuste%')
          .limit(1)
          .maybeSingle();
      return (row?['id'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _syncReception(
    String clientUuid,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _supabase.rpc(
        'fn_admin_caja_recepcion_offline',
        params: {
          'p_client_uuid': clientUuid,
          'p_entregado_por': payload['entregado_por'],
          'p_id_tienda': payload['id_tienda'],
          'p_monto_total': payload['monto_total'] ?? 0,
          'p_motivo': payload['motivo'] ?? 1,
          'p_observaciones': payload['observaciones'] ?? '',
          'p_productos': payload['productos'],
          'p_recibido_por': payload['recibido_por'],
          'p_uuid': payload['uuid'],
          'p_moneda_factura': payload['moneda_factura'] ?? 'USD',
        },
      );
    } catch (e) {
      print('⚠️ fn_admin_caja_recepcion_offline: $e — fallback');
      await _supabase.rpc(
        'fn_registrar_recepcion_con_inventario',
        params: {
          'p_entregado_por': payload['entregado_por'],
          'p_id_tienda': payload['id_tienda'],
          'p_monto_total': payload['monto_total'] ?? 0,
          'p_motivo': payload['motivo'] ?? 1,
          'p_observaciones':
              '${payload['observaciones'] ?? ''} [caja:$clientUuid]',
          'p_productos': payload['productos'],
          'p_recibido_por': payload['recibido_por'],
          'p_uuid': payload['uuid'],
          'p_moneda_factura': payload['moneda_factura'] ?? 'USD',
        },
      );
    }
  }

  Future<void> _syncProductCreate(
    String clientUuid,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _supabase.rpc(
        'fn_admin_caja_crear_producto_offline',
        params: {
          'p_client_uuid': clientUuid,
          'p_id_tienda': payload['id_tienda'],
          'p_denominacion': payload['denominacion'],
          'p_precio_venta_cup': payload['precio_venta_cup'],
          'p_precio_costo_usd': payload['precio_costo_usd'] ?? 0,
          'p_id_categoria': payload['id_categoria'],
        },
      );
    } catch (e) {
      print('⚠️ fn_admin_caja_crear_producto_offline: $e — fallback insert');
      final insert = await _supabase
          .from('app_dat_producto')
          .insert({
            'denominacion': payload['denominacion'],
            'id_tienda': payload['id_tienda'],
          })
          .select('id')
          .single();
      final productId = insert['id'] as int;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      await _supabase.from('app_dat_precio_venta').insert({
        'id_producto': productId,
        'precio_venta_cup': payload['precio_venta_cup'] ?? 0,
        'fecha_desde': today,
      });
      final costo = (payload['precio_costo_usd'] as num?)?.toDouble() ?? 0;
      await _supabase.from('app_dat_producto_presentacion').insert({
        'id_producto': productId,
        'id_presentacion': 1,
        'cantidad': 1,
        'es_base': true,
        'precio_promedio': costo,
      });
      final catId = (payload['id_categoria'] as num?)?.toInt();
      if (catId != null) {
        try {
          await _supabase.from('app_dat_productos_subcategorias').insert({
            'id_producto': productId,
            'id_sub_categoria': catId,
          });
        } catch (_) {
          // Categoría opcional
        }
      }
    }
  }
}

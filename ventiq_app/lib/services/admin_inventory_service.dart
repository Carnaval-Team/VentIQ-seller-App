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
  static const extraction = 'extraction';
  static const transfer = 'transfer';
  static const saleByAgreement = 'sale_by_agreement';
  static const tpvPriceUpsert = 'tpv_price_upsert';
  static const tpvCreate = 'tpv_create';
  static const tpvUpdate = 'tpv_update';
  static const vendorAssignTpv = 'vendor_assign_tpv';
  static const vendorUpdateFlags = 'vendor_update_flags';
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
    int? idProveedor,
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
      if (idProveedor != null) 'id_proveedor': idProveedor,
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

  /// Motivos de extracción (cache local; fallback fijo si vacío).
  Future<List<Map<String, dynamic>>> listExtractionMotives() async {
    final section = await _db.getSection('extraction_motives');
    if (section is List && section.isNotEmpty) {
      return section
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [
      {'id': 1, 'denominacion': 'Merma / daño'},
      {'id': 2, 'denominacion': 'Uso interno'},
      {'id': 3, 'denominacion': 'Devolución a proveedor'},
      {'id': 4, 'denominacion': 'Otro'},
    ];
  }

  Future<List<Map<String, dynamic>>> listCachedLayouts() async {
    var layouts = await _db.getCachedLayouts();
    if (layouts.isEmpty && _connectivity.isConnected) {
      try {
        await syncLayoutsFromServer();
        layouts = await _db.getCachedLayouts();
      } catch (e) {
        print('⚠️ AdminInventory: no se pudieron bajar layouts: $e');
      }
    }
    return layouts;
  }

  /// Baja layouts/ubicaciones de la tienda al cache offline.
  Future<int> syncLayoutsFromServer() async {
    final storeId = await _prefs.getIdTienda();
    if (storeId == null) return 0;

    final almacenes = await _supabase
        .from('app_dat_almacen')
        .select('id, denominacion')
        .eq('id_tienda', storeId);

    final almacenIds = <int>[];
    final almacenNames = <int, String>{};
    for (final row in (almacenes as List)) {
      final map = Map<String, dynamic>.from(row as Map);
      final id = (map['id'] as num?)?.toInt();
      if (id == null) continue;
      almacenIds.add(id);
      almacenNames[id] = map['denominacion']?.toString() ?? 'Almacén $id';
    }

    if (almacenIds.isEmpty) {
      await _db.saveCachedLayouts([]);
      return 0;
    }

    final rows = await _supabase
        .from('app_dat_layout_almacen')
        .select('id, denominacion, id_almacen')
        .inFilter('id_almacen', almacenIds);

    final layouts = <Map<String, dynamic>>[];
    for (final row in (rows as List)) {
      final map = Map<String, dynamic>.from(row as Map);
      final almacenId = (map['id_almacen'] as num?)?.toInt();
      final almacenName =
          almacenId != null ? almacenNames[almacenId] : null;
      layouts.add({
        'id': map['id'],
        'denominacion': map['denominacion'],
        'id_almacen': almacenId,
        'almacen': almacenName,
        'label':
            '${almacenName ?? 'Almacén'} · ${map['denominacion'] ?? map['id']}',
      });
    }
    await _db.saveCachedLayouts(layouts);

    // Motivos de extracción (best-effort)
    try {
      final motives = await _supabase.rpc('fn_listar_motivos_extraccion');
      if (motives is List && motives.isNotEmpty) {
        await _db.mergeSections({
          'extraction_motives': motives
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
        });
      }
    } catch (e) {
      print('⚠️ AdminInventory: motivos extracción no disponibles: $e');
    }

    return layouts.length;
  }

  Future<List<Map<String, dynamic>>> listCachedSuppliers({String? query}) async {
    final section = await _db.getSection('suppliers');
    var list = <Map<String, dynamic>>[];
    if (section is List) {
      list = section
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (list.isEmpty && _connectivity.isConnected) {
      try {
        await syncCrmCacheFromServer();
        final again = await _db.getSection('suppliers');
        if (again is List) {
          list = again
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (e) {
        print('⚠️ AdminInventory: sync proveedores: $e');
      }
    }
    final q = query?.trim().toLowerCase();
    if (q != null && q.isNotEmpty) {
      list = list
          .where(
            (s) => (s['denominacion']?.toString().toLowerCase() ?? '')
                .contains(q),
          )
          .toList();
    }
    list.sort(
      (a, b) => (a['denominacion']?.toString() ?? '').compareTo(
        b['denominacion']?.toString() ?? '',
      ),
    );
    return list;
  }

  Future<List<Map<String, dynamic>>> listCachedCustomers({String? query}) async {
    final section = await _db.getSection('customers');
    var list = <Map<String, dynamic>>[];
    if (section is List) {
      list = section
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (list.isEmpty && _connectivity.isConnected) {
      try {
        await syncCrmCacheFromServer();
        final again = await _db.getSection('customers');
        if (again is List) {
          list = again
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (e) {
        print('⚠️ AdminInventory: sync clientes: $e');
      }
    }
    final q = query?.trim().toLowerCase();
    if (q != null && q.isNotEmpty) {
      list = list.where((c) {
        final name = c['nombre_completo']?.toString().toLowerCase() ?? '';
        final phone = c['telefono']?.toString().toLowerCase() ?? '';
        final code = c['codigo_cliente']?.toString().toLowerCase() ?? '';
        return name.contains(q) || phone.contains(q) || code.contains(q);
      }).toList();
    }
    list.sort(
      (a, b) => (a['nombre_completo']?.toString() ?? '').compareTo(
        b['nombre_completo']?.toString() ?? '',
      ),
    );
    return list;
  }

  /// Cache local de proveedores + clientes para Admin Lite offline.
  Future<Map<String, int>> syncCrmCacheFromServer() async {
    final storeId = await _prefs.getIdTienda();
    if (storeId == null) return {'suppliers': 0, 'customers': 0};

    final suppliersRaw = await _supabase
        .from('app_dat_proveedor')
        .select('id, denominacion, direccion, sku_codigo, idtienda')
        .eq('idtienda', storeId)
        .order('denominacion');

    final suppliers = (suppliersRaw as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    // Clientes no tienen id_tienda: cachear activos recientes (tope).
    final customersRaw = await _supabase
        .from('app_dat_clientes')
        .select(
          'id, codigo_cliente, nombre_completo, telefono, email, activo',
        )
        .eq('activo', true)
        .order('nombre_completo')
        .limit(500);

    final customers = (customersRaw as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    await _db.mergeSections({
      'suppliers': suppliers,
      'customers': customers,
    });
    return {'suppliers': suppliers.length, 'customers': customers.length};
  }

  Future<List<Map<String, dynamic>>> listCachedTpvs() async {
    final section = await _db.getSection('tpvs');
    if (section is List && section.isNotEmpty) {
      return section
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (_connectivity.isConnected) {
      try {
        await syncTpvsAndPricesFromServer();
        final again = await _db.getSection('tpvs');
        if (again is List) {
          return again
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (e) {
        print('⚠️ AdminInventory: sync TPVs: $e');
      }
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> listCachedTpvPrices({
    int? idTpv,
    String? query,
  }) async {
    final section = await _db.getSection('tpv_prices');
    var list = <Map<String, dynamic>>[];
    if (section is List) {
      list = section
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (list.isEmpty && _connectivity.isConnected) {
      try {
        await syncTpvsAndPricesFromServer();
        final again = await _db.getSection('tpv_prices');
        if (again is List) {
          list = again
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (e) {
        print('⚠️ AdminInventory: sync precios TPV: $e');
      }
    }
    if (idTpv != null) {
      list = list
          .where((p) => (p['id_tpv'] as num?)?.toInt() == idTpv)
          .toList();
    }
    final q = query?.trim().toLowerCase();
    if (q != null && q.isNotEmpty) {
      list = list.where((p) {
        final name = p['producto_nombre']?.toString().toLowerCase() ?? '';
        final sku = p['producto_sku']?.toString().toLowerCase() ?? '';
        final tpv = p['tpv_nombre']?.toString().toLowerCase() ?? '';
        return name.contains(q) || sku.contains(q) || tpv.contains(q);
      }).toList();
    }
    list.sort((a, b) {
      final ta = a['tpv_nombre']?.toString() ?? '';
      final tb = b['tpv_nombre']?.toString() ?? '';
      final c = ta.compareTo(tb);
      if (c != 0) return c;
      return (a['producto_nombre']?.toString() ?? '').compareTo(
        b['producto_nombre']?.toString() ?? '',
      );
    });
    return list;
  }

  /// Cache TPVs de la tienda + precios + vendedores + almacenes.
  Future<Map<String, int>> syncTpvsAndPricesFromServer() async {
    final storeId = await _prefs.getIdTienda();
    if (storeId == null) {
      return {'tpvs': 0, 'tpv_prices': 0, 'vendors': 0, 'warehouses': 0};
    }

    final almacenesRaw = await _supabase
        .from('app_dat_almacen')
        .select('id, denominacion, id_tienda')
        .eq('id_tienda', storeId)
        .order('denominacion');
    final warehouses = (almacenesRaw as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final warehouseNames = <int, String>{
      for (final w in warehouses)
        if ((w['id'] as num?) != null)
          (w['id'] as num).toInt(): w['denominacion']?.toString() ?? '',
    };

    final tpvsRaw = await _supabase
        .from('app_dat_tpv')
        .select('id, denominacion, id_almacen, id_tienda')
        .eq('id_tienda', storeId)
        .order('denominacion');

    final tpvs = <Map<String, dynamic>>[];
    for (final row in (tpvsRaw as List)) {
      final map = Map<String, dynamic>.from(row as Map);
      final idAlmacen = (map['id_almacen'] as num?)?.toInt();
      tpvs.add({
        ...map,
        'almacen': idAlmacen != null ? warehouseNames[idAlmacen] : null,
      });
    }
    final tpvIds = tpvs
        .map((t) => (t['id'] as num?)?.toInt())
        .whereType<int>()
        .toList();
    final tpvNames = <int, String>{
      for (final t in tpvs)
        if ((t['id'] as num?) != null)
          (t['id'] as num).toInt(): t['denominacion']?.toString() ?? '',
    };

    var prices = <Map<String, dynamic>>[];
    if (tpvIds.isNotEmpty) {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final pricesRaw = await _supabase
          .from('app_dat_precio_tpv')
          .select(
            'id, id_producto, id_tpv, precio_venta_cup, fecha_desde, '
            'fecha_hasta, es_activo, deleted_at, '
            'app_dat_producto(denominacion, sku)',
          )
          .inFilter('id_tpv', tpvIds)
          .isFilter('deleted_at', null)
          .eq('es_activo', true);

      for (final row in (pricesRaw as List)) {
        final map = Map<String, dynamic>.from(row as Map);
        final prod = map['app_dat_producto'];
        final idTpv = (map['id_tpv'] as num?)?.toInt();
        final desde = map['fecha_desde']?.toString() ?? '';
        final hasta = map['fecha_hasta']?.toString();
        if (desde.isNotEmpty && desde.compareTo(today) > 0) continue;
        if (hasta != null &&
            hasta.isNotEmpty &&
            hasta.compareTo(today) < 0) {
          continue;
        }
        prices.add({
          'id': map['id'],
          'id_producto': map['id_producto'],
          'id_tpv': idTpv,
          'precio_venta_cup': map['precio_venta_cup'],
          'fecha_desde': map['fecha_desde'],
          'fecha_hasta': map['fecha_hasta'],
          'es_activo': map['es_activo'] == true,
          'producto_nombre': prod is Map ? prod['denominacion'] : null,
          'producto_sku': prod is Map ? prod['sku'] : null,
          'tpv_nombre': idTpv != null ? tpvNames[idTpv] : null,
        });
      }
    }

    // Vendedores de la tienda
    final trabajadores = await _supabase
        .from('app_dat_trabajadores')
        .select('id, nombres, apellidos, id_roll, id_tienda, user_mail, uuid')
        .eq('id_tienda', storeId);
    final trabajadorIds = (trabajadores as List)
        .map((t) => t['id'])
        .where((id) => id != null)
        .toList();

    final vendors = <Map<String, dynamic>>[];
    if (trabajadorIds.isNotEmpty) {
      final vendedores = await _supabase
          .from('app_dat_vendedor')
          .select('''
            id, uuid, id_tpv, id_trabajador, permitir_customizar_precio_venta,
            trabajador:app_dat_trabajadores(
              id, nombres, apellidos, id_roll, user_mail, uuid
            )
          ''')
          .inFilter('id_trabajador', trabajadorIds);

      final registered = await _prefs.getOfflineUsersForStore(storeId);
      final registeredEmails = registered
          .map((u) => u['email']?.toString().toLowerCase())
          .whereType<String>()
          .toSet();

      for (final raw in (vendedores as List)) {
        final v = Map<String, dynamic>.from(raw as Map);
        final trab = v['trabajador'] is Map
            ? Map<String, dynamic>.from(v['trabajador'] as Map)
            : <String, dynamic>{};
        final idTpv = (v['id_tpv'] as num?)?.toInt();
        final email = (trab['user_mail'] ?? '').toString().trim();
        vendors.add({
          'id': v['id'],
          'uuid': v['uuid'] ?? trab['uuid'],
          'id_tpv': idTpv,
          'id_trabajador': v['id_trabajador'] ?? trab['id'],
          'nombres': trab['nombres'] ?? '',
          'apellidos': trab['apellidos'] ?? '',
          'email': email,
          'permitir_customizar_precio_venta':
              v['permitir_customizar_precio_venta'] == true,
          'tpv_nombre': idTpv != null ? tpvNames[idTpv] : null,
          'registered_offline': email.isNotEmpty &&
              registeredEmails.contains(email.toLowerCase()),
        });
      }
    }

    await _db.mergeSections({
      'tpvs': tpvs,
      'tpv_prices': prices,
      'vendors': vendors,
      'warehouses': warehouses,
    });
    return {
      'tpvs': tpvs.length,
      'tpv_prices': prices.length,
      'vendors': vendors.length,
      'warehouses': warehouses.length,
    };
  }

  Future<List<Map<String, dynamic>>> listCachedVendors({String? query}) async {
    final section = await _db.getSection('vendors');
    var list = <Map<String, dynamic>>[];
    if (section is List) {
      list = section
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (list.isEmpty && _connectivity.isConnected) {
      try {
        await syncTpvsAndPricesFromServer();
        final again = await _db.getSection('vendors');
        if (again is List) {
          list = again
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (e) {
        print('⚠️ AdminInventory: sync vendors: $e');
      }
    }
    final q = query?.trim().toLowerCase();
    if (q != null && q.isNotEmpty) {
      list = list.where((v) {
        final name =
            '${v['nombres'] ?? ''} ${v['apellidos'] ?? ''}'.toLowerCase();
        final email = v['email']?.toString().toLowerCase() ?? '';
        final tpv = v['tpv_nombre']?.toString().toLowerCase() ?? '';
        return name.contains(q) || email.contains(q) || tpv.contains(q);
      }).toList();
    }
    list.sort((a, b) {
      final na = '${a['nombres'] ?? ''} ${a['apellidos'] ?? ''}';
      final nb = '${b['nombres'] ?? ''} ${b['apellidos'] ?? ''}';
      return na.compareTo(nb);
    });
    return list;
  }

  Future<List<Map<String, dynamic>>> listCachedWarehouses() async {
    final section = await _db.getSection('warehouses');
    if (section is List && section.isNotEmpty) {
      return section
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    // Fallback: únicos desde layouts
    final layouts = await listCachedLayouts();
    final seen = <int>{};
    final out = <Map<String, dynamic>>[];
    for (final l in layouts) {
      final id = (l['id_almacen'] as num?)?.toInt();
      if (id == null || seen.contains(id)) continue;
      seen.add(id);
      out.add({
        'id': id,
        'denominacion': l['almacen'] ?? 'Almacén $id',
      });
    }
    return out;
  }

  Future<void> createTpvOffline({
    required String denominacion,
    required int idAlmacen,
    String? almacenNombre,
  }) async {
    final storeId = await _prefs.getIdTienda();
    if (storeId == null) throw Exception('Sin tienda');
    final name = denominacion.trim();
    if (name.isEmpty) throw Exception('Nombre de TPV requerido');

    final clientUuid = UuidGenerator.v4();
    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final payload = {
      'temp_id': tempId,
      'denominacion': name,
      'id_almacen': idAlmacen,
      'id_tienda': storeId,
      'almacen': almacenNombre,
    };

    final tpvs = await listCachedTpvs();
    tpvs.add({
      'id': tempId,
      'denominacion': name,
      'id_almacen': idAlmacen,
      'id_tienda': storeId,
      'almacen': almacenNombre,
      'pending_local': true,
    });
    await _db.mergeSections({'tpvs': tpvs});

    if (_connectivity.isConnected && _supabase.auth.currentUser != null) {
      try {
        await _syncTpvCreate(clientUuid, payload);
        await syncTpvsAndPricesFromServer();
        return;
      } catch (e) {
        print('⚠️ AdminInventory: fallo online create TPV, encolando: $e');
      }
    }

    await _db.enqueueAdminOp(
      clientUuid: clientUuid,
      opType: AdminOpType.tpvCreate,
      payload: await _stampPayload(payload),
    );
  }

  Future<void> updateTpvOffline({
    required int idTpv,
    required String denominacion,
  }) async {
    final name = denominacion.trim();
    if (name.isEmpty) throw Exception('Nombre de TPV requerido');
    if (idTpv < 0) {
      throw Exception('TPV pendiente de sync; espera a sincronizar');
    }

    final clientUuid = UuidGenerator.v4();
    final payload = {'id': idTpv, 'denominacion': name};

    final tpvs = await listCachedTpvs();
    for (var i = 0; i < tpvs.length; i++) {
      if ((tpvs[i]['id'] as num?)?.toInt() == idTpv) {
        tpvs[i] = {...tpvs[i], 'denominacion': name, 'pending_local': true};
      }
    }
    await _db.mergeSections({'tpvs': tpvs});

    if (_connectivity.isConnected && _supabase.auth.currentUser != null) {
      try {
        await _syncTpvUpdate(clientUuid, payload);
        return;
      } catch (e) {
        print('⚠️ AdminInventory: fallo online update TPV, encolando: $e');
      }
    }

    await _db.enqueueAdminOp(
      clientUuid: clientUuid,
      opType: AdminOpType.tpvUpdate,
      payload: await _stampPayload(payload),
    );
  }

  Future<void> assignVendorToTpvOffline({
    required int vendorId,
    required int idTpv,
    String? tpvNombre,
  }) async {
    if (vendorId < 0 || idTpv < 0) {
      throw Exception('IDs temporales: sincroniza primero');
    }
    final clientUuid = UuidGenerator.v4();
    final payload = {
      'id_vendedor': vendorId,
      'id_tpv': idTpv,
      'tpv_nombre': tpvNombre,
    };

    final vendors = await listCachedVendors();
    for (var i = 0; i < vendors.length; i++) {
      if ((vendors[i]['id'] as num?)?.toInt() == vendorId) {
        vendors[i] = {
          ...vendors[i],
          'id_tpv': idTpv,
          'tpv_nombre': tpvNombre,
          'pending_local': true,
        };
      }
    }
    await _db.mergeSections({'vendors': vendors});

    // Si el vendedor está registrado offline, actualizar su idTpv local.
    try {
      final storeId = await _prefs.getIdTienda();
      if (storeId != null) {
        final users = await _prefs.getOfflineUsersForStore(storeId);
        final vendor = vendors.cast<Map<String, dynamic>?>().firstWhere(
              (v) => (v?['id'] as num?)?.toInt() == vendorId,
              orElse: () => null,
            );
        final email = vendor?['email']?.toString().toLowerCase();
        if (email != null && email.isNotEmpty) {
          for (final u in users) {
            if ((u['email']?.toString().toLowerCase() ?? '') == email) {
              await _prefs.upsertOfflineUserProfile({
                ...u,
                'idTpv': idTpv,
              });
            }
          }
        }
      }
    } catch (e) {
      print('⚠️ No se pudo actualizar offline user TPV: $e');
    }

    if (_connectivity.isConnected && _supabase.auth.currentUser != null) {
      try {
        await _syncVendorAssignTpv(clientUuid, payload);
        return;
      } catch (e) {
        print('⚠️ AdminInventory: fallo online assign TPV, encolando: $e');
      }
    }

    await _db.enqueueAdminOp(
      clientUuid: clientUuid,
      opType: AdminOpType.vendorAssignTpv,
      payload: await _stampPayload(payload),
    );
  }

  Future<void> updateVendorCustomizeFlagOffline({
    required int vendorId,
    required bool permitirCustomizar,
  }) async {
    if (vendorId < 0) throw Exception('Vendedor pendiente de sync');
    final clientUuid = UuidGenerator.v4();
    final payload = {
      'id_vendedor': vendorId,
      'permitir_customizar_precio_venta': permitirCustomizar,
    };

    final vendors = await listCachedVendors();
    for (var i = 0; i < vendors.length; i++) {
      if ((vendors[i]['id'] as num?)?.toInt() == vendorId) {
        vendors[i] = {
          ...vendors[i],
          'permitir_customizar_precio_venta': permitirCustomizar,
          'pending_local': true,
        };
      }
    }
    await _db.mergeSections({'vendors': vendors});

    if (_connectivity.isConnected && _supabase.auth.currentUser != null) {
      try {
        await _syncVendorUpdateFlags(clientUuid, payload);
        return;
      } catch (e) {
        print('⚠️ AdminInventory: fallo online vendor flags, encolando: $e');
      }
    }

    await _db.enqueueAdminOp(
      clientUuid: clientUuid,
      opType: AdminOpType.vendorUpdateFlags,
      payload: await _stampPayload(payload),
    );
  }

  /// Alta/edición de precio por TPV (offline-first).
  Future<void> upsertTpvPrice({
    required int idProducto,
    required int idTpv,
    required double precioVentaCup,
    int? existingPriceId,
    String? productoNombre,
    String? tpvNombre,
  }) async {
    if (precioVentaCup < 0) throw Exception('Precio inválido');

    final clientUuid = UuidGenerator.v4();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final payload = {
      'id': existingPriceId,
      'id_producto': idProducto,
      'id_tpv': idTpv,
      'precio_venta_cup': precioVentaCup,
      'fecha_desde': today,
      'producto_nombre': productoNombre,
      'tpv_nombre': tpvNombre,
    };

    await _applyTpvPriceLocally(payload);

    if (_connectivity.isConnected && _supabase.auth.currentUser != null) {
      try {
        await _syncTpvPriceUpsert(clientUuid, payload);
        return;
      } catch (e) {
        print('⚠️ AdminInventory: fallo online precio TPV, encolando: $e');
      }
    }

    await _db.enqueueAdminOp(
      clientUuid: clientUuid,
      opType: AdminOpType.tpvPriceUpsert,
      payload: await _stampPayload(payload),
    );
  }

  Future<void> _applyTpvPriceLocally(Map<String, dynamic> payload) async {
    final section = await _db.getSection('tpv_prices');
    final list = <Map<String, dynamic>>[];
    if (section is List) {
      list.addAll(
        section
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e)),
      );
    }

    final productId = (payload['id_producto'] as num).toInt();
    final tpvId = (payload['id_tpv'] as num).toInt();
    final existingId = (payload['id'] as num?)?.toInt();
    final idx = list.indexWhere((p) {
      final id = (p['id'] as num?)?.toInt();
      if (existingId != null && id == existingId) return true;
      return (p['id_producto'] as num?)?.toInt() == productId &&
          (p['id_tpv'] as num?)?.toInt() == tpvId;
    });

    final row = {
      'id': existingId ??
          (idx >= 0
              ? list[idx]['id']
              : -DateTime.now().millisecondsSinceEpoch),
      'id_producto': productId,
      'id_tpv': tpvId,
      'precio_venta_cup': payload['precio_venta_cup'],
      'fecha_desde': payload['fecha_desde'],
      'fecha_hasta': null,
      'es_activo': true,
      'producto_nombre':
          payload['producto_nombre'] ??
          (idx >= 0 ? list[idx]['producto_nombre'] : null),
      'producto_sku': idx >= 0 ? list[idx]['producto_sku'] : null,
      'tpv_nombre':
          payload['tpv_nombre'] ??
          (idx >= 0 ? list[idx]['tpv_nombre'] : null),
      'pending_local': true,
    };

    if (idx >= 0) {
      list[idx] = row;
    } else {
      list.add(row);
    }
    await _db.mergeSections({'tpv_prices': list});
  }

  /// Extracción de inventario (sale stock). Offline → cola.
  Future<void> registerExtraction({
    required List<Map<String, dynamic>> productos,
    required int idMotivoOperacion,
    required String autorizadoPor,
    String observaciones = '',
    int estadoInicial = 2,
  }) async {
    final storeId = await _prefs.getIdTienda();
    final userId =
        _supabase.auth.currentUser?.id ?? await _prefs.getUserId();
    if (storeId == null || userId == null) {
      throw Exception('Sin tienda o usuario autenticado');
    }
    if (productos.isEmpty) {
      throw Exception('Agrega al menos un producto');
    }

    final clientUuid = UuidGenerator.v4();
    final payload = {
      'id_tienda': storeId,
      'id_motivo_operacion': idMotivoOperacion,
      'autorizado_por': autorizadoPor,
      'observaciones': observaciones,
      'estado_inicial': estadoInicial,
      'productos': productos,
      'uuid': userId,
    };

    for (final p in productos) {
      final id = (p['id_producto'] as num?)?.toInt();
      final qty = (p['cantidad'] as num?)?.toDouble() ?? 0;
      if (id != null && qty != 0) {
        await _applyStockDeltaLocally(productId: id, delta: -qty);
      }
    }

    if (_connectivity.isConnected && _supabase.auth.currentUser != null) {
      try {
        await _syncExtraction(clientUuid, payload);
        return;
      } catch (e) {
        print('⚠️ AdminInventory: fallo online extracción, encolando: $e');
      }
    }

    await _db.enqueueAdminOp(
      clientUuid: clientUuid,
      opType: AdminOpType.extraction,
      payload: await _stampPayload(payload),
    );
  }

  /// Transferencia entre layouts. Offline → cola.
  /// Limitación: el cache de stock del vendedor es agregado; se resta del
  /// producto si el layout origen coincide con su `id_ubicacion` en cache.
  Future<void> registerTransfer({
    required int idLayoutOrigen,
    required int idLayoutDestino,
    required List<Map<String, dynamic>> productos,
    required String entregadoPor,
    required String transportadoPor,
    required String recibidoPor,
    String observaciones = '',
    bool completarOperaciones = true,
  }) async {
    final storeId = await _prefs.getIdTienda();
    final userId =
        _supabase.auth.currentUser?.id ?? await _prefs.getUserId();
    if (storeId == null || userId == null) {
      throw Exception('Sin tienda o usuario autenticado');
    }
    if (idLayoutOrigen == idLayoutDestino) {
      throw Exception('Origen y destino deben ser distintos');
    }
    if (productos.isEmpty) {
      throw Exception('Agrega al menos un producto');
    }

    final clientUuid = UuidGenerator.v4();
    final payload = {
      'id_tienda': storeId,
      'id_layout_origen': idLayoutOrigen,
      'id_layout_destino': idLayoutDestino,
      'productos': productos,
      'autorizado_por': entregadoPor,
      'entregado_por': entregadoPor,
      'transportado_por': transportadoPor,
      'recibido_por': recibidoPor,
      'observaciones': observaciones,
      'completar_operaciones': completarOperaciones,
      'uuid': userId,
      'moneda_factura': 'USD',
    };

    for (final p in productos) {
      final id = (p['id_producto'] as num?)?.toInt();
      final qty = (p['cantidad'] as num?)?.toDouble() ?? 0;
      if (id == null || qty == 0) continue;
      final product = await _db.getProductById(id);
      int? productLayout;
      final detalles = product?['detalles_completos'];
      if (detalles is Map) {
        final inv = detalles['inventario'];
        if (inv is List && inv.isNotEmpty && inv.first is Map) {
          productLayout = (inv.first['id_ubicacion'] as num?)?.toInt() ??
              (inv.first['ubicacion'] is Map
                  ? (inv.first['ubicacion']['id'] as num?)?.toInt()
                  : null);
        }
      }
      // Solo ajustar cache visible si el stock cacheado es del layout origen.
      if (productLayout == null || productLayout == idLayoutOrigen) {
        await _applyStockDeltaLocally(productId: id, delta: -qty);
      }
    }

    if (_connectivity.isConnected && _supabase.auth.currentUser != null) {
      try {
        await _syncTransfer(clientUuid, payload);
        return;
      } catch (e) {
        print('⚠️ AdminInventory: fallo online transferencia, encolando: $e');
      }
    }

    await _db.enqueueAdminOp(
      clientUuid: clientUuid,
      opType: AdminOpType.transfer,
      payload: await _stampPayload(payload),
    );
  }

  /// Venta por acuerdo (fn_registrar_venta + pago + completar). Offline → cola.
  Future<void> registerSaleByAgreement({
    required List<Map<String, dynamic>> productos,
    required int idTpv,
    required int idMedioPago,
    required double montoTotal,
    String cliente = '',
    String observaciones = '',
    int? idCliente,
  }) async {
    final userId =
        _supabase.auth.currentUser?.id ?? await _prefs.getUserId();
    if (userId == null) throw Exception('Sin usuario autenticado');
    if (productos.isEmpty) throw Exception('Agrega al menos un producto');
    if (montoTotal < 0) throw Exception('Monto inválido');

    final clientUuid = UuidGenerator.v4();
    final obs = StringBuffer();
    if (cliente.trim().isNotEmpty) {
      obs.write('Cliente: ${cliente.trim()}. ');
    }
    obs.write('Total: \$${montoTotal.toStringAsFixed(2)}. ');
    if (observaciones.trim().isNotEmpty) {
      obs.write(observaciones.trim());
    }

    final payload = {
      'id_tpv': idTpv,
      'id_medio_pago': idMedioPago,
      'monto_total': montoTotal,
      'cliente': cliente.trim(),
      'observaciones': obs.toString(),
      'productos': productos,
      'uuid': userId,
      'denominacion':
          'Venta por Acuerdo - ${DateTime.now().millisecondsSinceEpoch}',
      'estado_inicial': 1,
      if (idCliente != null) 'id_cliente': idCliente,
    };

    for (final p in productos) {
      final id = (p['id_producto'] as num?)?.toInt();
      final qty = (p['cantidad'] as num?)?.toDouble() ?? 0;
      if (id != null && qty != 0) {
        await _applyStockDeltaLocally(productId: id, delta: -qty);
      }
    }

    if (_connectivity.isConnected && _supabase.auth.currentUser != null) {
      try {
        await _syncSaleByAgreement(clientUuid, payload);
        return;
      } catch (e) {
        print('⚠️ AdminInventory: fallo online venta acuerdo, encolando: $e');
      }
    }

    await _db.enqueueAdminOp(
      clientUuid: clientUuid,
      opType: AdminOpType.saleByAgreement,
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
          case AdminOpType.extraction:
            await _syncExtraction(uuid, payload);
            break;
          case AdminOpType.transfer:
            await _syncTransfer(uuid, payload);
            break;
          case AdminOpType.saleByAgreement:
            await _syncSaleByAgreement(uuid, payload);
            break;
          case AdminOpType.tpvPriceUpsert:
            await _syncTpvPriceUpsert(uuid, payload);
            break;
          case AdminOpType.tpvCreate:
            await _syncTpvCreate(uuid, payload);
            break;
          case AdminOpType.tpvUpdate:
            await _syncTpvUpdate(uuid, payload);
            break;
          case AdminOpType.vendorAssignTpv:
            await _syncVendorAssignTpv(uuid, payload);
            break;
          case AdminOpType.vendorUpdateFlags:
            await _syncVendorUpdateFlags(uuid, payload);
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
    dynamic response;
    try {
      response = await _supabase.rpc(
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
      response = await _supabase.rpc(
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

    final idProveedor = (payload['id_proveedor'] as num?)?.toInt();
    if (idProveedor == null || response is! Map) return;
    final opId = (response['id_operacion'] as num?)?.toInt();
    if (opId == null) return;
    try {
      await _supabase
          .from('app_dat_recepcion_productos')
          .update({'id_proveedor': idProveedor})
          .eq('id_operacion', opId);
    } catch (e) {
      print('⚠️ Link proveedor recepción $opId: $e');
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

  Future<void> _syncExtraction(
    String clientUuid,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _supabase.rpc(
        'fn_admin_caja_extraccion_offline',
        params: {
          'p_client_uuid': clientUuid,
          'p_autorizado_por': payload['autorizado_por'],
          'p_estado_inicial': payload['estado_inicial'] ?? 2,
          'p_id_motivo_operacion': payload['id_motivo_operacion'],
          'p_id_tienda': payload['id_tienda'],
          'p_observaciones': payload['observaciones'] ?? '',
          'p_productos': payload['productos'],
          'p_uuid': payload['uuid'],
        },
      );
    } catch (e) {
      print('⚠️ fn_admin_caja_extraccion_offline: $e — fallback');
      await _supabase.rpc(
        'fn_crear_extraccion_con_movimiento',
        params: {
          'p_autorizado_por': payload['autorizado_por'],
          'p_estado_inicial': payload['estado_inicial'] ?? 2,
          'p_id_motivo_operacion': payload['id_motivo_operacion'],
          'p_id_tienda': payload['id_tienda'],
          'p_observaciones':
              '${payload['observaciones'] ?? ''} [caja:$clientUuid]',
          'p_productos': payload['productos'],
          'p_uuid': payload['uuid'],
        },
      );
    }
  }

  Future<void> _syncTransfer(
    String clientUuid,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _supabase.rpc(
        'fn_admin_caja_transferencia_offline',
        params: {
          'p_client_uuid': clientUuid,
          'p_id_layout_origen': payload['id_layout_origen'],
          'p_id_layout_destino': payload['id_layout_destino'],
          'p_productos': payload['productos'],
          'p_autorizado_por': payload['autorizado_por'],
          'p_entregado_por': payload['entregado_por'],
          'p_transportado_por': payload['transportado_por'],
          'p_recibido_por': payload['recibido_por'],
          'p_observaciones': payload['observaciones'] ?? '',
          'p_id_tienda': payload['id_tienda'],
          'p_uuid': payload['uuid'],
          'p_completar_operaciones': payload['completar_operaciones'] ?? true,
          'p_moneda_factura': payload['moneda_factura'] ?? 'USD',
        },
      );
    } catch (e) {
      print('⚠️ fn_admin_caja_transferencia_offline: $e — fallback');
      await _supabase.rpc(
        'fn_transferir_inventario_entre_layouts',
        params: {
          'p_id_layout_origen': payload['id_layout_origen'],
          'p_id_layout_destino': payload['id_layout_destino'],
          'p_productos': payload['productos'],
          'p_autorizado_por': payload['autorizado_por'],
          'p_entregado_por': payload['entregado_por'],
          'p_transportado_por': payload['transportado_por'],
          'p_recibido_por': payload['recibido_por'],
          'p_observaciones':
              '${payload['observaciones'] ?? ''} [caja:$clientUuid]',
          'p_id_tienda': payload['id_tienda'],
          'p_uuid': payload['uuid'],
          'p_completar_operaciones': payload['completar_operaciones'] ?? true,
          'p_moneda_factura': payload['moneda_factura'] ?? 'USD',
        },
      );
    }
  }

  Future<void> _syncSaleByAgreement(
    String clientUuid,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _supabase.rpc(
        'fn_admin_caja_venta_acuerdo_offline',
        params: {
          'p_client_uuid': clientUuid,
          'p_denominacion': payload['denominacion'],
          'p_estado_inicial': payload['estado_inicial'] ?? 1,
          'p_id_tpv': payload['id_tpv'],
          'p_observaciones': payload['observaciones'] ?? '',
          'p_productos': payload['productos'],
          'p_uuid': payload['uuid'],
          'p_id_medio_pago': payload['id_medio_pago'],
          'p_monto_total': payload['monto_total'],
          'p_id_cliente': payload['id_cliente'],
        },
      );
    } catch (e) {
      print('⚠️ fn_admin_caja_venta_acuerdo_offline: $e — fallback');
      final response = await _supabase.rpc(
        'fn_registrar_venta',
        params: {
          'p_codigo_promocion': null,
          'p_denominacion': payload['denominacion'],
          'p_estado_inicial': payload['estado_inicial'] ?? 1,
          'p_id_tpv': payload['id_tpv'],
          'p_observaciones':
              '${payload['observaciones'] ?? ''} [caja:$clientUuid]',
          'p_productos': payload['productos'],
          'p_uuid': payload['uuid'],
          'p_id_cliente': payload['id_cliente'],
        },
      );
      final map = response is Map
          ? Map<String, dynamic>.from(response)
          : <String, dynamic>{};
      final opId = (map['id_operacion'] as num?)?.toInt();
      if (opId == null) {
        throw Exception('Venta sin id_operacion: $response');
      }
      await _supabase.rpc(
        'fn_registrar_pago_venta',
        params: {
          'p_id_operacion_venta': opId,
          'p_pagos': [
            {
              'id_medio_pago': payload['id_medio_pago'],
              'monto': payload['monto_total'],
              'referencia_pago': 'Venta por Acuerdo - $clientUuid',
            },
          ],
        },
      );
      await _supabase.rpc(
        'fn_registrar_cambio_estado_operacion',
        params: {
          'p_id_operacion': opId,
          'p_nuevo_estado': 2,
          'p_uuid_usuario': payload['uuid'],
        },
      );
    }
  }

  Future<void> _syncTpvPriceUpsert(
    String clientUuid,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _supabase.rpc(
        'fn_admin_caja_precio_tpv_offline',
        params: {
          'p_client_uuid': clientUuid,
          'p_id_producto': payload['id_producto'],
          'p_id_tpv': payload['id_tpv'],
          'p_precio_venta_cup': payload['precio_venta_cup'],
          'p_fecha_desde': payload['fecha_desde'],
          'p_id_precio': payload['id'],
        },
      );
    } catch (e) {
      print('⚠️ fn_admin_caja_precio_tpv_offline: $e — fallback');
      final productId = (payload['id_producto'] as num).toInt();
      final tpvId = (payload['id_tpv'] as num).toInt();
      final price = (payload['precio_venta_cup'] as num).toDouble();
      final fechaDesde = payload['fecha_desde']?.toString() ??
          DateTime.now().toIso8601String().substring(0, 10);
      final existingId = (payload['id'] as num?)?.toInt();

      if (existingId != null && existingId > 0) {
        await _supabase.from('app_dat_precio_tpv').update({
          'precio_venta_cup': price,
          'fecha_desde': fechaDesde,
          'es_activo': true,
          'deleted_at': null,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', existingId);
        return;
      }

      final existing = await _supabase
          .from('app_dat_precio_tpv')
          .select('id')
          .eq('id_producto', productId)
          .eq('id_tpv', tpvId)
          .isFilter('deleted_at', null)
          .eq('es_activo', true)
          .order('fecha_desde', ascending: false)
          .limit(1)
          .maybeSingle();

      if (existing != null) {
        await _supabase.from('app_dat_precio_tpv').update({
          'precio_venta_cup': price,
          'fecha_desde': fechaDesde,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', existing['id']);
      } else {
        await _supabase.from('app_dat_precio_tpv').insert({
          'id_producto': productId,
          'id_tpv': tpvId,
          'precio_venta_cup': price,
          'fecha_desde': fechaDesde,
          'es_activo': true,
        });
      }
    }
  }

  Future<void> _syncTpvCreate(
    String clientUuid,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _supabase.rpc(
        'fn_admin_caja_tpv_create_offline',
        params: {
          'p_client_uuid': clientUuid,
          'p_denominacion': payload['denominacion'],
          'p_id_tienda': payload['id_tienda'],
          'p_id_almacen': payload['id_almacen'],
        },
      );
    } catch (e) {
      print('⚠️ fn_admin_caja_tpv_create_offline: $e — fallback');
      await _supabase.from('app_dat_tpv').insert({
        'denominacion': payload['denominacion'],
        'id_tienda': payload['id_tienda'],
        'id_almacen': payload['id_almacen'],
      });
    }
  }

  Future<void> _syncTpvUpdate(
    String clientUuid,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _supabase.rpc(
        'fn_admin_caja_tpv_update_offline',
        params: {
          'p_client_uuid': clientUuid,
          'p_id_tpv': payload['id'],
          'p_denominacion': payload['denominacion'],
        },
      );
    } catch (e) {
      print('⚠️ fn_admin_caja_tpv_update_offline: $e — fallback');
      await _supabase.from('app_dat_tpv').update({
        'denominacion': payload['denominacion'],
      }).eq('id', payload['id']);
    }
  }

  Future<void> _syncVendorAssignTpv(
    String clientUuid,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _supabase.rpc(
        'fn_admin_caja_vendor_assign_tpv_offline',
        params: {
          'p_client_uuid': clientUuid,
          'p_id_vendedor': payload['id_vendedor'],
          'p_id_tpv': payload['id_tpv'],
        },
      );
    } catch (e) {
      print('⚠️ fn_admin_caja_vendor_assign_tpv_offline: $e — fallback');
      await _supabase.from('app_dat_vendedor').update({
        'id_tpv': payload['id_tpv'],
      }).eq('id', payload['id_vendedor']);
    }
  }

  Future<void> _syncVendorUpdateFlags(
    String clientUuid,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _supabase.rpc(
        'fn_admin_caja_vendor_flags_offline',
        params: {
          'p_client_uuid': clientUuid,
          'p_id_vendedor': payload['id_vendedor'],
          'p_permitir_customizar_precio_venta':
              payload['permitir_customizar_precio_venta'] == true,
        },
      );
    } catch (e) {
      print('⚠️ fn_admin_caja_vendor_flags_offline: $e — fallback');
      await _supabase.from('app_dat_vendedor').update({
        'permitir_customizar_precio_venta':
            payload['permitir_customizar_precio_venta'] == true,
      }).eq('id', payload['id_vendedor']);
    }
  }
}

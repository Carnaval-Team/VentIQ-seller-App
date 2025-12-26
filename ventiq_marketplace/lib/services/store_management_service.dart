import 'package:supabase_flutter/supabase_flutter.dart';

class StoreManagementService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const int _defaultTpvId = 1;
  static const int _defaultPresentacionId = 1;

  Future<List<int>> getManagedStoreIds({required String uuid}) async {
    final response = await _supabase
        .from('app_dat_gerente')
        .select('id_tienda')
        .eq('uuid', uuid);

    final rows = List<Map<String, dynamic>>.from(response as List);
    final ids = <int>[];
    for (final row in rows) {
      final v = row['id_tienda'];
      if (v is int) {
        ids.add(v);
      } else if (v is num) {
        ids.add(v.toInt());
      }
    }
    return ids;
  }

  Future<List<Map<String, dynamic>>> getStoresByIds(List<int> storeIds) async {
    if (storeIds.isEmpty) return [];

    final response = await _supabase
        .from('app_dat_tienda')
        .select('*')
        .inFilter('id', storeIds)
        .order('id', ascending: true);

    return List<Map<String, dynamic>>.from(response as List);
  }

  Future<Map<String, dynamic>> createStore({
    required String denominacion,
    required String direccion,
    required String ubicacion,
    required String imagenUrl,
    required String phone,
    required String pais,
    required String estado,
    required String nombrePais,
    required String nombreEstado,
    required String horaApertura,
    required String horaCierre,
    required double latitude,
    required double longitude,
  }) async {
    final payload = {
      'denominacion': denominacion,
      'direccion': direccion,
      'ubicacion': ubicacion,
      'imagen_url': imagenUrl,
      'phone': phone,
      'pais': pais,
      'estado': estado,
      'nombre_pais': nombrePais,
      'nombre_estado': nombreEstado,
      'hora_apertura': horaApertura,
      'hora_cierre': horaCierre,
      'latitude': latitude,
      'longitude': longitude,
      'mostrar_en_catalogo': false,
      'only_catalogo': true,
    };

    final response = await _supabase
        .from('app_dat_tienda')
        .insert(payload)
        .select('*')
        .single();

    return Map<String, dynamic>.from(response as Map);
  }

  Future<void> updateMostrarEnCatalogo({
    required int storeId,
    required bool mostrarEnCatalogo,
  }) async {
    await _supabase
        .from('app_dat_tienda')
        .update({'mostrar_en_catalogo': mostrarEnCatalogo})
        .eq('id', storeId);
  }

  Future<void> ensureGerenteLink({
    required String uuid,
    required int storeId,
  }) async {
    final existing = await _supabase
        .from('app_dat_gerente')
        .select('id')
        .eq('uuid', uuid)
        .eq('id_tienda', storeId)
        .maybeSingle();

    if (existing != null) return;

    await _supabase.from('app_dat_gerente').insert({
      'uuid': uuid,
      'id_tienda': storeId,
    });
  }

  Future<List<Map<String, dynamic>>> getCatalogCategories() async {
    final response = await _supabase
        .from('app_dat_categoria')
        .select('id, denominacion, image')
        .eq('para_catalogo', true)
        .order('denominacion', ascending: true);

    return List<Map<String, dynamic>>.from(response as List);
  }

  Future<int?> getFirstSubcategoryId({required int categoryId}) async {
    final response = await _supabase
        .from('app_dat_subcategorias')
        .select('id')
        .eq('idcategoria', categoryId)
        .order('id', ascending: true)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;

    final v = response['id'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  Future<void> ensureCategoriaTiendaLink({
    required int storeId,
    required int categoryId,
  }) async {
    final existing = await _supabase
        .from('app_dat_categoria_tienda')
        .select('id')
        .eq('id_tienda', storeId)
        .eq('id_categoria', categoryId)
        .maybeSingle();

    if (existing != null) return;

    await _supabase.from('app_dat_categoria_tienda').insert({
      'id_tienda': storeId,
      'id_categoria': categoryId,
    });
  }

  Future<List<Map<String, dynamic>>> getStoreProductsOverview({
    required int storeId,
    int tpvId = _defaultTpvId,
  }) async {
    final productsResponse = await _supabase
        .from('app_dat_producto')
        .select('id, denominacion, imagen, mostrar_en_catalogo')
        .eq('id_tienda', storeId)
        .isFilter('deleted_at', null)
        .order('denominacion', ascending: true);

    final products = List<Map<String, dynamic>>.from(productsResponse as List);
    if (products.isEmpty) return [];

    final productIds = <int>[];
    for (final p in products) {
      final v = p['id'];
      if (v is int) {
        productIds.add(v);
      } else if (v is num) {
        productIds.add(v.toInt());
      }
    }

    final pricesResponse = await _supabase
        .from('app_dat_precio_venta')
        .select('id_producto, precio_venta_cup, fecha_desde')
        .inFilter('id_producto', productIds)
        .order('fecha_desde', ascending: false);

    final priceByProduct = <int, num>{};
    for (final row in List<Map<String, dynamic>>.from(pricesResponse as List)) {
      final idProducto = row['id_producto'];
      final precio = row['precio_venta_cup'];
      final pid = idProducto is int
          ? idProducto
          : (idProducto is num ? idProducto.toInt() : null);
      if (pid == null) continue;
      if (priceByProduct.containsKey(pid)) continue;
      if (precio is num) {
        priceByProduct[pid] = precio;
      }
    }

    final basePresentationsResponse = await _supabase
        .from('app_dat_producto_presentacion')
        .select('id, id_producto')
        .inFilter('id_producto', productIds)
        .eq('es_base', true);

    final basePresentationByProduct = <int, int>{};
    for (final row in List<Map<String, dynamic>>.from(
      basePresentationsResponse as List,
    )) {
      final idProducto = row['id_producto'];
      final idPres = row['id'];
      final pid = idProducto is int
          ? idProducto
          : (idProducto is num ? idProducto.toInt() : null);
      final presId = idPres is int
          ? idPres
          : (idPres is num ? idPres.toInt() : null);
      if (pid == null || presId == null) continue;
      basePresentationByProduct[pid] = presId;
    }

    final inventoryResponse = await _supabase
        .from('app_dat_inventario_productos')
        .select('id_producto, cantidad_final, created_at')
        .inFilter('id_producto', productIds)
        .order('created_at', ascending: false)
        .limit(2000);

    final stockByProduct = <int, num>{};
    for (final row in List<Map<String, dynamic>>.from(
      inventoryResponse as List,
    )) {
      final idProducto = row['id_producto'];
      final pid = idProducto is int
          ? idProducto
          : (idProducto is num ? idProducto.toInt() : null);
      if (pid == null) continue;
      if (stockByProduct.containsKey(pid)) continue;
      final qty = row['cantidad_final'];
      if (qty is num) {
        stockByProduct[pid] = qty;
      } else {
        stockByProduct[pid] = 0;
      }
    }

    final merged = <Map<String, dynamic>>[];
    for (final p in products) {
      final idRaw = p['id'];
      final pid = idRaw is int ? idRaw : (idRaw is num ? idRaw.toInt() : null);
      if (pid == null) continue;

      merged.add({
        ...p,
        'precio_venta_cup': priceByProduct[pid],
        'stock': stockByProduct[pid] ?? 0,
        'base_presentacion_id': basePresentationByProduct[pid],
      });
    }

    return merged;
  }

  Future<Map<String, dynamic>> getProductManagementDetail({
    required int productId,
    int tpvId = _defaultTpvId,
  }) async {
    final productResponse = await _supabase
        .from('app_dat_producto')
        .select(
          'id, id_tienda, id_categoria, denominacion, imagen, mostrar_en_catalogo',
        )
        .eq('id', productId)
        .single();

    final product = Map<String, dynamic>.from(productResponse as Map);

    final basePresentationResponse = await _supabase
        .from('app_dat_producto_presentacion')
        .select('id')
        .eq('id_producto', productId)
        .eq('es_base', true)
        .limit(1)
        .maybeSingle();

    final basePresentationIdRaw = basePresentationResponse?['id'];
    final basePresentationId = basePresentationIdRaw is int
        ? basePresentationIdRaw
        : (basePresentationIdRaw is num ? basePresentationIdRaw.toInt() : null);

    final priceResponse = await _supabase
        .from('app_dat_precio_venta')
        .select('precio_venta_cup, fecha_desde')
        .eq('id_producto', productId)
        .order('fecha_desde', ascending: false)
        .limit(1)
        .maybeSingle();

    final price = (priceResponse?['precio_venta_cup'] is num)
        ? (priceResponse?['precio_venta_cup'] as num)
        : null;

    final inventoryResponse = await _supabase
        .from('app_dat_inventario_productos')
        .select('cantidad_final, created_at')
        .eq('id_producto', productId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    final currentQty = (inventoryResponse?['cantidad_final'] is num)
        ? (inventoryResponse?['cantidad_final'] as num)
        : 0;

    return {
      'product': product,
      'base_presentacion_id': basePresentationId,
      'precio_venta_cup': price,
      'cantidad_final': currentQty,
    };
  }

  Future<int> ensureBasePresentationId({required int productId}) async {
    final basePresentationResponse = await _supabase
        .from('app_dat_producto_presentacion')
        .select('id')
        .eq('id_producto', productId)
        .eq('es_base', true)
        .limit(1)
        .maybeSingle();

    final basePresentationIdRaw = basePresentationResponse?['id'];
    final basePresentationId = basePresentationIdRaw is int
        ? basePresentationIdRaw
        : (basePresentationIdRaw is num ? basePresentationIdRaw.toInt() : null);

    if (basePresentationId != null) return basePresentationId;

    final created = await _supabase
        .from('app_dat_producto_presentacion')
        .insert({
          'id_producto': productId,
          'id_presentacion': _defaultPresentacionId,
          'cantidad': 1,
          'es_base': true,
        })
        .select('id')
        .single();

    final createdIdRaw = created['id'];
    final createdId = createdIdRaw is int
        ? createdIdRaw
        : (createdIdRaw is num ? createdIdRaw.toInt() : null);

    if (createdId == null) {
      throw Exception('No se pudo crear presentación base');
    }

    return createdId;
  }

  Future<void> updateProductCategory({
    required int productId,
    required int storeId,
    required int categoryId,
  }) async {
    await _supabase
        .from('app_dat_producto')
        .update({'id_categoria': categoryId})
        .eq('id', productId);

    await ensureCategoriaTiendaLink(storeId: storeId, categoryId: categoryId);

    final subcategoryId = await getFirstSubcategoryId(categoryId: categoryId);
    if (subcategoryId == null) {
      throw Exception('No hay subcategorías para esta categoría');
    }

    final existing = await _supabase
        .from('app_dat_productos_subcategorias')
        .select('id')
        .eq('id_producto', productId)
        .maybeSingle();

    if (existing != null) {
      await _supabase
          .from('app_dat_productos_subcategorias')
          .update({'id_sub_categoria': subcategoryId})
          .eq('id', existing['id']);
      return;
    }

    await _supabase.from('app_dat_productos_subcategorias').insert({
      'id_producto': productId,
      'id_sub_categoria': subcategoryId,
    });
  }

  Future<int> createProductComplete({
    required int storeId,
    required int categoryId,
    required String name,
    required String imageUrl,
    required num priceCup,
    required num initialQuantity,
    bool storeAllowsCatalog = false,
  }) async {
    final productInsert = {
      'id_tienda': storeId,
      'id_categoria': categoryId,
      'denominacion': name,
      'nombre_comercial': name,
      'denominacion_corta': name,
      'um': 'u',
      'es_vendible': true,
      'imagen': imageUrl,
      'mostrar_en_catalogo': storeAllowsCatalog,
    };

    final productResponse = await _supabase
        .from('app_dat_producto')
        .insert(productInsert)
        .select('id')
        .single();

    final productIdRaw = productResponse['id'];
    final productId = productIdRaw is int
        ? productIdRaw
        : (productIdRaw is num ? productIdRaw.toInt() : null);
    if (productId == null) {
      throw Exception('No se pudo obtener id del producto');
    }

    await ensureCategoriaTiendaLink(storeId: storeId, categoryId: categoryId);

    final subcategoryId = await getFirstSubcategoryId(categoryId: categoryId);
    if (subcategoryId == null) {
      throw Exception('No hay subcategorías para esta categoría');
    }

    await _supabase.from('app_dat_productos_subcategorias').insert({
      'id_producto': productId,
      'id_sub_categoria': subcategoryId,
    });

    final presentationResponse = await _supabase
        .from('app_dat_producto_presentacion')
        .insert({
          'id_producto': productId,
          'id_presentacion': _defaultPresentacionId,
          'cantidad': 1,
          'es_base': true,
        })
        .select('id')
        .single();

    final basePresentationIdRaw = presentationResponse['id'];
    final basePresentationId = basePresentationIdRaw is int
        ? basePresentationIdRaw
        : (basePresentationIdRaw is num ? basePresentationIdRaw.toInt() : null);
    if (basePresentationId == null) {
      throw Exception('No se pudo obtener id de presentación base');
    }
    final today = DateTime.now();
    final fecha = DateTime(today.year, today.month, today.day);
    await _supabase.from('app_dat_precio_venta').insert({
      'id_producto': productId,
      'fecha_desde': fecha.toIso8601String().substring(0, 10),
      'precio_venta_cup': priceCup,
    });

    await _supabase.from('app_dat_inventario_productos').insert({
      'id_producto': productId,
      'id_presentacion': basePresentationId,
      'cantidad_inicial': initialQuantity,
      'cantidad_final': initialQuantity,
      'origen_cambio': 2,
    });

    return productId;
  }

  Future<void> updateProductMostrarEnCatalogo({
    required int productId,
    required bool mostrarEnCatalogo,
  }) async {
    await _supabase
        .from('app_dat_producto')
        .update({'mostrar_en_catalogo': mostrarEnCatalogo})
        .eq('id', productId);
  }

  Future<void> updateProductBasicInfo({
    required int productId,
    required String name,
  }) async {
    await _supabase
        .from('app_dat_producto')
        .update({
          'denominacion': name,
          'nombre_comercial': name,
          'denominacion_corta': name,
        })
        .eq('id', productId);
  }

  Future<void> updateProductImage({
    required int productId,
    required String imageUrl,
  }) async {
    await _supabase
        .from('app_dat_producto')
        .update({'imagen': imageUrl})
        .eq('id', productId);
  }

  Future<void> upsertProductPriceForToday({
    required int productId,
    num priceCup = 0,
    int tpvId = _defaultTpvId,
  }) async {
    final today = DateTime.now();
    final fecha = DateTime(today.year, today.month, today.day);

    final existing = await _supabase
        .from('app_dat_precio_venta')
        .select('id')
        .eq('id_producto', productId)
        
        .eq('fecha_desde', fecha.toIso8601String().substring(0, 10))

        .maybeSingle();

    if (existing != null) {
      await _supabase
          .from('app_dat_precio_venta')
          .update({'precio_venta_cup': priceCup})
          .eq('id', existing['id']);
      return;
    }

    await _supabase.from('app_dat_precio_venta').insert({
      'id_producto': productId,
      'fecha_desde': fecha.toIso8601String().substring(0, 10),
      'precio_venta_cup': priceCup,
    });
  }

  Future<void> insertInventorySnapshot({
    required int productId,
    required int basePresentationId,
    required num currentQuantity,
    required num newQuantity,
  }) async {
    await _supabase.from('app_dat_inventario_productos').insert({
      'id_producto': productId,
      'id_presentacion': basePresentationId,
      'cantidad_inicial': currentQuantity,
      'cantidad_final': newQuantity,
      'origen_cambio': 2,
    });
  }
}

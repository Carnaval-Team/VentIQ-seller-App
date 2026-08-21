import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory_product.dart';
import 'offline_database_service.dart';
import 'user_preferences_service.dart';

class InventoryService {
  static final InventoryService _instance = InventoryService._internal();
  factory InventoryService() => _instance;
  InventoryService._internal();

  static final SupabaseClient _supabase = Supabase.instance.client;
  static final UserPreferencesService _prefsService = UserPreferencesService();

  /// Get inventory products using fn_listar_inventario_productos RPC
  static Future<List<InventoryProduct>> getInventoryProducts({
    String? busqueda,
    int? idAlmacen,
    String? nivelStock,
    int? limite = 50,
    int? pagina = 1,
  }) async {
    try {
      print('🔍 Obteniendo productos de inventario...');

      final userData = await _prefsService.getUserData();
      final idTiendaRaw = userData['idTienda'];
      final idTienda =
          idTiendaRaw is int
              ? idTiendaRaw
              : (idTiendaRaw is String ? int.tryParse(idTiendaRaw) : null);

      if (idTienda == null) {
        throw Exception('No se encontró información de la tienda');
      }

      print('🏪 ID Tienda: $idTienda');
      print('🔍 Búsqueda: $busqueda');
      print('📦 ID Almacén: $idAlmacen');
      print('📊 Nivel Stock: $nivelStock');
      print('📄 Límite: $limite, Página: $pagina');

      final response = await _supabase.rpc(
        'fn_listar_inventario_productos_paged2',
        params: {
          'p_id_tienda': idTienda,
          'p_id_almacen': idAlmacen,
          'p_busqueda': busqueda,
          'p_limite': limite,
          'p_pagina': pagina,
        },
      );

      print('📦 Respuesta RPC recibida: ${response?.runtimeType}');

      if (response == null) {
        print('⚠️ Respuesta nula del RPC');
        return [];
      }

      final products = <InventoryProduct>[];

      if (response is List) {
        print('📋 Procesando ${response.length} elementos de la respuesta');

        for (var item in response) {
          try {
            final product = InventoryProduct.fromSupabaseRpc(item);
            products.add(product);
          } catch (e) {
            print('❌ Error procesando producto: $e');
            print('📄 Datos del producto problemático: $item');
          }
        }

        print('📊 Calculando niveles de stock virtuales...');
      } else {
        print('❌ Formato de respuesta inesperado: ${response.runtimeType}');
        return [];
      }

      print(
        '✅ ${products.length} productos de inventario cargados exitosamente',
      );
      return products;
    } catch (e) {
      print('❌ Error al obtener productos de inventario: $e');
      return [];
    }
  }

  /// Construye el listado de conteo desde cache SQLite/offline.
  /// Suma cantidades por almacén del vendedor y usa fallback a `cantidad`
  /// del producto cuando `detalles_completos` falta o el inventario viene vacío.
  static Future<List<InventoryProduct>> buildFromOfflineCache({
    int? idAlmacen,
  }) async {
    final resolvedAlmacen = idAlmacen ?? await _prefsService.getIdAlmacen();

    Map<String, dynamic>? productsData;
    try {
      final offlineData = await _prefsService.getOfflineData();
      final raw = offlineData?['products'];
      if (raw is Map && raw.isNotEmpty) {
        productsData = Map<String, dynamic>.from(raw);
      }
    } catch (e) {
      print('⚠️ getOfflineData products: $e');
    }

    if (productsData == null || productsData.isEmpty) {
      final grouped =
          await OfflineDatabaseService().getProductsGroupedByCategory();
      if (grouped.isNotEmpty) {
        productsData = {
          for (final e in grouped.entries) e.key: e.value,
        };
      }
    }

    if (productsData == null || productsData.isEmpty) {
      print('⚠️ buildFromOfflineCache: sin productos en cache');
      return [];
    }

    final byId = <int, InventoryProduct>{};

    for (final categoryProducts in productsData.values) {
      if (categoryProducts is! List) continue;
      for (final prodDataRaw in categoryProducts) {
        if (prodDataRaw is! Map) continue;
        final prodData = Map<String, dynamic>.from(prodDataRaw);
        final productId = (prodData['id'] as num?)?.toInt();
        if (productId == null || byId.containsKey(productId)) continue;

        final built = _inventoryProductFromOfflineMap(
          prodData,
          idAlmacen: resolvedAlmacen,
        );
        if (built != null) {
          byId[productId] = built;
        }
      }
    }

    final list = byId.values.toList()
      ..sort((a, b) => a.nombreProducto.compareTo(b.nombreProducto));
    print(
      '✅ buildFromOfflineCache: ${list.length} productos '
      '(almacén=${resolvedAlmacen ?? "todos"})',
    );
    return list;
  }

  static InventoryProduct? _inventoryProductFromOfflineMap(
    Map<String, dynamic> prodData, {
    int? idAlmacen,
  }) {
    final detallesRaw = prodData['detalles_completos'];
    final detalles =
        detallesRaw is Map ? Map<String, dynamic>.from(detallesRaw) : null;
    final productoInfo = detalles?['producto'] is Map
        ? Map<String, dynamic>.from(detalles!['producto'] as Map)
        : null;

    final esElaborado = productoInfo?['es_elaborado'] == true ||
        prodData['es_elaborado'] == true;
    final esServicio = productoInfo?['es_servicio'] == true ||
        prodData['es_servicio'] == true;
    if (esElaborado || esServicio) return null;

    final productId = (productoInfo?['id'] as num?)?.toInt() ??
        (prodData['id'] as num?)?.toInt();
    if (productId == null) return null;

    final inventarioList = <Map<String, dynamic>>[];
    final invRaw = detalles?['inventario'];
    if (invRaw is List) {
      for (final row in invRaw) {
        if (row is Map) {
          inventarioList.add(Map<String, dynamic>.from(row));
        }
      }
    }

    Map<String, dynamic>? bestRow;
    double sumQty = 0;
    for (final inv in inventarioList) {
      final almId = _almacenIdOfInv(inv);
      if (idAlmacen != null && almId != null && almId != idAlmacen) {
        continue;
      }
      final qty = (inv['cantidad_disponible'] as num?)?.toDouble() ?? 0.0;
      sumQty += qty;
      bestRow ??= inv;
    }

    final topQty = (prodData['cantidad'] as num?)?.toDouble() ?? 0.0;
    if (sumQty <= 0 && topQty > 0) {
      sumQty = topQty;
    }
    if (sumQty <= 0) return null;

    bestRow ??= inventarioList.isNotEmpty ? inventarioList.first : null;
    final ubicacion = bestRow?['ubicacion'] is Map
        ? Map<String, dynamic>.from(bestRow!['ubicacion'] as Map)
        : <String, dynamic>{};
    final almacen = ubicacion['almacen'] is Map
        ? Map<String, dynamic>.from(ubicacion['almacen'] as Map)
        : <String, dynamic>{};
    final variante = bestRow?['variante'] is Map
        ? Map<String, dynamic>.from(bestRow!['variante'] as Map)
        : null;
    final presentacion = bestRow?['presentacion'] is Map
        ? Map<String, dynamic>.from(bestRow!['presentacion'] as Map)
        : null;

    var varianteNombre = 'Variante';
    if (variante != null &&
        variante['atributo'] is Map &&
        variante['opcion'] is Map) {
      final atributo = Map<String, dynamic>.from(variante['atributo'] as Map);
      final opcion = Map<String, dynamic>.from(variante['opcion'] as Map);
      varianteNombre =
          '${atributo['label'] ?? 'Atributo'}: ${opcion['valor'] ?? ''}';
    }

    final idUbicacion = (bestRow?['id_ubicacion'] as num?)?.toInt() ??
        (ubicacion['id'] as num?)?.toInt() ??
        (prodData['id_ubicacion'] as num?)?.toInt() ??
        0;
    final nombreUbicacion = bestRow?['ubicacion_nombre']?.toString() ??
        bestRow?['denominacion_ubicacion']?.toString() ??
        ubicacion['denominacion']?.toString() ??
        prodData['ubicacion_nombre']?.toString() ??
        'Ubicación';
    final idAlm = (almacen['id'] as num?)?.toInt() ?? idAlmacen ?? 0;
    final nombreAlm = almacen['denominacion']?.toString() ??
        prodData['almacen_nombre']?.toString() ??
        'Almacén';

    return InventoryProduct(
      id: productId,
      skuProducto: bestRow?['sku_producto']?.toString() ??
          prodData['sku']?.toString() ??
          '',
      nombreProducto: productoInfo?['denominacion']?.toString() ??
          prodData['denominacion']?.toString() ??
          'Producto',
      idCategoria: (productoInfo?['id_categoria'] as num?)?.toInt() ?? 0,
      categoria: productoInfo?['categoria'] is Map
          ? (productoInfo!['categoria']['denominacion']?.toString() ??
              'Sin categoría')
          : (prodData['categoria']?.toString() ?? 'Sin categoría'),
      idSubcategoria: (productoInfo?['id_subcategoria'] as num?)?.toInt() ?? 0,
      subcategoria: prodData['subcategoria']?.toString() ?? 'General',
      idTienda: (productoInfo?['id_tienda'] as num?)?.toInt() ??
          (prodData['id_tienda'] as num?)?.toInt() ??
          0,
      tienda: '',
      idAlmacen: idAlm,
      almacen: nombreAlm,
      idUbicacion: idUbicacion,
      ubicacion: nombreUbicacion,
      idVariante: (variante?['id'] as num?)?.toInt(),
      variante: varianteNombre,
      idOpcionVariante: variante?['opcion'] is Map
          ? (variante!['opcion']['id'] as num?)?.toInt()
          : null,
      opcionVariante: variante?['opcion'] is Map
          ? (variante!['opcion']['valor']?.toString() ?? varianteNombre)
          : varianteNombre,
      idPresentacion: (presentacion?['id'] as num?)?.toInt(),
      presentacion: presentacion?['denominacion']?.toString() ?? 'Unidad',
      cantidadInicial: sumQty,
      cantidadFinal: sumQty,
      stockDisponible: sumQty,
      stockReservado: 0,
      stockDisponibleAjustado: sumQty,
      esVendible: true,
      esInventariable: true,
      precioVenta: (productoInfo?['precio_actual'] as num?)?.toDouble() ??
          (prodData['precio'] as num?)?.toDouble() ??
          0,
      costoPromedio: null,
      margenActual: null,
      clasificacionAbc: 3,
      abcDescripcion: '',
      fechaUltimaActualizacion: DateTime.now(),
      totalCount: 0,
      resumenInventario: null,
      infoPaginacion: null,
    );
  }

  static int? _almacenIdOfInv(Map<String, dynamic> inv) {
    final ubicacion = inv['ubicacion'] is Map
        ? Map<String, dynamic>.from(inv['ubicacion'] as Map)
        : null;
    final almacen = ubicacion?['almacen'] is Map
        ? Map<String, dynamic>.from(ubicacion!['almacen'] as Map)
        : null;
    return (almacen?['id'] as num?)?.toInt() ??
        (inv['id_almacen'] as num?)?.toInt();
  }

  /// Get warehouses for the current store
  static Future<List<Map<String, dynamic>>> getWarehouses() async {
    try {
      final userData = await _prefsService.getUserData();
      final idTiendaRaw = userData['idTienda'];
      final idTienda =
          idTiendaRaw is int
              ? idTiendaRaw
              : (idTiendaRaw is String ? int.tryParse(idTiendaRaw) : null);

      if (idTienda == null) {
        throw Exception('No se encontró información de la tienda');
      }

      final response = await _supabase
          .from('app_dat_almacen')
          .select('id, denominacion, descripcion')
          .eq('id_tienda', idTienda)
          .eq('es_activo', true);

      print('✅ ${response.length} almacenes encontrados');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error al obtener almacenes: $e');
      return [];
    }
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product.dart';
import 'product_detail_service.dart';
import 'user_preferences_service.dart';

/// Resultado de carga de combustibles (red o cache).
class ServicentroLoadResult {
  final List<ServicentroFuelItem> items;
  final bool fromCache;
  final DateTime? syncedAt;
  final String? warning;

  const ServicentroLoadResult({
    required this.items,
    this.fromCache = false,
    this.syncedAt,
    this.warning,
  });
}

/// Snapshot de stock/precio del catálogo normal (mismo origen que categorías).
class _CatalogStock {
  final double cantidad;
  final double? precio;
  const _CatalogStock({required this.cantidad, this.precio});
}

/// Sync y cache local de combustibles / modo servicentro **por TPV**.
///
/// La lista (orden/color) viene de servicentro; el **stock** se toma del
/// catálogo de productos ya sincronizado (`offline_data.products` /
/// `get_detalle_producto`), igual que el resto de la app.
class ServicentroService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final UserPreferencesService _prefs = UserPreferencesService();
  static final ProductDetailService _productDetail = ProductDetailService();

  static bool _modoCached = false;
  static int _columnasCached = 2;
  static int? _tpvCached;
  static String? _tpvNombreCached;
  static DateTime? _syncedAtCached;

  static double unitPriceForEnteredAmount({
    required double liters,
    required double amount,
  }) {
    if (liters <= 0 || amount <= 0) return 0;
    return amount / liters;
  }

  static bool get modoServicentroSync => _modoCached;
  static int get servicentroColumnasSync => _columnasCached;
  static String? get tpvNombreSync => _tpvNombreCached;
  static DateTime? get lastSyncedAtSync => _syncedAtCached;

  /// Descarga config + lista del TPV y guarda en prefs.
  /// Luego alinea stock con el catálogo de productos.
  static Future<List<ServicentroFuelItem>> syncForTpv(int idTpv) async {
    try {
      final response = await _supabase.rpc(
        'fn_get_servicentro_config',
        params: {'p_id_tpv': idTpv},
      );

      if (response is! Map) {
        throw Exception('Respuesta inesperada de fn_get_servicentro_config');
      }
      final mapa = Map<String, dynamic>.from(response);
      if (mapa['status'] == 'error') {
        throw Exception(mapa['message']?.toString() ?? 'Error servicentro');
      }

      _modoCached = mapa['modo_servicentro'] == true;
      _columnasCached =
          ((mapa['servicentro_columnas'] as num?)?.toInt() ?? 2).clamp(1, 4);
      _tpvCached = idTpv;
      final nombre = mapa['tpv_denominacion']?.toString().trim();
      if (nombre != null && nombre.isNotEmpty) {
        _tpvNombreCached = nombre;
      }
      _syncedAtCached = DateTime.now();

      await _prefs.saveTpvServicentroFlags(
        idTpv: idTpv,
        modo: _modoCached,
        columnas: _columnasCached,
        tpvNombre: _tpvNombreCached,
      );

      var list = <ServicentroFuelItem>[];
      try {
        final listed = await _supabase.rpc(
          'fn_listar_servicentro_productos',
          params: {'p_id_tpv': idTpv},
        );
        list = _parseProductos(listed);
      } catch (e) {
        print('⚠️ fn_listar_servicentro_productos: $e — usando config');
        list = _parseProductos(mapa['productos']);
      }

      list = await refreshStockFromServer(list);

      await _prefs.saveServicentroProductos(
        list.map((e) => e.toJson()).toList(),
        idTpv: idTpv,
      );
      print(
        '⛽ Servicentro TPV $idTpv: modo=$_modoCached, '
        '${list.length} combustibles',
      );
      return list;
    } catch (e) {
      print('❌ Error sync servicentro TPV: $e');
      rethrow;
    }
  }

  static List<ServicentroFuelItem> _parseProductos(dynamic raw) {
    final list = <ServicentroFuelItem>[];
    if (raw is! List) return list;
    for (final row in raw) {
      if (row is! Map) continue;
      final item = ServicentroFuelItem.tryFromJson(
        Map<String, dynamic>.from(row),
      );
      if (item != null) list.add(item);
    }
    return list;
  }

  /// Stock/precio desde el mismo cache de productos que categorías / preorden.
  static Future<Map<int, _CatalogStock>> _catalogStockByProductId() async {
    final result = <int, _CatalogStock>{};
    try {
      final offlineData = await _prefs.getOfflineData();
      final products = offlineData?['products'];
      if (products is! Map) return result;

      for (final categoryProducts in products.values) {
        if (categoryProducts is! List) continue;
        for (final prodRaw in categoryProducts) {
          if (prodRaw is! Map) continue;
          final prod = Map<String, dynamic>.from(prodRaw);
          final pid = prod['id'];
          final id = pid is int ? pid : (pid is num ? pid.toInt() : null);
          if (id == null) continue;

          result[id] = _stockFromOfflineProductMap(prod);
        }
      }
    } catch (e) {
      print('⚠️ Lectura stock catálogo servicentro: $e');
    }
    return result;
  }

  static _CatalogStock _stockFromOfflineProductMap(Map<String, dynamic> prod) {
    double qty = (prod['cantidad'] as num?)?.toDouble() ?? 0;
    final detalles = prod['detalles_completos'];
    if (detalles is Map) {
      final fromInv = _stockFromDetalleMap(
        Map<String, dynamic>.from(detalles),
      );
      if (fromInv != null) qty = fromInv;
    }
    final precio = (prod['precio'] as num?)?.toDouble();
    return _CatalogStock(cantidad: qty, precio: precio);
  }

  /// Suma `cantidad_disponible` del bloque inventario (get_detalle_producto).
  static double? _stockFromDetalleMap(Map<String, dynamic> detalle) {
    final inv = detalle['inventario'];
    if (inv is! List || inv.isEmpty) return null;
    double sum = 0;
    for (final row in inv) {
      if (row is! Map) continue;
      sum += (row['cantidad_disponible'] as num?)?.toDouble() ?? 0;
    }
    return sum;
  }

  static double? _precioFromDetalleMap(Map<String, dynamic> detalle) {
    final producto = detalle['producto'];
    if (producto is Map) {
      return (producto['precio_actual'] as num?)?.toDouble();
    }
    return null;
  }

  /// Refresca stock en vivo con `get_detalles_productos_batch` (mismo que sync
  /// de catálogo) y actualiza el cache offline de esos productos.
  static Future<List<ServicentroFuelItem>> refreshStockFromServer(
    List<ServicentroFuelItem> items,
  ) async {
    if (items.isEmpty) return items;

    final offline = await _prefs.isOfflineModeEnabled() ||
        await _prefs.shouldStayFullyOffline();
    if (offline) {
      return enrichWithCatalogStock(items);
    }

    try {
      final ids = items.map((e) => e.idProducto).toSet().toList();
      final details = await _productDetail.getProductDetailsBatch(ids);
      if (details.isEmpty) {
        return enrichWithCatalogStock(items);
      }

      await _patchOfflineCatalogWithDetails(details);

      return items.map((item) {
        final detalle = details[item.idProducto];
        if (detalle is! Map) {
          return item;
        }
        final mapa = Map<String, dynamic>.from(detalle);
        final stock = _stockFromDetalleMap(mapa) ?? 0;
        final precio = _precioFromDetalleMap(mapa);
        return item.copyWith(
          stockDisponible: stock,
          tieneStock: stock > 0,
          precioVenta: (precio != null && precio > 0) ? precio : item.precioVenta,
        );
      }).toList();
    } catch (e) {
      print('⚠️ Refresh stock servicentro en vivo: $e — usando catálogo local');
      return enrichWithCatalogStock(items);
    }
  }

  /// Actualiza cantidad + detalles_completos en offline_data.products.
  static Future<void> _patchOfflineCatalogWithDetails(
    Map<int, dynamic> details,
  ) async {
    if (details.isEmpty) return;
    try {
      final offlineData = await _prefs.getOfflineData();
      if (offlineData == null) return;
      final products = offlineData['products'];
      if (products is! Map) return;

      var changed = false;
      final updated = <String, dynamic>{};
      products.forEach((key, value) {
        if (value is! List) {
          updated[key.toString()] = value;
          return;
        }
        final list = <Map<String, dynamic>>[];
        for (final prodRaw in value) {
          if (prodRaw is! Map) continue;
          final prod = Map<String, dynamic>.from(prodRaw);
          final pid = prod['id'];
          final id = pid is int ? pid : (pid is num ? pid.toInt() : null);
          final detalle = id != null ? details[id] : null;
          if (detalle is Map) {
            final mapa = Map<String, dynamic>.from(detalle);
            prod['detalles_completos'] = mapa;
            final stock = _stockFromDetalleMap(mapa);
            if (stock != null) {
              prod['cantidad'] = stock;
            }
            final precio = _precioFromDetalleMap(mapa);
            if (precio != null && precio > 0) {
              prod['precio'] = precio;
            }
            changed = true;
          }
          list.add(prod);
        }
        updated[key.toString()] = list;
      });

      if (!changed) return;
      offlineData['products'] = updated;
      await _prefs.saveOfflineData(offlineData);
      print('⛽ Stock catálogo offline actualizado para combustibles');
    } catch (e) {
      print('⚠️ No se pudo parchear stock offline servicentro: $e');
    }
  }

  /// Sobrescribe stock (y precio si hace falta) con el del catálogo de la app.
  static Future<List<ServicentroFuelItem>> enrichWithCatalogStock(
    List<ServicentroFuelItem> items,
  ) async {
    if (items.isEmpty) return items;
    final catalog = await _catalogStockByProductId();
    if (catalog.isEmpty) {
      print(
        '⚠️ Catálogo de productos vacío: stock servicentro sin alinear '
        '(sincroniza productos primero)',
      );
      return items;
    }

    return items.map((item) {
      final hit = catalog[item.idProducto];
      if (hit == null) {
        return item.copyWith(stockDisponible: 0, tieneStock: false);
      }
      return item.copyWith(
        stockDisponible: hit.cantidad,
        tieneStock: hit.cantidad > 0,
        precioVenta: (hit.precio != null && hit.precio! > 0)
            ? hit.precio!
            : item.precioVenta,
      );
    }).toList();
  }

  /// Producto completo para venta (detalle + inventario), igual que el catálogo.
  /// No usa el fallback vacío de [ServicentroFuelItem.toProduct]: sin metadata
  /// de ubicación la venta no puede descontar stock al sincronizar.
  static Future<Product> resolveProductForSale(ServicentroFuelItem fuel) async {
    return _productDetail.getProductDetail(fuel.idProducto);
  }

  /// Elige la fila de inventario como el detalle de producto normal:
  /// preferir stock > 0; si hay varias, la del almacén del TPV.
  static Future<Map<String, dynamic>?> resolveInventoryMetadata(
    Product product,
  ) async {
    final idAlmacen = await _prefs.getIdAlmacen();

    Map<String, dynamic>? fromVariant(ProductVariant v) => v.inventoryMetadata;

    final withStock =
        product.variantes.where((v) => v.cantidadReal > 0).toList();
    final pool =
        withStock.isNotEmpty ? withStock : List<ProductVariant>.from(product.variantes);

    if (pool.isNotEmpty) {
      if (idAlmacen != null) {
        for (final v in pool) {
          final meta = fromVariant(v);
          final metaAlmacen = (meta?['id_almacen'] as num?)?.toInt();
          if (metaAlmacen == idAlmacen &&
              (meta?['id_ubicacion'] != null)) {
            return meta;
          }
        }
      }
      for (final v in pool) {
        final meta = fromVariant(v);
        if (meta != null && meta['id_ubicacion'] != null) return meta;
      }
      return fromVariant(pool.first);
    }

    final productMeta = product.inventoryMetadata;
    if (productMeta != null && productMeta['id_ubicacion'] != null) {
      return productMeta;
    }
    return productMeta;
  }

  /// InventoryData alineado a [ProductDetailsScreen._buildInventoryData].
  static Future<Map<String, dynamic>> inventoryDataFromProduct(
    Product product,
  ) async {
    final meta = await resolveInventoryMetadata(product);
    if (meta == null) {
      return {
        'id_producto': product.id,
        'id_variante': null,
        'id_opcion_variante': null,
        'id_ubicacion': null,
        'id_inventario': null,
        'id_presentacion': null,
        'presentacion_nombre': null,
        'presentacion_factor_rel': null,
        'sku_producto': product.sku ?? product.id.toString(),
        'sku_ubicacion': null,
      };
    }

    return {
      'id_producto': product.id,
      'id_variante': meta['id_variante'],
      'id_opcion_variante': meta['id_opcion_variante'],
      'id_ubicacion': meta['id_ubicacion'],
      'id_inventario': meta['id_inventario'],
      'id_presentacion': meta['id_presentacion'],
      'presentacion_nombre': meta['presentacion_nombre'],
      'presentacion_factor_rel': meta['presentacion_factor_rel'] ?? 1.0,
      'sku_producto':
          meta['sku_producto'] ?? product.sku ?? product.id.toString(),
      'sku_ubicacion': meta['sku_ubicacion'],
    };
  }

  /// Nombre de ubicación como en ProductDetailsScreen._getLocationName.
  static Future<String> ubicacionFromProduct(Product product) async {
    final meta = await resolveInventoryMetadata(product);
    if (meta != null) {
      final ubicacionNombre = meta['ubicacion_nombre'] as String?;
      final almacenNombre = meta['almacen_nombre'] as String?;
      if (ubicacionNombre != null &&
          ubicacionNombre.isNotEmpty &&
          almacenNombre != null &&
          almacenNombre.isNotEmpty) {
        return '$almacenNombre - $ubicacionNombre';
      }
      if (ubicacionNombre != null && ubicacionNombre.isNotEmpty) {
        return ubicacionNombre;
      }
      if (almacenNombre != null && almacenNombre.isNotEmpty) {
        return almacenNombre;
      }
      final skuUbic = meta['sku_ubicacion']?.toString();
      if (skuUbic != null && skuUbic.trim().isNotEmpty) return skuUbic.trim();
    }
    return 'Almacén';
  }

  /// Alias usado por AutoSync.
  static Future<List<ServicentroFuelItem>> syncProductos({
    required int idTienda,
    int? idTpv,
  }) async {
    if (idTpv == null) {
      print('⚠️ syncProductos sin idTpv — se omite');
      return getCachedProductos();
    }
    return syncForTpv(idTpv);
  }

  static Future<void> primeCache() async {
    final flags = await _prefs.getTpvServicentroFlags();
    if (flags != null) {
      _modoCached = flags['modo'] == true;
      _columnasCached =
          ((flags['columnas'] as num?)?.toInt() ?? 2).clamp(1, 4);
      _tpvCached = (flags['id_tpv'] as num?)?.toInt();
      final nombre = flags['tpv_nombre']?.toString().trim();
      _tpvNombreCached =
          (nombre != null && nombre.isNotEmpty) ? nombre : _tpvNombreCached;
      final synced = flags['synced_at']?.toString();
      _syncedAtCached =
          synced != null ? DateTime.tryParse(synced) : null;
    }

    final sessionTpv = await _prefs.getIdTpv();
    if (sessionTpv != null &&
        _tpvCached != null &&
        sessionTpv != _tpvCached) {
      _modoCached = false;
      _columnasCached = 2;
      print(
        '⛽ Cache servicentro de TPV $_tpvCached ignorado '
        '(sesión=$sessionTpv)',
      );
    } else {
      print(
        '⛽ modo_servicentro TPV (cache): $_modoCached (tpv=$_tpvCached)',
      );
    }
  }

  static Future<List<ServicentroFuelItem>> getCachedProductos({
    int? idTpv,
  }) async {
    final cache = await _prefs.getServicentroProductosCache(idTpv: idTpv);
    if (cache == null) return [];
    final synced = cache['synced_at']?.toString();
    if (synced != null) {
      _syncedAtCached = DateTime.tryParse(synced) ?? _syncedAtCached;
    }
    final raw = cache['productos'] as List? ?? const [];
    final list = <ServicentroFuelItem>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final item = ServicentroFuelItem.tryFromJson(
        Map<String, dynamic>.from(e),
      );
      if (item != null) list.add(item);
    }
    return enrichWithCatalogStock(list);
  }

  /// Carga con conciencia offline: no fuerza red si el dispositivo está offline.
  static Future<ServicentroLoadResult> loadProductos({
    required int idTienda,
    int? idTpv,
  }) async {
    final offline = await _prefs.isOfflineModeEnabled() ||
        await _prefs.shouldStayFullyOffline();

    if (offline || idTpv == null) {
      final cached = await getCachedProductos(idTpv: idTpv);
      return ServicentroLoadResult(
        items: cached,
        fromCache: true,
        syncedAt: _syncedAtCached,
        warning: cached.isEmpty
            ? 'Sin combustibles en cache. Conéctate y sincroniza, '
                'o pide al gerente configurar el TPV en Admin.'
            : null,
      );
    }

    try {
      final items = await syncForTpv(idTpv);
      return ServicentroLoadResult(
        items: items,
        fromCache: false,
        syncedAt: _syncedAtCached,
        warning: items.isEmpty && _modoCached
            ? 'Modo servicentro activo pero no hay combustibles en este TPV. '
                'El gerente debe agregarlos en Admin → Gestión de TPVs → Servicentro.'
            : null,
      );
    } catch (e) {
      final cached = await getCachedProductos(idTpv: idTpv);
      return ServicentroLoadResult(
        items: cached,
        fromCache: true,
        syncedAt: _syncedAtCached,
        warning: cached.isEmpty
            ? 'No se pudo actualizar y no hay cache local.\n$e'
            : 'Mostrando cache local (sin conexión o error de red).',
      );
    }
  }

  static Future<List<ServicentroFuelItem>> getProductos({
    required int idTienda,
    int? idTpv,
  }) async {
    final result = await loadProductos(idTienda: idTienda, idTpv: idTpv);
    return result.items;
  }
}

class ServicentroFuelItem {
  final int id;
  final int idProducto;
  final int orden;
  final String color;
  final String denominacion;
  final String? sku;
  final String? um;
  final String? imagen;
  final double precioVenta;
  final double stockDisponible;
  final bool tieneStock;

  const ServicentroFuelItem({
    required this.id,
    required this.idProducto,
    required this.orden,
    required this.color,
    required this.denominacion,
    this.sku,
    this.um,
    this.imagen,
    this.precioVenta = 0,
    this.stockDisponible = 0,
    this.tieneStock = false,
  });

  bool get isValid => idProducto > 0 && denominacion.trim().isNotEmpty;

  /// Misma regla que categorías: `cantidadReal > 0`.
  bool get puedeVender => stockDisponible > 0;

  ServicentroFuelItem copyWith({
    int? id,
    int? idProducto,
    int? orden,
    String? color,
    String? denominacion,
    String? sku,
    String? um,
    String? imagen,
    double? precioVenta,
    double? stockDisponible,
    bool? tieneStock,
  }) {
    return ServicentroFuelItem(
      id: id ?? this.id,
      idProducto: idProducto ?? this.idProducto,
      orden: orden ?? this.orden,
      color: color ?? this.color,
      denominacion: denominacion ?? this.denominacion,
      sku: sku ?? this.sku,
      um: um ?? this.um,
      imagen: imagen ?? this.imagen,
      precioVenta: precioVenta ?? this.precioVenta,
      stockDisponible: stockDisponible ?? this.stockDisponible,
      tieneStock: tieneStock ?? this.tieneStock,
    );
  }

  static ServicentroFuelItem? tryFromJson(Map<String, dynamic> json) {
    try {
      final item = ServicentroFuelItem.fromJson(json);
      if (!item.isValid) return null;
      return item;
    } catch (_) {
      return null;
    }
  }

  factory ServicentroFuelItem.fromJson(Map<String, dynamic> json) {
    return ServicentroFuelItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      idProducto: (json['id_producto'] as num?)?.toInt() ?? 0,
      orden: (json['orden'] as num?)?.toInt() ?? 0,
      color: (json['color'] ?? '#64748B').toString(),
      denominacion: (json['denominacion'] ?? '').toString(),
      sku: json['sku']?.toString(),
      um: json['um']?.toString(),
      imagen: json['imagen']?.toString(),
      precioVenta: (json['precio_venta'] as num?)?.toDouble() ?? 0,
      stockDisponible: (json['stock_disponible'] as num?)?.toDouble() ?? 0,
      tieneStock: json['tiene_stock'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'id_producto': idProducto,
        'orden': orden,
        'color': color,
        'denominacion': denominacion,
        'sku': sku,
        'um': um,
        'imagen': imagen,
        'precio_venta': precioVenta,
        'stock_disponible': stockDisponible,
        'tiene_stock': tieneStock,
      };

  Product toProduct() {
    return Product(
      id: idProducto,
      denominacion: denominacion,
      sku: sku,
      foto: imagen,
      precio: precioVenta,
      cantidad: stockDisponible,
      esRefrigerado: false,
      esFragil: false,
      esPeligroso: false,
      esVendible: true,
      esComprable: false,
      esInventariable: true,
      esPorLotes: false,
      esElaborado: false,
      esServicio: false,
      categoria: 'Combustible',
    );
  }

  static ColorParse parseColor(String hex) {
    final cleaned = hex.trim();
    if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(cleaned)) {
      return const ColorParse(valid: false, argb: 0xFF64748B);
    }
    final value = int.parse(cleaned.substring(1), radix: 16);
    return ColorParse(valid: true, argb: 0xFF000000 | value);
  }
}

class ColorParse {
  final bool valid;
  final int argb;
  const ColorParse({required this.valid, required this.argb});
}

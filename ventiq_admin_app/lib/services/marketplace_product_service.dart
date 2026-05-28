import 'package:supabase_flutter/supabase_flutter.dart';

/// Producto ligero devuelto por el RPC `get_productos_marketplace`.
/// Se usa en el selector WAPI para difundir productos por WhatsApp:
/// solo necesitamos los campos visibles + el `idProducto` que viaja al backend.
class MarketplaceProduct {
  final int idProducto;
  final String denominacion;
  final String categoriaNombre;
  final double precioVenta;
  final String imagen;
  final double stockDisponible;
  final bool tieneStock;
  final String? ubicacion;
  final String? direccion;
  final String? denominacionTienda;

  MarketplaceProduct({
    required this.idProducto,
    required this.denominacion,
    required this.categoriaNombre,
    required this.precioVenta,
    required this.imagen,
    required this.stockDisponible,
    required this.tieneStock,
    this.ubicacion,
    this.direccion,
    this.denominacionTienda,
  });

  factory MarketplaceProduct.fromJson(Map<String, dynamic> j) {
    final meta = (j['metadata'] is Map<String, dynamic>)
        ? j['metadata'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return MarketplaceProduct(
      idProducto: (j['id_producto'] as num).toInt(),
      denominacion: (j['denominacion'] ?? '').toString(),
      categoriaNombre: (j['categoria_nombre'] ?? '').toString(),
      precioVenta: (j['precio_venta'] as num?)?.toDouble() ?? 0.0,
      imagen: (j['imagen'] ?? '').toString(),
      stockDisponible:
          (j['stock_disponible'] as num?)?.toDouble() ?? 0.0,
      tieneStock: j['tiene_stock'] == true,
      ubicacion: meta['ubicacion']?.toString(),
      direccion: meta['direccion']?.toString(),
      denominacionTienda: meta['denominacion_tienda']?.toString(),
    );
  }
}

class MarketplaceProductService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Llama al RPC `get_productos_marketplace` con paginación servidor.
  /// - [search]: cuando es no-nulo y no-vacío se envía como `search_query_param`.
  /// - [soloDisponibles]: por defecto true (filtra stock=0 en backend).
  static Future<List<MarketplaceProduct>> getProductos({
    required int idTienda,
    int limit = 20,
    int offset = 0,
    String? search,
    int? idCategoria,
    bool soloDisponibles = true,
  }) async {
    final q = search?.trim();
    final response = await _supabase.rpc(
      'get_productos_marketplace',
      params: {
        'id_tienda_param': idTienda,
        'id_categoria_param': idCategoria,
        'solo_disponibles_param': soloDisponibles,
        'search_query_param': (q == null || q.isEmpty) ? null : q,
        'limit_param': limit,
        'offset_param': offset,
      },
    );
    if (response == null) return [];
    final list = response as List<dynamic>;
    return list
        .map((e) => MarketplaceProduct.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

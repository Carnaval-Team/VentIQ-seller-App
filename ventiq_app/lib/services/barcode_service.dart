import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';

/// Resultado de búsqueda por código de barras.
/// Contiene el producto exacto (si existe), el desglose del código,
/// y productos similares del mismo fabricante.
class BarcodeSearchResult {
  final bool encontrado;
  final String codigoBarras;
  final Product? producto;
  final Map<String, String?> desglose;
  final List<Map<String, dynamic>> similares;

  BarcodeSearchResult({
    required this.encontrado,
    required this.codigoBarras,
    this.producto,
    required this.desglose,
    required this.similares,
  });
}

class BarcodeService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Busca un producto por código de barras usando la RPC v3.
  /// Retorna el producto completo con stock, precio, categoría,
  /// además de productos similares del mismo fabricante.
  Future<BarcodeSearchResult?> searchProductByBarcode(String barcode) async {
    try {
      print('🔍 Buscando producto con código de barras: $barcode');

      final response = await _supabase.rpc(
        'buscar_producto_por_codigo_barras_v3',
        params: {'p_barcode': barcode},
      );

      print('📦 Respuesta RPC v3: $response');

      if (response == null) {
        print('⚠️ Respuesta nula del RPC');
        return null;
      }

      final data = response as Map<String, dynamic>;
      final encontrado = data['encontrado'] == true;

      // Parsear desglose
      final desgloseRaw = data['desglose'] as Map<String, dynamic>? ?? {};
      final desglose = <String, String?>{
        'prefijo_pais': desgloseRaw['prefijo_pais']?.toString(),
        'codigo_fabricante': desgloseRaw['codigo_fabricante']?.toString(),
        'codigo_producto': desgloseRaw['codigo_producto']?.toString(),
        'digito_control': desgloseRaw['digito_control']?.toString(),
      };

      // Parsear producto exacto
      Product? producto;
      if (encontrado && data['producto'] != null) {
        producto = _mapProductFromV3(data['producto'] as Map<String, dynamic>);
      }

      // Parsear similares
      final similaresRaw = data['similares'] as List<dynamic>? ?? [];
      final similares = similaresRaw
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList();

      print('✅ Encontrado: $encontrado | Similares: ${similares.length}');
      if (desglose['codigo_fabricante'] != null) {
        print('📊 Fabricante: ${desglose['codigo_fabricante']} | País: ${desglose['prefijo_pais']}');
      }

      return BarcodeSearchResult(
        encontrado: encontrado,
        codigoBarras: barcode,
        producto: producto,
        desglose: desglose,
        similares: similares,
      );
    } catch (e) {
      print('❌ Error al buscar producto por código de barras: $e');
      return null;
    }
  }

  /// Mapea la respuesta del RPC v3 a un objeto Product completo.
  Product _mapProductFromV3(Map<String, dynamic> data) {
    // Extraer categoría
    final categoriaData = data['categoria'] as Map<String, dynamic>?;
    final categoriaNombre = categoriaData?['denominacion'] ?? '';

    // Extraer variantes
    final variantesRaw = data['variantes'] as List<dynamic>? ?? [];
    final variantes = variantesRaw.map((v) {
      final vMap = v as Map<String, dynamic>;
      final opcion = vMap['opcion'] as Map<String, dynamic>?;
      final atributo = vMap['atributo'] as Map<String, dynamic>?;
      return ProductVariant(
        id: vMap['id'] ?? 0,
        nombre: '${atributo?['label'] ?? ''}: ${opcion?['valor'] ?? ''}',
        precio: (vMap['precio'] as num?)?.toDouble() ?? 0.0,
        cantidad: vMap['stock'] ?? 0,
      );
    }).toList();

    return Product(
      id: data['id'] ?? 0,
      denominacion: data['denominacion'] ?? '',
      descripcion: data['descripcion'] ?? data['descripcion_corta'] ?? '',
      sku: data['sku'],
      foto: data['imagen'],
      precio: (data['precio_venta'] as num?)?.toDouble() ?? 0.0,
      cantidad: data['stock_disponible'] ?? 0,
      categoria: categoriaNombre,
      variantes: variantes,
      esRefrigerado: data['es_refrigerado'] ?? false,
      esFragil: data['es_fragil'] ?? false,
      esPeligroso: data['es_peligroso'] ?? false,
      esVendible: data['es_vendible'] ?? true,
      esComprable: data['es_comprable'] ?? true,
      esInventariable: data['es_inventariable'] ?? true,
      esPorLotes: data['es_por_lotes'] ?? false,
      esElaborado: data['es_elaborado'] ?? false,
      esServicio: data['es_servicio'] ?? false,
    );
  }
}

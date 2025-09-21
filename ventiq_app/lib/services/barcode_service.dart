import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';

class BarcodeService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<Product?> searchProductByBarcode(String barcode) async {
    try {
      print('Buscando producto con código de barras: $barcode');
      
      final response = await _supabase.rpc('buscar_producto_por_codigo_barras_v2', 
        params: {'p_barcode': barcode}
      );

      print('Respuesta RPC v2: $response');

      if (response == null || response.isEmpty) {
        print('No se encontró producto con el código de barras: $barcode');
        return null;
      }

      // Tomar el primer resultado (debería ser único por código de barras)
      final productData = response[0];
      
      print('Creando producto desde datos del código de barras v2');
      return _createProductFromBarcodeDataV2(productData);
      
    } catch (e) {
      print('Error al buscar producto por código de barras: $e');
      return null;
    }
  }

  Product _createProductFromBarcodeDataV2(Map<String, dynamic> data) {
    return Product(
      id: data['id'] ?? 0,
      denominacion: data['denominacion'] ?? '',
      descripcion: data['descripcion'] ?? data['descripcion_corta'] ?? '',
      precio: 0.0, // Se obtendría de otra tabla de precios
      cantidad: 100, // Valor por defecto para stock
      categoria: '', // Se obtendría de la tabla de categorías
      foto: data['imagen'], // URL de imagen del producto
      variantes: [], // Las variantes se obtendrían de otra consulta
      // Mapear campos booleanos desde la nueva estructura
      esRefrigerado: data['es_refrigerado'] ?? false,
      esFragil: data['es_fragil'] ?? false,
      esPeligroso: data['es_peligroso'] ?? false,
      esVendible: data['es_vendible'] ?? true,
      esComprable: data['es_comprable'] ?? true,
      esInventariable: data['es_inventariable'] ?? true,
      esPorLotes: data['es_por_lotes'] ?? false,
      esElaborado: data['es_elaborado'] ?? false,
    );
  }
}

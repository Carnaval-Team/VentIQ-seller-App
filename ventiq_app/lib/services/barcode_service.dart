import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';

class BarcodeService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<Product?> searchProductByBarcode(String barcode) async {
    try {
      print('Buscando producto con código de barras: $barcode');
      
      final response = await _supabase.rpc('buscar_producto_por_codigo_barras', 
        params: {'codigo_barras_param': barcode}
      );

      print('Respuesta RPC: $response');

      if (response == null || response.isEmpty) {
        print('No se encontró producto con el código de barras: $barcode');
        return null;
      }

      // Tomar el primer resultado (debería ser único por código de barras)
      final productData = response[0];
      
      // Verificar si tenemos suficientes datos para crear el producto
      if (_hasCompleteProductData(productData)) {
        print('Creando producto desde datos del código de barras');
        return _createProductFromBarcodeData(productData);
      } else {
        // Si no tenemos datos completos, llamar al servicio de productos
        print('Datos incompletos, cargando detalles del producto ID: ${productData['id_producto']}');
        return await _loadProductDetails(productData['id_producto']);
      }
      
    } catch (e) {
      print('Error al buscar producto por código de barras: $e');
      return null;
    }
  }

  bool _hasCompleteProductData(Map<String, dynamic> data) {
    // Verificar si tenemos los campos mínimos necesarios para crear un Product
    return data['denominacion_producto'] != null &&
           data['sku_producto'] != null &&
           data['id_producto'] != null;
  }

  Product _createProductFromBarcodeData(Map<String, dynamic> data) {
    return Product(
      id: data['id_producto'] ?? 0,
      denominacion: data['denominacion_producto'] ?? '',
      descripcion: _buildProductDescription(data),
      precio: 0.0, // No viene en la respuesta del RPC
      cantidad: 100, // Valor por defecto
      categoria: data['tienda_nombre'] ?? '',
      foto: null, // No viene en la respuesta del RPC
      variantes: _buildVariants(data),
      // Valores por defecto para campos booleanos
      esRefrigerado: false,
      esFragil: false,
      esPeligroso: false,
      esVendible: true,
      esComprable: true,
      esInventariable: true,
      esPorLotes: false,
    );
  }

  String _buildProductDescription(Map<String, dynamic> data) {
    List<String> descriptionParts = [];
    
    if (data['variante_nombre'] != null) {
      descriptionParts.add('${data['variante_nombre']}: ${data['opcion_variante_valor'] ?? ''}');
    }
    
    if (data['presentacion_nombre'] != null) {
      descriptionParts.add('Presentación: ${data['presentacion_nombre']}');
      if (data['cantidad_presentacion'] != null) {
        descriptionParts.add('Cantidad: ${data['cantidad_presentacion']}');
      }
    }
    
    return descriptionParts.join(' | ');
  }

  List<ProductVariant> _buildVariants(Map<String, dynamic> data) {
    if (data['variante_nombre'] != null && data['opcion_variante_valor'] != null) {
      return [
        ProductVariant(
          id: data['id_variante'] ?? 0,
          nombre: '${data['variante_nombre']}: ${data['opcion_variante_valor']}',
          precio: 0.0, // No viene en la respuesta del RPC
          cantidad: 100, // Valor por defecto
          descripcion: data['presentacion_nombre'],
        )
      ];
    }
    return [];
  }

  Future<Product?> _loadProductDetails(int productId) async {
    try {
      // Aquí podrías llamar al ProductService si tienes un método para obtener por ID
      // Por ahora retornamos null para que se maneje como producto no encontrado
      print('Función para cargar detalles del producto por ID no implementada aún');
      return null;
    } catch (e) {
      print('Error al cargar detalles del producto: $e');
      return null;
    }
  }
}

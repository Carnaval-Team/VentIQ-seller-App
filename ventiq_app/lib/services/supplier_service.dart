import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/supplier.dart';

class SupplierService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Obtener todos los proveedores de una tienda
  Future<List<Supplier>> getSuppliersByStore(int idTienda) async {
    try {
      print('📦 Obteniendo proveedores para tienda $idTienda...');

      final response = await _supabase
          .from('app_dat_proveedor')
          .select('id, denominacion, idtienda')
          .eq('idtienda', idTienda)
          .order('denominacion', ascending: true);

      print('✅ Proveedores obtenidos: ${response.length}');

      return (response as List<dynamic>)
          .map((json) => Supplier.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e,st) {
      print('❌ Error obteniendo proveedores: $e $st');
      rethrow;
    }
  }

  /// Asignar un proveedor a múltiples productos
  Future<void> assignSupplierToProducts(
    int supplierId,
    List<int> productIds,
  ) async {
    try {
      print(
        '📦 Asignando proveedor $supplierId a ${productIds.length} productos...',
      );

      // Actualizar cada producto con el id del proveedor
      for (final productId in productIds) {
        await _supabase
            .from('app_dat_producto')
            .update({'id_proveedor': supplierId})
            .eq('id', productId);
      }

      print('✅ Proveedor asignado exitosamente a ${productIds.length} productos');
    } catch (e) {
      print('❌ Error asignando proveedor a productos: $e');
      rethrow;
    }
  }

  /// Obtener el proveedor de un producto
  Future<Supplier?> getProductSupplier(int productId) async {
    try {
      final response = await _supabase
          .from('app_dat_producto')
          .select('id_proveedor')
          .eq('id', productId)
          .single();

      final supplierId = response['id_proveedor'] as int?;
      
      if (supplierId == null) {
        return null;
      }

      final supplierResponse = await _supabase
          .from('app_dat_proveedor')
          .select('id, denominacion, idtienda')
          .eq('id', supplierId)
          .single();

      return Supplier.fromJson(supplierResponse as Map<String, dynamic>);
    } catch (e) {
      print('❌ Error obteniendo proveedor del producto: $e');
      return null;
    }
  }
}

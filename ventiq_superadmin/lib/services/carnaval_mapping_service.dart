import 'package:supabase_flutter/supabase_flutter.dart';

class CarnavalMappingService {
  final supabase = Supabase.instance.client;

  // Obtener todas las tiendas
  Future<List<Map<String, dynamic>>> getStores() async {
    final response = await supabase
        .from('app_dat_tienda')
        .select('id, denominacion, direccion')
        .order('denominacion');
    return List<Map<String, dynamic>>.from(response);
  }

  // Obtener productos de una tienda específica
  Future<List<Map<String, dynamic>>> getStoreProducts(int storeId) async {
    final response = await supabase
        .from('app_dat_producto')
        .select(
          'id, denominacion, id_vendedor_app, app_dat_precio_venta(precio_venta_cup), sku',
        )
        .eq('id_tienda', storeId)
        .order('denominacion');
    return List<Map<String, dynamic>>.from(response);
  }

  // Obtener proveedores de Carnaval App
  Future<List<Map<String, dynamic>>> getCarnavalProviders() async {
    // Nota: Consultando esquema carnavalapp
    final response = await supabase
        .schema('carnavalapp')
        .from('proveedores')
        .select('id, name')
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  // Obtener productos de un proveedor de Carnaval
  Future<List<Map<String, dynamic>>> getCarnavalProducts(int providerId) async {
    final response = await supabase
        .schema('carnavalapp')
        .from('Productos')
        .select('id, name, price, description, image')
        .eq('proveedor', providerId)
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  // Obtener un producto de Carnaval por ID (para mostrar detalles si ya está enlazado)
  Future<Map<String, dynamic>?> getCarnavalProductById(int productId) async {
    final response = await supabase
        .schema('carnavalapp')
        .from('Productos')
        .select('id, name, price, description, image, proveedor')
        .eq('id', productId)
        .maybeSingle();
    return response;
  }

  // Obtener nombre del proveedor por ID
  Future<String?> getProviderName(int providerId) async {
    final response = await supabase
        .schema('carnavalapp')
        .from('proveedores')
        .select('name')
        .eq('id', providerId)
        .maybeSingle();

    if (response != null && response['name'] != null) {
      return response['name'] as String;
    }
    return null;
  }

  // Enlazar producto
  Future<void> linkProduct({
    required int localProductId,
    required int carnavalProductId,
    required bool updateName,
    String? newName,
    String? newImage,
  }) async {
    final updates = <String, dynamic>{'id_vendedor_app': carnavalProductId};

    if (updateName && newName != null) {
      updates['denominacion'] = newName;
    }

    if (newImage != null && newImage.isNotEmpty) {
      updates['imagen'] = newImage;
    }

    await supabase
        .from('app_dat_producto')
        .update(updates)
        .eq('id', localProductId);
  }
}

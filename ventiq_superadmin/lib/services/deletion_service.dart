import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/deletion_items.dart';

class DeletionService {
  static final _supabase = Supabase.instance.client;

  /// Obtiene proveedores de Carnaval con conteo de productos y último acceso del admin (auth.users.last_sign_in_at).
  static Future<List<CarnavalProviderDeletionItem>> getCarnavalProviders({
    int page = 0,
    int pageSize = 25,
  }) async {
    try {
      final providers =
          await _supabase.rpc(
                'fn_get_carnaval_providers_for_deletion',
                params: {'p_page': page, 'p_page_size': pageSize},
              )
              as List<dynamic>;

      return providers
          .map(
            (prov) => CarnavalProviderDeletionItem(
              id: prov['id'] as int,
              name: prov['name'] ?? 'Sin nombre',
              totalProductos: (prov['total_productos'] ?? 0) as int,
              ultimoAcceso:
                  prov['ultimo_acceso'] != null
                      ? DateTime.parse(prov['ultimo_acceso'])
                      : null,
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('❌ Error obteniendo proveedores para eliminación: $e');
      return [];
    }
  }

  /// Obtiene tiendas de Inventtia con total productos, almacenes y último acceso de supervisor (auth.users.last_sign_in_at).
  static Future<List<InventtiaStoreDeletionItem>> getInventtiaStores({
    int page = 0,
    int pageSize = 25,
  }) async {
    try {
      final stores =
          await _supabase.rpc(
                'fn_get_inventtia_stores_for_deletion',
                params: {'p_page': page, 'p_page_size': pageSize},
              )
              as List<dynamic>;

      return stores
          .map(
            (store) => InventtiaStoreDeletionItem(
              id: store['id'] as int,
              name: store['name'] ?? 'Sin nombre',
              totalProductos: (store['total_productos'] ?? 0) as int,
              totalAlmacenes: (store['total_almacenes'] ?? 0) as int,
              ultimoAccesoSupervisor:
                  store['ultimo_acceso_supervisor'] != null
                      ? DateTime.parse(store['ultimo_acceso_supervisor'])
                      : null,
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('❌ Error obteniendo tiendas para eliminación: $e');
      return [];
    }
  }

  /// Ejecuta la eliminación de proveedor en Carnaval.
  static Future<void> deleteCarnavalProvider(int providerId) async {
    await _supabase.schema('carnavalapp').rpc(
      'delete_proveedor_completo',
      params: {'p_proveedor_id': providerId},
    );
  }

  /// Ejecuta la eliminación de tienda en Inventtia.
  static Future<void> deleteInventtiaStore(int storeId) async {
    await _supabase.rpc(
      'delete_tienda_completa',
      params: {'p_tienda_id': storeId},
    );
  }
}

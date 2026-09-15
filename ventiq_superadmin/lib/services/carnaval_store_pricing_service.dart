import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CarnavalStorePricingService {
  static final _supabase = Supabase.instance.client;

  /// Devuelve los ids de tienda carnaval que tienen al menos un producto
  /// publicado en `carnavalapp.Productos`.
  static Future<Set<int>> _getCarnavalStoreIdsWithProducts(
    Set<int?> carnavalStoreIds,
  ) async {
    final ids = carnavalStoreIds.whereType<int>().toList();
    if (ids.isEmpty) return {};
    try {
      final response = await _supabase
          .schema('carnavalapp')
          .from('Productos')
          .select('proveedor')
          .inFilter('proveedor', ids);
      return (response as List)
          .map((r) => (r['proveedor'] as num?)?.toInt())
          .whereType<int>()
          .toSet();
    } catch (e) {
      debugPrint('❌ Error obteniendo tiendas con productos carnaval: $e');
      return {};
    }
  }

  /// Obtiene todas las tiendas con sus porcentajes actuales de recargo.
  static Future<List<Map<String, dynamic>>> getStoresWithPricing({
    bool onlyWithProducts = false,
  }) async {
    try {
      final storesResponse = await _supabase
          .from('app_dat_tienda')
          .select('id, denominacion, id_tienda_carnaval')
          .order('denominacion');

      final tiendaIds = (storesResponse as List)
          .map((s) => s['id'] as int?)
          .whereType<int>()
          .toList();

      final pricingResponse = await _supabase
          .from('app_dat_precio_general_tienda')
          .select('id_tienda, precio_regular, precio_venta_carnaval, precio_venta_carnaval_transferencia')
          .inFilter('id_tienda', tiendaIds);

      final pricingByStore = <int, Map<String, dynamic>>{};
      for (final row in pricingResponse as List) {
        final id = row['id_tienda'] as int?;
        if (id == null) continue;
        pricingByStore[id] = {
          'precio_regular': (row['precio_regular'] as num?)?.toDouble() ?? 0.0,
          'precio_venta_carnaval':
              (row['precio_venta_carnaval'] as num?)?.toDouble() ?? 0.0,
          'precio_venta_carnaval_transferencia':
              (row['precio_venta_carnaval_transferencia'] as num?)?.toDouble() ??
                  0.0,
        };
      }

      var stores = <Map<String, dynamic>>[];
      for (final store in storesResponse) {
        final id = store['id'] as int?;
        if (id == null) continue;
        final pricing = pricingByStore[id] ??
            {
              'precio_regular': 0.0,
              'precio_venta_carnaval': 0.0,
              'precio_venta_carnaval_transferencia': 0.0,
            };
        stores.add({
          'id': id,
          'denominacion': store['denominacion'] as String? ?? 'Sin nombre',
          'id_tienda_carnaval': store['id_tienda_carnaval'] as int?,
          ...pricing,
        });
      }

      if (onlyWithProducts) {
        final carnavalIds =
            stores.map((s) => s['id_tienda_carnaval'] as int?).toSet();
        final withProducts =
            await _getCarnavalStoreIdsWithProducts(carnavalIds);
        stores = stores
            .where((s) => withProducts.contains(s['id_tienda_carnaval']))
            .toList();
      }

      return stores;
    } catch (e) {
      debugPrint('❌ Error obteniendo tiendas con precios: $e');
      return [];
    }
  }

  /// Obtiene el piso global de porcentajes.
  static Future<Map<String, double>> getGlobalFloor() async {
    try {
      final response = await _supabase
          .from('precio_global_productos_carnaval')
          .select('porciento_efectivo, porciento_transferencia')
          .limit(1)
          .maybeSingle();

      return {
        'efectivo': (response?['porciento_efectivo'] as num?)?.toDouble() ?? 0.0,
        'transferencia':
            (response?['porciento_transferencia'] as num?)?.toDouble() ?? 0.0,
      };
    } catch (e) {
      debugPrint('❌ Error obteniendo piso global: $e');
      return {'efectivo': 0.0, 'transferencia': 0.0};
    }
  }

  /// Actualiza el piso global de porcentajes.
  static Future<bool> updateGlobalFloor({
    required double efectivo,
    required double transferencia,
  }) async {
    try {
      await _supabase
          .from('precio_global_productos_carnaval')
          .update({
            'porciento_efectivo': efectivo,
            'porciento_transferencia': transferencia,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .not('id', 'is', null);
      return true;
    } catch (e) {
      debugPrint('❌ Error actualizando piso global: $e');
      return false;
    }
  }

  /// Actualiza o inserta la configuración de recargos de una tienda.
  static Future<bool> updateStorePricing({
    required int storeId,
    required double precioRegular,
    required double precioVentaCarnaval,
    required double precioVentaCarnavalTransferencia,
  }) async {
    try {
      await _supabase.from('app_dat_precio_general_tienda').upsert(
        {
          'id_tienda': storeId,
          'precio_regular': precioRegular,
          'precio_venta_carnaval': precioVentaCarnaval,
          'precio_venta_carnaval_transferencia':
              precioVentaCarnavalTransferencia,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'id_tienda',
      );
      return true;
    } catch (e) {
      debugPrint('❌ Error actualizando precios de tienda $storeId: $e');
      return false;
    }
  }
}

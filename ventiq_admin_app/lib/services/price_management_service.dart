import 'package:supabase_flutter/supabase_flutter.dart';

class ProductPriceItem {
  final int id;
  final String name;
  final String sku;
  final double? lastPrice;
  final DateTime? lastPriceDate;
  final int? vendedorAppId;

  ProductPriceItem({
    required this.id,
    required this.name,
    required this.sku,
    required this.lastPrice,
    required this.lastPriceDate,
    required this.vendedorAppId,
  });

  factory ProductPriceItem.fromJson(Map<String, dynamic> json) {
    return ProductPriceItem(
      id: json['id_producto'] ?? json['id'] ?? 0,
      name: json['denominacion'] ?? json['nombre'] ?? '',
      sku: json['sku'] ?? '',
      lastPrice: (json['precio_venta_cup'] ?? json['last_price'])?.toDouble(),
      lastPriceDate:
          json['created_at'] != null
              ? DateTime.tryParse(json['created_at'].toString())
              : null,
      vendedorAppId: json['id_vendedor_app'],
    );
  }
}

class GeneralPriceConfig {
  final double precioRegular;
  final double precioVentaCarnaval;
  final double precioVentaCarnavalTransferencia;

  const GeneralPriceConfig({
    required this.precioRegular,
    required this.precioVentaCarnaval,
    required this.precioVentaCarnavalTransferencia,
  });
}

class PriceManagementService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Obtiene todos los productos de la tienda con su último precio registrado.
  /// Usa RPC para evitar N+1; si no existe, hace fallback a una vista básica.
  static Future<List<ProductPriceItem>> getProductsWithLastPrice(
    int storeId,
  ) async {
    try {
      final response = await _supabase.rpc(
        'rpc_get_products_last_price',
        params: {'p_store_id': storeId},
      );

      if (response is List) {
        return response.map((e) => ProductPriceItem.fromJson(e)).toList();
      }
    } catch (e) {
      print('❌ RPC rpc_get_products_last_price no disponible: $e');
    }

    // Fallback: consulta compacta (puede ser menos eficiente)
    try {
      final data = await _supabase
          .from('app_dat_producto')
          .select('''
            id,
            denominacion,
            sku,
            id_vendedor_app,
            app_dat_precio_venta!left(
              precio_venta_cup,
              created_at
            )
            ''')
          .eq('id_tienda', storeId);

      return data.map<ProductPriceItem>((item) {
        final prices = item['app_dat_precio_venta'] as List<dynamic>? ?? [];
        prices.sort(
          (a, b) => DateTime.parse(
            b['created_at'],
          ).compareTo(DateTime.parse(a['created_at'])),
        );
        final last = prices.isNotEmpty ? prices.first : null;

        return ProductPriceItem(
          id: item['id'],
          name: item['denominacion'] ?? '',
          sku: item['sku'] ?? '',
          vendedorAppId: item['id_vendedor_app'],
          lastPrice:
              last != null
                  ? (last['precio_venta_cup'] as num?)?.toDouble()
                  : null,
          lastPriceDate:
              last != null ? DateTime.tryParse(last['created_at']) : null,
        );
      }).toList();
    } catch (e) {
      print('❌ Error fallback obteniendo productos con precio: $e');
      return [];
    }
  }

  /// Obtiene o crea la configuración global de precios para la tienda.
  static Future<GeneralPriceConfig> getOrCreatePriceConfig(int storeId) async {
    const defaults = GeneralPriceConfig(
      precioRegular: 0.0,
      precioVentaCarnaval: 5.3,
      precioVentaCarnavalTransferencia: 11.1,
    );

    try {
      final response =
          await _supabase
              .from('app_dat_precio_general_tienda')
              .select()
              .eq('id_tienda', storeId)
              .maybeSingle();

      if (response != null) {
        return GeneralPriceConfig(
          precioRegular:
              (response['precio_regular'] ?? defaults.precioRegular).toDouble(),
          precioVentaCarnaval:
              (response['precio_venta_carnaval'] ??
                      defaults.precioVentaCarnaval)
                  .toDouble(),
          precioVentaCarnavalTransferencia:
              (response['precio_venta_carnaval_transferencia'] ??
                      defaults.precioVentaCarnavalTransferencia)
                  .toDouble(),
        );
      }

      // Crear con defaults
      await _supabase.from('app_dat_precio_general_tienda').insert({
        'id_tienda': storeId,
        'precio_regular': defaults.precioRegular,
        'precio_venta_carnaval': defaults.precioVentaCarnaval,
        'precio_venta_carnaval_transferencia':
            defaults.precioVentaCarnavalTransferencia,
      });

      return defaults;
    } catch (e) {
      print('❌ Error obteniendo/creando configuración de precios: $e');
      return defaults;
    }
  }

  /// Aplica cambio de precio global vía RPC (recomendada).
  static Future<bool> applyGlobalPriceChange({
    required int storeId,
    required double precioRegular,
    required double precioCarnaval,
    required double precioCarnavalTransferencia,
  }) async {
    try {
      await _supabase.rpc(
        'rpc_apply_global_price_change',
        params: {
          'p_store_id': storeId,
          'p_precio_regular': precioRegular,
          'p_precio_carnaval': precioCarnaval,
          'p_precio_carnaval_transferencia': precioCarnavalTransferencia,
        },
      );
      return true;
    } catch (e) {
      print('❌ Error aplicando cambio global: $e');
      return false;
    }
  }

  /// Aplica cambio de precio a productos seleccionados.
  /// changeType: 'percent' | 'fixed'
  static Future<bool> applySelectedPriceChange({
    required int storeId,
    required List<int> productIds,
    required String changeType,
    required double changeValue,
    required double precioCarnaval,
    required double precioCarnavalTransferencia,
  }) async {
    try {
      await _supabase.rpc(
        'rpc_apply_selected_price_change',
        params: {
          'p_store_id': storeId,
          'p_product_ids': productIds,
          'p_change_type': changeType,
          'p_change_value': changeValue,
          'p_precio_carnaval': precioCarnaval,
          'p_precio_carnaval_transferencia': precioCarnavalTransferencia,
        },
      );
      return true;
    } catch (e) {
      print('❌ Error aplicando cambio seleccionado: $e');
      return false;
    }
  }
}

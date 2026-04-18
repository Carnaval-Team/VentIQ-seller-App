import 'package:supabase_flutter/supabase_flutter.dart';

class ProductPriceItem {
  final int id;
  final String name;
  final String sku;
  final double? lastPrice;
  final double? lastPriceUsd;
  final DateTime? lastPriceDate;
  final int? vendedorAppId;
  final List<Map<String, dynamic>> presentaciones;

  ProductPriceItem({
    required this.id,
    required this.name,
    required this.sku,
    required this.lastPrice,
    this.lastPriceUsd,
    required this.lastPriceDate,
    required this.vendedorAppId,
    this.presentaciones = const [],
  });

  factory ProductPriceItem.fromJson(Map<String, dynamic> json) {
    final presList = (json['presentaciones'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return ProductPriceItem(
      id: json['id_producto'] ?? json['id'] ?? 0,
      name: json['denominacion'] ?? json['nombre'] ?? '',
      sku: json['sku'] ?? '',
      lastPrice: (json['precio_venta_cup'] ?? json['last_price'])?.toDouble(),
      lastPriceUsd: (json['precio_venta_usd'])?.toDouble(),
      lastPriceDate:
          json['created_at'] != null
              ? DateTime.tryParse(json['created_at'].toString())
              : null,
      vendedorAppId: json['id_vendedor_app'],
      presentaciones: presList,
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
        'rpc_get_products_last_price2',
        params: {'p_store_id': storeId},
      );

      if (response is List) {
        return response.map((e) => ProductPriceItem.fromJson(e)).toList();
      }
    } catch (e) {
      print('❌ RPC rpc_get_products_last_price2 no disponible: $e');
    }

    // Fallback: consulta compacta (puede ser menos eficiente)
    try {
      final data = await _supabase
          .from('app_dat_producto')
          .select('id, denominacion, sku, id_vendedor_app')
          .eq('id_tienda', storeId);

      final productoIds =
          (data as List).map((item) => item['id'] as int).toList();

      if (productoIds.isEmpty) return [];

      // Fetch only the latest price per product (one query, ordered desc)
      final preciosResp = await _supabase
          .from('app_dat_precio_venta')
          .select('id_producto, precio_venta_cup, precio_venta_usd, created_at')
          .inFilter('id_producto', productoIds)
          .order('created_at', ascending: false);

      // Keep only the first (latest) price per product
      final Map<int, Map<String, dynamic>> latestPrice = {};
      for (final row in (preciosResp as List)) {
        final pid = row['id_producto'] as int;
        if (!latestPrice.containsKey(pid)) {
          latestPrice[pid] = Map<String, dynamic>.from(row);
        }
      }

      final presentacionesResp = await _supabase
          .from('app_dat_producto_presentacion')
          .select('''
            id, id_producto, cantidad, es_base, precio_promedio,
            app_nom_presentacion!inner(id, denominacion)
          ''')
          .inFilter('id_producto', productoIds);

      final Map<int, List<Map<String, dynamic>>> pressByProduct = {};
      for (final p in (presentacionesResp as List)) {
        final pid = p['id_producto'] as int;
        pressByProduct.putIfAbsent(pid, () => []).add(
              Map<String, dynamic>.from(p),
            );
      }

      return data.map<ProductPriceItem>((item) {
        final pid = item['id'] as int;
        final last = latestPrice[pid];

        return ProductPriceItem(
          id: pid,
          name: item['denominacion'] ?? '',
          sku: item['sku'] ?? '',
          vendedorAppId: item['id_vendedor_app'],
          lastPrice: (last?['precio_venta_cup'] as num?)?.toDouble(),
          lastPriceUsd: (last?['precio_venta_usd'] as num?)?.toDouble(),
          lastPriceDate: last != null
              ? DateTime.tryParse(last['created_at'].toString())
              : null,
          presentaciones: pressByProduct[pid] ?? [],
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

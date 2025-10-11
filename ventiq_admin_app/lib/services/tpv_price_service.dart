import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tpv_price.dart';

/// Servicio para gestión de precios diferenciados por TPV
class TpvPriceService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Resuelve el precio de un producto para un TPV específico
  /// Jerarquía: TPV específico > Precio general > Precio base
  static Future<double> resolvePrice(int productId, int tpvId) async {
    try {
      print('🔍 Resolviendo precio para producto $productId en TPV $tpvId');

      // 1. Buscar precio específico del TPV
      final tpvPrice = await _getTpvSpecificPrice(productId, tpvId);
      if (tpvPrice != null) {
        print(
          '✅ Precio TPV específico encontrado: \$${tpvPrice.toStringAsFixed(2)}',
        );
        return tpvPrice;
      }

      // 2. Buscar precio general del producto
      final generalPrice = await _getGeneralPrice(productId);
      if (generalPrice != null) {
        print(
          '✅ Precio general encontrado: \$${generalPrice.toStringAsFixed(2)}',
        );
        return generalPrice;
      }

      // 3. Fallback al precio base del producto
      final basePrice = await _getBasePrice(productId);
      print('✅ Precio base usado: \$${basePrice.toStringAsFixed(2)}');
      return basePrice;
    } catch (e) {
      print('❌ Error resolviendo precio: $e');
      return 0.0;
    }
  }

  /// Obtiene precio específico del TPV (solo registros no eliminados)
  static Future<double?> _getTpvSpecificPrice(int productId, int tpvId) async {
    final today = DateTime.now().toIso8601String().split('T')[0];

    final response =
        await _supabase
            .from('app_dat_precio_tpv')
            .select('precio_venta_cup')
            .eq('id_producto', productId)
            .eq('id_tpv', tpvId)
            .eq('es_activo', true)
            .isFilter('deleted_at', null)
            .lte('fecha_desde', today)
            .or('fecha_hasta.is.null,fecha_hasta.gte.$today')
            .order('fecha_desde', ascending: false)
            .limit(1)
            .maybeSingle();

    return response?['precio_venta_cup']?.toDouble();
  }

  /// Obtiene precio general del producto
  static Future<double?> _getGeneralPrice(int productId) async {
    final today = DateTime.now().toIso8601String().split('T')[0];

    final response =
        await _supabase
            .from('app_dat_precio_venta')
            .select('precio_venta_cup')
            .eq('id_producto', productId)
            .eq('es_activo', true)
            .lte('fecha_desde', today)
            .or('fecha_hasta.is.null,fecha_hasta.gte.$today')
            .order('fecha_desde', ascending: false)
            .limit(1)
            .maybeSingle();

    return response?['precio_venta_cup']?.toDouble();
  }

  /// Obtiene precio base del producto
  static Future<double> _getBasePrice(int productId) async {
    final response =
        await _supabase
            .from('app_dat_producto')
            .select('precio_venta')
            .eq('id', productId)
            .single();

    return (response['precio_venta'] ?? 0.0).toDouble();
  }

  /// Crea un nuevo precio específico para TPV
  static Future<TpvPrice?> createTpvPrice({
    required int productId,
    required int tpvId,
    required double price,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
  }) async {
    try {
      print(
        '💰 Creando precio TPV: Producto $productId, TPV $tpvId, Precio \$${price.toStringAsFixed(2)}',
      );

      final data = {
        'id_producto': productId,
        'id_tpv': tpvId,
        'precio_venta_cup': price,
        'fecha_desde':
            (fechaDesde ?? DateTime.now()).toIso8601String().split('T')[0],
        'fecha_hasta': fechaHasta?.toIso8601String().split('T')[0],
        'es_activo': true,
      };

      final response =
          await _supabase
              .from('app_dat_precio_tpv')
              .insert(data)
              .select()
              .single();

      print('✅ Precio TPV creado exitosamente con ID: ${response['id']}');
      return TpvPrice.fromJson(response);
    } catch (e) {
      print('❌ Error creando precio TPV: $e');
      return null;
    }
  }

  /// Obtiene un precio específico por ID
  static Future<TpvPrice?> getTpvPriceById(int priceId) async {
    try {
      final response =
          await _supabase
              .from('app_dat_precio_tpv')
              .select('''
            *,
            app_dat_producto!inner(denominacion, sku),
            app_dat_tpv!inner(
              denominacion,
              app_dat_tienda!inner(denominacion)
            )
          ''')
              .eq('id', priceId)
              .single();

      // Mapear campos relacionados
      final mappedData = Map<String, dynamic>.from(response);
      mappedData['producto_nombre'] =
          response['app_dat_producto']['denominacion'];
      mappedData['producto_sku'] = response['app_dat_producto']['sku'];
      mappedData['tpv_nombre'] = response['app_dat_tpv']['denominacion'];
      mappedData['tienda_nombre'] =
          response['app_dat_tpv']['app_dat_tienda']['denominacion'];

      return TpvPrice.fromJson(mappedData);
    } catch (e) {
      print('❌ Error obteniendo precio TPV por ID: $e');
      return null;
    }
  }

  /// Actualiza un precio existente
  static Future<bool> updateTpvPrice({
    required int priceId,
    required double price,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
    bool? esActivo,
  }) async {
    try {
      print('🔄 Actualizando precio TPV ID: $priceId');

      final data = <String, dynamic>{
        'precio_venta_cup': price,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (fechaDesde != null) {
        data['fecha_desde'] = fechaDesde.toIso8601String().split('T')[0];
      }
      if (fechaHasta != null) {
        data['fecha_hasta'] = fechaHasta.toIso8601String().split('T')[0];
      }
      if (esActivo != null) {
        data['es_activo'] = esActivo;
      }

      await _supabase
          .from('app_dat_precio_tpv')
          .update(data)
          .eq('id', priceId)
          .isFilter('deleted_at', null);

      print('✅ Precio TPV actualizado exitosamente');
      return true;
    } catch (e) {
      print('❌ Error actualizando precio TPV: $e');
      return false;
    }
  }

  /// Elimina un precio (soft delete)
  static Future<bool> deleteTpvPrice(int priceId) async {
    try {
      print('🗑️ Eliminando precio TPV ID: $priceId (soft delete)');

      await _supabase
          .from('app_dat_precio_tpv')
          .update({
            'deleted_at': DateTime.now().toIso8601String(),
            'es_activo': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', priceId)
          .isFilter('deleted_at', null);

      print('✅ Precio TPV eliminado exitosamente');
      return true;
    } catch (e) {
      print('❌ Error eliminando precio TPV: $e');
      return false;
    }
  }

  /// Restaura un precio eliminado
  static Future<bool> restoreTpvPrice(int priceId) async {
    try {
      print('♻️ Restaurando precio TPV ID: $priceId');

      await _supabase
          .from('app_dat_precio_tpv')
          .update({
            'deleted_at': null,
            'es_activo': true,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', priceId)
          .not('deleted_at', 'is', null);

      print('✅ Precio TPV restaurado exitosamente');
      return true;
    } catch (e) {
      print('❌ Error restaurando precio TPV: $e');
      return false;
    }
  }

  /// Obtiene todos los precios de un producto
  static Future<List<TpvPrice>> getProductPrices(
    int productId, {
    bool includeDeleted = false,
  }) async {
    try {
      print(
        '🔍 Obteniendo precios para producto $productId (incluir eliminados: $includeDeleted)',
      );

      var query = _supabase
          .from('app_dat_precio_tpv')
          .select('''
            *,
            app_dat_tpv!inner(
              denominacion,
              app_dat_tienda!inner(denominacion)
            )
          ''')
          .eq('id_producto', productId);

      if (!includeDeleted) {
        query = query.isFilter('deleted_at', null);
      }

      final response = await query.order('fecha_desde', ascending: false);

      return response.map<TpvPrice>((item) {
        final mappedData = Map<String, dynamic>.from(item);
        mappedData['tpv_nombre'] = item['app_dat_tpv']['denominacion'];
        mappedData['tienda_nombre'] =
            item['app_dat_tpv']['app_dat_tienda']['denominacion'];
        return TpvPrice.fromJson(mappedData);
      }).toList();
    } catch (e) {
      print('❌ Error obteniendo precios del producto: $e');
      return [];
    }
  }

  /// Obtiene precios por TPV
  static Future<List<TpvPrice>> getTpvPrices(
    int tpvId, {
    bool includeDeleted = false,
    bool activeOnly = true,
  }) async {
    try {
      print('🔍 Obteniendo precios para TPV $tpvId');

      var query = _supabase
          .from('app_dat_precio_tpv')
          .select('''
            *,
            app_dat_producto!inner(denominacion, sku),
            app_dat_tpv!inner(
              denominacion,
              app_dat_tienda!inner(denominacion)
            )
          ''')
          .eq('id_tpv', tpvId);

      if (!includeDeleted) {
        query = query.isFilter('deleted_at', null);
      }

      if (activeOnly) {
        query = query.eq('es_activo', true);
      }

      final response = await query.order('fecha_desde', ascending: false);

      return response.map<TpvPrice>((item) {
        final mappedData = Map<String, dynamic>.from(item);
        mappedData['producto_nombre'] =
            item['app_dat_producto']['denominacion'];
        mappedData['producto_sku'] = item['app_dat_producto']['sku'];
        mappedData['tpv_nombre'] = item['app_dat_tpv']['denominacion'];
        mappedData['tienda_nombre'] =
            item['app_dat_tpv']['app_dat_tienda']['denominacion'];
        return TpvPrice.fromJson(mappedData);
      }).toList();
    } catch (e) {
      print('❌ Error obteniendo precios del TPV: $e');
      return [];
    }
  }

  /// Obtiene TPVs disponibles para configurar precios
  static Future<List<Map<String, dynamic>>> getAvailableTpvs(
    int? tiendaId,
  ) async {
    try {
      var query = _supabase.from('app_dat_tpv').select('''
      id,
      denominacion,
      app_dat_tienda!inner(
        id,
        denominacion
      )
    ''');

      if (tiendaId != null) {
        query = query.eq('id_tienda', tiendaId);
      }

      final response = await query.order('denominacion');

      return response
          .map<Map<String, dynamic>>(
            (tpv) => {
              'id': tpv['id'],
              'denominacion': tpv['denominacion'],
              'tienda_id': tpv['app_dat_tienda']['id'],
              'tienda_nombre': tpv['app_dat_tienda']['denominacion'],
            },
          )
          .toList();
    } catch (e) {
      print('❌ Error obteniendo TPVs: $e');
      return [];
    }
  }

  /// Importa precios masivamente
  static Future<Map<String, dynamic>> importTpvPrices(
    List<TpvPriceImportData> pricesData,
  ) async {
    try {
      print('📥 Importando ${pricesData.length} precios diferenciados');

      int successCount = 0;
      int errorCount = 0;
      final errors = <String>[];

      for (final priceData in pricesData) {
        try {
          final result = await createTpvPrice(
            productId: priceData.idProducto,
            tpvId: priceData.idTpv,
            price: priceData.precioVentaCup,
            fechaDesde: priceData.fechaDesde,
            fechaHasta: priceData.fechaHasta,
          );

          if (result != null) {
            successCount++;
          } else {
            errorCount++;
            errors.add(
              'Producto ${priceData.idProducto}, TPV ${priceData.idTpv}: Error desconocido',
            );
          }
        } catch (e) {
          errorCount++;
          errors.add(
            'Producto ${priceData.idProducto}, TPV ${priceData.idTpv}: $e',
          );
        }
      }

      return {
        'success': true,
        'total': pricesData.length,
        'success_count': successCount,
        'error_count': errorCount,
        'errors': errors,
      };
    } catch (e) {
      print('❌ Error en importación masiva: $e');
      return {'success': false, 'message': 'Error en importación masiva: $e'};
    }
  }

  /// Obtiene histórico de precios eliminados para auditoría
  static Future<List<TpvPrice>> getDeletedPrices({
    int? productId,
    int? tpvId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      print('📋 Obteniendo histórico de precios eliminados');

      var query = _supabase
          .from('app_dat_precio_tpv')
          .select('''
            *,
            app_dat_producto!inner(denominacion, sku),
            app_dat_tpv!inner(
              denominacion,
              app_dat_tienda!inner(denominacion)
            )
          ''')
          .not('deleted_at', 'is', null);

      if (productId != null) {
        query = query.eq('id_producto', productId);
      }
      if (tpvId != null) {
        query = query.eq('id_tpv', tpvId);
      }
      if (fromDate != null) {
        query = query.gte('deleted_at', fromDate.toIso8601String());
      }
      if (toDate != null) {
        query = query.lte('deleted_at', toDate.toIso8601String());
      }

      final response = await query.order('deleted_at', ascending: false);

      return response.map<TpvPrice>((item) {
        final mappedData = Map<String, dynamic>.from(item);
        mappedData['producto_nombre'] =
            item['app_dat_producto']['denominacion'];
        mappedData['producto_sku'] = item['app_dat_producto']['sku'];
        mappedData['tpv_nombre'] = item['app_dat_tpv']['denominacion'];
        mappedData['tienda_nombre'] =
            item['app_dat_tpv']['app_dat_tienda']['denominacion'];
        return TpvPrice.fromJson(mappedData);
      }).toList();
    } catch (e) {
      print('❌ Error obteniendo precios eliminados: $e');
      return [];
    }
  }

  /// Verifica si existe un precio específico para producto-TPV
  static Future<bool> existsPriceForProductTpv(int productId, int tpvId) async {
    try {
      final response = await _supabase
          .from('app_dat_precio_tpv')
          .select('id')
          .eq('id_producto', productId)
          .eq('id_tpv', tpvId)
          .eq('es_activo', true)
          .isFilter('deleted_at', null)
          .limit(1);

      return response.isNotEmpty;
    } catch (e) {
      print('❌ Error verificando existencia de precio: $e');
      return false;
    }
  }

  /// Obtiene estadísticas de precios diferenciados
  static Future<Map<String, dynamic>> getPriceStatistics() async {
    try {
      print('📊 Obteniendo estadísticas de precios diferenciados');

      // Total de precios activos
      final activePrices = await _supabase
          .from('app_dat_precio_tpv')
          .select('id')
          .eq('es_activo', true)
          .isFilter('deleted_at', null)
          .count(CountOption.exact);

      // Total de precios eliminados
      final deletedPrices = await _supabase
          .from('app_dat_precio_tpv')
          .select('id')
          .not('deleted_at', 'is', null)
          .count(CountOption.exact);

      // TPVs con precios específicos
      final tpvsWithPrices = await _supabase
          .from('app_dat_precio_tpv')
          .select('id_tpv')
          .eq('es_activo', true)
          .isFilter('deleted_at', null);

      final uniqueTpvs =
          tpvsWithPrices.map((item) => item['id_tpv']).toSet().length;

      // Productos con precios específicos
      final productsWithPrices = await _supabase
          .from('app_dat_precio_tpv')
          .select('id_producto')
          .eq('es_activo', true)
          .isFilter('deleted_at', null);

      final uniqueProducts =
          productsWithPrices.map((item) => item['id_producto']).toSet().length;

      return {
        'total_active_prices': activePrices.count ?? 0,
        'total_deleted_prices': deletedPrices.count ?? 0,
        'tpvs_with_prices': uniqueTpvs,
        'products_with_prices': uniqueProducts,
      };
    } catch (e) {
      print('❌ Error obteniendo estadísticas: $e');
      return {
        'total_active_prices': 0,
        'total_deleted_prices': 0,
        'tpvs_with_prices': 0,
        'products_with_prices': 0,
      };
    }
  }
}

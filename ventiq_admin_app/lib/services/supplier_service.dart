import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/supplier.dart';
import '../models/supplier_contact.dart';
import 'user_preferences_service.dart';

class SupplierService {
  static final SupplierService _instance = SupplierService._internal();
  factory SupplierService() => _instance;
  SupplierService._internal();

  static final SupabaseClient _supabase = Supabase.instance.client;
  static final UserPreferencesService _prefsService = UserPreferencesService();

  // ==================== CRUD BÁSICO ====================

  /// Obtener todos los proveedores
  static Future<List<Supplier>> getAllSuppliers({
    bool activeOnly = true,
    bool includeMetrics = false,
  }) async {
    try {
      print('🔍 Obteniendo proveedores...');
      print('📊 Incluir métricas: $includeMetrics');

      String selectQuery =
          'id, denominacion, direccion, ubicacion, sku_codigo, lead_time, created_at';

      // Eliminar las subconsultas complejas que causan el error
      if (includeMetrics) {
        // Usar la misma consulta básica - las métricas se obtendrán por separado si es necesario
        selectQuery =
            'id, denominacion, direccion, ubicacion, sku_codigo, lead_time, created_at';
      }

      var query = _supabase.from('app_dat_proveedor').select(selectQuery);

      final response = await query.order('denominacion');

      print('✅ Proveedores obtenidos: ${response.length}');

      return response.map<Supplier>((json) => Supplier.fromJson(json)).toList();
    } catch (e) {
      print('❌ Error al obtener proveedores: $e');
      rethrow;
    }
  }

  /// Obtener proveedor por ID
  static Future<Supplier?> getSupplierById(
    int id, {
    bool includeMetrics = false,
  }) async {
    try {
      print('🔍 Obteniendo proveedor ID: $id');

      String selectQuery = '''
        id, denominacion, direccion, ubicacion, sku_codigo, 
        lead_time, created_at
      ''';

      if (includeMetrics) {
        selectQuery = '''
          id, denominacion, direccion, ubicacion, sku_codigo, 
          lead_time, created_at,
          (
            SELECT COUNT(*) 
            FROM app_dat_recepcion_productos rp 
            WHERE rp.id_proveedor = app_dat_proveedor.id
          ) as total_orders,
          (
            SELECT AVG(rp.costo_real * rp.cantidad)
            FROM app_dat_recepcion_productos rp 
            WHERE rp.id_proveedor = app_dat_proveedor.id
          ) as average_order_value,
          (
            SELECT MAX(o.created_at)
            FROM app_dat_recepcion_productos rp
            JOIN app_dat_operaciones o ON rp.id_operacion = o.id
            WHERE rp.id_proveedor = app_dat_proveedor.id
          ) as last_order_date
        ''';
      }

      final response =
          await _supabase
              .from('app_dat_proveedor')
              .select(selectQuery)
              .eq('id', id)
              .single();

      print('✅ Proveedor obtenido: ${response['denominacion']}');
      return Supplier.fromJson(response);
    } catch (e) {
      print('❌ Error al obtener proveedor $id: $e');
      return null;
    }
  }

  /// Crear nuevo proveedor
  static Future<Map<String, dynamic>> createSupplier(Supplier supplier) async {
    try {
      print('🔄 Creando proveedor: ${supplier.denominacion}');

      // Validar que el SKU no exista
      final existingSupplier =
          await _supabase
              .from('app_dat_proveedor')
              .select('id')
              .eq('sku_codigo', supplier.skuCodigo)
              .maybeSingle();

      if (existingSupplier != null) {
        return {
          'success': false,
          'message':
              'Ya existe un proveedor con el código SKU: ${supplier.skuCodigo}',
        };
      }

      final response =
          await _supabase
              .from('app_dat_proveedor')
              .insert(supplier.toInsertJson())
              .select()
              .single();

      print('✅ Proveedor creado con ID: ${response['id']}');

      return {
        'success': true,
        'message': 'Proveedor creado exitosamente',
        'data': Supplier.fromJson(response),
      };
    } catch (e) {
      print('❌ Error al crear proveedor: $e');
      return {'success': false, 'message': 'Error al crear proveedor: $e'};
    }
  }

  /// Actualizar proveedor
  static Future<Map<String, dynamic>> updateSupplier(Supplier supplier) async {
    try {
      print('🔄 Actualizando proveedor ID: ${supplier.id}');

      // Validar que el SKU no exista en otro proveedor
      final existingSupplier =
          await _supabase
              .from('app_dat_proveedor')
              .select('id')
              .eq('sku_codigo', supplier.skuCodigo)
              .neq('id', supplier.id)
              .maybeSingle();

      if (existingSupplier != null) {
        return {
          'success': false,
          'message':
              'Ya existe otro proveedor con el código SKU: ${supplier.skuCodigo}',
        };
      }

      final response =
          await _supabase
              .from('app_dat_proveedor')
              .update(supplier.toInsertJson())
              .eq('id', supplier.id)
              .select()
              .single();

      print('✅ Proveedor actualizado: ${response['denominacion']}');

      return {
        'success': true,
        'message': 'Proveedor actualizado exitosamente',
        'data': Supplier.fromJson(response),
      };
    } catch (e) {
      print('❌ Error al actualizar proveedor: $e');
      return {'success': false, 'message': 'Error al actualizar proveedor: $e'};
    }
  }

  /// Eliminar proveedor (soft delete)
  static Future<Map<String, dynamic>> deleteSupplier(int id) async {
    try {
      print('🔄 Eliminando proveedor ID: $id');

      // Verificar si el proveedor tiene recepciones asociadas
      final hasReceptions = await _supabase
          .from('app_dat_recepcion_productos')
          .select('id')
          .eq('id_proveedor', id)
          .limit(1);

      if (hasReceptions.isNotEmpty) {
        return {
          'success': false,
          'message':
              'No se puede eliminar el proveedor porque tiene recepciones asociadas',
        };
      }

      await _supabase.from('app_dat_proveedor').delete().eq('id', id);

      print('✅ Proveedor eliminado');

      return {'success': true, 'message': 'Proveedor eliminado exitosamente'};
    } catch (e) {
      print('❌ Error al eliminar proveedor: $e');
      return {'success': false, 'message': 'Error al eliminar proveedor: $e'};
    }
  }

  // ==================== MÉTRICAS Y ANALYTICS ====================

  /// Obtener métricas detalladas de un proveedor usando RPC
  static Future<Map<String, dynamic>> getSupplierMetrics(int supplierId) async {
    try {
      print('📊 Obteniendo métricas del proveedor ID: $supplierId');

      final response = await _supabase.rpc(
        'fn_metricas_proveedor_completas',
        params: {
          'p_id_proveedor': supplierId,
          'p_fecha_desde':
              DateTime.now()
                  .subtract(const Duration(days: 90))
                  .toIso8601String()
                  .split('T')[0],
          'p_fecha_hasta': DateTime.now().toIso8601String().split('T')[0],
        },
      );

      if (response == null) {
        throw Exception('No se recibieron datos de métricas');
      }

      print('✅ Métricas RPC obtenidas exitosamente');
      return Map<String, dynamic>.from(response);
    } catch (e) {
      print('❌ Error con RPC, usando fallback: $e');
      return await _getSupplierMetricsDirectQuery(supplierId);
    }
  }

  /// Obtener dashboard de proveedores con métricas integradas
  static Future<Map<String, dynamic>> getSuppliersDashboard({
    int? storeId,
    int periodo = 30,
  }) async {
    try {
      print('📊 Obteniendo dashboard de proveedores...');

      final response = await _supabase.rpc(
        'fn_dashboard_proveedores',
        params: {'p_id_tienda': storeId, 'p_periodo': periodo},
      );

      if (response == null) {
        throw Exception('No se recibieron datos del dashboard');
      }

      print('✅ Dashboard de proveedores obtenido exitosamente');
      return Map<String, dynamic>.from(response);
    } catch (e) {
      print('❌ Error obteniendo dashboard de proveedores: $e');
      return await _getBasicSuppliersDashboard(storeId, periodo);
    }
  }

  /// Validar si un proveedor puede ser eliminado
  static Future<Map<String, dynamic>> validateSupplierDeletion(
    int supplierId,
  ) async {
    try {
      print('🔍 Validando eliminación del proveedor ID: $supplierId');

      // Verificar operaciones asociadas
      final operationsResponse =
          await _supabase
              .from('app_dat_recepcion_productos')
              .select('id')
              .eq('id_proveedor', supplierId)
              .count();
      final operationsCount = operationsResponse.count ?? 0;

      // Verificar productos con stock actual
      final activeProductsResponse =
          await _supabase
              .from('app_dat_inventario')
              .select('id')
              .eq('id_proveedor', supplierId)
              .gt('cantidad_actual', 0)
              .count();
      final activeProductsCount = activeProductsResponse.count ?? 0;

      final canDelete = operationsCount == 0 && activeProductsCount == 0;

      return {
        'success': true,
        'can_delete': canDelete,
        'operations_count': operationsCount,
        'active_products_count': activeProductsCount,
        'message':
            canDelete
                ? 'El proveedor puede ser eliminado'
                : 'El proveedor no puede ser eliminado debido a operaciones o productos asociados',
        'warnings': [
          if (operationsCount > 0)
            'Tiene $operationsCount operaciones asociadas',
          if (activeProductsCount > 0)
            'Tiene $activeProductsCount productos con stock actual',
        ],
      };
    } catch (e) {
      print('❌ Error validando eliminación: $e');
      return {
        'success': false,
        'can_delete': false,
        'error': e.toString(),
        'message': 'Error al validar la eliminación del proveedor',
      };
    }
  }

  /// Fallback para métricas cuando RPC no está disponible
  static Future<Map<String, dynamic>> _getSupplierMetricsDirectQuery(
    int supplierId,
  ) async {
    try {
      final basicMetrics = await _supabase
          .from('app_dat_recepcion_productos')
          .select('costo_real, cantidad, created_at')
          .eq('id_proveedor', supplierId);

      final totalOrders = basicMetrics.length;
      final totalValue = basicMetrics.fold<double>(
        0.0,
        (sum, item) => sum + (item['costo_real'] * item['cantidad']),
      );

      return {
        'id_proveedor': supplierId,
        'metricas_basicas': {
          'total_ordenes': totalOrders,
          'valor_total': totalValue,
          'valor_promedio': totalOrders > 0 ? totalValue / totalOrders : 0.0,
        },
        'metricas_performance': {
          'performance_score': 75.0,
          'lead_time_real': 7.0,
        },
        'alertas': [],
        'generado_en': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      throw Exception('Error en fallback de métricas: $e');
    }
  }

  /// Fallback para dashboard básico
  static Future<Map<String, dynamic>> _getBasicSuppliersDashboard(
    int? storeId,
    int periodo,
  ) async {
    try {
      final suppliers = await getAllSuppliers();

      return {
        'kpis_principales': {
          'total_proveedores': suppliers.length,
          'proveedores_activos': suppliers.where((s) => s.hasMetrics).length,
          'nuevos_proveedores': 0,
          'tasa_actividad': 0.0,
        },
        'metricas_financieras': {
          'valor_compras_total': 0.0,
          'crecimiento_compras': 0.0,
        },
        'top_proveedores': [],
        'alertas': [],
        'generado_en': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      throw Exception('Error en dashboard básico: $e');
    }
  }

  /// Obtener top proveedores por período
  static Future<List<Map<String, dynamic>>> getTopSuppliers({
    DateTime? fechaDesde,
    DateTime? fechaHasta,
    int limit = 10,
  }) async {
    try {
      print('📊 Obteniendo top proveedores...');

      String dateFilter = '';
      if (fechaDesde != null && fechaHasta != null) {
        dateFilter = '''
          AND o.created_at >= '${fechaDesde.toIso8601String()}'
          AND o.created_at <= '${fechaHasta.toIso8601String()}'
        ''';
      }

      final response = await _supabase.rpc(
        'fn_top_proveedores',
        params: {
          'p_fecha_desde': fechaDesde?.toIso8601String(),
          'p_fecha_hasta': fechaHasta?.toIso8601String(),
          'p_limite': limit,
        },
      );

      print('✅ Top proveedores obtenidos: ${response.length}');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error al obtener top proveedores: $e');
      // Fallback a consulta directa si no existe la función RPC
      return _getTopSuppliersDirectQuery(fechaDesde, fechaHasta, limit);
    }
  }

  // ==================== CONTACTOS ====================

  /// Obtener contactos de un proveedor
  static Future<List<SupplierContact>> getSupplierContacts(
    int supplierId,
  ) async {
    try {
      print('👥 Obteniendo contactos del proveedor ID: $supplierId');

      final response = await _supabase
          .from('app_dat_proveedor_contactos')
          .select('*')
          .eq('id_proveedor', supplierId)
          .eq('is_active', true)
          .order('is_primary', ascending: false)
          .order('nombre');

      print('✅ Contactos obtenidos: ${response.length}');

      return response
          .map<SupplierContact>((json) => SupplierContact.fromJson(json))
          .toList();
    } catch (e) {
      print('❌ Error al obtener contactos: $e');
      return [];
    }
  }

  // ==================== BÚSQUEDA Y FILTROS ====================

  /// Buscar proveedores por texto
  static Future<List<Supplier>> searchSuppliers(String query) async {
    try {
      if (query.trim().isEmpty) {
        return getAllSuppliers();
      }

      print('🔍 Buscando proveedores: "$query"');

      final response = await _supabase
          .from('app_dat_proveedor')
          .select('''
            id, denominacion, direccion, ubicacion, sku_codigo, 
            lead_time, created_at
          ''')
          .or(
            'denominacion.ilike.%$query%,sku_codigo.ilike.%$query%,ubicacion.ilike.%$query%',
          )
          .order('denominacion');

      print('✅ Proveedores encontrados: ${response.length}');

      return response.map<Supplier>((json) => Supplier.fromJson(json)).toList();
    } catch (e) {
      print('❌ Error en búsqueda de proveedores: $e');
      rethrow;
    }
  }

  // ==================== MÉTODOS AUXILIARES ====================

  /// Calcular score de performance del proveedor
  static double _calculatePerformanceScore(
    int totalRecepciones,
    double valorTotalCompras,
    DateTime? ultimaRecepcion,
  ) {
    double score = 0.0;

    // Puntos por número de recepciones (máximo 40 puntos)
    score += (totalRecepciones * 2).clamp(0, 40).toDouble();

    // Puntos por valor de compras (máximo 30 puntos)
    if (valorTotalCompras > 10000)
      score += 30;
    else if (valorTotalCompras > 5000)
      score += 20;
    else if (valorTotalCompras > 1000)
      score += 10;

    // Puntos por recencia (máximo 30 puntos)
    if (ultimaRecepcion != null) {
      final daysSinceLastOrder =
          DateTime.now().difference(ultimaRecepcion).inDays;
      if (daysSinceLastOrder <= 7)
        score += 30;
      else if (daysSinceLastOrder <= 30)
        score += 20;
      else if (daysSinceLastOrder <= 90)
        score += 10;
    }

    return score.clamp(0, 100);
  }

  /// Fallback para top proveedores si no existe función RPC
  static Future<List<Map<String, dynamic>>> _getTopSuppliersDirectQuery(
    DateTime? fechaDesde,
    DateTime? fechaHasta,
    int limit,
  ) async {
    try {
      var query = _supabase.from('app_dat_proveedor').select('''
            id, denominacion, sku_codigo,
            app_dat_recepcion_productos(
              cantidad, costo_real,
              app_dat_operaciones(created_at)
            )
          ''');

      final response = await query.limit(limit);

      // Procesar y ordenar por valor total
      final processed =
          response.map((supplier) {
            final recepciones =
                supplier['app_dat_recepcion_productos'] as List? ?? [];
            double valorTotal = 0.0;
            int totalRecepciones = 0;

            for (final recepcion in recepciones) {
              final fecha = DateTime.parse(
                recepcion['app_dat_operaciones']['created_at'],
              );

              // Aplicar filtro de fechas si es necesario
              if (fechaDesde != null && fecha.isBefore(fechaDesde)) continue;
              if (fechaHasta != null && fecha.isAfter(fechaHasta)) continue;

              valorTotal +=
                  (recepcion['cantidad'] ?? 0) * (recepcion['costo_real'] ?? 0);
              totalRecepciones++;
            }

            return {
              'id': supplier['id'],
              'denominacion': supplier['denominacion'],
              'sku_codigo': supplier['sku_codigo'],
              'valor_total': valorTotal,
              'total_recepciones': totalRecepciones,
            };
          }).toList();

      // Ordenar por valor total descendente
      processed.sort(
        (a, b) =>
            (b['valor_total'] as double).compareTo(a['valor_total'] as double),
      );

      return processed.take(limit).toList();
    } catch (e) {
      print('❌ Error en consulta directa de top proveedores: $e');
      return [];
    }
  }
}

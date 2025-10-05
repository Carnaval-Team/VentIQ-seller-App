// ==================== MÉTODOS ACTUALIZADOS PARA SUPPLIER SERVICE ====================

/// Obtener métricas detalladas de un proveedor usando RPC
static Future<Map<String, dynamic>> getSupplierMetrics(int supplierId) async {
  try {
    print('📊 Obteniendo métricas del proveedor ID: $supplierId');

    final response = await _supabase.rpc('fn_metricas_proveedor_completas', params: {
      'p_id_proveedor': supplierId,
      'p_fecha_desde': DateTime.now().subtract(const Duration(days: 90)).toIso8601String().split('T')[0],
      'p_fecha_hasta': DateTime.now().toIso8601String().split('T')[0],
    });

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

    final response = await _supabase.rpc('fn_dashboard_proveedores', params: {
      'p_id_tienda': storeId,
      'p_periodo': periodo,
    });

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
static Future<Map<String, dynamic>> validateSupplierDeletion(int supplierId) async {
  try {
    print('🔍 Validando eliminación del proveedor ID: $supplierId');

    // Verificar operaciones asociadas
    final operationsCount = await _supabase
        .from('app_dat_recepcion_productos')
        .select('id')
        .eq('id_proveedor', supplierId)
        .count();

    // Verificar productos con stock actual
    final activeProductsCount = await _supabase
        .from('app_dat_inventario')
        .select('id')
        .eq('id_proveedor', supplierId)
        .gt('cantidad_actual', 0)
        .count();

    final canDelete = operationsCount == 0 && activeProductsCount == 0;
    
    return {
      'success': true,
      'can_delete': canDelete,
      'operations_count': operationsCount,
      'active_products_count': activeProductsCount,
      'message': canDelete 
          ? 'El proveedor puede ser eliminado'
          : 'El proveedor no puede ser eliminado debido a operaciones o productos asociados',
      'warnings': [
        if (operationsCount > 0) 'Tiene $operationsCount operaciones asociadas',
        if (activeProductsCount > 0) 'Tiene $activeProductsCount productos con stock actual',
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
static Future<Map<String, dynamic>> _getSupplierMetricsDirectQuery(int supplierId) async {
  try {
    final basicMetrics = await _supabase
        .from('app_dat_recepcion_productos')
        .select('costo_real, cantidad, created_at')
        .eq('id_proveedor', supplierId);

    final totalOrders = basicMetrics.length;
    final totalValue = basicMetrics.fold<double>(
      0.0, 
      (sum, item) => sum + (item['costo_real'] * item['cantidad'])
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
static Future<Map<String, dynamic>> _getBasicSuppliersDashboard(int? storeId, int periodo) async {
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

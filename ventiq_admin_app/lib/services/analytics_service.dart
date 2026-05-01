import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/analytics/inventory_metrics.dart';
import 'user_preferences_service.dart';

// Clases auxiliares para analytics
class ProductMovementMetric {
  final int productId;
  final String productName;
  final String category;
  final double totalMovement;
  final double averageMovement;
  final int transactionCount;
  final double rotationRate;
  final DateTime lastMovement;
  final String movementTrend;

  ProductMovementMetric({
    required this.productId,
    required this.productName,
    required this.category,
    required this.totalMovement,
    required this.averageMovement,
    required this.transactionCount,
    required this.rotationRate,
    required this.lastMovement,
    required this.movementTrend,
  });

  // ✅ Agregar getter calculado
  String get rotationLabel {
    if (rotationRate >= 6) return 'Alta';
    if (rotationRate >= 3) return 'Media';
    if (rotationRate >= 1) return 'Baja';
    return 'Muy Baja';
  }

  factory ProductMovementMetric.fromJson(Map<String, dynamic> json) {
    return ProductMovementMetric(
      productId: json['productId'] ?? json['product_id'] ?? 0,
      productName: json['productName'] ?? json['product_name'] ?? '',
      category: json['category'] ?? '',
      totalMovement:
          (json['totalMovement'] ?? json['total_movement'] ?? 0).toDouble(),
      averageMovement:
          (json['averageMovement'] ?? json['average_movement'] ?? 0).toDouble(),
      transactionCount:
          json['transactionCount'] ?? json['transaction_count'] ?? 0,
      rotationRate:
          (json['rotationRate'] ?? json['rotation_rate'] ?? 0).toDouble(),
      lastMovement:
          DateTime.tryParse(
            json['lastMovement'] ?? json['last_movement'] ?? '',
          ) ??
          DateTime.now(),
      movementTrend:
          json['movementTrend'] ?? json['movement_trend'] ?? 'stable',
    );
  }
}

class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  static final SupabaseClient _supabase = Supabase.instance.client;
  static final UserPreferencesService _prefsService = UserPreferencesService();

  // ==================== MÉTRICAS GENERALES DE INVENTARIO ====================

  /// Obtener métricas generales del inventario
  static Future<InventoryMetrics> getInventoryMetrics({
    int? storeId,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    try {
      print('📊 Obteniendo métricas de inventario...');

      final userStoreId = storeId ?? await _prefsService.getIdTienda();
      if (userStoreId == null) {
        print('⚠️ No se encontró ID de tienda');
        return InventoryMetrics(
          totalValue: 0,
          totalProducts: 0,
          lowStockProducts: 0,
          outOfStockProducts: 0,
          averageRotation: 0,
          monthlyMovement: 0,
          calculatedAt: DateTime.now(),
        );
      }

      final response = await _supabase.rpc(
        'fn_analytics_inventory_metrics',
        params: {'p_store_id': userStoreId},
      );

      // ✅ CALCULAR ROTACIÓN PROMEDIO REAL desde productos
      double averageRotation = 0.0;
      try {
        final products = await getProductMovements(
          storeId: userStoreId,
          limit: 100, // Obtener más productos para cálculo preciso
        );

        if (products.isNotEmpty) {
          final totalRotation = products.fold<double>(
            0.0,
            (sum, p) => sum + p.rotationRate,
          );
          averageRotation = totalRotation / products.length;
          print(
            '🔄 Rotación promedio calculada: ${averageRotation.toStringAsFixed(2)} (desde ${products.length} productos)',
          );
        } else {
          print('⚠️ No hay productos con movimiento, usando rotación 0');
          averageRotation = 0.0;
        }
      } catch (rotationError) {
        print('⚠️ Error calculando rotación: $rotationError');
        print('   Usando rotación fallback: 0.0');
        averageRotation = 0.0; // Fallback más conservador
      }

      print(response);
      print('✅ Métricas obtenidas exitosamente');
      return _mapProductsAnalysisToInventoryMetrics(response, averageRotation);
    } catch (e) {
      print('❌ Error al obtener métricas de inventario: $e');
      // Fallback con datos básicos
      return _getBasicInventoryMetrics(storeId);
    }
  }

  /// Mapear respuesta de productos analysis a InventoryMetrics
  static InventoryMetrics _mapProductsAnalysisToInventoryMetrics(
    Map<String, dynamic> response,
    double averageRotation, // ✅ Rotación calculada desde productos
  ) {
    print('🗐️ Mapeando respuesta a InventoryMetrics...');
    print('  Response keys: ${response.keys}');

    // Soporte para AMBOS formatos:
    // 1) fn_analytics_inventory_metrics → claves planas en camelCase
    // 2) get_inventario_analisis_tienda_json → metricas_principales / detalles_adicionales
    final hasFlatFormat = response.containsKey('totalProducts') ||
        response.containsKey('totalValue');

    int totalProducts;
    int lowStock;
    int outOfStock;
    double totalValue;
    double monthlyMovement;
    double? rotationFromRpc;
    double? valueChangePercent;

    if (hasFlatFormat) {
      totalProducts = (response['totalProducts'] ?? 0) is int
          ? response['totalProducts'] ?? 0
          : (response['totalProducts'] as num).toInt();
      lowStock = (response['lowStockProducts'] ?? 0) is int
          ? response['lowStockProducts'] ?? 0
          : (response['lowStockProducts'] as num).toInt();
      outOfStock = (response['outOfStockProducts'] ?? 0) is int
          ? response['outOfStockProducts'] ?? 0
          : (response['outOfStockProducts'] as num).toInt();
      totalValue = (response['totalValue'] ?? 0).toDouble();
      monthlyMovement = (response['monthlyMovement'] ?? 0).toDouble();
      rotationFromRpc = (response['averageRotation'] ?? 0).toDouble();
      valueChangePercent = (response['valueChangePercent'] ?? 0).toDouble();
    } else {
      final metricas = response['metricas_principales'] ?? {};
      final detalles = response['detalles_adicionales'] ?? {};
      totalProducts = metricas['total_productos'] ?? 0;
      lowStock = metricas['stock_bajo'] ?? 0;
      outOfStock = detalles['productos_sin_stock'] ?? 0;
      totalValue = (metricas['valor_inventario'] ?? 0.0).toDouble();
      monthlyMovement = (metricas['productos_con_stock'] ?? 0) * 0.25;
    }

    // Si la rotación calculada desde productos es > 0, úsala; si no, fallback
    // a la del RPC (cuando exista).
    final finalRotation = averageRotation > 0
        ? averageRotation
        : (rotationFromRpc ?? 0.0);

    print('📊 Valores extraídos:');
    print('  totalProducts: $totalProducts');
    print('  totalValue: $totalValue');
    print('  lowStockProducts: $lowStock');
    print('  outOfStockProducts: $outOfStock');
    print('  monthlyMovement: $monthlyMovement');
    print('  averageRotation (final): $finalRotation');

    return InventoryMetrics(
      totalValue: totalValue,
      totalProducts: totalProducts,
      lowStockProducts: lowStock,
      outOfStockProducts: outOfStock,
      averageRotation: finalRotation,
      monthlyMovement: monthlyMovement,
      calculatedAt: DateTime.now(),
      valueChangePercent: valueChangePercent ?? 0.0,
    );
  }

  /// Obtener métricas básicas como fallback
  static Future<InventoryMetrics> _getBasicInventoryMetrics(
    int? storeId,
  ) async {
    try {
      final userStoreId = storeId ?? await _prefsService.getIdTienda();
      if (userStoreId == null) {
        print('⚠️ No se encontró ID de tienda');
        return InventoryMetrics(
          totalValue: 0,
          totalProducts: 0,
          lowStockProducts: 0,
          outOfStockProducts: 0,
          averageRotation: 0,
          monthlyMovement: 0,
          calculatedAt: DateTime.now(),
        );
      }
      // Consulta básica para obtener métricas esenciales
      final inventoryData = await _supabase
          .from('app_dat_inventario_productos')
          .select('''
  id_producto,
  COALESCE(cantidad_final, cantidad_inicial) as cantidad_disponible,
  app_dat_producto!inner(denominacion),
  app_dat_layout_almacen!inner(
    app_dat_almacen!inner(id_tienda)
  )
''')
          .eq('app_dat_layout_almacen.app_dat_almacen.id_tienda', userStoreId!);

      double totalValue = 0;
      int totalProducts = inventoryData.length;
      int lowStockProducts = 0;
      int outOfStockProducts = 0;

      for (final item in inventoryData) {
        final quantity = (item['cantidad_disponible'] ?? 0).toDouble();
        final price = (item['precio_unitario'] ?? 0).toDouble();

        totalValue += quantity * price;

        if (quantity == 0) {
          outOfStockProducts++;
        } else if (quantity < 10) {
          // Umbral básico
          lowStockProducts++;
        }
      }

      return InventoryMetrics(
        totalValue: totalValue,
        totalProducts: totalProducts,
        lowStockProducts: lowStockProducts,
        outOfStockProducts: outOfStockProducts,
        averageRotation: 0, // Requiere cálculo más complejo
        monthlyMovement: 0, // Requiere datos históricos
        calculatedAt: DateTime.now(),
      );
    } catch (e) {
      print('❌ Error en métricas básicas: $e');
      return InventoryMetrics(
        totalValue: 0,
        totalProducts: 0,
        lowStockProducts: 0,
        outOfStockProducts: 0,
        averageRotation: 0,
        monthlyMovement: 0,
        calculatedAt: DateTime.now(),
      );
    }
  }

  // ==================== MOVIMIENTOS DE PRODUCTOS ====================

  /// Obtener métricas de movimiento de productos
  static Future<List<ProductMovementMetric>> getProductMovements({
    int? storeId,
    DateTime? dateFrom,
    DateTime? dateTo,
    String orderBy = 'total_movement',
    int limit = 50,
  }) async {
    try {
      print('📈 Obteniendo movimientos de productos...');

      final userStoreId = storeId ?? await _prefsService.getIdTienda();

      final response = await _supabase.rpc(
        'fn_analytics_product_movements',
        params: {
          'p_store_id': userStoreId,
          'p_date_from': dateFrom?.toIso8601String(),
          'p_date_to': dateTo?.toIso8601String(),
          'p_order_by': orderBy,
          'p_limit': limit,
        },
      );

      final movements =
          response.map<ProductMovementMetric>((json) {
            final movement = ProductMovementMetric.fromJson(json);
            return movement;
          }).toList();

      print('📊 Total registros recibidos: ${movements.length}');

      // ✅ ELIMINAR DUPLICADOS por productId
      // Mantener solo el PRIMER registro de cada producto
      final uniqueMovements = <int, ProductMovementMetric>{};
      int duplicatesCount = 0;

      for (final movement in movements) {
        if (!uniqueMovements.containsKey(movement.productId)) {
          uniqueMovements[movement.productId] = movement;
        } else {
          duplicatesCount++;
        }
      }

      final result = uniqueMovements.values.toList();
      print('✅ Productos únicos: ${result.length}');
      print('🗑️ Duplicados eliminados: $duplicatesCount');

      // Mostrar resumen de productos
      if (result.isNotEmpty) {
        print('📊 Resumen de rotaciones:');
        for (final product in result.take(5)) {
          print(
            '  - ${product.productName}: ${product.rotationRate.toStringAsFixed(2)}',
          );
        }
        if (result.length > 5) {
          print('  ... y ${result.length - 5} productos más');
        }
      }

      return result;
    } catch (e) {
      print('❌ Error al obtener movimientos: $e');
      return [];
    }
  }

  /// Obtener productos con mayor rotación
  static Future<List<ProductMovementMetric>> getTopRotationProducts({
    int? storeId,
    int limit = 10,
  }) async {
    return getProductMovements(
      storeId: storeId,
      orderBy: 'rotation_rate',
      limit: limit,
    );
  }

  /// Obtener productos con menor rotación
  static Future<List<ProductMovementMetric>> getSlowMovingProducts({
    int? storeId,
    int limit = 10,
  }) async {
    return getProductMovements(
      storeId: storeId,
      orderBy: 'rotation_rate_asc',
      limit: limit,
    );
  }

  // ==================== ALERTAS DE STOCK ====================

  /// Obtener alertas activas de stock
  static Future<List<StockAlert>> getStockAlerts({
    int? storeId,
    List<String>? alertTypes,
    List<String>? severities,
    bool activeOnly = true,
  }) async {
    try {
      print('🚨 Obteniendo alertas de stock...');

      final userStoreId = storeId ?? await _prefsService.getIdTienda();

      final response = await _supabase.rpc(
        'fn_analytics_stock_alerts',
        params: {
          'p_store_id': userStoreId,
          'p_alert_types': alertTypes,
          'p_severities': severities,
          'p_active_only': activeOnly,
        },
      );
      print('🔍 Tipo: ${response.runtimeType}');
      print('🔍 Es Map?: ${response is Map}');
      if (response is Map) {
        print('🔍 Keys: ${response.keys}');
        print('🔍 Tiene alertas?: ${response.containsKey('alertas')}');
      }
      print('🔍 Tipo: ${response.runtimeType}');
      print('🔍 Es List?: ${response is List}');

      // El RPC devuelve una List con objetos StockAlert directamente
      if (response is List && response.isNotEmpty) {
        print('📊 Procesando ${response.length} alertas directas');

        // ⚠️ FILTRADO ADICIONAL DE SEGURIDAD
        // Filtrar primero por tienda en el response original
        final filteredResponse =
            response.where((alertData) {
              if (alertData.containsKey('storeId') ||
                  alertData.containsKey('store_id')) {
                final alertStoreId =
                    alertData['storeId'] ?? alertData['store_id'];
                return alertStoreId == userStoreId;
              }
              // Si no tiene storeId, asumir que es válida (fallback)
              return true;
            }).toList();

        print(
          '🔒 Alertas filtradas por tienda: ${filteredResponse.length} de ${response.length}',
        );

        final alerts =
            filteredResponse.map<StockAlert>((alertData) {
              print('🔄 Procesando: $alertData');

              // Los datos ya vienen en formato correcto
              final alertJson = <String, dynamic>{
                'product_id': alertData['productId'] ?? 0,
                'product_name':
                    alertData['productName'] ?? 'Producto Desconocido',
                'alert_type': alertData['alertType'] ?? 'unknown',
                'severity': alertData['severity'] ?? 'info',
                'current_stock': alertData['currentStock'] ?? 0,
                'min_stock': alertData['minStock'],
                'message': alertData['message'] ?? '',
                'created_at':
                    alertData['createdAt'] ?? DateTime.now().toIso8601String(),
                'is_active': true,
              };

              return StockAlert.fromJson(alertJson);
            }).toList();

        print('✅ Alertas procesadas: ${alerts.length}');
        return alerts;
      }

      print('⚠️ Usando fallback');
      return _getBasicStockAlerts(storeId);
    } catch (e) {
      print('❌ Error al obtener alertas: $e');
      // Fallback con alertas básicas
      return _getBasicStockAlerts(storeId);
    }
  }

  static Future<List<StockAlert>> _getBasicStockAlerts(int? storeId) async {
    try {
      final userStoreId = storeId ?? await _prefsService.getIdTienda();

      final inventoryData = await _supabase
          .from('app_dat_inventario_productos')
          .select('''
          id_producto,
          cantidad_final,
          app_dat_producto!inner(id_tienda, denominacion)
        ''')
          .eq('app_dat_producto.id_tienda', userStoreId!)
          .lte('cantidad_final', 10); // Solo productos con stock bajo

      print(
        '📦 Datos de inventario obtenidos: ${inventoryData.length} productos',
      );

      final alerts = <StockAlert>[];

      for (final item in inventoryData) {
        try {
          final quantity = (item['cantidad_final'] ?? 0).toDouble();
          final productId = item['id_producto'] ?? 0;

          // Manejo seguro del nombre del producto
          String productName = 'Producto Desconocido';
          if (item['app_dat_producto'] != null &&
              item['app_dat_producto'] is Map &&
              item['app_dat_producto']['denominacion'] != null) {
            productName = item['app_dat_producto']['denominacion'].toString();
          }

          print(
            '🏷️ Producto: $productName (ID: $productId, Stock: $quantity)',
          );

          if (quantity == 0) {
            alerts.add(
              StockAlert(
                productId: productId,
                productName: productName,
                alertType: 'out_of_stock',
                severity: 'critical',
                currentStock: quantity,
                minStock: 5.0,
                message: 'Producto sin stock disponible',
                createdAt: DateTime.now(),
                isActive: true,
              ),
            );
          } else if (quantity <= 5) {
            alerts.add(
              StockAlert(
                productId: productId,
                productName: productName,
                alertType: 'low_stock',
                severity: 'warning',
                currentStock: quantity,
                minStock: 5.0,
                message:
                    'Stock crítico: ${quantity.toInt()} unidades restantes',
                createdAt: DateTime.now(),
                isActive: true,
              ),
            );
          }
        } catch (itemError) {
          print('❌ Error procesando producto: $itemError');
          continue;
        }
      }

      print('🚨 Alertas generadas: ${alerts.length}');
      return alerts;
    } catch (e) {
      print('❌ Error en alertas básicas: $e');

      // Fallback con alertas de prueba
      return [
        StockAlert(
          productId: 1,
          productName: 'Producto de Prueba 1',
          alertType: 'out_of_stock',
          severity: 'critical',
          currentStock: 0,
          minStock: 5.0,
          message: 'Producto sin stock disponible',
          createdAt: DateTime.now(),
          isActive: true,
        ),
        StockAlert(
          productId: 2,
          productName: 'Producto de Prueba 2',
          alertType: 'low_stock',
          severity: 'warning',
          currentStock: 3,
          minStock: 5.0,
          message: 'Stock crítico: 3 unidades restantes',
          createdAt: DateTime.now(),
          isActive: true,
        ),
      ];
    }
  }

  /// Obtener alertas críticas
  static Future<List<StockAlert>> getCriticalAlerts({int? storeId}) async {
    return getStockAlerts(
      storeId: storeId,
      severities: ['critical'],
      activeOnly: true,
    );
  }

  // ==================== ANÁLISIS DE TENDENCIAS ====================

  /// Obtener tendencias de inventario por período
  static Future<Map<String, dynamic>> getInventoryTrends({
    int? storeId,
    String period = 'monthly', // 'daily', 'weekly', 'monthly'
    int periodCount = 6,
  }) async {
    try {
      print('📈 Obteniendo tendencias de inventario...');

      final userStoreId = storeId ?? await _prefsService.getIdTienda();

      final response = await _supabase.rpc(
        'fn_analytics_inventory_trends',
        params: {
          'p_store_id': userStoreId,
          'p_period': period,
          'p_period_count': periodCount,
        },
      );

      print('✅ Tendencias obtenidas');
      return response;
    } catch (e) {
      print('❌ Error al obtener tendencias: $e');
      return {'periods': [], 'values': [], 'movements': []};
    }
  }

  // ==================== ANÁLISIS DE CATEGORÍAS ====================

  /// Obtener análisis por categorías
  static Future<List<Map<String, dynamic>>> getCategoryAnalysis({
    int? storeId,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    try {
      print('📊 Obteniendo análisis por categorías...');

      final userStoreId = storeId ?? await _prefsService.getIdTienda();

      final response = await _supabase.rpc(
        'fn_analytics_category_analysis',
        params: {
          'p_store_id': userStoreId,
          'p_date_from': dateFrom?.toIso8601String(),
          'p_date_to': dateTo?.toIso8601String(),
        },
      );

      print('✅ Análisis de categorías obtenido: ${response.length}');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error en análisis de categorías: $e');
      return [];
    }
  }

  // ==================== REPORTES ESPECIALIZADOS ====================

  /// Generar reporte de rotación de inventario
  static Future<Map<String, dynamic>> generateRotationReport({
    int? storeId,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    try {
      print('📋 Generando reporte de rotación...');

      final userStoreId = storeId ?? await _prefsService.getIdTienda();

      final response = await _supabase.rpc(
        'fn_analytics_rotation_report',
        params: {
          'p_store_id': userStoreId,
          'p_date_from': dateFrom?.toIso8601String(),
          'p_date_to': dateTo?.toIso8601String(),
        },
      );

      print('✅ Reporte de rotación generado');
      return response;
    } catch (e) {
      print('❌ Error al generar reporte de rotación: $e');
      return {};
    }
  }

  /// Generar reporte de eficiencia operativa
  static Future<Map<String, dynamic>> generateEfficiencyReport({
    int? storeId,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    try {
      print('📋 Generando reporte de eficiencia...');

      final userStoreId = storeId ?? await _prefsService.getIdTienda();

      final response = await _supabase.rpc(
        'fn_analytics_efficiency_report',
        params: {
          'p_store_id': userStoreId,
          'p_date_from': dateFrom?.toIso8601String(),
          'p_date_to': dateTo?.toIso8601String(),
        },
      );

      print('✅ Reporte de eficiencia generado');
      return response;
    } catch (e) {
      print('❌ Error al generar reporte de eficiencia: $e');
      return {};
    }
  }

  // ==================== UTILIDADES ====================

  /// Limpiar caché de métricas
  static void clearMetricsCache() {
    print('🧹 Limpiando caché de métricas...');
    // Implementar lógica de caché si es necesario
  }

  /// Validar período de fechas
  static bool isValidDateRange(DateTime? from, DateTime? to) {
    if (from == null || to == null) return true;
    return from.isBefore(to) &&
        to.isBefore(DateTime.now().add(Duration(days: 1)));
  }

  // Métodos helper para mapear datos del RPC
  static String _mapTipoToAlertType(String tipo) {
    switch (tipo) {
      case 'stock_bajo':
        return 'low_stock';
      case 'sin_movimiento':
        return 'no_movement';
      case 'inventario_valor':
        return 'inventory_value';
      default:
        return 'unknown';
    }
  }

  static String _mapNivelToSeverity(String nivel) {
    switch (nivel) {
      case 'alta':
        return 'critical';
      case 'media':
        return 'warning';
      case 'baja':
        return 'info';
      default:
        return 'info';
    }
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'user_preferences_service.dart';

class DashboardService {
  static final DashboardService _instance = DashboardService._internal();
  factory DashboardService() => _instance;
  DashboardService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final UserPreferencesService _userPreferencesService = UserPreferencesService();

  /// Obtiene análisis completo de la tienda usando RPC obtener_analisis_tienda
  Future<Map<String, dynamic>?> getStoreAnalysis({
    required String periodo,
  }) async {
    try {
      // Obtener id_tienda del supervisor logueado
      final idTienda = await _userPreferencesService.getIdTienda();
      
      if (idTienda == null) {
        print('❌ No se encontró id_tienda del supervisor');
        return null;
      }

      print('🔍 Calling obtener_analisis_tienda RPC:');
      print('  - p_id_tienda: $idTienda');
      print('  - p_periodo: $periodo');

      // Llamar a la función RPC
      final response = await _supabase.rpc('obtener_analisis_tienda', params:{
        'p_id_tienda': idTienda,
        'p_periodo': periodo,
      });

      if (response == null) {
        print('❌ RPC response is null');
        return null;
      }

      print('✅ RPC obtener_analisis_tienda response:');
      print('📊 Raw response: $response');
      
      // Transformar respuesta a formato del dashboard
      final transformedData = _transformRpcResponseToDashboard(response, periodo);
      
      print('🔄 Transformed dashboard data:');
      transformedData.forEach((key, value) {
        print('  - $key: ${value.runtimeType}');
      });

      return transformedData;
    } catch (e) {
      print('❌ Error calling obtener_analisis_tienda: $e');
      print('❌ Error type: ${e.runtimeType}');
      return null;
    }
  }

  /// Obtiene análisis con período por defecto (1 mes)
  Future<Map<String, dynamic>?> getDefaultStoreAnalysis() async {
    return await getStoreAnalysis(periodo: '1 mes');
  }

  /// Valida que el supervisor tenga id_tienda configurado
  Future<bool> validateSupervisorStore() async {
    final idTienda = await _userPreferencesService.getIdTienda();
    final isValid = idTienda != null && idTienda > 0;
    
    print('🔐 Supervisor store validation:');
    print('  - ID Tienda: $idTienda');
    print('  - Is Valid: $isValid');
    
    return isValid;
  }

  /// Transforma la respuesta RPC al formato esperado por el dashboard
  Map<String, dynamic> _transformRpcResponseToDashboard(Map<String, dynamic> rpcResponse, String periodo) {
    try {
      // Extraer datos de la respuesta RPC
      final ventasTotales = rpcResponse['ventas_totales'] ?? 0;
      final ventasTotalesAnterior = rpcResponse['ventas_totales_anterior'] ?? 0;
      final totalProductos = rpcResponse['total_de_productos'] ?? 0;
      // totalProductosNoStock ya está incluido en estado_inventario como productos_sin_stock
      final totalOrdenes = rpcResponse['total_ordenes'] ?? 0;
      final totalGastos = rpcResponse['total_gastos'] ?? 0;
      final tendenciasVenta = rpcResponse['tendencias_de_venta'] as List<dynamic>? ?? [];
      final totalProdCategoria = rpcResponse['total_prod_categoria'] as List<dynamic>? ?? [];
      final estadoInventario = rpcResponse['estado_inventario'] as Map<String, dynamic>? ?? {};

      // Transformar tendencias de venta a FlSpot
      final salesData = _transformTendenciasToFlSpot(tendenciasVenta);

      // Transformar categorías para el gráfico de dona
      final categoryData = _transformCategoriesToChartData(totalProdCategoria);

      // Calcular porcentaje de cambio en ventas
      double salesChangePercentage = 0.0;
      if (ventasTotalesAnterior > 0) {
        salesChangePercentage = ((ventasTotales - ventasTotalesAnterior) / ventasTotalesAnterior) * 100;
      }

      // Estructura compatible con el dashboard actual
      return {
        // Métricas principales
        'totalSales': ventasTotales.toDouble(),
        'totalOrders': totalOrdenes,
        'totalProducts': totalProductos,
        'totalExpenses': totalGastos.toDouble(),
        
        // Cambios porcentuales
        'salesChange': salesChangePercentage,
        'ordersChange': 0.0, // No tenemos datos del período anterior para órdenes
        'productsChange': 0.0, // Los productos no cambian por período
        'expensesChange': 0.0, // No tenemos datos del período anterior para gastos
        
        // Estado del inventario
        'outOfStock': estadoInventario['productos_sin_stock'] ?? 0,
        'lowStock': estadoInventario['stock_bajo'] ?? 0,
        'okStock': estadoInventario['stock_ok'] ?? 0,
        
        // Datos para gráficos
        'salesData': salesData,
        'categoryData': categoryData,
        
        // Datos adicionales
        'period': periodo,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('❌ Error transforming RPC response: $e');
      return {};
    }
  }

  /// Transforma las tendencias de venta a formato FlSpot
  List<FlSpot> _transformTendenciasToFlSpot(List<dynamic> tendencias) {
    if (tendencias.isEmpty) return [];
    
    try {
      final spots = <FlSpot>[];
      for (int i = 0; i < tendencias.length; i++) {
        final item = tendencias[i] as Map<String, dynamic>;
        final value = (item['value'] ?? 0).toDouble();
        spots.add(FlSpot(i.toDouble(), value));
      }
      return spots;
    } catch (e) {
      print('❌ Error transforming tendencias to FlSpot: $e');
      return [];
    }
  }

  /// Transforma las categorías a formato PieChartSectionData
  List<PieChartSectionData> _transformCategoriesToChartData(List<dynamic> categorias) {
    if (categorias.isEmpty) {
      // Datos por defecto si no hay categorías
      return [
        PieChartSectionData(
          color: const Color(0xFF9E9E9E),
          value: 1,
          title: 'Sin datos\n1',
          radius: 50,
          titleStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        )
      ];
    }
    
    try {
      final colors = [
        const Color(0xFF4A90E2), // Azul VentIQ
        const Color(0xFF10B981), // Verde
        const Color(0xFFFF6B35), // Naranja
        const Color(0xFFE74C3C), // Rojo
        const Color(0xFF9B59B6), // Morado
        const Color(0xFFF39C12), // Amarillo
        const Color(0xFF1ABC9C), // Turquesa
        const Color(0xFF34495E), // Gris oscuro
      ];
      
      final chartData = <PieChartSectionData>[];
      for (int i = 0; i < categorias.length; i++) {
        final categoria = categorias[i] as Map<String, dynamic>;
        final name = categoria['name'] ?? 'Sin nombre';
        final value = (categoria['total_product'] ?? 0).toDouble();
        
        chartData.add(
          PieChartSectionData(
            color: colors[i % colors.length],
            value: value,
            title: '$name\n${value.toInt()}',
            radius: 50,
            titleStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        );
      }
      return chartData;
    } catch (e) {
      print('❌ Error transforming categorias to PieChartSectionData: $e');
      return [
        PieChartSectionData(
          color: const Color(0xFF9E9E9E),
          value: 1,
          title: 'Error\n1',
          radius: 50,
          titleStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        )
      ];
    }
  }
}

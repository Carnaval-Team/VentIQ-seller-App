import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'user_preferences_service.dart';

class DashboardService {
  static final DashboardService _instance = DashboardService._internal();
  factory DashboardService() => _instance;
  DashboardService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();

  /// Obtiene análisis completo de la tienda usando RPC fn_dashboard_analisis_tienda
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

      // Get current date in Cuba timezone (America/Havana)
      final now = DateTime.now().toLocal();
      final cubaDate = _formatDateForCuba(now);

      print('🔍 Calling fn_dashboard_analisis_tienda RPC:');
      print('  - p_id_tienda: $idTienda');
      print('  - p_periodo: $periodo');
      print('  - Cuba local date: $cubaDate (${now.toIso8601String()})');
      print('  - UTC date: ${DateTime.now().toUtc().toIso8601String()}');
      print('  - Timezone offset: ${now.timeZoneOffset}');
      print('  - Current hour Cuba: ${now.hour}:${now.minute}');

      // Llamar a la función RPC (revert to original parameters)
      final response = await _supabase.rpc(
        'fn_dashboard_analisis_tienda',
        params: {'p_id_tienda': idTienda, 'p_periodo': periodo},
      );

      if (response == null) {
        print('❌ RPC response is null');
        return null;
      }

      print('✅ RPC fn_dashboard_analisis_tienda response:');
      print('📊 Raw response: $response');

      // Debug specific fields that might have timezone issues
      if (response is Map<String, dynamic>) {
        print('🔍 Debugging timezone-sensitive data:');
        print('  - total_ordenes: ${response['total_ordenes']}');
        print('  - ventas_totales: ${response['ventas_totales']}');
        print('  - tendencias_de_venta: ${response['tendencias_de_venta']}');

        // Check if tendencias have date information
        if (response['tendencias_de_venta'] is List) {
          final tendencias = response['tendencias_de_venta'] as List;
          for (int i = 0; i < tendencias.length && i < 3; i++) {
            print('  - tendencia[$i]: ${tendencias[i]}');
          }
        }
      }

      // Transformar respuesta a formato del dashboard
      final transformedData = _transformRpcResponseToDashboard(
        response,
        periodo,
      );

      print('🔄 Transformed dashboard data:');
      transformedData.forEach((key, value) {
        print('  - $key: $value (${value.runtimeType})');
      });

      return transformedData;
    } catch (e) {
      print('❌ Error calling fn_dashboard_analisis_tienda: $e');
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
  Map<String, dynamic> _transformRpcResponseToDashboard(
    Map<String, dynamic> rpcResponse,
    String periodo,
  ) {
    try {
      // Extraer datos de la respuesta RPC
      final ventasTotales = rpcResponse['ventas_totales'] ?? 0;
      final ventasTotalesAnterior = rpcResponse['ventas_totales_anterior'] ?? 0;
      final totalProductos = rpcResponse['total_de_productos'] ?? 0;
      // totalProductosNoStock ya está incluido en estado_inventario como productos_sin_stock
      final totalOrdenes = rpcResponse['total_ordenes'] ?? 0;
      final totalGastos = rpcResponse['total_gastos'] ?? 0;
      final tendenciasVenta =
          rpcResponse['tendencias_de_venta'] as List<dynamic>? ?? [];
      final totalProdCategoria =
          rpcResponse['total_prod_categoria'] as List<dynamic>? ?? [];
      final estadoInventario =
          rpcResponse['estado_inventario'] as Map<String, dynamic>? ?? {};

      // Transformar tendencias de venta a datos de gráfico con etiquetas
      final salesChartData = _transformTendenciasToChartData(tendenciasVenta, periodo);
      final salesData = salesChartData['spots'] as List<FlSpot>;

      // Transformar categorías para el gráfico de dona
      final categoryData = _transformCategoriesToChartData(totalProdCategoria);

      // Calcular porcentaje de cambio en ventas
      double salesChangePercentage = 0.0;
      if (ventasTotalesAnterior > 0) {
        salesChangePercentage =
            ((ventasTotales - ventasTotalesAnterior) / ventasTotalesAnterior) *
            100;
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
        'ordersChange':
            0.0, // No tenemos datos del período anterior para órdenes
        'productsChange': 0.0, // Los productos no cambian por período
        'expensesChange':
            0.0, // No tenemos datos del período anterior para gastos
        // Estado del inventario
        'outOfStock': estadoInventario['productos_sin_stock'] ?? 0,
        'lowStock': estadoInventario['stock_bajo'] ?? 0,
        'okStock': estadoInventario['stock_ok'] ?? 0,

        // Datos para gráficos
        'salesData': salesData,
        'salesLabels': salesChartData['labels'] as List<String>,
        'salesDates': salesChartData['dates'] as List<String>,
        'categoryData': categoryData,

        // Datos adicionales
        'period': periodo,
        'lastUpdated': DateTime.now().toLocal().toIso8601String(),
      };
    } catch (e) {
      print('❌ Error transforming RPC response: $e');
      return {};
    }
  }

  /// Formatea la fecha para el timezone de Cuba (America/Havana)
  String _formatDateForCuba(DateTime date) {
    final localDate = date.toLocal();
    return '${localDate.day.toString().padLeft(2, '0')}/${localDate.month.toString().padLeft(2, '0')}/${localDate.year}';
  }

  /// Transforma las tendencias de venta a formato FlSpot con información de fechas
  Map<String, dynamic> _transformTendenciasToChartData(List<dynamic> tendencias, String periodo) {
    if (tendencias.isEmpty) {
      return {
        'spots': <FlSpot>[],
        'labels': <String>[],
        'dates': <String>[],
      };
    }

    try {
      final spots = <FlSpot>[];
      final labels = <String>[];
      final dates = <String>[];
      
      for (int i = 0; i < tendencias.length; i++) {
        final item = tendencias[i] as Map<String, dynamic>;
        final value = (item['value'] ?? 0).toDouble();
        final xAxis = item['x_axis'] ?? '';
        
        spots.add(FlSpot(i.toDouble(), value));
        dates.add(xAxis.toString());
        
        // Formatear etiqueta según el período
        final label = _formatDateLabel(xAxis.toString(), periodo);
        labels.add(label);
      }
      
      return {
        'spots': spots,
        'labels': labels,
        'dates': dates,
      };
    } catch (e) {
      print('❌ Error transforming tendencias to chart data: $e');
      return {
        'spots': <FlSpot>[],
        'labels': <String>[],
        'dates': <String>[],
      };
    }
  }

  /// Formatea las etiquetas de fecha según el período
  String _formatDateLabel(String xAxis, String periodo) {
    try {
      switch (periodo) {
        case 'Día':
          // Para período diario: "2025-09-15 08" -> "08:00"
          if (xAxis.contains(' ')) {
            final hour = xAxis.split(' ')[1];
            return '${hour}:00';
          }
          return xAxis;
          
        case 'Semana':
          // Para período semanal: "2025-09-08" -> "L8"
          final date = DateTime.parse(xAxis);
          final dayNames = ['D', 'L', 'M', 'Mi', 'J', 'V', 'S'];
          final dayName = dayNames[date.weekday % 7];
          return '$dayName${date.day}';
          
        case '1 mes':
          // Para período mensual: "2025-09-08" -> "8"
          final date = DateTime.parse(xAxis);
          return '${date.day}';
          
        case '3 meses':
        case '6 meses':
          // Para períodos de meses: "2025-09" -> "Sep 25"
          if (xAxis.length >= 7) {
            final parts = xAxis.split('-');
            if (parts.length >= 2) {
              final year = parts[0].substring(2); // "25" de "2025"
              final month = int.parse(parts[1]);
              final monthNames = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
                                 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
              return '${monthNames[month - 1]} $year';
            }
          }
          return xAxis;
          
        case '1 año':
        case '3 años':
        case '5 años':
          // Para períodos de años: "2025-09" -> "Sep 2025"
          if (xAxis.length >= 7) {
            final parts = xAxis.split('-');
            if (parts.length >= 2) {
              final year = parts[0];
              final month = int.parse(parts[1]);
              final monthNames = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
                                 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
              return '${monthNames[month - 1]} $year';
            }
          }
          return xAxis;
          
        default:
          return xAxis;
      }
    } catch (e) {
      print('❌ Error formatting date label: $e');
      return xAxis;
    }
  }

  /// Transforma las categorías a formato Map para el dashboard
  List<Map<String, dynamic>> _transformCategoriesToChartData(
    List<dynamic> categorias,
  ) {
    if (categorias.isEmpty) {
      // Datos por defecto si no hay categorías
      return [
        {'name': 'Sin datos', 'value': 1.0, 'color': 0xFF9E9E9E},
      ];
    }

    try {
      final colors = [
        0xFF4A90E2, // Azul VentIQ
        0xFF10B981, // Verde
        0xFFFF6B35, // Naranja
        0xFFE74C3C, // Rojo
        0xFF9B59B6, // Morado
        0xFFF39C12, // Amarillo
        0xFF1ABC9C, // Turquesa
        0xFF34495E, // Gris oscuro
      ];

      final chartData = <Map<String, dynamic>>[];
      for (int i = 0; i < categorias.length; i++) {
        final categoria = categorias[i] as Map<String, dynamic>;
        final name = categoria['name'] ?? 'Sin nombre';
        final value = (categoria['total_product'] ?? 0).toDouble();

        chartData.add({
          'name': name,
          'value': value,
          'color': colors[i % colors.length],
        });
      }

      return chartData;
    } catch (e) {
      print('❌ Error transforming categorias to chart data: $e');
      return [];
    }
  }
}

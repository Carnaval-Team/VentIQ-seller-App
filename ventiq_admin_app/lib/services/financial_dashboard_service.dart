import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/user_preferences_service.dart';

class FinancialDashboardService {
  static final FinancialDashboardService _instance = FinancialDashboardService._internal();
  factory FinancialDashboardService() => _instance;
  FinancialDashboardService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  // ==================== P&L CONSOLIDADO ====================

  /// Obtiene el estado de resultados (P&L) consolidado por tienda
  Future<Map<String, dynamic>> getProfitAndLoss({
    required int storeId,
    required String startDate,
    required String endDate,
    bool includeComparison = true,
  }) async {
    try {
      final response = await _supabase.rpc('fn_profit_and_loss', params: {
        'store_id': storeId,
        'start_date': startDate,
        'end_date': endDate,
        'include_comparison': includeComparison,
      });

      return response ?? {};
    } catch (e) {
      print('Error getting P&L: $e');
      return _getMockProfitAndLoss(storeId, startDate, endDate);
    }
  }

  /// Obtiene métricas clave del dashboard
  Future<Map<String, dynamic>> getKeyMetrics({
    required int storeId,
    required String period, // 'today', 'week', 'month', 'quarter', 'year'
  }) async {
    try {
      final dates = _getPeriodDates(period);
      
      // Obtener ventas totales
      final salesData = await _getSalesMetrics(storeId, dates['start']!, dates['end']!);
      
      // Obtener gastos totales
      final expensesData = await _getExpensesMetrics(storeId, dates['start']!, dates['end']!);
      
      // Obtener métricas de inventario
      final inventoryData = await _getInventoryMetrics(storeId);
      
      // Calcular KPIs
      final revenue = salesData['total_revenue'] ?? 0.0;
      final expenses = expensesData['total_expenses'] ?? 0.0;
      final grossProfit = revenue - (expensesData['cost_of_goods_sold'] ?? 0.0);
      final netProfit = revenue - expenses;
      
      return {
        'period': period,
        'store_id': storeId,
        'revenue': revenue,
        'expenses': expenses,
        'gross_profit': grossProfit,
        'net_profit': netProfit,
        'gross_margin': revenue > 0 ? (grossProfit / revenue * 100) : 0.0,
        'net_margin': revenue > 0 ? (netProfit / revenue * 100) : 0.0,
        'roi': _calculateROI(netProfit, expenses),
        'inventory_turnover': inventoryData['turnover_ratio'] ?? 0.0,
        'cash_flow': netProfit + (expensesData['depreciation'] ?? 0.0),
        'sales_growth': salesData['growth_rate'] ?? 0.0,
        'expense_ratio': revenue > 0 ? (expenses / revenue * 100) : 0.0,
        'updated_at': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('Error getting key metrics: $e');
      return _getMockKeyMetrics(storeId, period);
    }
  }

  /// Obtiene métricas de ventas
  Future<Map<String, dynamic>> _getSalesMetrics(int storeId, String startDate, String endDate) async {
    try {
      final response = await _supabase.rpc('fn_sales_metrics', params: {
        'store_id': storeId,
        'start_date': startDate,
        'end_date': endDate,
      });

      return response ?? {'total_revenue': 0.0, 'growth_rate': 0.0};
    } catch (e) {
      print('Error getting sales metrics: $e');
      return {'total_revenue': 0.0, 'growth_rate': 0.0};
    }
  }

  /// Obtiene métricas de gastos
  Future<Map<String, dynamic>> _getExpensesMetrics(int storeId, String startDate, String endDate) async {
    try {
      final response = await _supabase
          .from('app_cont_gastos')
          .select('monto, id_subcategoria_gasto, app_nom_subcategoria_gasto(nombre, codigo)')
          .eq('id_centro_costo', 'TDA_$storeId')
          .gte('fecha_gasto', startDate)
          .lte('fecha_gasto', endDate);

      double totalExpenses = 0.0;
      double costOfGoodsSold = 0.0;
      double operationalExpenses = 0.0;
      double administrativeExpenses = 0.0;

      for (final expense in response) {
        final amount = (expense['monto'] ?? 0.0).toDouble();
        totalExpenses += amount;

        final categoryCode = expense['app_nom_subcategoria_gasto']?['codigo'] ?? '';
        
        switch (categoryCode) {
          case 'COMPRAS':
            costOfGoodsSold += amount;
            break;
          case 'OPERATIVOS':
            operationalExpenses += amount;
            break;
          case 'ADMINISTRATIVOS':
            administrativeExpenses += amount;
            break;
        }
      }

      return {
        'total_expenses': totalExpenses,
        'cost_of_goods_sold': costOfGoodsSold,
        'operational_expenses': operationalExpenses,
        'administrative_expenses': administrativeExpenses,
        'depreciation': 0.0, // Placeholder for depreciation
      };
    } catch (e) {
      print('Error getting expenses metrics: $e');
      return {
        'total_expenses': 0.0,
        'cost_of_goods_sold': 0.0,
        'operational_expenses': 0.0,
        'administrative_expenses': 0.0,
        'depreciation': 0.0,
      };
    }
  }

  /// Obtiene métricas de inventario
  Future<Map<String, dynamic>> _getInventoryMetrics(int storeId) async {
    try {
      final response = await _supabase.rpc('fn_inventory_metrics', params: {
        'store_id': storeId,
      });

      return response ?? {'turnover_ratio': 0.0, 'average_inventory': 0.0};
    } catch (e) {
      print('Error getting inventory metrics: $e');
      return {'turnover_ratio': 0.0, 'average_inventory': 0.0};
    }
  }

  // ==================== ANÁLISIS DE RENTABILIDAD ====================

  /// Obtiene análisis de rentabilidad por producto
  Future<List<Map<String, dynamic>>> getProductProfitability({
    required int storeId,
    required String period,
    int limit = 20,
    String sortBy = 'profit_margin', // 'profit_margin', 'total_profit', 'revenue'
  }) async {
    try {
      final response = await _supabase.rpc('fn_product_profitability', params: {
        'store_id': storeId,
        'period': period,
        'limit_results': limit,
        'sort_by': sortBy,
      });

      return List<Map<String, dynamic>>.from(response ?? []);
    } catch (e) {
      print('Error getting product profitability: $e');
      return [];
    }
  }

  /// Obtiene análisis de rentabilidad por categoría
  Future<List<Map<String, dynamic>>> getCategoryProfitability({
    required int storeId,
    required String period,
  }) async {
    try {
      final response = await _supabase.rpc('fn_category_profitability', params: {
        'store_id': storeId,
        'period': period,
      });

      return List<Map<String, dynamic>>.from(response ?? []);
    } catch (e) {
      print('Error getting category profitability: $e');
      return [];
    }
  }

  // ==================== ALERTAS Y NOTIFICACIONES ====================

  /// Obtiene alertas financieras activas
  Future<List<Map<String, dynamic>>> getFinancialAlerts({
    required int storeId,
  }) async {
    try {
      final alerts = <Map<String, dynamic>>[];
      
      // Verificar alertas de presupuesto
      final budgetAlerts = await _checkBudgetAlerts(storeId);
      alerts.addAll(budgetAlerts);
      
      // Verificar alertas de rentabilidad
      final profitabilityAlerts = await _checkProfitabilityAlerts(storeId);
      alerts.addAll(profitabilityAlerts);
      
      // Verificar alertas de flujo de efectivo
      final cashFlowAlerts = await _checkCashFlowAlerts(storeId);
      alerts.addAll(cashFlowAlerts);

      return alerts;
    } catch (e) {
      print('Error getting financial alerts: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _checkBudgetAlerts(int storeId) async {
    // Implementar lógica de alertas de presupuesto
    return [];
  }

  Future<List<Map<String, dynamic>>> _checkProfitabilityAlerts(int storeId) async {
    // Implementar lógica de alertas de rentabilidad
    return [];
  }

  Future<List<Map<String, dynamic>>> _checkCashFlowAlerts(int storeId) async {
    // Implementar lógica de alertas de flujo de efectivo
    return [];
  }

  // ==================== PROYECCIONES Y TENDENCIAS ====================

  /// Obtiene proyecciones de flujo de efectivo
  Future<List<Map<String, dynamic>>> getCashFlowProjections({
    required int storeId,
    int monthsAhead = 6,
  }) async {
    try {
      final response = await _supabase.rpc('fn_cash_flow_projections', params: {
        'store_id': storeId,
        'months_ahead': monthsAhead,
      });

      return List<Map<String, dynamic>>.from(response ?? []);
    } catch (e) {
      print('Error getting cash flow projections: $e');
      return [];
    }
  }

  /// Obtiene tendencias históricas
  Future<Map<String, dynamic>> getHistoricalTrends({
    required int storeId,
    required String metric, // 'revenue', 'profit', 'expenses'
    int monthsBack = 12,
  }) async {
    try {
      final response = await _supabase.rpc('fn_historical_trends', params: {
        'store_id': storeId,
        'metric': metric,
        'months_back': monthsBack,
      });

      return response ?? {};
    } catch (e) {
      print('Error getting historical trends: $e');
      return {};
    }
  }

  // ==================== UTILIDADES ====================

  Map<String, String> _getPeriodDates(String period) {
    final now = DateTime.now();
    DateTime startDate;
    DateTime endDate = now;

    switch (period) {
      case 'today':
        startDate = DateTime(now.year, now.month, now.day);
        break;
      case 'week':
        startDate = now.subtract(Duration(days: now.weekday - 1));
        break;
      case 'month':
        startDate = DateTime(now.year, now.month, 1);
        break;
      case 'quarter':
        final quarterStart = ((now.month - 1) ~/ 3) * 3 + 1;
        startDate = DateTime(now.year, quarterStart, 1);
        break;
      case 'year':
        startDate = DateTime(now.year, 1, 1);
        break;
      default:
        startDate = DateTime(now.year, now.month, 1);
    }

    return {
      'start': startDate.toIso8601String().split('T')[0],
      'end': endDate.toIso8601String().split('T')[0],
    };
  }

  double _calculateROI(double netProfit, double investment) {
    return investment > 0 ? (netProfit / investment * 100) : 0.0;
  }

  // ==================== UTILIDADES PRIVADAS ====================

  Future<int> _getStoreId() async {
    try {
      final userPrefs = UserPreferencesService();
      final storeId = await userPrefs.getIdTienda();
      return storeId ?? 1;
    } catch (e) {
      print('❌ Error obteniendo store ID: $e');
      return 1;
    }
  }

  Future<String> _getUserId() async {
    try {
      final userPrefs = UserPreferencesService();
      final userId = await userPrefs.getUserId();
      return userId ?? 'default-user';
    } catch (e) {
      print('❌ Error obteniendo user ID: $e');
      return 'default-user';
    }
  }

  // ==================== DATOS MOCK PARA DESARROLLO ====================

  Map<String, dynamic> _getMockProfitAndLoss(int storeId, String startDate, String endDate) {
    return {
      'store_id': storeId,
      'period': '$startDate to $endDate',
      'revenue': 150000.0,
      'cost_of_goods_sold': 90000.0,
      'gross_profit': 60000.0,
      'operational_expenses': 25000.0,
      'administrative_expenses': 15000.0,
      'financial_expenses': 2000.0,
      'total_expenses': 42000.0,
      'net_profit': 18000.0,
      'gross_margin': 40.0,
      'net_margin': 12.0,
    };
  }

  Map<String, dynamic> _getMockKeyMetrics(int storeId, String period) {
    return {
      'period': period,
      'store_id': storeId,
      'revenue': 150000.0,
      'expenses': 132000.0,
      'gross_profit': 60000.0,
      'net_profit': 18000.0,
      'gross_margin': 40.0,
      'net_margin': 12.0,
      'roi': 13.6,
      'inventory_turnover': 6.2,
      'cash_flow': 20000.0,
      'sales_growth': 8.5,
      'expense_ratio': 88.0,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}

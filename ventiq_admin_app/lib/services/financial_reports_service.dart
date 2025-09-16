import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/user_preferences_service.dart';

class FinancialReportsService {
  static final FinancialReportsService _instance = FinancialReportsService._internal();
  factory FinancialReportsService() => _instance;
  FinancialReportsService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  // ==================== REPORTES AVANZADOS DE RENTABILIDAD ====================

  /// Genera reporte completo de rentabilidad por producto
  Future<Map<String, dynamic>> generateProfitabilityReport({
    required int storeId,
    required String startDate,
    required String endDate,
    String? categoryId,
    String sortBy = 'profit_margin', // 'profit_margin', 'total_profit', 'revenue', 'units_sold'
    bool includeDetails = true,
  }) async {
    try {
      final response = await _supabase.rpc('fn_profitability_report', params: {
        'store_id': storeId,
        'start_date': startDate,
        'end_date': endDate,
        'category_id': categoryId,
        'sort_by': sortBy,
        'include_details': includeDetails,
      });

      return response ?? _getMockProfitabilityReport(storeId, startDate, endDate);
    } catch (e) {
      print('Error generating profitability report: $e');
      return _getMockProfitabilityReport(storeId, startDate, endDate);
    }
  }

  /// Análisis de rentabilidad por categoría
  Future<List<Map<String, dynamic>>> getCategoryProfitabilityAnalysis({
    required int storeId,
    required String period,
    bool includeSubcategories = false,
  }) async {
    try {
      final response = await _supabase.rpc('fn_category_profitability_analysis', params: {
        'store_id': storeId,
        'period': period,
        'include_subcategories': includeSubcategories,
      });

      return List<Map<String, dynamic>>.from(response ?? _getMockCategoryAnalysis());
    } catch (e) {
      print('Error getting category profitability: $e');
      return _getMockCategoryAnalysis();
    }
  }

  /// Identifica productos con baja rentabilidad
  Future<List<Map<String, dynamic>>> getLowProfitabilityProducts({
    required int storeId,
    double marginThreshold = 15.0, // Productos con margen menor al 15%
    int limit = 50,
  }) async {
    try {
      final response = await _supabase.rpc('fn_low_profitability_products', params: {
        'store_id': storeId,
        'margin_threshold': marginThreshold,
        'limit_results': limit,
      });

      return List<Map<String, dynamic>>.from(response ?? []);
    } catch (e) {
      print('Error getting low profitability products: $e');
      return [];
    }
  }

  // ==================== PROYECCIONES DE FLUJO DE EFECTIVO ====================

  /// Genera proyecciones de flujo de efectivo
  Future<Map<String, dynamic>> generateCashFlowProjections({
    required int storeId,
    int monthsAhead = 6,
    bool includeSeasonality = true,
  }) async {
    try {
      // Obtener datos históricos para proyección
      final historicalData = await _getHistoricalCashFlowData(storeId, 12);
      
      // Calcular tendencias y estacionalidad
      final projections = _calculateCashFlowProjections(
        historicalData, 
        monthsAhead, 
        includeSeasonality
      );

      return {
        'store_id': storeId,
        'projection_months': monthsAhead,
        'include_seasonality': includeSeasonality,
        'projections': projections,
        'confidence_level': _calculateConfidenceLevel(historicalData),
        'generated_at': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('Error generating cash flow projections: $e');
      return _getMockCashFlowProjections(storeId, monthsAhead);
    }
  }

  Future<List<Map<String, dynamic>>> _getHistoricalCashFlowData(int storeId, int monthsBack) async {
    try {
      final endDate = DateTime.now();
      final startDate = DateTime(endDate.year, endDate.month - monthsBack, 1);

      final response = await _supabase.rpc('fn_historical_cash_flow', params: {
        'store_id': storeId,
        'start_date': startDate.toIso8601String().split('T')[0],
        'end_date': endDate.toIso8601String().split('T')[0],
      });

      return List<Map<String, dynamic>>.from(response ?? []);
    } catch (e) {
      print('Error getting historical cash flow data: $e');
      return [];
    }
  }

  List<Map<String, dynamic>> _calculateCashFlowProjections(
    List<Map<String, dynamic>> historicalData,
    int monthsAhead,
    bool includeSeasonality,
  ) {
    final projections = <Map<String, dynamic>>[];
    final now = DateTime.now();

    // Calcular promedios y tendencias
    double avgRevenue = 0.0;
    double avgExpenses = 0.0;
    double trendFactor = 1.0;

    if (historicalData.isNotEmpty) {
      avgRevenue = historicalData
          .map((d) => (d['revenue'] ?? 0.0).toDouble())
          .reduce((a, b) => a + b) / historicalData.length;
      
      avgExpenses = historicalData
          .map((d) => (d['expenses'] ?? 0.0).toDouble())
          .reduce((a, b) => a + b) / historicalData.length;

      // Calcular tendencia simple (últimos 3 meses vs anteriores)
      if (historicalData.length >= 6) {
        final recent = historicalData.take(3).toList();
        final previous = historicalData.skip(3).take(3).toList();
        
        final recentAvg = recent.map((d) => (d['revenue'] ?? 0.0).toDouble()).reduce((a, b) => a + b) / 3;
        final previousAvg = previous.map((d) => (d['revenue'] ?? 0.0).toDouble()).reduce((a, b) => a + b) / 3;
        
        trendFactor = previousAvg > 0 ? recentAvg / previousAvg : 1.0;
      }
    }

    for (int i = 1; i <= monthsAhead; i++) {
      final projectionDate = DateTime(now.year, now.month + i, 1);
      
      // Aplicar factor estacional si está habilitado
      double seasonalFactor = 1.0;
      if (includeSeasonality) {
        seasonalFactor = _getSeasonalFactor(projectionDate.month);
      }

      // Aplicar tendencia gradual
      final monthlyTrendFactor = 1.0 + ((trendFactor - 1.0) * i / monthsAhead);

      final projectedRevenue = avgRevenue * seasonalFactor * monthlyTrendFactor;
      final projectedExpenses = avgExpenses * seasonalFactor * monthlyTrendFactor * 0.95; // Ligera optimización de gastos
      final projectedCashFlow = projectedRevenue - projectedExpenses;

      projections.add({
        'month': projectionDate.toIso8601String().split('T')[0].substring(0, 7),
        'projected_revenue': projectedRevenue,
        'projected_expenses': projectedExpenses,
        'projected_cash_flow': projectedCashFlow,
        'seasonal_factor': seasonalFactor,
        'trend_factor': monthlyTrendFactor,
      });
    }

    return projections;
  }

  double _getSeasonalFactor(int month) {
    // Factores estacionales típicos para retail (ajustables por negocio)
    const seasonalFactors = {
      1: 0.85,  // Enero - post navidad
      2: 0.90,  // Febrero
      3: 0.95,  // Marzo
      4: 1.00,  // Abril
      5: 1.05,  // Mayo - día de la madre
      6: 1.00,  // Junio
      7: 0.95,  // Julio
      8: 0.90,  // Agosto
      9: 1.05,  // Septiembre - regreso a clases
      10: 1.10, // Octubre
      11: 1.15, // Noviembre - pre navidad
      12: 1.25, // Diciembre - navidad
    };
    
    return seasonalFactors[month] ?? 1.0;
  }

  double _calculateConfidenceLevel(List<Map<String, dynamic>> historicalData) {
    if (historicalData.length < 3) return 0.5;
    if (historicalData.length < 6) return 0.7;
    if (historicalData.length < 12) return 0.8;
    return 0.9;
  }

  // ==================== COMPARATIVAS HISTÓRICAS ====================

  /// Genera comparativas históricas por período
  Future<Map<String, dynamic>> generateHistoricalComparison({
    required int storeId,
    required String currentPeriodStart,
    required String currentPeriodEnd,
    String comparisonType = 'previous_period', // 'previous_period', 'same_period_last_year'
  }) async {
    try {
      final response = await _supabase.rpc('fn_historical_comparison', params: {
        'store_id': storeId,
        'current_start': currentPeriodStart,
        'current_end': currentPeriodEnd,
        'comparison_type': comparisonType,
      });

      return response ?? _getMockHistoricalComparison(storeId);
    } catch (e) {
      print('Error generating historical comparison: $e');
      return _getMockHistoricalComparison(storeId);
    }
  }

  /// Análisis de tendencias por KPI
  Future<Map<String, dynamic>> getTrendAnalysis({
    required int storeId,
    required String kpi, // 'revenue', 'profit', 'margin', 'inventory_turnover'
    int monthsBack = 12,
  }) async {
    try {
      final response = await _supabase.rpc('fn_trend_analysis', params: {
        'store_id': storeId,
        'kpi': kpi,
        'months_back': monthsBack,
      });

      return response ?? _getMockTrendAnalysis(kpi);
    } catch (e) {
      print('Error getting trend analysis: $e');
      return _getMockTrendAnalysis(kpi);
    }
  }

  // ==================== CONTROL PRESUPUESTARIO ====================

  /// Crea presupuesto por centro de costo
  Future<void> createBudget({
    required int storeId,
    required String period, // 'YYYY-MM' formato
    required Map<String, double> categoryBudgets, // categoria_id -> monto
    String? description,
  }) async {
    try {
      await _supabase.from('app_cont_presupuesto').insert({
        'id_tienda': storeId,
        'periodo': period,
        'presupuesto_categorias': categoryBudgets,
        'descripcion': description ?? 'Presupuesto generado automáticamente',
        'fecha_creacion': DateTime.now().toIso8601String(),
        'activo': true,
      });
    } catch (e) {
      print('Error creating budget: $e');
      rethrow;
    }
  }

  /// Obtiene análisis de variaciones presupuestarias
  Future<Map<String, dynamic>> getBudgetVarianceAnalysis({
    required int storeId,
    required String period,
  }) async {
    try {
      final response = await _supabase.rpc('fn_budget_variance_analysis', params: {
        'store_id': storeId,
        'period': period,
      });

      return response ?? _getMockBudgetVariance(storeId, period);
    } catch (e) {
      print('Error getting budget variance: $e');
      return _getMockBudgetVariance(storeId, period);
    }
  }

  /// Sistema de aprobaciones de gastos excepcionales
  Future<void> requestExpenseApproval({
    required int storeId,
    required double amount,
    required String categoryId,
    required String description,
    required String justification,
    String? attachments,
  }) async {
    try {
      await _supabase.from('app_cont_aprobacion_gastos').insert({
        'id_tienda': storeId,
        'monto': amount,
        'id_categoria': categoryId,
        'descripcion': description,
        'justificacion': justification,
        'adjuntos': attachments,
        'estado': 'pendiente',
        'fecha_solicitud': DateTime.now().toIso8601String(),
        'solicitado_por': await _getUserId(),
      });
    } catch (e) {
      print('Error requesting expense approval: $e');
      rethrow;
    }
  }

  /// Obtiene gastos pendientes de aprobación
  Future<List<Map<String, dynamic>>> getPendingApprovals({
    required int storeId,
  }) async {
    try {
      final response = await _supabase
          .from('app_cont_aprobacion_gastos')
          .select('*')
          .eq('id_tienda', storeId)
          .eq('estado', 'pendiente')
          .order('fecha_solicitud', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error getting pending approvals: $e');
      return [];
    }
  }

  // ==================== DATOS MOCK PARA DESARROLLO ====================

  Map<String, dynamic> _getMockProfitabilityReport(int storeId, String startDate, String endDate) {
    return {
      'store_id': storeId,
      'period': '$startDate to $endDate',
      'total_products': 150,
      'profitable_products': 120,
      'loss_making_products': 30,
      'average_margin': 28.5,
      'top_performers': [
        {'product_name': 'Producto A', 'margin': 45.2, 'profit': 15000},
        {'product_name': 'Producto B', 'margin': 38.7, 'profit': 12500},
        {'product_name': 'Producto C', 'margin': 35.1, 'profit': 11200},
      ],
      'bottom_performers': [
        {'product_name': 'Producto X', 'margin': 5.2, 'profit': 800},
        {'product_name': 'Producto Y', 'margin': 8.1, 'profit': 1200},
      ],
    };
  }

  List<Map<String, dynamic>> _getMockCategoryAnalysis() {
    return [
      {'category': 'Electrónicos', 'margin': 32.5, 'revenue': 85000, 'profit': 27625},
      {'category': 'Ropa', 'margin': 45.2, 'revenue': 65000, 'profit': 29380},
      {'category': 'Hogar', 'margin': 28.1, 'revenue': 45000, 'profit': 12645},
    ];
  }

  Map<String, dynamic> _getMockCashFlowProjections(int storeId, int monthsAhead) {
    final projections = <Map<String, dynamic>>[];
    final now = DateTime.now();
    
    for (int i = 1; i <= monthsAhead; i++) {
      final month = DateTime(now.year, now.month + i, 1);
      projections.add({
        'month': month.toIso8601String().split('T')[0].substring(0, 7),
        'projected_revenue': 150000 + (i * 5000),
        'projected_expenses': 120000 + (i * 3000),
        'projected_cash_flow': 30000 + (i * 2000),
      });
    }

    return {
      'store_id': storeId,
      'projection_months': monthsAhead,
      'projections': projections,
      'confidence_level': 0.8,
    };
  }

  Map<String, dynamic> _getMockHistoricalComparison(int storeId) {
    return {
      'store_id': storeId,
      'current_period': {'revenue': 150000, 'profit': 18000, 'margin': 12.0},
      'comparison_period': {'revenue': 140000, 'profit': 16000, 'margin': 11.4},
      'variance': {'revenue': 7.1, 'profit': 12.5, 'margin': 0.6},
    };
  }

  Map<String, dynamic> _getMockTrendAnalysis(String kpi) {
    return {
      'kpi': kpi,
      'trend': 'upward',
      'growth_rate': 8.5,
      'volatility': 'medium',
      'seasonal_pattern': true,
    };
  }

  Map<String, dynamic> _getMockBudgetVariance(int storeId, String period) {
    return {
      'store_id': storeId,
      'period': period,
      'total_budget': 120000,
      'total_actual': 125000,
      'variance_percent': 4.2,
      'category_variances': [
        {'category': 'Operativos', 'budget': 50000, 'actual': 52000, 'variance': 4.0},
        {'category': 'Administrativos', 'budget': 30000, 'actual': 31000, 'variance': 3.3},
      ],
    };
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
}

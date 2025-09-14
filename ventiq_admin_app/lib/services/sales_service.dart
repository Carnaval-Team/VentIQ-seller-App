import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';
import '../models/sales.dart';

class ProductSalesReport {
  final int idTienda;
  final int idProducto;
  final String nombreProducto;
  final double precioVentaCup;
  final double precioCosto;
  final double valorUsd;
  final double precioCostoCup;
  final double totalVendido;
  final double ingresosTotales;
  final double costoTotalVendido;
  final double gananciaUnitaria;
  final double gananciaTotal;

  ProductSalesReport({
    required this.idTienda,
    required this.idProducto,
    required this.nombreProducto,
    required this.precioVentaCup,
    required this.precioCosto,
    required this.valorUsd,
    required this.precioCostoCup,
    required this.totalVendido,
    required this.ingresosTotales,
    required this.costoTotalVendido,
    required this.gananciaUnitaria,
    required this.gananciaTotal,
  });

  factory ProductSalesReport.fromJson(Map<String, dynamic> json) {
    return ProductSalesReport(
      idTienda: json['id_tienda'] ?? 0,
      idProducto: json['id_producto'] ?? 0,
      nombreProducto: json['nombre_producto'] ?? '',
      precioVentaCup: (json['precio_venta_cup'] ?? 0).toDouble(),
      precioCosto: (json['precio_costo'] ?? 0).toDouble(),
      valorUsd: (json['valor_usd'] ?? 1).toDouble(),
      precioCostoCup: (json['precio_costo_cup'] ?? 0).toDouble(),
      totalVendido: (json['total_vendido'] ?? 0).toDouble(),
      ingresosTotales: (json['ingresos_totales'] ?? 0).toDouble(),
      costoTotalVendido: (json['costo_total_vendido'] ?? 0).toDouble(),
      gananciaUnitaria: (json['ganancia_unitaria'] ?? 0).toDouble(),
      gananciaTotal: (json['ganancia_total'] ?? 0).toDouble(),
    );
  }
}

class ProductAnalysis {
  final int idTienda;
  final int idProducto;
  final String nombreProducto;
  final double precioVentaCup;
  final double precioCosto;
  final double valorUsd;
  final double precioCostoCup;
  final double ganancia;

  ProductAnalysis({
    required this.idTienda,
    required this.idProducto,
    required this.nombreProducto,
    required this.precioVentaCup,
    required this.precioCosto,
    required this.valorUsd,
    required this.precioCostoCup,
    required this.ganancia,
  });

  factory ProductAnalysis.fromJson(Map<String, dynamic> json) {
    return ProductAnalysis(
      idTienda: json['id_tienda'] ?? 0,
      idProducto: json['id_producto'] ?? 0,
      nombreProducto: json['nombre_producto'] ?? '',
      precioVentaCup: (json['precio_venta_cup'] ?? 0).toDouble(),
      precioCosto: (json['precio_costo'] ?? 0).toDouble(),
      valorUsd: (json['valor_usd'] ?? 1).toDouble(),
      precioCostoCup: (json['precio_costo_cup'] ?? 0).toDouble(),
      ganancia: (json['ganancia'] ?? 0).toDouble(),
    );
  }

  // Calcular porcentaje de ganancia
  double get porcentajeGanancia {
    if (precioCostoCup == 0) return 0.0;
    return (ganancia / precioCostoCup) * 100;
  }

  // Precio venta en USD
  double get precioVentaUsd {
    if (valorUsd == 0) return 0.0;
    return precioVentaCup / valorUsd;
  }
}

class SalesService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static Future<List<ProductSalesReport>> getProductSalesReport({
    DateTime? fechaDesde,
    DateTime? fechaHasta,
  }) async {
    try {
      // Get store ID from preferences
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      if (idTienda == null) {
        print('Error: No se pudo obtener el ID de tienda');
        return [];
      }

      print('Calling fn_reporte_ventas_ganancias with:');
      print('- id_tienda: $idTienda');
      print('- fecha_desde: $fechaDesde');
      print('- fecha_hasta: $fechaHasta');

      // Prepare parameters
      final Map<String, dynamic> params = {'p_id_tienda': idTienda};

      if (fechaDesde != null) {
        params['p_fecha_desde'] = fechaDesde.toIso8601String().split('T')[0];
      }
      if (fechaHasta != null) {
        params['p_fecha_hasta'] = fechaHasta.toIso8601String().split('T')[0];
      }

      // Call the RPC function
      final response = await _supabase.rpc(
        'fn_reporte_ventas_ganancias',
        params: params,
      );

      print('Response received: ${response.length} products');

      if (response == null) {
        print('No data received from RPC call');
        return [];
      }

      // Convert response to ProductSalesReport objects
      final List<ProductSalesReport> reports = [];
      for (final item in response) {
        try {
          final report = ProductSalesReport.fromJson(item);
          reports.add(report);
          print(
            'Added product: ${report.nombreProducto} - Total vendido: ${report.totalVendido}',
          );
        } catch (e) {
          print('Error parsing product sales report item: $e');
          print('Item data: $item');
        }
      }

      print('Successfully parsed ${reports.length} product sales reports');
      return reports;
    } catch (e) {
      print('Error in getProductSalesReport: $e');
      return [];
    }
  }

  // Get date ranges for filters
  static DateTime getStartOfDay() =>
      DateTime.now().copyWith(hour: 0, minute: 0, second: 0, microsecond: 0);
  static DateTime getStartOfWeek() {
    final now = DateTime.now();
    final weekday = now.weekday;
    return now
        .subtract(Duration(days: weekday - 1))
        .copyWith(hour: 0, minute: 0, second: 0, microsecond: 0);
  }

  static DateTime getStartOfMonth() =>
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  static DateTime getStartOfYear() => DateTime(DateTime.now().year, 1, 1);

  static Map<String, DateTime> _getDateRangeForPeriod(String period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (period) {
      case 'Hoy':
        return {
          'start': today,
          'end': today
              .add(const Duration(days: 1))
              .subtract(const Duration(seconds: 1)),
        };
      case 'Esta Semana':
        final startOfWeek = today.subtract(Duration(days: now.weekday - 1));
        return {
          'start': startOfWeek,
          'end': startOfWeek
              .add(const Duration(days: 7))
              .subtract(const Duration(seconds: 1)),
        };
      case 'Este Mes':
        final startOfMonth = DateTime(now.year, now.month, 1);
        final endOfMonth = DateTime(
          now.year,
          now.month + 1,
          1,
        ).subtract(const Duration(seconds: 1));
        return {'start': startOfMonth, 'end': endOfMonth};
      case 'Este Año':
        final startOfYear = DateTime(now.year, 1, 1);
        final endOfYear = DateTime(
          now.year + 1,
          1,
          1,
        ).subtract(const Duration(seconds: 1));
        return {'start': startOfYear, 'end': endOfYear};
      default:
        return {
          'start': today,
          'end': today
              .add(const Duration(days: 1))
              .subtract(const Duration(seconds: 1)),
        };
    }
  }

  static Future<Map<String, dynamic>> getSalesMetrics(String period) async {
    try {
      final userPrefs = UserPreferencesService();
      final storeId = await userPrefs.getIdTienda();

      print('=== DEBUG getSalesMetrics ===');
      print('Period: $period');
      print('Store ID: $storeId');

      final dateRange = _getDateRangeForPeriod(period);
      final startDate = dateRange['start']!.toIso8601String().split('T')[0];
      final endDate = dateRange['end']!.toIso8601String().split('T')[0];

      print('Date range calculated:');
      print('- Start date: $startDate');
      print('- End date: $endDate');
      print('- Start DateTime: ${dateRange['start']}');
      print('- End DateTime: ${dateRange['end']}');

      final params = {
        'p_id_tienda': storeId,
        'p_fecha_desde': startDate,
        'p_fecha_hasta': endDate,
      };

      print('Parameters being sent to fn_reporte_ventas_ganancias:');
      print(
        '- p_id_tienda: ${params['p_id_tienda']} (type: ${params['p_id_tienda'].runtimeType})',
      );
      print(
        '- p_fecha_desde: ${params['p_fecha_desde']} (type: ${params['p_fecha_desde'].runtimeType})',
      );
      print(
        '- p_fecha_hasta: ${params['p_fecha_hasta']} (type: ${params['p_fecha_hasta'].runtimeType})',
      );

      print('Calling RPC function...');
      final response = await Supabase.instance.client.rpc(
        'fn_reporte_ventas_ganancias',
        params: params,
      );

      print('Raw response received:');
      print('- Response type: ${response.runtimeType}');
      print('- Response length: ${response?.length ?? 'null'}');
      print('- Response content: $response');

      if (response == null || response.isEmpty) {
        print('No data received - returning zeros');
        return {'totalSales': 0.0, 'transactionCount': 0};
      }

      double totalSales = 0.0;
      int transactionCount = 0;

      print('Processing ${response.length} items:');
      for (int i = 0; i < response.length; i++) {
        var item = response[i];
        print('Item $i: $item');
        print('- Item type: ${item.runtimeType}');
        print('- Keys: ${item.keys.toList()}');

        final ingresoTotal = (item['ingresos_totales'] as num?)?.toDouble() ?? 0.0;
        final totalVendido = (item['total_vendido'] as num?)?.toDouble() ?? 0.0;

        print('- ingresos_totales: $ingresoTotal (raw: ${item['ingresos_totales']})');
        print('- total_vendido: $totalVendido (raw: ${item['total_vendido']})');

        totalSales += ingresoTotal;
        if (totalVendido > 0) {
          transactionCount++;
        }
      }

      final result = {
        'totalSales': totalSales,
        'transactionCount': transactionCount,
      };

      print('Final calculated metrics:');
      print('- Total Sales: $totalSales');
      print('- Transaction Count: $transactionCount');
      print('=== END DEBUG getSalesMetrics ===');

      return result;
    } catch (e) {
      print('ERROR in getSalesMetrics: $e');
      print('Error type: ${e.runtimeType}');
      print('Stack trace: ${StackTrace.current}');
      return {'totalSales': 0.0, 'transactionCount': 0};
    }
  }

  static Future<List<ProductAnalysis>> getProductAnalysis({
    DateTime? fechaDesde,
    DateTime? fechaHasta,
  }) async {
    try {
      // Get store ID from preferences
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      if (idTienda == null) {
        print('Error: No se pudo obtener el ID de tienda');
        return [];
      }

      print('Calling fn_vista_precios_productos with:');
      print('- id_tienda: $idTienda');
      print('- fecha_desde: $fechaDesde');
      print('- fecha_hasta: $fechaHasta');

      // Prepare parameters
      final Map<String, dynamic> params = {'p_id_tienda': idTienda};

      // if (fechaDesde != null) {
      //   params['p_fecha_desde'] = fechaDesde.toIso8601String().split('T')[0];
      // }
      // if (fechaHasta != null) {
      //   params['p_fecha_hasta'] = fechaHasta.toIso8601String().split('T')[0];
      // }

      // Call the RPC function
      final response = await _supabase.rpc(
        'fn_vista_precios_productos',
        params: params,
      );

      print('Response received: ${response?.length ?? 0} products');

      if (response == null) {
        print('No response from fn_vista_precios_productos');
        return [];
      }

      // Parse response into ProductAnalysis objects
      final List<ProductAnalysis> productAnalysis = [];
      for (var item in response) {
        try {
          final analysis = ProductAnalysis.fromJson(item);
          productAnalysis.add(analysis);
          print('Parsed product: ${analysis.nombreProducto}');
        } catch (e) {
          print('Error parsing product analysis item: $e');
          print('Item data: $item');
        }
      }

      print(
        'Successfully parsed ${productAnalysis.length} product analysis records',
      );
      return productAnalysis;
    } catch (e) {
      print('Error in getProductAnalysis: $e');
      return [];
    }
  }

  static Future<List<CashDelivery>> getCashDeliveries({
    required DateTime fechaInicio,
    required DateTime fechaFin,
    String? uuidUsuario,
  }) async {
    try {
      print('Calling fn_listar_entregas_por_fechas_usuario with:');
      print('- p_fecha_inicio: $fechaInicio');
      print('- p_fecha_fin: $fechaFin');
      print('- p_uuid_usuario: $uuidUsuario');

      // Prepare parameters
      final Map<String, dynamic> params = {
        'p_fecha_inicio': fechaInicio.toIso8601String(),
        'p_fecha_fin': fechaFin.toIso8601String(),
      };

      if (uuidUsuario != null) {
        params['p_uuid_usuario'] = uuidUsuario;
      }

      // Call the RPC function
      final response = await _supabase.rpc(
        'fn_listar_entregas_por_fechas_usuario',
        params: params,
      );

      print('Response received: ${response?.length ?? 0} cash deliveries');

      if (response == null) {
        print('No data received from fn_listar_entregas_por_fechas_usuario');
        return [];
      }

      // Convert response to CashDelivery objects
      final List<CashDelivery> deliveries = [];
      for (final item in response) {
        try {
          final delivery = CashDelivery.fromJson(item);
          deliveries.add(delivery);
          print(
            'Added delivery: ID ${delivery.id} - Monto: \$${delivery.montoEntrega} - Motivo: ${delivery.motivoEntrega}',
          );
        } catch (e) {
          print('Error parsing cash delivery item: $e');
          print('Item data: $item');
        }
      }

      print('Successfully parsed ${deliveries.length} cash deliveries');
      return deliveries;
    } catch (e) {
      print('Error in getCashDeliveries: $e');
      return [];
    }
  }

  static Future<List<SalesVendorReport>> getSalesVendorReport({
    DateTime? fechaDesde,
    DateTime? fechaHasta,
    String? uuidUsuario,
  }) async {
    try {
      // Get store ID from preferences
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      if (idTienda == null) {
        print('Error: No se pudo obtener el ID de tienda');
        return [];
      }

      print('Calling fn_reporte_ventas_por_vendedor with:');
      print('- p_id_tienda: $idTienda');
      print('- p_fecha_desde: $fechaDesde');
      print('- p_fecha_hasta: $fechaHasta');
      print('- p_uuid_usuario: $uuidUsuario');

      // Prepare parameters
      final Map<String, dynamic> params = {'p_id_tienda': idTienda};

      if (fechaDesde != null) {
        params['p_fecha_desde'] = fechaDesde.toIso8601String().split('T')[0];
      }
      if (fechaHasta != null) {
        params['p_fecha_hasta'] = fechaHasta.toIso8601String().split('T')[0];
      }
      // if (uuidUsuario != null) {
      //   params['p_uuid_usuario'] = uuidUsuario;
      // }

      // Call the RPC function
      final response = await _supabase.rpc(
        'fn_reporte_ventas_por_vendedor',
        params: params,
      );

      print('Response received: ${response?.length ?? 0} vendors');

      if (response == null) {
        print('No data received from fn_reporte_ventas_por_vendedor');
        return [];
      }

      // Convert response to SalesVendorReport objects
      final List<SalesVendorReport> reports = [];
      for (final item in response) {
        try {
          final report = SalesVendorReport.fromJson(item);
          reports.add(report);
          print(
            'Added vendor: ${report.nombreCompleto} - Total ventas: ${report.totalVentas} - Total dinero: \$${report.totalDineroGeneral}',
          );
        } catch (e) {
          print('Error parsing sales vendor report item: $e');
          print('Item data: $item');
        }
      }

      print('Successfully parsed ${reports.length} sales vendor reports');
      return reports;
    } catch (e) {
      print('Error in getSalesVendorReport: $e');
      return [];
    }
  }

  static Future<double> getTotalEgresosByVendor({
    required DateTime fechaInicio,
    required DateTime fechaFin,
    required String uuidUsuario,
  }) async {
    try {
      final deliveries = await getCashDeliveries(
        fechaInicio: fechaInicio,
        fechaFin: fechaFin,
        uuidUsuario: uuidUsuario,
      );

      double totalEgresos = 0.0;
      for (final delivery in deliveries) {
        totalEgresos += delivery.montoEntrega;
      }

      print('Total egresos for user $uuidUsuario: \$${totalEgresos.toStringAsFixed(2)}');
      return totalEgresos;
    } catch (e) {
      print('Error calculating total egresos for vendor: $e');
      return 0.0;
    }
  }
}

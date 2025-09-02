import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';

class SellerSalesReport {
  final String uuidUsuario;
  final String nombres;
  final String apellidos;
  final String nombreCompleto;
  final int totalVentas;
  final double totalProductosVendidos;
  final double totalDineroEfectivo;
  final double totalDineroTransferencia;
  final double totalDineroGeneral;
  final double totalImporteVentas;
  final int productosDiferentesVendidos;
  final DateTime primeraVenta;
  final DateTime ultimaVenta;

  SellerSalesReport({
    required this.uuidUsuario,
    required this.nombres,
    required this.apellidos,
    required this.nombreCompleto,
    required this.totalVentas,
    required this.totalProductosVendidos,
    required this.totalDineroEfectivo,
    required this.totalDineroTransferencia,
    required this.totalDineroGeneral,
    required this.totalImporteVentas,
    required this.productosDiferentesVendidos,
    required this.primeraVenta,
    required this.ultimaVenta,
  });

  factory SellerSalesReport.fromJson(Map<String, dynamic> json) {
    return SellerSalesReport(
      uuidUsuario: json['uuid_usuario'] ?? '',
      nombres: json['nombres'] ?? '',
      apellidos: json['apellidos'] ?? '',
      nombreCompleto: json['nombre_completo'] ?? '',
      totalVentas: json['total_ventas'] ?? 0,
      totalProductosVendidos:
          (json['total_productos_vendidos'] ?? 0.0).toDouble(),
      totalDineroEfectivo: (json['total_dinero_efectivo'] ?? 0.0).toDouble(),
      totalDineroTransferencia:
          (json['total_dinero_transferencia'] ?? 0.0).toDouble(),
      totalDineroGeneral: (json['total_dinero_general'] ?? 0.0).toDouble(),
      totalImporteVentas: (json['total_importe_ventas'] ?? 0.0).toDouble(),
      productosDiferentesVendidos: json['productos_diferentes_vendidos'] ?? 0,
      primeraVenta: DateTime.parse(
        json['primera_venta'] ?? DateTime.now().toIso8601String(),
      ),
      ultimaVenta: DateTime.parse(
        json['ultima_venta'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }
}

class SellerSalesService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Obtiene las ventas del vendedor actual para el período especificado
  static Future<SellerSalesReport?> getCurrentSellerSales({
    DateTime? fechaDesde,
    DateTime? fechaHasta,
  }) async {
    try {
      // Obtener datos del vendedor actual
      final userPrefs = UserPreferencesService();
      final workerProfile = await userPrefs.getWorkerProfile();
      final idTienda = await userPrefs.getIdTienda();
      final userid = await userPrefs.getUserId();
      print(' id $idTienda userid $userid');

      // if (workerProfile == null || workerProfile['uuid'] == null || idTienda == null) {
      //   print('❌ No se pudo obtener UUID del vendedor o ID de tienda');
      //   return null;
      // }

      // final uuidVendedor = workerProfile['uuid'] as String;

      print('🔍 Calling fn_reporte_ventas_por_vendedor for current seller:');
      // print('- p_uuid_usuario: $uuidVendedor');
      final today = DateTime.now();
      final formattedDate = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
      
      print('- p_id_tienda: $idTienda');
      print('- p_fecha_desde: $formattedDate');
      print('- p_fecha_hasta: $formattedDate');

      // Preparar parámetros
      final Map<String, dynamic> params = {
        'p_uuid_usuario': userid,
        'p_id_tienda': idTienda,
      };

      // final today = DateTime.now();
      // final formattedDate = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
      // // if (fechaDesde != null) {
        params['p_fecha_desde'] = '$formattedDate 00:00:00';
      // }
      // if (fechaHasta != null) {
        params['p_fecha_hasta'] = '$formattedDate 23:59:59';
      // }

      // Llamar a la función RPC
      final response = await _supabase.rpc(
        'fn_reporte_ventas_por_vendedor',
        params: params,
      );

      print('📊 Response received: ${response?.length ?? 0} records');

      if (response == null || response.isEmpty) {
        print('ℹ️ No sales data found for current seller');
        return null;
      }

      // Tomar el primer resultado (debería ser único para el vendedor actual)
      final salesData = response[0] as Map<String, dynamic>;
      final report = SellerSalesReport.fromJson(salesData);

      print('✅ Sales report for ${report.nombreCompleto}:');
      print('- Total ventas: ${report.totalVentas}');
      print('- Total dinero: \$${report.totalDineroGeneral}');
      print('- Productos vendidos: ${report.totalProductosVendidos}');

      return report;
    } catch (e) {
      print('❌ Error in getCurrentSellerSales: $e');
      return null;
    }
  }

  /// Obtiene las ventas del día actual (00:00:00 a 23:59:59)
  static Future<SellerSalesReport?> getTodaySales() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

    return await getCurrentSellerSales(
      fechaDesde: startOfDay,
      fechaHasta: endOfDay,
    );
  }

  /// Obtiene las ventas de esta semana (lunes 00:00:00 a domingo 23:59:59)
  static Future<SellerSalesReport?> getThisWeekSales() async {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startOfWeekDay = DateTime(
      startOfWeek.year,
      startOfWeek.month,
      startOfWeek.day,
      0,
      0,
      0,
    );
    final endOfWeekDay = startOfWeekDay.add(const Duration(days: 6));
    final endOfWeek = DateTime(
      endOfWeekDay.year,
      endOfWeekDay.month,
      endOfWeekDay.day,
      23,
      59,
      59,
    );

    return await getCurrentSellerSales(
      fechaDesde: startOfWeekDay,
      fechaHasta: endOfWeek,
    );
  }

  /// Obtiene las ventas de este mes (día 1 00:00:00 a último día 23:59:59)
  static Future<SellerSalesReport?> getThisMonthSales() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1, 0, 0, 0);
    final lastDayOfMonth = DateTime(now.year, now.month + 1, 0);
    final endOfMonth = DateTime(
      lastDayOfMonth.year,
      lastDayOfMonth.month,
      lastDayOfMonth.day,
      23,
      59,
      59,
    );

    return await getCurrentSellerSales(
      fechaDesde: startOfMonth,
      fechaHasta: endOfMonth,
    );
  }
}

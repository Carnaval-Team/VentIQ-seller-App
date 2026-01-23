import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';
import '../models/sales.dart';

class VendorOrder {
  final int idOperacion;
  final String tipoOperacion;
  final int idTienda;
  final String tiendaNombre;
  final int idTpv;
  final String tpvNombre;
  final String usuarioNombre;
  final int estado;
  final String estadoNombre;
  final DateTime fechaOperacion;
  final double totalOperacion;
  final int cantidadItems;
  final String? observaciones;
  final Map<String, dynamic> detalles;

  VendorOrder({
    required this.idOperacion,
    required this.tipoOperacion,
    required this.idTienda,
    required this.tiendaNombre,
    required this.idTpv,
    required this.tpvNombre,
    required this.usuarioNombre,
    required this.estado,
    required this.estadoNombre,
    required this.fechaOperacion,
    required this.totalOperacion,
    required this.cantidadItems,
    this.observaciones,
    required this.detalles,
  });

  factory VendorOrder.fromJson(Map<String, dynamic> json) {
    return VendorOrder(
      idOperacion: json['id_operacion'] ?? 0,
      tipoOperacion: json['tipo_operacion'] ?? '',
      idTienda: json['id_tienda'] ?? 0,
      tiendaNombre: json['tienda_nombre'] ?? '',
      idTpv: json['id_tpv'] ?? 0,
      tpvNombre: json['tpv_nombre'] ?? '',
      usuarioNombre: json['usuario_nombre'] ?? '',
      estado: json['estado'] ?? 0,
      estadoNombre: json['estado_nombre'] ?? '',
      fechaOperacion: DateTime.parse(json['fecha_operacion']),
      totalOperacion: (json['total_operacion'] ?? 0).toDouble(),
      cantidadItems: json['cantidad_items'] ?? 0,
      observaciones: json['observaciones'],
      detalles: json['detalles'] ?? {},
    );
  }
}

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
  final double precioCostoUsd;
  final double gananciaUsd;
  final double gananciaCup;
  final double ganancia;
  final double porcGananciaCup;
  final double porGananciaUsd;

  ProductAnalysis({
    required this.idTienda,
    required this.idProducto,
    required this.nombreProducto,
    required this.precioVentaCup,
    required this.precioCosto,
    required this.valorUsd,
    required this.precioCostoCup,
    required this.precioCostoUsd,
    required this.gananciaUsd,
    required this.gananciaCup,
    required this.porcGananciaCup,
    required this.porGananciaUsd,
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
      precioCostoUsd: (json['precio_costo_usd'] ?? 0).toDouble(),
      gananciaUsd: (json['ganancia_usd'] ?? 0).toDouble(),
      gananciaCup: (json['ganancia_cup'] ?? 0).toDouble(),
      porcGananciaCup: (json['porcentaje_ganancia_cup'] ?? 0).toDouble(),
      porGananciaUsd: (json['porcentaje_ganancia_usd'] ?? 0).toDouble(),
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

class SupplierSalesReport {
  final int idProveedor;
  final String nombreProveedor;
  final double totalVentas;
  final double totalCosto;
  final double totalGanancia;
  final double cantidadProductos;
  final double margenPorcentaje;

  SupplierSalesReport({
    required this.idProveedor,
    required this.nombreProveedor,
    required this.totalVentas,
    required this.totalCosto,
    required this.totalGanancia,
    required this.cantidadProductos,
    required this.margenPorcentaje,
  });

  factory SupplierSalesReport.fromJson(Map<String, dynamic> json) {
    return SupplierSalesReport(
      idProveedor: json['id_proveedor'] ?? 0,
      nombreProveedor: json['nombre_proveedor'] ?? 'Sin Proveedor',
      totalVentas: (json['total_ventas'] ?? 0).toDouble(),
      totalCosto: (json['total_costo'] ?? 0).toDouble(),
      totalGanancia: (json['total_ganancia'] ?? 0).toDouble(),
      cantidadProductos: (json['cantidad_productos'] ?? 0).toDouble(),
      margenPorcentaje: (json['margen_porcentaje'] ?? 0).toDouble(),
    );
  }
}

class ProductSalesWithSupplier {
  final int idTienda;
  final int idProducto;
  final String nombreProducto;
  final int idProveedor;
  final String nombreProveedor;
  final double precioVentaCup;
  final double precioCosto;
  final double valorUsd;
  final double precioCostoCup;
  final double totalVendido;
  final double ingresosTotales;
  final double costoTotalVendido;
  final double gananciaUnitaria;
  final double gananciaTotal;

  ProductSalesWithSupplier({
    required this.idTienda,
    required this.idProducto,
    required this.nombreProducto,
    required this.idProveedor,
    required this.nombreProveedor,
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

  factory ProductSalesWithSupplier.fromJson(Map<String, dynamic> json) {
    return ProductSalesWithSupplier(
      idTienda: json['id_tienda'] ?? 0,
      idProducto: json['id_producto'] ?? 0,
      nombreProducto: json['nombre_producto'] ?? '',
      idProveedor: json['id_proveedor'] ?? 0,
      nombreProveedor: json['nombre_proveedor'] ?? 'Sin Proveedor',
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
      // ✅ CAMBIO: Usar fn_reporte_ventas_gananciasv5_por_presentacion que agrupa por producto-presentación
      // y usa precio_promedio de app_dat_producto_presentacion como costo real
      final response = await _supabase.rpc(
        'fn_reporte_ventas_gananciasv5',
        params: params,
      );

      print('Response ventas received: ${response.length} products');
      print('${response}');

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

      /*if (fechaDesde != null) {
        params['p_fecha_desde'] = fechaDesde.toIso8601String().split('T')[0];
      }
      if (fechaHasta != null) {
        params['p_fecha_hasta'] = fechaHasta.toIso8601String().split('T')[0];
      }*/

      print('Final params: $params');

      // Call the RPC function
      final response = await _supabase.rpc(
        'fn_vista_precios_productos3',
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

  static Future<List<VendorOrder>> getVendorOrders({
    required DateTime fechaDesde,
    required DateTime fechaHasta,
    required String uuidUsuario,
  }) async {
    try {
      // Get store ID from preferences
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      if (idTienda == null) {
        print('Error: No se pudo obtener el ID de tienda');
        return [];
      }

      print('Calling listar_ordenes for vendor orders with:');
      print('- id_tienda_param: $idTienda');
      print('- fecha_desde_param: $fechaDesde');
      print('- fecha_hasta_param: $fechaHasta');
      print('- id_usuario_param: $uuidUsuario');

      final rpcParams = {
        'con_inventario_param': false,
        'fecha_desde_param': fechaDesde.toIso8601String().split('T')[0],
        'fecha_hasta_param': fechaHasta.toIso8601String().split('T')[0],
        'id_estado_param': null, // Todos los estados
        'id_tienda_param': idTienda,
        'id_tipo_operacion_param': null, // Todas las operaciones
        'id_tpv_param': null,
        'id_usuario_param': uuidUsuario,
        'limite_param': null,
        'pagina_param': null,
        'solo_pendientes_param': false,
      };

      final response = await _supabase.rpc(
        'listar_ordenes',
        params: rpcParams,
      );

      print('Response received: ${response?.length ?? 0} orders');

      if (response == null) {
        print('No data received from listar_ordenes');
        return [];
      }

      // Convert response to VendorOrder objects and filter by tipo_operacion
      final List<VendorOrder> orders = [];
      for (final item in response) {
        try {
          final order = VendorOrder.fromJson(item);
          
          // Filter only orders that contain "Venta" in tipo_operacion
          final tipoOperacion = item['tipo_operacion']?.toString() ?? '';
          if (tipoOperacion.toLowerCase().contains('venta')) {
            orders.add(order);
            print(
              'Added order: #${order.idOperacion} - Total: \$${order.totalOperacion} - Items: ${order.cantidadItems} - Tipo: $tipoOperacion',
            );
          } else {
            print('Filtered out order #${order.idOperacion} - Tipo: $tipoOperacion (not a Venta)');
          }
        } catch (e) {
          print('Error parsing order: $e');
          print('Item data: $item');
        }
      }

      return orders;
    } catch (e) {
      print('Error in getVendorOrders: $e');
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

  static Future<List<SupplierSalesReport>> getSupplierSalesReport({
    DateTime? fechaDesde,
    DateTime? fechaHasta,
  }) async {
    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      if (idTienda == null) return [];

      final Map<String, dynamic> params = {'p_id_tienda': idTienda};

      if (fechaDesde != null) {
        params['p_fecha_desde'] = fechaDesde.toIso8601String().split('T')[0];
      }
      if (fechaHasta != null) {
        params['p_fecha_hasta'] = fechaHasta.toIso8601String().split('T')[0];
      }

      final response = await _supabase.rpc(
        'fn_reporte_ventas_proveedor',
        params: params,
      );

      print('DEBUG - Supplier Report Response: $response');

      if (response == null) return [];

      return (response as List)
          .map((item) => SupplierSalesReport.fromJson(item))
          .toList();
    } catch (e) {
      print('Error in getSupplierSalesReport: $e');
      return [];
    }
  }
  static Future<List<ProductSalesWithSupplier>> getProductSalesWithSupplier({
    DateTime? fechaDesde,
    DateTime? fechaHasta,
    int? idAlmacen,
  }) async {
    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      if (idTienda == null) return [];

      final Map<String, dynamic> params = {'p_id_tienda': idTienda};

      if (fechaDesde != null) {
        params['p_fecha_desde'] = fechaDesde.toIso8601String().split('T')[0];
      }
      if (fechaHasta != null) {
        params['p_fecha_hasta'] = fechaHasta.toIso8601String().split('T')[0];
      }
      if (idAlmacen != null) {
        params['p_id_almacen'] = idAlmacen;
      }

      final response = await _supabase.rpc(
        'fn_reporte_ventas_con_proveedor2',
        params: params,
      );

      print('DEBUG - Detailed Supplier Report Response: $response');

      if (response == null) return [];

      return (response as List)
          .map((item) => ProductSalesWithSupplier.fromJson(item))
          .toList();
    } catch (e) {
      print('Error in getProductSalesWithSupplier: $e');
      return [];
    }
  }

  static Future<List<ProductSalesWithSupplier>> getSupplierProductReport({
    required int idProveedor,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
    int? idAlmacen,
  }) async {
    try {
      // Obtener el reporte general de productos con proveedor
      final allProducts = await getProductSalesWithSupplier(
        fechaDesde: fechaDesde,
        fechaHasta: fechaHasta,
        idAlmacen: idAlmacen,
      );

      // Filtrar por proveedor
      final supplierProducts = allProducts
          .where((product) => product.idProveedor == idProveedor)
          .toList();

      print('DEBUG - Supplier Product Report: ${supplierProducts.length} productos para proveedor $idProveedor');

      return supplierProducts;
    } catch (e) {
      print('Error in getSupplierProductReport: $e');
      return [];
    }
  }
}

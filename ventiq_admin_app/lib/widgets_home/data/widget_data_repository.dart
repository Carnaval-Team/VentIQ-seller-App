import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/sales.dart';
import '../../services/currency_service.dart';
import '../../services/dashboard_service.dart';
import '../../services/product_service.dart';
import '../../services/sales_service.dart';
import '../models/widget_config.dart';
import '../widget_keys.dart';

/// Snapshot listo para volcar a las preferencias que leen los widgets nativos.
///
/// El mapa `values` usa claves ya compuestas (`<prefijo>_<id>_<campo>`) y todos
/// los valores son String: es el contrato acordado con Kotlin (ver WidgetKeys).
class WidgetSnapshot {
  const WidgetSnapshot({required this.values, this.error});

  final Map<String, String> values;
  final String? error;

  bool get isError => error != null;
}

/// Construye los snapshots de los tres widgets reutilizando exclusivamente los
/// servicios y RPCs que ya consumen DashboardScreen, SalesScreen y
/// ProductDetailScreen. No hay endpoints nuevos.
class WidgetDataRepository {
  const WidgetDataRepository();

  /// Mini Dashboard.
  ///
  /// - `fn_dashboard_analisis_tienda` (vía [DashboardService.getStoreAnalysis]):
  ///   gastos, órdenes y la serie `tendencias_de_venta` ya transformada.
  /// - `fn_reporte_ventas_con_proveedor4` (vía
  ///   [SalesService.getProductSalesReport]): ganancia real por costo de
  ///   producto, para calcular la ganancia neta = ganancia bruta − gastos.
  Future<WidgetSnapshot> buildMiniDashboard(WidgetConfig config) async {
    final periodo = config.periodo ?? '1 mes';
    final storeId = config.storeId;
    if (storeId == null) {
      return const WidgetSnapshot(values: {}, error: 'Sin tienda seleccionada');
    }

    try {
      final analysis = await DashboardService.getStoreAnalysis(
        periodo: periodo,
        storeId: storeId,
      );

      final gastos = _toDouble(analysis['totalExpenses']);
      final ordenes = _toDouble(analysis['totalOrders']).toInt();
      final deltaPct = _toDouble(analysis['salesChange']);

      // La serie que dibuja el Dashboard son FlSpot; se extrae solo la Y.
      final trend = _extractTrend(analysis['salesData']);
      final labels = (analysis['salesLabels'] as List?)
              ?.map((label) => label.toString())
              .toList() ??
          const <String>[];

      // Ganancia bruta del periodo (opción 1-b acordada): suma de
      // `ganancia_total` del reporte de ventas con proveedor.
      final range = _rangeForPeriodo(periodo);
      double gananciaBruta = 0.0;
      try {
        final reports = await SalesService.getProductSalesReport(
          fechaDesde: range.desde,
          fechaHasta: range.hasta,
          storeId: storeId,
        );
        for (final report in reports) {
          gananciaBruta += report.gananciaTotal;
        }
      } catch (error) {
        // Si el reporte de ganancias falla, se degrada a ventas − gastos en
        // lugar de dejar el widget vacío.
        debugPrint('⚠️ Widget: ganancia por producto no disponible: $error');
        gananciaBruta = _toDouble(analysis['totalSales']);
      }

      final gananciaNeta = gananciaBruta - gastos;

      return WidgetSnapshot(
        values: {
          WidgetKeys.fieldPeriodo: periodo,
          WidgetKeys.fieldVentas: _money(_toDouble(analysis['totalSales'])),
          WidgetKeys.fieldGastos: _money(gastos),
          WidgetKeys.fieldGananciaNeta: _money(gananciaNeta),
          WidgetKeys.fieldOrdenes: ordenes.toString(),
          WidgetKeys.fieldDeltaPct: _money(deltaPct),
          WidgetKeys.fieldTrend:
              trend.map(_money).join(WidgetKeys.seriesSeparator),
          WidgetKeys.fieldTrendLabels:
              labels.join(WidgetKeys.seriesSeparator),
        },
      );
    } catch (error) {
      return WidgetSnapshot(values: const {}, error: _humanize(error));
    }
  }

  /// Sales / TPV.
  ///
  /// `fn_reporte_ventas_por_vendedor_sch` para los totales y el desglose, más
  /// `fn_listar_entregas_por_fechas_usuario` (vía
  /// [SalesService.getTotalEgresosByVendor]) para los egresos de cada vendedor,
  /// igual que hace la pestaña TPVs de SalesScreen.
  Future<WidgetSnapshot> buildSales(WidgetConfig config) async {
    final storeId = config.storeId;
    if (storeId == null) {
      return const WidgetSnapshot(values: {}, error: 'Sin tienda seleccionada');
    }

    final range = config.resolveRange();
    final isRealtime = config.modo != WidgetKeys.modoRange;

    try {
      final reports = await SalesService.getSalesVendorReport(
        fechaDesde: range.desde,
        fechaHasta: range.hasta,
        storeId: storeId,
      );

      // Egresos por vendedor: el RPC de vendedores no siempre los trae, la app
      // los completa con las entregas de efectivo.
      final enriched = <SalesVendorReport>[];
      for (final report in reports) {
        if (report.totalEgresos > 0) {
          enriched.add(report);
          continue;
        }
        try {
          final egresos = await SalesService.getTotalEgresosByVendor(
            fechaInicio: range.desde,
            fechaFin: range.hasta,
            uuidUsuario: report.uuidUsuario,
          );
          enriched.add(report.copyWith(totalEgresos: egresos));
        } catch (_) {
          enriched.add(report);
        }
      }

      // Solo vendedores con movimiento, ordenados por importe (como la app).
      final visible = enriched
          .where((report) => report.totalDineroGeneral > 0)
          .toList()
        ..sort(
          (a, b) => b.totalDineroGeneral.compareTo(a.totalDineroGeneral),
        );

      double total = 0.0;
      double efectivo = 0.0;
      double transferencia = 0.0;
      double egresos = 0.0;
      for (final report in visible) {
        total += report.totalDineroGeneral;
        efectivo += report.totalDineroEfectivo;
        transferencia += report.totalDineroTransferencia;
        egresos += report.totalEgresos;
      }

      final breakdown = visible
          .map(
            (report) => {
              'nombre': report.nombreCompleto.isEmpty
                  ? 'Sin nombre'
                  : report.nombreCompleto,
              'total': report.totalDineroGeneral,
              'efectivo': report.totalDineroEfectivo,
              'transferencia': report.totalDineroTransferencia,
              'egresos': report.totalEgresos,
              'ventas': report.totalVentas,
            },
          )
          .toList();

      return WidgetSnapshot(
        values: {
          WidgetKeys.fieldModo:
              isRealtime ? WidgetKeys.modoRealtime : WidgetKeys.modoRange,
          WidgetKeys.fieldDesde: _isoDate(range.desde),
          WidgetKeys.fieldHasta: _isoDate(range.hasta),
          WidgetKeys.fieldTotal: _money(total),
          WidgetKeys.fieldEfectivo: _money(efectivo),
          WidgetKeys.fieldTransferencia: _money(transferencia),
          WidgetKeys.fieldEgresos: _money(egresos),
          WidgetKeys.fieldTpvs: jsonEncode(breakdown),
          WidgetKeys.fieldExpanded: config.expanded ? '1' : '0',
        },
      );
    } catch (error) {
      return WidgetSnapshot(values: const {}, error: _humanize(error));
    }
  }

  /// Product Tracking.
  ///
  /// - `fn_vista_precios_productos3` → precio de venta y costos CUP/USD.
  /// - `fn_reporte_ventas_con_proveedor4` → unidades vendidas e ingresos.
  /// - `fn_listar_inventario_productos_paged2` → stock actual por ubicación.
  Future<WidgetSnapshot> buildProduct(WidgetConfig config) async {
    final productoId = config.productoId;
    final storeId = config.storeId;
    if (storeId == null || productoId == null) {
      return const WidgetSnapshot(values: {}, error: 'Sin producto seleccionado');
    }

    try {
      final analyses = await SalesService.getProductAnalysis(storeId: storeId);
      final analysis = analyses.firstWhere(
        (item) => item.idProducto == productoId,
        orElse: () => throw StateError('Producto no encontrado en precios'),
      );

      // Ventas: sin rango explícito el RPC devuelve el histórico completo,
      // que es lo que muestra ProductDetailScreen como "total de ventas".
      double vendido = 0.0;
      double ingresos = 0.0;
      try {
        final reports = await SalesService.getProductSalesReport(
          storeId: storeId,
        );
        for (final report in reports) {
          if (report.idProducto != productoId) continue;
          vendido += report.totalVendido;
          ingresos += report.ingresosTotales;
        }
      } catch (error) {
        debugPrint('⚠️ Widget: ventas del producto no disponibles: $error');
      }

      // Stock en tiempo real: suma de las ubicaciones.
      double stock = 0.0;
      try {
        final locations = await ProductService.getProductStockLocations(
          productoId.toString(),
          storeId: storeId,
        );
        for (final location in locations) {
          stock += _toDouble(location['cantidad']);
        }
      } catch (error) {
        debugPrint('⚠️ Widget: stock del producto no disponible: $error');
      }

      return WidgetSnapshot(
        values: {
          WidgetKeys.fieldProductoId: productoId.toString(),
          WidgetKeys.fieldProductoNombre: analysis.nombreProducto.isEmpty
              ? (config.productoNombre ?? 'Producto')
              : analysis.nombreProducto,
          WidgetKeys.fieldPrecioVenta: _money(analysis.precioVentaCup),
          WidgetKeys.fieldCostoCup: _money(analysis.precioCostoCup),
          WidgetKeys.fieldCostoUsd: _money(analysis.precioCostoUsd),
          WidgetKeys.fieldTotalVendido: _money(vendido),
          WidgetKeys.fieldIngresos: _money(ingresos),
          WidgetKeys.fieldStock: _money(stock),
        },
      );
    } catch (error) {
      return WidgetSnapshot(values: const {}, error: _humanize(error));
    }
  }

  /// Tasa USD→CUP efectiva; la comparten los tres widgets.
  Future<double> fetchUsdRate() async {
    try {
      return await CurrencyService.getEffectiveUsdToCupRate();
    } catch (error) {
      debugPrint('⚠️ Widget: tasa USD no disponible: $error');
      return 0.0;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Extrae los valores Y de la lista de FlSpot que produce DashboardService.
  static List<double> _extractTrend(Object? salesData) {
    if (salesData is! List) return const [];
    final values = <double>[];
    for (final spot in salesData) {
      try {
        // FlSpot expone `y`; se accede dinámicamente para no importar fl_chart
        // en la capa de datos de los widgets.
        final dynamic dynamicSpot = spot;
        values.add(_toDouble(dynamicSpot.y));
      } catch (_) {
        // Ignora puntos con forma inesperada.
      }
    }
    return values;
  }

  /// Traduce el periodo del Dashboard a un rango de fechas concreto, con la
  /// misma semántica que usa el RPC de análisis.
  static ({DateTime desde, DateTime hasta}) _rangeForPeriodo(String periodo) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final hasta = today
        .add(const Duration(days: 1))
        .subtract(const Duration(seconds: 1));

    final desde = switch (periodo) {
      'Día' => today,
      'Semana' => today.subtract(Duration(days: now.weekday - 1)),
      '1 mes' => DateTime(now.year, now.month, 1),
      '3 meses' => DateTime(now.year, now.month - 2, 1),
      '6 meses' => DateTime(now.year, now.month - 5, 1),
      '1 año' => DateTime(now.year, 1, 1),
      '3 años' => DateTime(now.year - 2, 1, 1),
      _ => DateTime(now.year, now.month, 1),
    };

    return (desde: desde, hasta: hasta);
  }

  static double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  /// Serializa con 2 decimales: suficiente para dinero y evita notación
  /// científica al pasar por SharedPreferences.
  static String _money(double value) => value.toStringAsFixed(2);

  static String _isoDate(DateTime date) =>
      date.toIso8601String().split('T').first;

  static String _humanize(Object error) {
    final text = error.toString();
    if (text.contains('permisos')) return 'Sin permisos para esta tienda';
    if (text.contains('SocketException') || text.contains('Failed host')) {
      return 'Sin conexión';
    }
    if (text.length > 90) return '${text.substring(0, 87)}…';
    return text;
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ConsignacionMovimientosService {
  static final _supabase = Supabase.instance.client;

  /// Obtener movimientos de productos en consignación
  /// 
  /// Parámetros:
  /// - idContrato: ID del contrato de consignación
  /// - fechaDesde: Fecha inicial (opcional)
  /// - fechaHasta: Fecha final (opcional)
  static Future<List<Map<String, dynamic>>> getMovimientosConsignacion({
    required int idContrato,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
  }) async {
    try {
      debugPrint('📊 Obteniendo movimientos para contrato: $idContrato');

      final response = await _supabase.rpc(
        'get_movimientos_consignacion',
        params: {
          'p_id_contrato': idContrato,
          'p_fecha_desde': fechaDesde?.toIso8601String(),
          'p_fecha_hasta': fechaHasta?.toIso8601String(),
        },
      ) as List;

      debugPrint('✅ Movimientos obtenidos: ${response.length}');

      return response
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (e) {
      debugPrint('❌ Error obteniendo movimientos: $e');
      return [];
    }
  }

  /// Obtener resumen de ventas por producto en consignación
  /// 
  /// Parámetros:
  /// - idContrato: ID del contrato de consignación
  /// - fechaDesde: Fecha inicial (opcional)
  /// - fechaHasta: Fecha final (opcional)
  static Future<List<Map<String, dynamic>>> getResumenVentasConsignacion({
    required int idContrato,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
  }) async {
    try {
      debugPrint('📊 Obteniendo resumen de ventas para contrato: $idContrato');

      final response = await _supabase.rpc(
        'get_resumen_ventas_consignacion',
        params: {
          'p_id_contrato': idContrato,
          'p_fecha_desde': fechaDesde?.toIso8601String(),
          'p_fecha_hasta': fechaHasta?.toIso8601String(),
        },
      ) as List;

      debugPrint('✅ Resumen obtenido: ${response.length} productos');

      return response
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (e) {
      debugPrint('❌ Error obteniendo resumen de ventas: $e');
      return [];
    }
  }

  /// Obtener movimientos detallados con información de operación
  /// 
  /// Parámetros:
  /// - idContrato: ID del contrato de consignación
  /// - fechaDesde: Fecha inicial (opcional)
  /// - fechaHasta: Fecha final (opcional)
  static Future<List<Map<String, dynamic>>> getMovimientosDetallado({
    required int idContrato,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
  }) async {
    try {
      debugPrint('📊 Obteniendo movimientos detallados para contrato: $idContrato');

      final response = await _supabase.rpc(
        'get_movimientos_consignacion_detallado',
        params: {
          'p_id_contrato': idContrato,
          'p_fecha_desde': fechaDesde?.toIso8601String(),
          'p_fecha_hasta': fechaHasta?.toIso8601String(),
        },
      ) as List;

      debugPrint('✅ Movimientos detallados obtenidos: ${response.length}');

      return response
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (e) {
      debugPrint('❌ Error obteniendo movimientos detallados: $e');
      return [];
    }
  }

  /// Obtener estadísticas de ventas para un contrato
  /// 
  /// Retorna: {
  ///   totalProductos: int,
  ///   totalEnviado: double,
  ///   totalVendido: double,
  ///   totalDevuelto: double,
  ///   totalPendiente: double,
  ///   totalMovimientos: int,
  ///   totalVentas: int,
  /// }
  static Future<Map<String, dynamic>> getEstadisticasVentas({
    required int idContrato,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
  }) async {
    try {
      final response = await _supabase.rpc(
        'get_estadisticas_ventas_consignacion',
        params: {
          'p_id_contrato': idContrato,
          'p_fecha_desde': fechaDesde?.toIso8601String(),
          'p_fecha_hasta': fechaHasta?.toIso8601String(),
        },
      );

      if (response == null || (response is List && response.isEmpty)) {
        return {
          'totalEnviado': 0,
          'totalVendido': 0,
          'totalDevuelto': 0,
          'totalPendiente': 0,
          'totalOperaciones': 0,
          'totalMontoVentas': 0,
          'promedioVenta': 0,
        };
      }

      final stats = (response is List ? response[0] : response) as Map<String, dynamic>;

      return {
        'totalEnviado': stats['total_enviado'] ?? 0,
        'totalVendido': stats['total_vendido'] ?? 0,
        'totalDevuelto': stats['total_devuelto'] ?? 0,
        'totalPendiente': stats['total_pendiente'] ?? 0,
        'totalOperaciones': stats['total_operaciones'] ?? 0,
        'totalMontoVentas': stats['total_monto_ventas'] ?? 0,
        'promedioVenta': stats['promedio_venta'] ?? 0,
      };
    } catch (e) {
      debugPrint('❌ Error obteniendo estadísticas: $e');
      return {};
    }
  }

  /// Obtener movimientos filtrados por motivo de extracción
  /// 
  /// idMotivoExtraccion: ID del motivo de extracción (11-20 para ventas)
  static Future<List<Map<String, dynamic>>> getMovimientosPorMotivo({
    required int idContrato,
    required int idMotivoExtraccion,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
  }) async {
    try {
      debugPrint('📊 Obteniendo movimientos con motivo $idMotivoExtraccion para contrato: $idContrato');

      final movimientos = await getMovimientosConsignacion(
        idContrato: idContrato,
        fechaDesde: fechaDesde,
        fechaHasta: fechaHasta,
      );

      final filtrados = movimientos
          .where((m) => m['id_motivo_extraccion'] == idMotivoExtraccion)
          .toList();

      debugPrint('✅ Movimientos filtrados: ${filtrados.length}');

      return filtrados;
    } catch (e) {
      debugPrint('❌ Error filtrando movimientos: $e');
      return [];
    }
  }

  /// Obtener solo operaciones de venta (motivos 11-20)
  static Future<List<Map<String, dynamic>>> getOperacionesVenta({
    required int idContrato,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
  }) async {
    try {
      debugPrint('📊 Obteniendo operaciones de venta para contrato: $idContrato');

      final movimientos = await getMovimientosConsignacion(
        idContrato: idContrato,
        fechaDesde: fechaDesde,
        fechaHasta: fechaHasta,
      );

      // Las operaciones ya están filtradas por motivos 11-20 en SQL
      debugPrint('✅ Operaciones de venta obtenidas: ${movimientos.length}');

      return movimientos;
    } catch (e) {
      debugPrint('❌ Error obteniendo operaciones de venta: $e');
      return [];
    }
  }
}

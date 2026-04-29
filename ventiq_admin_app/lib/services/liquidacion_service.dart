import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Servicio para gestionar liquidaciones de consignación
/// Permite crear, listar, confirmar, rechazar y cancelar liquidaciones
class LiquidacionService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Crear nueva liquidación (solo consignatario)
  /// Recibe monto en CUP, tasa USD→CUP de CurrencyService, y calcula monto USD
  static Future<Map<String, dynamic>> crearLiquidacion({
    required int contratoId,
    required double montoCup,
    required double tasaUsdCup,
    String? observaciones,
  }) async {
    try {
      debugPrint('💰 Creando liquidación para contrato $contratoId...');
      debugPrint('   Monto CUP: \$${montoCup.toStringAsFixed(2)}');
      debugPrint('   Tasa USD→CUP: $tasaUsdCup');

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Usuario no autenticado');
      }

      if (tasaUsdCup <= 0) {
        throw Exception('Tasa de cambio inválida');
      }

      final montoUsd = montoCup / tasaUsdCup;
      // tasa_cambio en la tabla se almacena como CUP→USD (inversa)
      final tasaCupUsd = 1.0 / tasaUsdCup;

      debugPrint('   Monto USD calculado: \$${montoUsd.toStringAsFixed(2)}');
      debugPrint('   Tasa CUP→USD: $tasaCupUsd');

      final response = await _supabase
          .from('app_dat_liquidacion_consignacion')
          .insert({
            'id_contrato': contratoId,
            'monto_cup': montoCup,
            'monto_usd': montoUsd,
            'tasa_cambio': tasaCupUsd,
            'estado': 0,
            'observaciones': observaciones,
            'created_by': userId,
          })
          .select()
          .single();

      debugPrint('✅ Liquidación creada exitosamente');
      debugPrint('   ID: ${response['id']}');
      debugPrint('   Monto USD: \$${response['monto_usd']}');
      debugPrint('   Tasa cambio: ${response['tasa_cambio']}');

      return response;
    } catch (e) {
      debugPrint('❌ Error creando liquidación: $e');
      rethrow;
    }
  }

  /// Listar liquidaciones de un contrato
  /// Opcionalmente filtrar por estado: 0=Pendiente, 1=Confirmada, 2=Rechazada
  static Future<List<Map<String, dynamic>>> listarLiquidaciones({
    required int contratoId,
    int? estado,
  }) async {
    try {
      debugPrint('📋 Listando liquidaciones para contrato $contratoId...');
      if (estado != null) {
        debugPrint('   Filtro estado: $estado');
      }

      var query = _supabase
          .from('app_dat_liquidacion_consignacion')
          .select('*')
          .eq('id_contrato', contratoId);

      if (estado != null) {
        query = query.eq('estado', estado);
      }

      final response = await query.order('fecha_liquidacion', ascending: false);

      debugPrint('✅ Liquidaciones obtenidas: ${response.length}');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error listando liquidaciones: $e');
      return [];
    }
  }

  /// Confirmar liquidación (solo consignador)
  static Future<void> confirmarLiquidacion({
    required int liquidacionId,
    String? observaciones,
  }) async {
    try {
      debugPrint('✅ Confirmando liquidación $liquidacionId...');

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Usuario no autenticado');
      }

      await _supabase.rpc(
        'fn_confirmar_liquidacion',
        params: {
          'p_liquidacion_id': liquidacionId,
          'p_confirmed_by': userId,
          'p_observaciones': observaciones,
        },
      );

      debugPrint('✅ Liquidación confirmada exitosamente');
    } catch (e) {
      debugPrint('❌ Error confirmando liquidación: $e');
      rethrow;
    }
  }

  /// Rechazar liquidación (solo consignador)
  static Future<void> rechazarLiquidacion({
    required int liquidacionId,
    required String motivoRechazo,
  }) async {
    try {
      debugPrint('❌ Rechazando liquidación $liquidacionId...');
      debugPrint('   Motivo: $motivoRechazo');

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Usuario no autenticado');
      }

      await _supabase.rpc(
        'fn_rechazar_liquidacion',
        params: {
          'p_liquidacion_id': liquidacionId,
          'p_confirmed_by': userId,
          'p_motivo_rechazo': motivoRechazo,
        },
      );

      debugPrint('✅ Liquidación rechazada exitosamente');
    } catch (e) {
      debugPrint('❌ Error rechazando liquidación: $e');
      rethrow;
    }
  }

  /// Cancelar liquidación (solo consignatario, solo pendientes)
  static Future<void> cancelarLiquidacion(int liquidacionId) async {
    try {
      debugPrint('🗑️ Cancelando liquidación $liquidacionId...');

      await _supabase
          .from('app_dat_liquidacion_consignacion')
          .delete()
          .eq('id', liquidacionId)
          .eq('estado', 0); // Solo pendientes

      debugPrint('✅ Liquidación cancelada exitosamente');
    } catch (e) {
      debugPrint('❌ Error cancelando liquidación: $e');
      rethrow;
    }
  }

  /// Obtener totales del contrato
  /// Retorna: monto_total del contrato y total de liquidaciones confirmadas
  static Future<Map<String, double>> obtenerTotalesContrato(int contratoId) async {
    try {
      debugPrint('📊 Obteniendo totales del contrato $contratoId...');

      // Obtener monto_total del contrato
      final contratoData = await _supabase
          .from('app_dat_contrato_consignacion')
          .select('monto_total')
          .eq('id', contratoId)
          .single();

      final montoTotal = (contratoData['monto_total'] as num?)?.toDouble() ?? 0.0;

      // Obtener suma de liquidaciones confirmadas (estado = 1)
      final liquidacionesData = await _supabase
          .from('app_dat_liquidacion_consignacion')
          .select('monto_usd')
          .eq('id_contrato', contratoId)
          .eq('estado', 1); // Solo confirmadas

      double totalLiquidaciones = 0.0;
      for (final liq in liquidacionesData) {
        totalLiquidaciones += (liq['monto_usd'] as num?)?.toDouble() ?? 0.0;
      }

      debugPrint('✅ Totales obtenidos:');
      debugPrint('   Monto total contrato: \$${montoTotal.toStringAsFixed(2)} USD');
      debugPrint('   Total liquidaciones: \$${totalLiquidaciones.toStringAsFixed(2)} USD');
      debugPrint('   Saldo pendiente: \$${(montoTotal - totalLiquidaciones).toStringAsFixed(2)} USD');

      return {
        'monto_total': montoTotal,
        'total_liquidaciones': totalLiquidaciones,
        'total_liquidado': totalLiquidaciones,
        'saldo_pendiente': montoTotal - totalLiquidaciones,
      };
    } catch (e) {
      debugPrint('❌ Error obteniendo totales: $e');
      return {
        'monto_total': 0.0,
        'total_liquidaciones': 0.0,
        'saldo_pendiente': 0.0,
      };
    }
  }

  /// Obtener estadísticas de liquidaciones por estado
  static Future<Map<String, int>> obtenerEstadisticasLiquidaciones(int contratoId) async {
    try {
      final liquidaciones = await listarLiquidaciones(contratoId: contratoId);

      int pendientes = 0;
      int confirmadas = 0;
      int rechazadas = 0;

      for (final liq in liquidaciones) {
        final estado = liq['estado'] as int;
        switch (estado) {
          case 0:
            pendientes++;
            break;
          case 1:
            confirmadas++;
            break;
          case 2:
            rechazadas++;
            break;
        }
      }

      return {
        'pendientes': pendientes,
        'confirmadas': confirmadas,
        'rechazadas': rechazadas,
        'total': liquidaciones.length,
      };
    } catch (e) {
      debugPrint('❌ Error obteniendo estadísticas: $e');
      return {
        'pendientes': 0,
        'confirmadas': 0,
        'rechazadas': 0,
        'total': 0,
      };
    }
  }
}

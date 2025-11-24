import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ConsignacionService {
  static final _supabase = Supabase.instance.client;

  // Obtener todos los contratos de consignación activos
  static Future<List<Map<String, dynamic>>> getActiveContratos() async {
    try {
      debugPrint('📋 Obteniendo contratos de consignación activos...');

      final response = await _supabase
          .from('app_dat_contrato_consignacion')
          .select('''
            id,
            id_tienda_consignadora,
            id_tienda_consignataria,
            estado,
            fecha_inicio,
            fecha_fin,
            porcentaje_comision,
            plazo_dias,
            condiciones,
            created_at,
            updated_at
          ''')
          .eq('estado', 1)
          .order('created_at', ascending: false);

      // Obtener datos de tiendas por separado
      final tiendas = await _supabase
          .from('app_dat_tienda')
          .select('id, denominacion');

      final tiendasMap = <int, String>{};
      for (var tienda in tiendas) {
        tiendasMap[tienda['id'] as int] = tienda['denominacion'] as String;
      }

      // Enriquecer respuesta con nombres de tiendas
      final enrichedResponse = response.map((contrato) {
        return {
          ...contrato,
          'app_dat_tienda!app_dat_contrato_consignacion_id_tienda_consignadora_fkey': {
            'id': contrato['id_tienda_consignadora'],
            'denominacion': tiendasMap[contrato['id_tienda_consignadora']] ?? 'Desconocida',
          },
          'app_dat_tienda!app_dat_contrato_consignacion_id_tienda_consignataria_fkey': {
            'id': contrato['id_tienda_consignataria'],
            'denominacion': tiendasMap[contrato['id_tienda_consignataria']] ?? 'Desconocida',
          },
        };
      }).toList();

      debugPrint('✅ ${enrichedResponse.length} contratos obtenidos');
      return List<Map<String, dynamic>>.from(enrichedResponse);
    } catch (e) {
      debugPrint('❌ Error obteniendo contratos: $e');
      return [];
    }
  }

  // Obtener todos los contratos (activos e inactivos)
  static Future<List<Map<String, dynamic>>> getAllContratos() async {
    try {
      debugPrint('📋 Obteniendo todos los contratos de consignación...');

      final response = await _supabase
          .from('app_dat_contrato_consignacion')
          .select('''
            id,
            id_tienda_consignadora,
            id_tienda_consignataria,
            estado,
            fecha_inicio,
            fecha_fin,
            porcentaje_comision,
            plazo_dias,
            condiciones,
            created_at,
            updated_at
          ''')
          .order('created_at', ascending: false);

      // Obtener datos de tiendas por separado
      final tiendas = await _supabase
          .from('app_dat_tienda')
          .select('id, denominacion');

      final tiendasMap = <int, String>{};
      for (var tienda in tiendas) {
        tiendasMap[tienda['id'] as int] = tienda['denominacion'] as String;
      }

      // Enriquecer respuesta con nombres de tiendas
      final enrichedResponse = response.map((contrato) {
        return {
          ...contrato,
          'app_dat_tienda!app_dat_contrato_consignacion_id_tienda_consignadora_fkey': {
            'id': contrato['id_tienda_consignadora'],
            'denominacion': tiendasMap[contrato['id_tienda_consignadora']] ?? 'Desconocida',
          },
          'app_dat_tienda!app_dat_contrato_consignacion_id_tienda_consignataria_fkey': {
            'id': contrato['id_tienda_consignataria'],
            'denominacion': tiendasMap[contrato['id_tienda_consignataria']] ?? 'Desconocida',
          },
        };
      }).toList();

      debugPrint('✅ ${enrichedResponse.length} contratos obtenidos');
      return List<Map<String, dynamic>>.from(enrichedResponse);
    } catch (e) {
      debugPrint('❌ Error obteniendo contratos: $e');
      return [];
    }
  }

  // Crear nuevo contrato de consignación
  static Future<bool> createContrato({
    required int idTiendaConsignadora,
    required int idTiendaConsignataria,
    required DateTime fechaInicio,
    DateTime? fechaFin,
    required double porcentajeComision,
    int? plazoDias,
    String? condiciones,
  }) async {
    try {
      debugPrint('➕ Creando nuevo contrato de consignación...');
      debugPrint('   Consignadora: $idTiendaConsignadora');
      debugPrint('   Consignataria: $idTiendaConsignataria');
      debugPrint('   Comisión: $porcentajeComision%');
      debugPrint('   Plazo: ${plazoDias ?? "N/A"} días');

      await _supabase.from('app_dat_contrato_consignacion').insert({
        'id_tienda_consignadora': idTiendaConsignadora,
        'id_tienda_consignataria': idTiendaConsignataria,
        'estado': 1,
        'fecha_inicio': fechaInicio.toIso8601String().split('T')[0],
        'fecha_fin': fechaFin != null ? fechaFin.toIso8601String().split('T')[0] : null,
        'porcentaje_comision': porcentajeComision,
        'plazo_dias': plazoDias,
        'condiciones': condiciones,
      });

      debugPrint('✅ Contrato creado exitosamente');
      return true;
    } catch (e) {
      debugPrint('❌ Error creando contrato: $e');
      return false;
    }
  }

  // Actualizar contrato de consignación
  static Future<bool> updateContrato({
    required int contratoId,
    DateTime? fechaFin,
    double? porcentajeComision,
    int? plazoDias,
    String? condiciones,
  }) async {
    try {
      debugPrint('✏️ Actualizando contrato ID: $contratoId');

      final updates = <String, dynamic>{};
      if (fechaFin != null) {
        updates['fecha_fin'] = fechaFin.toIso8601String().split('T')[0];
      }
      if (porcentajeComision != null) {
        updates['porcentaje_comision'] = porcentajeComision;
      }
      if (plazoDias != null) {
        updates['plazo_dias'] = plazoDias;
      }
      if (condiciones != null) {
        updates['condiciones'] = condiciones;
      }
      updates['updated_at'] = DateTime.now().toIso8601String();

      await _supabase
          .from('app_dat_contrato_consignacion')
          .update(updates)
          .eq('id', contratoId);

      debugPrint('✅ Contrato actualizado exitosamente');
      return true;
    } catch (e) {
      debugPrint('❌ Error actualizando contrato: $e');
      return false;
    }
  }

  // Desactivar contrato (cambiar estado a 0)
  static Future<bool> deactivateContrato(int contratoId) async {
    try {
      debugPrint('🔴 Desactivando contrato ID: $contratoId');

      await _supabase
          .from('app_dat_contrato_consignacion')
          .update({
            'estado': 0,
            'fecha_fin': DateTime.now().toIso8601String().split('T')[0],
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', contratoId);

      debugPrint('✅ Contrato desactivado exitosamente');
      return true;
    } catch (e) {
      debugPrint('❌ Error desactivando contrato: $e');
      return false;
    }
  }

  // Eliminar contrato
  static Future<bool> deleteContrato(int contratoId) async {
    try {
      debugPrint('🗑️ Eliminando contrato ID: $contratoId');

      await _supabase
          .from('app_dat_contrato_consignacion')
          .delete()
          .eq('id', contratoId);

      debugPrint('✅ Contrato eliminado exitosamente');
      return true;
    } catch (e) {
      debugPrint('❌ Error eliminando contrato: $e');
      return false;
    }
  }

  // Obtener contratos de una tienda específica (como consignadora)
  static Future<List<Map<String, dynamic>>> getContratosByConsignadora(
    int idTiendaConsignadora,
  ) async {
    try {
      debugPrint('📋 Obteniendo contratos de consignadora: $idTiendaConsignadora');

      final response = await _supabase
          .from('app_dat_contrato_consignacion')
          .select('''
            id,
            id_tienda_consignadora,
            id_tienda_consignataria,
            estado,
            fecha_inicio,
            fecha_fin,
            porcentaje_comision,
            plazo_dias,
            condiciones,
            created_at,
            updated_at
          ''')
          .eq('id_tienda_consignadora', idTiendaConsignadora)
          .order('created_at', ascending: false);

      // Obtener datos de tiendas por separado
      final tiendas = await _supabase
          .from('app_dat_tienda')
          .select('id, denominacion');

      final tiendasMap = <int, String>{};
      for (var tienda in tiendas) {
        tiendasMap[tienda['id'] as int] = tienda['denominacion'] as String;
      }

      // Enriquecer respuesta
      final enrichedResponse = response.map((contrato) {
        return {
          ...contrato,
          'app_dat_tienda!app_dat_contrato_consignacion_id_tienda_consignataria_fkey': {
            'id': contrato['id_tienda_consignataria'],
            'denominacion': tiendasMap[contrato['id_tienda_consignataria']] ?? 'Desconocida',
          },
        };
      }).toList();

      debugPrint('✅ ${enrichedResponse.length} contratos encontrados');
      return List<Map<String, dynamic>>.from(enrichedResponse);
    } catch (e) {
      debugPrint('❌ Error obteniendo contratos: $e');
      return [];
    }
  }

  // Obtener contratos de una tienda específica (como consignataria)
  static Future<List<Map<String, dynamic>>> getContratosByConsignataria(
    int idTiendaConsignataria,
  ) async {
    try {
      debugPrint('📋 Obteniendo contratos de consignataria: $idTiendaConsignataria');

      final response = await _supabase
          .from('app_dat_contrato_consignacion')
          .select('''
            id,
            id_tienda_consignadora,
            id_tienda_consignataria,
            estado,
            fecha_inicio,
            fecha_fin,
            porcentaje_comision,
            plazo_dias,
            condiciones,
            created_at,
            updated_at
          ''')
          .eq('id_tienda_consignataria', idTiendaConsignataria)
          .order('created_at', ascending: false);

      // Obtener datos de tiendas por separado
      final tiendas = await _supabase
          .from('app_dat_tienda')
          .select('id, denominacion');

      final tiendasMap = <int, String>{};
      for (var tienda in tiendas) {
        tiendasMap[tienda['id'] as int] = tienda['denominacion'] as String;
      }

      // Enriquecer respuesta
      final enrichedResponse = response.map((contrato) {
        return {
          ...contrato,
          'app_dat_tienda!app_dat_contrato_consignacion_id_tienda_consignadora_fkey': {
            'id': contrato['id_tienda_consignadora'],
            'denominacion': tiendasMap[contrato['id_tienda_consignadora']] ?? 'Desconocida',
          },
        };
      }).toList();

      debugPrint('✅ ${enrichedResponse.length} contratos encontrados');
      return List<Map<String, dynamic>>.from(enrichedResponse);
    } catch (e) {
      debugPrint('❌ Error obteniendo contratos: $e');
      return [];
    }
  }

  // Verificar si existe un contrato activo entre dos tiendas
  static Future<bool> existsActiveContrato(
    int idTiendaConsignadora,
    int idTiendaConsignataria,
  ) async {
    try {
      final response = await _supabase
          .from('app_dat_contrato_consignacion')
          .select('id')
          .eq('id_tienda_consignadora', idTiendaConsignadora)
          .eq('id_tienda_consignataria', idTiendaConsignataria)
          .eq('estado', 1);

      return response.isNotEmpty;
    } catch (e) {
      debugPrint('❌ Error verificando contrato: $e');
      return false;
    }
  }
}

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AgenteService {
  static final _supabase = Supabase.instance.client;

  /// Listar todos los agentes
  static Future<List<Map<String, dynamic>>> getAgentes({
    bool soloActivos = true,
  }) async {
    try {
      var query = _supabase
          .from('app_dat_agente')
          .select('*');

      if (soloActivos) {
        query = query.eq('estado', 1);
      }

      final response = await query.order('nombre', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error obteniendo agentes: $e');
      rethrow;
    }
  }

  /// Crear un nuevo agente
  static Future<Map<String, dynamic>> crearAgente({
    required String nombre,
    required String apellidos,
    String? telefono,
    String? email,
    String? observaciones,
  }) async {
    try {
      final response = await _supabase
          .from('app_dat_agente')
          .insert({
            'nombre': nombre,
            'apellidos': apellidos,
            'telefono': telefono,
            'email': email,
            'observaciones': observaciones,
          })
          .select()
          .single();

      debugPrint('✅ Agente creado: ${response['id']}');
      return response;
    } catch (e) {
      debugPrint('❌ Error creando agente: $e');
      rethrow;
    }
  }

  /// Actualizar un agente existente
  static Future<Map<String, dynamic>> actualizarAgente({
    required int id,
    required String nombre,
    required String apellidos,
    String? telefono,
    String? email,
    String? observaciones,
  }) async {
    try {
      final response = await _supabase
          .from('app_dat_agente')
          .update({
            'nombre': nombre,
            'apellidos': apellidos,
            'telefono': telefono,
            'email': email,
            'observaciones': observaciones,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id)
          .select()
          .single();

      debugPrint('✅ Agente actualizado: $id');
      return response;
    } catch (e) {
      debugPrint('❌ Error actualizando agente: $e');
      rethrow;
    }
  }

  /// Desactivar un agente (soft delete)
  static Future<void> desactivarAgente(int id) async {
    try {
      await _supabase
          .from('app_dat_agente')
          .update({
            'estado': 0,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id);

      debugPrint('✅ Agente desactivado: $id');
    } catch (e) {
      debugPrint('❌ Error desactivando agente: $e');
      rethrow;
    }
  }

  /// Activar un agente
  static Future<void> activarAgente(int id) async {
    try {
      await _supabase
          .from('app_dat_agente')
          .update({
            'estado': 1,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id);

      debugPrint('✅ Agente activado: $id');
    } catch (e) {
      debugPrint('❌ Error activando agente: $e');
      rethrow;
    }
  }

  /// Asignar agente a una suscripción
  static Future<void> asignarAgenteASuscripcion({
    required int idSuscripcion,
    required int? idAgente,
  }) async {
    try {
      await _supabase
          .from('app_suscripciones')
          .update({
            'id_agente': idAgente,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', idSuscripcion);

      debugPrint('✅ Agente $idAgente asignado a suscripción $idSuscripcion');
    } catch (e) {
      debugPrint('❌ Error asignando agente: $e');
      rethrow;
    }
  }

  /// Obtener suscripciones de un agente
  static Future<List<Map<String, dynamic>>> getSuscripcionesDeAgente(
    int idAgente,
  ) async {
    try {
      final response = await _supabase
          .from('app_suscripciones')
          .select('''
            id,
            id_tienda,
            id_plan,
            fecha_inicio,
            fecha_fin,
            estado,
            app_dat_tienda!inner(denominacion, ubicacion),
            app_suscripciones_plan!inner(denominacion, precio_mensual)
          ''')
          .eq('id_agente', idAgente)
          .order('fecha_fin', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error obteniendo suscripciones del agente: $e');
      rethrow;
    }
  }

  /// Contar suscripciones activas por agente
  static Future<int> contarSuscripcionesActivas(int idAgente) async {
    try {
      final response = await _supabase
          .from('app_suscripciones')
          .select('id')
          .eq('id_agente', idAgente)
          .eq('estado', 1);

      return (response as List).length;
    } catch (e) {
      debugPrint('❌ Error contando suscripciones: $e');
      return 0;
    }
  }
}

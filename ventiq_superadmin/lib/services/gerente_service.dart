import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GerenteService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Obtiene todos los gerentes con información de tienda y trabajador en una sola consulta
  Future<List<Map<String, dynamic>>> getAllGerentes() async {
    try {
      debugPrint('═══════════════════════════════════════════');
      debugPrint('📞 LLAMANDO RPC: get_gerentes_completo()');
      
      final response = await _supabase.rpc('get_gerentes_completo');
      
      debugPrint('✅ RPC ejecutado exitosamente');
      debugPrint('Registros obtenidos: ${(response as List).length}');
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error en RPC: $e');
      throw Exception('Error al obtener gerentes: $e');
    }
  }

  /// Obtiene gerentes filtrados por tienda
  Future<List<Map<String, dynamic>>> getGerentesByTienda(int idTienda) async {
    try {
      final response = await _supabase
          .from('app_dat_gerente')
          .select('''
            id,
            uuid,
            id_tienda,
            id_trabajador,
            created_at
          ''')
          .eq('id_tienda', idTienda)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Error al obtener gerentes por tienda: $e');
    }
  }

  /// Obtiene información del usuario por UUID
  Future<Map<String, dynamic>?> getUserByUuid(String uuid) async {
    try {
      final response = await _supabase
          .from('auth.users')
          .select('id, email')
          .eq('id', uuid)
          .maybeSingle();

      return response;
    } catch (e) {
      throw Exception('Error al obtener usuario: $e');
    }
  }

  /// Obtiene información de la tienda
  Future<Map<String, dynamic>?> getTiendaById(int idTienda) async {
    try {
      final response = await _supabase
          .from('app_dat_tienda')
          .select('id, denominacion, direccion, ubicacion')
          .eq('id', idTienda)
          .maybeSingle();

      return response;
    } catch (e) {
      throw Exception('Error al obtener tienda: $e');
    }
  }

  /// Obtiene información del trabajador
  Future<Map<String, dynamic>?> getTrabajadorById(int idTrabajador) async {
    try {
      final response = await _supabase
          .from('app_dat_trabajadores')
          .select('id, nombres, apellidos')
          .eq('id', idTrabajador)
          .maybeSingle();

      return response;
    } catch (e) {
      throw Exception('Error al obtener trabajador: $e');
    }
  }

  /// Crea un nuevo gerente
  Future<Map<String, dynamic>> createGerente({
    required String uuid,
    required int idTienda,
    int? idTrabajador,
  }) async {
    try {
      final response = await _supabase
          .from('app_dat_gerente')
          .insert({
            'uuid': uuid,
            'id_tienda': idTienda,
            'id_trabajador': idTrabajador,
          })
          .select()
          .single();

      return response;
    } catch (e) {
      throw Exception('Error al crear gerente: $e');
    }
  }

  /// Actualiza un gerente
  Future<Map<String, dynamic>> updateGerente({
    required int id,
    String? uuid,
    int? idTienda,
    int? idTrabajador,
  }) async {
    try {
      final updateData = <String, dynamic>{};
      if (uuid != null) updateData['uuid'] = uuid;
      if (idTienda != null) updateData['id_tienda'] = idTienda;
      if (idTrabajador != null) updateData['id_trabajador'] = idTrabajador;

      final response = await _supabase
          .from('app_dat_gerente')
          .update(updateData)
          .eq('id', id)
          .select()
          .single();

      return response;
    } catch (e) {
      throw Exception('Error al actualizar gerente: $e');
    }
  }

  /// Elimina un gerente
  Future<void> deleteGerente(int id) async {
    try {
      await _supabase.from('app_dat_gerente').delete().eq('id', id);
    } catch (e) {
      throw Exception('Error al eliminar gerente: $e');
    }
  }

  /// Obtiene todas las tiendas disponibles
  Future<List<Map<String, dynamic>>> getAllTiendas() async {
    try {
      final response = await _supabase
          .from('app_dat_tienda')
          .select('id, denominacion, direccion, ubicacion')
          .order('denominacion', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Error al obtener tiendas: $e');
    }
  }

  /// Obtiene todos los gerentes existentes (para excluir en selección)
  Future<List<String>> getGerentesUuids() async {
    try {
      final response = await _supabase
          .from('app_dat_gerente')
          .select('uuid');

      return (response as List)
          .map((g) => g['uuid'] as String)
          .toList();
    } catch (e) {
      throw Exception('Error al obtener UUIDs de gerentes: $e');
    }
  }

  /// Verifica si un usuario ya es gerente en una tienda
  Future<bool> isUserGerenteInTienda(String uuid, int idTienda) async {
    try {
      final response = await _supabase
          .from('app_dat_gerente')
          .select('id')
          .eq('uuid', uuid)
          .eq('id_tienda', idTienda);

      return response.isNotEmpty;
    } catch (e) {
      throw Exception('Error al verificar gerente: $e');
    }
  }

  /// Obtiene el email del usuario por UUID
  Future<String?> getUserEmailByUuid(String uuid) async {
    try {
      final user = await getUserByUuid(uuid);
      return user?['email'];
    } catch (e) {
      return null;
    }
  }

  /// Obtiene datos del trabajador por UUID
  Future<Map<String, dynamic>?> getTrabajadorByUuid(String uuid) async {
    try {
      debugPrint('═══════════════════════════════════════════');
      debugPrint('🔍 BUSCANDO TRABAJADOR');
      debugPrint('UUID: $uuid');
      debugPrint('Tabla: app_dat_trabajadores');
      debugPrint('Columnas: id, nombres, apellidos, id_tienda, id_roll, salario_horas');
      
      final response = await _supabase
          .from('app_dat_trabajadores')
          .select('id, nombres, apellidos, id_tienda, id_roll, salario_horas')
          .eq('uuid', uuid)
          .maybeSingle();

      debugPrint('───────────────────────────────────────────');
      debugPrint('✅ RESULTADO:');
      if (response == null) {
        debugPrint('❌ No se encontró trabajador con ese UUID');
      } else {
        debugPrint('✓ Trabajador encontrado:');
        response.forEach((key, value) {
          debugPrint('  $key: $value (${value.runtimeType})');
        });
      }
      debugPrint('═══════════════════════════════════════════');
      
      return response;
    } catch (e) {
      debugPrint('═══════════════════════════════════════════');
      debugPrint('❌ ERROR AL OBTENER TRABAJADOR:');
      debugPrint('Tipo: ${e.runtimeType}');
      debugPrint('Mensaje: $e');
      debugPrint('═══════════════════════════════════════════');
      throw Exception('Error al obtener trabajador: $e');
    }
  }

  /// Busca usuarios en auth.users por email
  Future<List<Map<String, dynamic>>> searchUsersByEmail(String email) async {
    try {
      debugPrint('🔍 Buscando usuarios con email: $email');
      
      final response = await _supabase
          .from('auth.users')
          .select('id, email')
          .ilike('email', '%$email%')
          .limit(10);

      debugPrint('✅ Usuarios encontrados: ${(response as List).length}');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error buscando usuarios: $e');
      throw Exception('Error al buscar usuarios: $e');
    }
  }

  /// Crea un nuevo trabajador
  Future<Map<String, dynamic>> createTrabajador({
    required String uuid,
    required String nombres,
    required String apellidos,
    required int idTienda,
    int? idRoll,
  }) async {
    try {
      debugPrint('═══════════════════════════════════════════');
      debugPrint('➕ CREANDO NUEVO TRABAJADOR');
      debugPrint('UUID: $uuid');
      debugPrint('Nombres: $nombres');
      debugPrint('Apellidos: $apellidos');
      debugPrint('ID Tienda: $idTienda');
      debugPrint('ID Roll: $idRoll');
      
      final response = await _supabase
          .from('app_dat_trabajadores')
          .insert({
            'uuid': uuid,
            'nombres': nombres,
            'apellidos': apellidos,
            'id_tienda': idTienda,
            'id_roll': idRoll,
          })
          .select()
          .single();

      debugPrint('✅ Trabajador creado exitosamente');
      debugPrint('ID: ${response['id']}');
      debugPrint('═══════════════════════════════════════════');
      
      return response;
    } catch (e) {
      debugPrint('❌ Error creando trabajador: $e');
      throw Exception('Error al crear trabajador: $e');
    }
  }

  /// Crea un gerente desde email, nombres, apellidos e id_tienda
  /// Crea el trabajador y lo asigna como gerente en una transacción
  Future<Map<String, dynamic>> createGerenteFromEmail({
    required String email,
    required String nombres,
    required String apellidos,
    required int idTienda,
  }) async {
    try {
      debugPrint('═══════════════════════════════════════════');
      debugPrint('➕ CREANDO GERENTE DESDE EMAIL');
      debugPrint('Email: $email');
      debugPrint('Nombres: $nombres');
      debugPrint('Apellidos: $apellidos');
      debugPrint('ID Tienda: $idTienda');
      
      final params = {
        'p_email': email,
        'p_nombres': nombres,
        'p_apellidos': apellidos,
        'p_id_tienda': idTienda,
      };
      dynamic response;
      try {
        response = await _supabase.rpc('fn_m01_crear_gerente', params: params);
      } catch (e) {
        final text = e.toString().toLowerCase();
        final denied = text.contains('42501') ||
            text.contains('insufficient_privilege') ||
            text.contains('permission denied') ||
            text.contains('acceso denegado');
        final missing = !denied &&
            (text.contains('pgrst202') ||
                text.contains('could not find the function') ||
                (text.contains('does not exist') &&
                    text.contains('fn_m01_crear_gerente')));
        if (!missing) rethrow;
        response = await _supabase.rpc(
          'create_gerente_from_email',
          params: params,
        );
      }

      debugPrint('✅ Gerente creado exitosamente');
      debugPrint('Gerente ID: ${response[0]['gerente_id']}');
      debugPrint('Trabajador ID: ${response[0]['trabajador_id']}');
      debugPrint('UUID: ${response[0]['uuid']}');
      debugPrint('═══════════════════════════════════════════');
      
      return Map<String, dynamic>.from(response[0]);
    } catch (e) {
      debugPrint('❌ Error creando gerente: $e');
      throw Exception('Error al crear gerente: $e');
    }
  }
}

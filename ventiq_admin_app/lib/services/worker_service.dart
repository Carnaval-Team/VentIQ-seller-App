import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/worker_models.dart';

class WorkerService {
  static final _supabase = Supabase.instance.client;

  // =====================================================
  // FUNCIONES PARA TRABAJADORES
  // =====================================================

  /// Lista todos los trabajadores de una tienda
  static Future<List<WorkerData>> getWorkersByStore(int storeId, String userUuid) async {
    try {
      print('🔍 Obteniendo trabajadores para tienda: $storeId, usuario: $userUuid');
      
      final response = await _supabase.rpc('fn_listar_trabajadores_tienda', params: {
        'p_id_tienda': storeId,
        'p_usuario_solicitante': userUuid,
      });

      print('📋 Respuesta del RPC: $response');

      if (response['success'] == true) {
        final List<dynamic> workersData = response['data'] as List<dynamic>;
        print('📋 Procesando ${workersData.length} trabajadores...');
        
        final List<WorkerData> workers = [];
        for (int i = 0; i < workersData.length; i++) {
          try {
            final workerJson = workersData[i] as Map<String, dynamic>;
            print('👤 Procesando trabajador ${i + 1}: ${workerJson['nombres']} ${workerJson['apellidos']}');
            print('   - rol_id: ${workerJson['rol_id']} (${workerJson['rol_id'].runtimeType})');
            print('   - rol_nombre: ${workerJson['rol_nombre']} (${workerJson['rol_nombre'].runtimeType})');
            print('   - tipo_rol: ${workerJson['tipo_rol']}');
            
            final worker = WorkerData.fromJson(workerJson);
            workers.add(worker);
            print('✅ Trabajador procesado correctamente');
          } catch (e) {
            print('❌ Error procesando trabajador ${i + 1}: $e');
            print('   Datos: ${workersData[i]}');
            // Continuar con el siguiente trabajador en lugar de fallar completamente
          }
        }
        
        print('✅ Total trabajadores procesados: ${workers.length}');
        return workers;
      } else {
        throw Exception(response['message'] ?? 'Error al obtener trabajadores');
      }
    } catch (e) {
      print('❌ Error en getWorkersByStore: $e');
      throw Exception('Error al cargar trabajadores: $e');
    }
  }

  /// Obtiene el detalle completo de un trabajador
  static Future<WorkerData> getWorkerDetail(int workerId, int storeId) async {
    try {
      print('🔍 Obteniendo detalle del trabajador: $workerId');
      
      final response = await _supabase.rpc('fn_obtener_detalle_trabajador', params: {
        'p_trabajador_id': workerId,
        'p_id_tienda': storeId,
      });

      print('📋 Respuesta del detalle: $response');

      if (response['success'] == true) {
        return WorkerData.fromJson(response['data'] as Map<String, dynamic>);
      } else {
        throw Exception(response['message'] ?? 'Error al obtener detalle del trabajador');
      }
    } catch (e) {
      print('❌ Error en getWorkerDetail: $e');
      throw Exception('Error al cargar detalle del trabajador: $e');
    }
  }

  /// Crea un nuevo trabajador
  static Future<bool> createWorker({
    required int storeId,
    required String nombres,
    required String apellidos,
    required String tipoRol,
    required String usuarioUuid,
    int? tpvId,
    int? almacenId,
    String? numeroConfirmacion,
  }) async {
    try {
      print('➕ Creando trabajador: $nombres $apellidos, rol: $tipoRol');
      
      final response = await _supabase.rpc('fn_insertar_trabajador_completo', params: {
        'p_id_tienda': storeId,
        'p_nombres': nombres,
        'p_apellidos': apellidos,
        'p_tipo_rol': tipoRol,
        'p_usuario_uuid': usuarioUuid,
        'p_tpv_id': tpvId,
        'p_almacen_id': almacenId,
        'p_numero_confirmacion': numeroConfirmacion,
      });

      print('📋 Respuesta de creación: $response');

      if (response['success'] == true) {
        return true;
      } else {
        throw Exception(response['message'] ?? 'Error al crear trabajador');
      }
    } catch (e) {
      print('❌ Error en createWorker: $e');
      throw Exception('Error al crear trabajador: $e');
    }
  }

  /// Edita un trabajador existente
  static Future<bool> editWorker({
    required int workerId,
    required int storeId,
    String? nombres,
    String? apellidos,
    String? tipoRol,
    String? usuarioUuid,
    int? tpvId,
    int? almacenId,
    String? numeroConfirmacion,
  }) async {
    try {
      print('✏️ Editando trabajador: $workerId');
      
      final response = await _supabase.rpc('fn_editar_trabajador_completo', params: {
        'p_trabajador_id': workerId,
        'p_id_tienda': storeId,
        'p_nombres': nombres,
        'p_apellidos': apellidos,
        'p_tipo_rol': tipoRol,
        'p_usuario_uuid': usuarioUuid,
        'p_tpv_id': tpvId,
        'p_almacen_id': almacenId,
        'p_numero_confirmacion': numeroConfirmacion,
      });

      print('📋 Respuesta de edición: $response');

      if (response['success'] == true) {
        return true;
      } else {
        throw Exception(response['message'] ?? 'Error al editar trabajador');
      }
    } catch (e) {
      print('❌ Error en editWorker: $e');
      throw Exception('Error al editar trabajador: $e');
    }
  }

  /// Elimina un trabajador
  static Future<bool> deleteWorker(int workerId, int storeId) async {
    try {
      print('🗑️ Eliminando trabajador: $workerId');
      
      final response = await _supabase.rpc('fn_eliminar_trabajador_completo', params: {
        'p_trabajador_id': workerId,
        'p_id_tienda': storeId,
      });

      print('📋 Respuesta de eliminación: $response');

      if (response['success'] == true) {
        return true;
      } else {
        throw Exception(response['message'] ?? 'Error al eliminar trabajador');
      }
    } catch (e) {
      print('❌ Error en deleteWorker: $e');
      throw Exception('Error al eliminar trabajador: $e');
    }
  }

  /// Obtiene estadísticas de trabajadores
  static Future<WorkerStatistics> getWorkerStatistics(int storeId) async {
    try {
      print('📊 Obteniendo estadísticas de trabajadores para tienda: $storeId');
      
      final response = await _supabase.rpc('fn_estadisticas_trabajadores_tienda', params: {
        'p_id_tienda': storeId,
      });

      print('📋 Respuesta de estadísticas: $response');

      if (response['success'] == true) {
        final statsData = response['data'] as Map<String, dynamic>;
        print('📊 Procesando estadísticas...');
        print('   - Estructura completa: $statsData');
        print('   - total_trabajadores: ${statsData['total_trabajadores']}');
        print('   - por_rol: ${statsData['por_rol']}');
        print('   - porcentajes: ${statsData['porcentajes']}');
        
        try {
          final statistics = WorkerStatistics.fromJson(statsData);
          print('✅ Estadísticas procesadas correctamente');
          return statistics;
        } catch (e) {
          print('❌ Error procesando estadísticas: $e');
          rethrow;
        }
      } else {
        throw Exception(response['message'] ?? 'Error al obtener estadísticas');
      }
    } catch (e) {
      print('❌ Error en getWorkerStatistics: $e');
      throw Exception('Error al cargar estadísticas: $e');
    }
  }

  // =====================================================
  // FUNCIONES AUXILIARES
  // =====================================================

  /// Obtiene los roles disponibles de una tienda
  static Future<List<WorkerRole>> getRolesByStore(int storeId) async {
    try {
      print('🔍 Obteniendo roles para tienda: $storeId');
      
      final response = await _supabase.rpc('fn_obtener_roles_tienda', params: {
        'p_id_tienda': storeId,
      });

      print('📋 Respuesta de roles: $response');

      if (response['success'] == true) {
        final List<dynamic> rolesData = response['data'] as List<dynamic>;
        return rolesData.map((json) => WorkerRole.fromJson(json as Map<String, dynamic>)).toList();
      } else {
        throw Exception(response['message'] ?? 'Error al obtener roles');
      }
    } catch (e) {
      print('❌ Error en getRolesByStore: $e');
      throw Exception('Error al cargar roles: $e');
    }
  }

  /// Obtiene los TPVs disponibles de una tienda
  static Future<List<TPVData>> getTPVsByStore(int storeId) async {
    try {
      print('🔍 Obteniendo TPVs para tienda: $storeId');
      
      final response = await _supabase.rpc('fn_obtener_tpvs_tienda', params: {
        'p_id_tienda': storeId,
      });

      print('📋 Respuesta de TPVs: $response');

      if (response['success'] == true) {
        final List<dynamic> tpvsData = response['data'] as List<dynamic>;
        return tpvsData.map((json) => TPVData.fromJson(json as Map<String, dynamic>)).toList();
      } else {
        throw Exception(response['message'] ?? 'Error al obtener TPVs');
      }
    } catch (e) {
      print('❌ Error en getTPVsByStore: $e');
      throw Exception('Error al cargar TPVs: $e');
    }
  }

  /// Obtiene los almacenes disponibles de una tienda
  static Future<List<AlmacenData>> getAlmacenesByStore(int storeId) async {
    try {
      print('🔍 Obteniendo almacenes para tienda: $storeId');
      
      final response = await _supabase.rpc('fn_obtener_almacenes_tienda', params: {
        'p_id_tienda': storeId,
      });

      print('📋 Respuesta de almacenes: $response');

      if (response['success'] == true) {
        final List<dynamic> almacenesData = response['data'] as List<dynamic>;
        return almacenesData.map((json) => AlmacenData.fromJson(json as Map<String, dynamic>)).toList();
      } else {
        throw Exception(response['message'] ?? 'Error al obtener almacenes');
      }
    } catch (e) {
      print('❌ Error en getAlmacenesByStore: $e');
      throw Exception('Error al cargar almacenes: $e');
    }
  }

  /// Verifica los permisos de un usuario en una tienda
  static Future<Map<String, dynamic>> verifyUserPermissions(String userUuid, int storeId) async {
    try {
      print('🔍 Verificando permisos para usuario: $userUuid, tienda: $storeId');
      
      final response = await _supabase.rpc('fn_verificar_permisos_usuario', params: {
        'p_usuario_uuid': userUuid,
        'p_id_tienda': storeId,
      });

      print('📋 Respuesta de permisos: $response');

      if (response['success'] == true) {
        return response['data'] as Map<String, dynamic>;
      } else {
        throw Exception(response['message'] ?? 'Error al verificar permisos');
      }
    } catch (e) {
      print('❌ Error en verifyUserPermissions: $e');
      throw Exception('Error al verificar permisos: $e');
    }
  }

  // =====================================================
  // FUNCIONES PARA ROLES
  // =====================================================

  /// Crea un nuevo rol
  static Future<bool> createRole({
    required int storeId,
    required String denominacion,
    String? descripcion,
  }) async {
    try {
      print('➕ Creando rol: $denominacion');
      
      final response = await _supabase.from('seg_roll').insert({
        'id_tienda': storeId,
        'denominacion': denominacion,
        'descripcion': descripcion,
      }).select();

      print('📋 Respuesta de creación de rol: $response');
      return response.isNotEmpty;
    } catch (e) {
      print('❌ Error en createRole: $e');
      throw Exception('Error al crear rol: $e');
    }
  }

  /// Edita un rol existente
  static Future<bool> editRole({
    required int roleId,
    String? denominacion,
    String? descripcion,
  }) async {
    try {
      print('✏️ Editando rol: $roleId');
      
      final Map<String, dynamic> updateData = {};
      if (denominacion != null) updateData['denominacion'] = denominacion;
      if (descripcion != null) updateData['descripcion'] = descripcion;

      if (updateData.isEmpty) {
        throw Exception('No hay datos para actualizar');
      }

      final response = await _supabase
          .from('seg_roll')
          .update(updateData)
          .eq('id', roleId)
          .select();

      print('📋 Respuesta de edición de rol: $response');
      return response.isNotEmpty;
    } catch (e) {
      print('❌ Error en editRole: $e');
      throw Exception('Error al editar rol: $e');
    }
  }

  /// Elimina un rol
  static Future<bool> deleteRole(int roleId) async {
    try {
      print('🗑️ Eliminando rol: $roleId');
      
      // Verificar que no hay trabajadores con este rol
      final workersWithRole = await _supabase
          .from('app_dat_trabajadores')
          .select('id')
          .eq('id_roll', roleId);

      if (workersWithRole.isNotEmpty) {
        throw Exception('No se puede eliminar el rol porque hay trabajadores asignados a él');
      }

      final response = await _supabase
          .from('seg_roll')
          .delete()
          .eq('id', roleId)
          .select();

      print('📋 Respuesta de eliminación de rol: $response');
      return response.isNotEmpty;
    } catch (e) {
      print('❌ Error en deleteRole: $e');
      throw Exception('Error al eliminar rol: $e');
    }
  }
}

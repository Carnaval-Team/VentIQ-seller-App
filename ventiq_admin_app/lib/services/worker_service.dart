import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/worker_models.dart';
import 'permissions_service.dart';
class WorkerService {
  static final _supabase = Supabase.instance.client;

  // =====================================================
  // FUNCIONES PARA TRABAJADORES
  // =====================================================

  /// Lista todos los trabajadores de una tienda
  static Future<List<WorkerData>> getWorkersByStore(
    int storeId,
    String userUuid,
  ) async {
    try {
      print(
        '🔍 Obteniendo trabajadores para tienda: $storeId, usuario: $userUuid',
      );

      final response = await _supabase.rpc(
        'fn_listar_trabajadores_tienda',
        params: {'p_id_tienda': storeId, 'p_usuario_solicitante': userUuid},
      );

      print('📋 Respuesta del RPC: $response');

      if (response['success'] == true) {
        final List<dynamic> workersData = response['data'] as List<dynamic>;
        print('📋 Procesando ${workersData.length} trabajadores...');

        final List<WorkerData> workers = [];
        for (int i = 0; i < workersData.length; i++) {
          try {
            final workerJson = workersData[i] as Map<String, dynamic>;
            print(
              '👤 Procesando trabajador ${i + 1}: ${workerJson['nombres']} ${workerJson['apellidos']}',
            );
            print(
              '   - rol_id: ${workerJson['rol_id']} (${workerJson['rol_id'].runtimeType})',
            );
            print(
              '   - rol_nombre: ${workerJson['rol_nombre']} (${workerJson['rol_nombre'].runtimeType})',
            );
            print('   - tipo_rol: ${workerJson['tipo_rol']}');
            print('   - datos_especificos: ${workerJson['datos_especificos']}');
            print('   - es_vendedor: ${workerJson['es_vendedor']}');
            print('   - es_almacenero: ${workerJson['es_almacenero']}');
            print('   - 💰 salario_horas: ${workerJson['salario_horas']}'); // 💰 DEBUG

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

      final response = await _supabase.rpc(
        'fn_obtener_detalle_trabajador',
        params: {'p_trabajador_id': workerId, 'p_id_tienda': storeId},
      );

      print('📋 Respuesta del detalle: $response');

      if (response['success'] == true) {
        return WorkerData.fromJson(response['data'] as Map<String, dynamic>);
      } else {
        throw Exception(
          response['message'] ?? 'Error al obtener detalle del trabajador',
        );
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
    double salarioHoras = 0.0, // 💰 NUEVO: Salario por hora
    int? tpvId,
    int? almacenId,
    String? numeroConfirmacion,
  }) async {
    try {
      print('➕ Creando trabajador: $nombres $apellidos, rol: $tipoRol');
      print('💰 Salario/Hora: $salarioHoras');

      // 1. Crear trabajador con RPC existente
      final response = await _supabase.rpc(
        'fn_insertar_trabajador_completo',
        params: {
          'p_id_tienda': storeId,
          'p_nombres': nombres,
          'p_apellidos': apellidos,
          'p_tipo_rol': tipoRol,
          'p_usuario_uuid': usuarioUuid,
          'p_tpv_id': tpvId,
          'p_almacen_id': almacenId,
          'p_numero_confirmacion': numeroConfirmacion,
        },
      );

      print('📋 Respuesta de creación: $response');

      if (response['success'] != true) {
        throw Exception(response['message'] ?? 'Error al crear trabajador');
      }

      // 2. 💰 Actualizar salario_horas si es mayor a 0
      if (salarioHoras > 0 && response['trabajador_id'] != null) {
        final trabajadorId = response['trabajador_id'] as int;
        print('💰 Actualizando salario_horas: $salarioHoras para trabajador $trabajadorId');
        await _supabase
            .from('app_dat_trabajadores')
            .update({'salario_horas': salarioHoras})
            .eq('id', trabajadorId);
        print('✅ Salario actualizado correctamente');
      }

      return true;
    } catch (e) {
      print('❌ Error en createWorker: $e');
      throw Exception('Error al crear trabajador: $e');
    }
  }

  /// Crea un trabajador básico (sin rol específico de app)
  static Future<bool> createWorkerBasic({
    required int storeId,
    required String nombres,
    required String apellidos,
    String? usuarioUuid,
    int? rolId,
    double salarioHoras = 0.0, // 💰 NUEVO: Salario por hora
  }) async {
    try {
      print('➡️ Creando trabajador básico: $nombres $apellidos');
      print('   UUID: ${usuarioUuid ?? "null"}, Rol ID: $rolId');
      print('💰 Salario/Hora: $salarioHoras');

      // 1. Crear trabajador con RPC existente
      final response = await _supabase.rpc(
        'fn_insertar_trabajador_basico',
        params: {
          'p_id_tienda': storeId,
          'p_nombres': nombres,
          'p_apellidos': apellidos,
          'p_usuario_uuid': usuarioUuid,
          'p_id_roll': rolId,
        },
      );

      print('📋 Respuesta de creación básica: $response');

      if (response['success'] != true) {
        throw Exception(response['message'] ?? 'Error al crear trabajador');
      }

      // 2. 💰 Actualizar salario_horas si es mayor a 0
      if (salarioHoras > 0 && response['trabajador_id'] != null) {
        final trabajadorId = response['trabajador_id'] as int;
        print('💰 Actualizando salario_horas: $salarioHoras para trabajador $trabajadorId');
        await _supabase
            .from('app_dat_trabajadores')
            .update({'salario_horas': salarioHoras})
            .eq('id', trabajadorId);
        print('✅ Salario actualizado correctamente');
      }

      return true;
    } catch (e) {
      print('❌ Error en createWorkerBasic: $e');
      throw Exception('Error al crear trabajador: $e');
    }
  }

  /// Edita solo los datos básicos de un trabajador (nombre, apellidos, uuid)
  /// Para gestionar roles, usar addWorkerRole, removeWorkerRole, updateRoleSpecificData
  static Future<bool> editWorker({
    required int workerId,
    required int storeId,
    required String nombres,
    required String apellidos,
    String? tipoRol, // Deprecated - mantenido por compatibilidad
    String? usuarioUuid,
    double? salarioHoras, // 💰 NUEVO: Salario por hora (opcional para edición)
    int? tpvId, // Deprecated - usar updateRoleSpecificData
    int? almacenId, // Deprecated - usar updateRoleSpecificData
    String? numeroConfirmacion, // Deprecated - usar updateRoleSpecificData
  }) async {
    try {
      print('✏️ Editando trabajador: $workerId');
      print('  - Nombres: $nombres');
      print('  - Apellidos: $apellidos');
      print('  - UUID: $usuarioUuid');
      print('  - Salario/Hora: ${salarioHoras ?? "sin cambios"}'); // 💰 NUEVO

      // 1. Editar datos básicos con RPC existente
      final response = await _supabase.rpc(
        'fn_editar_trabajador_basico',
        params: {
          'p_trabajador_id': workerId,
          'p_nombres': nombres,
          'p_apellidos': apellidos,
          'p_uuid': usuarioUuid,
        },
      );

      print('📋 Respuesta de edición: $response');

      if (response['success'] != true) {
        throw Exception(response['message'] ?? 'Error al editar trabajador');
      }

      // 2. 💰 Actualizar salario_horas directamente si se proporcionó
      if (salarioHoras != null) {
        print('💰 Actualizando salario_horas: $salarioHoras');
        await _supabase
            .from('app_dat_trabajadores')
            .update({'salario_horas': salarioHoras})
            .eq('id', workerId);
        print('✅ Salario actualizado correctamente');
      }

      return true;
    } catch (e) {
      print('❌ Error en editWorker: $e');
      throw Exception('Error al editar trabajador: $e');
    }
  }

  /// Actualiza el UUID de un trabajador (para asignar usuario a trabajador existente)
  static Future<bool> updateWorkerUUID({
    required int workerId,
    required int storeId,
    required String uuid,
  }) async {
    try {
      print('🔄 Actualizando UUID del trabajador: $workerId');

      final response =
          await _supabase
              .from('app_dat_trabajadores')
              .update({'uuid': uuid})
              .eq('id', workerId)
              .eq('id_tienda', storeId)
              .select();

      print('📋 Respuesta de actualización de UUID: $response');
      return response.isNotEmpty;
    } catch (e) {
      print('❌ Error en updateWorkerUUID: $e');
      throw Exception('Error al actualizar UUID del trabajador: $e');
    }
  }

  /// Elimina un trabajador
  static Future<bool> deleteWorker(int workerId, int storeId) async {
    try {
      print('🗑️ Eliminando trabajador: $workerId');

      final response = await _supabase.rpc(
        'fn_eliminar_trabajador_completo',
        params: {'p_trabajador_id': workerId, 'p_id_tienda': storeId},
      );

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

      final response = await _supabase.rpc(
        'fn_estadisticas_trabajadores_tienda',
        params: {'p_id_tienda': storeId},
      );

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

      final response = await _supabase.rpc(
        'fn_obtener_roles_tienda',
        params: {'p_id_tienda': storeId},
      );

      print('📋 Respuesta de roles: $response');

      if (response['success'] == true) {
        final List<dynamic> rolesData = response['data'] as List<dynamic>;
        return rolesData
            .map((json) => WorkerRole.fromJson(json as Map<String, dynamic>))
            .toList();
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

      final response = await _supabase.rpc(
        'fn_obtener_tpvs_tienda',
        params: {'p_id_tienda': storeId},
      );

      print('📋 Respuesta de TPVs: $response');

      if (response['success'] == true) {
        final List<dynamic> tpvsData = response['data'] as List<dynamic>;
        return tpvsData
            .map((json) => TPVData.fromJson(json as Map<String, dynamic>))
            .toList();
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

      final response = await _supabase.rpc(
        'fn_obtener_almacenes_tienda',
        params: {'p_id_tienda': storeId},
      );

      print('📋 Respuesta de almacenes: $response');

      if (response['success'] == true) {
        final List<dynamic> almacenesData = response['data'] as List<dynamic>;
        return almacenesData
            .map((json) => AlmacenData.fromJson(json as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception(response['message'] ?? 'Error al obtener almacenes');
      }
    } catch (e) {
      print('❌ Error en getAlmacenesByStore: $e');
      throw Exception('Error al cargar almacenes: $e');
    }
  }

  /// Verifica los permisos de un usuario en una tienda
  static Future<Map<String, dynamic>> verifyUserPermissions(
    String userUuid,
    int storeId,
  ) async {
    try {
      print(
        '🔍 Verificando permisos para usuario: $userUuid, tienda: $storeId',
      );

      final response = await _supabase.rpc(
        'fn_verificar_permisos_usuario',
        params: {'p_usuario_uuid': userUuid, 'p_id_tienda': storeId},
      );

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

      final response =
          await _supabase.from('seg_roll').insert({
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

      final response =
          await _supabase
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
        throw Exception(
          'No se puede eliminar el rol porque hay trabajadores asignados a él',
        );
      }

      final response =
          await _supabase.from('seg_roll').delete().eq('id', roleId).select();

      print('📋 Respuesta de eliminación de rol: $response');
      return response.isNotEmpty;
    } catch (e) {
      print('❌ Error en deleteRole: $e');
      throw Exception('Error al eliminar rol: $e');
    }
  }

  // =====================================================
  // 🆕 FUNCIONES PARA GESTIÓN DE ROLES MÚLTIPLES
  // =====================================================

  /// Agrega un rol adicional a un trabajador
  static Future<bool> addWorkerRole({
    required int trabajadorId,
    required int storeId,
    required String tipoRol,
    required String usuarioUuid,
    int? tpvId,
    int? almacenId,
    String? numeroConfirmacion,
  }) async {
    try {
      print('➡️ Agregando rol $tipoRol al trabajador $trabajadorId');

      final response = await _supabase.rpc(
        'fn_agregar_rol_trabajador',
        params: {
          'p_trabajador_id': trabajadorId,
          'p_id_tienda': storeId,
          'p_tipo_rol': tipoRol,
          'p_usuario_uuid': usuarioUuid,
          'p_tpv_id': tpvId,
          'p_almacen_id': almacenId,
          'p_numero_confirmacion': numeroConfirmacion,
        },
      );

      print('📋 Respuesta de agregar rol: $response');

      if (response['success'] == true) {
        return true;
      } else {
        throw Exception(response['message'] ?? 'Error al agregar rol');
      }
    } catch (e) {
      print('❌ Error en addWorkerRole: $e');
      throw Exception('Error al agregar rol: $e');
    }
  }

  /// Elimina un rol específico de un trabajador
  static Future<bool> removeWorkerRole({
    required int trabajadorId,
    required String tipoRol,
  }) async {
    try {
      print('❌ Eliminando rol $tipoRol del trabajador $trabajadorId');

      final response = await _supabase.rpc(
        'fn_eliminar_rol_trabajador',
        params: {'p_trabajador_id': trabajadorId, 'p_tipo_rol': tipoRol},
      );

      print('📋 Respuesta de eliminar rol: $response');

      if (response['success'] == true) {
        return true;
      } else {
        throw Exception(response['message'] ?? 'Error al eliminar rol');
      }
    } catch (e) {
      print('❌ Error en removeWorkerRole: $e');
      throw Exception('Error al eliminar rol: $e');
    }
  }

  /// Actualiza los datos específicos de un rol (TPV para vendedor, Almacén para almacenero)
  static Future<bool> updateRoleSpecificData({
    required int trabajadorId,
    required String tipoRol,
    int? tpvId,
    int? almacenId,
    String? numeroConfirmacion,
  }) async {
    try {
      print(
        '✏️ Actualizando datos específicos del rol $tipoRol para trabajador $trabajadorId',
      );

      final response = await _supabase.rpc(
        'fn_actualizar_datos_rol_trabajador',
        params: {
          'p_trabajador_id': trabajadorId,
          'p_tipo_rol': tipoRol,
          'p_tpv_id': tpvId,
          'p_almacen_id': almacenId,
          'p_numero_confirmacion': numeroConfirmacion,
        },
      );

      print('📋 Respuesta de actualizar datos de rol: $response');

      if (response['success'] == true) {
        return true;
      } else {
        throw Exception(
          response['message'] ?? 'Error al actualizar datos del rol',
        );
      }
    } catch (e) {
      print('❌ Error en updateRoleSpecificData: $e');
      throw Exception('Error al actualizar datos del rol: $e');
    }
  }

  // =====================================================
  // GESTIÓN DE TRABAJADORES ELIMINADOS (SOFT DELETE)
  // =====================================================

  /// Lista trabajadores eliminados (soft delete)
  static Future<List<WorkerData>> getDeletedWorkers(
    int storeId,
    String userUuid,
  ) async {
    try {
      print('🗑️ Obteniendo trabajadores eliminados para tienda: $storeId');

      final response = await _supabase.rpc(
        'fn_listar_trabajadores_eliminados',
        params: {'p_id_tienda': storeId, 'p_usuario_solicitante': userUuid},
      );

      print('📋 Respuesta del RPC (eliminados): $response');

      if (response['success'] == true) {
        final List<dynamic> workersData = response['data'] as List<dynamic>;
        print('📋 Procesando ${workersData.length} trabajadores eliminados...');

        final List<WorkerData> workers = [];
        for (int i = 0; i < workersData.length; i++) {
          try {
            final workerJson = workersData[i] as Map<String, dynamic>;
            final worker = WorkerData.fromJson(workerJson);
            workers.add(worker);
          } catch (e) {
            print('❌ Error procesando trabajador eliminado ${i + 1}: $e');
          }
        }

        print('✅ Total trabajadores eliminados procesados: ${workers.length}');
        return workers;
      } else {
        throw Exception(
          response['message'] ?? 'Error al obtener trabajadores eliminados',
        );
      }
    } catch (e) {
      print('❌ Error en getDeletedWorkers: $e');
      throw Exception('Error al cargar trabajadores eliminados: $e');
    }
  }

  /// Restaura un trabajador eliminado (soft delete)
  static Future<bool> restoreWorker(int workerId, int storeId) async {
    try {
      print('♻️ Restaurando trabajador: $workerId');

      final response = await _supabase.rpc(
        'fn_restaurar_trabajador',
        params: {'p_trabajador_id': workerId, 'p_id_tienda': storeId},
      );

      print('📋 Respuesta de restauración: $response');

      if (response['success'] == true) {
        return true;
      } else {
        throw Exception(response['message'] ?? 'Error al restaurar trabajador');
      }
    } catch (e) {
      print('❌ Error en restoreWorker: $e');
      throw Exception('Error al restaurar trabajador: $e');
    }
  }

  // =====================================================
  // ASIGNACIÓN AUTOMÁTICA DE UUID DESDE ROLES
  // =====================================================

  /// Asigna UUID a trabajadores desde sus roles (gerente, supervisor, vendedor, almacenero)
  static Future<Map<String, dynamic>> assignUUIDFromRoles(int? storeId) async {
    try {
      print('🔄 Asignando UUID desde roles para tienda: ${storeId ?? "todas"}');

      final response = await _supabase.rpc(
        'asignar_uuid_desde_roles',
        params: {'p_id_tienda': storeId},
      );

      print('📋 Respuesta: $response');

      if (response is List) {
        final results = response as List<dynamic>;

        // Filtrar resultados exitosos (excluir el mensaje de "no encontrados")
        final successResults =
            results.where((r) => r['trabajador_id'] != null).toList();

        return {
          'success': true,
          'total': successResults.length,
          'results': successResults,
          'message':
              successResults.isEmpty
                  ? 'No se encontraron trabajadores sin UUID con roles asignados'
                  : '${successResults.length} trabajador(es) actualizado(s)',
        };
      } else {
        throw Exception('Formato de respuesta inesperado');
      }
    } catch (e) {
      print('❌ Error en assignUUIDFromRoles: $e');
      throw Exception('Error al asignar UUID desde roles: $e');
    }
  }
}

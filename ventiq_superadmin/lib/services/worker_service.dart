import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/worker_models.dart';

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

      if (response['success'] == true) {
        final List<dynamic> workersData = response['data'] as List<dynamic>;
        
        final List<WorkerData> workers = [];
        for (int i = 0; i < workersData.length; i++) {
          try {
            final workerJson = workersData[i] as Map<String, dynamic>;
            final worker = WorkerData.fromJson(workerJson);
            workers.add(worker);
          } catch (e) {
            print('❌ Error procesando trabajador ${i + 1}: $e');
          }
        }

        return workers;
      } else {
        throw Exception(response['message'] ?? 'Error al obtener trabajadores');
      }
    } catch (e) {
      print('❌ Error en getWorkersByStore: $e');
      throw Exception('Error al cargar trabajadores: $e');
    }
  }

  /// Crea un nuevo trabajador (completo)
  static Future<bool> createWorker({
    required int storeId,
    required String nombres,
    required String apellidos,
    required String tipoRol,
    required String usuarioUuid,
    double salarioHoras = 0.0,
    int? tpvId,
    int? almacenId,
    String? numeroConfirmacion,
  }) async {
    try {
      print('➕ Creando trabajador: $nombres $apellidos, rol: $tipoRol');

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

      if (response['success'] != true) {
        throw Exception(response['message'] ?? 'Error al crear trabajador');
      }

      if (salarioHoras > 0 && response['trabajador_id'] != null) {
        final trabajadorId = response['trabajador_id'] as int;
        await _supabase
            .from('app_dat_trabajadores')
            .update({'salario_horas': salarioHoras})
            .eq('id', trabajadorId);
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
    double salarioHoras = 0.0,
  }) async {
    try {
      print('➡️ Creando trabajador básico: $nombres $apellidos');

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

      if (response['success'] != true) {
        throw Exception(response['message'] ?? 'Error al crear trabajador');
      }

      if (salarioHoras > 0 && response['trabajador_id'] != null) {
        final trabajadorId = response['trabajador_id'] as int;
        await _supabase
            .from('app_dat_trabajadores')
            .update({'salario_horas': salarioHoras})
            .eq('id', trabajadorId);
      }

      return true;
    } catch (e) {
      print('❌ Error en createWorkerBasic: $e');
      throw Exception('Error al crear trabajador: $e');
    }
  }

  // =====================================================
  // FUNCIONES AUXILIARES
  // =====================================================

  /// Obtiene los roles disponibles de una tienda
  static Future<List<WorkerRole>> getRolesByStore(int storeId) async {
    try {
      final response = await _supabase.rpc(
        'fn_obtener_roles_tienda',
        params: {'p_id_tienda': storeId},
      );

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
      final response = await _supabase.rpc(
        'fn_obtener_tpvs_tienda',
        params: {'p_id_tienda': storeId},
      );

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
      final response = await _supabase.rpc(
        'fn_obtener_almacenes_tienda',
        params: {'p_id_tienda': storeId},
      );

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
}

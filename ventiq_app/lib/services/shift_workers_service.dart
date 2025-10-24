import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/shift_worker.dart';
import 'user_preferences_service.dart';

/// Servicio para gestión de trabajadores de turno con soporte offline
class ShiftWorkersService {
  static final _supabase = Supabase.instance.client;
  static final _userPrefs = UserPreferencesService();

  /// Obtener trabajadores del turno actual
  static Future<List<ShiftWorker>> getShiftWorkers(int idTurno) async {
    try {
      print('🔍 Obteniendo trabajadores del turno $idTurno...');

      // Verificar modo offline
      final isOffline = await _userPrefs.isOfflineModeEnabled();

      if (isOffline) {
        print('🔌 Modo offline - Cargando desde cache...');
        return await _getShiftWorkersOffline(idTurno);
      }

      // Modo online - consultar Supabase con JOIN
      final response = await _supabase
          .from('app_dat_turno_trabajadores')
          .select('''
            *,
            trabajador:app_dat_trabajadores!inner(
              id,
              nombres,
              apellidos,
              id_roll,
              seg_roll!inner(
                id,
                denominacion
              )
            )
          ''')
          .eq('id_turno', idTurno)
          .order('hora_entrada', ascending: true);

      print('📊 Respuesta de Supabase: ${response.length} trabajadores');

      final workers = (response as List)
          .map((json) => ShiftWorker.fromJson(json))
          .toList();

      // Guardar en cache para uso offline
      await _saveShiftWorkersCache(idTurno, workers);

      return workers;
    } catch (e) {
      print('❌ Error obteniendo trabajadores del turno: $e');
      
      // Intentar cargar desde cache en caso de error
      try {
        print('🔄 Intentando cargar desde cache...');
        return await _getShiftWorkersOffline(idTurno);
      } catch (cacheError) {
        print('❌ Error cargando desde cache: $cacheError');
        return [];
      }
    }
  }

  /// Obtener trabajadores disponibles de la tienda
  static Future<List<AvailableWorker>> getAvailableWorkers() async {
    try {
      print('🔍 Obteniendo trabajadores disponibles...');

      final idTienda = await _userPrefs.getIdTienda();
      if (idTienda == null) {
        throw Exception('ID de tienda no encontrado');
      }

      // Verificar modo offline
      final isOffline = await _userPrefs.isOfflineModeEnabled();

      if (isOffline) {
        print('🔌 Modo offline - Cargando desde cache...');
        return await _getAvailableWorkersOffline();
      }

      // Consultar trabajadores activos de la tienda
      final response = await _supabase
          .from('app_dat_trabajadores')
          .select('''
            id,
            nombres,
            apellidos,
            id_roll,
            seg_roll(
              id,
              denominacion
            )
          ''')
          .eq('id_tienda', idTienda)
          .isFilter('deleted_at', null)
          .order('nombres', ascending: true);

      print('📊 Trabajadores disponibles: ${response.length}');

      final workers = (response as List)
          .map((json) => AvailableWorker.fromJson(json))
          .toList();

      // Guardar en cache
      await _saveAvailableWorkersCache(workers);

      return workers;
    } catch (e) {
      print('❌ Error obteniendo trabajadores disponibles: $e');
      
      // Intentar cargar desde cache
      try {
        return await _getAvailableWorkersOffline();
      } catch (cacheError) {
        print('❌ Error cargando desde cache: $cacheError');
        return [];
      }
    }
  }

  /// Agregar trabajador(es) al turno
  static Future<Map<String, dynamic>> addWorkersToShift({
    required int idTurno,
    required List<int> idsTrabajadores,
    DateTime? horaEntrada,
  }) async {
    try {
      print('➕ Agregando ${idsTrabajadores.length} trabajador(es) al turno $idTurno...');

      // Verificar modo offline
      final isOffline = await _userPrefs.isOfflineModeEnabled();

      if (isOffline) {
        print('🔌 Modo offline - Guardando localmente...');
        return await _addWorkersOffline(
          idTurno: idTurno,
          idsTrabajadores: idsTrabajadores,
          horaEntrada: horaEntrada,
        );
      }

      final entrada = horaEntrada ?? DateTime.now();
      final List<Map<String, dynamic>> insertData = [];

      for (final idTrabajador in idsTrabajadores) {
        insertData.add({
          'id_turno': idTurno,
          'id_trabajador': idTrabajador,
          'hora_entrada': entrada.toIso8601String(),
        });
      }

      // Insertar en Supabase
      await _supabase.from('app_dat_turno_trabajadores').insert(insertData);

      print('✅ Trabajadores agregados exitosamente');

      return {
        'success': true,
        'message': '${idsTrabajadores.length} trabajador(es) agregado(s) al turno',
      };
    } catch (e) {
      print('❌ Error agregando trabajadores: $e');
      
      // Si falla, intentar guardar offline
      if (e.toString().contains('duplicate') || 
          e.toString().contains('unique')) {
        return {
          'success': false,
          'message': 'Uno o más trabajadores ya están en el turno',
        };
      }

      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
      };
    }
  }

  /// Registrar salida de trabajador(es)
  static Future<Map<String, dynamic>> registerWorkersExit({
    required List<int> idsRegistros,
    DateTime? horaSalida,
  }) async {
    try {
      print('🚪 Registrando salida de ${idsRegistros.length} trabajador(es)...');

      // Verificar modo offline
      final isOffline = await _userPrefs.isOfflineModeEnabled();

      if (isOffline) {
        print('🔌 Modo offline - Guardando localmente...');
        return await _registerExitOffline(
          idsRegistros: idsRegistros,
          horaSalida: horaSalida,
        );
      }

      final salida = horaSalida ?? DateTime.now();

      // Actualizar registros en Supabase
      for (final id in idsRegistros) {
        await _supabase
            .from('app_dat_turno_trabajadores')
            .update({'hora_salida': salida.toIso8601String()})
            .eq('id', id);
      }

      print('✅ Salida registrada exitosamente');

      return {
        'success': true,
        'message': 'Salida registrada para ${idsRegistros.length} trabajador(es)',
      };
    } catch (e) {
      print('❌ Error registrando salida: $e');
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
      };
    }
  }

  // ==================== MÉTODOS OFFLINE ====================

  /// Obtener trabajadores del turno desde cache offline
  static Future<List<ShiftWorker>> _getShiftWorkersOffline(int idTurno) async {
    final offlineData = await _userPrefs.getOfflineData();
    if (offlineData == null || offlineData.isEmpty) return [];
    
    final shiftWorkersData = offlineData['shift_workers'] as Map<String, dynamic>?;
    
    if (shiftWorkersData == null) {
      print('⚠️ No hay datos de trabajadores en cache');
      return [];
    }

    final turnoKey = idTurno.toString();
    final workersJson = shiftWorkersData[turnoKey] as List<dynamic>?;

    if (workersJson == null || workersJson.isEmpty) {
      return [];
    }

    return workersJson
        .map((json) => ShiftWorker.fromOfflineJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Obtener trabajadores disponibles desde cache offline
  static Future<List<AvailableWorker>> _getAvailableWorkersOffline() async {
    final offlineData = await _userPrefs.getOfflineData();
    if (offlineData == null || offlineData.isEmpty) return [];
    
    final workersJson = offlineData['available_workers'] as List<dynamic>?;

    if (workersJson == null || workersJson.isEmpty) {
      print('⚠️ No hay trabajadores disponibles en cache');
      return [];
    }

    return workersJson
        .map((json) => AvailableWorker.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Guardar trabajadores del turno en cache
  static Future<void> _saveShiftWorkersCache(
    int idTurno,
    List<ShiftWorker> workers,
  ) async {
    try {
      final offlineData = await _userPrefs.getOfflineData();
      Map<String, dynamic> shiftWorkersData = {};
      
      if (offlineData != null && offlineData.isNotEmpty && offlineData.containsKey('shift_workers')) {
        final existingData = offlineData['shift_workers'];
        if (existingData is Map<String, dynamic>) {
          shiftWorkersData = Map<String, dynamic>.from(existingData);
        }
      }
      
      shiftWorkersData[idTurno.toString()] = workers
          .map((w) => w.toOfflineJson())
          .toList();

      await _userPrefs.mergeOfflineData({'shift_workers': shiftWorkersData});
      print('💾 Trabajadores del turno guardados en cache');
    } catch (e) {
      print('❌ Error guardando trabajadores en cache: $e');
    }
  }

  /// Guardar trabajadores disponibles en cache
  static Future<void> _saveAvailableWorkersCache(
    List<AvailableWorker> workers,
  ) async {
    try {
      final workersJson = workers.map((w) => {
        'id': w.id,
        'nombres': w.nombres,
        'apellidos': w.apellidos,
        'id_roll': w.idRol,
        'seg_roll': w.rol != null ? {'denominacion': w.rol} : null,
      }).toList();

      await _userPrefs.mergeOfflineData({'available_workers': workersJson});
      print('💾 Trabajadores disponibles guardados en cache');
    } catch (e) {
      print('❌ Error guardando trabajadores disponibles: $e');
    }
  }

  /// Agregar trabajadores offline
  static Future<Map<String, dynamic>> _addWorkersOffline({
    required int idTurno,
    required List<int> idsTrabajadores,
    DateTime? horaEntrada,
  }) async {
    try {
      final entrada = horaEntrada ?? DateTime.now();
      
      // Obtener trabajadores disponibles para obtener nombres
      final availableWorkers = await _getAvailableWorkersOffline();
      
      // Crear operaciones pendientes
      for (final idTrabajador in idsTrabajadores) {
        final worker = availableWorkers.firstWhere(
          (w) => w.id == idTrabajador,
          orElse: () => AvailableWorker(
            id: idTrabajador,
            nombres: 'Trabajador',
            apellidos: '#$idTrabajador',
          ),
        );

        final offlineId = 'shift_worker_${DateTime.now().millisecondsSinceEpoch}_$idTrabajador';
        
        await _userPrefs.savePendingOperation({
          'type': 'add_shift_worker',
          'offline_id': offlineId,
          'data': {
            'id_turno': idTurno,
            'id_trabajador': idTrabajador,
            'nombres_trabajador': worker.nombres,
            'apellidos_trabajador': worker.apellidos,
            'rol_trabajador': worker.rol,
            'hora_entrada': entrada.toIso8601String(),
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          },
        });
      }

      print('✅ Trabajadores guardados offline para sincronización');

      return {
        'success': true,
        'message': 'Trabajadores agregados offline. Se sincronizarán cuando haya conexión.',
      };
    } catch (e) {
      print('❌ Error agregando trabajadores offline: $e');
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
      };
    }
  }

  /// Registrar salida offline
  static Future<Map<String, dynamic>> _registerExitOffline({
    required List<int> idsRegistros,
    DateTime? horaSalida,
  }) async {
    try {
      final salida = horaSalida ?? DateTime.now();

      for (final id in idsRegistros) {
        await _userPrefs.savePendingOperation({
          'type': 'register_worker_exit',
          'data': {
            'id_registro': id,
            'hora_salida': salida.toIso8601String(),
          },
        });
      }

      print('✅ Salida guardada offline para sincronización');

      return {
        'success': true,
        'message': 'Salida registrada offline. Se sincronizará cuando haya conexión.',
      };
    } catch (e) {
      print('❌ Error registrando salida offline: $e');
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
      };
    }
  }

  /// Sincronizar operaciones pendientes (llamado por AutoSyncService)
  static Future<int> syncPendingOperations() async {
    try {
      print('🔄 Sincronizando operaciones de trabajadores de turno...');
      
      final pendingOps = await _userPrefs.getPendingOperations();
      int syncedCount = 0;

      for (final op in pendingOps) {
        final type = op['type'] as String;
        
        if (type == 'add_shift_worker') {
          final data = op['data'] as Map<String, dynamic>;
          
          try {
            await _supabase.from('app_dat_turno_trabajadores').insert({
              'id_turno': data['id_turno'],
              'id_trabajador': data['id_trabajador'],
              'hora_entrada': data['hora_entrada'],
            });
            
            syncedCount++;
            print('  ✅ Trabajador agregado sincronizado');
          } catch (e) {
            print('  ❌ Error sincronizando trabajador: $e');
          }
        } else if (type == 'register_worker_exit') {
          final data = op['data'] as Map<String, dynamic>;
          
          try {
            await _supabase
                .from('app_dat_turno_trabajadores')
                .update({'hora_salida': data['hora_salida']})
                .eq('id', data['id_registro']);
            
            syncedCount++;
            print('  ✅ Salida de trabajador sincronizada');
          } catch (e) {
            print('  ❌ Error sincronizando salida: $e');
          }
        }
      }

      if (syncedCount > 0) {
        print('✅ $syncedCount operaciones de trabajadores sincronizadas');
      }

      return syncedCount;
    } catch (e) {
      print('❌ Error sincronizando operaciones de trabajadores: $e');
      return 0;
    }
  }
}

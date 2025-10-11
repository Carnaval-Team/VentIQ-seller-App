import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';

/// Servicio para gestionar vendedores
/// Responsabilidades:
/// - CRUD de vendedores
/// - Asignación/desasignación de TPVs
/// - Obtener trabajadores disponibles
/// - Estadísticas de vendedores
class VendedorService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  // ==================== CONSULTAS ====================

  /// Obtiene todos los vendedores de la tienda
  static Future<List<Map<String, dynamic>>> getVendedoresByStore() async {
    try {
      final userPrefs = UserPreferencesService();
      final storeId = await userPrefs.getIdTienda();
      if (storeId == null) {
        throw Exception('No se pudo obtener el ID de la tienda');
      }

      // Primero obtener IDs de trabajadores de la tienda
      final trabajadoresResponse = await _supabase
          .from('app_dat_trabajadores')
          .select('id')
          .eq('id_tienda', storeId);

      final trabajadoresIds = trabajadoresResponse
          .map((t) => t['id'])
          .where((id) => id != null)
          .toList();

      if (trabajadoresIds.isEmpty) {
        print('⚠️ No hay trabajadores en la tienda $storeId');
        return [];
      }

      // Luego obtener vendedores que pertenecen a esos trabajadores
      final response = await _supabase
          .from('app_dat_vendedor')
          .select('''
            *,
            trabajador:app_dat_trabajadores(
              id,
              nombres,
              apellidos,
              id_roll,
              id_tienda
            ),
            tpv:app_dat_tpv(
              id,
              denominacion
            )
          ''')
          .inFilter('id_trabajador', trabajadoresIds)
          .order('created_at', ascending: false);

      print('✅ Vendedores obtenidos: ${response.length} para tienda $storeId');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo vendedores: $e');
      return [];
    }
  }

  /// Obtiene trabajadores disponibles (sin asignar como vendedores)
  static Future<List<Map<String, dynamic>>> getTrabajadoresDisponibles() async {
    try {
      final userPrefs = UserPreferencesService();
      final storeId = await userPrefs.getIdTienda();
      if (storeId == null) {
        throw Exception('No se pudo obtener el ID de la tienda');
      }

      // Obtener IDs de trabajadores que ya son vendedores
      final vendedoresResponse = await _supabase
          .from('app_dat_vendedor')
          .select('id_trabajador');

      final trabajadoresVendedores =
          vendedoresResponse
              .map((v) => v['id_trabajador'])
              .where((id) => id != null)
              .toList();

      // Obtener trabajadores que NO están en la lista de vendedores
      var query = _supabase
          .from('app_dat_trabajadores')
          .select('id, nombres, apellidos, id_roll')
          .eq('id_tienda', storeId);

      if (trabajadoresVendedores.isNotEmpty) {
        query = query.not('id', 'nin', trabajadoresVendedores);
      }
      query.order('nombres');
      final response = await query;

      print('✅ Trabajadores disponibles: ${response.length}');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo trabajadores disponibles: $e');
      return [];
    }
  }

  /// Obtiene estadísticas de vendedores
  static Future<Map<String, dynamic>> getVendedoresStatistics() async {
    try {
      final userPrefs = UserPreferencesService();
      final storeId = await userPrefs.getIdTienda();
      if (storeId == null) {
        throw Exception('No se pudo obtener el ID de la tienda');
      }

      final vendedores = await getVendedoresByStore();
      final vendedoresConTpv =
          vendedores.where((v) => v['id_tpv'] != null).length;

      return {
        'total_vendedores': vendedores.length,
        'vendedores_con_tpv': vendedoresConTpv,
        'vendedores_sin_tpv': vendedores.length - vendedoresConTpv,
        'tpvs_con_vendedor': vendedoresConTpv,
      };
    } catch (e) {
      print('❌ Error obteniendo estadísticas: $e');
      return {
        'total_vendedores': 0,
        'vendedores_con_tpv': 0,
        'vendedores_sin_tpv': 0,
        'tpvs_con_vendedor': 0,
      };
    }
  }

  // ==================== CREAR ====================

  /// Crea un vendedor desde un trabajador existente
  static Future<bool> createVendedor({
    required int trabajadorId,
    required int tpvId,
    required String uuid,
  }) async {
    try {
      final vendedorData = {
        'id_trabajador': trabajadorId,
        'id_tpv': tpvId,
        'uuid': uuid,
        'created_at': DateTime.now().toIso8601String(),
      };

      await _supabase.from('app_dat_vendedor').insert(vendedorData);
      print('✅ Vendedor creado exitosamente');
      return true;
    } catch (e) {
      print('❌ Error creando vendedor: $e');
      return false;
    }
  }

  /// Crea un trabajador y vendedor desde cero
  static Future<bool> createTrabajadorYVendedor({
    required String nombres,
    required String apellidos,
    required int idRoll,
    required int idTienda,
    required int tpvId,
    required String uuid,
  }) async {
    try {
      // 1. Crear trabajador
      final trabajadorData = {
        'nombres': nombres,
        'apellidos': apellidos,
        'id_roll': idRoll,
        'id_tienda': idTienda,
        'created_at': DateTime.now().toIso8601String(),
      };

      final trabajadorResponse =
          await _supabase
              .from('app_dat_trabajadores')
              .insert(trabajadorData)
              .select('id')
              .single();

      final trabajadorId = trabajadorResponse['id'];

      // 2. Crear vendedor
      return await createVendedor(
        trabajadorId: trabajadorId,
        tpvId: tpvId,
        uuid: uuid,
      );
    } catch (e) {
      print('❌ Error creando trabajador y vendedor: $e');
      return false;
    }
  }

  // ==================== ASIGNACIÓN DE TPV ====================

  /// Asigna o reasigna un vendedor a un TPV
  static Future<bool> asignarVendedorATpv({
    required int vendedorId,
    required int tpvId,
  }) async {
    try {
      await _supabase
          .from('app_dat_vendedor')
          .update({
            'id_tpv': tpvId,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', vendedorId);

      print('✅ Vendedor asignado a TPV exitosamente');
      return true;
    } catch (e) {
      print('❌ Error asignando vendedor a TPV: $e');
      return false;
    }
  }

  /// Desasigna un vendedor de su TPV
  static Future<bool> desasignarVendedorDeTpv(int vendedorId) async {
    try {
      await _supabase
          .from('app_dat_vendedor')
          .update({
            'id_tpv': null,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', vendedorId);

      print('✅ Vendedor desasignado de TPV exitosamente');
      return true;
    } catch (e) {
      print('❌ Error desasignando vendedor de TPV: $e');
      return false;
    }
  }

  // ==================== ELIMINAR ====================

  /// Elimina un vendedor
  static Future<bool> deleteVendedor(int vendedorId) async {
    try {
      await _supabase.from('app_dat_vendedor').delete().eq('id', vendedorId);

      print('✅ Vendedor eliminado exitosamente');
      return true;
    } catch (e) {
      print('❌ Error eliminando vendedor: $e');
      return false;
    }
  }

  // ==================== VALIDACIONES ====================

  /// Valida si un trabajador ya es vendedor
  static Future<bool> isTrabajadorVendedor(int trabajadorId) async {
    try {
      final response =
          await _supabase
              .from('app_dat_vendedor')
              .select('id')
              .eq('id_trabajador', trabajadorId)
              .maybeSingle();

      return response != null;
    } catch (e) {
      print('❌ Error validando trabajador: $e');
      return false;
    }
  }

  /// Valida si un TPV ya tiene vendedor asignado
  static Future<bool> tpvTieneVendedor(int tpvId) async {
    try {
      final response =
          await _supabase
              .from('app_dat_vendedor')
              .select('id')
              .eq('id_tpv', tpvId)
              .maybeSingle();

      return response != null;
    } catch (e) {
      print('❌ Error validando TPV: $e');
      return false;
    }
  }
}
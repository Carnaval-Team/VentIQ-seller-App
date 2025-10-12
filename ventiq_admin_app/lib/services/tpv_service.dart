import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';

class TpvService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  // ==================== GESTIÓN DE TPVs ====================

  /// Obtiene todos los TPVs de la tienda del usuario
  static Future<List<Map<String, dynamic>>> getTpvsByStore() async {
    try {
      final userPrefs = UserPreferencesService();
      final storeId = await userPrefs.getIdTienda(); // ✅
      if (storeId == null) {
        throw Exception('No se pudo obtener el ID de la tienda del usuario');
      }

      final response = await _supabase
          .from('app_dat_tpv')
          .select('''
      *,
      vendedor:app_dat_vendedor(
        id,
        trabajador:app_dat_trabajadores(
          nombres,
          apellidos
        )
      )
    ''')
          .eq('id_tienda', storeId)
          .order('denominacion');

      print('📱 TPVs obtenidos: ${response.length}');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo TPVs: $e');
      return [];
    }
  }

  /// Crea un nuevo TPV
  static Future<bool> createTpv({
    required String denominacion,
    String? descripcion,
    int? idVendedor,
    String? ubicacion,
    bool esActivo = true,
  }) async {
    try {
      final userPrefs = UserPreferencesService();
      final storeId = await userPrefs.getIdTienda(); // ✅
      if (storeId == null) {
        throw Exception('No se pudo obtener el ID de la tienda del usuario');
      }

      final tpvData = {
        'denominacion': denominacion,
        'descripcion': descripcion,
        'id_vendedor': idVendedor,
        'ubicacion': ubicacion,
        'id_tienda': storeId,
        'created_at': DateTime.now().toIso8601String(),
      };

      await _supabase.from('app_dat_tpv').insert(tpvData);
      print('✅ TPV creado exitosamente: $denominacion');
      return true;
    } catch (e) {
      print('❌ Error creando TPV: $e');
      return false;
    }
  }

  /// Actualiza un TPV existente
  static Future<bool> updateTpv({
    required int id,
    String? denominacion,
    String? descripcion,
    int? idVendedor,
    String? ubicacion,
    bool? esActivo,
  }) async {
    try {
      final userPrefs = UserPreferencesService();
      final storeId = await userPrefs.getIdTienda(); // ✅
      if (storeId == null) {
        throw Exception('No se pudo obtener el ID de la tienda del usuario');
      }

      final updateData = <String, dynamic>{};
      if (denominacion != null) updateData['denominacion'] = denominacion;
      if (descripcion != null) updateData['descripcion'] = descripcion;
      if (idVendedor != null) updateData['id_vendedor'] = idVendedor;
      if (ubicacion != null) updateData['ubicacion'] = ubicacion;
      if (esActivo != null) updateData['es_activo'] = esActivo;

      updateData['updated_at'] = DateTime.now().toIso8601String();

      await _supabase
          .from('app_dat_tpv')
          .update(updateData)
          .eq('id', id)
          .eq('id_tienda', storeId);

      print('✅ TPV actualizado exitosamente: ID $id');
      return true;
    } catch (e) {
      print('❌ Error actualizando TPV: $e');
      return false;
    }
  }

  /// Elimina un TPV (soft delete)
  static Future<bool> deleteTpv(int id) async {
    try {
      final userPrefs = UserPreferencesService();
      final storeId = await userPrefs.getIdTienda();
      if (storeId == null) {
        throw Exception('No se pudo obtener el ID de la tienda del usuario');
      }

      // Verificar si el TPV tiene precios asociados (SIN filtrar por id_tienda)
      final pricesCount = await _supabase
          .from('app_dat_precio_tpv')
          .select('id')
          .eq('id_tpv', id)
          .isFilter('deleted_at', null)
          .count(CountOption.exact);

      if ((pricesCount.count ?? 0) > 0) {
        print('⚠️ No se puede eliminar TPV con precios asociados');
        return false;
      }

      await _supabase
          .from('app_dat_tpv')
          .update({
            'es_activo': false,
            'deleted_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id)
          .eq('id_tienda', storeId);

      print('✅ TPV eliminado exitosamente: ID $id');
      return true;
    } catch (e) {
      print('❌ Error eliminando TPV: $e');
      return false;
    }
  }

  /// Obtiene TPV por ID
  static Future<Map<String, dynamic>?> getTpvById(int id) async {
    try {
      final userPrefs = UserPreferencesService();
      final storeId = await userPrefs.getIdTienda(); // ✅
      if (storeId == null) {
        throw Exception('No se pudo obtener el ID de la tienda del usuario');
      }

      final response =
          await _supabase
              .from('app_dat_tpv')
              .select('''
      *,
      vendedor:app_dat_vendedor(
        id,
        trabajador:app_dat_trabajadores(
          nombres,
          apellidos
        )
      )
    ''')
              .eq('id', id)
              .eq('id_tienda', storeId)
              .single();

      return response;
    } catch (e) {
      print('❌ Error obteniendo TPV por ID: $e');
      return null;
    }
  }

  /// Obtiene estadísticas de un TPV específico
  static Future<Map<String, dynamic>> getTpvStatistics(int tpvId) async {
    try {
      final userPrefs = UserPreferencesService();
      final storeId = await userPrefs.getIdTienda();
      if (storeId == null) {
        throw Exception('No se pudo obtener el ID de la tienda del usuario');
      }

      // Contar precios activos del TPV (SIN filtrar por id_tienda)
      final activePrices = await _supabase
          .from('app_dat_precio_tpv')
          .select('id')
          .eq('id_tpv', tpvId)
          .eq('es_activo', true)
          .isFilter('deleted_at', null)
          .count(CountOption.exact);

      // Contar productos únicos con precios (SIN filtrar por id_tienda)
      final uniqueProducts = await _supabase
          .from('app_dat_precio_tpv')
          .select('id_producto')
          .eq('id_tpv', tpvId)
          .eq('es_activo', true)
          .isFilter('deleted_at', null);

      final productCount =
          uniqueProducts.map((item) => item['id_producto']).toSet().length;

      // Obtener última venta
      final lastSale =
          await _supabase
              .from('app_dat_operacion_venta')
              .select('created_at')
              .eq('id_tpv', tpvId)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();

      return {
        'tpv_id': tpvId,
        'active_prices': activePrices.count ?? 0,
        'unique_products': productCount,
        'last_sale': lastSale?['created_at'],
        'last_updated': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('❌ Error obteniendo estadísticas del TPV: $e');
      return {
        'tpv_id': tpvId,
        'active_prices': 0,
        'unique_products': 0,
        'error': e.toString(),
      };
    }
  }

  /// Valida si se puede eliminar un TPV
  static Future<Map<String, dynamic>> validateTpvDeletion(int tpvId) async {
    try {
      final userPrefs = UserPreferencesService();
      final storeId = await userPrefs.getIdTienda();
      if (storeId == null) {
        throw Exception('No se pudo obtener el ID de la tienda del usuario');
      }

      // Verificar precios activos (SIN filtrar por id_tienda)
      final activePrices = await _supabase
          .from('app_dat_precio_tpv')
          .select('id')
          .eq('id_tpv', tpvId)
          .eq('es_activo', true)
          .isFilter('deleted_at', null)
          .count(CountOption.exact);

      // Verificar ventas recientes (últimos 30 días)
      final thirtyDaysAgo = DateTime.now().subtract(Duration(days: 30));
      final recentSales = await _supabase
          .from('app_dat_operacion_venta')
          .select('id')
          .eq('id_tpv', tpvId)
          .gte('created_at', thirtyDaysAgo.toIso8601String())
          .count(CountOption.exact);

      final canDelete =
          (activePrices.count ?? 0) == 0 && (recentSales.count ?? 0) == 0;

      return {
        'can_delete': canDelete,
        'active_prices': activePrices.count ?? 0,
        'recent_sales': recentSales.count ?? 0,
        'reasons':
            canDelete
                ? []
                : [
                  if ((activePrices.count ?? 0) > 0)
                    'Tiene precios activos asociados',
                  if ((recentSales.count ?? 0) > 0)
                    'Tiene ventas recientes (últimos 30 días)',
                ],
      };
    } catch (e) {
      print('❌ Error validando eliminación de TPV: $e');
      return {'can_delete': false, 'error': e.toString()};
    }
  }

  /// Busca TPVs por término
  static Future<List<Map<String, dynamic>>> searchTpvs(
    String searchTerm,
  ) async {
    try {
      final userPrefs = UserPreferencesService();
      final storeId = await userPrefs.getIdTienda(); // ✅
      if (storeId == null) {
        throw Exception('No se pudo obtener el ID de la tienda del usuario');
      }

      final response = await _supabase
          .from('app_dat_tpv')
          .select('''
      *,
      vendedor:app_dat_vendedor(
        id,
        trabajador:app_dat_trabajadores(
          nombres,
          apellidos
        )
      )
    ''')
          .eq('id_tienda', storeId)
          .or('denominacion.ilike.%$searchTerm%,ubicacion.ilike.%$searchTerm%')
          .order('denominacion');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error buscando TPVs: $e');
      return [];
    }
  }

  /// Obtiene TPVs con sus estadísticas
  static Future<List<Map<String, dynamic>>> getTpvsWithStats() async {
    try {
      final tpvs = await getTpvsByStore();
      final tpvsWithStats = <Map<String, dynamic>>[];

      for (final tpv in tpvs) {
        final stats = await getTpvStatistics(tpv['id']);
        tpvsWithStats.add({...tpv, 'statistics': stats});
      }

      return tpvsWithStats;
    } catch (e) {
      print('❌ Error obteniendo TPVs con estadísticas: $e');
      return [];
    }
  }

  // Agregar al TpvService
  static Future<List<Map<String, dynamic>>> getTpvsDisponibles() async {
    try {
      final userPrefs = UserPreferencesService();
      final storeId = await userPrefs.getIdTienda();
      if (storeId == null) {
        throw Exception('No se pudo obtener el ID de la tienda del usuario');
      }

      // Obtener todos los TPVs activos
      final allTpvs = await _supabase
          .from('app_dat_tpv')
          .select('id, denominacion, descripcion')
          .eq('id_tienda', storeId)
          .eq('es_activo', true)
          .isFilter('deleted_at', null);

      // Obtener TPVs que ya tienen vendedor asignado
      final tpvsConVendedor = await _supabase
          .from('app_dat_vendedor')
          .select('id_tpv')
          .not('id_tpv', 'is', null);

      final tpvsOcupados =
          tpvsConVendedor
              .map((v) => v['id_tpv'])
              .where((id) => id != null)
              .toSet();

      // Filtrar TPVs disponibles (sin vendedor asignado)
      final tpvsDisponibles =
          allTpvs.where((tpv) => !tpvsOcupados.contains(tpv['id'])).toList();

      return tpvsDisponibles;
    } catch (e) {
      print('❌ Error obteniendo TPVs disponibles: $e');
      return [];
    }
  }
}

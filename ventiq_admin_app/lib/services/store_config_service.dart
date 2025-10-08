import 'package:supabase_flutter/supabase_flutter.dart';

class StoreConfigService {
  static final _supabase = Supabase.instance.client;

  /// Obtiene la configuración de la tienda
  /// Si no existe, la crea con valores por defecto
  static Future<Map<String, dynamic>> getStoreConfig(int storeId) async {
    try {
      print('🔧 Obteniendo configuración para tienda ID: $storeId');
      
      // Intentar obtener configuración existente
      final response = await _supabase
          .from('app_dat_configuracion_tienda')
          .select('*')
          .eq('id_tienda', storeId)
          .maybeSingle();

      if (response != null) {
        print('✅ Configuración encontrada para tienda $storeId');
        return response;
      } else {
        print('⚠️ No existe configuración para tienda $storeId, creando con valores por defecto...');
        
        // Crear configuración con valores por defecto
        final newConfig = await _supabase
            .from('app_dat_configuracion_tienda')
            .insert({
              'id_tienda': storeId,
              'need_master_password_to_cancel': false,
              'need_all_orders_completed_to_continue': false,
            })
            .select()
            .single();

        print('✅ Configuración creada para tienda $storeId con valores por defecto');
        return newConfig;
      }
    } catch (e) {
      print('❌ Error al obtener/crear configuración de tienda: $e');
      rethrow;
    }
  }

  /// Actualiza la configuración de la tienda
  static Future<Map<String, dynamic>> updateStoreConfig(
    int storeId, {
    bool? needMasterPasswordToCancel,
    bool? needAllOrdersCompletedToContinue,
  }) async {
    try {
      print('🔧 Actualizando configuración para tienda ID: $storeId');
      
      final updateData = <String, dynamic>{};
      
      if (needMasterPasswordToCancel != null) {
        updateData['need_master_password_to_cancel'] = needMasterPasswordToCancel;
        print('  - need_master_password_to_cancel: $needMasterPasswordToCancel');
      }
      
      if (needAllOrdersCompletedToContinue != null) {
        updateData['need_all_orders_completed_to_continue'] = needAllOrdersCompletedToContinue;
        print('  - need_all_orders_completed_to_continue: $needAllOrdersCompletedToContinue');
      }

      if (updateData.isEmpty) {
        throw Exception('No hay datos para actualizar');
      }

      final response = await _supabase
          .from('app_dat_configuracion_tienda')
          .update(updateData)
          .eq('id_tienda', storeId)
          .select()
          .single();

      print('✅ Configuración actualizada exitosamente para tienda $storeId');
      return response;
    } catch (e) {
      print('❌ Error al actualizar configuración de tienda: $e');
      rethrow;
    }
  }

  /// Obtiene solo el valor de need_master_password_to_cancel
  static Future<bool> getNeedMasterPasswordToCancel(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['need_master_password_to_cancel'] ?? false;
    } catch (e) {
      print('❌ Error al obtener need_master_password_to_cancel: $e');
      return false; // Valor por defecto en caso de error
    }
  }

  /// Obtiene solo el valor de need_all_orders_completed_to_continue
  static Future<bool> getNeedAllOrdersCompletedToContinue(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['need_all_orders_completed_to_continue'] ?? false;
    } catch (e) {
      print('❌ Error al obtener need_all_orders_completed_to_continue: $e');
      return false; // Valor por defecto en caso de error
    }
  }

  /// Actualiza solo need_master_password_to_cancel
  static Future<void> updateNeedMasterPasswordToCancel(int storeId, bool value) async {
    await updateStoreConfig(storeId, needMasterPasswordToCancel: value);
  }

  /// Actualiza solo need_all_orders_completed_to_continue
  static Future<void> updateNeedAllOrdersCompletedToContinue(int storeId, bool value) async {
    await updateStoreConfig(storeId, needAllOrdersCompletedToContinue: value);
  }
}

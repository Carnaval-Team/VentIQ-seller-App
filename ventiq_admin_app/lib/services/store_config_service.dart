import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

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
    String? masterPassword,
    bool? manejaInventario,
    bool? permiteVenderAunSinDisponibilidad,
    bool? noSolicitarCliente,
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
      
      if (masterPassword != null) {
        // Encriptar la contraseña usando SHA-256
        final bytes = utf8.encode(masterPassword);
        final digest = sha256.convert(bytes);
        updateData['master_password'] = digest.toString();
        print('  - master_password: [ENCRIPTADA]');
      }
      
      if (manejaInventario != null) {
        updateData['maneja_inventario'] = manejaInventario;
        print('  - maneja_inventario: $manejaInventario');
      }
      
      if (permiteVenderAunSinDisponibilidad != null) {
        updateData['permite_vender_aun_sin_disponibilidad'] = permiteVenderAunSinDisponibilidad;
        print('  - permite_vender_aun_sin_disponibilidad: $permiteVenderAunSinDisponibilidad');
      }
      
      if (noSolicitarCliente != null) {
        updateData['no_solicitar_cliente'] = noSolicitarCliente;
        print('  - no_solicitar_cliente: $noSolicitarCliente');
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

  /// Actualiza solo master_password
  static Future<void> updateMasterPassword(int storeId, String password) async {
    await updateStoreConfig(storeId, masterPassword: password);
  }

  /// Obtiene el master_password (encriptado)
  static Future<String?> getMasterPassword(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['master_password'];
    } catch (e) {
      print('❌ Error al obtener master_password: $e');
      return null;
    }
  }

  /// Verifica si existe un master_password configurado
  static Future<bool> hasMasterPassword(int storeId) async {
    try {
      final masterPassword = await getMasterPassword(storeId);
      return masterPassword != null && masterPassword.isNotEmpty;
    } catch (e) {
      print('❌ Error al verificar master_password: $e');
      return false;
    }
  }

  /// Obtiene solo el valor de maneja_inventario
  static Future<bool> getManejaInventario(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['maneja_inventario'] ?? false;
    } catch (e) {
      print('❌ Error al obtener maneja_inventario: $e');
      return false; // Valor por defecto en caso de error
    }
  }

  /// Actualiza solo maneja_inventario
  static Future<void> updateManejaInventario(int storeId, bool value) async {
    await updateStoreConfig(storeId, manejaInventario: value);
  }

  /// Obtiene solo el valor de permite_vender_aun_sin_disponibilidad
  static Future<bool> getPermiteVenderAunSinDisponibilidad(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['permite_vender_aun_sin_disponibilidad'] ?? false;
    } catch (e) {
      print('❌ Error al obtener permite_vender_aun_sin_disponibilidad: $e');
      return false; // Valor por defecto en caso de error
    }
  }

  /// Actualiza solo permite_vender_aun_sin_disponibilidad
  static Future<void> updatePermiteVenderAunSinDisponibilidad(int storeId, bool value) async {
    await updateStoreConfig(storeId, permiteVenderAunSinDisponibilidad: value);
  }

  /// Obtiene solo el valor de no_solicitar_cliente
  static Future<bool> getNoSolicitarCliente(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['no_solicitar_cliente'] ?? false;
    } catch (e) {
      print('❌ Error al obtener no_solicitar_cliente: $e');
      return false; // Valor por defecto en caso de error
    }
  }

  /// Actualiza solo no_solicitar_cliente
  static Future<void> updateNoSolicitarCliente(int storeId, bool value) async {
    await updateStoreConfig(storeId, noSolicitarCliente: value);
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';
import 'connectivity_service.dart';

class StoreConfigService {
  static final _supabase = Supabase.instance.client;
  static final _userPreferencesService = UserPreferencesService();

  /// Obtiene la configuración de la tienda desde Supabase
  static Future<Map<String, dynamic>?> getStoreConfigFromSupabase(
    int storeId,
  ) async {
    try {
      print(
        '🔧 Obteniendo configuración de tienda desde Supabase para ID: $storeId',
      );

      final response =
          await _supabase
              .from('app_dat_configuracion_tienda')
              .select('*')
              .eq('id_tienda', storeId)
              .maybeSingle();

      if (response != null) {
        print('✅ Configuración de tienda obtenida desde Supabase');
        print(
          '  - need_master_password_to_cancel: ${response['need_master_password_to_cancel']}',
        );
        print(
          '  - need_all_orders_completed_to_continue: ${response['need_all_orders_completed_to_continue']}',
        );
        print(
          '  - permite_vender_aun_sin_disponibilidad: ${response['permite_vender_aun_sin_disponibilidad']}',
        );
        print('  - no_solicitar_cliente: ${response['no_solicitar_cliente']}');
        return response;
      } else {
        print('⚠️ No existe configuración para tienda $storeId en Supabase');
        return null;
      }
    } catch (e) {
      print('❌ Error al obtener configuración de tienda desde Supabase: $e');
      return null;
    }
  }

  /// Guarda la configuración de tienda en cache offline
  static Future<void> saveStoreConfigToCache(
    Map<String, dynamic> config,
  ) async {
    try {
      print('💾 Guardando configuración de tienda en cache offline...');

      await _userPreferencesService.saveStoreConfig(config);

      print('✅ Configuración de tienda guardada en cache offline');
      print(
        '  - need_master_password_to_cancel: ${config['need_master_password_to_cancel']}',
      );
      print(
        '  - need_all_orders_completed_to_continue: ${config['need_all_orders_completed_to_continue']}',
      );
      print(
        '  - permite_vender_aun_sin_disponibilidad: ${config['permite_vender_aun_sin_disponibilidad']}',
      );
      print('  - no_solicitar_cliente: ${config['no_solicitar_cliente']}');
    } catch (e) {
      print('❌ Error al guardar configuración de tienda en cache: $e');
    }
  }

  /// Obtiene la configuración de tienda desde cache offline
  static Future<Map<String, dynamic>?> getStoreConfigFromCache() async {
    try {
      print('📱 Obteniendo configuración de tienda desde cache offline...');

      final config = await _userPreferencesService.getStoreConfig();

      if (config != null) {
        print('✅ Configuración de tienda obtenida desde cache offline');
        print(
          '  - need_master_password_to_cancel: ${config['need_master_password_to_cancel']}',
        );
        print(
          '  - need_all_orders_completed_to_continue: ${config['need_all_orders_completed_to_continue']}',
        );
        print(
          '  - permite_vender_aun_sin_disponibilidad: ${config['permite_vender_aun_sin_disponibilidad']}',
        );
        print('  - no_solicitar_cliente: ${config['no_solicitar_cliente']}');
      } else {
        print('⚠️ No hay configuración de tienda en cache offline');
      }

      return config;
    } catch (e) {
      print('❌ Error al obtener configuración de tienda desde cache: $e');
      return null;
    }
  }

  /// Obtiene la configuración de tienda (online primero, luego offline)
  static Future<Map<String, dynamic>?> getStoreConfig(int storeId) async {
    try {
      // ✅ NUEVO: Verificar conectividad real PRIMERO, no solo el modo offline
      final connectivityService = ConnectivityService();
      final hasRealConnection = await connectivityService.checkConnectivity();

      // Verificar si modo offline está activado
      final isOfflineMode =
          await _userPreferencesService.isOfflineModeEnabled();

      print('🔍 Estado de conexión:');
      print('  • Modo offline activado: $isOfflineMode');
      print('  • Conectividad real: $hasRealConnection');

      // ✅ IMPORTANTE: Si hay conexión real, siempre intentar obtener desde Supabase
      if (hasRealConnection && !isOfflineMode) {
        print(
          '🌐 Conexión real detectada - Cargando configuración desde Supabase...',
        );

        // Intentar obtener desde Supabase
        final config = await getStoreConfigFromSupabase(storeId);

        if (config != null) {
          // Guardar en cache para uso offline futuro
          await saveStoreConfigToCache(config);
          return config;
        } else {
          // Si no hay en Supabase, intentar desde cache como fallback
          print('🔄 Fallback: Intentando cargar desde cache offline...');
          return await getStoreConfigFromCache();
        }
      } else if (isOfflineMode || !hasRealConnection) {
        print(
          '🔌 Modo offline o sin conexión - Cargando configuración desde cache...',
        );
        return await getStoreConfigFromCache();
      }
    } catch (e) {
      print('❌ Error al obtener configuración de tienda: $e');

      // Fallback final: intentar desde cache
      print('🔄 Fallback final: Intentando cargar desde cache offline...');
      return await getStoreConfigFromCache();
    }
  }

  /// Sincroniza la configuración de tienda (para uso en sincronización automática)
  static Future<bool> syncStoreConfig(int storeId) async {
    try {
      print('🔄 Sincronizando configuración de tienda...');

      final config = await getStoreConfigFromSupabase(storeId);

      if (config != null) {
        await saveStoreConfigToCache(config);
        print('✅ Configuración de tienda sincronizada exitosamente');
        return true;
      } else {
        print('⚠️ No se pudo sincronizar configuración de tienda');
        return false;
      }
    } catch (e) {
      print('❌ Error al sincronizar configuración de tienda: $e');
      return false;
    }
  }

  /// Obtiene solo el valor de need_master_password_to_cancel
  static Future<bool> getNeedMasterPasswordToCancel(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config?['need_master_password_to_cancel'] ?? false;
    } catch (e) {
      print('❌ Error al obtener need_master_password_to_cancel: $e');
      return false; // Valor por defecto en caso de error
    }
  }

  /// Obtiene solo el valor de need_all_orders_completed_to_continue
  static Future<bool> getNeedAllOrdersCompletedToContinue(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config?['need_all_orders_completed_to_continue'] ?? false;
    } catch (e) {
      print('❌ Error al obtener need_all_orders_completed_to_continue: $e');
      return false; // Valor por defecto en caso de error
    }
  }

  /// Obtiene solo el valor de permite_vender_aun_sin_disponibilidad
  static Future<bool> getPermiteVenderAunSinDisponibilidad(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config?['permite_vender_aun_sin_disponibilidad'] ?? false;
    } catch (e) {
      print('❌ Error al obtener permite_vender_aun_sin_disponibilidad: $e');
      return false; // Valor por defecto en caso de error
    }
  }

  /// Obtiene solo el valor de no_solicitar_cliente
  static Future<bool> getNoSolicitarCliente(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config?['no_solicitar_cliente'] ?? false;
    } catch (e) {
      print('❌ Error al obtener no_solicitar_cliente: $e');
      return false; // Valor por defecto en caso de error
    }
  }

  /// Obtiene solo el valor de allow_discount_on_vendedor
  static Future<bool> getAllowDiscountOnVendedor(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      final value = config?['allow_discount_on_vendedor'] ?? false;
      print('✅ allow_discount_on_vendedor: $value para tienda $storeId');
      return value;
    } catch (e) {
      print('❌ Error al obtener allow_discount_on_vendedor: $e');
      return false;
    }
  }

  /// Verifica si hay configuración de tienda en cache
  static Future<bool> hasStoreConfigInCache() async {
    try {
      final config = await _userPreferencesService.getStoreConfig();
      return config != null;
    } catch (e) {
      print('❌ Error al verificar configuración de tienda en cache: $e');
      return false;
    }
  }

  /// Limpia la configuración de tienda del cache
  static Future<void> clearStoreConfigCache() async {
    try {
      print('🗑️ Limpiando configuración de tienda del cache...');
      await _userPreferencesService.clearStoreConfig();
      print('✅ Configuración de tienda eliminada del cache');
    } catch (e) {
      print('❌ Error al limpiar configuración de tienda del cache: $e');
    }
  }
}

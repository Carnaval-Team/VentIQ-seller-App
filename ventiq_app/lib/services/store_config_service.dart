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
      // Reflejar el flag de modo restaurante en el cache sincrónico.
      _modoRestauranteCached = config['modo_restaurante'] == true;
      _cocinaActivaCached = config['cocina_activa'] == true;

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
      final isOfflineMode =
          await _userPreferencesService.isOfflineModeEnabled();
      final stayFullyOffline =
          await _userPreferencesService.shouldStayFullyOffline();

      // Full offline / modo offline: solo cache — no ping ni Supabase.
      if (isOfflineMode || stayFullyOffline) {
        print(
          '🔌 Modo offline/full-offline - Cargando configuración desde cache...',
        );
        return await getStoreConfigFromCache();
      }

      final connectivityService = ConnectivityService();
      final hasRealConnection = await connectivityService.checkConnectivity();

      print('🔍 Estado de conexión:');
      print('  • Modo offline activado: $isOfflineMode');
      print('  • Conectividad real: $hasRealConnection');

      if (hasRealConnection) {
        print(
          '🌐 Conexión real detectada - Cargando configuración desde Supabase...',
        );

        final config = await getStoreConfigFromSupabase(storeId);

        if (config != null) {
          await saveStoreConfigToCache(config);
          return config;
        } else {
          print('🔄 Fallback: Intentando cargar desde cache offline...');
          return await getStoreConfigFromCache();
        }
      } else {
        print(
          '📵 Sin conexión - Cargando configuración desde cache...',
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

  // Cache sincrónico del flag modo_restaurante para que la lógica de
  // navegación (botón Home → /mesas vs /categories) pueda decidirlo sin
  // esperar un Future. Se siembra desde:
  //   - getModoRestaurante / saveStoreConfigToCache / setModoRestaurante
  //   - getStoreConfigFromCache (al leerse en cualquier pantalla)
  static bool _modoRestauranteCached = false;
  static bool get modoRestauranteSync => _modoRestauranteCached;

  // Cache sincronico de cocina_activa. La Fase 2 ("pedir != cobrar") solo se
  // activa cuando la tienda tiene el modulo de cocina encendido; si esta
  // apagado, agregar a la cuenta sigue siendo puramente contable como antes.
  // Se necesita sincronico porque OrderService.addItemToCurrentOrder decide la
  // ruta sin poder esperar un Future.
  static bool _cocinaActivaCached = false;
  static bool get cocinaActivaSync => _cocinaActivaCached;

  /// Carga el valor cacheado desde SharedPreferences de forma async. Llamar
  /// una vez en `main()` antes de runApp para que el primer render del drawer
  /// y del bottom-nav ya tenga el estado correcto.
  static Future<void> primeModoRestauranteCache() async {
    final config = await getStoreConfigFromCache();
    _modoRestauranteCached = config?['modo_restaurante'] == true;
    _cocinaActivaCached = config?['cocina_activa'] == true;
    print('🍽️ modo_restaurante (cache sincrónico): $_modoRestauranteCached');
  }

  /// Obtiene el valor de modo_restaurante para la tienda
  static Future<bool> getModoRestaurante(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      final value = config?['modo_restaurante'] ?? false;
      _modoRestauranteCached = value == true;
      print('✅ modo_restaurante: $value para tienda $storeId');
      return value;
    } catch (e) {
      print('❌ Error al obtener modo_restaurante: $e');
      return false;
    }
  }

  /// Actualiza modo_restaurante en Supabase y refresca el cache.
  /// Devuelve true si la operación terminó correctamente.
  static Future<bool> setModoRestaurante(int storeId, bool enabled) async {
    try {
      print('🔧 Actualizando modo_restaurante=$enabled para tienda $storeId');

      // Upsert para crear el registro si no existe
      await _supabase.from('app_dat_configuracion_tienda').upsert({
        'id_tienda': storeId,
        'modo_restaurante': enabled,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'id_tienda');

      // Refrescar cache
      final config = await getStoreConfigFromSupabase(storeId);
      if (config != null) {
        await saveStoreConfigToCache(config);
      } else {
        // Si por alguna razón no se pudo leer, actualizar al menos la key
        final cached = await getStoreConfigFromCache() ?? {};
        cached['modo_restaurante'] = enabled;
        await saveStoreConfigToCache(cached);
      }

      _modoRestauranteCached = enabled;
      print('✅ modo_restaurante actualizado correctamente');
      return true;
    } catch (e) {
      print('❌ Error al actualizar modo_restaurante: $e');
      return false;
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

  /// Obtiene si los vendedores pueden crear ventas a pago pendiente (cuentas
  /// por cobrar) libremente desde el checkout.
  static Future<bool> getVendedoresPuedenCrearCxc(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      final value = config?['vendedores_pueden_crear_cxc'] ?? false;
      print('✅ vendedores_pueden_crear_cxc: $value para tienda $storeId');
      return value;
    } catch (e) {
      print('❌ Error al obtener vendedores_pueden_crear_cxc: $e');
      return false;
    }
  }

  /// Obtiene el valor de permitir_imprimir_pendientes
  static Future<bool> getAllowPrintPending(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      final value = config?['permitir_imprimir_pendientes'] ?? false;
      print('✅ permitir_imprimir_pendientes: $value para tienda $storeId');
      return value;
    } catch (e) {
      print('❌ Error al obtener permitir_imprimir_pendientes: $e');
      return false;
    }
  }

  /// Obtiene el valor de solicitar_imagen_operacion.
  static Future<bool> getSolicitarImagenOperacion(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config?['solicitar_imagen_operacion'] == true;
    } catch (e) {
      print('❌ Error al obtener solicitar_imagen_operacion: $e');
      return false;
    }
  }

  /// Obtiene el valor de allow_seller_make_order_modifications
  static Future<bool> getAllowSellerMakeOrderModifications(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      final value = config?['allow_seller_make_order_modifications'] ?? false;
      print(
        '✅ allow_seller_make_order_modifications: $value para tienda $storeId',
      );
      return value;
    } catch (e) {
      print('❌ Error al obtener allow_seller_make_order_modifications: $e');
      return false;
    }
  }

  /// Obtiene el valor de permitir_modo_offline_completo.
  /// Funciona offline porque getStoreConfig cae al cache local sin conexión.
  static Future<bool> getPermitirModoOfflineCompleto(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      final value = config?['permitir_modo_offline_completo'] == true;
      print('✅ permitir_modo_offline_completo: $value para tienda $storeId');
      return value;
    } catch (e) {
      print('❌ Error al obtener permitir_modo_offline_completo: $e');
      return false;
    }
  }

  /// Obtiene el valor de dias_max_sin_validar_licencia.
  static Future<int> getDiasMaxSinValidarLicencia(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      final raw = config?['dias_max_sin_validar_licencia'];
      final value = raw is int ? raw : int.tryParse('$raw') ?? 7;
      print('✅ dias_max_sin_validar_licencia: $value para tienda $storeId');
      return value;
    } catch (e) {
      print('❌ Error al obtener dias_max_sin_validar_licencia: $e');
      return 7;
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

  /// Obtiene el valor de guardar_impresora_por_defecto.
  static Future<bool> getGuardarImpresoraPorDefecto(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config?['guardar_impresora_por_defecto'] == true;
    } catch (e) {
      print('❌ Error al obtener guardar_impresora_por_defecto: $e');
      return false;
    }
  }

  /// Actualiza guardar_impresora_por_defecto.
  static Future<bool> setGuardarImpresoraPorDefecto(
    int storeId,
    bool enabled,
  ) async {
    return await _updateBooleanStoreConfig(
      storeId,
      'guardar_impresora_por_defecto',
      enabled,
    );
  }

  /// Obtiene la lista de tickets a imprimir.
  static Future<List<String>> getTicketsAImprimir(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      final raw = config?['tickets_a_imprimir'];
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
      return ['cliente', 'almacen'];
    } catch (e) {
      print('❌ Error al obtener tickets_a_imprimir: $e');
      return ['cliente', 'almacen'];
    }
  }

  /// Actualiza tickets_a_imprimir.
  static Future<bool> setTicketsAImprimir(
    int storeId,
    List<String> tickets,
  ) async {
    try {
      print('🔧 Actualizando tickets_a_imprimir=$tickets para tienda $storeId');
      await _supabase.from('app_dat_configuracion_tienda').upsert({
        'id_tienda': storeId,
        'tickets_a_imprimir': tickets,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'id_tienda');
      await _refreshStoreConfigCache(storeId);
      print('✅ tickets_a_imprimir actualizado correctamente');
      return true;
    } catch (e) {
      print('❌ Error al actualizar tickets_a_imprimir: $e');
      return false;
    }
  }

  /// Obtiene el mapa de copias por ticket.
  static Future<Map<String, int>> getCopiasPorTicket(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      final raw = config?['copias_por_ticket'];
      if (raw is Map) {
        return raw.map(
          (key, value) => MapEntry(key.toString(), (value as num).toInt()),
        );
      }
      return {'cliente': 1, 'almacen': 1};
    } catch (e) {
      print('❌ Error al obtener copias_por_ticket: $e');
      return {'cliente': 1, 'almacen': 1};
    }
  }

  /// Actualiza copias_por_ticket.
  static Future<bool> setCopiasPorTicket(
    int storeId,
    Map<String, int> copias,
  ) async {
    try {
      print('🔧 Actualizando copias_por_ticket=$copias para tienda $storeId');
      await _supabase.from('app_dat_configuracion_tienda').upsert({
        'id_tienda': storeId,
        'copias_por_ticket': copias,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'id_tienda');
      await _refreshStoreConfigCache(storeId);
      print('✅ copias_por_ticket actualizado correctamente');
      return true;
    } catch (e) {
      print('❌ Error al actualizar copias_por_ticket: $e');
      return false;
    }
  }

  /// Obtiene el valor de autocompletar_cantidad_real_conteo.
  static Future<bool> getAutocompletarCantidadRealConteo(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config?['autocompletar_cantidad_real_conteo'] == true;
    } catch (e) {
      print('❌ Error al obtener autocompletar_cantidad_real_conteo: $e');
      return false;
    }
  }

  /// Actualiza autocompletar_cantidad_real_conteo.
  static Future<bool> setAutocompletarCantidadRealConteo(
    int storeId,
    bool enabled,
  ) async {
    return await _updateBooleanStoreConfig(
      storeId,
      'autocompletar_cantidad_real_conteo',
      enabled,
    );
  }

  /// Helper para actualizar un booleano en la configuración de tienda.
  static Future<bool> _updateBooleanStoreConfig(
    int storeId,
    String column,
    bool value,
  ) async {
    try {
      print('🔧 Actualizando $column=$value para tienda $storeId');
      await _supabase.from('app_dat_configuracion_tienda').upsert({
        'id_tienda': storeId,
        column: value,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'id_tienda');
      await _refreshStoreConfigCache(storeId);
      print('✅ $column actualizado correctamente');
      return true;
    } catch (e) {
      print('❌ Error al actualizar $column: $e');
      return false;
    }
  }

  /// Refresca el cache local después de un update parcial.
  static Future<void> _refreshStoreConfigCache(int storeId) async {
    try {
      final config = await getStoreConfigFromSupabase(storeId);
      if (config != null) {
        await saveStoreConfigToCache(config);
      }
    } catch (e) {
      print('❌ Error refrescando cache de configuración: $e');
    }
  }
}

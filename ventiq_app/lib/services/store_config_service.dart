import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../money/politica_moneda.dart';
import '../utils/uuid_generator.dart';
import 'user_preferences_service.dart';
import 'connectivity_service.dart';

bool _rpcAusente(Object error, String functionName) {
  final text = error.toString().toLowerCase();
  if (text.contains('42501') ||
      text.contains('insufficient_privilege') ||
      text.contains('permission denied') ||
      text.contains('acceso denegado')) {
    return false;
  }
  final fn = functionName.toLowerCase();
  return text.contains('pgrst202') ||
      text.contains('could not find the function') ||
      text.contains('schema cache') ||
      (text.contains('does not exist') && text.contains(fn));
}

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

  /// Configuración de la tienda de la sesión actual.
  ///
  /// Apertura y cierre deben usar esto y no solo el cache: en web el login
  /// no siempre deja `store_config` poblado, y sin `maneja_inventario` el
  /// turno se crea o se cierra como si la tienda no controlara inventario.
  static Future<Map<String, dynamic>?> getStoreConfigForSession() async {
    final idTienda = await _userPreferencesService.getIdTienda();
    if (idTienda != null) {
      final config = await getStoreConfig(idTienda);
      if (config != null) return config;
    }
    return getStoreConfigFromCache();
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
        await syncPoliticaMoneda(storeId, config);
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

  /// Revisión y constancia, aparte del select de la configuración.
  static Future<void> syncPoliticaMoneda(
    int storeId,
    Map<String, dynamic> config,
  ) async {
    final sesion = await _userPreferencesService.getIdTienda();
    if (!PoliticaMonedaEstado.puedeReemplazar(
      tiendaRespuesta: storeId,
      tiendaSesion: sesion,
    )) {
      return;
    }
    final usuario = _supabase.auth.currentUser?.id;
    Map<String, dynamic>? revision;
    Map<String, dynamic>? constancia;
    var denegada = false;
    if (usuario != null) {
      try {
        await _supabase.rpc(
          'fn_m01_emitir_constancia_politica',
          params: {
            'p_id_tienda': storeId,
            'p_dispositivo': await _dispositivoPolitica(),
          },
        );
      } catch (e) {
        if (!_rpcAusente(e, 'fn_m01_emitir_constancia_politica')) {
          denegada = true;
        }
      }
    }
    try {
      final row =
          await _supabase
              .from('app_dat_politica_moneda_revision')
              .select(
                'id, id_tienda, permitir_moneda_por_producto, forzar_moneda_venta, moneda_venta_forzada, monedas_habilitadas',
              )
              .eq('id_tienda', storeId)
              .order('id', ascending: false)
              .limit(1)
              .maybeSingle();
      if (row != null) revision = Map<String, dynamic>.from(row);
    } catch (e) {
      if (!_rpcAusente(e, 'app_dat_politica_moneda_revision')) denegada = true;
    }
    try {
      if (usuario != null) {
        final row =
            await _supabase
                .from('app_dat_politica_moneda_constancia')
                .select('id, id_tienda, id_revision, uuid_sujeto, dispositivo, huella')
                .eq('id_tienda', storeId)
                .eq('uuid_sujeto', usuario)
                .order('id', ascending: false)
                .limit(1)
                .maybeSingle();
        if (row != null) constancia = Map<String, dynamic>.from(row);
      }
    } catch (e) {
      if (!_rpcAusente(e, 'app_dat_politica_moneda_constancia')) denegada = true;
    }
    await _userPreferencesService.savePoliticaMoneda({
      'id_tienda': storeId,
      'flag': config['permitir_moneda_por_producto'] == true,
      'denegada': denegada,
      'revision': revision,
      'constancia': constancia,
    });
  }

  static Future<String> _dispositivoPolitica() async {
    final prefs = await SharedPreferences.getInstance();
    final guardado = prefs.getString('m01_dispositivo');
    final valido = RegExp(r'^[A-Za-z0-9_.:-]{1,120}$');
    if (guardado != null && valido.hasMatch(guardado)) return guardado;
    final nuevo = 'tpv-${UuidGenerator.v4().replaceAll('-', '').substring(0, 20)}';
    await prefs.setString('m01_dispositivo', nuevo);
    return nuevo;
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

      await _escribirConfig(storeId, 'modo_restaurante', enabled);

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

  /// Si el ticket debe imprimir el método / desglose de pago.
  /// Default `true` (comportamiento histórico) si la columna aún no existe.
  static Future<bool> getMostrarMetodoPagoTicket(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      final value = config?['mostrar_metodo_pago_ticket'];
      if (value == null) return true;
      return value == true;
    } catch (e) {
      print('❌ Error al obtener mostrar_metodo_pago_ticket: $e');
      return true;
    }
  }

  /// Si el checkout muestra el toggle CUP/USD por método de pago.
  /// Default `false` — la tienda debe habilitarlo explícitamente.
  static Future<bool> getMostrarSelectorMoneda(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      final value = config?['mostrar_selector_moneda'];
      if (value == null) return false;
      return value == true;
    } catch (e) {
      print('❌ Error al obtener mostrar_selector_moneda: $e');
      return false;
    }
  }

  /// Si la tienda obliga a vender en una sola divisa.
  ///
  /// Con esto activo el vendedor no puede cambiar la moneda de venta: ni en el
  /// chip de la barra ni en el selector por línea del checkout.
  static Future<bool> getForzarMonedaVenta(int storeId) async {
    return (await getMonedaVentaForzadaConfig(storeId)).forzar;
  }

  /// Divisa que la tienda impone (`null` si no hay ninguna forzada).
  ///
  /// Solo devuelve el código tal cual lo declara la tienda: que además sea una
  /// divisa **aceptada y con tasa** lo valida quien conoce las tasas, que es
  /// `MonedaVentaService`.
  static Future<String?> getMonedaVentaForzada(int storeId) async {
    return (await getMonedaVentaForzadaConfig(storeId)).moneda;
  }

  /// Lee de una sola vez el par `forzar_moneda_venta` / `moneda_venta_forzada`.
  ///
  /// Los dos valores se consumen siempre juntos y cada `getStoreConfig` cuesta
  /// su comprobación de conectividad: separarlos duplicaría ese trabajo sin
  /// aportar nada. El código se normaliza aquí y se descarta si no tiene forma
  /// de divisa ISO, para que ningún llamador tenga que defenderse de un valor
  /// basura.
  static Future<({bool forzar, String? moneda})> getMonedaVentaForzadaConfig(
    int storeId,
  ) async {
    try {
      final config = await getStoreConfig(storeId);
      final forzar = config?['forzar_moneda_venta'] == true;
      final codigo = _normalizarCodigoMoneda(config?['moneda_venta_forzada']);
      return (forzar: forzar, moneda: forzar ? codigo : null);
    } catch (e) {
      print('❌ Error al obtener forzar_moneda_venta: $e');
      return (forzar: false, moneda: null);
    }
  }

  /// `'USD'` a partir de `' usd '`; `null` si no es un código ISO de divisa.
  static String? _normalizarCodigoMoneda(Object? raw) {
    final codigo = (raw ?? '').toString().trim().toUpperCase();
    return RegExp(r'^[A-Z]{3}$').hasMatch(codigo) ? codigo : null;
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
      await _escribirConfig(storeId, 'tickets_a_imprimir', tickets);
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
      await _escribirConfig(storeId, 'copias_por_ticket', copias);
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
      await _escribirConfig(storeId, column, value);
      await _refreshStoreConfigCache(storeId);
      print('✅ $column actualizado correctamente');
      return true;
    } catch (e) {
      print('❌ Error al actualizar $column: $e');
      return false;
    }
  }

  /// Escribe un campo permitido. Si la función no existe, conserva el upsert.
  /// Una denegación no abre la tabla.
  static Future<void> _escribirConfig(
    int storeId,
    String campo,
    Object valor,
  ) async {
    try {
      final respuesta = await _supabase.rpc(
        'fn_m01_actualizar_config_tienda',
        params: {
          'p_client_uuid': UuidGenerator.v4(),
          'p_id_tienda': storeId,
          'p_campo': campo,
          'p_valor': valor,
        },
      );
      final mapa = respuesta is Map
          ? Map<String, dynamic>.from(respuesta)
          : null;
      if (mapa == null || mapa['success'] != true) {
        throw Exception(
          mapa?['message'] ?? 'No se actualizó la configuración',
        );
      }
    } catch (e) {
      if (!_rpcAusente(e, 'fn_m01_actualizar_config_tienda')) rethrow;
      await _supabase.from('app_dat_configuracion_tienda').upsert({
        'id_tienda': storeId,
        campo: valor,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'id_tienda');
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

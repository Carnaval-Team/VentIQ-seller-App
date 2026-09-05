import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/promotion_rules.dart';
import '../utils/uuid_generator.dart';
import 'admin_access_service.dart';
import 'order_service.dart';
import 'offline_database_service.dart';

class UserPreferencesService {
  static final UserPreferencesService _instance =
      UserPreferencesService._internal();
  factory UserPreferencesService() => _instance;
  UserPreferencesService._internal();

  static const String _userIdKey = 'user_id';
  static const String _userEmailKey = 'user_email';
  static const String _accessTokenKey = 'access_token';
  static const String _isLoggedInKey = 'is_logged_in';

  // Seller data keys
  static const String _idTpvKey = 'id_tpv';
  static const String _idTrabajadorKey = 'id_trabajador';
  static const String _manejaAperturaControlCacheKey =
      'maneja_apertura_control_cache';
  static const String _idSellerKey = 'id_seller';
  static const String _nombresKey = 'nombres';
  static const String _apellidosKey = 'apellidos';
  static const String _idTiendaKey = 'id_tienda';
  static const String _idRollKey = 'id_roll';
  static const String _appVersionKey = 'app_version';
  static const String _appIdAlmacenKey = 'id_almacen';
  static const String _allowCustomSalePriceKey =
      'permitir_customizar_precio_venta';

  // Remember me keys
  static const String _rememberMeKey = 'remember_me';
  static const String _savedEmailKey = 'saved_email';
  static const String _savedPasswordKey = 'saved_password';
  static const String _tokenExpiryKey = 'token_expiry';

  // Promotion keys
  static const String _promotionIdKey = 'promotion_id';
  static const String _promotionCodeKey = 'promotion_code';
  static const String _promotionValueKey = 'promotion_value';
  static const String _promotionTypeKey = 'promotion_type';
  static const String _promotionTypeIdKey = 'promotion_type_id';
  static const String _promotionMinCompraKey = 'promotion_min_compra';
  static const String _promotionAplicaTodoKey = 'promotion_aplica_todo';
  static const String _promotionRequiereMedioPagoKey =
      'promotion_requiere_medio_pago';
  static const String _promotionIdMedioPagoRequeridoKey =
      'promotion_id_medio_pago_requerido';
  static const String _productPromotionsKey = 'product_promotions';

  // Data usage keys
  static const String _limitDataUsageKey = 'limit_data_usage';

  // Fluid mode keys
  static const String _fluidModeKey = 'fluid_mode_enabled';

  // Superadmin flag (cacheado en login; usado para herramientas ocultas)
  static const String _isSuperAdminKey = 'is_superadmin';
  // Rol admin de tienda (gerente/supervisor) cacheado para Admin Lite offline
  static const String _adminRoleKeyPrefix = 'caja_admin_role_';
  // Rol de entrada a Caja: vendedor | gerente | supervisor
  static const String _cajaEntryRoleKey = 'caja_entry_role';
  // Rol de cocina cacheado: 'jefe_cocina' | 'cocinero' | '' (ninguno).
  // Se cachea porque decide el home de la sesión y consultarlo en cada
  // navegación costaría una RPC por toque del botón Home.
  static const String _cocinaRoleKey = 'caja_cocina_role';

  // Offline mode keys
  static const String _offlineModeKey = 'offline_mode_enabled';
  static const String _offlineDataKey = 'offline_data';
  static const String _offlineDataStagingKey = 'offline_data_staging';
  static const String _offlineUsersKey =
      'offline_users'; // Array de usuarios offline
  static const String _pendingOrdersKey =
      'pending_orders'; // Órdenes pendientes de sincronización
  static const String _pendingOperationsKey =
      'pending_operations'; // Operaciones pendientes (apertura/cierre/cambio estado)
  static const String _offlineTurnoKey =
      'offline_turno'; // Legacy: un solo turno (migrado a cola)
  static const String _offlineTurnosKey =
      'offline_turnos'; // Cola multi-turno offline (open + cerrados pendientes)
  static const String _turnoResumenKey =
      'turno_resumen_cache'; // Cache del resumen de turno anterior
  static const String _resumenCierreKey =
      'resumen_cierre_cache'; // Cache del resumen de cierre diario
  /// Checkpoint de sync modular interrumpida (para reanudar por partes).
  static const String _syncModulesCheckpointKey = 'sync_modules_checkpoint';
  static const String _egresosOfflineKey =
      'egresos_offline'; // Egresos creados offline
  static const String _egresosCacheKey =
      'egresos_cache'; // Cache de egresos para modo offline
  static const String _storeConfigKey =
      'store_config'; // Configuración de la tienda
  // Inventario/catálogo offline compartido por tienda (vendedor + admin
  // en el mismo teléfono usan el mismo stock local).
  static const String _offlineInventoryStoreKey = 'offline_inventory_store_id';
  // Legacy: dueño por usuario (ya no se usa para wipe; se migra a tienda)
  static const String _offlineDataOwnerKey = 'offline_data_owner';
  // Dispositivo preparado para full offline (admin primero + switch local)
  static const String _deviceFullOfflineReadyKey = 'device_full_offline_ready';
  static const String _deviceFullOfflineStoreKey =
      'device_full_offline_store_id';
  static const String _deviceFullOfflineAdminEmailKey =
      'device_full_offline_admin_email';
  static const String _deviceFullOfflineAdminPasswordKey =
      'device_full_offline_admin_password';

  // Persistent preorder keys
  static const String _persistentPreorderKey =
      'persistent_preorder'; // Preorden persistente

  // Default order items key
  static const String _defaultOrderItemsKey = 'default_order_items';

  // Conteos de inventario durante cierre (por TPV)
  static const String _inventoryCountCierreKeyPrefix =
      'inventory_count_cierre_';
  // Conteos de inventario durante apertura (por TPV)
  static const String _inventoryCountAperturaKeyPrefix =
      'inventory_count_apertura_';

  // Subscription keys
  static const String _subscriptionIdKey = 'subscription_id';
  static const String _subscriptionStateKey = 'subscription_state';
  static const String _subscriptionPlanIdKey = 'subscription_plan_id';
  static const String _subscriptionPlanNameKey = 'subscription_plan_name';
  static const String _subscriptionStartDateKey = 'subscription_start_date';
  static const String _subscriptionEndDateKey = 'subscription_end_date';
  static const String _subscriptionFeaturesKey = 'subscription_features';
  static const String _subscriptionLastCheckKey = 'subscription_last_check';

  // Licencia offline firmada + anti-rollback de reloj
  static const String _signedOfflineLicenseKey = 'signed_offline_license';
  static const String _signedOfflineLicenseFirmaKey =
      'signed_offline_license_firma';
  static const String _lastSeenTimestampKey = 'last_seen_timestamp';

  // Guardar datos del usuario
  Future<void> saveUserData({
    required String userId,
    required String email,
    required String accessToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // La sesión (credenciales/rol) es por usuario. El inventario offline es
    // por tienda: NO se borra al cambiar vendedor ↔ gerente de la misma
    // tienda. El wipe solo ocurre en [ensureOfflineStoreScope] si cambia
    // id_tienda.
    await prefs.setString(_userIdKey, userId);
    await prefs.setString(_userEmailKey, email);
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setBool(_isLoggedInKey, true);
    // Compat: recordar último usuario de sesión (ya no gobierna el wipe)
    await prefs.setString(_offlineDataOwnerKey, userId);

    // Set token expiry (24 hours from now).
    // Nota: en modo offline la sesión NO depende de esta expiración
    // (ver hasValidSession()), permite trabajar indefinidamente sin conexión.
    final expiryTime =
        DateTime.now().add(Duration(hours: 24)).millisecondsSinceEpoch;
    await prefs.setInt(_tokenExpiryKey, expiryTime);
  }

  /// Vincula el inventario/colas offline a [idTienda].
  ///
  /// - Misma tienda: conserva catálogo, stock, ventas pendientes, ops admin.
  ///   Así vendedor y admin comparten el mismo inventario en el teléfono.
  /// - Otra tienda: limpia todo el offline (no mezclar inventarios).
  Future<void> ensureOfflineStoreScope(int idTienda) async {
    final prefs = await SharedPreferences.getInstance();
    final previousStore = prefs.getInt(_offlineInventoryStoreKey);

    if (previousStore != null && previousStore != idTienda) {
      print(
        '🏪 Cambio de tienda offline ($previousStore → $idTienda): '
        'limpiando inventario y colas del dispositivo',
      );
      await clearAllOfflineDataForced();
      await clearOfflineData();
      await clearEgresosOffline();
      await clearTurnoResumenCache();
      await clearResumenCierreCache();
    } else if (previousStore == idTienda) {
      print(
        '📦 Inventario offline compartido de tienda $idTienda '
        '(vendedor/admin usan el mismo stock local)',
      );
    } else {
      print('📦 Inicializando inventario offline para tienda $idTienda');
    }

    await prefs.setInt(_offlineInventoryStoreKey, idTienda);
  }

  Future<int?> getOfflineInventoryStoreId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_offlineInventoryStoreKey);
  }

  // Obtener ID del usuario
  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey);
  }

  // Obtener email del usuario
  Future<String?> getUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userEmailKey);
  }

  Future<int?> getIdAlmacen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_appIdAlmacenKey);
  }

  // Obtener access token del usuario
  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessTokenKey);
  }

  // Guardar datos del vendedor
  Future<void> saveSellerData({
    required int idTpv,
    required int idTrabajador,
    bool? permitirCustomizarPrecioVenta,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_idTpvKey, idTpv);
    await prefs.setInt(_idTrabajadorKey, idTrabajador);
    await prefs.setBool(
      _allowCustomSalePriceKey,
      permitirCustomizarPrecioVenta ?? false,
    );
  }

  // Guardar datos del trabajador/perfil
  Future<void> saveWorkerProfile({
    required String nombres,
    required String apellidos,
    required int idTienda,
    required int idRoll,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nombresKey, nombres);
    await prefs.setString(_apellidosKey, apellidos);
    await prefs.setInt(_idTiendaKey, idTienda);
    await prefs.setInt(_idRollKey, idRoll);
  }

  // Obtener ID TPV (desde app_dat_vendedor)
  Future<int?> getIdTpv() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_idTpvKey);
  }

  // Obtener ID Tienda (desde app_dat_trabajadores)
  Future<int?> getIdTienda() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_idTiendaKey);
  }

  // Guardar ID del vendedor (desde app_dat_vendedor)
  Future<void> saveIdSeller(int idSeller) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_idSellerKey, idSeller);
  }

  Future<void> saveIdAlmacen(int idAlmacen) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_appIdAlmacenKey, idAlmacen);
  }

  // Obtener ID del vendedor
  Future<int?> getIdSeller() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_idSellerKey);
  }

  // Obtener datos del perfil del trabajador
  Future<Map<String, dynamic?>> getWorkerProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'nombres': prefs.getString(_nombresKey),
      'apellidos': prefs.getString(_apellidosKey),
      'idTienda': prefs.getInt(_idTiendaKey),
      'idTpv': prefs.getInt(_idTpvKey),
      'idRoll': prefs.getInt(_idRollKey),
      'idTrabajador': prefs.getInt(_idTrabajadorKey),
      'idSeller': prefs.getInt(_idSellerKey),
      'permitirCustomizarPrecioVenta':
          prefs.getBool(_allowCustomSalePriceKey) ?? false,
    };
  }

  Future<bool> canCustomizeSalePrice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_allowCustomSalePriceKey) ?? false;
  }

  /// Cargar configuración de maneja_apertura_control del trabajador desde la base de datos
  /// Retorna true si el trabajador debe manejar inventario en apertura/cierre
  /// Retorna true por defecto si no se encuentra el trabajador (comportamiento seguro)
  ///
  /// Offline-aware: si el modo offline/full-offline está activo, no llama a
  /// Supabase (fallaría con `Failed host lookup` sin conexión); usa el
  /// último valor cacheado (o `true` por defecto si nunca se cacheó).
  Future<bool> loadWorkerManejaAperturaControl() async {
    final prefs = await SharedPreferences.getInstance();

    if (await shouldUseLocalData()) {
      final cached = prefs.getBool(_manejaAperturaControlCacheKey);
      if (cached != null) {
        print('🔌 maneja_apertura_control desde cache offline: $cached');
        return cached;
      }
      print(
        '🔌 Offline sin cache de maneja_apertura_control; usando valor por '
        'defecto (true)',
      );
      return true;
    }

    try {
      final idTrabajador = prefs.getInt(_idTrabajadorKey);

      if (idTrabajador == null) {
        print(
          '⚠️ No se encontró ID de trabajador, usando valor por defecto (true)',
        );
        return true; // Comportamiento seguro por defecto
      }

      print(
        '🔍 Consultando maneja_apertura_control para trabajador ID: $idTrabajador',
      );

      final supabase = Supabase.instance.client;
      final response =
          await supabase
              .from('app_dat_trabajadores')
              .select('maneja_apertura_control')
              .eq('id', idTrabajador)
              .maybeSingle();

      if (response == null) {
        print('⚠️ Trabajador no encontrado, usando valor por defecto (true)');
        return true; // Comportamiento seguro si no se encuentra
      }

      final manejaAperturaControl =
          response['maneja_apertura_control'] as bool? ?? true;
      print('✅ maneja_apertura_control cargado: $manejaAperturaControl');

      await prefs.setBool(
        _manejaAperturaControlCacheKey,
        manejaAperturaControl,
      );

      return manejaAperturaControl;
    } catch (e) {
      print('❌ Error cargando maneja_apertura_control: $e');
      // Ante un error de red, usar el último valor cacheado si existe.
      final cached = prefs.getBool(_manejaAperturaControlCacheKey);
      return cached ?? true; // Comportamiento seguro en caso de error
    }
  }

  /// Guardar flag de superadmin (cacheado en login para uso offline).
  Future<void> setIsSuperAdmin(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isSuperAdminKey, value);
  }

  /// Leer flag de superadmin cacheado. Por defecto false.
  Future<bool> isSuperAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isSuperAdminKey) ?? false;
  }

  /// Cache del rol Admin Lite por tienda: 'gerente' | 'almacenero' | 'none'
  Future<void> setCachedAdminRoleRaw(int storeId, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_adminRoleKeyPrefix$storeId', role);
  }

  Future<String?> getCachedAdminRoleRaw(int storeId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_adminRoleKeyPrefix$storeId');
  }

  Future<void> setCajaEntryRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cajaEntryRoleKey, role);
  }

  Future<String?> getCajaEntryRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cajaEntryRoleKey);
  }

  /// Gerente/supervisor: solo inventario/productos (no venta).
  Future<bool> isInventoryOnlySession() async {
    final role = await getCajaEntryRole();
    return role == 'gerente' || role == 'supervisor';
  }

  // ---------- Rol de cocina (jefe de cocina / cocinero) ----------

  /// Guarda el rol de cocina de la sesión. Cadena vacía = no tiene ninguno.
  ///
  /// Se cachea en el login porque decide el home de la sesión: sin cache habría
  /// que llamar a `fn_cocinas_del_usuario` en cada navegación a Home.
  Future<void> setCocinaRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cocinaRoleKey, role);
  }

  Future<String?> getCocinaRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cocinaRoleKey);
  }

  /// Sesión de personal de cocina (jefe o cocinero).
  ///
  /// Un gerente que además tenga cocinas NO cuenta: su trabajo es la gestión de
  /// la tienda y su home sigue siendo el de administración. Solo se marca a
  /// quien accede *por* su rol de cocina.
  Future<bool> isCocinaSession() async {
    final role = await getCocinaRole();
    return role == 'jefe_cocina' || role == 'cocinero';
  }

  /// Solo el jefe puede producir tandas y mover el inventario de su cocina.
  Future<bool> isJefeCocinaSession() async {
    return await getCocinaRole() == 'jefe_cocina';
  }

  // ---------- Dispositivo full offline (admin prepara + switch local) ----------

  Future<bool> isDeviceFullOfflineReady() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_deviceFullOfflineReadyKey) ?? false;
  }

  /// Dispositivo preparado + modo offline ON: operar sin servidor aunque
  /// haya red. Solo el admin (desactivar offline en Settings / sync prep)
  /// debe volver a contactar al servidor.
  Future<bool> shouldStayFullyOffline() async {
    return await isDeviceFullOfflineReady() && await isOfflineModeEnabled();
  }

  /// Lecturas de catálogo/UI deben ir a SQLite/cache local.
  /// Incluye dispositivo full-offline ready aunque `offline_mode` parpadee
  /// en false durante un sync explícito (prep / FAB de pendientes).
  Future<bool> shouldUseLocalData() async {
    return await isOfflineModeEnabled() || await isDeviceFullOfflineReady();
  }

  Future<int?> getDeviceFullOfflineStoreId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_deviceFullOfflineStoreKey);
  }

  Future<void> setDeviceFullOfflineReady({
    required int storeId,
    required String adminEmail,
    required String adminPassword,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_deviceFullOfflineReadyKey, true);
    await prefs.setInt(_deviceFullOfflineStoreKey, storeId);
    await prefs.setString(_deviceFullOfflineAdminEmailKey, adminEmail);
    await prefs.setString(_deviceFullOfflineAdminPasswordKey, adminPassword);
  }

  Future<Map<String, String?>> getDeviceFullOfflineAdminCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'email': prefs.getString(_deviceFullOfflineAdminEmailKey),
      'password': prefs.getString(_deviceFullOfflineAdminPasswordKey),
    };
  }

  Future<void> clearDeviceFullOffline() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deviceFullOfflineReadyKey);
    await prefs.remove(_deviceFullOfflineStoreKey);
    await prefs.remove(_deviceFullOfflineAdminEmailKey);
    await prefs.remove(_deviceFullOfflineAdminPasswordKey);
  }

  /// Cierra la sesión activa localmente sin borrar inventario, colas,
  /// offline_users ni el flag full-offline del dispositivo.
  Future<void> clearSessionKeepingStoreOffline() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_idTpvKey);
    await prefs.remove(_idTrabajadorKey);
    await prefs.remove(_idSellerKey);
    await prefs.remove(_nombresKey);
    await prefs.remove(_apellidosKey);
    await prefs.remove(_idTiendaKey);
    await prefs.remove(_idRollKey);
    await prefs.remove(_allowCustomSalePriceKey);
    await prefs.remove(_cajaEntryRoleKey);
    await prefs.remove(_cocinaRoleKey);
    await prefs.remove(_appIdAlmacenKey);
    await prefs.setBool(_isLoggedInKey, false);
    await clearPromotionData();
    // Limpiar cache de rol admin por tienda para no heredar gerente→vendedor
    final keys = prefs.getKeys().where(
      (k) => k.startsWith(_adminRoleKeyPrefix),
    );
    for (final k in keys) {
      await prefs.remove(k);
    }
    // No tocar: SQLite inventario, pending orders/ops, offline_users,
    // device_full_offline_*, offline_inventory_store_id, store config offline.
    print('🔓 Sesión local limpiada (inventario/offline_users conservados)');
  }

  /// Usuarios offline de una tienda (para el selector local).
  Future<List<Map<String, dynamic>>> getOfflineUsersForStore(
    int storeId,
  ) async {
    final all = await getOfflineUsers();
    return all.where((u) {
      final id = u['idTienda'];
      return id == storeId || id?.toString() == storeId.toString();
    }).toList();
  }

  /// Guarda/actualiza un perfil offline completo (admin o vendedor) sin
  /// depender de la sesión activa en prefs.
  Future<void> upsertOfflineUserProfile(Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    final email = userData['email']?.toString();
    if (email == null || email.isEmpty) {
      throw Exception('Email requerido para usuario offline');
    }

    final usersJson = prefs.getString(_offlineUsersKey);
    List<Map<String, dynamic>> offlineUsers = [];
    if (usersJson != null) {
      final decoded = jsonDecode(usersJson) as List<dynamic>;
      offlineUsers =
          decoded
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
    }

    final existingIndex = offlineUsers.indexWhere(
      (user) => user['email'] == email,
    );
    final row = {...userData, 'lastSync': DateTime.now().toIso8601String()};
    if (existingIndex != -1) {
      offlineUsers[existingIndex] = {...offlineUsers[existingIndex], ...row};
    } else {
      offlineUsers.add(row);
    }
    await prefs.setString(_offlineUsersKey, jsonEncode(offlineUsers));
  }

  // Verificar si el usuario está logueado
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
  }

  // Limpiar todos los datos del usuario (logout)
  Future<void> clearUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_idTpvKey);
    await prefs.remove(_idTrabajadorKey);
    await prefs.remove(_idSellerKey);
    await prefs.remove(_nombresKey);
    await prefs.remove(_apellidosKey);
    await prefs.remove(_idTiendaKey);
    await prefs.remove(_idRollKey);
    await prefs.remove(_allowCustomSalePriceKey);
    await prefs.remove(_cajaEntryRoleKey);
    await prefs.remove(_cocinaRoleKey);
    await prefs.setBool(_isLoggedInKey, false);

    // Limpiar promociones al cerrar sesión
    await clearPromotionData();

    // Limpiar configuración de tienda al cerrar sesión
    await clearStoreConfig();

    // Limpiar órdenes al cerrar sesión
    await _clearOrdersOnLogout();
  }

  Future<void> clearAllCachedDataForOnlineLogout() async {
    final prefs = await SharedPreferences.getInstance();
    OrderService().clearAllOrders();
    await OfflineDatabaseService().clearAll();
    await prefs.clear();
    _cachedShowSkuEnabled = false;
    _skuCacheLoaded = false;
    print('🗑️ Caché local eliminada completamente al cerrar sesión online');
  }

  // Método privado para limpiar órdenes durante logout
  Future<void> _clearOrdersOnLogout() async {
    try {
      final orderService = OrderService();
      orderService.clearAllOrders();
      print('UserPreferencesService: Órdenes limpiadas durante logout');
    } catch (e) {
      print('Error limpiando órdenes durante logout: $e');
    }
  }

  // Guardar versión de la app
  Future<void> saveAppVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appVersionKey, version);
  }

  // Obtener versión de la app
  Future<String?> getAppVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_appVersionKey);
  }

  // Verificar si es la primera vez que se abre la app o hay una nueva versión
  Future<bool> isFirstTimeOpening([String? currentVersion]) async {
    final prefs = await SharedPreferences.getInstance();

    // Si no hay versión guardada, es primera vez
    if (!prefs.containsKey(_appVersionKey)) {
      return true;
    }

    // Si se proporciona una versión actual, comparar
    if (currentVersion != null) {
      final savedVersion = prefs.getString(_appVersionKey);
      if (savedVersion == null) {
        return true;
      }

      // Comparar versiones usando comparación semántica
      return _isNewerVersion(currentVersion, savedVersion);
    }

    // Si no se proporciona versión, usar lógica anterior
    return false;
  }

  // Comparar si la versión actual es más nueva que la guardada
  bool _isNewerVersion(String currentVersion, String savedVersion) {
    try {
      // Limpiar versiones (remover caracteres no numéricos excepto puntos)
      final cleanCurrent = currentVersion.replaceAll(RegExp(r'[^\d\.]'), '');
      final cleanSaved = savedVersion.replaceAll(RegExp(r'[^\d\.]'), '');

      // Dividir en partes (major.minor.patch)
      final currentParts =
          cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final savedParts =
          cleanSaved.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      // Asegurar que ambas listas tengan al menos 3 elementos
      while (currentParts.length < 3) currentParts.add(0);
      while (savedParts.length < 3) savedParts.add(0);

      // Comparar major.minor.patch
      for (int i = 0; i < 3; i++) {
        if (currentParts[i] > savedParts[i]) {
          return true; // Versión actual es mayor
        } else if (currentParts[i] < savedParts[i]) {
          return false; // Versión guardada es mayor
        }
        // Si son iguales, continuar con el siguiente número
      }

      // Si llegamos aquí, las versiones son iguales
      return false;
    } catch (e) {
      print('Error comparando versiones: $e');
      // En caso de error, asumir que es nueva versión para mostrar changelog
      return true;
    }
  }

  // Obtener todos los datos del usuario
  Future<Map<String, dynamic?>> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'userId': prefs.getString(_userIdKey),
      'email': prefs.getString(_userEmailKey),
      'accessToken': prefs.getString(_accessTokenKey),
      'idTpv': prefs.getInt(_idTpvKey),
      'idTrabajador': prefs.getInt(_idTrabajadorKey),
      'nombres': prefs.getString(_nombresKey),
      'apellidos': prefs.getString(_apellidosKey),
      'idTienda': prefs.getInt(_idTiendaKey),
      'idRoll': prefs.getInt(_idRollKey),
      'permitirCustomizarPrecioVenta':
          prefs.getBool(_allowCustomSalePriceKey) ?? false,
    };
  }

  // Remember Me functionality
  Future<void> saveCredentials(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedEmailKey, email);
    await prefs.setString(_savedPasswordKey, password);
    await prefs.setBool(_rememberMeKey, true);
  }

  Future<void> clearSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedEmailKey);
    await prefs.remove(_savedPasswordKey);
    await prefs.setBool(_rememberMeKey, false);
  }

  Future<Map<String, String?>> getSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'email': prefs.getString(_savedEmailKey),
      'password': prefs.getString(_savedPasswordKey),
    };
  }

  Future<bool> shouldRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rememberMeKey) ?? false;
  }

  // Token validation
  Future<bool> isTokenValid() async {
    final prefs = await SharedPreferences.getInstance();
    final expiryTime = prefs.getInt(_tokenExpiryKey);
    if (expiryTime == null) return false;

    final now = DateTime.now().millisecondsSinceEpoch;
    return now < expiryTime;
  }

  Future<bool> hasValidSession() async {
    final isLoggedIn = await this.isLoggedIn();
    final accessToken = await getAccessToken();

    if (!isLoggedIn || accessToken == null || accessToken.isEmpty) {
      return false;
    }

    // 🔌 MODO OFFLINE: la sesión NO expira mientras existan datos offline
    // válidos y un usuario offline guardado. Permite trabajar días, semanas
    // o meses sin conexión sin que la app fuerce un nuevo login.
    final offlineEnabled = await isOfflineModeEnabled();
    final isOfflineToken = accessToken == 'offline_mode';
    if (offlineEnabled || isOfflineToken) {
      final email = await getUserEmail();
      final hasOfflineUser =
          email != null && email.isNotEmpty && await this.hasOfflineUser(email);
      final hasData = await hasOfflineData();
      if (hasOfflineUser && hasData) {
        return true;
      }
      // Sin datos offline o sin usuario offline: la sesión offline no es
      // utilizable; se exige reconexión.
      return false;
    }

    // 🌐 MODO ONLINE: se respeta la expiración del token.
    final hasValidToken = await isTokenValid();
    if (hasValidToken) {
      return true;
    }

    // 🛟 FALLBACK OFFLINE: el token expiró pero el dispositivo tiene datos
    // offline completos y un usuario offline guardado (caso típico: se perdió
    // la conexión sin activar manualmente el modo offline). En vez de forzar
    // logout y arriesgar pérdida de datos, se mantiene la sesión para poder
    // seguir trabajando offline. El token se revalidará al recuperar conexión.
    final email = await getUserEmail();
    final hasOfflineUser =
        email != null && email.isNotEmpty && await this.hasOfflineUser(email);
    final hasData = await hasOfflineData();
    return hasOfflineUser && hasData;
  }

  // Promotion management methods
  Future<void> savePromotionData({
    int? idPromocion,
    String? codigoPromocion,
    double? valorDescuento,
    int? tipoDescuento,
    int? idTipoPromocion,
    double? minCompra,
    bool? aplicaTodo,
    bool? requiereMedioPago,
    int? idMedioPagoRequerido,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final resolvedTipoDescuento =
        PromotionRules.resolveTipoDescuentoFromPromotionTypeId(
          idTipoPromocion,
        ) ??
        tipoDescuento;

    if (idPromocion != null) {
      await prefs.setInt(_promotionIdKey, idPromocion);
    } else {
      await prefs.remove(_promotionIdKey);
    }

    if (codigoPromocion != null) {
      await prefs.setString(_promotionCodeKey, codigoPromocion);
    } else {
      await prefs.remove(_promotionCodeKey);
    }

    if (valorDescuento != null) {
      await prefs.setDouble(_promotionValueKey, valorDescuento);
    } else {
      await prefs.remove(_promotionValueKey);
    }

    if (resolvedTipoDescuento != null) {
      await prefs.setInt(_promotionTypeKey, resolvedTipoDescuento);
    } else {
      await prefs.remove(_promotionTypeKey);
    }

    if (idTipoPromocion != null) {
      await prefs.setInt(_promotionTypeIdKey, idTipoPromocion);
    } else {
      await prefs.remove(_promotionTypeIdKey);
    }

    if (minCompra != null) {
      await prefs.setDouble(_promotionMinCompraKey, minCompra);
    } else {
      await prefs.remove(_promotionMinCompraKey);
    }

    if (aplicaTodo != null) {
      await prefs.setBool(_promotionAplicaTodoKey, aplicaTodo);
    } else {
      await prefs.remove(_promotionAplicaTodoKey);
    }

    if (requiereMedioPago != null) {
      await prefs.setBool(_promotionRequiereMedioPagoKey, requiereMedioPago);
    } else {
      await prefs.remove(_promotionRequiereMedioPagoKey);
    }

    if (idMedioPagoRequerido != null) {
      await prefs.setInt(
        _promotionIdMedioPagoRequeridoKey,
        idMedioPagoRequerido,
      );
    } else {
      await prefs.remove(_promotionIdMedioPagoRequeridoKey);
    }
  }

  Future<Map<String, dynamic>?> getPromotionData() async {
    final prefs = await SharedPreferences.getInstance();
    final idPromocion = prefs.getInt(_promotionIdKey);
    final codigoPromocion = prefs.getString(_promotionCodeKey);
    final valorDescuento = prefs.getDouble(_promotionValueKey);
    final tipoDescuento = prefs.getInt(_promotionTypeKey);
    final idTipoPromocion = prefs.getInt(_promotionTypeIdKey);
    final minCompra = prefs.getDouble(_promotionMinCompraKey);
    final aplicaTodo = prefs.getBool(_promotionAplicaTodoKey);
    final requiereMedioPago = prefs.getBool(_promotionRequiereMedioPagoKey);
    final idMedioPagoRequerido = prefs.getInt(
      _promotionIdMedioPagoRequeridoKey,
    );

    final resolvedTipoDescuento =
        PromotionRules.resolveTipoDescuentoFromPromotionTypeId(
          idTipoPromocion,
        ) ??
        tipoDescuento;
    final tipoPromocionNombre = PromotionRules.resolveTipoPromocionNombre(
      idTipoPromocion: idTipoPromocion,
      tipoDescuento: resolvedTipoDescuento,
    );

    if (idPromocion != null && codigoPromocion != null) {
      return {
        'id_promocion': idPromocion,
        'codigo_promocion': codigoPromocion,
        'valor_descuento': valorDescuento,
        'tipo_descuento':
            resolvedTipoDescuento, // 1 = %, 2 = fijo, 3 = recargo %, 4 = recargo fijo
        'tipo_promocion_nombre': tipoPromocionNombre,
        'id_tipo_promocion': idTipoPromocion,
        'min_compra': minCompra,
        'aplica_todo': aplicaTodo,
        'requiere_medio_pago': requiereMedioPago,
        'id_medio_pago_requerido': idMedioPagoRequerido,
      };
    }
    return null;
  }

  Future<void> clearPromotionData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_promotionIdKey);
    await prefs.remove(_promotionCodeKey);
    await prefs.remove(_promotionValueKey);
    await prefs.remove(_promotionTypeKey);
    await prefs.remove(_promotionTypeIdKey);
    await prefs.remove(_promotionMinCompraKey);
    await prefs.remove(_promotionAplicaTodoKey);
    await prefs.remove(_promotionRequiereMedioPagoKey);
    await prefs.remove(_promotionIdMedioPagoRequeridoKey);
  }

  /// Guardar promociones de un producto específico
  Future<void> saveProductPromotions(
    int productId,
    List<Map<String, dynamic>> promotions,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Obtener mapa actual de promociones
      final promotionsJson = prefs.getString(_productPromotionsKey);
      Map<String, dynamic> allPromotions = {};

      if (promotionsJson != null) {
        allPromotions = jsonDecode(promotionsJson) as Map<String, dynamic>;
      }

      // Guardar promociones del producto
      allPromotions[productId.toString()] = promotions;

      // Guardar mapa actualizado
      await prefs.setString(_productPromotionsKey, jsonEncode(allPromotions));
      print(
        '✅ Promociones guardadas para producto ID: $productId (${promotions.length} promociones)',
      );
    } catch (e) {
      print('❌ Error guardando promociones de producto: $e');
    }
  }

  /// Obtener promociones de un producto específico
  Future<List<Map<String, dynamic>>?> getProductPromotions(
    int productId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final promotionsJson = prefs.getString(_productPromotionsKey);

      if (promotionsJson == null) {
        return null;
      }

      final allPromotions = jsonDecode(promotionsJson) as Map<String, dynamic>;
      final productPromotions = allPromotions[productId.toString()];

      if (productPromotions == null) {
        return null;
      }

      // Convertir a lista de mapas
      return (productPromotions as List<dynamic>)
          .map((item) => item as Map<String, dynamic>)
          .toList();
    } catch (e) {
      print('❌ Error obteniendo promociones de producto: $e');
      return null;
    }
  }

  /// Limpiar todas las promociones de productos almacenadas
  Future<void> clearProductPromotions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_productPromotionsKey);
    print('✅ Promociones de productos limpiadas');
  }

  // Turno data keys
  static const String _turnoIdKey = 'turno_id';
  static const String _turnoDataKey = 'turno_data';

  // Print settings keys
  static const String _printEnabledKey = 'print_enabled';
  static const String _printUsdEnabledKey = 'print_usd_enabled';

  // Static text settings keys
  static const String _staticTextEnabledKey = 'static_text_enabled';

  // SKU visibility settings keys
  static const String _showSkuEnabledKey = 'show_sku_enabled';
  bool _cachedShowSkuEnabled = false;
  bool _skuCacheLoaded = false;

  // Currency denominations keys
  static const String _monedasDenominacionKey = 'monedas_denominacion';
  static const String _cambioCupUsdKey = 'cambio_cup_usd';
  static const String _hiddenDenominationsKey = 'hidden_denominations';

  Future<void> saveTurnoData(Map<String, dynamic> turnoData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_turnoIdKey, turnoData['id']);
    await prefs.setString(_turnoDataKey, jsonEncode(turnoData));
  }

  Future<int?> getTurnoId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_turnoIdKey);
  }

  Future<Map<String, dynamic>?> getTurnoData() async {
    final prefs = await SharedPreferences.getInstance();
    final turnoDataString = prefs.getString(_turnoDataKey);
    if (turnoDataString != null) {
      return jsonDecode(turnoDataString) as Map<String, dynamic>;
    }
    return null;
  }

  Future<void> clearTurnoData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_turnoIdKey);
    await prefs.remove(_turnoDataKey);
  }

  // Print settings methods
  Future<void> setPrintEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_printEnabledKey, enabled);
    print(
      'UserPreferencesService: Configuración de impresión actualizada: $enabled',
    );
  }

  Future<bool> isPrintEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_printEnabledKey) ?? true; // Por defecto habilitado
  }

  Future<void> setPrintUsdEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_printUsdEnabledKey, enabled);
    print(
      'UserPreferencesService: Mostrar USD en impresión actualizado: $enabled',
    );
  }

  Future<bool> isPrintUsdEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_printUsdEnabledKey) ?? false;
  }

  // Static text settings methods
  Future<void> setStaticTextEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_staticTextEnabledKey, enabled);
    print(
      'UserPreferencesService: Configuración de textos estáticos actualizada: $enabled',
    );
  }

  Future<bool> isStaticTextEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_staticTextEnabledKey) ??
        false; // Por defecto deshabilitado (marquee activo)
  }

  // SKU visibility settings methods
  Future<void> setShowSkuEnabled(bool enabled) async {
    _cachedShowSkuEnabled = enabled;
    _skuCacheLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showSkuEnabledKey, enabled);
    print('UserPreferencesService: Mostrar SKU actualizado: $enabled');
  }

  Future<bool> isShowSkuEnabled() async {
    if (!_skuCacheLoaded) {
      final prefs = await SharedPreferences.getInstance();
      _cachedShowSkuEnabled = prefs.getBool(_showSkuEnabledKey) ?? false;
      _skuCacheLoaded = true;
    }
    return _cachedShowSkuEnabled;
  }

  /// Synchronous read — returns cached value (false until first async load).
  bool get isShowSkuEnabledSync => _cachedShowSkuEnabled;

  // Data usage settings methods
  Future<void> setLimitDataUsage(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_limitDataUsageKey, enabled);
    print('UserPreferencesService: Límite de datos actualizado: $enabled');
  }

  Future<bool> isLimitDataUsageEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_limitDataUsageKey) ??
        false; // Por defecto deshabilitado
  }

  // ==================== MODO FLUIDO ====================

  /// Habilitar o deshabilitar el modo fluido
  Future<void> setFluidModeEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_fluidModeKey, enabled);
    print('UserPreferencesService: Modo fluido actualizado: $enabled');
  }

  /// Verificar si el modo fluido está habilitado
  Future<bool> isFluidModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_fluidModeKey) ?? false; // Por defecto deshabilitado
  }

  // ==================== MODO OFFLINE ====================

  /// Habilitar o deshabilitar el modo offline
  Future<void> setOfflineMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_offlineModeKey, enabled);
    print('UserPreferencesService: Modo offline actualizado: $enabled');
  }

  Future<bool> isOfflineModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_offlineModeKey) ?? false; // Por defecto deshabilitado
  }

  // Guardar datos offline completos (SQLite)
  Future<void> saveOfflineData(Map<String, dynamic> data) async {
    await OfflineDatabaseService().saveAllFromMap(data);
    print('UserPreferencesService: Datos offline guardados (SQLite)');
  }

  Future<void> saveOfflineDataTransactional(Map<String, dynamic> data) async {
    await OfflineDatabaseService().saveAllFromMap(data);
    print(
      'UserPreferencesService: Datos offline guardados (SQLite/transaccional)',
    );
  }

  // Hacer merge inteligente de datos offline (preserva datos existentes)
  Future<void> mergeOfflineData(Map<String, dynamic> newData) async {
    print('📋 Merge offline → SQLite (${newData.keys.join(', ')})');
    print(
      '  - Categorías entrantes: ${newData['categories'] != null ? (newData['categories'] is List ? (newData['categories'] as List).length : 'Sí') : 'No'}',
    );
    print(
      '  - Productos entrantes: ${newData['products'] != null ? 'Sí' : 'No'}',
    );

    await OfflineDatabaseService().mergeSections(newData);
    print('🔄 Merge de datos offline completado (SQLite)');
  }

  // Obtener datos offline
  Future<Map<String, dynamic>?> getOfflineData() async {
    try {
      return await OfflineDatabaseService().getAllAsMap();
    } catch (e) {
      print('❌ Error leyendo offline_data desde SQLite: $e');
      return null;
    }
  }

  // Verificar si hay datos offline disponibles
  Future<bool> hasOfflineData() async {
    try {
      final data = await getOfflineData();
      if (data == null) return false;

      final hasCredentials = data['credentials'] != null;
      final hasCategories =
          data['categories'] != null && (data['categories'] as List).isNotEmpty;
      final hasProducts =
          data['products'] != null && (data['products'] as Map).isNotEmpty;

      final stats = await OfflineDatabaseService().getStats();
      print('📊 Verificación de datos offline (SQLite):');
      print('  - Credenciales: ${hasCredentials ? "✅" : "❌"}');
      print(
        '  - Categorías: ${hasCategories ? "✅" : "❌"} (${stats['categories']})',
      );
      print('  - Productos: ${hasProducts ? "✅" : "❌"} (${stats['products']})');

      // Requiere al menos credenciales y categorías para funcionar offline
      return hasCredentials && hasCategories;
    } catch (e) {
      print('❌ Error verificando datos offline: $e');
      return false;
    }
  }

  // Limpiar datos offline
  Future<void> clearOfflineData() async {
    await OfflineDatabaseService().clearAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_offlineDataKey);
    await prefs.remove(_offlineDataStagingKey);
    await prefs.setBool(_offlineModeKey, false);
    print('UserPreferencesService: Datos offline eliminados (SQLite)');
  }

  // ============= MÉTODOS PARA MÚLTIPLES USUARIOS OFFLINE =============

  /// Guardar credenciales de un usuario para modo offline
  /// Mantiene un array de usuarios con sus credenciales y datos necesarios
  Future<void> saveOfflineUser({
    required String email,
    required String password,
    required String userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Obtener datos actuales del usuario de SharedPreferences
    final idTienda = prefs.getInt(_idTiendaKey);
    final idTpv = prefs.getInt(_idTpvKey);
    final idTrabajador = prefs.getInt(_idTrabajadorKey);
    final idSeller = prefs.getInt(_idSellerKey);
    final nombres = prefs.getString(_nombresKey);
    final apellidos = prefs.getString(_apellidosKey);
    final idRoll = prefs.getInt(_idRollKey);
    final entryRole = prefs.getString(_cajaEntryRoleKey);
    final permitirCustomizarPrecioVenta =
        prefs.getBool(_allowCustomSalePriceKey) ?? false;

    // Obtener lista actual de usuarios offline
    final usersJson = prefs.getString(_offlineUsersKey);
    List<Map<String, dynamic>> offlineUsers = [];

    if (usersJson != null) {
      final decoded = jsonDecode(usersJson) as List<dynamic>;
      offlineUsers =
          decoded.map((item) => item as Map<String, dynamic>).toList();
    }

    // Verificar si el usuario ya existe (por email)
    final existingIndex = offlineUsers.indexWhere(
      (user) => user['email'] == email,
    );

    final userData = {
      'email': email,
      'password': password,
      'userId': userId,
      'idTienda': idTienda,
      'idTpv': idTpv,
      'idTrabajador': idTrabajador,
      'idSeller': idSeller,
      'nombres': nombres,
      'apellidos': apellidos,
      'idRoll': idRoll,
      'entryRole': entryRole,
      'permitir_customizar_precio_venta': permitirCustomizarPrecioVenta,
      'lastSync': DateTime.now().toIso8601String(),
    };

    if (existingIndex != -1) {
      // Actualizar usuario existente
      offlineUsers[existingIndex] = userData;
      print('✅ Usuario offline actualizado: $email');
    } else {
      // Agregar nuevo usuario
      offlineUsers.add(userData);
      print('✅ Nuevo usuario offline guardado: $email');
    }

    // Guardar array actualizado
    await prefs.setString(_offlineUsersKey, jsonEncode(offlineUsers));
    print('📱 Total de usuarios offline: ${offlineUsers.length}');
    print(
      '📊 Datos guardados: idTienda=$idTienda, idTpv=$idTpv, idTrabajador=$idTrabajador',
    );
  }

  /// Verificar si un usuario tiene credenciales guardadas para modo offline
  Future<bool> hasOfflineUser(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final usersJson = prefs.getString(_offlineUsersKey);

    if (usersJson == null) return false;

    final decoded = jsonDecode(usersJson) as List<dynamic>;
    final offlineUsers =
        decoded.map((item) => item as Map<String, dynamic>).toList();

    return offlineUsers.any((user) => user['email'] == email);
  }

  /// Validar credenciales de un usuario offline
  /// Retorna todos los datos del usuario si las credenciales son válidas
  Future<Map<String, dynamic>?> validateOfflineUser({
    required String email,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final usersJson = prefs.getString(_offlineUsersKey);

    if (usersJson == null) {
      print('❌ No hay usuarios offline guardados');
      return null;
    }

    final decoded = jsonDecode(usersJson) as List<dynamic>;
    final offlineUsers =
        decoded.map((item) => item as Map<String, dynamic>).toList();

    // Buscar usuario por email
    final user = offlineUsers.firstWhere(
      (user) => user['email'] == email,
      orElse: () => {},
    );

    if (user.isEmpty) {
      print('❌ Usuario no encontrado en modo offline: $email');
      return null;
    }

    // Validar password
    if (user['password'] == password) {
      print('✅ Credenciales offline válidas para: $email');
      // Retornar TODOS los datos del usuario
      return {
        'email': user['email'],
        'userId': user['userId'],
        'idTienda': user['idTienda'],
        'idTpv': user['idTpv'],
        'idTrabajador': user['idTrabajador'],
        'idSeller': user['idSeller'],
        'nombres': user['nombres'],
        'apellidos': user['apellidos'],
        'idRoll': user['idRoll'],
        'entryRole': user['entryRole'],
        'permitir_customizar_precio_venta':
            user['permitir_customizar_precio_venta'] ?? false,
        'lastSync': user['lastSync'],
      };
    } else {
      print('❌ Contraseña incorrecta para usuario offline: $email');
      return null;
    }
  }

  /// Restaura la sesión de un usuario offline validado con email/password.
  /// Devuelve los datos del usuario restaurado si tuvo éxito, o null.
  /// Es útil para el auto-login offline desde el splash sin volver a pedir
  /// credenciales al usuario.
  Future<Map<String, dynamic>?> restoreOfflineUserSession(
    String email,
    String password,
  ) async {
    final offlineUser = await validateOfflineUser(
      email: email,
      password: password,
    );
    if (offlineUser == null) return null;

    final offlineData = await getOfflineData();
    if (offlineData == null) {
      print('❌ No hay datos offline guardados');
      return null;
    }

    // Restaurar datos de sesión del usuario
    await saveUserData(
      userId: offlineUser['userId'],
      email: offlineUser['email'],
      accessToken: 'offline_mode',
    );

    // Restaurar datos del vendedor
    if (offlineUser['idTpv'] != null && offlineUser['idTrabajador'] != null) {
      await saveSellerData(
        idTpv: offlineUser['idTpv'],
        idTrabajador: offlineUser['idTrabajador'],
        permitirCustomizarPrecioVenta:
            offlineUser['permitir_customizar_precio_venta'] == true,
      );
    }

    if (offlineUser['idSeller'] != null) {
      await saveIdSeller(offlineUser['idSeller']);
    }

    // Restaurar perfil del trabajador
    if (offlineUser['nombres'] != null &&
        offlineUser['apellidos'] != null &&
        offlineUser['idTienda'] != null &&
        offlineUser['idRoll'] != null) {
      await saveWorkerProfile(
        nombres: offlineUser['nombres'],
        apellidos: offlineUser['apellidos'],
        idTienda: offlineUser['idTienda'],
        idRoll: offlineUser['idRoll'],
      );
      final storeId = offlineUser['idTienda'];
      if (storeId is int) {
        await ensureOfflineStoreScope(storeId);
      } else if (storeId is num) {
        await ensureOfflineStoreScope(storeId.toInt());
      }
    }

    final entryRole = offlineUser['entryRole']?.toString();
    if (entryRole != null && entryRole.isNotEmpty) {
      await setCajaEntryRole(entryRole);
      final storeId = offlineUser['idTienda'];
      if (storeId != null) {
        final sid = storeId is int ? storeId : (storeId as num).toInt();
        final adminRole =
            (entryRole == 'gerente' || entryRole == 'supervisor')
                ? entryRole
                : 'none';
        await setCachedAdminRoleRaw(sid, adminRole);
      }
      AdminAccessService().clearMemoryCache();
    }

    await setOfflineMode(true);
    return offlineUser;
  }

  /// Obtener todos los usuarios offline guardados
  Future<List<Map<String, dynamic>>> getOfflineUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final usersJson = prefs.getString(_offlineUsersKey);

    if (usersJson == null) return [];

    final decoded = jsonDecode(usersJson) as List<dynamic>;
    return decoded.map((item) => item as Map<String, dynamic>).toList();
  }

  /// Eliminar un usuario offline específico
  Future<void> removeOfflineUser(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final usersJson = prefs.getString(_offlineUsersKey);

    if (usersJson == null) return;

    final decoded = jsonDecode(usersJson) as List<dynamic>;
    final offlineUsers =
        decoded.map((item) => item as Map<String, dynamic>).toList();

    // Filtrar para remover el usuario
    offlineUsers.removeWhere((user) => user['email'] == email);

    // Guardar array actualizado
    await prefs.setString(_offlineUsersKey, jsonEncode(offlineUsers));
    print('🗑️ Usuario offline eliminado: $email');
  }

  /// Limpiar todos los usuarios offline
  Future<void> clearAllOfflineUsers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_offlineUsersKey);
    print('🗑️ Todos los usuarios offline eliminados');
  }

  // ==================== MÉTODOS DE PAGO OFFLINE ====================

  /// Obtener métodos de pago desde cache offline
  Future<List<Map<String, dynamic>>> getPaymentMethodsOffline() async {
    final offlineData = await getOfflineData();
    if (offlineData != null && offlineData['payment_methods'] != null) {
      return List<Map<String, dynamic>>.from(offlineData['payment_methods']);
    }
    return [];
  }

  // ==================== ÓRDENES PENDIENTES DE SINCRONIZACIÓN ====================

  /// Guardar una orden pendiente de sincronización
  Future<void> savePendingOrder(Map<String, dynamic> orderData) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingOrdersJson = prefs.getString(_pendingOrdersKey);

    List<Map<String, dynamic>> pendingOrders = [];
    if (pendingOrdersJson != null) {
      final decoded = jsonDecode(pendingOrdersJson) as List<dynamic>;
      pendingOrders =
          decoded.map((item) => item as Map<String, dynamic>).toList();
    }

    // Agregar nueva orden con timestamp y flag de pendiente
    orderData['is_pending_sync'] = true;
    orderData['created_offline_at'] = DateTime.now().toIso8601String();
    orderData['offline_user_id'] ??= prefs.getString(_userIdKey);
    orderData['offline_store_id'] ??= prefs.getInt(_offlineInventoryStoreKey);
    pendingOrders.add(orderData);

    await prefs.setString(_pendingOrdersKey, jsonEncode(pendingOrders));
    print(
      '💾 Orden pendiente guardada. Total pendientes: ${pendingOrders.length}',
    );
  }

  Future<bool> updatePendingOrderPayments(
    String orderId,
    List<Map<String, dynamic>> payments,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingOrders = await getPendingOrders();
    var changed = false;

    for (final order in pendingOrders) {
      if (order['id']?.toString() != orderId) continue;
      order['desglose_pagos'] = payments;
      order['last_modified'] = DateTime.now().toIso8601String();
      changed = true;
      break;
    }

    if (changed) {
      await prefs.setString(_pendingOrdersKey, jsonEncode(pendingOrders));
    }
    return changed;
  }

  /// Obtener todas las órdenes pendientes de sincronización
  Future<List<Map<String, dynamic>>> getPendingOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingOrdersJson = prefs.getString(_pendingOrdersKey);

    if (pendingOrdersJson == null) return [];

    final decoded = jsonDecode(pendingOrdersJson) as List<dynamic>;
    return decoded.map((item) => item as Map<String, dynamic>).toList();
  }

  /// Órdenes pendientes visibles para el vendedor.
  ///
  /// Solo del turno **open** actual. Sin turno abierto → lista vacía.
  /// También excluye turnos `closed_pending_sync` (los ve el admin).
  Future<List<Map<String, dynamic>>> getSellerVisiblePendingOrders() async {
    final open = await getOpenOfflineTurno();
    if (open == null) return [];

    final openLocalId = open['local_id']?.toString();
    if (openLocalId == null || openLocalId.isEmpty) return [];

    final from = DateTime.tryParse(open['fecha_apertura']?.toString() ?? '');
    final orders = await getPendingOrders();
    final closedIds = await _closedPendingSyncLocalTurnoIds();

    return orders.where((order) {
      final lid = order['local_turno_id']?.toString();
      if (lid != null && lid.isNotEmpty) {
        if (closedIds.contains(lid)) return false;
        return lid == openLocalId;
      }
      // Legacy sin local_turno_id: ventana desde apertura del open.
      if (from == null) return false;
      final created = DateTime.tryParse(
        (order['fecha_creacion'] ?? order['created_offline_at'])?.toString() ??
            '',
      );
      if (created == null) return false;
      return !created.toUtc().isBefore(from.toUtc());
    }).toList();
  }

  Future<Set<String>> _closedPendingSyncLocalTurnoIds() async {
    final turnos = await getOfflineTurnos();
    return turnos
        .where((t) => t['status'] == offlineTurnoStatusClosedPending)
        .map((t) => t['local_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<int> getSellerVisiblePendingOrdersCount() async {
    return (await getSellerVisiblePendingOrders()).length;
  }

  /// Eliminar una orden pendiente específica (después de sincronizar)
  Future<void> removePendingOrder(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingOrdersJson = prefs.getString(_pendingOrdersKey);

    if (pendingOrdersJson == null) return;

    final decoded = jsonDecode(pendingOrdersJson) as List<dynamic>;
    final pendingOrders =
        decoded.map((item) => item as Map<String, dynamic>).toList();

    // Filtrar para remover la orden
    pendingOrders.removeWhere((order) => order['id'] == orderId);

    await prefs.setString(_pendingOrdersKey, jsonEncode(pendingOrders));
    print(
      '🗑️ Orden pendiente eliminada: $orderId. Restantes: ${pendingOrders.length}',
    );
  }

  /// Limpiar todas las órdenes pendientes
  Future<void> clearPendingOrders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingOrdersKey);
    print('🗑️ Todas las órdenes pendientes eliminadas');
  }

  /// Marca órdenes como sincronizadas SIN eliminarlas del almacenamiento local.
  ///
  /// Esto permite que las órdenes activas (no finalizadas) sigan visibles en la
  /// pantalla de órdenes tras sincronizar. Opcionalmente asocia el id_operacion
  /// devuelto por el servidor (mapa orderId -> id_operacion).
  Future<void> markOrdersSyncedById(
    List<String> orderIds, {
    Map<String, int>? operationIds,
  }) async {
    if (orderIds.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_pendingOrdersKey);
    if (json == null) return;

    final decoded = jsonDecode(json) as List<dynamic>;
    final idSet = orderIds.toSet();
    bool changed = false;

    final updated =
        decoded.map((item) {
          final order = item as Map<String, dynamic>;
          final id = order['id']?.toString();
          if (id != null && idSet.contains(id)) {
            order['synced'] = true;
            order['synced_at'] = DateTime.now().toIso8601String();
            order['is_pending_sync'] = false;
            // Promover el estado de SYNC al estado de NEGOCIO real para que la
            // orden deje de contarse como pendiente y, si es final, se purgue.
            final estadoActual = order['estado']?.toString();
            if (estadoActual == null ||
                estadoActual == 'pendiente_sincronizacion') {
              order['estado'] =
                  order['estado_final']?.toString() ?? 'completada';
            }
            final opId = operationIds?[id];
            if (opId != null) order['id_operacion'] = opId;
            changed = true;
          }
          return order;
        }).toList();

    if (changed) {
      await prefs.setString(_pendingOrdersKey, jsonEncode(updated));
      print('🔖 ${orderIds.length} órdenes marcadas como sincronizadas');
    }
  }

  /// Estados que se consideran finales (la orden ya no está activa).
  static const Set<String> _estadosFinalesOrden = {
    'completada',
    'cancelada',
    'devuelta',
  };

  /// Purga del almacenamiento local SOLO las ordenes ya sincronizadas
  /// y en estado final.
  ///
  /// No llamar tras sincronizar ventas mientras el turno sigue abierto:
  /// esas ordenes deben permanecer para el listado y el resumen local.
  /// Llamar al cerrar el turno (o en logout forzado).
  Future<void> purgeFinalizedSyncedOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_pendingOrdersKey);
    if (json == null) return;

    final decoded = jsonDecode(json) as List<dynamic>;
    final remaining =
        decoded.map((e) => e as Map<String, dynamic>).where((order) {
          final synced = order['synced'] == true;
          final estado = (order['estado'] ?? '').toString();
          final esFinal = _estadosFinalesOrden.contains(estado);
          // Conservar si NO está sincronizada, o si todavía está activa.
          return !(synced && esFinal);
        }).toList();

    final removed = decoded.length - remaining.length;
    if (removed > 0) {
      await prefs.setString(_pendingOrdersKey, jsonEncode(remaining));
      print('🧹 Purgadas $removed órdenes sincronizadas y finalizadas');
    }
  }

  /// Quita de pending_orders las ya subidas cuyo id_operacion ya está en el
  /// cache descargado del servidor (evita duplicados en listado offline).
  /// Conserva las no sincronizadas y las synced que aún no aparecen en servidor.
  Future<int> removeSyncedPendingPresentOnServer(Set<int> serverOpIds) async {
    if (serverOpIds.isEmpty) return 0;
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_pendingOrdersKey);
    if (json == null) return 0;

    final decoded = jsonDecode(json) as List<dynamic>;
    final remaining = <Map<String, dynamic>>[];
    var removed = 0;

    for (final item in decoded) {
      final order = Map<String, dynamic>.from(item as Map);
      final synced = order['synced'] == true;
      final rawOp = order['id_operacion'];
      final opId =
          rawOp is int
              ? rawOp
              : (rawOp is num ? rawOp.toInt() : int.tryParse('$rawOp'));

      if (synced && opId != null && serverOpIds.contains(opId)) {
        removed++;
        continue;
      }
      remaining.add(order);
    }

    if (removed > 0) {
      await prefs.setString(_pendingOrdersKey, jsonEncode(remaining));
      print(
        '🧹 $removed órdenes locales synced ya están en servidor; '
        'quitadas de pending para evitar duplicados',
      );
    }
    return removed;
  }

  /// Obtener número de órdenes pendientes
  Future<int> getPendingOrdersCount() async {
    final pendingOrders = await getPendingOrders();
    return pendingOrders.length;
  }

  /// Marcar una orden pendiente como fallida tras un intento de sincronización
  /// Guarda el mensaje de error, timestamp y conteo acumulado de intentos
  Future<void> markPendingOrderSyncFailure(
    String orderId,
    String errorMessage,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingOrdersJson = prefs.getString(_pendingOrdersKey);
    if (pendingOrdersJson == null) return;

    final decoded = jsonDecode(pendingOrdersJson) as List<dynamic>;
    final pendingOrders =
        decoded.map((item) => item as Map<String, dynamic>).toList();

    var changed = false;
    for (final order in pendingOrders) {
      if (order['id']?.toString() == orderId) {
        final previousAttempts = (order['sync_attempts'] as num?)?.toInt() ?? 0;
        order['last_sync_error'] = errorMessage;
        order['last_sync_attempt_at'] = DateTime.now().toIso8601String();
        order['sync_attempts'] = previousAttempts + 1;
        changed = true;
        break;
      }
    }

    if (changed) {
      await prefs.setString(_pendingOrdersKey, jsonEncode(pendingOrders));
      print('⚠️ Error registrado en orden pendiente $orderId');
    }
  }

  /// Limpiar el estado de error de una orden pendiente antes de reintentar
  Future<void> clearPendingOrderError(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingOrdersJson = prefs.getString(_pendingOrdersKey);
    if (pendingOrdersJson == null) return;

    final decoded = jsonDecode(pendingOrdersJson) as List<dynamic>;
    final pendingOrders =
        decoded.map((item) => item as Map<String, dynamic>).toList();

    var changed = false;
    for (final order in pendingOrders) {
      if (order['id']?.toString() == orderId) {
        if (order.containsKey('last_sync_error')) {
          order.remove('last_sync_error');
          changed = true;
        }
        break;
      }
    }

    if (changed) {
      await prefs.setString(_pendingOrdersKey, jsonEncode(pendingOrders));
    }
  }

  /// Descartar manualmente una orden pendiente (alias semántico de removePendingOrder)
  Future<void> discardPendingOrder(String orderId) async {
    await removePendingOrder(orderId);
    print('🗑️ Orden pendiente descartada manualmente: $orderId');
  }

  // ==================== ACTUALIZACIÓN DE CACHE DE PRODUCTOS ====================

  /// Actualizar inventario de productos en cache (descontar cantidades).
  /// Con [quantityToSubtract] negativo se suma stock (p. ej. recepción offline).
  /// Soporta productos con y sin variantes usando ids de inventario/ubicación.
  ///
  /// FASE 5 presentaciones: [presentationId] es la fila de
  /// `app_dat_producto_presentacion` sobre la que se aplica el delta. Es
  /// **imprescindible** desde la Fase 4, porque `cantidad` ya viene EN LA
  /// PRESENTACIÓN ELEGIDA: vender 2 Bultos mandaba `2` y, sin este filtro, el
  /// delta se aplicaba a la primera fila de inventario que casara (normalmente
  /// la base) → el caché local descontaba 2 **Bolsas** en vez de 2 Bultos, y el
  /// vendedor veía un stock que no existía hasta la siguiente sincronización.
  ///
  /// [quantityToSubtract] es `num` y no `int`: truncar con `.toInt()` perdía las
  /// ventas fraccionadas (0,5 kg → 0, o sea no descontaba nada).
  Future<void> updateProductInventoryInCache(
    int productId,
    int? variantId,
    num quantityToSubtract, {
    int? inventoryId,
    int? locationId,
    int? presentationId,
  }) async {
    final offlineData = await getOfflineData();
    if (offlineData == null || offlineData['products'] == null) return;

    final productsData = Map<String, dynamic>.from(offlineData['products']);
    bool updated = false;

    // Buscar el producto en todas las categorías
    for (var categoryKey in productsData.keys) {
      final rawCategory = productsData[categoryKey];
      if (rawCategory is! List) continue;

      final categoryProducts =
          rawCategory
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();

      for (int i = 0; i < categoryProducts.length; i++) {
        final productIdRaw = categoryProducts[i]['id'];
        final matchesId =
            productIdRaw == productId ||
            (productIdRaw is num && productIdRaw.toInt() == productId);
        if (!matchesId) continue;

        // Actualizar cantidad total del producto
        final currentQty =
            (categoryProducts[i]['cantidad'] as num?)?.toDouble() ?? 0;
        final nextQty = currentQty - quantityToSubtract;
        categoryProducts[i]['cantidad'] =
            quantityToSubtract >= 0
                ? nextQty.clamp(0, double.infinity)
                : nextQty;

        // Actualizar inventario en detalles_completos (si existe)
        if (categoryProducts[i]['detalles_completos'] != null) {
          final detalles = Map<String, dynamic>.from(
            categoryProducts[i]['detalles_completos'] as Map,
          );
          final rawInventario = detalles['inventario'];
          final inventarioList =
              rawInventario is List
                  ? rawInventario
                      .whereType<Map>()
                      .map((e) => Map<String, dynamic>.from(e))
                      .toList()
                  : <Map<String, dynamic>>[];

          bool inventoryUpdated = false;

          bool matchesInventoryItem(Map<String, dynamic> inv) {
            final varianteData =
                inv['variante'] is Map
                    ? Map<String, dynamic>.from(inv['variante'] as Map)
                    : null;

            // FASE 5: la presentación manda. Si se pidió una concreta y la fila
            // es de otra, NO es la fila a tocar — sin esto el delta de «2
            // Bultos» caía sobre las Bolsas.
            if (presentationId != null) {
              final presData =
                  inv['presentacion'] is Map
                      ? Map<String, dynamic>.from(inv['presentacion'] as Map)
                      : null;
              final invPresId =
                  (presData?['id'] as num?)?.toInt() ??
                  (inv['id_presentacion'] as num?)?.toInt();
              if (invPresId != null && invPresId != presentationId) {
                return false;
              }
            }

            if (variantId != null) {
              return varianteData != null && varianteData['id'] == variantId;
            }

            if (inventoryId != null && inv['id_inventario'] == inventoryId) {
              return true;
            }

            if (locationId != null) {
              final ubicacion =
                  inv['ubicacion'] is Map
                      ? Map<String, dynamic>.from(inv['ubicacion'] as Map)
                      : null;
              return ubicacion?['id'] == locationId;
            }

            // Con presentación pedida y sin variante/ubicación, llegar aquí ya
            // significa que la presentación casó.
            return presentationId != null || varianteData == null;
          }

          void applyDeltaToInv(Map<String, dynamic> inv) {
            final currentInvQty =
                (inv['cantidad_disponible'] as num?)?.toDouble() ?? 0;
            final nextInvQty = currentInvQty - quantityToSubtract;
            inv['cantidad_disponible'] =
                quantityToSubtract >= 0
                    ? nextInvQty.clamp(0, double.infinity)
                    : nextInvQty;
          }

          for (int j = 0; j < inventarioList.length; j++) {
            final inv = inventarioList[j];
            if (matchesInventoryItem(inv)) {
              applyDeltaToInv(inv);
              inventarioList[j] = inv;
              inventoryUpdated = true;
              print(
                '📦 Inventario actualizado - Producto: $productId, '
                'Variante: ${variantId ?? "sin variante"}, '
                'Delta: ${-quantityToSubtract}',
              );
              break;
            }
          }

          if (!inventoryUpdated &&
              variantId == null &&
              presentationId == null &&
              inventarioList.isNotEmpty) {
            // Fallback a la primera fila SOLO si no se pidió presentación: con
            // presentación concreta, tocar otra fila es escribir un saldo falso.
            final inv = inventarioList.first;
            applyDeltaToInv(inv);
            inventarioList[0] = inv;
            print(
              '📦 Inventario actualizado (fallback) - Producto: $productId, '
              'Delta: ${-quantityToSubtract}',
            );
          } else if (!inventoryUpdated && presentationId != null) {
            // No hay fila de esa presentación en el caché: el total del producto
            // ya se ajustó arriba. Se avisa porque suele significar un caché
            // desactualizado, no un error de la venta.
            print(
              '⚠️ Sin fila de inventario para la presentación $presentationId '
              '(producto $productId): solo se ajustó el total del producto',
            );
          }

          detalles['inventario'] = inventarioList;
          categoryProducts[i]['detalles_completos'] = detalles;
        }

        productsData[categoryKey] = categoryProducts;
        updated = true;
        break;
      }

      if (updated) break;
    }

    if (updated) {
      offlineData['products'] = productsData;
      await saveOfflineDataTransactional(offlineData);
      print('✅ Cache de productos actualizado');
    }
  }

  // ==================== OPERACIONES PENDIENTES ====================

  /// Guardar una operación pendiente (apertura/cierre/cambio estado)
  Future<void> savePendingOperation(Map<String, dynamic> operation) async {
    final prefs = await SharedPreferences.getInstance();
    final operationsJson = prefs.getString(_pendingOperationsKey);

    List<Map<String, dynamic>> operations = [];
    if (operationsJson != null) {
      final decoded = jsonDecode(operationsJson) as List<dynamic>;
      operations = decoded.map((item) => item as Map<String, dynamic>).toList();
    }

    // Agregar timestamp
    operation['created_at'] = DateTime.now().toIso8601String();
    operation['offline_user_id'] ??= prefs.getString(_userIdKey);
    operation['offline_store_id'] ??= prefs.getInt(_offlineInventoryStoreKey);
    operations.add(operation);

    await prefs.setString(_pendingOperationsKey, jsonEncode(operations));
    print('💾 Operación pendiente guardada: ${operation['type']}');
  }

  /// Actualiza el `estado` de una orden ya cacheada (creada online) para que
  /// el listado offline no la vuelva a mostrar como pendiente.
  Future<void> updateCachedOrderEstado({
    required String orderId,
    int? operationId,
    required int estado,
  }) async {
    try {
      final data = await getOfflineData();
      final raw = data?['orders'];
      if (raw is! List) return;

      final opId =
          operationId ?? int.tryParse(orderId.replaceFirst('ORD-', ''));
      var changed = false;
      final updated =
          raw.map((item) {
            if (item is! Map) return item;
            final map = Map<String, dynamic>.from(item);
            final rowOp = map['id_operacion'];
            final rowOpInt =
                rowOp is int
                    ? rowOp
                    : (rowOp is num ? rowOp.toInt() : int.tryParse('$rowOp'));
            final rowId = map['id']?.toString();
            if (rowId == orderId || (opId != null && rowOpInt == opId)) {
              map['estado'] = estado;
              changed = true;
            }
            return map;
          }).toList();

      if (changed) {
        await mergeOfflineData({'orders': updated});
        print('💾 Cache de órdenes: $orderId -> estado $estado');
      }
    } catch (e) {
      print('⚠️ No se pudo actualizar estado en cache de órdenes: $e');
    }
  }

  /// Sobrescribir la lista completa de operaciones pendientes.
  /// Útil para persistir el resultado tras sincronizar (p. ej. quitar las ya
  /// sincronizadas conservando las que fallaron).
  Future<void> savePendingOperations(
    List<Map<String, dynamic>> operations,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (operations.isEmpty) {
      await prefs.remove(_pendingOperationsKey);
    } else {
      await prefs.setString(_pendingOperationsKey, jsonEncode(operations));
    }
  }

  /// Obtener todas las operaciones pendientes
  Future<List<Map<String, dynamic>>> getPendingOperations() async {
    final prefs = await SharedPreferences.getInstance();
    final operationsJson = prefs.getString(_pendingOperationsKey);

    if (operationsJson == null) return [];

    final decoded = jsonDecode(operationsJson) as List<dynamic>;
    return decoded.map((item) => item as Map<String, dynamic>).toList();
  }

  /// Eliminar operaciones pendientes por tipo
  Future<void> removePendingOperationsByType(String type) async {
    final prefs = await SharedPreferences.getInstance();
    final operationsJson = prefs.getString(_pendingOperationsKey);

    if (operationsJson == null) return;

    final decoded = jsonDecode(operationsJson) as List<dynamic>;
    final operations =
        decoded.map((item) => item as Map<String, dynamic>).toList();
    final filtered =
        operations.where((operation) => operation['type'] != type).toList();

    if (filtered.isEmpty) {
      await prefs.remove(_pendingOperationsKey);
    } else {
      await prefs.setString(_pendingOperationsKey, jsonEncode(filtered));
    }

    print('🗑️ Operaciones pendientes eliminadas para tipo: $type');
  }

  /// Limpiar operaciones pendientes
  Future<void> clearPendingOperations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingOperationsKey);
    print('🗑️ Operaciones pendientes eliminadas');
  }

  // ==================== TURNO OFFLINE (cola multi-día) ====================

  static const String offlineTurnoStatusOpen = 'open';
  static const String offlineTurnoStatusClosedPending = 'closed_pending_sync';
  static const String offlineTurnoStatusSynced = 'synced';

  /// Vista compatible del turno abierto: payload de apertura + campos de cola.
  Map<String, dynamic> _openTurnoView(Map<String, dynamic> entry) {
    final apertura = entry['apertura'];
    final base =
        apertura is Map
            ? Map<String, dynamic>.from(apertura)
            : <String, dynamic>{};
    base['local_id'] = entry['local_id'];
    base['local_turno_id'] = entry['local_id'];
    base['status'] = entry['status'];
    base['server_id_turno'] = entry['server_id_turno'];
    base['client_uuid'] = entry['client_uuid_apertura'] ?? base['client_uuid'];
    if (entry['fecha_apertura'] != null) {
      base['fecha_apertura'] = entry['fecha_apertura'];
    }
    if (entry['id_tpv'] != null) base['id_tpv'] = entry['id_tpv'];
    if (entry['id_vendedor'] != null)
      base['id_vendedor'] = entry['id_vendedor'];
    // Preferir id servidor si ya se sincronizó la apertura; si no, local_id.
    base['id'] = entry['server_id_turno'] ?? entry['local_id'] ?? base['id'];
    return base;
  }

  /// Serializa mutaciones de la cola para evitar lost-updates (lectura/escritura
  /// entrelazada durante awaits largos de RPC).
  static Future<void> _turnosWriteChain = Future.value();

  Future<T> _withOfflineTurnosLock<T>(Future<T> Function() action) {
    final done = _turnosWriteChain.then((_) => action());
    _turnosWriteChain = done.then((_) {}, onError: (_, __) {});
    return done;
  }

  Future<void> _persistOfflineTurnos(List<Map<String, dynamic>> turnos) async {
    final prefs = await SharedPreferences.getInstance();
    if (turnos.isEmpty) {
      // remove() puede devolver false si la clave ya no existía.
      await prefs.remove(_offlineTurnosKey);
    } else {
      final encoded = jsonEncode(turnos);
      final ok = await prefs.setString(_offlineTurnosKey, encoded);
      if (!ok) {
        throw StateError(
          'No se pudo guardar offline_turnos '
          '(¿payload demasiado grande? ${encoded.length} chars)',
        );
      }
    }
    // Mantener legacy en sync con el open (compat lecturas antiguas).
    Map<String, dynamic>? open;
    for (final t in turnos) {
      if (t['status'] == offlineTurnoStatusOpen) {
        open = t;
        break;
      }
    }
    if (open != null) {
      final ok = await prefs.setString(
        _offlineTurnoKey,
        jsonEncode(_openTurnoView(open)),
      );
      if (!ok) {
        throw StateError('No se pudo guardar offline_turno legacy');
      }
    } else {
      await prefs.remove(_offlineTurnoKey);
    }
  }

  /// Migra el blob legacy `offline_turno` a la cola `offline_turnos` (una vez).
  Future<void> _migrateLegacyOfflineTurnoIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final queueJson = prefs.getString(_offlineTurnosKey);
    if (queueJson != null) return;

    final legacyJson = prefs.getString(_offlineTurnoKey);
    if (legacyJson == null) return;

    try {
      final legacy = jsonDecode(legacyJson) as Map<String, dynamic>;
      final localId =
          legacy['local_id']?.toString() ??
          legacy['local_turno_id']?.toString() ??
          UuidGenerator.v4();
      final clientUuid =
          legacy['client_uuid']?.toString() ?? UuidGenerator.v4();
      final entry = <String, dynamic>{
        'local_id': localId,
        'client_uuid_apertura': clientUuid,
        'status': offlineTurnoStatusOpen,
        'id_tpv': legacy['id_tpv'],
        'id_vendedor': legacy['id_vendedor'],
        'usuario': legacy['usuario'],
        'fecha_apertura': legacy['fecha_apertura'],
        'apertura': {...legacy, 'client_uuid': clientUuid, 'local_id': localId},
        'server_id_turno':
            legacy['server_id_turno'] ??
            (legacy['id'] is int ? legacy['id'] : null),
      };
      await prefs.setString(_offlineTurnosKey, jsonEncode([entry]));
      print('🔄 Migrado offline_turno legacy → cola offline_turnos');
    } catch (e) {
      print('⚠️ Error migrando offline_turno legacy: $e');
    }
  }

  /// Cola completa de turnos offline (open + cerrados pendientes + synced).
  Future<List<Map<String, dynamic>>> getOfflineTurnos() async {
    await _migrateLegacyOfflineTurnoIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_offlineTurnosKey);
    if (json == null) return [];
    final decoded = jsonDecode(json) as List<dynamic>;
    return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Turnos que realmente requieren sincronización.
  /// Un turno abierto que ya existe en el servidor solo queda pendiente cuando
  /// contiene ventas locales aún no sincronizadas.
  Future<List<Map<String, dynamic>>> getOfflineTurnosPendingSync() async {
    final all = await getOfflineTurnos();
    final orders = await getPendingOrders();
    final unsyncedOrders = orders.where(
      (order) => order['synced'] != true && order['is_pending_sync'] != false,
    );
    final pendingOrderCountByTurno = <String, int>{};
    for (final order in unsyncedOrders) {
      final localTurnoId = order['local_turno_id']?.toString();
      if (localTurnoId == null || localTurnoId.isEmpty) continue;
      pendingOrderCountByTurno.update(
        localTurnoId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    final pending =
        all
            .where((turno) {
              final status = turno['status']?.toString();
              if (status == offlineTurnoStatusClosedPending) return true;
              if (status != offlineTurnoStatusOpen) return false;
              final localId = turno['local_id']?.toString();
              final serverId = turno['server_id_turno'] ?? turno['id_turno'];
              final hasServerTurno =
                  serverId is num ||
                  int.tryParse(serverId?.toString() ?? '') != null;
              return !hasServerTurno ||
                  (localId != null &&
                      (pendingOrderCountByTurno[localId] ?? 0) > 0);
            })
            .map((turno) {
              final localId = turno['local_id']?.toString();
              return {
                ...turno,
                'pending_orders_count':
                    localId == null
                        ? 0
                        : pendingOrderCountByTurno[localId] ?? 0,
              };
            })
            .toList()
          ..sort((a, b) {
            final fa = a['fecha_apertura']?.toString() ?? '';
            final fb = b['fecha_apertura']?.toString() ?? '';
            return fa.compareTo(fb);
          });
    return pending;
  }

  /// Dump legible de la cola de turnos offline para diagnóstico.
  /// Prefijo fijo `[TURNO_SYNC]` para filtrar en logcat / flutter run.
  Future<void> dumpOfflineTurnosQueue(String reason) async {
    try {
      final all = await getOfflineTurnos();
      final open = await getOpenOfflineTurno();
      final legacy = await getOfflineTurno();
      final resumen = await getTurnoResumenCache();
      print('════════════ [TURNO_SYNC] DUMP ($reason) ════════════');
      print(
        '[TURNO_SYNC] cola.size=${all.length} '
        'open=${open?['local_id']} '
        'legacy_open=${legacy?['local_id'] ?? legacy?['id']} '
        'resumen.status=${resumen?['status']} '
        'resumen.cerrado_online=${resumen?['cerrado_online']} '
        'resumen.id=${resumen?['id'] ?? resumen?['server_id_turno']}',
      );
      if (all.isEmpty) {
        print('[TURNO_SYNC] (cola vacía)');
      }
      for (var i = 0; i < all.length; i++) {
        print('[TURNO_SYNC]   ${describeOfflineTurnoEntry(all[i], index: i)}');
      }
      print('════════════ [TURNO_SYNC] FIN DUMP ════════════');
    } catch (e, st) {
      print('[TURNO_SYNC] ❌ dumpOfflineTurnosQueue falló: $e');
      print(st);
    }
  }

  /// Resumen de una entrada de cola para logs.
  static String describeOfflineTurnoEntry(
    Map<String, dynamic> t, {
    int? index,
  }) {
    final cierre = t['cierre'];
    final apertura = t['apertura'];
    final hasCierre = cierre is Map && cierre.isNotEmpty;
    final hasApertura = apertura is Map && apertura.isNotEmpty;
    final productos =
        hasCierre ? (cierre['productos'] as List?)?.length ?? 0 : 0;
    final prefix = index != null ? '#$index ' : '';
    return '${prefix}local=${t['local_id']} '
        'status=${t['status']} '
        'server_id=${t['server_id_turno']} '
        'tpv=${t['id_tpv']} '
        'vendedor=${t['id_vendedor']} '
        'usuario=${t['usuario']} '
        'apertura=${hasApertura ? 'yes' : 'no'} '
        'cierre=${hasCierre ? 'yes(prod=$productos)' : 'no'} '
        'uuid_ap=${t['client_uuid_apertura']} '
        'uuid_ci=${t['client_uuid_cierre']} '
        'fa=${t['fecha_apertura']} '
        'fc=${t['fecha_cierre']} '
        'synced_at=${t['synced_at']}';
  }

  Future<Map<String, dynamic>?> getOpenOfflineTurno() async {
    final all = await getOfflineTurnos();
    for (final t in all) {
      if (t['status'] == offlineTurnoStatusOpen) return t;
    }
    return null;
  }

  Future<Map<String, dynamic>?> getOfflineTurnoByLocalId(String localId) async {
    final all = await getOfflineTurnos();
    for (final t in all) {
      if (t['local_id']?.toString() == localId) return t;
    }
    return null;
  }

  /// Inserta o actualiza un registro de la cola por `local_id`.
  Future<void> upsertOfflineTurno(Map<String, dynamic> entry) async {
    final localId = entry['local_id']?.toString();
    if (localId == null || localId.isEmpty) {
      throw ArgumentError('upsertOfflineTurno requiere local_id');
    }
    await _withOfflineTurnosLock(() async {
      final all = await getOfflineTurnos();
      final idx = all.indexWhere((t) => t['local_id']?.toString() == localId);
      if (idx >= 0) {
        all[idx] = {...all[idx], ...entry, 'local_id': localId};
      } else {
        all.add({...entry, 'local_id': localId});
      }
      await _persistOfflineTurnos(all);
      print('💾 Turno offline upsert: $localId (${entry['status']})');
    });
  }

  /// Crea un turno abierto en la cola (falla si ya hay uno open).
  Future<Map<String, dynamic>> createOpenOfflineTurno({
    required Map<String, dynamic> aperturaPayload,
  }) async {
    final existing = await getOpenOfflineTurno();
    if (existing != null) {
      throw StateError(
        'Ya existe un turno offline abierto (${existing['local_id']})',
      );
    }

    final localId =
        aperturaPayload['local_id']?.toString() ?? UuidGenerator.v4();
    final clientUuid =
        aperturaPayload['client_uuid']?.toString() ?? UuidGenerator.v4();
    final payload =
        Map<String, dynamic>.from(aperturaPayload)
          ..['local_id'] = localId
          ..['local_turno_id'] = localId
          ..['client_uuid'] = clientUuid
          ..['id'] = localId;

    final entry = <String, dynamic>{
      'local_id': localId,
      'client_uuid_apertura': clientUuid,
      'status': offlineTurnoStatusOpen,
      'id_tpv': payload['id_tpv'],
      'id_vendedor': payload['id_vendedor'],
      'usuario': payload['usuario'],
      'fecha_apertura': payload['fecha_apertura'],
      'apertura': payload,
      // Si el payload ya es un turno de servidor (cache online), conservar el id.
      'server_id_turno':
          payload['server_id_turno'] ??
          (payload['id'] is int
              ? payload['id']
              : (payload['id'] is num ? (payload['id'] as num).toInt() : null)),
    };
    await upsertOfflineTurno(entry);
    return entry;
  }

  /// Marca el turno open (o el indicado) como cerrado pendiente de sync.
  /// [resumen] es el cuadre/snapshot local para que el admin lo vea offline.
  Future<void> markOfflineTurnoClosed({
    String? localId,
    required Map<String, dynamic> cierrePayload,
    Map<String, dynamic>? resumen,
  }) async {
    print(
      '[TURNO_SYNC] markOfflineTurnoClosed START '
      'localId=$localId '
      'cierre.keys=${cierrePayload.keys.toList()} '
      'efectivo_final=${cierrePayload['efectivo_final']} '
      'productos=${(cierrePayload['productos'] as List?)?.length ?? 0}',
    );
    await dumpOfflineTurnosQueue('ANTES markOfflineTurnoClosed');

    await _withOfflineTurnosLock(() async {
      final all = await getOfflineTurnos();
      String? id = localId;
      if (id == null) {
        for (final t in all) {
          if (t['status'] == offlineTurnoStatusOpen) {
            id = t['local_id']?.toString();
            break;
          }
        }
      }
      if (id == null) {
        print('[TURNO_SYNC] ❌ markOfflineTurnoClosed: no hay turno open');
        throw StateError('No hay turno open para cerrar offline');
      }

      final clientUuidCierre =
          cierrePayload['client_uuid']?.toString() ?? UuidGenerator.v4();
      final cierre =
          Map<String, dynamic>.from(cierrePayload)
            ..['client_uuid'] = clientUuidCierre
            ..['local_turno_id'] = id;

      final idx = all.indexWhere((t) => t['local_id']?.toString() == id);
      if (idx < 0) {
        print('[TURNO_SYNC] ❌ markOfflineTurnoClosed: $id no está en cola');
        throw StateError('Turno $id no encontrado en cola');
      }

      print(
        '[TURNO_SYNC] markOfflineTurnoClosed BEFORE '
        '${describeOfflineTurnoEntry(all[idx])}',
      );

      all[idx] = {
        ...all[idx],
        'status': offlineTurnoStatusClosedPending,
        'client_uuid_cierre': clientUuidCierre,
        'fecha_cierre':
            cierre['fecha_cierre'] ?? DateTime.now().toIso8601String(),
        'cierre': cierre,
        if (resumen != null) 'resumen': resumen,
      };
      await _persistOfflineTurnos(all);
      await _mirrorTurnoResumenToGlobalCache(all[idx]);
      print(
        '[TURNO_SYNC] ✅ markOfflineTurnoClosed AFTER '
        '${describeOfflineTurnoEntry(all[idx])}',
      );
    });
    await dumpOfflineTurnosQueue('DESPUÉS markOfflineTurnoClosed');
  }

  /// Persiste el cuadre del turno en los caches globales de resumen/cierre.
  Future<void> _mirrorTurnoResumenToGlobalCache(
    Map<String, dynamic> entry,
  ) async {
    try {
      final cuadre = await getOfflineTurnoCuadre(entry);
      final isClosedPending =
          entry['status'] == offlineTurnoStatusClosedPending;
      final isSynced = entry['status'] == offlineTurnoStatusSynced;
      final payload = <String, dynamic>{
        ...cuadre,
        'local_id': entry['local_id'],
        'status': entry['status'],
        // Evita que un pull del servidor reabra el turno en UI/cache
        // mientras el cierre local aún no se sincronizó.
        'cerrado_local': isClosedPending || isSynced,
        'cerrado_online': isSynced || entry['cerrado_online'] == true,
        if (entry['synced_at'] != null) 'synced_at': entry['synced_at'],
        if (entry['fecha_cierre'] != null)
          'fecha_cierre': entry['fecha_cierre'],
        if (entry['fecha_apertura'] != null)
          'fecha_apertura': entry['fecha_apertura'],
        if (entry['server_id_turno'] != null)
          'server_id_turno': entry['server_id_turno'],
        if (entry['server_id_turno'] != null) 'id': entry['server_id_turno'],
      };
      await saveTurnoResumenCache(payload);
      await saveResumenCierreCache({
        ...payload,
        'total_ventas': cuadre['ventas_totales'],
      });
    } catch (e) {
      print('⚠️ No se pudo mirror resumen a cache global: $e');
    }
  }

  /// True si hay un cierre local pendiente (o recién cerrado) que corresponde
  /// al turno del servidor [serverId] o al mismo TPV/vendedor.
  Future<Map<String, dynamic>?> findClosedPendingMatching({
    int? serverId,
    int? idTpv,
    int? idVendedor,
  }) async {
    final all = await getOfflineTurnos();
    Map<String, dynamic>? tpvFallback;
    for (final t in all) {
      if (t['status'] != offlineTurnoStatusClosedPending) continue;
      final sid = t['server_id_turno'];
      final sidInt =
          sid is int ? sid : (sid is num ? sid.toInt() : int.tryParse('$sid'));
      if (serverId != null && sidInt != null && sidInt == serverId) {
        return t;
      }
      // Mismo server id aún no pegado en entry pero sí en apertura.
      if (serverId != null && t['apertura'] is Map) {
        final apId =
            (t['apertura'] as Map)['id'] ??
            (t['apertura'] as Map)['server_id_turno'];
        final apInt =
            apId is int
                ? apId
                : (apId is num ? apId.toInt() : int.tryParse('$apId'));
        if (apInt != null && apInt == serverId) return t;
      }

      final tTpv =
          t['id_tpv'] ??
          (t['apertura'] is Map ? (t['apertura'] as Map)['id_tpv'] : null);
      final tVend =
          t['id_vendedor'] ??
          (t['apertura'] is Map ? (t['apertura'] as Map)['id_vendedor'] : null);
      final tpvInt =
          tTpv is int
              ? tTpv
              : (tTpv is num ? tTpv.toInt() : int.tryParse('$tTpv'));
      final vendInt =
          tVend is int
              ? tVend
              : (tVend is num ? tVend.toInt() : int.tryParse('$tVend'));
      if (idTpv != null &&
          tpvInt == idTpv &&
          (idVendedor == null || vendInt == null || vendInt == idVendedor)) {
        // Preferir match exacto por server_id; si el cierre offline aún no
        // tiene server_id (apertura recién subida), usar este fallback.
        if (sidInt == null || (serverId != null && sidInt == serverId)) {
          tpvFallback ??= t;
        }
      }
    }
    return tpvFallback;
  }

  /// Turno cerrado o sincronizado más reciente (para UI cuando no hay open).
  Future<Map<String, dynamic>?> getLastClosedOrSyncedTurnoForDisplay() async {
    final all = await getOfflineTurnos();
    final candidates =
        all
            .where(
              (t) =>
                  t['status'] == offlineTurnoStatusClosedPending ||
                  t['status'] == offlineTurnoStatusSynced,
            )
            .toList();
    if (candidates.isNotEmpty) {
      candidates.sort((a, b) {
        final fa =
            a['fecha_cierre']?.toString() ??
            a['synced_at']?.toString() ??
            a['fecha_apertura']?.toString() ??
            '';
        final fb =
            b['fecha_cierre']?.toString() ??
            b['synced_at']?.toString() ??
            b['fecha_apertura']?.toString() ??
            '';
        return fb.compareTo(fa);
      });
      return _openTurnoView(candidates.first);
    }

    final cache = await getTurnoResumenCache();
    if (cache != null && cache.isNotEmpty) {
      if (cache['cerrado_online'] == true ||
          cache['status'] == offlineTurnoStatusSynced ||
          cache['status'] == offlineTurnoStatusClosedPending) {
        return cache;
      }
    }
    return null;
  }

  /// Turnos cerrados pendientes de sync (cuadres locales).
  Future<List<Map<String, dynamic>>> getClosedPendingOfflineTurnos() async {
    final all = await getOfflineTurnosPendingSync();
    return all
        .where((t) => t['status'] == offlineTurnoStatusClosedPending)
        .toList();
  }

  /// Cuadre local de un turno de la cola (snapshot o reconstruido).
  Future<Map<String, dynamic>> getOfflineTurnoCuadre(
    Map<String, dynamic> turnoEntry,
  ) async {
    final existing = turnoEntry['resumen'];
    if (existing is Map && existing.isNotEmpty) {
      return Map<String, dynamic>.from(existing);
    }
    return buildOfflineTurnoCuadreFromLocalData(turnoEntry);
  }

  /// Reconstruye un cuadre a partir de apertura/cierre + órdenes/egresos locales.
  Future<Map<String, dynamic>> buildOfflineTurnoCuadreFromLocalData(
    Map<String, dynamic> turnoEntry,
  ) async {
    final localId = turnoEntry['local_id']?.toString();
    final apertura =
        turnoEntry['apertura'] is Map
            ? Map<String, dynamic>.from(turnoEntry['apertura'] as Map)
            : <String, dynamic>{};
    final cierre =
        turnoEntry['cierre'] is Map
            ? Map<String, dynamic>.from(turnoEntry['cierre'] as Map)
            : <String, dynamic>{};

    final efectivoInicial = (apertura['efectivo_inicial'] ?? 0).toDouble();
    final efectivoFinal = (cierre['efectivo_final'] ?? 0).toDouble();
    final diferenciaCierre = (cierre['diferencia'] ?? 0).toDouble();

    final orders = await getPendingOrders();
    final turnoOrders =
        orders.where((o) {
          if (localId == null) return false;
          final lid = o['local_turno_id']?.toString();
          if (lid != null && lid.isNotEmpty) return lid == localId;
          // Fallback legacy por ventana de fechas
          final created = o['fecha_creacion'] ?? o['created_offline_at'];
          if (created == null) return false;
          final dt = DateTime.tryParse(created.toString())?.toUtc();
          final from =
              DateTime.tryParse(
                '${turnoEntry['fecha_apertura'] ?? ''}',
              )?.toUtc();
          final to =
              DateTime.tryParse('${turnoEntry['fecha_cierre'] ?? ''}')?.toUtc();
          if (dt == null || from == null) return false;
          if (dt.isBefore(from)) return false;
          if (to != null && dt.isAfter(to)) return false;
          return true;
        }).toList();

    double ventas = 0;
    double totalEfectivo = 0;
    double totalTransferencias = 0;
    int productos = 0;
    int operaciones = 0;

    for (final o in turnoOrders) {
      final estado = (o['estado'] ?? '').toString().toLowerCase();
      if (estado == 'cancelada' || estado == 'devuelta') continue;
      operaciones++;
      final total = (o['total'] as num?)?.toDouble() ?? 0.0;
      ventas += total;

      final items = o['items'] as List<dynamic>? ?? [];
      for (final item in items) {
        if (item is Map) {
          productos += ((item['cantidad'] as num?)?.toDouble() ?? 0).round();
        }
      }

      final desglose = o['desglose_pagos'] as List<dynamic>? ?? [];
      if (desglose.isEmpty) {
        totalEfectivo += total;
      } else {
        for (final p in desglose) {
          if (p is! Map) continue;
          final monto = (p['monto'] as num?)?.toDouble() ?? 0.0;
          final esEfectivo = p['es_efectivo'] == true;
          final esDigital = p['es_digital'] == true;
          if (esEfectivo || (!esDigital && !esEfectivo)) {
            totalEfectivo += monto;
          } else {
            totalTransferencias += monto;
          }
        }
      }
    }

    // Egresos del turno
    double egresosEfectivo = 0;
    double egresosDigital = 0;
    try {
      final egresos = await getEgresosOffline();
      for (final e in egresos) {
        if (localId == null) break;
        final lid = e['local_turno_id']?.toString();
        if (lid == null || lid != localId) continue;
        final monto = (e['monto_entrega'] as num?)?.toDouble() ?? 0.0;
        if (e['es_digital'] == true) {
          egresosDigital += monto;
        } else {
          egresosEfectivo += monto;
        }
      }
    } catch (_) {}

    final efectivoEsperado = efectivoInicial + totalEfectivo - egresosEfectivo;
    final ticketPromedio = operaciones > 0 ? ventas / operaciones : 0.0;

    return {
      'efectivo_inicial': efectivoInicial,
      'ventas_totales': ventas,
      'total_efectivo': totalEfectivo,
      'total_transferencias': totalTransferencias,
      'productos_vendidos': productos,
      'operaciones_totales': operaciones,
      'ticket_promedio': ticketPromedio,
      'egresos_efectivo': egresosEfectivo,
      'egresos_digitales': egresosDigital,
      'egresos_totales': egresosEfectivo + egresosDigital,
      'efectivo_esperado': efectivoEsperado,
      'efectivo_final': efectivoFinal,
      'efectivo_real': efectivoFinal,
      'estado_turno': 2,
      'diferencia':
          diferenciaCierre != 0
              ? diferenciaCierre
              : (efectivoFinal - efectivoEsperado),
      'fecha_apertura': turnoEntry['fecha_apertura'],
      'fecha_cierre': turnoEntry['fecha_cierre'] ?? cierre['fecha_cierre'],
      'ordenes_locales': turnoOrders.length,
      'reconstruido': true,
    };
  }

  Future<void> setOfflineTurnoServerId(String localId, int serverId) async {
    await _withOfflineTurnosLock(() async {
      final all = await getOfflineTurnos();
      final idx = all.indexWhere((t) => t['local_id']?.toString() == localId);
      if (idx < 0) return;
      all[idx]['server_id_turno'] = serverId;
      final apertura = all[idx]['apertura'];
      if (apertura is Map) {
        all[idx]['apertura'] = {
          ...Map<String, dynamic>.from(apertura),
          'server_id_turno': serverId,
          'id': serverId,
        };
      }
      await _persistOfflineTurnos(all);
    });
  }

  /// Marca un turno como sincronizado (conserva en cola con status `synced`).
  /// Devuelve `true` solo si ya no queda como pendiente tras persistir.
  Future<bool> markOfflineTurnoSynced(
    String localId, {
    int? serverIdTurno,
  }) async {
    if (localId.isEmpty) {
      print('[TURNO_SYNC] ❌ markOfflineTurnoSynced: localId vacío');
      return false;
    }

    print(
      '[TURNO_SYNC] markOfflineTurnoSynced START '
      'localId=$localId serverIdTurno=$serverIdTurno',
    );

    final result = await _withOfflineTurnosLock(() async {
      final all = await getOfflineTurnos();
      final idx = all.indexWhere((t) => t['local_id']?.toString() == localId);
      if (idx < 0) {
        print(
          '[TURNO_SYNC] ℹ️ markOfflineTurnoSynced: $localId ya no está en cola '
          '(tratado como synced)',
        );
        return true;
      }

      print(
        '[TURNO_SYNC] markOfflineTurnoSynced BEFORE '
        '${describeOfflineTurnoEntry(all[idx])}',
      );

      if (all[idx]['status'] == offlineTurnoStatusSynced) {
        print(
          '[TURNO_SYNC] ℹ️ markOfflineTurnoSynced: $localId ya estaba synced',
        );
        return true;
      }

      final now = DateTime.now().toIso8601String();
      final sid = serverIdTurno ?? all[idx]['server_id_turno'];
      final updated = <String, dynamic>{
        ...all[idx],
        'status': offlineTurnoStatusSynced,
        'synced_at': now,
        if (sid != null) 'server_id_turno': sid,
      };
      if (sid != null && updated['apertura'] is Map) {
        updated['apertura'] = {
          ...Map<String, dynamic>.from(updated['apertura'] as Map),
          'server_id_turno': sid,
          'id': sid,
        };
      }
      all[idx] = updated;
      await _persistOfflineTurnos(all);
      await _mirrorTurnoResumenToGlobalCache(updated);

      final still = await getOfflineTurnoByLocalId(localId);
      final pending =
          still != null &&
          (still['status'] == offlineTurnoStatusOpen ||
              still['status'] == offlineTurnoStatusClosedPending);
      if (pending) {
        print(
          '[TURNO_SYNC] ❌ markOfflineTurnoSynced: $localId SIGUE pendiente '
          'tras persistir status=${still['status']}',
        );
        return false;
      }

      print(
        '[TURNO_SYNC] ✅ markOfflineTurnoSynced OK '
        '${describeOfflineTurnoEntry(updated)}',
      );
      return true;
    });

    await dumpOfflineTurnosQueue(
      result
          ? 'DESPUÉS markOfflineTurnoSynced OK'
          : 'FALLO markOfflineTurnoSynced',
    );
    return result;
  }

  /// Retira turnos ya sincronizados de la cola (p.ej. al abrir turno nuevo).
  Future<void> purgeSyncedOfflineTurnosFromQueue() async {
    await _withOfflineTurnosLock(() async {
      final all = await getOfflineTurnos();
      final remaining =
          all.where((t) => t['status'] != offlineTurnoStatusSynced).toList();
      if (remaining.length != all.length) {
        await _persistOfflineTurnos(remaining);
        print(
          '🧹 Purged ${all.length - remaining.length} turno(s) synced de la cola',
        );
      }
    });
  }

  /// Purga órdenes synced+finales de un local_turno_id concreto.
  Future<void> purgeFinalizedSyncedOrdersForTurno(String localTurnoId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_pendingOrdersKey);
    if (json == null) return;

    final decoded = jsonDecode(json) as List<dynamic>;
    final remaining =
        decoded.map((e) => e as Map<String, dynamic>).where((order) {
          final orderTurno = order['local_turno_id']?.toString();
          if (orderTurno != localTurnoId) return true;
          final synced = order['synced'] == true;
          final estado = (order['estado'] ?? '').toString();
          final esFinal = _estadosFinalesOrden.contains(estado);
          return !(synced && esFinal);
        }).toList();

    final removed = decoded.length - remaining.length;
    if (removed > 0) {
      await prefs.setString(_pendingOrdersKey, jsonEncode(remaining));
      print(
        '🧹 Purgadas $removed órdenes del turno $localTurnoId (synced+final)',
      );
    }
  }

  /// Guardar / actualizar el turno **abierto** (compat). Actualiza la cola.
  /// Guarda/actualiza en cache el turno abierto que llegó del SERVIDOR
  /// (apertura hecha online), para poder seguir operando si luego se pierde
  /// la conexión. Marca explícitamente `origen_apertura: 'online'` y limpia
  /// `created_offline_at`/`tipo_operacion` heredados de una entrada previa
  /// de la cola offline, para que no se confunda con una apertura hecha
  /// realmente offline (ver `_isOfflineTurno` en apertura_screen.dart).
  Future<void> saveOfflineTurno(Map<String, dynamic> turnoData) async {
    final estado = turnoData['estado'];
    if (estado != null && estado != 1) {
      print(
        'ℹ️ saveOfflineTurno: turno no abierto (estado=$estado); no se cachea',
      );
      return;
    }

    final incomingIdRaw = turnoData['id'] ?? turnoData['server_id_turno'];
    final incomingId =
        incomingIdRaw is int
            ? incomingIdRaw
            : (incomingIdRaw is num
                ? incomingIdRaw.toInt()
                : int.tryParse('$incomingIdRaw'));
    final incomingTpvRaw = turnoData['id_tpv'];
    final incomingTpv =
        incomingTpvRaw is int
            ? incomingTpvRaw
            : (incomingTpvRaw is num
                ? incomingTpvRaw.toInt()
                : int.tryParse('$incomingTpvRaw'));
    final incomingVendRaw = turnoData['id_vendedor'];
    final incomingVend =
        incomingVendRaw is int
            ? incomingVendRaw
            : (incomingVendRaw is num
                ? incomingVendRaw.toInt()
                : int.tryParse('$incomingVendRaw'));

    final resumen = await getTurnoResumenCache();
    if (resumen?['cerrado_online'] == true ||
        resumen?['cerrado_local'] == true ||
        resumen?['status'] == offlineTurnoStatusClosedPending ||
        resumen?['status'] == offlineTurnoStatusSynced) {
      final closedId = resumen!['id'] ?? resumen['server_id_turno'];
      if (closedId != null &&
          incomingId != null &&
          closedId.toString() == incomingId.toString()) {
        print(
          'ℹ️ saveOfflineTurno: turno $closedId ya cerrado local/online; '
          'no se re-cachea como abierto',
        );
        return;
      }
    }

    // Si el cierre ya está en cola (closed_pending_sync), NUNCA recrear un
    // open desde el pull del servidor: eso deja el turno "abierto" en UI
    // aunque el cierre local exista y el sync de cierre aún no haya corrido.
    final closedPending = await findClosedPendingMatching(
      serverId: incomingId,
      idTpv: incomingTpv,
      idVendedor: incomingVend,
    );
    if (closedPending != null) {
      final localId = closedPending['local_id']?.toString();
      print(
        'ℹ️ saveOfflineTurno: existe cierre local pendiente '
        '($localId) para server_id=$incomingId / tpv=$incomingTpv — '
        'solo se actualiza server_id, no se reabre',
      );
      if (localId != null && incomingId != null) {
        await setOfflineTurnoServerId(localId, incomingId);
      }
      return;
    }

    // La fila cruda de `app_dat_caja_turno` (turnoData) no tiene columna
    // `usuario` (UUID), sólo `id_vendedor` (int). Sin este fallback, un
    // turno abierto online y cacheado aquí para resiliencia offline puede
    // quedar sin usuario válido, y el replay posterior falla con
    // "invalid input syntax for type uuid" al intentar reabrirlo.
    Future<String?> resolveUsuario() async {
      final direct = turnoData['usuario']?.toString();
      if (direct != null && direct.isNotEmpty) return direct;
      final userData = await getUserData();
      final current = userData['userId']?.toString();
      return (current != null && current.isNotEmpty) ? current : null;
    }

    final open = await getOpenOfflineTurno();
    if (open != null) {
      final localId = open['local_id']?.toString();
      if (localId == null) return;
      final usuario = await resolveUsuario() ?? open['usuario']?.toString();
      final mergedApertura = {
        ...Map<String, dynamic>.from(
          open['apertura'] is Map
              ? Map<String, dynamic>.from(open['apertura'] as Map)
              : {},
        ),
        ...turnoData,
        'local_id': localId,
        'local_turno_id': localId,
        'origen_apertura': 'online',
        'created_offline_at': null,
        if (usuario != null) 'usuario': usuario,
      };
      await upsertOfflineTurno({
        ...open,
        'apertura': mergedApertura,
        'fecha_apertura': turnoData['fecha_apertura'] ?? open['fecha_apertura'],
        'id_tpv': turnoData['id_tpv'] ?? open['id_tpv'],
        'id_vendedor': turnoData['id_vendedor'] ?? open['id_vendedor'],
        if (usuario != null) 'usuario': usuario,
        'server_id_turno':
            turnoData['server_id_turno'] ??
            (turnoData['id'] is int
                ? turnoData['id']
                : open['server_id_turno']),
        'client_uuid_apertura':
            turnoData['client_uuid'] ?? open['client_uuid_apertura'],
      });
      return;
    }

    // Sin open: crear uno desde el payload (p.ej. cache de turno online).
    final usuario = await resolveUsuario();
    await createOpenOfflineTurno(
      aperturaPayload: {
        ...turnoData,
        'origen_apertura': 'online',
        if (usuario != null) 'usuario': usuario,
      },
    );
  }

  /// Obtener turno abierto offline (compat: vista aplanada del open).
  Future<Map<String, dynamic>?> getOfflineTurno() async {
    final open = await getOpenOfflineTurno();
    if (open == null) return null;
    return _openTurnoView(open);
  }

  /// Quita el turno abierto de la cola (no borra cerrados pendientes).
  Future<void> clearOfflineTurno() async {
    await _withOfflineTurnosLock(() async {
      final all = await getOfflineTurnos();
      final filtered =
          all.where((t) => t['status'] != offlineTurnoStatusOpen).toList();
      await _persistOfflineTurnos(filtered);
      print(
        '🗑️ Turno offline abierto eliminado (cola de cerrados conservada)',
      );
    });
  }

  /// Borra toda la cola de turnos offline.
  Future<void> clearAllOfflineTurnos() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_offlineTurnosKey);
    await prefs.remove(_offlineTurnoKey);
    print('🗑️ Cola de turnos offline eliminada');
  }

  /// Tras cierre online exitoso: quita el turno abierto de la cola y purga
  /// órdenes ya sincronizadas en estado final. **Conserva** resúmenes y demás
  /// cache del turno hasta la próxima apertura.
  Future<void> finalizeTurnoAfterOnlineClose({int? serverTurnoId}) async {
    await clearOfflineTurno();
    await purgeFinalizedSyncedOrders();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_offlineTurnoKey);

    final now = DateTime.now().toIso8601String();
    final resumen = await getTurnoResumenCache();
    if (resumen != null) {
      final updated = {
        ...resumen,
        'status': offlineTurnoStatusSynced,
        'cerrado_online': true,
        'synced_at': now,
        'fecha_cierre': resumen['fecha_cierre'] ?? now,
        if (serverTurnoId != null) 'id': serverTurnoId,
        if (serverTurnoId != null) 'server_id_turno': serverTurnoId,
      };
      await saveTurnoResumenCache(updated);
      await saveResumenCierreCache({
        ...updated,
        'total_ventas': updated['ventas_totales'],
        'efectivo_real': updated['efectivo_final'],
      });
    }

    print(
      '✅ Cierre online: cola open limpiada; '
      'resúmenes marcados como cerrados/synced',
    );
  }

  /// Resumen del **último turno cerrado** desde caches / cola offline
  /// (para la pantalla de apertura cuando no hay red o modo local).
  Future<Map<String, dynamic>?> getPreviousShiftSummaryFromLocal() async {
    var raw = await getTurnoResumenCache();
    if (raw != null && _summaryHasMeaningfulData(raw)) {
      // Si el cache fue pisado con un KPI de turno aún abierto, no sirve
      // como "turno anterior".
      final estado = raw['estado_turno'];
      final isOpenKpi = estado == 1 || estado == '1';
      if (!isOpenKpi) {
        return normalizePreviousShiftSummary(raw);
      }
    }

    raw = await getResumenCierreCache();
    if (raw != null && _summaryHasMeaningfulData(raw)) {
      return normalizePreviousShiftSummary(raw);
    }

    final lastClosed = await getLastClosedOrSyncedTurnoForDisplay();
    if (lastClosed != null) {
      try {
        final localId = lastClosed['local_id']?.toString();
        Map<String, dynamic> entry = lastClosed;
        if (localId != null) {
          entry = await getOfflineTurnoByLocalId(localId) ?? lastClosed;
        }
        final cuadre = await getOfflineTurnoCuadre(entry);
        if (_summaryHasMeaningfulData(cuadre) ||
            _summaryHasMeaningfulData(entry)) {
          return normalizePreviousShiftSummary({...entry, ...cuadre});
        }
      } catch (e) {
        print('⚠️ No se pudo reconstruir cuadre del último cerrado: $e');
      }
    }

    // Último recurso: cache de turno aunque sea KPI abierto (mejor que nada).
    raw = await getTurnoResumenCache();
    if (raw != null && _summaryHasMeaningfulData(raw)) {
      return normalizePreviousShiftSummary(raw);
    }
    return null;
  }

  /// Normaliza claves del resumen para la UI de apertura.
  Map<String, dynamic> normalizePreviousShiftSummary(Map<String, dynamic> raw) {
    final ventas = _asDouble(raw['ventas_totales'] ?? raw['total_ventas']);
    final efectivoInicial = _asDouble(raw['efectivo_inicial']);
    final efectivoReal = _asDouble(
      raw['efectivo_real'] ?? raw['efectivo_final'] ?? raw['efectivo_esperado'],
    );
    // FASE 3: _asNum, no _asInt — las cantidades fraccionadas (0,5 kg) se
    // perdian al truncar.
    final productos = _asNum(raw['productos_vendidos']);
    final ticket = _asDouble(raw['ticket_promedio']);

    return {
      ...raw,
      'ventas_totales': ventas,
      'total_ventas': ventas,
      'efectivo_inicial': efectivoInicial,
      'efectivo_real': efectivoReal,
      'efectivo_final': _asDouble(raw['efectivo_final'] ?? efectivoReal),
      // Efectivo sugerido para la nueva apertura = lo contado al cierre.
      'efectivo_sugerido_apertura':
          efectivoReal > 0 ? efectivoReal : efectivoInicial,
      'productos_vendidos': productos,
      'ticket_promedio': ticket,
    };
  }

  bool _summaryHasMeaningfulData(Map<String, dynamic> raw) {
    final ventas = _asDouble(raw['ventas_totales'] ?? raw['total_ventas']);
    final ei = _asDouble(raw['efectivo_inicial']);
    final er = _asDouble(
      raw['efectivo_real'] ?? raw['efectivo_final'] ?? raw['efectivo_esperado'],
    );
    // FASE 3: _asNum — un turno con solo 0,5 kg vendidos no debe parecer vacio.
    final productos = _asNum(raw['productos_vendidos']);
    return ventas > 0 || ei > 0 || er > 0 || productos > 0;
  }

  static double _asDouble(dynamic raw) {
    if (raw == null) return 0.0;
    if (raw is double) return raw;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString().replaceAll(',', '.')) ?? 0.0;
  }

  static int _asInt(dynamic raw) {
    if (raw == null) return 0;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString()) ?? 0;
  }

  /// Igual que [_asInt] pero **sin truncar**.
  ///
  /// FASE 3 presentaciones: las cantidades vendidas pueden ser fraccionadas
  /// (media libra, 0,5 kg) y meterlas en un `int` las deforma — media libra
  /// pasaba a 0. Se usa para `productos_vendidos`, que la RPC
  /// `fn_resumen_diario_cierre_v2` ya devuelve como numeric por el mismo
  /// motivo: el cast a integer del SQL **redondeaba** (tres lineas de 0,5 kg
  /// daban 2).
  static num _asNum(dynamic raw) {
    if (raw == null) return 0;
    if (raw is num) return raw;
    return num.tryParse(raw.toString().replaceAll(',', '.')) ?? 0;
  }

  /// Limpia resúmenes del turno anterior (llamar al abrir un turno nuevo).
  Future<void> clearPreviousTurnoCaches() async {
    await purgeSyncedOfflineTurnosFromQueue();
    await clearTurnoResumenCache();
    await clearResumenCierreCache();
  }

  /// Actualizar estado de orden pendiente
  Future<void> updatePendingOrderStatus(
    String orderId,
    String newStatus,
    Map<String, dynamic>? additionalData,
  ) async {
    final pendingOrders = await getPendingOrders();

    for (var order in pendingOrders) {
      if (order['id'] == orderId) {
        order['estado'] = newStatus;
        order['last_modified'] = DateTime.now().toIso8601String();

        // Guardar operación de cambio de estado
        await savePendingOperation({
          'type': 'order_status_change',
          'order_id': orderId,
          'new_status': newStatus,
          'additional_data': additionalData,
        });

        break;
      }
    }

    // Guardar órdenes actualizadas
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingOrdersKey, jsonEncode(pendingOrders));
    print('📝 Estado de orden actualizado: $orderId -> $newStatus');
  }

  /// Verificar si hay turno abierto offline
  Future<bool> hasOfflineTurnoAbierto() async {
    return await getOpenOfflineTurno() != null;
  }

  /// Obtener información del turno offline para mostrar en settings
  Future<Map<String, dynamic>?> getOfflineTurnoInfo() async {
    final turno = await getOfflineTurno();
    if (turno == null) return null;

    return {
      'id': turno['id'],
      'local_id': turno['local_id'],
      'fecha_apertura': turno['fecha_apertura'],
      'efectivo_inicial':
          turno['efectivo_inicial'] ??
          (turno['apertura'] is Map
              ? (turno['apertura'] as Map)['efectivo_inicial']
              : null),
      'usuario': turno['usuario'],
      'observaciones': turno['observaciones'],
    };
  }

  /// Cantidad de turnos pendientes de sync (open + closed_pending_sync).
  Future<int> getPendingOfflineTurnosCount() async {
    final pending = await getOfflineTurnosPendingSync();
    return pending.length;
  }

  /// Reautenticar usuario con credenciales guardadas
  Future<Map<String, dynamic>> reloginWithSavedCredentials() async {
    try {
      final credentials = await getSavedCredentials();
      final email = credentials['email'];
      final password = credentials['password'];

      if (email == null || password == null) {
        throw Exception('No hay credenciales guardadas para relogin');
      }

      print('🔐 Reautenticando con credenciales guardadas...');
      print('  - Email: $email');

      // Aquí se haría la llamada real a Supabase Auth
      // Por ahora simulamos el éxito
      return {
        'success': true,
        'email': email,
        'message': 'Reautenticación exitosa',
      };
    } catch (e) {
      print('❌ Error en reautenticación: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Obtener resumen de datos offline para sincronización
  Future<Map<String, dynamic>> getOfflineSyncSummary() async {
    final allOrders = await getPendingOrders();
    final pendingOrders =
        allOrders
            .where(
              (order) =>
                  order['synced'] != true && order['is_pending_sync'] != false,
            )
            .toList();
    final pendingOperations = await getPendingOperations();
    final turno = await getOfflineTurno();
    final pendingTurnos = await getOfflineTurnosPendingSync();
    final pendingTurnoIds =
        pendingTurnos
            .map((turno) => turno['local_id']?.toString())
            .whereType<String>()
            .toSet();
    final embeddedPendingOrders =
        pendingOrders
            .where(
              (order) =>
                  pendingTurnoIds.contains(order['local_turno_id']?.toString()),
            )
            .length;
    final standalonePendingOrders =
        pendingOrders.length - embeddedPendingOrders;
    final closedPending =
        pendingTurnos
            .where((t) => t['status'] == offlineTurnoStatusClosedPending)
            .length;
    final allTurnos = await getOfflineTurnos();
    final syncedTurnos =
        allTurnos
            .where((t) => t['status'] == offlineTurnoStatusSynced)
            .toList();
    syncedTurnos.sort((a, b) {
      final fa = a['synced_at']?.toString() ?? '';
      final fb = b['synced_at']?.toString() ?? '';
      return fb.compareTo(fa);
    });
    final lastSynced = syncedTurnos.isNotEmpty ? syncedTurnos.first : null;

    return {
      'pending_orders_count': standalonePendingOrders,
      'pending_turno_orders_count': embeddedPendingOrders,
      'pending_turno_ids': pendingTurnoIds.toList(),
      'pending_operations_count': pendingOperations.length,
      'has_open_turno': turno != null,
      'pending_turnos_count': pendingTurnos.length,
      'closed_turnos_pending_count': closedPending,
      'synced_turnos_count': syncedTurnos.length,
      'last_synced_turno':
          lastSynced != null
              ? {
                'local_id': lastSynced['local_id'],
                'server_id_turno': lastSynced['server_id_turno'],
                'synced_at': lastSynced['synced_at'],
                'fecha_cierre': lastSynced['fecha_cierre'],
              }
              : null,
      'turno_info':
          turno != null
              ? {
                'fecha_apertura': turno['fecha_apertura'],
                'efectivo_inicial': turno['efectivo_inicial'],
                'local_id': turno['local_id'],
              }
              : null,
    };
  }

  /// Limpieza POST-SINCRONIZACIÓN segura.
  ///
  /// Conserva el turno `open` y los `closed_pending_sync` que el sync loop
  /// aún no haya marcado como synced. Solo limpia ops ya sincronizadas.
  Future<void> clearAllOfflineData() async {
    await _removeSyncedPendingOperations();
    // Retirar de pending_operations las apertura/cierre legacy ya reflejadas
    // en la cola (la cola es fuente de verdad).
    try {
      final ops = await getPendingOperations();
      final filtered =
          ops
              .where(
                (op) =>
                    op['type'] != 'apertura_turno' &&
                    op['type'] != 'cierre_turno',
              )
              .toList();
      if (filtered.length != ops.length) {
        await savePendingOperations(filtered);
      }
    } catch (_) {}
    print(
      'ℹ️ Sincronización completada — cola de turnos gestionada por sync loop',
    );
  }

  /// Limpieza TOTAL de datos offline (logout real / cambio de usuario).
  /// Borra todo, incluido el turno. Usar solo cuando se confirma que no hay
  /// nada pendiente de sincronizar (ver hasUnsyncedOfflineData()).
  Future<void> clearAllOfflineDataForced() async {
    await clearPendingOrders();
    await clearPendingOperations();
    await clearAllOfflineTurnos();
    await OfflineDatabaseService().clearAll();
    print('🗑️ Todos los datos offline eliminados (forzado, incl. SQLite)');
  }

  /// Elimina del array de operaciones pendientes solo las marcadas como
  /// sincronizadas (synced == true), conservando el resto.
  Future<void> _removeSyncedPendingOperations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_pendingOperationsKey);
      if (json == null) return;
      final decoded = jsonDecode(json) as List<dynamic>;
      final remaining =
          decoded
              .map((e) => e as Map<String, dynamic>)
              .where((op) => op['synced'] != true)
              .toList();
      if (remaining.isEmpty) {
        await prefs.remove(_pendingOperationsKey);
      } else {
        await prefs.setString(_pendingOperationsKey, jsonEncode(remaining));
      }
    } catch (e) {
      print('⚠️ Error limpiando operaciones sincronizadas: $e');
    }
  }

  /// ¿Hay datos offline sin sincronizar que se perderían al hacer logout?
  /// Considera órdenes pendientes, operaciones pendientes y turnos offline.
  ///
  /// Registra en el log CUÁL de las categorías disparó el resultado, para
  /// poder diagnosticar reportes de "dice que hay pendientes pero no hay
  /// nada" sin adivinar.
  Future<bool> hasUnsyncedOfflineData() async {
    try {
      final pendingOrders = await getPendingOrders();
      final unsyncedOrders =
          pendingOrders.where((o) => o['synced'] != true).toList();
      if (unsyncedOrders.isNotEmpty) {
        print(
          '🔎 hasUnsyncedOfflineData: ${unsyncedOrders.length} orden(es) '
          'sin sincronizar: ${unsyncedOrders.map((o) => o['id']).toList()}',
        );
        return true;
      }

      final operations = await getPendingOperations();
      final unsyncedOps = operations.where((o) => o['synced'] != true).toList();
      if (unsyncedOps.isNotEmpty) {
        print(
          '🔎 hasUnsyncedOfflineData: ${unsyncedOps.length} operación(es) '
          'pendiente(s): ${unsyncedOps.map((o) => o['type']).toList()}',
        );
        return true;
      }

      // Un turno "open" con `server_id_turno` ya asignado significa que su
      // apertura SÍ está sincronizada en el servidor (solo sigue activo);
      // no hay nada de esa apertura pendiente de subir. Sólo cuenta como
      // pendiente real un turno cerrado sin sincronizar, o uno abierto que
      // todavía no se ha podido registrar en el servidor.
      final pendingTurnos = await getOfflineTurnosPendingSync();
      final trulyPendingTurnos =
          pendingTurnos.where((t) {
            if (t['status'] == offlineTurnoStatusClosedPending) return true;
            return t['server_id_turno'] == null;
          }).toList();
      if (trulyPendingTurnos.isNotEmpty) {
        print(
          '🔎 hasUnsyncedOfflineData: ${trulyPendingTurnos.length} turno(s) '
          'pendiente(s): ${trulyPendingTurnos.map((t) => '${t['local_id']}(status=${t['status']}, server_id_turno=${t['server_id_turno']})').toList()}',
        );
        return true;
      }

      final egresos = await getEgresosOffline();
      if (egresos.isNotEmpty) {
        print(
          '🔎 hasUnsyncedOfflineData: ${egresos.length} egreso(s) '
          'sin sincronizar',
        );
        return true;
      }

      final adminPending =
          await OfflineDatabaseService().countPendingAdminOps();
      if (adminPending > 0) {
        print(
          '🔎 hasUnsyncedOfflineData: $adminPending operación(es) admin '
          'pendiente(s)',
        );
        return true;
      }

      return false;
    } catch (e) {
      print('⚠️ Error verificando datos sin sincronizar: $e');
      // Ante la duda, asumir que SÍ hay datos para no arriesgar pérdida.
      return true;
    }
  }

  /// Limpiar preferencias offline al abrir una nueva versión
  Future<void> clearOfflinePreferencesForNewVersion() async {
    try {
      await clearPendingOrders();
      await clearPendingOperations();
      await clearAllOfflineTurnos();
      await clearTurnoResumenCache();
      await clearResumenCierreCache();
      await clearEgresosOffline();
      await clearEgresosCache();
      await clearOfflineData();
      await clearAllOfflineUsers();
      print('🧹 Preferencias offline limpiadas por actualización de versión');
    } catch (e) {
      print('⚠️ Error limpiando preferencias offline en actualización: $e');
    }
  }

  // ========== MÉTODOS PARA CACHE DE RESUMEN DE TURNO ==========

  /// Guardar resumen de turno en cache para modo offline
  Future<void> saveTurnoResumenCache(Map<String, dynamic> resumenData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final resumenJson = jsonEncode(resumenData);
      await prefs.setString(_turnoResumenKey, resumenJson);
      print('💾 Resumen de turno guardado en cache offline');
      print('📊 Datos guardados: ${resumenData.keys.toList()}');
    } catch (e) {
      print('❌ Error guardando resumen de turno en cache: $e');
    }
  }

  /// Obtener resumen de turno desde cache offline
  Future<Map<String, dynamic>?> getTurnoResumenCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final resumenJson = prefs.getString(_turnoResumenKey);

      if (resumenJson != null) {
        final resumenData = jsonDecode(resumenJson) as Map<String, dynamic>;
        print('📱 Resumen de turno cargado desde cache offline');
        print('📊 Datos disponibles: ${resumenData.keys.toList()}');
        return resumenData;
      }

      print('⚠️ No hay resumen de turno en cache offline');
      return null;
    } catch (e) {
      print('❌ Error cargando resumen de turno desde cache: $e');
      return null;
    }
  }

  /// Verificar si hay resumen de turno en cache
  Future<bool> hasTurnoResumenCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(_turnoResumenKey);
    } catch (e) {
      print('❌ Error verificando cache de resumen de turno: $e');
      return false;
    }
  }

  /// Limpiar cache de resumen de turno
  Future<void> clearTurnoResumenCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_turnoResumenKey);
      print('🗑️ Cache de resumen de turno eliminado');
    } catch (e) {
      print('❌ Error limpiando cache de resumen de turno: $e');
    }
  }

  // ==================== RESUMEN DE CIERRE CACHE ====================

  /// Guardar resumen de cierre en cache offline
  Future<void> saveResumenCierreCache(Map<String, dynamic> resumenData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final resumenJson = jsonEncode(resumenData);
      await prefs.setString(_resumenCierreKey, resumenJson);
      print('💾 Resumen de cierre guardado en cache offline');
      print('📊 Datos guardados: ${resumenData.keys.toList()}');
    } catch (e) {
      print('❌ Error guardando resumen de cierre en cache: $e');
    }
  }

  /// Obtener resumen de cierre desde cache offline
  Future<Map<String, dynamic>?> getResumenCierreCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final resumenJson = prefs.getString(_resumenCierreKey);

      if (resumenJson != null) {
        final resumenData = jsonDecode(resumenJson) as Map<String, dynamic>;
        print('📱 Resumen de cierre cargado desde cache offline');
        print('📊 Datos cargados: ${resumenData.keys.toList()}');
        return resumenData;
      }

      print('ℹ️ No hay resumen de cierre en cache offline');
      return null;
    } catch (e) {
      print('❌ Error obteniendo resumen de cierre desde cache: $e');
      return null;
    }
  }

  /// Verificar si existe resumen de cierre en cache
  Future<bool> hasResumenCierreCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(_resumenCierreKey);
    } catch (e) {
      print('❌ Error verificando cache de resumen de cierre: $e');
      return false;
    }
  }

  /// Limpiar cache de resumen de cierre
  Future<void> clearResumenCierreCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_resumenCierreKey);
      print('🗑️ Cache de resumen de cierre eliminado');
    } catch (e) {
      print('❌ Error limpiando cache de resumen de cierre: $e');
    }
  }

  // ========== CHECKPOINT SYNC MODULAR ==========

  /// Guarda el avance de una sync interrumpida para reanudar módulos OK.
  Future<void> saveSyncModulesCheckpoint({
    required List<String> completedModules,
    required List<String> pendingModules,
    required List<String> errors,
    String? abortReason,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _syncModulesCheckpointKey,
        jsonEncode({
          'completed': completedModules,
          'pending': pendingModules,
          'errors': errors,
          if (abortReason != null) 'abort_reason': abortReason,
          'updated_at': DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      print('⚠️ No se pudo guardar checkpoint de sync: $e');
    }
  }

  /// Checkpoint válido si tiene menos de [maxAge] (por defecto 6 h).
  Future<Map<String, dynamic>?> getSyncModulesCheckpoint({
    Duration maxAge = const Duration(hours: 6),
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_syncModulesCheckpointKey);
      if (raw == null || raw.isEmpty) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final updatedAt = DateTime.tryParse('${data['updated_at'] ?? ''}');
      if (updatedAt == null || DateTime.now().difference(updatedAt) > maxAge) {
        await clearSyncModulesCheckpoint();
        return null;
      }
      return data;
    } catch (e) {
      print('⚠️ Error leyendo checkpoint de sync: $e');
      return null;
    }
  }

  Future<void> clearSyncModulesCheckpoint() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_syncModulesCheckpointKey);
    } catch (e) {
      print('⚠️ Error limpiando checkpoint de sync: $e');
    }
  }

  /// Actualizar resumen de cierre con órdenes del **turno abierto**.
  ///
  /// No usa el resumen diario crudo ni órdenes de otros turnos: reconstruye
  /// el cuadre desde la cola offline (local_turno_id / ventana de fechas).
  Future<Map<String, dynamic>?> getResumenCierreWithOfflineOrders() async {
    try {
      final open = await getOpenOfflineTurno();
      if (open != null) {
        final cuadre = await buildOfflineTurnoCuadreFromLocalData(open);
        final base = await getResumenCierreCache();
        final merged = <String, dynamic>{
          if (base != null) ...base,
          ...cuadre,
          'total_ventas': cuadre['ventas_totales'],
          'ventas_totales': cuadre['ventas_totales'],
          'efectivo_real': cuadre['total_efectivo'],
          'total_efectivo': cuadre['total_efectivo'],
          'efectivo_esperado': cuadre['efectivo_esperado'],
          'ordenes_locales': cuadre['ordenes_locales'],
        };
        print(
          '📊 Resumen de cierre desde turno open '
          '${open['local_id']}: ventas=${cuadre['ventas_totales']} '
          'ops=${cuadre['operaciones_totales']}',
        );
        return merged;
      }

      // Sin turno open local: no mezclar órdenes ajenas al resumen base.
      print(
        'ℹ️ No hay turno open offline; se usa resumen base sin sumar órdenes',
      );
      return await getResumenCierreCache();
    } catch (e) {
      print('❌ Error actualizando resumen con órdenes offline: $e');
      return await getResumenCierreCache();
    }
  }

  // ============= MÉTODOS PARA EGRESOS OFFLINE =============

  /// Guardar egreso offline
  Future<void> saveOfflineEgreso(Map<String, dynamic> egresoData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final egresosOffline = await getEgresosOffline();

      // Agregar timestamp de creación offline
      egresoData['created_offline_at'] = DateTime.now().toIso8601String();
      egresoData['offline_id'] = '${DateTime.now().millisecondsSinceEpoch}';

      // 🔑 IDEMPOTENCIA: client_uuid estable por egreso, para que un reintento
      // de sincronización NO duplique el egreso en el servidor.
      if (egresoData['client_uuid'] == null ||
          (egresoData['client_uuid'] as String).isEmpty) {
        egresoData['client_uuid'] = UuidGenerator.v4();
      }

      egresosOffline.add(egresoData);

      await prefs.setString(_egresosOfflineKey, jsonEncode(egresosOffline));
      print('💾 Egreso guardado offline: ${egresoData['offline_id']}');
    } catch (e) {
      print('❌ Error guardando egreso offline: $e');
      throw e;
    }
  }

  /// Obtener egresos offline
  Future<List<Map<String, dynamic>>> getEgresosOffline() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final egresosJson = prefs.getString(_egresosOfflineKey);

      if (egresosJson != null) {
        final List<dynamic> egresosData = jsonDecode(egresosJson);
        return egresosData.cast<Map<String, dynamic>>();
      }

      return [];
    } catch (e) {
      print('❌ Error obteniendo egresos offline: $e');
      return [];
    }
  }

  /// Limpiar egresos offline después de sincronización exitosa
  Future<void> clearEgresosOffline() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_egresosOfflineKey);
      print('🧹 Egresos offline limpiados');
    } catch (e) {
      print('❌ Error limpiando egresos offline: $e');
    }
  }

  /// Sobrescribir la lista completa de egresos offline pendientes.
  Future<void> saveEgresosOffline(List<Map<String, dynamic>> egresos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_egresosOfflineKey, jsonEncode(egresos));
      print('💾 Egresos offline guardados: ${egresos.length} pendientes');
    } catch (e) {
      print('❌ Error guardando egresos offline: $e');
    }
  }

  /// Eliminar SOLO los egresos offline cuyos offline_id fueron sincronizados
  /// con éxito, conservando los demás (evita perder egresos no sincronizados
  /// cuando la subida es parcial por un corte de conexión).
  Future<void> removeEgresosOfflineByIds(List<String> syncedOfflineIds) async {
    if (syncedOfflineIds.isEmpty) return;
    try {
      final egresos = await getEgresosOffline();
      final syncedSet = syncedOfflineIds.toSet();
      final restantes =
          egresos
              .where((e) => !syncedSet.contains(e['offline_id']?.toString()))
              .toList();
      await saveEgresosOffline(restantes);
      print(
        '🧹 Egresos offline: ${syncedOfflineIds.length} sincronizados removidos, '
        '${restantes.length} conservados',
      );
    } catch (e) {
      print('❌ Error removiendo egresos offline sincronizados: $e');
    }
  }

  /// Guardar cache de egresos para modo offline
  Future<void> saveEgresosCache(List<Map<String, dynamic>> egresos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_egresosCacheKey, jsonEncode(egresos));
      print('💾 Cache de egresos guardado: ${egresos.length} egresos');
    } catch (e) {
      print('❌ Error guardando cache de egresos: $e');
    }
  }

  /// Obtener cache de egresos
  Future<List<Map<String, dynamic>>> getEgresosCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final egresosJson = prefs.getString(_egresosCacheKey);

      if (egresosJson != null) {
        final List<dynamic> egresosData = jsonDecode(egresosJson);
        return egresosData.cast<Map<String, dynamic>>();
      }

      return [];
    } catch (e) {
      print('❌ Error obteniendo cache de egresos: $e');
      return [];
    }
  }

  /// Verificar si hay egresos offline pendientes
  Future<bool> hasEgresosOffline() async {
    final egresos = await getEgresosOffline();
    return egresos.isNotEmpty;
  }

  /// Obtener conteo de egresos offline
  Future<int> getEgresosOfflineCount() async {
    final egresos = await getEgresosOffline();
    return egresos.length;
  }

  /// Limpiar cache de egresos
  Future<void> clearEgresosCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_egresosCacheKey);
      print('🧹 Cache de egresos limpiado');
    } catch (e) {
      print('❌ Error limpiando cache de egresos: $e');
    }
  }

  // ==================== CONFIGURACIÓN DE TIENDA ====================

  /// Guardar configuración de tienda
  Future<void> saveStoreConfig(Map<String, dynamic> config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storeConfigKey, jsonEncode(config));
      print('💾 Configuración de tienda guardada en cache');
    } catch (e) {
      print('❌ Error guardando configuración de tienda: $e');
    }
  }

  /// Obtener configuración de tienda
  Future<Map<String, dynamic>?> getStoreConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = prefs.getString(_storeConfigKey);

      if (configJson != null) {
        return jsonDecode(configJson) as Map<String, dynamic>;
      }

      return null;
    } catch (e) {
      print('❌ Error obteniendo configuración de tienda: $e');
      return null;
    }
  }

  /// Verificar si hay configuración de tienda en cache
  Future<bool> hasStoreConfig() async {
    try {
      final config = await getStoreConfig();
      return config != null;
    } catch (e) {
      print('❌ Error verificando configuración de tienda: $e');
      return false;
    }
  }

  /// Limpiar configuración de tienda
  Future<void> clearStoreConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storeConfigKey);
      print('🗑️ Configuración de tienda eliminada del cache');
    } catch (e) {
      print('❌ Error limpiando configuración de tienda: $e');
    }
  }

  // ==================== PREORDEN PERSISTENTE ====================

  /// Guardar preorden persistente
  Future<void> savePersistentPreorder(Map<String, dynamic> orderData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_persistentPreorderKey, jsonEncode(orderData));
      print('💾 Preorden guardada en cache persistente');
      print('📦 Items en preorden: ${orderData['items']?.length ?? 0}');
    } catch (e) {
      print('❌ Error guardando preorden persistente: $e');
    }
  }

  /// Obtener preorden persistente
  Future<Map<String, dynamic>?> getPersistentPreorder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final orderJson = prefs.getString(_persistentPreorderKey);

      if (orderJson != null) {
        final orderData = jsonDecode(orderJson) as Map<String, dynamic>;
        print('📱 Preorden cargada desde cache persistente');
        print('📦 Items en preorden: ${orderData['items']?.length ?? 0}');
        return orderData;
      }

      print('📱 No hay preorden persistente guardada');
      return null;
    } catch (e) {
      print('❌ Error obteniendo preorden persistente: $e');
      return null;
    }
  }

  /// Verificar si hay preorden persistente
  Future<bool> hasPersistentPreorder() async {
    try {
      final preorder = await getPersistentPreorder();
      return preorder != null &&
          (preorder['items'] as List?)?.isNotEmpty == true;
    } catch (e) {
      print('❌ Error verificando preorden persistente: $e');
      return false;
    }
  }

  /// Limpiar preorden persistente
  Future<void> clearPersistentPreorder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_persistentPreorderKey);
      print('🗑️ Preorden persistente eliminada del cache');
    } catch (e) {
      print('❌ Error limpiando preorden persistente: $e');
    }
  }

  // ==================== CONTROL DE DIÁLOGO DE ACTUALIZACIÓN ====================

  static const String _lastUpdateDialogShownKey = 'last_update_dialog_shown';
  static const int _updateDialogIntervalHours = 3; // Mostrar cada 3 horas

  /// Verificar si se debe mostrar el diálogo de actualización
  /// Retorna true si:
  /// - Es la primera vez (nunca se ha mostrado)
  /// - Han pasado más de 3 horas desde la última vez
  Future<bool> shouldShowUpdateDialog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastShownTimestamp = prefs.getInt(_lastUpdateDialogShownKey);

      if (lastShownTimestamp == null) {
        // Primera vez - mostrar diálogo
        print('🆕 Primera vez que se verifica actualización - Mostrar diálogo');
        return true;
      }

      final lastShownTime = DateTime.fromMillisecondsSinceEpoch(
        lastShownTimestamp,
      );
      final now = DateTime.now();
      final difference = now.difference(lastShownTime);

      final shouldShow = difference.inHours >= _updateDialogIntervalHours;

      if (shouldShow) {
        print(
          '⏰ Han pasado ${difference.inHours} horas desde el último diálogo - Mostrar actualización',
        );
      } else {
        final hoursRemaining = _updateDialogIntervalHours - difference.inHours;
        final minutesRemaining = (difference.inMinutes % 60);
        print(
          '⏳ Faltan ${hoursRemaining}h ${60 - minutesRemaining}min para mostrar próximo diálogo de actualización',
        );
      }

      return shouldShow;
    } catch (e) {
      print('❌ Error verificando si mostrar diálogo de actualización: $e');
      // En caso de error, permitir mostrar el diálogo
      return true;
    }
  }

  /// Guardar timestamp de cuando se mostró el diálogo de actualización
  Future<void> markUpdateDialogShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(_lastUpdateDialogShownKey, now);
      print(
        '✅ Diálogo de actualización marcado como mostrado: ${DateTime.now()}',
      );
    } catch (e) {
      print('❌ Error guardando timestamp de diálogo de actualización: $e');
    }
  }

  /// Obtener información del último diálogo mostrado (para debugging)
  Future<Map<String, dynamic>> getUpdateDialogInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastShownTimestamp = prefs.getInt(_lastUpdateDialogShownKey);

      if (lastShownTimestamp == null) {
        return {
          'ever_shown': false,
          'message': 'Nunca se ha mostrado el diálogo de actualización',
        };
      }

      final lastShownTime = DateTime.fromMillisecondsSinceEpoch(
        lastShownTimestamp,
      );
      final now = DateTime.now();
      final difference = now.difference(lastShownTime);

      return {
        'ever_shown': true,
        'last_shown': lastShownTime.toIso8601String(),
        'hours_since_last_shown': difference.inHours,
        'minutes_since_last_shown': difference.inMinutes,
        'should_show_now': difference.inHours >= _updateDialogIntervalHours,
      };
    } catch (e) {
      print('❌ Error obteniendo información de diálogo de actualización: $e');
      return {'error': e.toString()};
    }
  }

  /// Resetear el control del diálogo de actualización (útil para testing)
  Future<void> resetUpdateDialogControl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastUpdateDialogShownKey);
      print('🔄 Control de diálogo de actualización reseteado');
    } catch (e) {
      print('❌ Error reseteando control de diálogo: $e');
    }
  }

  // ========== SUBSCRIPTION MANAGEMENT ==========

  /// Guarda los datos de suscripción en las preferencias
  Future<void> saveSubscriptionData({
    required int subscriptionId,
    required int state,
    required int planId,
    required String planName,
    required DateTime startDate,
    DateTime? endDate,
    Map<String, dynamic>? features,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt(_subscriptionIdKey, subscriptionId);
    await prefs.setInt(_subscriptionStateKey, state);
    await prefs.setInt(_subscriptionPlanIdKey, planId);
    await prefs.setString(_subscriptionPlanNameKey, planName);
    await prefs.setString(
      _subscriptionStartDateKey,
      startDate.toIso8601String(),
    );

    if (endDate != null) {
      await prefs.setString(_subscriptionEndDateKey, endDate.toIso8601String());
    } else {
      await prefs.remove(_subscriptionEndDateKey);
    }

    if (features != null) {
      await prefs.setString(_subscriptionFeaturesKey, jsonEncode(features));
    } else {
      await prefs.remove(_subscriptionFeaturesKey);
    }

    // Marcar última verificación
    await prefs.setString(
      _subscriptionLastCheckKey,
      DateTime.now().toIso8601String(),
    );

    print(
      '💾 Datos de suscripción guardados: Plan $planName (ID: $subscriptionId)',
    );
  }

  /// Obtiene los datos de suscripción guardados
  Future<Map<String, dynamic>?> getSubscriptionData() async {
    final prefs = await SharedPreferences.getInstance();

    final subscriptionId = prefs.getInt(_subscriptionIdKey);
    if (subscriptionId == null) return null;

    final state = prefs.getInt(_subscriptionStateKey);
    final planId = prefs.getInt(_subscriptionPlanIdKey);
    final planName = prefs.getString(_subscriptionPlanNameKey);
    final startDateStr = prefs.getString(_subscriptionStartDateKey);
    final endDateStr = prefs.getString(_subscriptionEndDateKey);
    final featuresStr = prefs.getString(_subscriptionFeaturesKey);
    final lastCheckStr = prefs.getString(_subscriptionLastCheckKey);

    if (state == null ||
        planId == null ||
        planName == null ||
        startDateStr == null) {
      return null;
    }

    return {
      'subscription_id': subscriptionId,
      'state': state,
      'plan_id': planId,
      'plan_name': planName,
      'start_date': DateTime.parse(startDateStr),
      'end_date': endDateStr != null ? DateTime.parse(endDateStr) : null,
      'features': featuresStr != null ? jsonDecode(featuresStr) : null,
      'last_check': lastCheckStr != null ? DateTime.parse(lastCheckStr) : null,
    };
  }

  /// Verifica si la suscripción guardada está activa
  Future<bool> hasActiveSubscriptionStored() async {
    final subscriptionData = await getSubscriptionData();
    if (subscriptionData == null) return false;

    final state = subscriptionData['state'] as int;
    final endDate = subscriptionData['end_date'] as DateTime?;

    // Estado 1 = Activa
    final isActiveState = state == 1;

    // Verificar si no ha vencido
    final isNotExpired = endDate == null || endDate.isAfter(DateTime.now());

    return isActiveState && isNotExpired;
  }

  /// Obtiene el nombre del plan de suscripción
  Future<String?> getSubscriptionPlanName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_subscriptionPlanNameKey);
  }

  /// Obtiene las funciones habilitadas de la suscripción
  Future<Map<String, dynamic>?> getSubscriptionFeatures() async {
    final prefs = await SharedPreferences.getInstance();
    final featuresStr = prefs.getString(_subscriptionFeaturesKey);
    if (featuresStr == null) return null;

    try {
      return jsonDecode(featuresStr) as Map<String, dynamic>;
    } catch (e) {
      print('❌ Error decodificando funciones de suscripción: $e');
      return null;
    }
  }

  /// Verifica si una función específica está habilitada
  Future<bool> isFeatureEnabled(String feature) async {
    final features = await getSubscriptionFeatures();
    if (features == null) return false;

    return features[feature] == true;
  }

  /// Obtiene la fecha de última verificación de suscripción
  Future<DateTime?> getSubscriptionLastCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheckStr = prefs.getString(_subscriptionLastCheckKey);
    if (lastCheckStr == null) return null;

    try {
      return DateTime.parse(lastCheckStr);
    } catch (e) {
      return null;
    }
  }

  /// Verifica si es necesario actualizar los datos de suscripción (más de 5 minutos)
  Future<bool> shouldRefreshSubscription() async {
    final lastCheck = await getSubscriptionLastCheck();
    if (lastCheck == null) return true;

    final now = DateTime.now();
    final difference = now.difference(lastCheck).inMinutes;

    return difference >= 5;
  }

  /// Limpia los datos de suscripción
  Future<void> clearSubscriptionData() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_subscriptionIdKey);
    await prefs.remove(_subscriptionStateKey);
    await prefs.remove(_subscriptionPlanIdKey);
    await prefs.remove(_subscriptionPlanNameKey);
    await prefs.remove(_subscriptionStartDateKey);
    await prefs.remove(_subscriptionEndDateKey);
    await prefs.remove(_subscriptionFeaturesKey);
    await prefs.remove(_subscriptionLastCheckKey);

    print('🧹 Datos de suscripción limpiados');
  }

  // ========== LICENCIA OFFLINE FIRMADA + ANTI-ROLLBACK ==========

  /// Guarda el payload + firma HMAC de la licencia offline.
  Future<void> saveSignedOfflineLicense({
    required Map<String, dynamic> licencia,
    required String firma,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_signedOfflineLicenseKey, jsonEncode(licencia));
    await prefs.setString(_signedOfflineLicenseFirmaKey, firma);
    print('💾 Licencia offline firmada persistida');
  }

  /// Obtiene la licencia firmada local: `{licencia: Map, firma: String}`.
  Future<Map<String, dynamic>?> getSignedOfflineLicense() async {
    final prefs = await SharedPreferences.getInstance();
    final licenciaStr = prefs.getString(_signedOfflineLicenseKey);
    final firma = prefs.getString(_signedOfflineLicenseFirmaKey);
    if (licenciaStr == null || firma == null || firma.isEmpty) return null;

    try {
      final decoded = jsonDecode(licenciaStr);
      if (decoded is! Map) return null;
      return {'licencia': Map<String, dynamic>.from(decoded), 'firma': firma};
    } catch (e) {
      print('❌ Error leyendo licencia firmada: $e');
      return null;
    }
  }

  Future<void> clearSignedOfflineLicense() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_signedOfflineLicenseKey);
    await prefs.remove(_signedOfflineLicenseFirmaKey);
    print('🧹 Licencia offline firmada eliminada');
  }

  /// Actualiza el máximo timestamp observado (anti-rollback de reloj).
  Future<void> updateLastSeenTimestamp([DateTime? at]) async {
    final prefs = await SharedPreferences.getInstance();
    final now = at ?? DateTime.now();
    final existing = prefs.getString(_lastSeenTimestampKey);
    DateTime? previous;
    if (existing != null) {
      previous = DateTime.tryParse(existing);
    }
    if (previous == null || now.isAfter(previous)) {
      await prefs.setString(_lastSeenTimestampKey, now.toIso8601String());
    }
  }

  Future<DateTime?> getLastSeenTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastSeenTimestampKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// Actualiza last_seen y detecta rollback de reloj.
  /// Retorna `false` si el reloj del dispositivo es anterior al último visto
  /// (con tolerancia de 2 minutos por desfase menor).
  Future<bool> touchAndValidateClock() async {
    final now = DateTime.now();
    final lastSeen = await getLastSeenTimestamp();
    if (lastSeen != null &&
        now.isBefore(lastSeen.subtract(const Duration(minutes: 2)))) {
      print('⛔ Rollback de reloj detectado: now=$now lastSeen=$lastSeen');
      return false;
    }
    await updateLastSeenTimestamp(now);
    return true;
  }

  // ==================== DENOMINACIONES DE MONEDA ====================

  /// Guardar denominaciones de moneda en cache
  Future<void> saveMonedasDenominacion(
    List<Map<String, dynamic>> denominaciones,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final denominacionesJson = jsonEncode(denominaciones);
      await prefs.setString(_monedasDenominacionKey, denominacionesJson);
      print('💰 Denominaciones de moneda guardadas en cache');
      print('📊 Total denominaciones: ${denominaciones.length}');

      // Log de monedas disponibles
      final monedas =
          denominaciones.map((d) => d['codigo_moneda']).toSet().toList();
      print('💱 Monedas disponibles: ${monedas.join(', ')}');
    } catch (e) {
      print('❌ Error guardando denominaciones de moneda: $e');
    }
  }

  /// Obtener todas las denominaciones de moneda desde cache
  Future<List<Map<String, dynamic>>> getMonedasDenominacion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final denominacionesJson = prefs.getString(_monedasDenominacionKey);

      if (denominacionesJson != null) {
        final denominacionesList =
            jsonDecode(denominacionesJson) as List<dynamic>;
        final denominaciones =
            denominacionesList
                .map((item) => item as Map<String, dynamic>)
                .toList();

        print(
          '💰 Denominaciones cargadas desde cache: ${denominaciones.length}',
        );
        return denominaciones;
      }

      print('⚠️ No hay denominaciones de moneda en cache');
      return [];
    } catch (e) {
      print('❌ Error cargando denominaciones de moneda: $e');
      return [];
    }
  }

  /// Obtener denominaciones de una moneda específica
  Future<List<Map<String, dynamic>>> getDenominacionesPorMoneda(
    String codigoMoneda,
  ) async {
    try {
      final todasLasDenominaciones = await getMonedasDenominacion();
      final denominacionesMoneda =
          todasLasDenominaciones
              .where(
                (d) =>
                    d['codigo_moneda'] == codigoMoneda && d['active'] == true,
              )
              .toList();

      // Ordenar por denominación de mayor a menor
      denominacionesMoneda.sort(
        (a, b) =>
            (b['denominacion'] as num).compareTo(a['denominacion'] as num),
      );

      print(
        '💱 Denominaciones para $codigoMoneda: ${denominacionesMoneda.length}',
      );
      return denominacionesMoneda;
    } catch (e) {
      print('❌ Error obteniendo denominaciones para $codigoMoneda: $e');
      return [];
    }
  }

  /// IDs de denominaciones que el vendedor decidió ocultar del contador.
  Future<Set<int>> getHiddenDenominations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hiddenJson = prefs.getString(_hiddenDenominationsKey);
      if (hiddenJson == null) return {};
      final hiddenList = jsonDecode(hiddenJson) as List<dynamic>;
      return hiddenList.map((e) => e as int).toSet();
    } catch (e) {
      print('❌ Error cargando denominaciones ocultas: $e');
      return {};
    }
  }

  Future<void> saveHiddenDenominations(Set<int> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hiddenJson = jsonEncode(ids.toList());
      await prefs.setString(_hiddenDenominationsKey, hiddenJson);
      print('💰 Denominaciones ocultas guardadas: ${ids.length}');
    } catch (e) {
      print('❌ Error guardando denominaciones ocultas: $e');
    }
  }

  /// Obtener lista de monedas disponibles (códigos únicos)
  Future<List<String>> getMonedasDisponibles() async {
    try {
      final denominaciones = await getMonedasDenominacion();
      final monedasSet =
          denominaciones
              .where((d) => d['active'] == true)
              .map((d) => d['codigo_moneda'] as String)
              .toSet();

      final monedas = monedasSet.toList();
      monedas.sort(); // Ordenar alfabéticamente

      print('💱 Monedas disponibles: ${monedas.join(', ')}');
      return monedas;
    } catch (e) {
      print('❌ Error obteniendo monedas disponibles: $e');
      return [];
    }
  }

  /// Verificar si hay denominaciones de moneda en cache
  Future<bool> hasMonedasDenominacion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final denominacionesJson = prefs.getString(_monedasDenominacionKey);

      if (denominacionesJson == null) return false;

      final denominacionesList =
          jsonDecode(denominacionesJson) as List<dynamic>;
      return denominacionesList.isNotEmpty;
    } catch (e) {
      print('❌ Error verificando cache de denominaciones: $e');
      return false;
    }
  }

  /// Limpiar cache de denominaciones de moneda
  Future<void> clearMonedasDenominacion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_monedasDenominacionKey);
      print('🗑️ Cache de denominaciones de moneda eliminado');
    } catch (e) {
      print('❌ Error limpiando cache de denominaciones: $e');
    }
  }

  /// Obtener información de denominaciones para debugging
  Future<Map<String, dynamic>> getDenominacionesInfo() async {
    try {
      final denominaciones = await getMonedasDenominacion();
      final monedas = await getMonedasDisponibles();

      final info = <String, dynamic>{
        'total_denominaciones': denominaciones.length,
        'monedas_disponibles': monedas,
        'denominaciones_por_moneda': <String, int>{},
      };

      for (final moneda in monedas) {
        final denominacionesMoneda = await getDenominacionesPorMoneda(moneda);
        info['denominaciones_por_moneda'][moneda] = denominacionesMoneda.length;
      }

      return info;
    } catch (e) {
      print('❌ Error obteniendo info de denominaciones: $e');
      return {};
    }
  }

  // ==================== TIPO DE CAMBIO CUP-USD ====================

  /// Guardar tipo de cambio CUP-USD en cache
  Future<void> saveCambioCupUsd(double cambio) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_cambioCupUsdKey, cambio);
      print('💱 Tipo de cambio CUP-USD guardado: $cambio');
    } catch (e) {
      print('❌ Error guardando tipo de cambio CUP-USD: $e');
    }
  }

  /// Obtener tipo de cambio CUP-USD desde cache
  Future<double> getCambioCupUsd() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cambio = prefs.getDouble(_cambioCupUsdKey);

      if (cambio != null) {
        print('💱 Tipo de cambio CUP-USD desde cache: $cambio');
        return cambio;
      } else {
        print(
          '⚠️ No hay tipo de cambio CUP-USD en cache, usando default: 420.0',
        );
        return 420.0; // Valor por defecto
      }
    } catch (e) {
      print('❌ Error obteniendo tipo de cambio CUP-USD: $e');
      return 420.0; // Valor por defecto
    }
  }

  /// Verificar si hay tipo de cambio CUP-USD en cache
  Future<bool> hasCambioCupUsd() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(_cambioCupUsdKey);
    } catch (e) {
      print('❌ Error verificando cache de tipo de cambio: $e');
      return false;
    }
  }

  /// Limpiar cache de tipo de cambio CUP-USD
  Future<void> clearCambioCupUsd() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cambioCupUsdKey);
      print('🗑️ Cache de tipo de cambio CUP-USD eliminado');
    } catch (e) {
      print('❌ Error limpiando cache de tipo de cambio: $e');
    }
  }

  // ==================== FRACTION STEP ====================

  Future<double> getFractionStep() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('fraction_step') ?? 0.5;
  }

  Future<void> setFractionStep(double step) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fraction_step', step);
  }

  // ==================== PRODUCTOS POR DEFECTO EN ORDEN ====================

  /// Clave local scoped por usuario + tienda.
  Future<String> _defaultOrderItemsScopedKey() async {
    final userId = await getUserId() ?? 'anon';
    final idTienda = await getIdTienda() ?? 0;
    return '${_defaultOrderItemsKey}_${userId}_$idTienda';
  }

  Future<String> _defaultOrderItemsMigratedKey() async {
    final userId = await getUserId() ?? 'anon';
    final idTienda = await getIdTienda() ?? 0;
    return '${_defaultOrderItemsKey}_migrated_${userId}_$idTienda';
  }

  Future<bool> _isDefaultOrderItemsMigrated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(await _defaultOrderItemsMigratedKey()) ?? false;
  }

  Future<void> _markDefaultOrderItemsMigrated([bool value = true]) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(await _defaultOrderItemsMigratedKey(), value);
  }

  /// Lee solo el cache local (clave scoped, con fallback a la clave legacy).
  Future<List<Map<String, dynamic>>> _getDefaultOrderItemsLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scopedKey = await _defaultOrderItemsScopedKey();
      var raw = prefs.getString(scopedKey);

      // Migración de clave global antigua → scoped
      if (raw == null) {
        final legacy = prefs.getString(_defaultOrderItemsKey);
        if (legacy != null) {
          raw = legacy;
          await prefs.setString(scopedKey, legacy);
          print('📦 Productos por defecto: clave legacy migrada a $scopedKey');
        }
      }

      if (raw == null) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      print('❌ Error leyendo productos por defecto locales: $e');
      return [];
    }
  }

  Future<void> _saveDefaultOrderItemsLocal(
    List<Map<String, dynamic>> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _defaultOrderItemsScopedKey();
    await prefs.setString(scopedKey, jsonEncode(items));
  }

  /// Convierte filas del RPC a formato local `{product, cantidad}`.
  List<Map<String, dynamic>> _mapServerDefaultItems(
    List<Map<String, dynamic>> rows,
  ) {
    return rows.map((row) {
      final idProducto = (row['id_producto'] as num?)?.toInt() ?? 0;
      final cantidad = (row['cantidad'] as num?)?.toDouble() ?? 1.0;
      return <String, dynamic>{
        'product': <String, dynamic>{
          'id': idProducto,
          'denominacion': row['denominacion'] ?? 'Producto',
          'descripcion': null,
          'sku': row['sku'],
          'foto': row['imagen'],
          'precio': (row['precio_venta'] as num?)?.toDouble() ?? 0.0,
          'cantidad': 0,
          'es_refrigerado': false,
          'es_fragil': false,
          'es_peligroso': false,
          'es_vendible': row['es_vendible'] ?? true,
          'es_comprable': true,
          'es_inventariable': true,
          'es_por_lotes': false,
          'es_elaborado': row['es_elaborado'] ?? false,
          'es_servicio': row['es_servicio'] ?? false,
          'es_paquete': row['es_paquete'] ?? false,
          'categoria': '',
          'variantes': <dynamic>[],
          'reservado_carnaval': 0,
        },
        'cantidad': cantidad,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _toServerPayload(
    List<Map<String, dynamic>> items,
  ) {
    final payload = <Map<String, dynamic>>[];
    for (var i = 0; i < items.length; i++) {
      final entry = items[i];
      final product = entry['product'];
      int? idProducto;
      if (product is Map) {
        idProducto = (product['id'] as num?)?.toInt();
      }
      if (idProducto == null) continue;
      final cantidad = (entry['cantidad'] as num?)?.toDouble() ?? 1.0;
      if (cantidad <= 0) continue;
      payload.add({
        'id_producto': idProducto,
        'cantidad': cantidad,
        'orden': i,
      });
    }
    return payload;
  }

  Future<bool> _canReachDefaultItemsServer() async {
    if (await isOfflineModeEnabled()) return false;
    final token = await getAccessToken();
    if (token == null || token.isEmpty || token == 'offline_mode') {
      return false;
    }
    return true;
  }

  Future<List<Map<String, dynamic>>> _fetchDefaultOrderItemsFromServer(
    int idTienda,
  ) async {
    final response = await Supabase.instance.client.rpc(
      'fn_get_productos_orden_default',
      params: {'p_id_tienda': idTienda},
    );
    if (response == null) return [];
    if (response is! List) return [];
    return response
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _pushDefaultOrderItemsToServer(
    int idTienda,
    List<Map<String, dynamic>> items,
  ) async {
    await Supabase.instance.client.rpc(
      'fn_set_productos_orden_default',
      params: {'p_id_tienda': idTienda, 'p_items': _toServerPayload(items)},
    );
  }

  /// Guardar lista de productos por defecto (local + servidor si hay red).
  ///
  /// Cada elemento: { 'product': Map (Product.toJson), 'cantidad': double }
  ///
  /// Retorna `{ success, savedLocal, savedServer, message }`.
  Future<Map<String, dynamic>> saveDefaultOrderItems(
    List<Map<String, dynamic>> items,
  ) async {
    try {
      await _saveDefaultOrderItemsLocal(items);
      print('💾 Productos por defecto locales: ${items.length}');

      var savedServer = false;
      String message = 'Guardado en este dispositivo';

      if (await _canReachDefaultItemsServer()) {
        final idTienda = await getIdTienda();
        if (idTienda != null) {
          try {
            await _pushDefaultOrderItemsToServer(idTienda, items);
            await _markDefaultOrderItemsMigrated(true);
            savedServer = true;
            message = 'Guardado en servidor y dispositivo';
            print('☁️ Productos por defecto subidos al servidor');
          } catch (e) {
            print('⚠️ No se pudo guardar en servidor: $e');
            message =
                'Guardado solo en este dispositivo (sin conexión al servidor)';
          }
        }
      }

      return {
        'success': true,
        'savedLocal': true,
        'savedServer': savedServer,
        'message': message,
      };
    } catch (e) {
      print('❌ Error guardando productos por defecto: $e');
      return {
        'success': false,
        'savedLocal': false,
        'savedServer': false,
        'message': 'Error guardando: $e',
      };
    }
  }

  /// Obtener lista de productos por defecto.
  /// Online: servidor gana; si servidor vacío y hay local no migrado, lo sube.
  /// Offline: solo cache local.
  Future<List<Map<String, dynamic>>> getDefaultOrderItems() async {
    try {
      final local = await _getDefaultOrderItemsLocal();

      if (!await _canReachDefaultItemsServer()) {
        return local;
      }

      final idTienda = await getIdTienda();
      if (idTienda == null) return local;

      try {
        final serverRows = await _fetchDefaultOrderItemsFromServer(idTienda);
        if (serverRows.isNotEmpty) {
          final mapped = _mapServerDefaultItems(serverRows);
          await _saveDefaultOrderItemsLocal(mapped);
          await _markDefaultOrderItemsMigrated(true);
          print('☁️ Productos por defecto desde servidor: ${mapped.length}');
          return mapped;
        }

        // Servidor vacío: migrar local una sola vez
        if (local.isNotEmpty && !await _isDefaultOrderItemsMigrated()) {
          await _pushDefaultOrderItemsToServer(idTienda, local);
          await _markDefaultOrderItemsMigrated(true);
          print(
            '📤 Migración local→servidor de productos por defecto '
            '(${local.length})',
          );
        }
        return local;
      } catch (e) {
        print('⚠️ Fallback local productos por defecto: $e');
        return local;
      }
    } catch (e) {
      print('❌ Error obteniendo productos por defecto: $e');
      return [];
    }
  }

  /// Sube de forma explícita la configuración local al servidor (forzar sync).
  Future<Map<String, dynamic>> uploadLocalDefaultOrderItemsToServer() async {
    try {
      if (!await _canReachDefaultItemsServer()) {
        return {'success': false, 'message': 'Sin conexión al servidor'};
      }
      final idTienda = await getIdTienda();
      if (idTienda == null) {
        return {'success': false, 'message': 'No hay tienda seleccionada'};
      }
      final local = await _getDefaultOrderItemsLocal();
      await _pushDefaultOrderItemsToServer(idTienda, local);
      await _markDefaultOrderItemsMigrated(true);
      return {
        'success': true,
        'count': local.length,
        'message':
            local.isEmpty
                ? 'Lista vacía sincronizada en el servidor'
                : 'Se subieron ${local.length} productos al servidor',
      };
    } catch (e) {
      print('❌ Error subiendo productos por defecto: $e');
      return {'success': false, 'message': 'Error al subir: $e'};
    }
  }

  /// Limpiar todos los productos por defecto (local + servidor).
  Future<Map<String, dynamic>> clearDefaultOrderItems() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scopedKey = await _defaultOrderItemsScopedKey();
      await prefs.remove(scopedKey);
      // También limpia la clave legacy si existiera
      await prefs.remove(_defaultOrderItemsKey);
      print('🗑️ Productos por defecto locales eliminados');

      var clearedServer = false;
      if (await _canReachDefaultItemsServer()) {
        final idTienda = await getIdTienda();
        if (idTienda != null) {
          try {
            await _pushDefaultOrderItemsToServer(idTienda, const []);
            await _markDefaultOrderItemsMigrated(true);
            clearedServer = true;
          } catch (e) {
            print('⚠️ No se pudo limpiar en servidor: $e');
          }
        }
      }

      return {
        'success': true,
        'clearedServer': clearedServer,
        'message':
            clearedServer
                ? 'Lista eliminada en servidor y dispositivo'
                : 'Lista eliminada en este dispositivo',
      };
    } catch (e) {
      print('❌ Error limpiando productos por defecto: $e');
      return {
        'success': false,
        'clearedServer': false,
        'message': 'Error limpiando: $e',
      };
    }
  }

  // ==================== CONTEOS DE INVENTARIO EN CIERRE ====================

  String _inventoryCountCierreKey(int? idTpv) {
    return '${_inventoryCountCierreKeyPrefix}${idTpv ?? 0}';
  }

  /// Guarda los conteos de inventario introducidos durante el cierre.
  /// [counts] usa como clave el id del producto como String.
  Future<void> saveInventoryCountCierre(
    int? idTpv,
    Map<String, double> counts,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(counts);
      await prefs.setString(_inventoryCountCierreKey(idTpv), json);
      print('💾 Conteos de inventario guardados (${counts.length} productos)');
    } catch (e) {
      print('❌ Error guardando conteos de inventario: $e');
    }
  }

  /// Recupera los conteos de inventario guardados durante el cierre.
  Future<Map<String, double>> getInventoryCountCierre(int? idTpv) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_inventoryCountCierreKey(idTpv));
      if (json == null || json.isEmpty) return {};
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return decoded.map(
        (key, value) => MapEntry(key, (value as num).toDouble()),
      );
    } catch (e) {
      print('❌ Error obteniendo conteos de inventario: $e');
      return {};
    }
  }

  /// Elimina los conteos de inventario guardados.
  Future<void> clearInventoryCountCierre(int? idTpv) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_inventoryCountCierreKey(idTpv));
      print('🗑️ Conteos de inventario eliminados');
    } catch (e) {
      print('❌ Error limpiando conteos de inventario: $e');
    }
  }

  // ==================== CONTEOS DE INVENTARIO EN APERTURA ====================

  String _inventoryCountAperturaKey(int? idTpv) {
    return '${_inventoryCountAperturaKeyPrefix}${idTpv ?? 0}';
  }

  /// Guarda los conteos de inventario introducidos durante la apertura.
  Future<void> saveInventoryCountApertura(
    int? idTpv,
    Map<String, double> counts,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(counts);
      await prefs.setString(_inventoryCountAperturaKey(idTpv), json);
      print(
        '💾 Conteos de inventario (apertura) guardados (${counts.length} productos)',
      );
    } catch (e) {
      print('❌ Error guardando conteos de inventario (apertura): $e');
    }
  }

  /// Recupera los conteos de inventario guardados durante la apertura.
  Future<Map<String, double>> getInventoryCountApertura(int? idTpv) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_inventoryCountAperturaKey(idTpv));
      if (json == null || json.isEmpty) return {};
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return decoded.map(
        (key, value) => MapEntry(key, (value as num).toDouble()),
      );
    } catch (e) {
      print('❌ Error obteniendo conteos de inventario (apertura): $e');
      return {};
    }
  }

  /// Elimina los conteos de inventario de apertura guardados.
  Future<void> clearInventoryCountApertura(int? idTpv) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_inventoryCountAperturaKey(idTpv));
      print('🗑️ Conteos de inventario (apertura) eliminados');
    } catch (e) {
      print('❌ Error limpiando conteos de inventario (apertura): $e');
    }
  }
}

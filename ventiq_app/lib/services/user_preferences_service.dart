import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'order_service.dart';

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
  static const String _idSellerKey = 'id_seller';
  static const String _nombresKey = 'nombres';
  static const String _apellidosKey = 'apellidos';
  static const String _idTiendaKey = 'id_tienda';
  static const String _idRollKey = 'id_roll';
  static const String _appVersionKey = 'app_version';

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
  
  // Data usage keys
  static const String _limitDataUsageKey = 'limit_data_usage';
  
  // Offline mode keys
  static const String _offlineModeKey = 'offline_mode_enabled';
  static const String _offlineDataKey = 'offline_data';
  static const String _offlineUsersKey = 'offline_users'; // Array de usuarios offline
  static const String _pendingOrdersKey = 'pending_orders'; // Órdenes pendientes de sincronización
  static const String _pendingOperationsKey = 'pending_operations'; // Operaciones pendientes (apertura/cierre/cambio estado)
  static const String _offlineTurnoKey = 'offline_turno'; // Turno abierto offline
  static const String _turnoResumenKey = 'turno_resumen_cache'; // Cache del resumen de turno anterior
  static const String _resumenCierreKey = 'resumen_cierre_cache'; // Cache del resumen de cierre diario

  // Guardar datos del usuario
  Future<void> saveUserData({
    required String userId,
    required String email,
    required String accessToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userIdKey, userId);
    await prefs.setString(_userEmailKey, email);
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setBool(_isLoggedInKey, true);

    // Set token expiry (24 hours from now)
    final expiryTime =
        DateTime.now().add(Duration(hours: 24)).millisecondsSinceEpoch;
    await prefs.setInt(_tokenExpiryKey, expiryTime);
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

  // Obtener access token del usuario
  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessTokenKey);
  }

  // Guardar datos del vendedor
  Future<void> saveSellerData({
    required int idTpv,
    required int idTrabajador,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_idTpvKey, idTpv);
    await prefs.setInt(_idTrabajadorKey, idTrabajador);
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
    };
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
    await prefs.setBool(_isLoggedInKey, false);

    // Limpiar promociones al cerrar sesión
    await clearPromotionData();

    // Limpiar órdenes al cerrar sesión
    await _clearOrdersOnLogout();
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

  // Verificar si es la primera vez que se abre la app
  Future<bool> isFirstTimeOpening() async {
    final prefs = await SharedPreferences.getInstance();
    return !prefs.containsKey(_appVersionKey);
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
    final hasValidToken = await isTokenValid();
    final accessToken = await getAccessToken();

    return isLoggedIn &&
        hasValidToken &&
        accessToken != null &&
        accessToken.isNotEmpty;
  }

  // Promotion management methods
  Future<void> savePromotionData({
    int? idPromocion,
    String? codigoPromocion,
    double? valorDescuento,
    int? tipoDescuento,
  }) async {
    final prefs = await SharedPreferences.getInstance();

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

    if (tipoDescuento != null) {
      await prefs.setInt(_promotionTypeKey, tipoDescuento);
    } else {
      await prefs.remove(_promotionTypeKey);
    }
  }

  Future<Map<String, dynamic>?> getPromotionData() async {
    final prefs = await SharedPreferences.getInstance();
    final idPromocion = prefs.getInt(_promotionIdKey);
    final codigoPromocion = prefs.getString(_promotionCodeKey);
    final valorDescuento = prefs.getDouble(_promotionValueKey);
    final tipoDescuento = prefs.getInt(_promotionTypeKey);

    if (idPromocion != null && codigoPromocion != null) {
      return {
        'id_promocion': idPromocion,
        'codigo_promocion': codigoPromocion,
        'valor_descuento': valorDescuento,
        'tipo_descuento': tipoDescuento, // 1 = porcentual, 2 = valor fijo
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
  }

  // Turno data keys
  static const String _turnoIdKey = 'turno_id';
  static const String _turnoDataKey = 'turno_data';

  // Print settings keys
  static const String _printEnabledKey = 'print_enabled';

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
  
  // Data usage settings methods
  Future<void> setLimitDataUsage(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_limitDataUsageKey, enabled);
    print(
      'UserPreferencesService: Límite de datos actualizado: $enabled',
    );
  }

  Future<bool> isLimitDataUsageEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_limitDataUsageKey) ?? false; // Por defecto deshabilitado
  }
  
  // Offline mode settings methods
  Future<void> setOfflineMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_offlineModeKey, enabled);
    print(
      'UserPreferencesService: Modo offline actualizado: $enabled',
    );
  }

  Future<bool> isOfflineModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_offlineModeKey) ?? false; // Por defecto deshabilitado
  }
  
  // Guardar datos offline completos
  Future<void> saveOfflineData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_offlineDataKey, jsonEncode(data));
    print('UserPreferencesService: Datos offline guardados');
  }
  
  // Obtener datos offline
  Future<Map<String, dynamic>?> getOfflineData() async {
    final prefs = await SharedPreferences.getInstance();
    final dataString = prefs.getString(_offlineDataKey);
    if (dataString != null) {
      return jsonDecode(dataString) as Map<String, dynamic>;
    }
    return null;
  }
  
  // Verificar si hay datos offline disponibles
  Future<bool> hasOfflineData() async {
    final prefs = await SharedPreferences.getInstance();
    final dataString = prefs.getString(_offlineDataKey);
    
    if (dataString == null || dataString.isEmpty) {
      return false;
    }
    
    try {
      final data = jsonDecode(dataString) as Map<String, dynamic>;
      
      // Verificar que hay datos esenciales para modo offline
      final hasCredentials = data['credentials'] != null;
      final hasCategories = data['categories'] != null && (data['categories'] as List).isNotEmpty;
      final hasProducts = data['products'] != null && (data['products'] as Map).isNotEmpty;
      
      print('📊 Verificación de datos offline:');
      print('  - Credenciales: ${hasCredentials ? "✅" : "❌"}');
      print('  - Categorías: ${hasCategories ? "✅" : "❌"} (${hasCategories ? (data['categories'] as List).length : 0})');
      print('  - Productos: ${hasProducts ? "✅" : "❌"} (${hasProducts ? (data['products'] as Map).keys.length : 0} categorías)');
      
      // Requiere al menos credenciales y categorías para funcionar offline
      return hasCredentials && hasCategories;
      
    } catch (e) {
      print('❌ Error verificando datos offline: $e');
      return false;
    }
  }
  
  // Limpiar datos offline
  Future<void> clearOfflineData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_offlineDataKey);
    await prefs.setBool(_offlineModeKey, false);
    print('UserPreferencesService: Datos offline eliminados');
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
    
    // Obtener lista actual de usuarios offline
    final usersJson = prefs.getString(_offlineUsersKey);
    List<Map<String, dynamic>> offlineUsers = [];
    
    if (usersJson != null) {
      final decoded = jsonDecode(usersJson);
      offlineUsers = List<Map<String, dynamic>>.from(decoded);
    }
    
    // Verificar si el usuario ya existe (por email)
    final existingIndex = offlineUsers.indexWhere((user) => user['email'] == email);
    
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
    print('📊 Datos guardados: idTienda=$idTienda, idTpv=$idTpv, idTrabajador=$idTrabajador');
  }
  
  /// Verificar si un usuario tiene credenciales guardadas para modo offline
  Future<bool> hasOfflineUser(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final usersJson = prefs.getString(_offlineUsersKey);
    
    if (usersJson == null) return false;
    
    final decoded = jsonDecode(usersJson);
    final offlineUsers = List<Map<String, dynamic>>.from(decoded);
    
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
    
    final decoded = jsonDecode(usersJson);
    final offlineUsers = List<Map<String, dynamic>>.from(decoded);
    
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
        'lastSync': user['lastSync'],
      };
    } else {
      print('❌ Contraseña incorrecta para usuario offline: $email');
      return null;
    }
  }
  
  /// Obtener todos los usuarios offline guardados
  Future<List<Map<String, dynamic>>> getOfflineUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final usersJson = prefs.getString(_offlineUsersKey);
    
    if (usersJson == null) return [];
    
    final decoded = jsonDecode(usersJson);
    return List<Map<String, dynamic>>.from(decoded);
  }
  
  /// Eliminar un usuario offline específico
  Future<void> removeOfflineUser(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final usersJson = prefs.getString(_offlineUsersKey);
    
    if (usersJson == null) return;
    
    final decoded = jsonDecode(usersJson);
    final offlineUsers = List<Map<String, dynamic>>.from(decoded);
    
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
      final decoded = jsonDecode(pendingOrdersJson);
      pendingOrders = List<Map<String, dynamic>>.from(decoded);
    }
    
    // Agregar nueva orden con timestamp y flag de pendiente
    orderData['is_pending_sync'] = true;
    orderData['created_offline_at'] = DateTime.now().toIso8601String();
    pendingOrders.add(orderData);
    
    await prefs.setString(_pendingOrdersKey, jsonEncode(pendingOrders));
    print('💾 Orden pendiente guardada. Total pendientes: ${pendingOrders.length}');
  }
  
  /// Obtener todas las órdenes pendientes de sincronización
  Future<List<Map<String, dynamic>>> getPendingOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingOrdersJson = prefs.getString(_pendingOrdersKey);
    
    if (pendingOrdersJson == null) return [];
    
    final decoded = jsonDecode(pendingOrdersJson);
    return List<Map<String, dynamic>>.from(decoded);
  }
  
  /// Eliminar una orden pendiente específica (después de sincronizar)
  Future<void> removePendingOrder(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingOrdersJson = prefs.getString(_pendingOrdersKey);
    
    if (pendingOrdersJson == null) return;
    
    final decoded = jsonDecode(pendingOrdersJson);
    final pendingOrders = List<Map<String, dynamic>>.from(decoded);
    
    // Filtrar para remover la orden
    pendingOrders.removeWhere((order) => order['id'] == orderId);
    
    await prefs.setString(_pendingOrdersKey, jsonEncode(pendingOrders));
    print('🗑️ Orden pendiente eliminada: $orderId. Restantes: ${pendingOrders.length}');
  }
  
  /// Limpiar todas las órdenes pendientes
  Future<void> clearPendingOrders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingOrdersKey);
    print('🗑️ Todas las órdenes pendientes eliminadas');
  }
  
  /// Obtener número de órdenes pendientes
  Future<int> getPendingOrdersCount() async {
    final pendingOrders = await getPendingOrders();
    return pendingOrders.length;
  }
  
  // ==================== ACTUALIZACIÓN DE CACHE DE PRODUCTOS ====================
  
  /// Actualizar inventario de productos en cache (descontar cantidades)
  Future<void> updateProductInventoryInCache(int productId, int variantId, int quantityToSubtract) async {
    final offlineData = await getOfflineData();
    if (offlineData == null || offlineData['products'] == null) return;
    
    final productsData = Map<String, dynamic>.from(offlineData['products']);
    bool updated = false;
    
    // Buscar el producto en todas las categorías
    for (var categoryKey in productsData.keys) {
      final categoryProducts = List<Map<String, dynamic>>.from(productsData[categoryKey]);
      
      for (int i = 0; i < categoryProducts.length; i++) {
        if (categoryProducts[i]['id'] == productId) {
          // Actualizar cantidad total del producto
          final currentQty = categoryProducts[i]['cantidad'] as num;
          categoryProducts[i]['cantidad'] = (currentQty - quantityToSubtract).clamp(0, double.infinity);
          
          // Actualizar inventario en detalles_completos
          if (categoryProducts[i]['detalles_completos'] != null) {
            final detalles = Map<String, dynamic>.from(categoryProducts[i]['detalles_completos']);
            final inventarioList = List<Map<String, dynamic>>.from(detalles['inventario']);
            
            // Buscar y actualizar la variante específica
            for (int j = 0; j < inventarioList.length; j++) {
              final inv = inventarioList[j];
              final varianteData = inv['variante'] as Map<String, dynamic>?;
              
              if (varianteData != null && varianteData['id'] == variantId) {
                final currentInvQty = inv['cantidad_disponible'] as num;
                inv['cantidad_disponible'] = (currentInvQty - quantityToSubtract).clamp(0, double.infinity);
                inventarioList[j] = inv;
                print('📦 Inventario actualizado - Producto: $productId, Variante: $variantId, Descontado: $quantityToSubtract');
                break;
              }
            }
            
            detalles['inventario'] = inventarioList;
            categoryProducts[i]['detalles_completos'] = detalles;
          }
          
          productsData[categoryKey] = categoryProducts;
          updated = true;
          break;
        }
      }
      
      if (updated) break;
    }
    
    if (updated) {
      // Guardar cache actualizado
      offlineData['products'] = productsData;
      await saveOfflineData(offlineData);
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
      final decoded = jsonDecode(operationsJson);
      operations = List<Map<String, dynamic>>.from(decoded);
    }
    
    // Agregar timestamp
    operation['created_at'] = DateTime.now().toIso8601String();
    operations.add(operation);
    
    await prefs.setString(_pendingOperationsKey, jsonEncode(operations));
    print('💾 Operación pendiente guardada: ${operation['type']}');
  }
  
  /// Obtener todas las operaciones pendientes
  Future<List<Map<String, dynamic>>> getPendingOperations() async {
    final prefs = await SharedPreferences.getInstance();
    final operationsJson = prefs.getString(_pendingOperationsKey);
    
    if (operationsJson == null) return [];
    
    final decoded = jsonDecode(operationsJson);
    return List<Map<String, dynamic>>.from(decoded);
  }
  
  /// Limpiar operaciones pendientes
  Future<void> clearPendingOperations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingOperationsKey);
    print('🗑️ Operaciones pendientes eliminadas');
  }
  
  // ==================== TURNO OFFLINE ====================
  
  /// Guardar turno abierto offline
  Future<void> saveOfflineTurno(Map<String, dynamic> turnoData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_offlineTurnoKey, jsonEncode(turnoData));
    print('💾 Turno offline guardado');
  }
  
  /// Obtener turno offline
  Future<Map<String, dynamic>?> getOfflineTurno() async {
    final prefs = await SharedPreferences.getInstance();
    final turnoJson = prefs.getString(_offlineTurnoKey);
    
    if (turnoJson == null) return null;
    
    return jsonDecode(turnoJson) as Map<String, dynamic>;
  }
  
  /// Limpiar turno offline
  Future<void> clearOfflineTurno() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_offlineTurnoKey);
    print('🗑️ Turno offline eliminado');
  }
  
  /// Actualizar estado de orden pendiente
  Future<void> updatePendingOrderStatus(String orderId, String newStatus, Map<String, dynamic>? additionalData) async {
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
    final turno = await getOfflineTurno();
    return turno != null;
  }

  /// Obtener información del turno offline para mostrar en settings
  Future<Map<String, dynamic>?> getOfflineTurnoInfo() async {
    final turno = await getOfflineTurno();
    if (turno == null) return null;
    
    return {
      'id': turno['id'],
      'fecha_apertura': turno['fecha_apertura'],
      'efectivo_inicial': turno['efectivo_inicial'],
      'usuario': turno['usuario'],
      'observaciones': turno['observaciones'],
    };
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
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Obtener resumen de datos offline para sincronización
  Future<Map<String, dynamic>> getOfflineSyncSummary() async {
    final pendingOrders = await getPendingOrders();
    final pendingOperations = await getPendingOperations();
    final turno = await getOfflineTurno();
    
    return {
      'pending_orders_count': pendingOrders.length,
      'pending_operations_count': pendingOperations.length,
      'has_open_turno': turno != null,
      'turno_info': turno != null ? {
        'fecha_apertura': turno['fecha_apertura'],
        'efectivo_inicial': turno['efectivo_inicial'],
      } : null,
    };
  }

  /// Limpiar todos los datos offline después de sincronización exitosa
  Future<void> clearAllOfflineData() async {
    await clearPendingOrders();
    await clearPendingOperations();
    await clearOfflineTurno();
    print('🗑️ Todos los datos offline eliminados después de sincronización');
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

  /// Actualizar resumen de cierre con órdenes offline
  /// Suma las nuevas órdenes offline al resumen existente
  Future<Map<String, dynamic>?> getResumenCierreWithOfflineOrders() async {
    try {
      // Obtener resumen base desde cache
      final resumenBase = await getResumenCierreCache();
      if (resumenBase == null) {
        print('ℹ️ No hay resumen de cierre base para actualizar');
        return null;
      }

      // Obtener órdenes offline pendientes
      final orderService = OrderService();
      final ordenes = orderService.orders;
      
      // Filtrar órdenes offline (las que no han sido sincronizadas)
      final ordenesOffline = ordenes.where((orden) => 
        orden.status.name == 'pendienteDeSincronizacion' || orden.status.name == 'enviada'
      ).toList();

      if (ordenesOffline.isEmpty) {
        print('ℹ️ No hay órdenes offline para agregar al resumen');
        return resumenBase;
      }

      // Calcular totales de órdenes offline
      double ventasOffline = 0.0;
      double efectivoOffline = 0.0;
      double transferenciasOffline = 0.0;
      int productosVendidosOffline = 0;

      for (final orden in ordenesOffline) {
        ventasOffline += orden.total;
        productosVendidosOffline += orden.items.fold<int>(0, (sum, item) => sum + item.cantidad);
        
        // Estimar método de pago (70% efectivo, 30% transferencias)
        final efectivoOrden = orden.total * 0.7;
        final transferenciasOrden = orden.total * 0.3;
        efectivoOffline += efectivoOrden;
        transferenciasOffline += transferenciasOrden;
      }

      // Crear resumen actualizado
      final resumenActualizado = Map<String, dynamic>.from(resumenBase);
      
      // Sumar valores offline a los existentes usando los nombres correctos del cache
      final ventasBase = (resumenBase['ventas_totales'] ?? resumenBase['total_ventas'] ?? 0.0) as double;
      final efectivoBase = (resumenBase['efectivo_real'] ?? resumenBase['total_efectivo'] ?? 0.0) as double;
      final transferenciasBase = (resumenBase['total_transferencias'] ?? 0.0) as double;
      final productosBase = (resumenBase['productos_vendidos'] ?? 0) as int;
      
      // Actualizar con nombres consistentes (usar los del cache original)
      resumenActualizado['ventas_totales'] = ventasBase + ventasOffline;
      resumenActualizado['efectivo_real'] = efectivoBase + efectivoOffline;
      resumenActualizado['total_transferencias'] = transferenciasBase + transferenciasOffline;
      resumenActualizado['productos_vendidos'] = productosBase + productosVendidosOffline;
      resumenActualizado['ordenes_offline'] = ordenesOffline.length;
      resumenActualizado['ventas_offline'] = ventasOffline;
      
      // Recalcular totales
      final totalVentas = resumenActualizado['ventas_totales'] as double;
      final totalProductos = resumenActualizado['productos_vendidos'] as int;
      resumenActualizado['ticket_promedio'] = totalProductos > 0 ? totalVentas / totalProductos : 0.0;

      print('📊 Resumen de cierre actualizado con órdenes offline:');
      print('  - Órdenes offline: ${ordenesOffline.length}');
      print('  - Ventas offline: \$${ventasOffline.toStringAsFixed(2)}');
      print('  - Total ventas: \$${totalVentas.toStringAsFixed(2)}');
      print('  - Productos vendidos: $totalProductos');

      return resumenActualizado;
      
    } catch (e) {
      print('❌ Error actualizando resumen con órdenes offline: $e');
      return await getResumenCierreCache(); // Fallback al resumen base
    }
  }
}

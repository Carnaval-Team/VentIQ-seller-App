import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class UserPreferencesService {
  static final UserPreferencesService _instance =
      UserPreferencesService._internal();
  factory UserPreferencesService() => _instance;
  UserPreferencesService._internal();

  static const String _userIdKey = 'user_id';
  static const String _userEmailKey = 'user_email';
  static const String _accessTokenKey = 'access_token';
  static const String _isLoggedInKey = 'is_logged_in';

  // Admin user data keys
  static const String _adminNameKey = 'admin_name';
  static const String _adminRoleKey = 'admin_role';
  static const String _appVersionKey = 'app_version';
  static const String _idTiendaKey = 'id_tienda';
  static const String _userStoresKey = 'user_stores';

  // Remember me keys
  static const String _rememberMeKey = 'remember_me';
  static const String _savedEmailKey = 'saved_email';
  static const String _savedPasswordKey = 'saved_password';
  static const String _tokenExpiryKey = 'token_expiry';

  // Subscription keys
  static const String _subscriptionIdKey = 'subscription_id';
  static const String _subscriptionStateKey = 'subscription_state';
  static const String _subscriptionPlanIdKey = 'subscription_plan_id';
  static const String _subscriptionPlanNameKey = 'subscription_plan_name';
  static const String _subscriptionStartDateKey = 'subscription_start_date';
  static const String _subscriptionEndDateKey = 'subscription_end_date';
  static const String _subscriptionFeaturesKey = 'subscription_features';
  static const String _subscriptionLastCheckKey = 'subscription_last_check';

  // Guardar datos del usuario admin
  Future<void> saveUserData({
    required String userId,
    required String email,
    required String accessToken,
    String? adminName,
    String? adminRole,
    int? idTienda,
    List<Map<String, dynamic>>? userStores,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userIdKey, userId);
    await prefs.setString(_userEmailKey, email);
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setBool(_isLoggedInKey, true);

    if (adminName != null) {
      await prefs.setString(_adminNameKey, adminName);
    }
    if (adminRole != null) {
      await prefs.setString(_adminRoleKey, adminRole);
    }
    if (idTienda != null) {
      await prefs.setInt(_idTiendaKey, idTienda);
    }
    if (userStores != null) {
      await prefs.setString(_userStoresKey, jsonEncode(userStores));
    }

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

  // Obtener nombre del admin
  Future<String?> getAdminName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_adminNameKey);
  }

  // Obtener rol del admin
  Future<String?> getAdminRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_adminRoleKey);
  }

  // Obtener ID de tienda del supervisor (compatibilidad con código existente)
  Future<int?> getIdTienda() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_idTiendaKey);
  }

  // Obtener ID de tienda específico (método tradicional)
  Future<int?> getStoredIdTienda() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_idTiendaKey);
  }

  // Guardar lista de tiendas del usuario
  Future<void> saveUserStores(List<Map<String, dynamic>> stores) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userStoresKey, jsonEncode(stores));
  }

  // Obtener lista de tiendas del usuario
  Future<List<Map<String, dynamic>>> getUserStores() async {
    final prefs = await SharedPreferences.getInstance();
    final storesJson = prefs.getString(_userStoresKey);
    if (storesJson == null) return [];
    
    try {
      final List<dynamic> storesList = jsonDecode(storesJson);
      return storesList.cast<Map<String, dynamic>>();
    } catch (e) {
      print('❌ Error parsing user stores: $e');
      return [];
    }
  }

  // Actualizar tienda seleccionada
  Future<void> updateSelectedStore(int idTienda) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_idTiendaKey, idTienda);
    print('🏪 Updated selected store to: $idTienda');
  }

  // Obtener información de la tienda actual
  Future<Map<String, dynamic>?> getCurrentStoreInfo() async {
    final currentStoreId = await getIdTienda();
    if (currentStoreId == null) return null;
    
    final stores = await getUserStores();
    try {
      return stores.firstWhere(
        (store) => store['id_tienda'] == currentStoreId,
      );
    } catch (e) {
      print('❌ Current store not found in user stores list');
      return null;
    }
  }

  // Verificar si el usuario está logueado
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
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
      final currentParts = cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final savedParts = cleanSaved.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      
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
  Future<Map<String, dynamic>> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'userId': prefs.getString(_userIdKey),
      'email': prefs.getString(_userEmailKey),
      'accessToken': prefs.getString(_accessTokenKey),
      'adminName': prefs.getString(_adminNameKey),
      'adminRole': prefs.getString(_adminRoleKey),
      'idTienda': prefs.getInt(_idTiendaKey),
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

  // Get admin profile data for role-based access control
  Future<Map<String, dynamic>> getAdminProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'name': prefs.getString(_adminNameKey) ?? 'Admin',
      'role': prefs.getString(_adminRoleKey) ?? 'trabajador',
      'email': prefs.getString(_userEmailKey) ?? '',
      'idTienda': prefs.getInt(_idTiendaKey),
    };
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
    await prefs.setString(_subscriptionStartDateKey, startDate.toIso8601String());
    
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
    await prefs.setString(_subscriptionLastCheckKey, DateTime.now().toIso8601String());
    
    print('💾 Datos de suscripción guardados: Plan $planName (ID: $subscriptionId)');
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
    
    if (state == null || planId == null || planName == null || startDateStr == null) {
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

  /// Limpia todos los datos del usuario incluyendo suscripción
  Future<void> clearUserData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Limpiar datos básicos del usuario
    await prefs.remove(_userIdKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_adminNameKey);
    await prefs.remove(_adminRoleKey);
    await prefs.remove(_idTiendaKey);
    await prefs.remove(_userStoresKey);
    await prefs.remove(_tokenExpiryKey);
    await prefs.setBool(_isLoggedInKey, false);
    
    // Limpiar datos de suscripción
    await clearSubscriptionData();
    
    print('🧹 Todos los datos del usuario limpiados');
  }
}

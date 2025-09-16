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

  // Limpiar todos los datos del usuario (logout)
  Future<void> clearUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_adminNameKey);
    await prefs.remove(_adminRoleKey);
    await prefs.remove(_idTiendaKey);
    await prefs.remove(_userStoresKey);
    await prefs.setBool(_isLoggedInKey, false);
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
}

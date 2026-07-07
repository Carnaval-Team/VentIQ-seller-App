import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserPreferencesService {
  static final UserPreferencesService _instance = UserPreferencesService._internal();
  factory UserPreferencesService() => _instance;
  UserPreferencesService._internal();

  static const String _userIdKey = 'user_id';
  static const String _userEmailKey = 'user_email';
  static const String _accessTokenKey = 'access_token';
  static const String _isLoggedInKey = 'is_logged_in';
  static const String _tokenExpiryKey = 'token_expiry';

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
    final expiryTime = DateTime.now().add(Duration(hours: 24)).millisecondsSinceEpoch;
    await prefs.setInt(_tokenExpiryKey, expiryTime);
    
    print('✅ UserPreferencesService: Datos guardados para $email');
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

  // Verificar si el usuario está logueado
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
  }

  // Token validation
  Future<bool> isTokenValid() async {
    final prefs = await SharedPreferences.getInstance();
    final expiryTime = prefs.getInt(_tokenExpiryKey);
    if (expiryTime == null) return false;

    final now = DateTime.now().millisecondsSinceEpoch;
    return now < expiryTime;
  }

  // Verificar si hay sesión válida
  Future<bool> hasValidSession() async {
    final isLoggedIn = await this.isLoggedIn();
    final accessToken = await getAccessToken();

    if (!isLoggedIn || accessToken == null || accessToken.isEmpty) {
      return false;
    }

    // Si el token es de Supabase (JWT), verificar validez
    if (accessToken.startsWith('eyJ')) {
      return await isTokenValid();
    }

    // Para otros tipos de token, considerar válido si está logueado
    return true;
  }

  // Obtener usuario actual con fallback a SharedPreferences
  Future<User?> getCurrentUserWithFallback() async {
    try {
      // Primero intentar obtener de Supabase
      final supabaseUser = Supabase.instance.client.auth.currentUser;
      if (supabaseUser != null) {
        return supabaseUser;
      }

      // Fallback: intentar obtener de SharedPreferences y hacer getUser()
      final userId = await getUserId();
      if (userId != null) {
        final response = await Supabase.instance.client.auth.getUser();
        return response.user;
      }

      return null;
    } catch (e) {
      print('❌ Error obteniendo usuario con fallback: $e');
      return null;
    }
  }

  // Obtener UUID del usuario con múltiples fallbacks
  Future<String?> getCurrentUserId() async {
    try {
      // 1. Intentar de Supabase directo
      final supabaseUser = Supabase.instance.client.auth.currentUser;
      if (supabaseUser?.id != null) {
        return supabaseUser!.id;
      }

      // 2. Intentar getUser() de Supabase
      final response = await Supabase.instance.client.auth.getUser();
      if (response.user?.id != null) {
        return response.user!.id;
      }

      // 3. Fallback a SharedPreferences
      final cachedUserId = await getUserId();
      if (cachedUserId != null) {
        return cachedUserId;
      }

      return null;
    } catch (e) {
      print('❌ Error obteniendo UUID del usuario: $e');
      // Último recurso: intentar de SharedPreferences
      return await getUserId();
    }
  }

  // Sincronizar estado con Supabase Auth
  Future<void> syncWithSupabaseAuth() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final session = Supabase.instance.client.auth.currentSession;
      if (user != null && session != null) {
        await saveUserData(
          userId: user.id,
          email: user.email ?? '',
          accessToken: session.accessToken,
        );
        print('✅ UserPreferencesService: Sincronizado con Supabase Auth');
      } else {
        await clearUserData();
        print('✅ UserPreferencesService: Limpiado datos (no hay sesión en Supabase)');
      }
    } catch (e) {
      print('❌ Error sincronizando con Supabase Auth: $e');
    }
  }

  // Limpiar todos los datos del usuario (logout)
  Future<void> clearUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_tokenExpiryKey);
    await prefs.setBool(_isLoggedInKey, false);
    
    print('✅ UserPreferencesService: Datos limpiados');
  }

  // Obtener todos los datos del usuario
  Future<Map<String, dynamic?>> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'userId': prefs.getString(_userIdKey),
      'email': prefs.getString(_userEmailKey),
      'accessToken': prefs.getString(_accessTokenKey),
      'isLoggedIn': prefs.getBool(_isLoggedInKey),
      'tokenExpiry': prefs.getInt(_tokenExpiryKey),
    };
  }

  // Verificar si hay datos cacheados
  Future<bool> hasCachedData() async {
    final userId = await getUserId();
    final email = await getUserEmail();
    return (userId != null && userId.isNotEmpty) && 
           (email != null && email.isNotEmpty);
  }

  // Forzar refresh del token desde Supabase
  Future<bool> refreshSession() async {
    try {
      final response = await Supabase.instance.client.auth.refreshSession();
      if (response.session != null) {
        await saveUserData(
          userId: response.session!.user.id,
          email: response.session!.user.email ?? '',
          accessToken: response.session!.accessToken,
        );
        print('✅ UserPreferencesService: Sesión refrescada');
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error refrescando sesión: $e');
      return false;
    }
  }
}

import 'package:shared_preferences/shared_preferences.dart';

class UserPreferencesService {
  static final UserPreferencesService _instance = UserPreferencesService._internal();
  factory UserPreferencesService() => _instance;
  UserPreferencesService._internal();

  static const String _userIdKey = 'user_id';
  static const String _userEmailKey = 'user_email';
  static const String _accessTokenKey = 'access_token';
  static const String _isLoggedInKey = 'is_logged_in';
  
  // Seller data keys
  static const String _idTpvKey = 'id_tpv';
  static const String _idTrabajadorKey = 'id_trabajador';
  static const String _nombresKey = 'nombres';
  static const String _apellidosKey = 'apellidos';
  static const String _idTiendaKey = 'id_tienda';
  static const String _idRollKey = 'id_roll';

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

  // Obtener ID TPV (tienda)
  Future<int?> getIdTpv() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_idTpvKey);
  }

  // Obtener datos del perfil del trabajador
  Future<Map<String, dynamic?>> getWorkerProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'nombres': prefs.getString(_nombresKey),
      'apellidos': prefs.getString(_apellidosKey),
      'idTienda': prefs.getInt(_idTiendaKey),
      'idRoll': prefs.getInt(_idRollKey),
      'idTrabajador': prefs.getInt(_idTrabajadorKey),
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
    await prefs.remove(_nombresKey);
    await prefs.remove(_apellidosKey);
    await prefs.remove(_idTiendaKey);
    await prefs.remove(_idRollKey);
    await prefs.setBool(_isLoggedInKey, false);
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
}

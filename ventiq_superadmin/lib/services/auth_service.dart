import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _isLoggedInKey = 'is_logged_in';
  static const String _userIdKey = 'user_id';
  static const String _userEmailKey = 'user_email';
  static const String _userNameKey = 'user_name';
  static const String _userRoleKey = 'user_role';

  // Simulación de login - En producción conectar con Supabase
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      // Simular delay de red
      await Future.delayed(const Duration(seconds: 2));

      // Credenciales de prueba
      if (email == 'admin@ventiq.com' && password == 'admin123') {
        await _saveUserData(
          userId: 'super-admin-1',
          email: email,
          name: 'Super Administrador',
          role: 'super_admin',
        );

        return {
          'success': true,
          'message': 'Login exitoso',
          'user': {
            'id': 'super-admin-1',
            'email': email,
            'name': 'Super Administrador',
            'role': 'super_admin',
          }
        };
      } else {
        return {
          'success': false,
          'message': 'Credenciales incorrectas',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error de conexión: ${e.toString()}',
      };
    }
  }

  Future<void> _saveUserData({
    required String userId,
    required String email,
    required String name,
    required String role,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isLoggedInKey, true);
    await prefs.setString(_userIdKey, userId);
    await prefs.setString(_userEmailKey, email);
    await prefs.setString(_userNameKey, name);
    await prefs.setString(_userRoleKey, role);
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
  }

  Future<Map<String, String?>> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'id': prefs.getString(_userIdKey),
      'email': prefs.getString(_userEmailKey),
      'name': prefs.getString(_userNameKey),
      'role': prefs.getString(_userRoleKey),
    };
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_isLoggedInKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_userNameKey);
    await prefs.remove(_userRoleKey);
  }

  Future<bool> changePassword(String currentPassword, String newPassword) async {
    try {
      // Simular delay de red
      await Future.delayed(const Duration(seconds: 1));
      
      // En producción, validar contraseña actual y actualizar en Supabase
      if (currentPassword == 'admin123') {
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }
}

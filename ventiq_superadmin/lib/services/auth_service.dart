import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/superadmin.dart';
import '../config/app_routes.dart';

class AuthService {
  static const String _isLoggedInKey = 'is_logged_in';
  static const String _userIdKey = 'user_id';
  static const String _userEmailKey = 'user_email';
  static const String _userNameKey = 'user_name';
  static const String _userRoleKey = 'user_role';
  static const String _userUuidKey = 'user_uuid';
  static const String _userNivelAccesoKey = 'user_nivel_acceso';
  static const String _userRoleIdKey = 'user_role_id';
  static const String _userRolePermissionsKey = 'user_role_permissions';
  
  static final _supabase = Supabase.instance.client;
  static SuperAdmin? _currentSuperAdmin;
  
  static SuperAdmin? get currentSuperAdmin => _currentSuperAdmin;

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      debugPrint('🔐 Iniciando login para: $email');
      
      // Autenticar con Supabase
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        return {
          'success': false,
          'message': 'Credenciales inválidas',
        };
      }

      final user = response.user!;
      debugPrint('✅ Usuario autenticado: ${user.id}');

      // Verificar si es superadmin y cargar rol con permisos
      final superadminResponse = await _supabase
          .from('app_dat_superadmin')
          .select('*, app_dat_superadmin_roles(*)')
          .eq('uuid', user.id)
          .eq('activo', true)
          .maybeSingle();

      if (superadminResponse == null) {
        debugPrint('❌ Usuario no es superadministrador');
        await _supabase.auth.signOut();
        return {
          'success': false,
          'message': 'No tienes permisos de superadministrador',
        };
      }

      debugPrint('✅ Superadmin verificado: ${superadminResponse['nombre']} ${superadminResponse['apellidos']}');
      
      // Crear objeto SuperAdmin
      _currentSuperAdmin = SuperAdmin.fromJson(superadminResponse);

      // Actualizar último acceso
      await _supabase
          .from('app_dat_superadmin')
          .update({'ultimo_acceso': DateTime.now().toIso8601String()})
          .eq('id', _currentSuperAdmin!.id);

      // Guardar en SharedPreferences
      await _saveUserData(
        userId: _currentSuperAdmin!.id.toString(),
        uuid: _currentSuperAdmin!.uuid,
        email: _currentSuperAdmin!.email,
        name: _currentSuperAdmin!.nombreCompleto,
        role: 'super_admin',
        nivelAcceso: _currentSuperAdmin!.nivelAcceso,
        roleId: _currentSuperAdmin!.idRol,
        rolePermissions: _currentSuperAdmin!.permisosRutas,
      );

      debugPrint('✅ Login exitoso - Nivel de acceso: ${_currentSuperAdmin!.nivelAccesoTexto}');

      return {
        'success': true,
        'message': 'Login exitoso',
        'user': {
          'id': _currentSuperAdmin!.id.toString(),
          'email': _currentSuperAdmin!.email,
          'name': _currentSuperAdmin!.nombreCompleto,
          'role': 'super_admin',
          'nivel_acceso': _currentSuperAdmin!.nivelAcceso,
        }
      };
    } catch (e) {
      debugPrint('❌ Error en login: $e');
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
      };
    }
  }

  Future<void> _saveUserData({
    required String userId,
    required String uuid,
    required String email,
    required String name,
    required String role,
    required int nivelAcceso,
    int? roleId,
    List<String> rolePermissions = const [],
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isLoggedInKey, true);
    await prefs.setString(_userIdKey, userId);
    await prefs.setString(_userUuidKey, uuid);
    await prefs.setString(_userEmailKey, email);
    await prefs.setString(_userNameKey, name);
    await prefs.setString(_userRoleKey, role);
    await prefs.setInt(_userNivelAccesoKey, nivelAcceso);
    if (roleId != null) {
      await prefs.setInt(_userRoleIdKey, roleId);
    } else {
      await prefs.remove(_userRoleIdKey);
    }
    await prefs.setStringList(_userRolePermissionsKey, rolePermissions);
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool(_isLoggedInKey) ?? false;
    
    if (isLoggedIn && _currentSuperAdmin == null) {
      // Intentar recuperar datos del superadmin
      await checkAuthStatus();
    }
    
    return isLoggedIn && _currentSuperAdmin != null;
  }

  Future<Map<String, dynamic>> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'id': prefs.getString(_userIdKey),
      'uuid': prefs.getString(_userUuidKey),
      'email': prefs.getString(_userEmailKey),
      'name': prefs.getString(_userNameKey),
      'role': prefs.getString(_userRoleKey),
      'nivel_acceso': prefs.getInt(_userNivelAccesoKey),
      'id_rol': prefs.getInt(_userRoleIdKey),
      'permisos_rutas': prefs.getStringList(_userRolePermissionsKey) ?? [],
    };
  }

  Future<void> logout() async {
    try {
      debugPrint('🔐 Cerrando sesión...');

      // Limpiar SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_isLoggedInKey);
      await prefs.remove(_userIdKey);
      await prefs.remove(_userUuidKey);
      await prefs.remove(_userEmailKey);
      await prefs.remove(_userNameKey);
      await prefs.remove(_userRoleKey);
      await prefs.remove(_userNivelAccesoKey);
      await prefs.remove(_userRoleIdKey);
      await prefs.remove(_userRolePermissionsKey);

      // Cerrar sesión en Supabase
      await _supabase.auth.signOut();

      debugPrint('✅ Sesión cerrada exitosamente');
    } catch (e) {
      debugPrint('❌ Error al cerrar sesión: $e');
    } finally {
      // Siempre limpiar datos en memoria
      _currentSuperAdmin = null;
    }
  }

  Future<bool> changePassword(String currentPassword, String newPassword) async {
    try {
      // Actualizar contraseña en Supabase
      await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      return true;
    } catch (e) {
      debugPrint('❌ Error al cambiar contraseña: $e');
      return false;
    }
  }
  
  Future<bool> checkAuthStatus() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      // Verificar si tenemos datos del superadmin en memoria
      if (_currentSuperAdmin != null) return true;

      // Intentar recuperar de la base de datos
      final superadminResponse = await _supabase
          .from('app_dat_superadmin')
          .select('*, app_dat_superadmin_roles(*)')
          .eq('uuid', user.id)
          .eq('activo', true)
          .maybeSingle();

      if (superadminResponse != null) {
        _currentSuperAdmin = SuperAdmin.fromJson(superadminResponse);
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('❌ Error verificando estado de autenticación: $e');
      return false;
    }
  }
  
  static bool hasFullAccess() {
    return _currentSuperAdmin?.nivelAcceso == 1;
  }

  static bool canWrite() {
    return _currentSuperAdmin != null && _currentSuperAdmin!.nivelAcceso <= 2;
  }

  static bool canRead() {
    return _currentSuperAdmin != null && _currentSuperAdmin!.nivelAcceso <= 3;
  }

  /// Determina si el superadmin actual puede acceder a una ruta protegida.
  /// Las rutas publicas (/, /login, /dashboard) siempre estan permitidas.
  /// Si no tiene rol asignado y su nivel es 1, tiene acceso total legacy.
  static bool canAccessRoute(String route) {
    if (AppRoutes.alwaysAllowed.contains(route)) return true;

    final admin = _currentSuperAdmin;
    if (admin == null) return false;

    // Legacy fallback: acceso total
    if (admin.rol == null && admin.nivelAcceso == 1) return true;

    final permisos = admin.permisosRutas;
    if (permisos.isEmpty && admin.nivelAcceso == 1) return true;

    return permisos.contains(route);
  }
}

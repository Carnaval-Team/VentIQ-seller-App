import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/perfil.dart';
import '../services/auth_service.dart';
import '../services/perfil_service.dart';
import '../services/user_preferences_service.dart';

class AuthProvider extends ChangeNotifier {
  User? _user;
  Perfil? _perfil;
  bool _isLoading = false;
  String? _error;
  bool _perfilLoaded = false;
  bool _perfilLoading = false;
  final UserPreferencesService _prefsService = UserPreferencesService();

  User? get user => _user;
  Perfil? get perfil => _perfil;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _user != null;
  bool get hasPerfil => _perfil != null;
  bool get perfilLoaded => _perfilLoaded;

  AuthProvider() {
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    // Primero obtener usuario de Supabase (síncrono, sin red)
    _user = AuthService.currentUser;

    // Escuchar cambios de autenticación
    String? _lastUserId;
    AuthService.authStateChanges.listen((state) {
      final newUser = state.session?.user;
      _user = newUser;
      if (newUser != null) {
        // Solo recargar perfil si el usuario cambió
        if (newUser.id != _lastUserId) {
          _lastUserId = newUser.id;
          _perfilLoaded = false;
          _loadPerfil();
        }
        _prefsService.syncWithSupabaseAuth();
      } else {
        _lastUserId = null;
        _perfil = null;
        _perfilLoaded = false;
        _perfilLoading = false;
        _prefsService.clearUserData();
      }
      notifyListeners();
    });

    // Si ya hay sesión activa al arrancar, cargar perfil una sola vez
    if (_user != null) {
      _loadPerfil();
      await _prefsService.syncWithSupabaseAuth();
    }
  }

  Future<void> _loadPerfil() async {
    if (_user == null || _perfilLoading) return;
    _perfilLoading = true;
    print('[flow] _loadPerfil → uuid: ${_user!.id}');
    try {
      _perfil = await PerfilService.getPerfil(_user!.id);
      print('[flow] _loadPerfil → perfil cargado: ${_perfil?.nombreCompleto}');
    } catch (e, st) {
      print('[flow] _loadPerfil ERROR: $e\n$st');
    } finally {
      _perfilLoaded = true;
      _perfilLoading = false;
      notifyListeners();
    }
  }

  Future<bool> signIn(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    print('[flow] signIn → $email');
    try {
      final response = await AuthService.signIn(email: email, password: password);
      print('[flow] signIn → OK');
      
      // Guardar en SharedPreferences después del login exitoso
      if (response.user != null && response.session != null) {
        await _prefsService.saveUserData(
          userId: response.user!.id,
          email: response.user!.email ?? email,
          accessToken: response.session!.accessToken,
        );
      }
      
      // _loadPerfil es disparado por authStateChanges; esperar a que termine
      int wait = 0;
      while (!_perfilLoaded && wait < 30) {
        await Future.delayed(const Duration(milliseconds: 100));
        wait++;
      }
      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      print('[flow] signIn AuthException → ${e.message} (status: ${e.statusCode})');
      _error = _parseAuthError(e.message);
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e, st) {
      print('[flow] signIn ERROR: $e\n$st');
      _error = _parseError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> signUp(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    print('[flow] signUp → $email');
    try {
      await AuthService.signUp(email: email, password: password);
      print('[flow] signUp → OK');
      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      print('[flow] signUp AuthException → ${e.message} (status: ${e.statusCode})');
      _error = _parseAuthError(e.message);
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e, st) {
      print('[flow] signUp ERROR: $e\n$st');
      _error = _parseError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  static String _parseAuthError(String msg) {
    final raw = msg.toLowerCase();
    if (raw.contains('invalid login') || raw.contains('invalid credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (raw.contains('email not confirmed')) {
      return 'Debes confirmar tu correo antes de iniciar sesión.';
    }
    if (raw.contains('user already registered') || raw.contains('already been registered')) {
      return 'Este correo ya está registrado. Intenta iniciar sesión.';
    }
    if (raw.contains('password should be')) {
      return 'La contraseña debe tener al menos 6 caracteres.';
    }
    if (raw.contains('rate limit') || raw.contains('too many')) {
      return 'Demasiados intentos. Espera unos minutos e intenta nuevamente.';
    }
    return 'Error de autenticación: $msg';
  }

  Future<void> signOut() async {
    await AuthService.signOut();
    _perfil = null;
    // Limpiar preferencias locales
    await _prefsService.clearUserData();
    notifyListeners();
  }

  Future<bool> savePerfil({
    required String nombre,
    required String apellidos,
    required String ci,
    String? telefono,
  }) async {
    if (_user == null) return false;
    _isLoading = true;
    _error = null;
    notifyListeners();
    final action = _perfil == null ? 'create' : 'update';
    // En actualización, el CI no cambia: se conserva el del perfil existente
    final ciFinal = _perfil?.ci ?? ci;
    print('[flow] savePerfil → $action | ci: $ciFinal | uuid: ${_user!.id}');
    try {
      if (_perfil == null) {
        _perfil = await PerfilService.createPerfil(
          uuidUsuario: _user!.id,
          nombre: nombre,
          apellidos: apellidos,
          ci: ciFinal,
          telefono: telefono,
        );
      } else {
        _perfil = await PerfilService.updatePerfil(
          uuidUsuario: _user!.id,
          nombre: nombre,
          apellidos: apellidos,
          ci: ciFinal,
          telefono: telefono,
        );
      }
      print('[flow] savePerfil → OK | id: ${_perfil?.id}');
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e, st) {
      print('[flow] savePerfil ERROR ($action): $e\n$st');
      _error = _parseError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  static String _parseError(Object e) {
    print('[flow] _parseError → raw: $e');
    final raw = e.toString().toLowerCase();
    if (raw.contains('pgrst106') || raw.contains('schema must be') || raw.contains('not acceptable')) {
      return 'Error de configuración del servidor. Contacta al administrador.';
    }
    if (raw.contains('duplicate') || raw.contains('unique') || raw.contains('23505')) {
      if (raw.contains('ci')) {
        return 'Este carnet de identidad ya está registrado por otro usuario.';
      }
      return 'Ya existe un registro con estos datos.';
    }
    if (raw.contains('violates') || raw.contains('constraint')) {
      return 'Los datos ingresados no son válidos. Verifica el formulario.';
    }
    if (raw.contains('network') || raw.contains('socketexception') || raw.contains('connection')) {
      return 'Sin conexión a internet. Verifica tu red e intenta nuevamente.';
    }
    if (raw.contains('permission') || raw.contains('rls') || raw.contains('row-level')) {
      return 'No tienes permiso para realizar esta acción.';
    }
    if (raw.contains('jwt') || raw.contains('token') || raw.contains('session')) {
      return 'Tu sesión expiró. Vuelve a iniciar sesión.';
    }
    return 'Error inesperado: $e';
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Métodos adicionales para compatibilidad con ventiq_app

  /// Obtener UUID del usuario con múltiples fallbacks
  Future<String?> getCurrentUserId() async {
    return await _prefsService.getCurrentUserId();
  }

  /// Verificar si hay sesión válida (incluyendo offline)
  Future<bool> hasValidSession() async {
    return await _prefsService.hasValidSession();
  }

  /// Forzar refresh de sesión
  Future<bool> refreshSession() async {
    return await _prefsService.refreshSession();
  }

  /// Obtener usuario actual con fallback a preferencias
  Future<User?> getCurrentUserWithFallback() async {
    return await _prefsService.getCurrentUserWithFallback();
  }

  /// Verificar si hay datos cacheados
  Future<bool> hasCachedData() async {
    return await _prefsService.hasCachedData();
  }
}

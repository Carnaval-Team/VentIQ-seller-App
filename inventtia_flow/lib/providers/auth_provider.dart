import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/perfil.dart';
import '../services/auth_service.dart';
import '../services/perfil_service.dart';

class AuthProvider extends ChangeNotifier {
  User? _user;
  Perfil? _perfil;
  bool _isLoading = false;
  String? _error;
  bool _perfilLoaded = false;

  User? get user => _user;
  Perfil? get perfil => _perfil;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _user != null;
  bool get hasPerfil => _perfil != null;
  bool get perfilLoaded => _perfilLoaded;

  AuthProvider() {
    _user = AuthService.currentUser;
    AuthService.authStateChanges.listen((state) {
      _user = state.session?.user;
      if (_user != null) {
        _perfilLoaded = false;
        _loadPerfil();
      } else {
        _perfil = null;
        _perfilLoaded = false;
      }
      notifyListeners();
    });
    if (_user != null) _loadPerfil();
  }

  Future<void> _loadPerfil() async {
    if (_user == null) return;
    print('[flow] _loadPerfil → uuid: ${_user!.id}');
    try {
      _perfil = await PerfilService.getPerfil(_user!.id);
      print('[flow] _loadPerfil → perfil cargado: ${_perfil?.nombreCompleto}');
    } catch (e, st) {
      print('[flow] _loadPerfil ERROR: $e\n$st');
    } finally {
      _perfilLoaded = true;
      notifyListeners();
    }
  }

  Future<bool> signIn(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    print('[flow] signIn → $email');
    try {
      await AuthService.signIn(email: email, password: password);
      print('[flow] signIn → OK');
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
    return 'Error de autenticación. Verifica tus datos e intenta nuevamente.';
  }

  Future<void> signOut() async {
    await AuthService.signOut();
    _perfil = null;
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
    return 'Ocurrió un error inesperado. Intenta nuevamente.';
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

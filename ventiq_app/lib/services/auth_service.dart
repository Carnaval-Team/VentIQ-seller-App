import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'subscription_guard_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  SupabaseClient get client => Supabase.instance.client;

  // Inicializar Supabase
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
    );
  }

  // Obtener usuario actual
  User? get currentUser => client.auth.currentUser;

  // Verificar si el usuario está autenticado
  bool get isAuthenticated => currentUser != null;

  // Stream de cambios de autenticación
  Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  // Login con email y password
  Future<AuthResponse> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  // Registro con email y password
  Future<AuthResponse> signUpWithEmailAndPassword({
    required String email,
    required String password,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final response = await client.auth.signUp(
        email: email,
        password: password,
        data: metadata,
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  // Cerrar sesión
  Future<void> signOut() async {
    try {
      await client.auth.signOut();
      // Limpiar caché de suscripción
      await SubscriptionGuardService().clearCache();
      print('👋 Usuario cerró sesión exitosamente');
    } catch (e) {
      print('❌ Error al cerrar sesión: $e');
      rethrow;
    }
  }

  // Resetear password
  Future<void> resetPassword(String email) async {
    try {
      await client.auth.resetPasswordForEmail(email);
    } catch (e) {
      rethrow;
    }
  }

  // Obtener información del usuario
  Future<User?> getUserProfile() async {
    try {
      return currentUser;
    } catch (e) {
      return null;
    }
  }

  // Actualizar perfil del usuario
  Future<UserResponse> updateUserProfile({
    String? email,
    String? password,
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await client.auth.updateUser(
        UserAttributes(
          email: email,
          password: password,
          data: data,
        ),
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }
}

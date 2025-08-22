import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  // Sign in with email and password
  Future<AuthResponse> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      
      print('🔐 Admin login attempt for: $email');
      print('✅ Login successful: ${response.user?.id}');
      
      return response;
    } catch (e) {
      print('❌ Admin login error: $e');
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
      print('👋 Admin signed out successfully');
    } catch (e) {
      print('❌ Admin sign out error: $e');
      rethrow;
    }
  }

  // Get current user
  User? get currentUser => _supabase.auth.currentUser;

  // Get current session
  Session? get currentSession => _supabase.auth.currentSession;

  // Check if user is signed in
  bool get isSignedIn => currentUser != null;

  // Listen to auth state changes
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  // Verify admin permissions (placeholder for future implementation)
  Future<bool> verifyAdminPermissions(String userId) async {
    try {
      // TODO: Implement admin verification logic with Supabase
      // This could check a specific admin table or user roles
      print('🔍 Verifying admin permissions for user: $userId');
      
      // For now, return true - implement actual verification later
      return true;
    } catch (e) {
      print('❌ Admin verification error: $e');
      return false;
    }
  }

  // Get admin profile (placeholder for future implementation)
  Future<Map<String, dynamic>?> getAdminProfile(String userId) async {
    try {
      // TODO: Implement admin profile fetching from Supabase
      print('👤 Fetching admin profile for user: $userId');
      
      // Return mock data for now - implement actual fetching later
      return {
        'name': 'Administrador',
        'role': 'Super Admin',
        'permissions': ['all'],
      };
    } catch (e) {
      print('❌ Admin profile fetch error: $e');
      return null;
    }
  }
}

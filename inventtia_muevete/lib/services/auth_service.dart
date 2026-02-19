import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Sign in with email and password.
  Future<AuthResponse> signInWithEmail(String email, String password) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return response;
  }

  /// Sign up with email and password, optionally providing a display name.
  Future<AuthResponse> signUpWithEmail(
    String email,
    String password, {
    String? name,
  }) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: name != null ? {'name': name} : null,
    );
    return response;
  }

  /// Sign out the current user.
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  /// Returns the currently authenticated user, or null if not signed in.
  User? get currentUser => _supabase.auth.currentUser;

  /// Returns true if a user is currently authenticated.
  bool get isAuthenticated => _supabase.auth.currentUser != null;

  /// Fetches the user profile from the muevete.users table.
  Future<Map<String, dynamic>?> getUserProfile() async {
    final user = currentUser;
    if (user == null) return null;

    final response = await _supabase
        .schema('muevete')
        .from('users')
        .select()
        .eq('uuid', user.id)
        .maybeSingle();

    return response;
  }

  /// Fetches the driver profile from the muevete.drivers table.
  Future<Map<String, dynamic>?> getDriverProfile() async {
    final user = currentUser;
    if (user == null) return null;

    final response = await _supabase
        .schema('muevete')
        .from('drivers')
        .select()
        .eq('uuid', user.id)
        .maybeSingle();

    return response;
  }

  /// Updates the user profile in the muevete.users table.
  Future<void> updateUserProfile(Map<String, dynamic> data) async {
    final user = currentUser;
    if (user == null) throw Exception('No authenticated user');

    await _supabase
        .schema('muevete')
        .from('users')
        .update(data)
        .eq('uuid', user.id);
  }

  /// Checks if the current authenticated user has a record in muevete.drivers.
  Future<bool> isDriver() async {
    final user = currentUser;
    if (user == null) return false;

    final response = await _supabase
        .schema('muevete')
        .from('drivers')
        .select('id')
        .eq('uuid', user.id)
        .maybeSingle();

    return response != null;
  }

  /// Checks if the current authenticated user has a record in muevete.users.
  Future<bool> isClient() async {
    final user = currentUser;
    if (user == null) return false;

    final response = await _supabase
        .schema('muevete')
        .from('users')
        .select('user_id')
        .eq('uuid', user.id)
        .maybeSingle();

    return response != null;
  }

  /// Creates a new user profile in muevete.users.
  Future<void> createUserProfile(Map<String, dynamic> data) async {
    await _supabase.schema('muevete').from('users').insert(data);
  }

  /// Creates a new driver profile in muevete.drivers.
  Future<void> createDriverProfile(Map<String, dynamic> data) async {
    await _supabase.schema('muevete').from('drivers').insert(data);
  }

  /// Updates the driver profile in the muevete.drivers table.
  Future<void> updateDriverProfile(Map<String, dynamic> data) async {
    final user = currentUser;
    if (user == null) throw Exception('No authenticated user');

    await _supabase
        .schema('muevete')
        .from('drivers')
        .update(data)
        .eq('uuid', user.id);
  }
}

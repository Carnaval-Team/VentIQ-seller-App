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

    // Single join: drivers -> vehiculos -> vehicle_type (no N+1)
    final response = await _supabase
        .schema('muevete')
        .from('drivers')
        .select('''
          *,
          vehiculos (
            id,
            marca,
            modelo,
            chapa,
            color,
            categoria,
            capacidad,
            descripcion,
            id_tipo_vehiculo,
            vehicle_type:vehicle_type ( id, tipo, precio_km_default )
          )
        ''')
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

  /// Returns the tipo_usuario string for the current user.
  /// Checks drivers table first (faster for the driver majority),
  /// then users table. Returns null if unauthenticated.
  Future<String?> getTipoUsuario() async {
    final user = currentUser;
    if (user == null) return null;

    // Check drivers table first
    final driverRow = await _supabase
        .schema('muevete')
        .from('drivers')
        .select('tipo_usuario')
        .eq('uuid', user.id)
        .maybeSingle();

    if (driverRow != null) {
      return (driverRow['tipo_usuario'] as String?) ?? 'conductor_pasajeros';
    }

    // Check users table
    final userRow = await _supabase
        .schema('muevete')
        .from('users')
        .select('tipo_usuario')
        .eq('uuid', user.id)
        .maybeSingle();

    if (userRow != null) {
      return (userRow['tipo_usuario'] as String?) ?? 'cliente_pasajero';
    }

    return null;
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

  /// Inserts a row into muevete.vehiculos and returns the new vehicle id.
  Future<int?> createVehicle(Map<String, dynamic> data) async {
    final row = await _supabase
        .schema('muevete')
        .from('vehiculos')
        .insert(data)
        .select('id')
        .single();
    return row['id'] as int?;
  }

  /// Updates the `vehiculo` FK on the driver row so it points to [vehicleId].
  Future<void> linkVehicleToDriver(int vehicleId) async {
    final user = currentUser;
    if (user == null) throw Exception('No authenticated user');
    await _supabase
        .schema('muevete')
        .from('drivers')
        .update({'vehiculo': vehicleId})
        .eq('uuid', user.id);
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

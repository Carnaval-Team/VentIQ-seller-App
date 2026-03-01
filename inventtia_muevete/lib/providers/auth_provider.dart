import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/background_service.dart';
import '../utils/battery_optimizer.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  User? _user;
  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? _driverProfile;
  String? _role; // 'client' or 'driver'
  bool _isLoading = false;
  String? _error;

  User? get user => _user;
  Map<String, dynamic>? get userProfile => _userProfile;
  Map<String, dynamic>? get driverProfile => _driverProfile;
  String? get role => _role;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;
  bool get isClient => _role == 'client';
  bool get isDriver => _role == 'driver';

  AuthProvider() {
    _user = _authService.currentUser;
    if (_user != null) {
      _loadProfile();
    }
  }

  Future<void> _loadProfile() async {
    try {
      final isDriverUser = await _authService.isDriver();
      if (isDriverUser) {
        _role = 'driver';
        _driverProfile = await _authService.getDriverProfile();
      } else {
        _role = 'client';
        _userProfile = await _authService.getUserProfile();
      }
      // Subscribe to in-app notifications
      if (_user != null) {
        NotificationService().subscribe(_user!.id);
        // Start background service only if location permission is already granted.
        // On Android 14+ (SDK 34), foreground services with type "location"
        // require the runtime location permission BEFORE starting.
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse) {
          // Quick attempt; driver_home_screen will do full retries later
          BackgroundService.start(
            userUuid: _user!.id,
            role: _role ?? 'client',
            driverId: _driverProfile?['id'] as int?,
            maxRetries: 1,
          );
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  /// Try to start the background service. Call this after location permission
  /// has been granted (Android 14+ requires it before starting FGS location).
  /// Returns true if started successfully, false if failed after retries.
  Future<bool> ensureBackgroundServiceStarted() async {
    if (_user == null || kIsWeb) return true;

    // Request "Allow all the time" for reliable background GPS
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.whileInUse) {
      await Geolocator.requestPermission(); // prompts for "always"
    }

    // Request disable battery optimization (Samsung, Xiaomi, etc. kill bg services)
    await BatteryOptimizer.requestDisable();

    return BackgroundService.start(
      userUuid: _user!.id,
      role: _role ?? 'client',
      driverId: _driverProfile?['id'] as int?,
    );
  }

  Future<bool> signIn(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _authService.signInWithEmail(email, password);
      _user = response.user;
      if (_user != null) {
        await _loadProfile();
      }
      _isLoading = false;
      notifyListeners();
      return _user != null;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> signUp(
    String email,
    String password, {
    required String name,
    required String role,
    String? phone,
    String? pais,
    String? province,
    String? municipality,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _authService.signUpWithEmail(
        email,
        password,
        name: name,
      );
      _user = response.user;
      _role = role;

      if (_user != null) {
        if (role == 'driver') {
          await _authService.createDriverProfile({
            'name': name,
            'email': email,
            'uuid': _user!.id,
            'estado': false,
            if (phone != null && phone.isNotEmpty) 'telefono': phone,
          });
        } else {
          await _authService.createUserProfile({
            'name': name,
            'email': email,
            'uuid': _user!.id,
            if (phone != null && phone.isNotEmpty) 'phone': phone,
            if (pais != null && pais.isNotEmpty) 'pais': pais,
            if (province != null && province.isNotEmpty) 'province': province,
            if (municipality != null && municipality.isNotEmpty)
              'municipality': municipality,
          });
        }
        await _loadProfile();
      }

      _isLoading = false;
      notifyListeners();
      return _user != null;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    await BackgroundService.stop();
    await NotificationService().unsubscribe();
    await _authService.signOut();
    _user = null;
    _userProfile = null;
    _driverProfile = null;
    _role = null;
    notifyListeners();
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    try {
      if (isDriver) {
        await _authService.updateDriverProfile(data);
        _driverProfile = await _authService.getDriverProfile();
      } else {
        await _authService.updateUserProfile(data);
        _userProfile = await _authService.getUserProfile();
      }
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Reloads the driver profile (e.g. after creating a vehicle).
  Future<void> refreshDriverProfile() async {
    _driverProfile = await _authService.getDriverProfile();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

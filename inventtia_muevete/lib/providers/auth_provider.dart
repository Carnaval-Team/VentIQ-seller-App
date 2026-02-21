import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

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
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
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
          });
        } else {
          await _authService.createUserProfile({
            'name': name,
            'email': email,
            'uuid': _user!.id,
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

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../services/location_service.dart';
import '../utils/constants.dart';

class LocationProvider extends ChangeNotifier {
  final LocationService _locationService = LocationService();

  LatLng? _currentLocation;
  bool _isTracking = false;
  bool _hasPermission = false;
  bool _isLoading = false;
  String? _error;
  StreamSubscription? _positionSubscription;

  LatLng? get currentLocation => _currentLocation;
  bool get isTracking => _isTracking;
  bool get hasPermission => _hasPermission;
  bool get isLoading => _isLoading;
  String? get error => _error;

  LatLng get locationOrDefault =>
      _currentLocation ??
      LatLng(AppConstants.defaultLat, AppConstants.defaultLon);

  Future<bool> initLocation() async {
    _isLoading = true;
    notifyListeners();

    try {
      final enabled = await _locationService.isLocationServiceEnabled();
      if (!enabled) {
        _error = 'Los servicios de ubicacion estan desactivados';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      var permission = await _locationService.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await _locationService.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _error = 'Permiso de ubicacion denegado';
        _hasPermission = false;
        _isLoading = false;
        notifyListeners();
        return false;
      }

      _hasPermission = true;
      _currentLocation = await _locationService.getCurrentPosition();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void startTracking() {
    if (_isTracking) return;
    _isTracking = true;

    _positionSubscription = _locationService.getPositionStream().listen(
      (position) {
        _currentLocation = position;
        notifyListeners();
      },
      onError: (e) {
        debugPrint('Location tracking error: $e');
      },
    );

    notifyListeners();
  }

  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _isTracking = false;
    notifyListeners();
  }

  double distanceTo(LatLng target) {
    if (_currentLocation == null) return 0;
    return _locationService.calculateDistance(_currentLocation!, target);
  }

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}

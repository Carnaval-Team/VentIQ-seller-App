import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../services/location_service.dart';
import '../services/background_service.dart';
import '../utils/constants.dart';

class LocationProvider extends ChangeNotifier {
  final LocationService _locationService = LocationService();

  LatLng? _currentLocation;
  double _currentSpeed = 0.0; // m/s from GPS
  bool _isTracking = false;
  bool _hasPermission = false;
  bool _isLoading = false;
  String? _error;

  // Position stream — continuous real-time updates
  StreamSubscription? _positionSubscription;
  // Service-status stream — fires when the user enables/disables GPS
  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;
  // Background service location stream
  StreamSubscription? _bgLocationSubscription;

  LatLng? get currentLocation => _currentLocation;
  /// Current speed in m/s from GPS (0 when stationary or unknown).
  double get currentSpeed => _currentSpeed;
  bool get isTracking => _isTracking;
  bool get hasPermission => _hasPermission;
  bool get isLoading => _isLoading;
  String? get error => _error;

  LatLng get locationOrDefault =>
      _currentLocation ??
      LatLng(AppConstants.defaultLat, AppConstants.defaultLon);

  /// Call once on app start. Requests permission, gets first fix, then
  /// starts the continuous position stream AND listens for GPS on/off events.
  Future<bool> initLocation() async {
    _isLoading = true;
    notifyListeners();

    try {
      var permission = await _locationService.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await _locationService.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _error = 'Permiso de ubicación denegado';
        _hasPermission = false;
        _isLoading = false;
        notifyListeners();
        // Still listen for service status so we react if they enable later
        _listenServiceStatus();
        return false;
      }

      _hasPermission = true;

      final enabled = await _locationService.isLocationServiceEnabled();
      if (!enabled) {
        _error = 'Activa el GPS para ver tu ubicación';
        _isLoading = false;
        notifyListeners();
        _listenServiceStatus();
        return false;
      }

      // Get first fix — retry up to 3 times on timeout
      bool gotFix = false;
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          _currentLocation = await _locationService.getCurrentPosition();
          _error = null;
          gotFix = true;
          break;
        } on TimeoutException catch (_) {
          debugPrint('[LocationProvider] getCurrentPosition timeout (attempt $attempt/3)');
          if (attempt < 3) {
            _error = 'Obteniendo ubicación... (intento ${attempt + 1}/3)';
            notifyListeners();
          }
        }
      }

      if (!gotFix) {
        _error = 'No se pudo obtener la ubicación. Esperando señal GPS...';
        debugPrint('[LocationProvider] All 3 getCurrentPosition attempts timed out, starting stream anyway');
      }

      _isLoading = false;
      notifyListeners();

      // Always start continuous stream (will deliver position even if first fix failed)
      _startPositionStream();
      _listenServiceStatus();
      _listenBackgroundService();
      return gotFix;
    } catch (e, st) {
      debugPrint('[LocationProvider] initLocation error: $e\n$st');
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      // Still start stream + listeners so we recover when GPS becomes available
      _startPositionStream();
      _listenServiceStatus();
      _listenBackgroundService();
      return false;
    }
  }

  /// Starts (or restarts) the continuous GPS position stream.
  void _startPositionStream() {
    _positionSubscription?.cancel();
    _isTracking = true;

    _positionSubscription = _locationService.getRawPositionStream().listen(
      (position) {
        _currentLocation = LatLng(position.latitude, position.longitude);
        // speed < 0 means unknown; clamp to 0
        _currentSpeed = position.speed > 0 ? position.speed : 0.0;
        _error = null;
        notifyListeners();
      },
      onError: (e, st) {
        debugPrint('[LocationProvider] Position stream error: $e\n$st');
        _isTracking = false;
        notifyListeners();
      },
    );
  }

  /// Listens to GPS service on/off events. When the user enables GPS while
  /// the app is open, this automatically re-initialises the location.
  void _listenServiceStatus() {
    // getServiceStatusStream is not supported on Web
    if (kIsWeb) return;
    _serviceStatusSubscription?.cancel();
    _serviceStatusSubscription =
        Geolocator.getServiceStatusStream().listen((status) async {
      if (status == ServiceStatus.enabled) {
        debugPrint('GPS enabled — re-initialising location');
        _error = null;
        await initLocation();
      } else {
        _error = 'GPS desactivado';
        _positionSubscription?.cancel();
        _isTracking = false;
        notifyListeners();
      }
    });
  }

  /// Listens for location updates from the background service isolate.
  void _listenBackgroundService() {
    _bgLocationSubscription?.cancel();
    _bgLocationSubscription = BackgroundService.onLocationUpdate.listen((data) {
      if (data != null) {
        final lat = (data['lat'] as num).toDouble();
        final lon = (data['lon'] as num).toDouble();
        _currentLocation = LatLng(lat, lon);
        _error = null;
        notifyListeners();
      }
    });
  }

  // Public API kept for compatibility (home_map_screen calls startTracking
  // indirectly through the driver screens)
  void startTracking() {
    if (_isTracking) return;
    _startPositionStream();
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
    _positionSubscription?.cancel();
    _serviceStatusSubscription?.cancel();
    _bgLocationSubscription?.cancel();
    super.dispose();
  }
}

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/background_service.dart';
import '../services/pushy_service.dart';
import '../services/vehicle_service.dart';
import '../services/suscripcion_service.dart';
import '../utils/battery_optimizer.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final SuscripcionService _suscripcionService = SuscripcionService();

  User? _user;
  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? _driverProfile;
  String? _role; // 'client' or 'driver' — kept for backward compat
  String? _tipoUsuario; // full type: 'cliente_pasajero'|'shipper'|'conductor_pasajeros'|'carrier_carga'|'dispatcher'
  bool _isLoading = false;
  String? _error;
  bool _profileLoadFailed = false;

  User? get user => _user;
  Map<String, dynamic>? get userProfile => _userProfile;
  Map<String, dynamic>? get driverProfile => _driverProfile;
  String? get role => _role;
  String? get tipoUsuario => _tipoUsuario;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;
  bool get profileLoadFailed => _profileLoadFailed;

  // ── Typed role getters ───────────────────────────────────────────────────
  bool get isClient => _role == 'client';
  bool get isDriver => _role == 'driver';
  bool get isClientePasajero => _tipoUsuario == 'cliente_pasajero';
  bool get isShipper => _tipoUsuario == 'shipper';
  bool get isConductorPasajeros => _tipoUsuario == 'conductor_pasajeros';
  bool get isCarrierCarga => _tipoUsuario == 'carrier_carga';
  bool get isDispatcher => _tipoUsuario == 'dispatcher';

  /// Named route for the current user's home screen.
  String get homeRoute {
    switch (_tipoUsuario) {
      case 'shipper':
        return '/shipper/home';
      case 'carrier_carga':
        return '/carrier/home';
      case 'dispatcher':
        return '/dispatcher/home';
      case 'conductor_pasajeros':
        return '/driver/home';
      default:
        return '/client/home';
    }
  }

  AuthProvider() {
    _user = _authService.currentUser;
    if (_user != null) {
      _loadProfile().catchError((e) {
        _profileLoadFailed = true;
        debugPrint('[AuthProvider] Profile load failed in constructor: $e');
        notifyListeners();
      });
    }
  }

  Future<void> _loadProfile() async {
    try {
      final isDriverUser = await _authService.isDriver();
      if (isDriverUser) {
        _role = 'driver';
        _driverProfile = await _authService.getDriverProfile();
        // Read tipo_usuario from the loaded driver profile
        _tipoUsuario = (_driverProfile?['tipo_usuario'] as String?) ??
            'conductor_pasajeros';
      } else {
        _role = 'client';
        _userProfile = await _authService.getUserProfile();
        // Read tipo_usuario from the loaded user profile
        _tipoUsuario =
            (_userProfile?['tipo_usuario'] as String?) ?? 'cliente_pasajero';
      }
      // Subscribe to in-app notifications (no permission dialog)
      if (_user != null) {
        NotificationService().subscribe(_user!.id);
      }
      // NOTE: PushyService.register() and BackgroundService.start() are NOT
      // called here to avoid a race condition with the location permission
      // dialog. They are called sequentially from the home screens via
      // registerPushAndStartBackground() after location permission is granted.
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading profile: $e');
      rethrow;
    }
  }

  /// Register push notifications and start the background service.
  /// Call this from the home screen BEFORE requesting location permission
  /// so that the notification permission dialog finishes first (Android only
  /// shows one permission dialog at a time).
  Future<void> registerPushAndStartBackground() async {
    if (_user == null || kIsWeb) return;

    // 1. Register Pushy — may show notification permission dialog
    await PushyService.register(_user!.id);

    // 2. Start background service only if location permission is already granted.
    final permission = await Geolocator.checkPermission();
    debugPrint('[AuthProvider] Location permission: $permission');
    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      debugPrint('[AuthProvider] Starting background service...');
      final started = await BackgroundService.start(
        userUuid: _user!.id,
        role: _role ?? 'client',
        driverId: _driverProfile?['id'] as int?,
        maxRetries: 10,
      );
      debugPrint('[AuthProvider] Background service started: $started');
    } else {
      debugPrint('[AuthProvider] Skipping BG service - no location permission yet');
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
        try {
          await _loadProfile();
        } catch (e) {
          debugPrint('[AuthProvider] signIn: profile load failed: $e');
          _error = 'No se pudo cargar el perfil. Verifica tu conexión.';
          _profileLoadFailed = true;
          _isLoading = false;
          notifyListeners();
          return false;
        }
      }
      _isLoading = false;
      _profileLoadFailed = false;
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
    // tipoUsuario replaces old `role` but role is kept for backward compat
    String role = 'client',
    String tipoUsuario = 'cliente_pasajero',
    String? phone,
    String? pais,
    String? province,
    String? municipality,
    String? tipoDocumento,
    String? docFrenteUrl,
    String? docDorsoUrl,
    // Shipper-specific
    String? tipoCuenta,
    String? empresaNombre,
    String? empresaRut,
    String? empresaDireccion,
    List<String>? mercaderiasHabituales,
    // Carrier: lista de carrocerías (1..N vehículos/plataformas)
    List<Map<String, dynamic>>? carrocerias,
    // Conductor pasajeros: datos del vehículo
    String? vehiculoMarca,
    String? vehiculoModelo,
    String? vehiculoChapa,
    String? vehiculoColor,
    int? vehiculoAnio,
    int? vehiculoCapacidad,
    String? vehiculoCondicion,
    bool? vehiculoAireAcondicionado,
    int? vehiculoIdTipo,
    // Legacy single-vehicle fields kept for backward compat (conductor_pasajeros)
    String? mcNumber,
    String? dotNumber,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    // Derive role from tipoUsuario for backward compat
    final isDriverType = tipoUsuario == 'conductor_pasajeros' ||
        tipoUsuario == 'carrier_carga' ||
        tipoUsuario == 'dispatcher';
    final resolvedRole = isDriverType ? 'driver' : 'client';

    try {
      debugPrint('[signUp] Iniciando registro: email=$email tipoUsuario=$tipoUsuario');

      final response = await _authService.signUpWithEmail(
        email,
        password,
        name: name,
      );
      _user = response.user;
      _role = resolvedRole;
      _tipoUsuario = tipoUsuario;
      debugPrint('[signUp] Auth user creado: ${_user?.id}');

      if (_user != null) {
        if (isDriverType) {
          debugPrint('[signUp] Creando perfil driver (tipo=$tipoUsuario)...');
          await _authService.createDriverProfile({
            'name': name,
            'email': email,
            'uuid': _user!.id,
            'estado': false,
            'tipo_usuario': tipoUsuario,
            if (phone != null && phone.isNotEmpty) 'telefono': phone,
            if (pais != null && pais.isNotEmpty) 'pais': pais,
            if (province != null && province.isNotEmpty) 'province': province,
            if (municipality != null && municipality.isNotEmpty)
              'municipality': municipality,
            if (tipoDocumento != null) 'tipo_documento': tipoDocumento,
            if (docFrenteUrl != null) 'doc_frente_url': docFrenteUrl,
            if (docDorsoUrl != null) 'doc_dorso_url': docDorsoUrl,
            if (mcNumber != null && mcNumber.isNotEmpty) 'mc_number': mcNumber,
            if (dotNumber != null && dotNumber.isNotEmpty)
              'dot_number': dotNumber,
            // Dispatcher company fields
            if (tipoUsuario == 'dispatcher') ...{
              if (empresaNombre != null) 'empresa_nombre': empresaNombre,
              if (empresaRut != null) 'empresa_rut': empresaRut,
              if (empresaDireccion != null) 'empresa_direccion': empresaDireccion,
            },
          });
          debugPrint('[signUp] Perfil driver creado OK');

          // Insert carrocerías for carrier_carga (N vehicles)
          if (tipoUsuario == 'carrier_carga' &&
              carrocerias != null &&
              carrocerias.isNotEmpty) {
            debugPrint('[signUp] Insertando ${carrocerias.length} carrocería(s)...');
            final freshProfile = await _authService.getDriverProfile();
            final driverId = freshProfile?['id'] as int?;
            debugPrint('[signUp] driver_id obtenido: $driverId');
            if (driverId != null) {
              await VehicleService().createCarrocerias(
                driverId: driverId,
                carrocerias: carrocerias,
              );
              debugPrint('[signUp] Carrocerías insertadas OK');
            } else {
              debugPrint('[signUp][WARN] No se obtuvo driver_id; carrocerías no insertadas');
            }
          }

          // Insert vehicle for conductor_pasajeros and link it to the driver
          if (tipoUsuario == 'conductor_pasajeros' &&
              vehiculoChapa != null &&
              vehiculoChapa.isNotEmpty) {
            debugPrint('[signUp] Insertando vehículo pasajeros (chapa=$vehiculoChapa)...');
            final vehicleData = <String, dynamic>{
              'driver_uuid': _user!.id,
              if (vehiculoMarca != null && vehiculoMarca.isNotEmpty)
                'marca': vehiculoMarca,
              if (vehiculoModelo != null && vehiculoModelo.isNotEmpty)
                'modelo': vehiculoModelo,
              'chapa': vehiculoChapa,
              if (vehiculoColor != null && vehiculoColor.isNotEmpty)
                'color': vehiculoColor,
              if (vehiculoAnio != null) 'año': vehiculoAnio,
              if (vehiculoCapacidad != null) 'capacidad_int': vehiculoCapacidad,
              if (vehiculoCapacidad != null)
                'capacidad': vehiculoCapacidad.toString(),
              if (vehiculoCondicion != null) 'condicion': vehiculoCondicion,
              if (vehiculoAireAcondicionado != null)
                'aire_acondicionado': vehiculoAireAcondicionado,
              if (vehiculoIdTipo != null) 'id_tipo_vehiculo': vehiculoIdTipo,
            };
            final vehicleId =
                await _authService.createVehicle(vehicleData);
            debugPrint('[signUp] Vehículo creado con id=$vehicleId');
            if (vehicleId != null) {
              await _authService.linkVehicleToDriver(vehicleId);
              debugPrint('[signUp] Vehículo enlazado al driver OK');
            } else {
              debugPrint('[signUp][WARN] createVehicle retornó null; no se enlazó');
            }
          }
        } else {
          debugPrint('[signUp] Creando perfil usuario (tipo=$tipoUsuario)...');
          await _authService.createUserProfile({
            'name': name,
            'email': email,
            'uuid': _user!.id,
            'tipo_usuario': tipoUsuario,
            if (phone != null && phone.isNotEmpty) 'phone': phone,
            if (pais != null && pais.isNotEmpty) 'pais': pais,
            if (province != null && province.isNotEmpty) 'province': province,
            if (municipality != null && municipality.isNotEmpty)
              'municipality': municipality,
            if (tipoDocumento != null) 'tipo_documento': tipoDocumento,
            if (docFrenteUrl != null) 'doc_frente_url': docFrenteUrl,
            if (docDorsoUrl != null) 'doc_dorso_url': docDorsoUrl,
            // Shipper fields
            if (tipoUsuario == 'shipper') ...{
              if (tipoCuenta != null) 'tipo_cuenta': tipoCuenta,
              if (empresaNombre != null) 'empresa_nombre': empresaNombre,
              if (empresaRut != null) 'empresa_rut': empresaRut,
              if (empresaDireccion != null) 'empresa_direccion': empresaDireccion,
              if (mercaderiasHabituales != null)
                'mercaderias_habituales': mercaderiasHabituales,
            },
          });
          debugPrint('[signUp] Perfil usuario creado OK');
        }
        debugPrint('[signUp] Cargando perfil local...');
        await _loadProfile();
        debugPrint('[signUp] Perfil local cargado OK');

        // Crear suscripción gratuita del primer mes
        // Solo para tipos de usuario de la plataforma de carga
        final tiposConPlan = ['shipper', 'carrier_carga', 'dispatcher'];
        if (tiposConPlan.contains(tipoUsuario)) {
          debugPrint('[signUp] Creando suscripción gratis para tipo=$tipoUsuario...');
          // Normalizar: 'carrier_carga' → 'carrier' para el plan
          final tipoPlan = tipoUsuario == 'carrier_carga' ? 'carrier' : tipoUsuario;
          await _suscripcionService.crearSuscripcionGratis(_user!.id, tipoPlan);
          debugPrint('[signUp] Suscripción gratis creada OK');
        }
      }

      _isLoading = false;
      notifyListeners();
      debugPrint('[signUp] Registro completado exitosamente');
      return _user != null;
    } catch (e, st) {
      debugPrint('[signUp][ERROR] $e\n$st');
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    await BackgroundService.stop();
    await NotificationService().unsubscribe();
    if (_user != null) {
      await PushyService.unregister(_user!.id);
    }
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

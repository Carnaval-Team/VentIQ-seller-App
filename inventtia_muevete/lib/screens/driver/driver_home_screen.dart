import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import '../../utils/smooth_compass_mixin.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_map/flutter_map.dart' hide TileLayer;
import 'package:flutter_map/flutter_map.dart' as fm show TileLayer;
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart' as fmtc;
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:geolocator/geolocator.dart';

import '../../services/mbtiles_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/completion_sync_service.dart';
import '../../services/driver_service.dart';
import '../../services/background_service.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import '../../utils/app_error.dart';
import '../../widgets/onboarding_checklist_fab.dart';
import 'active_ride_screen.dart';
import 'incoming_requests_screen.dart';
import 'driver_wallet_screen.dart';


class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen>
    with WidgetsBindingObserver, SmoothCompassMixin {
  final DriverService _driverService = DriverService();
  final MapController _mapController = MapController();

  /// Checklist de requisitos (perfil, consentimiento, contacto, KYC, vehículo).
  final GlobalKey<OnboardingChecklistFabState> _checklistKey =
      GlobalKey<OnboardingChecklistFabState>();

  @override
  MapController get compassMapController => _mapController;

  bool _isOnline = false;
  bool _isTogglingStatus = false;
  bool _driverInitialized = false;
  int _currentNavIndex = 0;

  // Periodic location tracker while online
  Timer? _locationTimer;
  Timer? _tripPollingTimer;

  // Viajes pendientes cercanos: sólo se usan para pintar el mapa.
  List<Map<String, dynamic>> _nearbyRequests = [];

  // Datos del viaje en curso para el banner. Se llena desde `muevete.viajes`
  // + su `solicitudes_transporte`; nulo cuando no hay viaje activo.
  Map<String, dynamic>? _confirmedTripData;

  @override
  void initState() {
    super.initState();
    _initializeDriver();

    WidgetsBinding.instance.addObserver(this);
    MbTilesService.instance.addListener(_onOfflineMapChanged);
  }

  void _onOfflineMapChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initializeDriver() async {
    if (_driverInitialized) return;
    _driverInitialized = true;

    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      await Geolocator.requestPermission();
    }

    final locationProvider = context.read<LocationProvider>();
    final authProvider = context.read<AuthProvider>(); // read before await
    // Register push first (may show notification permission dialog), then
    // request location permission — avoids two dialogs at the same time.
    await authProvider.registerPushAndStartBackground();
    await locationProvider.initLocation();
    locationProvider.startTracking();
    // Start background service now that location permission is granted (retries up to 10 times)
    final bgStarted = await authProvider.ensureBackgroundServiceStarted();
    if (!bgStarted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo iniciar el servicio en segundo plano después de 10 intentos. Verifica los permisos de ubicación y reinicia la app.',
          ),
          duration: Duration(seconds: 8),
          backgroundColor: Colors.red,
        ),
      );
    }

    if (!mounted) return;
    final driverProfile = authProvider.driverProfile;
    if (driverProfile != null) {
      final estado = driverProfile['estado'] as bool? ?? false;
      // Only seed from profile once — never overwrite a live toggle with stale cache
      setState(() => _isOnline = estado);
      if (_isOnline) {
        _startLocationTracking();
        await _loadNearbyRequests();
        _startTripPolling();
        BackgroundService.updateStatus(
          title: 'Muevete - Conductor',
          content: 'En línea · Esperando viajes',
        );
      }
      // El banner del viaje en curso se refresca también al arrancar.
      await _refreshActiveTripBanner();
    }
  }

  void _startLocationTracking() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted || !_isOnline) return;
      // Read all context-dependent values synchronously before any await
      final authProvider = context.read<AuthProvider>();
      final driverProfile = authProvider.driverProfile;
      final driverId = driverProfile?['id'] as int?;
      final vehiculo = driverProfile?['vehiculos'] as Map<String, dynamic>?;
      final vehicleId = vehiculo?['id'] as int?;
      if (driverId == null || vehicleId == null) return;
      final loc = context.read<LocationProvider>().locationOrDefault;
      // No more context access after this point
      try {
        // Only update coordinates — never flip place.estado while tracking
        await _driverService.updateDriverLocation(
          driverId,
          loc.latitude,
          loc.longitude,
        );
      } catch (e) {
        dev.log(
          '[Tracking] Error actualizando posición: $e',
          name: 'DriverHome',
        );
      }
    });
  }

  void _stopLocationTracking() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  /// Refresco de seguridad: pinta los viajes cercanos en el mapa y mantiene
  /// al día el banner del viaje en curso.
  void _startTripPolling() {
    _tripPollingTimer?.cancel();
    _tripPollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      if (_isOnline) _loadNearbyRequests();
      _refreshActiveTripBanner();
    });
  }

  void _stopTripPolling() {
    _tripPollingTimer?.cancel();
    _tripPollingTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // Sync any pending offline completions
      CompletionSyncService.syncPendingCompletions();
      if (_isOnline) _loadNearbyRequests();
      _refreshActiveTripBanner();
    }
  }

  /// Pinta en el mapa los viajes pendientes cercanos. La decisión real de
  /// tomar un viaje vive en "Viajes disponibles" (`fn_viajes_disponibles`).
  Future<void> _loadNearbyRequests() async {
    if (!mounted) return;
    final loc = context.read<LocationProvider>().locationOrDefault;
    try {
      final rows = await _driverService.fetchNearbyPendingRequests(
        loc.latitude,
        loc.longitude,
        AppConstants.defaultSearchRadiusKm,
      );

      if (mounted) {
        // Only rebuild if data actually changed
        final oldIds = _nearbyRequests.map((r) => r['id']).toSet();
        final newIds = rows.map((r) => r['id']).toSet();
        if (!_setEquals(oldIds, newIds)) {
          setState(() => _nearbyRequests = rows);
        }
      }
    } catch (e) {
      dev.log('[NearbyRequest] Error: $e', name: 'DriverHome');
    }
  }

  bool _setEquals(Set a, Set b) => a.length == b.length && a.containsAll(b);

  Future<void> _goToActiveRide() async {
    if (_confirmedTripData == null) return;
    final data = Map<String, dynamic>.from(_confirmedTripData!);
    setState(() => _confirmedTripData = null);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ActiveRideScreen(tripData: data)),
    );
    if (mounted) await _refreshActiveTripBanner();
  }

  /// Mantiene el banner del viaje en curso.
  ///
  /// En el flujo de precio fijo el viaje lo crea `fn_tomar_viaje`: se busca la
  /// fila abierta de `muevete.viajes` y se completa con su solicitud
  /// (`solicitud_id`, migración 031). Sin viaje abierto, el banner desaparece.
  Future<void> _refreshActiveTripBanner() async {
    if (!mounted) return;
    final driverProfile = context.read<AuthProvider>().driverProfile;
    final driverId = driverProfile?['id'] as int?;
    if (driverId == null) {
      if (_confirmedTripData != null) {
        setState(() => _confirmedTripData = null);
      }
      return;
    }

    Map<String, dynamic>? activeTrip;
    try {
      activeTrip = await _driverService.getActiveTrip(driverId);
    } catch (e) {
      dev.log('[ActiveTrip] Error: $e', name: 'DriverHome');
      return;
    }
    if (!mounted) return;

    if (activeTrip == null) {
      if (_confirmedTripData != null) {
        setState(() => _confirmedTripData = null);
      }
      return;
    }

    final data = await _tripDataDesdeViaje(activeTrip);
    if (!mounted) return;
    // Evita repintar cada 15 s cuando el viaje no cambió.
    final mismoViaje = _confirmedTripData?['viaje_id'] == data['viaje_id'] &&
        _confirmedTripData?['estado'] == data['estado'];
    if (!mismoViaje) {
      setState(() => _confirmedTripData = data);
    }
  }

  /// Arma el `tripData` que espera `ActiveRideScreen` a partir de la fila del
  /// viaje y su solicitud.
  Future<Map<String, dynamic>> _tripDataDesdeViaje(
    Map<String, dynamic> viaje,
  ) async {
    final data = <String, dynamic>{
      'viaje_id': viaje['id'],
      'estado': viaje['estado'],
      'user_id': viaje['user'],
    };

    final solicitudId = (viaje['solicitud_id'] as num?)?.toInt();
    if (solicitudId == null) return data;

    data['solicitud_id'] = solicitudId;
    try {
      final solicitud = await _driverService.fetchSolicitudById(solicitudId);
      if (solicitud == null) return data;

      data['direccion_origen'] = solicitud['direccion_origen'] ?? 'Origen';
      data['direccion_destino'] = solicitud['direccion_destino'] ?? 'Destino';
      data['lat_origen'] = solicitud['lat_origen'];
      data['lon_origen'] = solicitud['lon_origen'];
      data['lat_destino'] = solicitud['lat_destino'];
      data['lon_destino'] = solicitud['lon_destino'];
      // Lo que paga el cliente: el precio lo fija el servidor al crear.
      data['precio'] = solicitud['precio_plataforma'];
      data['pago_chofer'] = solicitud['precio_chofer'];

      final userId = solicitud['user_id'] as String?;
      if (userId != null) {
        data['user_id'] = userId;
        final client = await _driverService.fetchClientInfo(userId);
        if (client != null) {
          data['client_name'] = client['name'] ?? 'Pasajero';
          data['client_phone'] = client['phone'] ?? '';
          data['client_image'] = client['photo_url'];
        }
      }
    } catch (e) {
      dev.log('[ActiveTrip] Error leyendo solicitud: $e', name: 'DriverHome');
    }
    return data;
  }

  /// Abre "Viajes disponibles": el chofer toma el viaje con el precio que ya
  /// fijó la plataforma (no hay oferta ni contraoferta).
  Future<void> _abrirViajesDisponibles() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const IncomingRequestsScreen()),
    );
    if (!mounted) return;
    await _refreshActiveTripBanner();
    if (mounted && _isOnline) await _loadNearbyRequests();
  }

  Future<void> _confirmAndSignOut() async {
    final isDark = context.read<ThemeProvider>().isDark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface(isDark),
        title: Text(
          'Cerrar sesión',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary(isDark),
          ),
        ),
        content: Text(
          '¿Seguro que deseas cerrar sesión?',
          style: GoogleFonts.plusJakartaSans(
            color: AppTheme.textSecondary(isDark),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.plusJakartaSans(
                color: AppTheme.textTertiary(isDark),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: Text(
              'Cerrar sesión',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (_isOnline) {
      try {
        await _toggleOnlineStatus();
      } catch (_) {}
    }
    if (!mounted) return;
    await context.read<AuthProvider>().signOut();
  }

  Future<void> _toggleOnlineStatus() async {
    final authProvider = context.read<AuthProvider>();
    final driverProfile = authProvider.driverProfile;
    if (driverProfile == null) return;

    final driverId = driverProfile['id'] as int?;
    if (driverId == null) return;

    // Block going online if no vehicle assigned
    final vehiculo = driverProfile['vehiculos'] as Map<String, dynamic>?;
    if (vehiculo == null && !_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Debes registrar un vehículo desde tu perfil antes de ponerte en línea'),
        behavior: SnackBarBehavior.floating,
      ));
      Navigator.pushNamed(context, '/profile');
      return;
    }

    setState(() => _isTogglingStatus = true);

    try {
      final newStatus = !_isOnline;
      final locationProvider = context.read<LocationProvider>();
      final loc = locationProvider.locationOrDefault;
      final vehicleId = vehiculo?['id'] as int?;

      if (newStatus && vehicleId != null) {
        // Upsert place immediately on go-online (creates row if missing)
        await _driverService.upsertDriverLocation(
          driverId: driverId,
          vehicleId: vehicleId,
          lat: loc.latitude,
          lon: loc.longitude,
          online: true,
        );
        // Persist online status in drivers table so it survives app restart
        await _driverService.toggleOnlineStatus(driverId, true);
        authProvider.setDriverOnlineStatus(true);
      } else {
        // Go offline — update estado only
        await _driverService.toggleOnlineStatus(driverId, false);
        authProvider.setDriverOnlineStatus(false);
      }

      setState(() => _isOnline = newStatus);

      if (newStatus) {
        _startLocationTracking();
        _startTripPolling();
        await _loadNearbyRequests();
        await _refreshActiveTripBanner();
        BackgroundService.updateStatus(
          title: 'Muevete - Conductor',
          content: 'En línea · Esperando viajes',
        );
      } else {
        await _driverService.unsubscribe();
        _stopLocationTracking();
        _stopTripPolling();
        setState(() {
          _nearbyRequests.clear();
        });
        BackgroundService.updateStatus(
          title: 'Muevete - Conductor',
          content: 'Desconectado',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppError.message(e, action: 'cambiar el estado'))));
      }
    } finally {
      if (mounted) setState(() => _isTogglingStatus = false);
    }
  }

  /// Abre la pantalla del viaje en curso o avisa si no hay ninguno.
  Future<void> _checkForActiveRide() async {
    await _refreshActiveTripBanner();
    if (!mounted) return;
    if (_confirmedTripData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No tienes un viaje en curso.',
            style: GoogleFonts.plusJakartaSans(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await _goToActiveRide();
  }

  /// Abre el perfil (donde se registra el vehículo) y refresca al volver:
  /// el checklist de requisitos depende de esos datos.
  Future<void> _abrirPerfil() async {
    await Navigator.of(context).pushNamed('/profile');
    if (!mounted) return;
    _checklistKey.currentState?.refresh();
    if (_isOnline) _loadNearbyRequests();
  }

  void _onNavTap(int index) {
    if (index == _currentNavIndex) return;

    switch (index) {
      case 0:
        // Already on home
        break;
      case 1:
        Navigator.of(context)
            .push(
              MaterialPageRoute(builder: (_) => const IncomingRequestsScreen()),
            )
            .then((_) async {
              if (!mounted) return;
              await _refreshActiveTripBanner();
              if (mounted && _isOnline) _loadNearbyRequests();
            });
        return;
      case 2:
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const DriverWalletScreen()))
            .then((_) {
              if (mounted && _isOnline) _loadNearbyRequests();
            });
        return;
      case 3:
        _abrirPerfil();
        return;
    }

    setState(() {
      _currentNavIndex = index;
    });
  }

  @override
  void dispose() {
    MbTilesService.instance.removeListener(_onOfflineMapChanged);
    disposeCompass();
    WidgetsBinding.instance.removeObserver(this);
    _stopLocationTracking();
    _stopTripPolling();
    _driverService.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final locationProvider = context.watch<LocationProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDark;

    final driverProfile = authProvider.driverProfile;
    final driverName = driverProfile?['name'] as String? ?? 'Conductor';
    final driverId = driverProfile?['id'] as int?;
    final vehiculo = driverProfile?['vehiculos'] as Map<String, dynamic>?;
    final vehicleType = vehiculo?['vehicle_type'] as Map<String, dynamic>?;
    final location = locationProvider.locationOrDefault;

    final tileUrl = isDark ? AppTheme.cartoDarkTileUrl : AppTheme.osmTileUrl;

    // El botón "Viajes disponibles" es el acceso principal del home. Los
    // flotantes suben para no quedar encima; si hay viaje en curso manda el
    // banner y el botón de viajes se oculta.
    final bool mostrarCtaViajes = _confirmedTripData == null;
    final double fabBottom = mostrarCtaViajes ? 176 : 100;

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      body: Stack(
        children: [
          // Full-screen map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: location,
              initialZoom: AppConstants.defaultZoom,
            ),
            children: [
              if (!kIsWeb &&
                  MbTilesService.instance.useOffline &&
                  MbTilesService.instance.provider != null)
                VectorTileLayer(
                  theme: MbTilesService.instance.getTheme(isDark: isDark),
                  tileProviders: TileProviders({
                    'openmaptiles': MbTilesService.instance.provider!,
                  }),
                  maximumZoom: 18,
                  fileCacheMaximumSizeInBytes: 0,
                )
              else
                fm.TileLayer(
                  urlTemplate: tileUrl,
                  userAgentPackageName: 'com.inventtia.muevete',
                  tileProvider: kIsWeb
                      ? null
                      : fmtc.FMTCTileProvider(
                          stores: const {
                            'mapTiles': fmtc.BrowseStoreStrategy.readUpdate,
                          },
                        ),
                ),
              MarkerLayer(
                markers: [
                  // Driver marker: navigation arrow when auto-rotate, car icon otherwise
                  Marker(
                    point: location,
                    width: 50,
                    height: 50,
                    rotate: autoRotate,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.markerBorder(isDark),
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor.withValues(alpha: 0.4),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        autoRotate ? Icons.navigation : Icons.directions_car,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                  // Viajes pendientes cercanos (origen verde + destino rojo).
                  // Al tocar se abre "Viajes disponibles": aquí no se oferta.
                  ..._nearbyRequests.expand((row) {
                    final lat = (row['lat_origen'] as num?)?.toDouble();
                    final lon = (row['lon_origen'] as num?)?.toDouble();
                    final latDest = (row['lat_destino'] as num?)?.toDouble();
                    final lonDest = (row['lon_destino'] as num?)?.toDouble();
                    if (lat == null || lon == null) return <Marker?>[];
                    final name =
                        row['direccion_origen'] as String? ?? 'Cliente';
                    final destName =
                        row['direccion_destino'] as String? ?? 'Destino';
                    return [
                      // Origin marker (green)
                      Marker(
                        point: LatLng(lat, lon),
                        width: 56,
                        height: 56,
                        child: GestureDetector(
                          onTap: _abrirViajesDisponibles,
                          child: Tooltip(
                            message: name,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppTheme.success,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTheme.markerBorder(isDark),
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.success.withValues(
                                      alpha: 0.45,
                                    ),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : 'C',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Destination marker (red flag) — only if coords exist
                      if (latDest != null && lonDest != null)
                        Marker(
                          point: LatLng(latDest, lonDest),
                          width: 40,
                          height: 40,
                          child: Tooltip(
                            message: destName,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppTheme.error,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTheme.markerBorder(isDark),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.error.withValues(
                                      alpha: 0.4,
                                    ),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.flag,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                    ];
                  }).whereType<Marker>(),
                ],
              ),
            ],
          ),

          // Top bar with greeting and online toggle
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surface(isDark).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border(isDark)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Avatar
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person,
                        color: AppTheme.primaryColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Name + status + vehicle info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Hola, $driverName',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary(isDark),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _isOnline
                                      ? AppTheme.success
                                      : Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _isOnline ? 'En línea' : 'Desconectado',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: _isOnline
                                      ? AppTheme.success
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Vehicle chip
                          vehiculo != null
                              ? GestureDetector(
                                  onTap: _abrirPerfil,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryColor.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: AppTheme.primaryColor.withValues(
                                          alpha: 0.4,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.directions_car,
                                          color: AppTheme.primaryColor,
                                          size: 12,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${vehiculo['marca'] ?? ''} ${vehiculo['modelo'] ?? ''} · ${vehiculo['chapa'] ?? ''}'
                                              .trim(),
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.primaryColor,
                                          ),
                                        ),
                                        if (vehicleType != null) ...[
                                          const SizedBox(width: 4),
                                          Text(
                                            '(${vehicleType['tipo'] ?? ''})',
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 10,
                                              color: AppTheme.textTertiary(
                                                isDark,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                )
                              : GestureDetector(
                                  onTap: _abrirPerfil,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.error.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: AppTheme.error.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.warning_amber_rounded,
                                          color: AppTheme.error,
                                          size: 12,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Sin vehículo · Registrar',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.error,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        ],
                      ),
                    ),
                    // Online toggle + logout
                    _isTogglingStatus
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primaryColor,
                            ),
                          )
                        : Switch.adaptive(
                            value: _isOnline,
                            onChanged: _isTogglingStatus
                                ? null
                                : (_) => _toggleOnlineStatus(),
                            activeColor: AppTheme.success,
                            activeTrackColor: AppTheme.success.withValues(
                              alpha: 0.3,
                            ),
                            inactiveThumbColor: vehiculo == null
                                ? AppTheme.error
                                : Colors.grey,
                            inactiveTrackColor: vehiculo == null
                                ? AppTheme.error.withValues(alpha: 0.3)
                                : Colors.grey.withValues(alpha: 0.3),
                          ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Cerrar sesión',
                      onPressed: _confirmAndSignOut,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      icon: Icon(
                        Icons.logout_rounded,
                        size: 22,
                        color: AppTheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Re-center + theme toggle buttons. El checklist de requisitos va
          // encima del grupo, con 12 px de separación; se oculta solo cuando
          // ya no falta nada, así que no deja hueco.
          Positioned(
            right: 16,
            bottom: fabBottom,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                OnboardingChecklistFab(
                  key: _checklistKey,
                  rol: 'chofer',
                  driverId: driverId,
                  separacionInferior: 12,
                ),
                FloatingActionButton.small(
                  heroTag: 'autorotate',
                  onPressed: toggleAutoRotate,
                  backgroundColor: autoRotate
                      ? AppTheme.primaryColor
                      : AppTheme.surface(isDark),
                  child: Icon(
                    autoRotate ? Icons.explore : Icons.explore_off,
                    color: autoRotate ? Colors.white : AppTheme.primaryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.small(
                  heroTag: 'recenter',
                  onPressed: () {
                    _mapController.move(location, AppConstants.defaultZoom);
                  },
                  backgroundColor: AppTheme.surface(isDark),
                  child: const Icon(
                    Icons.my_location,
                    color: AppTheme.primaryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.small(
                  heroTag: 'theme_toggle',
                  onPressed: () {
                    context.read<ThemeProvider>().toggleTheme();
                  },
                  backgroundColor: AppTheme.surface(isDark),
                  child: Icon(
                    themeProvider.isDark ? Icons.light_mode : Icons.dark_mode,
                    color: AppTheme.primaryColor,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),

          // Check active ride button
          if (_isOnline)
            Positioned(
              left: 16,
              bottom: fabBottom,
              child: FloatingActionButton.small(
                heroTag: 'activeride',
                onPressed: _checkForActiveRide,
                backgroundColor: AppTheme.surface(isDark),
                child: const Icon(
                  Icons.route,
                  color: AppTheme.primaryColor,
                  size: 20,
                ),
              ),
            ),

          // Acceso principal del home del chofer: viajes disponibles.
          // El precio ya viene fijado por la plataforma, no hay oferta.
          if (mostrarCtaViajes)
            Positioned(
              left: 16,
              right: 16,
              bottom: 92,
              child: SizedBox(
                height: 62,
                child: ElevatedButton(
                  onPressed: _abrirViajesDisponibles,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.local_taxi, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Viajes disponibles',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _isOnline
                                  ? 'El precio ya está fijado por la plataforma'
                                  : 'Ponte en línea para tomar viajes',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 22),
                    ],
                  ),
                ),
              ),
            ),

          // Banner del viaje en curso
          if (_confirmedTripData != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 80,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.surface(isDark),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.success.withValues(alpha: 0.4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.success.withValues(alpha: 0.2),
                          ),
                          child: const Icon(
                            Icons.check_circle,
                            color: AppTheme.success,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Viaje en curso',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary(isDark),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_confirmedTripData!['client_name'] ?? 'Pasajero'} te espera',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  color: AppTheme.textTertiary(isDark),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Lo que paga el cliente. Si el viaje es de una versión anterior
                        // (sin `precio_plataforma`) no se inventa un monto.
                        if ((_confirmedTripData!['precio'] as num?) != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.success.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              Helpers.formatCurrency(
                                (_confirmedTripData!['precio'] as num)
                                    .toDouble(),
                              ),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.success,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.circle,
                          color: AppTheme.success,
                          size: 8,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _confirmedTripData!['direccion_origen'] ?? '',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: AppTheme.textSecondary(isDark),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.circle,
                          color: AppTheme.error,
                          size: 8,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _confirmedTripData!['direccion_destino'] ?? '',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: AppTheme.textSecondary(isDark),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _goToActiveRide,
                        icon: const Icon(Icons.navigation, size: 20),
                        label: Text(
                          'Ir al viaje',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentNavIndex,
        onTap: _onNavTap,
        backgroundColor: AppTheme.surface(isDark),
        selectedItemColor: AppTheme.primaryColor,
        unselectedItemColor: AppTheme.textTertiary(isDark),
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt_outlined),
            activeIcon: Icon(Icons.list_alt),
            label: 'Viajes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet),
            label: 'Billetera',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

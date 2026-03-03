import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_compass_v2/flutter_compass_v2.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_theme.dart';
import '../../providers/address_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/transport_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/transport_request_service.dart';
import '../../services/routing_service.dart';
import '../../models/transport_request_model.dart';
import '../../utils/constants.dart';
import '../../widgets/client_drawer.dart';
import '../../widgets/map_widget.dart';
import '../../widgets/transport_type_card.dart';
import 'location_search_screen.dart';
import 'ride_confirmed_screen.dart';

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final MapController _mapController = MapController();
  int _currentNavIndex = 0;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _mapCenteredOnUser = false;

  final TransportRequestService _requestService = TransportRequestService();
  final RoutingService _routingService = RoutingService();
  List<Map<String, dynamic>> _nearbyDrivers = [];
  Timer? _driversRefreshTimer;

  // ── Active trip state ───────────────────────────────────────────────────
  bool _checkingActiveTrip = true;
  bool _hasActiveTrip = false;
  Map<String, dynamic>? _activeSolicitud; // solicitud row
  Map<String, dynamic>? _activeSolicitudDriver; // driver info if accepted
  LatLng? _activeTripDestination;
  LatLng? _activeTripDriverPos;
  List<LatLng> _activeTripRoute = [];
  List<LatLng> _activeTripTrail = [];
  LatLng? _lastTrailPosition;
  bool _isRecalculating = false;
  Timer? _driverTrackingTimer;
  Timer? _routeRefreshTimer; // periodic fallback every 10s
  Timer? _activeTripPollingTimer; // polling for active trip / offers

  // Navigation mode state
  bool _autoRotate = false;
  bool _tilt3D = false;
  double _currentTilt = 0.0;
  double _heading = 0.0;
  StreamSubscription<CompassEvent>? _compassSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final locationProvider = context.read<LocationProvider>();
      locationProvider.initLocation().then((_) async {
        // Start background service now that location permission is granted
        if (!mounted) return;
        final started = await context.read<AuthProvider>().ensureBackgroundServiceStarted();
        if (!started && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo iniciar el servicio en segundo plano después de 10 intentos. Verifica permisos de ubicación y reinicia la app.'),
              duration: Duration(seconds: 8),
              backgroundColor: Colors.red,
            ),
          );
        }
      });
      locationProvider.addListener(_onLocationChanged);

      context.read<TransportProvider>().loadVehicleTypes();
      final uuid = context.read<AuthProvider>().user?.id;
      if (uuid != null) {
        context.read<AddressProvider>().loadAddresses(uuid);
        _checkActiveTrip(uuid);
      } else {
        setState(() => _checkingActiveTrip = false);
      }

      _loadNearbyDrivers();
      _driversRefreshTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _loadNearbyDrivers(),
      );

      // Polling: re-check active trip every 15s as realtime backup
      _activeTripPollingTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) {
          if (!mounted) return;
          final uuid = context.read<AuthProvider>().user?.id;
          if (uuid != null) _checkActiveTrip(uuid);
        },
      );
    });
  }

  // ── Active trip check ───────────────────────────────────────────────────
  bool _isFirstTripCheck = true;
  Future<void> _checkActiveTrip(String userId) async {
    // Only show loading spinner on the very first check, not on polling refreshes
    if (_isFirstTripCheck) {
      setState(() => _checkingActiveTrip = true);
    }
    try {
      // Look for solicitudes that are pendiente OR aceptada (not completada/cancelada)
      final rows = await Supabase.instance.client
          .schema('muevete')
          .from('solicitudes_transporte')
          .select()
          .eq('user_id', userId)
          .inFilter('estado', ['pendiente', 'aceptada'])
          .order('created_at', ascending: false)
          .limit(1);

      if (rows != null && (rows as List).isNotEmpty) {
        final solicitud = Map<String, dynamic>.from(rows.first);
        setState(() {
          _activeSolicitud = solicitud;
          _hasActiveTrip = true;
          final lat = (solicitud['lat_destino'] as num?)?.toDouble();
          final lon = (solicitud['lon_destino'] as num?)?.toDouble();
          if (lat != null && lon != null) {
            _activeTripDestination = LatLng(lat, lon);
          }
        });

        // If aceptada, load driver info
        if (solicitud['estado'] == 'aceptada') {
          await _loadAcceptedTripDriver(solicitud['id'] as int);
        }

        // Start real-time tracking for active trip
        _startActiveTripTracking();
      } else {
        setState(() => _hasActiveTrip = false);
      }
    } catch (e, st) {
      debugPrint('[HomeMap] _checkActiveTrip error: $e\n$st');
      setState(() => _hasActiveTrip = false);
    } finally {
      _isFirstTripCheck = false;
      if (mounted) setState(() => _checkingActiveTrip = false);
    }
  }

  Future<void> _loadAcceptedTripDriver(int solicitudId) async {
    try {
      final offerRows = await Supabase.instance.client
          .schema('muevete')
          .from('ofertas_chofer')
          .select('''
            driver_id,
            tiempo_estimado,
            precio,
            drivers!ofertas_chofer_driver_id_fkey(
              id, name, image, telefono, kyc,
              vehiculos!drivers_vehiculo_fkey(marca, modelo, chapa, color)
            )
          ''')
          .eq('solicitud_id', solicitudId)
          .eq('estado', 'aceptada')
          .limit(1);

      if (offerRows != null && (offerRows as List).isNotEmpty) {
        setState(() {
          _activeSolicitudDriver =
              Map<String, dynamic>.from(offerRows.first);
        });
      }
    } catch (e, st) {
      debugPrint('[HomeMap] _loadAcceptedTripDriver error: $e\n$st');
    }
  }

  void _startActiveTripTracking() {
    final locationProvider = context.read<LocationProvider>();

    // Listen to client GPS
    locationProvider.addListener(_onActiveTripLocationUpdate);

    // Seed trail with current or default position — always force first route calc
    final loc =
        locationProvider.currentLocation ?? locationProvider.locationOrDefault;
    _lastTrailPosition = loc;
    _activeTripTrail = [loc];
    _forceRecalculateActiveTripRoute(loc);

    // Periodic fallback: recalculate route every 10s regardless of movement
    _routeRefreshTimer?.cancel();
    _routeRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted || !_hasActiveTrip) return;
      final current = context.read<LocationProvider>().currentLocation ??
          context.read<LocationProvider>().locationOrDefault;
      _forceRecalculateActiveTripRoute(current);
    });

    // Poll driver position if there's a driver
    _driverTrackingTimer?.cancel();
    if (_activeSolicitudDriver != null) {
      final driverId =
          _activeSolicitudDriver!['driver_id'] as int?;
      if (driverId != null) {
        _pollActiveTripDriverPos(driverId);
        _driverTrackingTimer = Timer.periodic(
          const Duration(seconds: 8),
          (_) => _pollActiveTripDriverPos(driverId),
        );
      }
    }
  }

  void _onActiveTripLocationUpdate() {
    if (!mounted || !_hasActiveTrip) return;
    final loc = context.read<LocationProvider>().currentLocation;
    if (loc == null) return;

    if (_lastTrailPosition != null &&
        _haversineMeters(_lastTrailPosition!, loc) < 2) return;



    _lastTrailPosition = loc;

    setState(() {
      _activeTripTrail.add(loc);
      if (_activeTripTrail.length > 500) _activeTripTrail.removeAt(0);
    });

    // Auto-center with smooth animation
    if (_autoRotate || _hasActiveTrip) {
      _animateCameraToLocation(loc);
    }

    if (!_isRecalculating) {
      _forceRecalculateActiveTripRoute(loc);
    }
  }

  Future<void> _forceRecalculateActiveTripRoute(LatLng from) async {
    if (_activeTripDestination == null) return;
    _isRecalculating = true;
    try {
      final result =
          await _routingService.getRoute(from, _activeTripDestination!);
      if (mounted) {
        setState(() => _activeTripRoute = result.polyline);
      }
    } catch (e, st) {
      debugPrint('[HomeMap] _forceRecalculateActiveTripRoute error: $e\n$st');
    }
    _isRecalculating = false;
  }

  Future<void> _pollActiveTripDriverPos(int driverId) async {
    try {
      final row = await Supabase.instance.client
          .schema('muevete')
          .from('place')
          .select('latitude, longitude')
          .eq('driver', driverId)
          .maybeSingle();
      if (row != null && mounted) {
        final lat = (row['latitude'] as num?)?.toDouble();
        final lon = (row['longitude'] as num?)?.toDouble();
        if (lat != null && lon != null) {
          setState(() => _activeTripDriverPos = LatLng(lat, lon));
        }
      }
    } catch (e, st) {
      debugPrint('[HomeMap] _pollActiveTripDriverPos error: $e\n$st');
    }
  }

  double _haversineMeters(LatLng a, LatLng b) {
    const earthR = 6371000.0;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLon = (b.longitude - a.longitude) * pi / 180;
    final sinDLat = sin(dLat / 2);
    final sinDLon = sin(dLon / 2);
    final h = sinDLat * sinDLat +
        cos(a.latitude * pi / 180) *
            cos(b.latitude * pi / 180) *
            sinDLon *
            sinDLon;
    return 2 * earthR * asin(sqrt(h));
  }

  // ── Nearby drivers ──────────────────────────────────────────────────────
  Future<void> _loadNearbyDrivers() async {
    final loc = context.read<LocationProvider>().locationOrDefault;
    try {
      final drivers = await _requestService.getNearbyDrivers(
        loc.latitude,
        loc.longitude,
        AppConstants.defaultSearchRadiusKm,
      );
      if (!mounted) return;
      // Only update state if data actually changed to avoid unnecessary rebuilds
      if (!_listsEqual(_nearbyDrivers, drivers)) {
        setState(() => _nearbyDrivers = drivers);
      }
    } catch (e, st) {
      debugPrint('[HomeMap] _loadNearbyDrivers error: $e\n$st');
    }
  }

  /// Shallow comparison of two lists of maps by driver id.
  bool _listsEqual(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i]['driver'] != b[i]['driver'] ||
          a[i]['latitude'] != b[i]['latitude'] ||
          a[i]['longitude'] != b[i]['longitude']) return false;
    }
    return true;
  }

  void _refreshAfterNav() {
    if (!mounted) return;
    _loadNearbyDrivers();
    final uuid = context.read<AuthProvider>().user?.id;
    if (uuid != null) _checkActiveTrip(uuid);
  }

  void _onLocationChanged() {
    if (_mapCenteredOnUser) return;
    final loc = context.read<LocationProvider>().currentLocation;
    if (loc == null) return;
    _mapCenteredOnUser = true;
    try {
      _mapController.move(loc, AppConstants.defaultZoom);
    } catch (e, st) {
      debugPrint('[HomeMap] _onLocationChanged move error: $e\n$st');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadNearbyDrivers();
      final uuid = context.read<AuthProvider>().user?.id;
      if (uuid != null) _checkActiveTrip(uuid);
      // Re-subscribe realtime channels that may have died while suspended
      context.read<TransportProvider>().resubscribeRealtime();
    }
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _activeTripPollingTimer?.cancel();
    _driversRefreshTimer?.cancel();
    _driverTrackingTimer?.cancel();
    _routeRefreshTimer?.cancel();
    try {
      context.read<LocationProvider>().removeListener(_onLocationChanged);
      context
          .read<LocationProvider>()
          .removeListener(_onActiveTripLocationUpdate);
    } catch (e, st) {
      debugPrint('[HomeMap] dispose removeListener error: $e\n$st');
    }
    _pulseController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _centerOnUser() {
    final loc = context.read<LocationProvider>().locationOrDefault;
    _mapController.move(loc, AppConstants.defaultZoom);
  }

  void _animateCameraToLocation(LatLng target) {
    try {
      final cam = _mapController.camera;
      final startCenter = cam.center;
      final startZoom = cam.zoom;
      final startRotation = cam.rotation;
      final targetRotation = _autoRotate ? -_heading : 0.0;

      const steps = 15;
      const duration = Duration(milliseconds: 450);
      final stepDuration = Duration(
        microseconds: duration.inMicroseconds ~/ steps,
      );

      int step = 0;
      Timer.periodic(stepDuration, (timer) {
        step++;
        if (step >= steps || !mounted) {
          timer.cancel();
          return;
        }
        final t = step / steps;
        final ease = 1 - pow(1 - t, 3).toDouble();

        final lat = startCenter.latitude +
            (target.latitude - startCenter.latitude) * ease;
        final lon = startCenter.longitude +
            (target.longitude - startCenter.longitude) * ease;

        double rot = startRotation;
        if (_autoRotate) {
          var diff = targetRotation - startRotation;
          while (diff > 180) diff -= 360;
          while (diff < -180) diff += 360;
          rot = startRotation + diff * ease;
        }

        try {
          _mapController.moveAndRotate(LatLng(lat, lon), startZoom, rot);
        } catch (e) {
          debugPrint('[HomeMap] animateCamera moveAndRotate error: $e');
        }
      });
    } catch (e, st) {
      debugPrint('[HomeMap] animateCamera outer error: $e\n$st');
      try {
        _mapController.move(target, _mapController.camera.zoom);
      } catch (e2) {
        debugPrint('[HomeMap] animateCamera fallback move error: $e2');
      }
    }
  }

  void _toggleAutoRotate() {
    setState(() {
      _autoRotate = !_autoRotate;
      if (_autoRotate) {
        _compassSub = FlutterCompass.events?.listen((event) {
          final h = event.heading;
          if (h == null || !mounted) return;
          setState(() => _heading = h);
          if (_autoRotate) {
            try {
              _mapController.rotate(-h);
            } catch (e) {
              debugPrint('[HomeMap] compass rotate error: $e');
            }
          }
        });
      } else {
        _compassSub?.cancel();
        _compassSub = null;
        try {
          _mapController.rotate(0);
        } catch (e) {
          debugPrint('[HomeMap] rotate reset error: $e');
        }
      }
    });
  }

  void _toggle3DTilt() {
    setState(() => _tilt3D = !_tilt3D);
    const steps = 12;
    const duration = Duration(milliseconds: 350);
    final stepDuration = Duration(
      microseconds: duration.inMicroseconds ~/ steps,
    );
    final startTilt = _currentTilt;
    final endTilt = _tilt3D ? 1.0 : 0.0;

    int step = 0;
    Timer.periodic(stepDuration, (timer) {
      step++;
      if (step >= steps || !mounted) {
        timer.cancel();
        if (mounted) setState(() => _currentTilt = endTilt);
        return;
      }
      final t = step / steps;
      final ease = 1 - pow(1 - t, 3).toDouble();
      setState(() => _currentTilt = startTilt + (endTilt - startTilt) * ease);
    });
  }


  void _onMapTap(TapPosition tapPosition, LatLng point) {
    if (_hasActiveTrip) return; // block when active trip
    final locationProvider = context.read<LocationProvider>();
    final transportProvider = context.read<TransportProvider>();
    transportProvider.setPickup(locationProvider.locationOrDefault,
        address: 'Ubicación actual');
    transportProvider.setDropoff(point, address: 'Destino seleccionado');
    _openSearchScreen();
  }

  void _openSearchScreen() {
    if (_hasActiveTrip) return; // block when active trip
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LocationSearchScreen()),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final locationProvider = context.watch<LocationProvider>();
    final transportProvider = context.watch<TransportProvider>();
    final isDark = themeProvider.isDark;
    final userLocation = locationProvider.locationOrDefault;
    final addressProvider = context.watch<AddressProvider>();
    final locationError = locationProvider.error;

    // Build map markers
    final markers = <Marker>[
      // User marker: navigation arrow when auto-rotate, pulsing dot otherwise
      Marker(
        point: userLocation,
        width: 40,
        height: 40,
        rotate: _autoRotate,
        child: _autoRotate
            ? Container(
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.4),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.navigation,
                  color: Colors.white,
                  size: 20,
                ),
              )
            : _PulsingDot(animation: _pulseAnimation),
      ),
    ];

    // Nearby drivers (only when no active trip)
    if (!_hasActiveTrip) {
      for (final d in _nearbyDrivers) {
        final lat = (d['latitude'] as num?)?.toDouble();
        final lon = (d['longitude'] as num?)?.toDouble();
        if (lat == null || lon == null) continue;
        final driver = d['drivers'] as Map<String, dynamic>?;
        final name = driver?['name'] as String? ?? 'Conductor';
        final image = driver?['image'] as String?;
        markers.add(
          Marker(
            point: LatLng(lat, lon),
            width: 48,
            height: 48,
            child: Tooltip(
              message: name,
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: image != null && image.isNotEmpty
                      ? Image.network(image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                                Icons.directions_car,
                                color: Colors.white,
                                size: 22,
                              ))
                      : const Icon(Icons.directions_car,
                          color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        );
      }
    }

    // Active trip markers
    if (_hasActiveTrip) {
      // Destination pin
      if (_activeTripDestination != null) {
        markers.add(
          Marker(
            point: _activeTripDestination!,
            width: 44,
            height: 44,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.error,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.error.withValues(alpha: 0.4),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(Icons.flag, color: Colors.white, size: 20),
            ),
          ),
        );
      }
      // Driver pin
      if (_activeTripDriverPos != null) {
        final driverData =
            _activeSolicitudDriver?['drivers'] as Map<String, dynamic>?;
        final driverName = driverData?['name'] as String? ?? 'Conductor';
        markers.add(
          Marker(
            point: _activeTripDriverPos!,
            width: 80,
            height: 72,
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkCard : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 6),
                    ],
                  ),
                  child: Text(
                    driverName,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primaryColor,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.directions_car,
                      color: Colors.white, size: 18),
                ),
              ],
            ),
          ),
        );
      }
    }

    // Build polylines
    final polylines = <Polyline>[];
    if (_hasActiveTrip) {
      // Grey trail
      if (_activeTripTrail.length >= 2) {
        polylines.add(Polyline(
          points: List.from(_activeTripTrail),
          strokeWidth: 4.0,
          color: Colors.grey.withValues(alpha: 0.7),
        ));
      }
      // Blue current route — glow layer + solid
      if (_activeTripRoute.isNotEmpty) {
        polylines.add(Polyline(
          points: _activeTripRoute,
          strokeWidth: 10.0,
          color: AppTheme.primaryColor.withValues(alpha: 0.2),
        ));
        polylines.add(Polyline(
          points: _activeTripRoute,
          strokeWidth: 4.5,
          color: AppTheme.primaryColor,
        ));
      }
    }

    return Scaffold(
      drawer: const ClientDrawer(),
      body: Stack(
        children: [
          // Full-screen map
          MapWidget(
            isDark: isDark,
            mapController: _mapController,
            center: userLocation,
            zoom: AppConstants.defaultZoom,
            onTap: _onMapTap,
            markers: markers,
            polylines: polylines,
            perspectiveTilt: _currentTilt,
          ),

          // Top bar overlay
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Builder(
                        builder: (scaffoldContext) => _buildCircleButton(
                          icon: Icons.menu,
                          onPressed: () =>
                              Scaffold.of(scaffoldContext).openDrawer(),
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Search bar — shows "Viaje en curso" when locked
                      Expanded(
                        child: GestureDetector(
                          onTap:
                              _hasActiveTrip ? null : _openSearchScreen,
                          child: Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppTheme.darkSurface
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _hasActiveTrip
                                      ? Icons.directions_car
                                      : Icons.search,
                                  color: _hasActiveTrip
                                      ? AppTheme.primaryColor
                                      : (isDark
                                          ? Colors.white54
                                          : Colors.grey[600]),
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _hasActiveTrip
                                        ? 'Viaje en curso...'
                                        : '¿A donde vas?',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 15,
                                      color: _hasActiveTrip
                                          ? AppTheme.primaryColor
                                          : (isDark
                                              ? Colors.white54
                                              : Colors.grey[600]),
                                      fontWeight: _hasActiveTrip
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (_hasActiveTrip)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppTheme.success,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildCircleButton(
                        icon: Icons.notifications_outlined,
                        onPressed: () {},
                        isDark: isDark,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Quick chips — hidden during active trip
                  if (!_hasActiveTrip)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (int i = 0;
                              i < addressProvider.addresses.length && i < 5;
                              i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            _buildQuickDestinationPill(
                              icon: _iconForName(
                                  addressProvider.addresses[i].icon),
                              label: addressProvider.addresses[i].label,
                              isDark: isDark,
                              onTap: () async {
                                final addr =
                                    addressProvider.addresses[i];
                                final tp =
                                    context.read<TransportProvider>();
                                final lp =
                                    context.read<LocationProvider>();
                                final nav = Navigator.of(context);
                                tp.setPickup(lp.locationOrDefault,
                                    address: 'Ubicación actual');
                                tp.setDropoff(
                                  LatLng(addr.latitud, addr.longitud),
                                  address: addr.direccion,
                                );
                                await tp.calculateRoute();
                                if (mounted) {
                                  nav.pushNamed('/client/route-preview');
                                }
                              },
                            ),
                          ],
                          if (addressProvider.addresses.length < 5) ...[
                            if (addressProvider.addresses.isNotEmpty)
                              const SizedBox(width: 8),
                            _buildQuickDestinationPill(
                              icon: Icons.add_location_alt_outlined,
                              label: 'Agregar',
                              isDark: isDark,
                              onTap: () => Navigator.pushNamed(
                                  context, '/client/saved-addresses'),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // GPS error banner (rendered above top bar so it's visible)
          if (locationError != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: GestureDetector(
                  onTap: () async {
                    if (locationError.contains('denegado') ||
                        locationError.contains('permiso')) {
                      await Geolocator.openAppSettings();
                    } else {
                      await Geolocator.openLocationSettings();
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_off,
                            color: Colors.white, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            locationError,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Activar',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            decoration: TextDecoration.underline,
                            decorationColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Right side floating buttons
          Positioned(
            right: 16,
            bottom: _hasActiveTrip ? 240 : 280,
            child: Column(
              children: [
                if (_hasActiveTrip) ...[
                  _buildNavModeButton(
                    icon: _autoRotate
                        ? Icons.explore
                        : Icons.explore_off,
                    isActive: _autoRotate,
                    onPressed: _toggleAutoRotate,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 10),
                  _buildNavModeButton(
                    icon: Icons.view_in_ar,
                    isActive: _tilt3D,
                    onPressed: _toggle3DTilt,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 10),
                ],
                _buildCircleButton(
                  icon: Icons.my_location,
                  onPressed: _centerOnUser,
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _buildCircleButton(
                  icon: Icons.layers_outlined,
                  onPressed: () =>
                      context.read<ThemeProvider>().toggleTheme(),
                  isDark: isDark,
                ),
              ],
            ),
          ),

          // ── Loading indicator while checking active trip ──────────────
          if (_checkingActiveTrip)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.15),
                child: const Center(
                  child: CircularProgressIndicator(
                      color: AppTheme.primaryColor),
                ),
              ),
            ),

          // ── Active trip bottom panel ──────────────────────────────────
          if (_hasActiveTrip && !_checkingActiveTrip)
            _buildActiveTripPanel(isDark)
          // ── Normal bottom sheet ───────────────────────────────────────
          else if (!_checkingActiveTrip)
            _buildNormalBottomSheet(isDark, transportProvider),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentNavIndex,
        onTap: (index) {
          if (index == 0) {
            setState(() => _currentNavIndex = 0);
            return;
          }
          setState(() => _currentNavIndex = index);
          switch (index) {
            case 1:
              Navigator.pushNamed(context, '/client/request-history').then((_) => _refreshAfterNav());
              break;
            case 2:
              Navigator.pushNamed(context, '/client/wallet').then((_) => _refreshAfterNav());
              break;
            case 3:
              Navigator.pushNamed(context, '/client/profile').then((_) => _refreshAfterNav());
              break;
          }
          Future.microtask(() {
            if (mounted) setState(() => _currentNavIndex = 0);
          });
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor:
            context.watch<ThemeProvider>().isDark
                ? AppTheme.darkSurface
                : Colors.white,
        selectedItemColor: AppTheme.primaryColor,
        unselectedItemColor:
            context.watch<ThemeProvider>().isDark
                ? Colors.white54
                : Colors.grey,
        selectedLabelStyle: GoogleFonts.plusJakartaSans(
            fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(
            fontSize: 12, fontWeight: FontWeight.w400),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_outlined),
              activeIcon: Icon(Icons.receipt_long),
              label: 'Actividad'),
          BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_outlined),
              activeIcon: Icon(Icons.account_balance_wallet),
              label: 'Billetera'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Perfil'),
        ],
      ),
    );
  }

  // ── Active trip bottom panel ────────────────────────────────────────────
  Widget _buildActiveTripPanel(bool isDark) {
    final solicitud = _activeSolicitud!;
    final estado = solicitud['estado'] as String? ?? 'pendiente';
    final destAddress =
        solicitud['direccion_destino'] as String? ?? 'Destino';

    final driverData =
        _activeSolicitudDriver?['drivers'] as Map<String, dynamic>?;
    final driverName = driverData?['name'] as String? ?? 'Buscando conductor...';
    final driverImage = driverData?['image'] as String?;
    final veh = driverData?['vehiculos'] as Map<String, dynamic>?;
    final vehicleInfo = [
      veh?['marca'] as String? ?? '',
      veh?['modelo'] as String? ?? '',
      veh?['color'] as String? ?? '',
    ].where((s) => s.isNotEmpty).join(' ');
    final chapa = veh?['chapa'] as String? ?? '';
    final eta = _activeSolicitudDriver?['tiempo_estimado'] as int? ?? 0;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : Colors.white,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Status row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: estado == 'aceptada'
                          ? AppTheme.success.withValues(alpha: 0.15)
                          : AppTheme.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: estado == 'aceptada'
                                ? AppTheme.success
                                : AppTheme.warning,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          estado == 'aceptada'
                              ? 'Conductor en camino'
                              : 'Buscando conductor',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: estado == 'aceptada'
                                ? AppTheme.success
                                : AppTheme.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (eta > 0)
                    Text(
                      '$eta min',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Destination row
              Row(
                children: [
                  Icon(Icons.flag_outlined,
                      color: AppTheme.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      destAddress,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color:
                            isDark ? Colors.white70 : Colors.grey[700],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Driver info (if accepted)
              if (estado == 'aceptada') ...[
                Row(
                  children: [
                    // Avatar
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.primaryColor.withValues(alpha: 0.2),
                        border:
                            Border.all(color: AppTheme.primaryColor, width: 2),
                        image: driverImage != null
                            ? DecorationImage(
                                image: NetworkImage(driverImage),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: driverImage == null
                          ? const Icon(Icons.person,
                              color: AppTheme.primaryColor, size: 24)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            driverName,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color:
                                  isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          if (vehicleInfo.isNotEmpty)
                            Text(
                              vehicleInfo,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white60
                                    : Colors.grey[600],
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (chapa.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppTheme.darkCard
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isDark
                                ? AppTheme.darkBorder
                                : Colors.grey[300]!,
                          ),
                        ),
                        child: Text(
                          chapa,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
              ],

              // Action buttons
              Row(
                children: [
                  // Go to ride confirmed screen
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          // Restore provider state so RideConfirmedScreen has driver data
                          if (_activeSolicitud != null) {
                            final request = TransportRequestModel.fromJson(
                                _activeSolicitud!);
                            await context
                                .read<TransportProvider>()
                                .restoreAcceptedRide(request);
                          }
                          if (!mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const RideConfirmedScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: Text(
                          'Ver viaje',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ── Normal bottom sheet ─────────────────────────────────────────────────
  Widget _buildNormalBottomSheet(
      bool isDark, TransportProvider transportProvider) {
    return DraggableScrollableSheet(
      initialChildSize: 0.35,
      minChildSize: 0.06,
      maxChildSize: 0.55,
      snap: true,
      snapSizes: const [0.06, 0.35, 0.55],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Elige tu transporte',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              if (transportProvider.loadingVehicleTypes)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryColor,
                      strokeWidth: 2.5,
                    ),
                  ),
                )
              else
                ...transportProvider.vehicleTypes.map((vt) {
                  final isSelected =
                      transportProvider.selectedVehicleType?.id == vt.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TransportTypeCard(
                      vehicleType: vt.displayName,
                      icon: vt.icon,
                      passengerCount: vt.passengerCount,
                      price: vt.precioKmDefault,
                      eta:
                          '${vt.tiempoMinPorKm.toStringAsFixed(1)} min/km',
                      isSelected: isSelected,
                      onTap: () => context
                          .read<TransportProvider>()
                          .setVehicleType(vt),
                    ),
                  );
                }),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkCard : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? AppTheme.darkBorder
                        : Colors.grey[300]!,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.payments_outlined,
                        color: AppTheme.success, size: 22),
                    const SizedBox(width: 12),
                    Text(
                      'Efectivo',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.chevron_right,
                        color: isDark ? Colors.white38 : Colors.grey),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────
  IconData _iconForName(String name) {
    switch (name) {
      case 'home':
        return Icons.home_outlined;
      case 'work':
        return Icons.work_outlined;
      case 'school':
        return Icons.school_outlined;
      case 'gym':
        return Icons.fitness_center_outlined;
      case 'star':
        return Icons.star_outline;
      default:
        return Icons.place_outlined;
    }
  }

  Widget _buildNavModeButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onPressed,
    required bool isDark,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: isActive
            ? AppTheme.primaryColor
            : (isDark ? AppTheme.darkSurface : Colors.white),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: isActive
                ? AppTheme.primaryColor.withValues(alpha: 0.4)
                : Colors.black.withValues(alpha: 0.15),
            blurRadius: isActive ? 12 : 6,
            spreadRadius: isActive ? 2 : 0,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: isActive
                  ? Colors.white
                  : (isDark ? Colors.white70 : Colors.black54),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onPressed,
    required bool isDark,
  }) {
    return Material(
      color: isDark ? AppTheme.darkSurface : Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Icon(
            icon,
            color: isDark ? Colors.white : Colors.black87,
            size: 22,
          ),
        ),
      ),
    );
  }

  Widget _buildQuickDestinationPill({
    required IconData icon,
    required String label,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppTheme.primaryColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pulsing blue dot marker for the user's location.
class _PulsingDot extends AnimatedWidget {
  const _PulsingDot({required Animation<double> animation})
      : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    final value = (listenable as Animation<double>).value;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.primaryColor.withValues(alpha: value * 0.3),
      ),
      child: Center(
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.primaryColor,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withValues(alpha: 0.4),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

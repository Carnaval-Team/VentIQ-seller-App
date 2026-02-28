import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_theme.dart';
import '../../models/notification_model.dart';
import '../../providers/location_provider.dart';
import '../../providers/transport_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/notification_service.dart';
import '../../services/routing_service.dart';
import '../../utils/helpers.dart';
import '../../widgets/map_widget.dart';

class RideConfirmedScreen extends StatefulWidget {
  const RideConfirmedScreen({super.key});

  @override
  State<RideConfirmedScreen> createState() => _RideConfirmedScreenState();
}

class _RideConfirmedScreenState extends State<RideConfirmedScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Real driver position polled from muevete.place
  LatLng? _driverPosition;
  Timer? _locationPollTimer;
  bool _isCompleting = false;

  // Real-time client tracking
  List<LatLng> _clientTrail = []; // breadcrumb trail (grey)
  List<LatLng> _currentRoute = []; // current optimal route to destination
  double _distanceToDestinationM = double.infinity;
  static const double _completeThresholdM = 30.0;
  bool _isRecalculating = false;
  Timer? _routeRefreshTimer; // periodic fallback every 10s

  final RoutingService _routingService = RoutingService();

  LatLng? _lastClientPosition;
  double _clientBearing = 0.0;
  bool _clientIsMoving = false;

  // Whether the driver has started the trip (hide driver marker from map)
  bool _tripStarted = false;
  StreamSubscription<NotificationModel>? _notifSubscription;

  // Driver-to-client route (shown while driver is on the way)
  List<LatLng> _driverToClientRoute = [];
  double _driverEtaSeconds = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Listen for "trip started" notification to hide driver marker
    _notifSubscription =
        NotificationService().notificationStream.listen((notif) {
      if (notif.tipo == NotificationType.viajeIniciado && mounted) {
        setState(() {
          _tripStarted = true;
          _driverToClientRoute = [];
          _driverEtaSeconds = 0;
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startDriverTracking();
      _startClientTracking();
      // Periodic fallback: recalculate route every 10s regardless of movement
      _routeRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (!mounted) return;
        final loc = context.read<LocationProvider>().currentLocation ??
            context.read<LocationProvider>().locationOrDefault;
        _forceRecalculateRoute(loc);
      });
    });
  }

  // ─── Driver tracking (poll every 8s) ────────────────────────────────────
  Future<void> _startDriverTracking() async {
    final driverId =
        context.read<TransportProvider>().acceptedOffer?.driverId;
    if (driverId == null) return;
    await _pollDriverPosition(driverId);
    _locationPollTimer =
        Timer.periodic(const Duration(seconds: 8), (_) async {
      if (!mounted) return;
      await _pollDriverPosition(driverId);
    });
  }

  Future<void> _pollDriverPosition(int driverId) async {
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
          final newPos = LatLng(lat, lon);
          setState(() => _driverPosition = newPos);
          // Recalculate driver-to-client route when trip hasn't started
          if (!_tripStarted) {
            _recalculateDriverToClientRoute(newPos);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _recalculateDriverToClientRoute(LatLng driverPos) async {
    final clientPos = _lastClientPosition;
    if (clientPos == null) return;
    try {
      final result = await _routingService.getRoute(driverPos, clientPos);
      if (mounted) {
        setState(() {
          _driverToClientRoute = result.polyline;
          _driverEtaSeconds = result.totalDuration;
        });
      }
    } catch (_) {}
  }

  // ─── Client real-time tracking ───────────────────────────────────────────
  void _startClientTracking() {
    final locationProvider = context.read<LocationProvider>();

    // Use current fix or fallback default — always seed immediately
    final current =
        locationProvider.currentLocation ?? locationProvider.locationOrDefault;
    _lastClientPosition = current;
    _clientTrail = [current];
    // First route calculation — no throttle guard
    _forceRecalculateRoute(current);

    // Listen to every GPS update
    locationProvider.addListener(_onClientPositionUpdate);
  }

  void _onClientPositionUpdate() {
    if (!mounted) return;
    final loc = context.read<LocationProvider>().currentLocation;
    if (loc == null) return;

    // Accumulate trail on any movement > 2m
    if (_lastClientPosition != null &&
        _haversineMeters(_lastClientPosition!, loc) < 2) {
      // Still update distance even if not moving much
      _updateDistance(loc);
      return;
    }
    // Calculate bearing
    if (_lastClientPosition != null) {
      final b = _calcBearing(_lastClientPosition!, loc);
      _clientBearing = b;
      _clientIsMoving = true;
    }
    _lastClientPosition = loc;

    setState(() {
      _clientTrail.add(loc);
      if (_clientTrail.length > 500) _clientTrail.removeAt(0);
    });

    // Auto-center map on client position
    try {
      _mapController.move(loc, _mapController.camera.zoom);
    } catch (_) {}

    _updateDistance(loc);

    // Recalculate only when not already in flight
    if (!_isRecalculating) {
      _forceRecalculateRoute(loc);
    }
  }

  void _updateDistance(LatLng loc) {
    final dest = context.read<TransportProvider>().dropoffLocation;
    if (dest == null) return;
    final dist = _haversineMeters(loc, dest);
    if (mounted) setState(() => _distanceToDestinationM = dist);
  }

  /// Always fires a route recalculation, bypassing the _isRecalculating guard.
  /// Used for the initial seed and the periodic timer fallback.
  Future<void> _forceRecalculateRoute(LatLng from) async {
    final dest = context.read<TransportProvider>().dropoffLocation;
    if (dest == null) return;
    _isRecalculating = true;
    try {
      final result = await _routingService.getRoute(from, dest);
      if (mounted) {
        setState(() => _currentRoute = result.polyline);
      }
    } catch (_) {
      // Keep previous route on error
    }
    // Always reset — even if catch fires
    _isRecalculating = false;
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

  double _calcBearing(LatLng from, LatLng to) {
    final dLon = (to.longitude - from.longitude) * pi / 180;
    final lat1 = from.latitude * pi / 180;
    final lat2 = to.latitude * pi / 180;
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    return atan2(y, x);
  }

  // ─── Complete ride ───────────────────────────────────────────────────────
  Future<void> _completeRide() async {
    final tp = context.read<TransportProvider>();
    final requestId = tp.activeRequest?.id;
    if (requestId == null || _isCompleting) return;
    setState(() => _isCompleting = true);
    try {
      await Supabase.instance.client
          .schema('muevete')
          .from('solicitudes_transporte')
          .update({'estado': 'completada'})
          .eq('id', requestId);
      if (mounted) {
        tp.resetTrip();
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isCompleting = false);
    }
  }

  @override
  void dispose() {
    _notifSubscription?.cancel();
    _pulseController.dispose();
    _locationPollTimer?.cancel();
    _routeRefreshTimer?.cancel();
    _mapController.dispose();
    try {
      context.read<LocationProvider>().removeListener(_onClientPositionUpdate);
    } catch (_) {}
    super.dispose();
  }

  Future<void> _launchCall(String phone) async {
    final url = Uri.parse(Helpers.buildPhoneUrl(phone));
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _launchWhatsApp(String phone) async {
    final url = Uri.parse(
      Helpers.buildWhatsAppUrl(phone, message: 'Hola, soy tu pasajero'),
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final transportProvider = context.watch<TransportProvider>();
    final locationProvider = context.watch<LocationProvider>();
    final isDark = themeProvider.isDark;

    final acceptedOffer = transportProvider.acceptedOffer;
    final pickup = transportProvider.pickupLocation;
    final dropoff = transportProvider.dropoffLocation;
    final userLocation = locationProvider.locationOrDefault;

    // Driver info from accepted offer (real data from DB)
    final driverName = acceptedOffer?.driverName ?? 'Conductor';
    final driverImage = acceptedOffer?.driverImage;
    final driverPhone = acceptedOffer?.driverPhone ?? '';
    final driverKyc = acceptedOffer?.driverKyc ?? false;
    final marca = acceptedOffer?.vehicleMarca ?? '';
    final modelo = acceptedOffer?.vehicleModelo ?? '';
    final chapa = acceptedOffer?.vehicleChapa ?? '';
    final color = acceptedOffer?.vehicleColor ?? '';
    final tripCount = acceptedOffer?.tripCount ?? 0;
    final vehicleInfo =
        [marca, modelo, color].where((s) => s.isNotEmpty).join(' ');
    final staticEta = acceptedOffer?.tiempoEstimado ?? 0;
    // Use real-time driver ETA when available, else static offer ETA
    final driverEtaMin = _driverEtaSeconds > 0
        ? (_driverEtaSeconds / 60).ceil()
        : staticEta;

    // Can complete?
    final canComplete = _distanceToDestinationM <= _completeThresholdM;
    final distStr = _distanceToDestinationM == double.infinity
        ? '—'
        : _distanceToDestinationM < 1000
            ? '${_distanceToDestinationM.toStringAsFixed(0)} m'
            : '${(_distanceToDestinationM / 1000).toStringAsFixed(2)} km';

    // Build markers
    final markers = <Marker>[];
    // Pickup marker
    if (pickup != null) {
      markers.add(
        Marker(
          point: pickup,
          width: 40,
          height: 40,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.success,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: const Icon(
              Icons.my_location,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      );
    }
    // Destination marker
    if (dropoff != null) {
      markers.add(
        Marker(
          point: dropoff,
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
            child: const Icon(
              Icons.flag,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      );
    }

    // Client current position marker — directional arrow when moving
    markers.add(
      Marker(
        point: userLocation,
        width: 40,
        height: 40,
        child: _clientIsMoving
            ? Transform.rotate(
                angle: _clientBearing,
                child: Container(
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
                  child: const Icon(
                    Icons.navigation,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              )
            : _PulsingDot(animation: _pulseAnimation),
      ),
    );

    // Driver marker with name label (hidden once trip starts)
    if (_driverPosition != null && !_tripStarted) {
      markers.add(
        Marker(
          point: _driverPosition!,
          width: 80,
          height: 80,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 6,
                    ),
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
                      color: AppTheme.primaryColor
                          .withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.directions_car,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Build polylines
    final polylines = <Polyline>[];

    // Grey breadcrumb trail (visited path)
    if (_clientTrail.length >= 2) {
      polylines.add(
        Polyline(
          points: List.from(_clientTrail),
          strokeWidth: 4.0,
          color: Colors.grey.withValues(alpha: 0.7),
        ),
      );
    }

    // Orange driver-to-client route (while driver is on the way)
    if (!_tripStarted && _driverToClientRoute.length >= 2) {
      polylines.add(
        Polyline(
          points: _driverToClientRoute,
          strokeWidth: 8.0,
          color: AppTheme.warning.withValues(alpha: 0.2),
        ),
      );
      polylines.add(
        Polyline(
          points: _driverToClientRoute,
          strokeWidth: 4.0,
          color: AppTheme.warning,
        ),
      );
    }

    // Blue current route to destination — glow layer + solid
    if (_currentRoute.isNotEmpty) {
      polylines.add(
        Polyline(
          points: _currentRoute,
          strokeWidth: 10.0,
          color: AppTheme.primaryColor.withValues(alpha: 0.2),
        ),
      );
      polylines.add(
        Polyline(
          points: _currentRoute,
          strokeWidth: 4.5,
          color: AppTheme.primaryColor,
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // Map with route
          MapWidget(
            isDark: isDark,
            mapController: _mapController,
            center: userLocation,
            zoom: 15.0,
            markers: markers,
            polylines: polylines,
          ),

          // Top status bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16.0, vertical: 12),
              child: Row(
                children: [
                  // Back button
                  _buildTopButton(
                    icon: Icons.arrow_back,
                    isDark: isDark,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  // ETA + distance status bar
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppTheme.darkSurface.withValues(alpha: 0.95)
                            : Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color:
                                Colors.black.withValues(alpha: 0.15),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _AnimatedPulseDot(
                              animation: _pulseAnimation),
                          const SizedBox(width: 8),
                          Text(
                            _tripStarted
                                ? 'Viaje en curso'
                                : 'Conductor llega en $driverEtaMin min',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : Colors.black87,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: 1,
                            height: 16,
                            color: isDark ? Colors.white24 : Colors.grey[300],
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.place_outlined,
                            size: 14,
                            color: isDark ? Colors.white54 : Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            distStr,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: canComplete
                                  ? AppTheme.success
                                  : (isDark
                                      ? Colors.white70
                                      : Colors.grey[700]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Safety shield button
                  _buildTopButton(
                    icon: Icons.shield_outlined,
                    isDark: isDark,
                    onTap: () {
                      // Open safety features
                    },
                  ),
                ],
              ),
            ),
          ),

          // Bottom driver card
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurface : Colors.white,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
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
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white24
                              : Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Driver info row
                    Row(
                      children: [
                        // Driver avatar
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.primaryColor
                                .withValues(alpha: 0.2),
                            border: Border.all(
                              color: AppTheme.primaryColor,
                              width: 2,
                            ),
                            image: driverImage != null
                                ? DecorationImage(
                                    image:
                                        NetworkImage(driverImage),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: driverImage == null
                              ? const Icon(
                                  Icons.person,
                                  color: AppTheme.primaryColor,
                                  size: 28,
                                )
                              : null,
                        ),
                        const SizedBox(width: 14),
                        // Driver details
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      driverName,
                                      style:
                                          GoogleFonts.plusJakartaSans(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                      overflow:
                                          TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (driverKyc)
                                    Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTheme.success
                                            .withValues(alpha: 0.15),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize:
                                            MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.verified,
                                            color: AppTheme.success,
                                            size: 12,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            'Verificado',
                                            style: GoogleFonts
                                                .plusJakartaSans(
                                              fontSize: 10,
                                              fontWeight:
                                                  FontWeight.w600,
                                              color:
                                                  AppTheme.success,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              // Vehicle info
                              Text(
                                vehicleInfo,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  // Rating
                                  const Icon(
                                    Icons.star,
                                    color: AppTheme.warning,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '—',
                                    style:
                                        GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Ride count
                                  Icon(
                                    Icons
                                        .directions_car_outlined,
                                    size: 14,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.grey[500],
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '$tripCount viajes',
                                    style:
                                        GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.white54
                                          : Colors.grey[500],
                                    ),
                                  ),
                                  const Spacer(),
                                  // Plate number
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? AppTheme.darkCard
                                          : Colors.grey[100],
                                      borderRadius:
                                          BorderRadius.circular(
                                              6),
                                      border: Border.all(
                                        color: isDark
                                            ? AppTheme.darkBorder
                                            : Colors.grey[300]!,
                                      ),
                                    ),
                                    child: Text(
                                      chapa.isNotEmpty ? chapa : '—',
                                      style: GoogleFonts
                                          .plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Chat preview bubble — show only if driver sent a message
                    if ((acceptedOffer?.mensaje ?? '').isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppTheme.darkCard
                              : Colors.grey[50],
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark
                                ? AppTheme.darkBorder
                                : Colors.grey[200]!,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 18,
                              color: isDark
                                  ? Colors.white54
                                  : Colors.grey[500],
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                acceptedOffer!.mensaje!,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.grey[700],
                                  fontStyle: FontStyle.italic,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    // Action buttons
                    Row(
                      children: [
                        // Call button
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  _launchCall(driverPhone),
                              icon:
                                  const Icon(Icons.phone, size: 20),
                              label: Text(
                                'Llamar Conductor',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // WhatsApp button
                        SizedBox(
                          height: 50,
                          width: 110,
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                _launchWhatsApp(driverPhone),
                            icon:
                                const Icon(Icons.chat, size: 20),
                            label: Text(
                              'WhatsApp',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFF25D366),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Complete ride button — locked until within 30m
                    Tooltip(
                      message: canComplete
                          ? ''
                          : 'Debes estar a menos de 30 m del destino',
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed:
                              (canComplete && !_isCompleting)
                                  ? _completeRide
                                  : null,
                          icon: _isCompleting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  canComplete
                                      ? Icons.check_circle_outline
                                      : Icons.lock_outline,
                                  size: 20,
                                ),
                          label: Text(
                            _isCompleting
                                ? 'Completando...'
                                : canComplete
                                    ? 'Completar viaje'
                                    : 'Faltan $distStr para completar',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: canComplete
                                ? AppTheme.success
                                : Colors.grey[400],
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                Colors.grey[400],
                            disabledForegroundColor:
                                Colors.white70,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopButton({
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isDark ? AppTheme.darkSurface : Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      child: InkWell(
        onTap: onTap,
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
}

/// Pulsing blue dot for client position.
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

/// Animated green pulse dot for the "Llega en X min" status.
class _AnimatedPulseDot extends AnimatedWidget {
  const _AnimatedPulseDot({required Animation<double> animation})
      : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    final animation = listenable as Animation<double>;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.success.withValues(alpha: animation.value),
        boxShadow: [
          BoxShadow(
            color: AppTheme.success
                .withValues(alpha: animation.value * 0.5),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_theme.dart';
import '../../providers/location_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/routing_service.dart';
import '../../utils/helpers.dart';
import '../../widgets/map_widget.dart';

enum _RidePhase { goingToPickup, waitingAtPickup, inProgress, completed }

class ActiveRideScreen extends StatefulWidget {
  final Map<String, dynamic>? tripData;

  const ActiveRideScreen({super.key, this.tripData});

  @override
  State<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends State<ActiveRideScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  final RoutingService _routingService = RoutingService();

  _RidePhase _currentPhase = _RidePhase.goingToPickup;
  List<LatLng> _routePolyline = [];
  bool _isLoadingRoute = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Placeholder client data (from tripData or defaults)
  late String _clientName;
  late String _clientPhone;
  late String _pickupAddress;
  late String _dropoffAddress;
  late double _tripPrice;
  LatLng? _pickupLocation;
  LatLng? _dropoffLocation;

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

    // Extract trip data
    final data = widget.tripData ?? {};
    _clientName = data['client_name'] as String? ?? 'Carlos Martinez';
    _clientPhone = data['client_phone'] as String? ?? '+5350001234';
    _pickupAddress =
        data['direccion_origen'] as String? ?? 'Punto de recogida';
    _dropoffAddress =
        data['direccion_destino'] as String? ?? 'Destino del viaje';
    _tripPrice = (data['precio'] as num?)?.toDouble() ?? 0.0;

    final latOrigen = (data['lat_origen'] as num?)?.toDouble();
    final lonOrigen = (data['lon_origen'] as num?)?.toDouble();
    final latDestino = (data['lat_destino'] as num?)?.toDouble();
    final lonDestino = (data['lon_destino'] as num?)?.toDouble();

    if (latOrigen != null && lonOrigen != null) {
      _pickupLocation = LatLng(latOrigen, lonOrigen);
    }
    if (latDestino != null && lonDestino != null) {
      _dropoffLocation = LatLng(latDestino, lonDestino);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRoute();
    });
  }

  Future<void> _loadRoute() async {
    final locationProvider = context.read<LocationProvider>();
    final driverLocation = locationProvider.locationOrDefault;

    // Determine route endpoints based on phase
    LatLng start = driverLocation;
    LatLng? end;

    if (_currentPhase == _RidePhase.goingToPickup ||
        _currentPhase == _RidePhase.waitingAtPickup) {
      end = _pickupLocation ?? driverLocation;
    } else if (_currentPhase == _RidePhase.inProgress) {
      start = _pickupLocation ?? driverLocation;
      end = _dropoffLocation;
    }

    if (end == null) return;

    setState(() {
      _isLoadingRoute = true;
    });

    try {
      final result = await _routingService.getRoute(start, end);
      if (mounted) {
        setState(() {
          _routePolyline = result.polyline;
          _isLoadingRoute = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _routePolyline = [start, end!];
          _isLoadingRoute = false;
        });
      }
    }
  }

  void _advancePhase() {
    setState(() {
      switch (_currentPhase) {
        case _RidePhase.goingToPickup:
          _currentPhase = _RidePhase.waitingAtPickup;
          break;
        case _RidePhase.waitingAtPickup:
          _currentPhase = _RidePhase.inProgress;
          _loadRoute(); // Recalculate route pickup -> dropoff
          break;
        case _RidePhase.inProgress:
          _currentPhase = _RidePhase.completed;
          _showCompletionDialog();
          break;
        case _RidePhase.completed:
          break;
      }
    });
  }

  String _getPhaseLabel() {
    switch (_currentPhase) {
      case _RidePhase.goingToPickup:
        return 'Rumbo al punto de recogida';
      case _RidePhase.waitingAtPickup:
        return 'Esperando al pasajero';
      case _RidePhase.inProgress:
        return 'Viaje en curso';
      case _RidePhase.completed:
        return 'Viaje completado';
    }
  }

  String _getActionButtonLabel() {
    switch (_currentPhase) {
      case _RidePhase.goingToPickup:
        return 'Llegue al punto';
      case _RidePhase.waitingAtPickup:
        return 'Iniciar Viaje';
      case _RidePhase.inProgress:
        return 'Completar Viaje';
      case _RidePhase.completed:
        return 'Finalizado';
    }
  }

  Color _getPhaseColor() {
    switch (_currentPhase) {
      case _RidePhase.goingToPickup:
        return AppTheme.primaryColor;
      case _RidePhase.waitingAtPickup:
        return AppTheme.warning;
      case _RidePhase.inProgress:
        return AppTheme.success;
      case _RidePhase.completed:
        return AppTheme.success;
    }
  }

  IconData _getPhaseIcon() {
    switch (_currentPhase) {
      case _RidePhase.goingToPickup:
        return Icons.navigation;
      case _RidePhase.waitingAtPickup:
        return Icons.hourglass_top;
      case _RidePhase.inProgress:
        return Icons.directions_car;
      case _RidePhase.completed:
        return Icons.check_circle;
    }
  }

  void _showCompletionDialog() {
    final isDark = context.read<ThemeProvider>().isDark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.success.withValues(alpha: 0.15),
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: AppTheme.success,
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Viaje Completado',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Has completado el viaje exitosamente.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: isDark ? Colors.white60 : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                Helpers.formatCurrency(_tripPrice),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.success,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Volver al Inicio',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _launchCall(String phone) async {
    final url = Uri.parse(Helpers.buildPhoneUrl(phone));
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _launchWhatsApp(String phone) async {
    final url = Uri.parse(
      Helpers.buildWhatsAppUrl(phone,
          message: 'Hola, soy tu conductor de Muevete'),
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final locationProvider = context.watch<LocationProvider>();
    final isDark = themeProvider.isDark;

    final driverLocation = locationProvider.locationOrDefault;
    final phaseColor = _getPhaseColor();

    // Build markers
    final markers = <Marker>[];

    // Driver marker
    markers.add(
      Marker(
        point: driverLocation,
        width: 46,
        height: 46,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.primaryColor,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withValues(alpha: 0.4),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Icon(
            Icons.directions_car,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );

    // Pickup marker
    if (_pickupLocation != null) {
      markers.add(
        Marker(
          point: _pickupLocation!,
          width: 40,
          height: 40,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.success,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: const Icon(
              Icons.person_pin_circle,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      );
    }

    // Dropoff marker
    if (_dropoffLocation != null) {
      markers.add(
        Marker(
          point: _dropoffLocation!,
          width: 40,
          height: 40,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.error,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: const Icon(
              Icons.flag,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      );
    }

    // Build polylines
    final polylines = <Polyline>[];
    if (_routePolyline.isNotEmpty) {
      polylines.add(
        Polyline(
          points: _routePolyline,
          strokeWidth: 4.0,
          color: phaseColor,
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // Map
          MapWidget(
            isDark: isDark,
            mapController: _mapController,
            center: _pickupLocation ?? driverLocation,
            zoom: 15.0,
            markers: markers,
            polylines: polylines,
          ),

          // Loading overlay for route
          if (_isLoadingRoute)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkSurface.withValues(alpha: 0.9)
                        : Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Calculando ruta...',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: isDark ? Colors.white70 : Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Top status bar
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
              child: Row(
                children: [
                  // Back button
                  _buildTopButton(
                    icon: Icons.arrow_back,
                    isDark: isDark,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  // Phase status bar
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
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _AnimatedPulseDot(
                            animation: _pulseAnimation,
                            color: phaseColor,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _getPhaseLabel(),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color:
                                    isDark ? Colors.white : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Phase icon button
                  _buildTopButton(
                    icon: _getPhaseIcon(),
                    isDark: isDark,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),

          // Bottom card with client info and actions
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurface : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
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
                          color:
                              isDark ? Colors.white24 : Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Client info row
                    Row(
                      children: [
                        // Client avatar
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.primaryColor
                                .withValues(alpha: 0.2),
                            border: Border.all(
                              color: AppTheme.primaryColor,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.person,
                            color: AppTheme.primaryColor,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        // Client details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _clientName,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _currentPhase == _RidePhase.inProgress
                                    ? _dropoffAddress
                                    : _pickupAddress,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // Trip price badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            Helpers.formatCurrency(_tripPrice),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.success,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Address info
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color:
                            isDark ? AppTheme.darkCard : Colors.grey[50],
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? AppTheme.darkBorder
                              : Colors.grey[200]!,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.circle,
                                  color: AppTheme.success, size: 10),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _pickupAddress,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.9)
                                        : Colors.grey[800],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.only(left: 4, top: 4, bottom: 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                width: 1,
                                height: 16,
                                color: isDark
                                    ? Colors.white24
                                    : Colors.grey[300],
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              const Icon(Icons.circle,
                                  color: AppTheme.error, size: 10),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _dropoffAddress,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.9)
                                        : Colors.grey[800],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Communication buttons + Action button
                    Row(
                      children: [
                        // Call button
                        SizedBox(
                          height: 50,
                          width: 50,
                          child: ElevatedButton(
                            onPressed: () => _launchCall(_clientPhone),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark
                                  ? AppTheme.darkCard
                                  : Colors.grey[100],
                              foregroundColor: isDark
                                  ? Colors.white
                                  : Colors.black87,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: EdgeInsets.zero,
                              elevation: 0,
                            ),
                            child: const Icon(Icons.phone, size: 22),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // WhatsApp button
                        SizedBox(
                          height: 50,
                          width: 50,
                          child: ElevatedButton(
                            onPressed: () =>
                                _launchWhatsApp(_clientPhone),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF25D366),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: EdgeInsets.zero,
                              elevation: 0,
                            ),
                            child: const Icon(Icons.chat, size: 22),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Main action button
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed:
                                  _currentPhase == _RidePhase.completed
                                      ? null
                                      : _advancePhase,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: phaseColor,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    AppTheme.success.withValues(alpha: 0.5),
                                disabledForegroundColor:
                                    Colors.white.withValues(alpha: 0.7),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                _getActionButtonLabel(),
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
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

/// Animated pulse dot for the phase status bar.
class _AnimatedPulseDot extends AnimatedWidget {
  final Color color;

  const _AnimatedPulseDot({
    required Animation<double> animation,
    this.color = AppTheme.success,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    final animation = listenable as Animation<double>;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: animation.value),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: animation.value * 0.5),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

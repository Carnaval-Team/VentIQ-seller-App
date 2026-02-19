import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_theme.dart';
import '../../providers/location_provider.dart';
import '../../providers/transport_provider.dart';
import '../../providers/theme_provider.dart';
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

  // Simulated driver position (moving toward pickup)
  LatLng? _driverPosition;
  Timer? _driverMovementTimer;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startDriverSimulation();
    });
  }

  void _startDriverSimulation() {
    final transportProvider = context.read<TransportProvider>();
    final pickup = transportProvider.pickupLocation;
    if (pickup == null) return;

    // Start driver slightly away from pickup
    _driverPosition = LatLng(
      pickup.latitude + 0.005,
      pickup.longitude + 0.003,
    );

    _driverMovementTimer =
        Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_driverPosition == null || !mounted) {
        timer.cancel();
        return;
      }

      final currentPickup =
          context.read<TransportProvider>().pickupLocation;
      if (currentPickup == null) return;

      setState(() {
        // Move driver closer to pickup
        final latDiff =
            currentPickup.latitude - _driverPosition!.latitude;
        final lonDiff =
            currentPickup.longitude - _driverPosition!.longitude;
        _driverPosition = LatLng(
          _driverPosition!.latitude + latDiff * 0.15,
          _driverPosition!.longitude + lonDiff * 0.15,
        );
      });
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _driverMovementTimer?.cancel();
    _mapController.dispose();
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
    final polyline = transportProvider.routePolyline;
    final userLocation = locationProvider.locationOrDefault;

    // Driver info from accepted offer
    final driverName = acceptedOffer?.driverName ?? 'Ricardo';
    final driverImage = acceptedOffer?.driverImage;
    final vehicleInfo = acceptedOffer?.vehicleInfo ?? 'Toyota Corolla Gris';
    final eta = acceptedOffer?.tiempoEstimado ?? 4;
    const driverPhone = '+5350001234'; // Placeholder

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
    // Driver marker with name label
    if (_driverPosition != null) {
      markers.add(
        Marker(
          point: _driverPosition!,
          width: 80,
          height: 70,
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

    // Build polylines (dashed blue)
    final polylines = <Polyline>[];
    if (polyline != null && polyline.isNotEmpty) {
      polylines.add(
        Polyline(
          points: polyline,
          strokeWidth: 4.0,
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
            center: pickup ?? userLocation,
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
                  // ETA status bar
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
                            'Llega en $eta min',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : Colors.black87,
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
                                  // Verified badge
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
                                    '4.9',
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
                                    '1,240 viajes',
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
                                      'P-123456',
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
                    // Chat preview bubble
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
                              'Estoy en la esquina cerca de la tienda.',
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

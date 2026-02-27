import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_theme.dart';
import '../../providers/address_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/transport_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/transport_request_service.dart';
import '../../utils/constants.dart';
import '../../widgets/client_drawer.dart';
import '../../widgets/map_widget.dart';
import '../../widgets/transport_type_card.dart';
import 'location_search_screen.dart';

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  int _currentNavIndex = 0;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  /// Tracks whether we have already moved the map to the first real GPS fix.
  /// Once done we stop auto-centering so the user can pan freely.
  bool _mapCenteredOnUser = false;

  final TransportRequestService _requestService = TransportRequestService();
  List<Map<String, dynamic>> _nearbyDrivers = [];
  Timer? _driversRefreshTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final locationProvider = context.read<LocationProvider>();

      // Always (re)init to ensure the continuous GPS stream is running.
      locationProvider.initLocation();

      // Listen so we can move the map to the first real GPS fix.
      locationProvider.addListener(_onLocationChanged);

      context.read<TransportProvider>().loadVehicleTypes();
      final uuid = context.read<AuthProvider>().user?.id;
      if (uuid != null) {
        context.read<AddressProvider>().loadAddresses(uuid);
      }

      // Load nearby online drivers, refresh every 15 s
      _loadNearbyDrivers();
      _driversRefreshTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _loadNearbyDrivers(),
      );
    });
  }

  Future<void> _loadNearbyDrivers() async {
    final loc = context.read<LocationProvider>().locationOrDefault;
    try {
      final drivers = await _requestService.getNearbyDrivers(
        loc.latitude,
        loc.longitude,
        AppConstants.defaultSearchRadiusKm,
      );
      if (mounted) setState(() => _nearbyDrivers = drivers);
    } catch (_) {}
  }

  /// Called whenever LocationProvider notifies. On the first real GPS fix,
  /// move the map camera to the user's position.
  void _onLocationChanged() {
    if (_mapCenteredOnUser) return;
    final loc = context.read<LocationProvider>().currentLocation;
    if (loc == null) return;

    _mapCenteredOnUser = true;
    try {
      _mapController.move(loc, AppConstants.defaultZoom);
    } catch (_) {
      // MapController may not be ready on the very first callback; ignore.
    }
  }

  @override
  void dispose() {
    _driversRefreshTimer?.cancel();
    try {
      context.read<LocationProvider>().removeListener(_onLocationChanged);
    } catch (_) {}
    _pulseController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _centerOnUser() {
    final locationProvider = context.read<LocationProvider>();
    final loc = locationProvider.locationOrDefault;
    _mapController.move(loc, AppConstants.defaultZoom);
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    final locationProvider = context.read<LocationProvider>();
    final transportProvider = context.read<TransportProvider>();

    transportProvider.setPickup(
      locationProvider.locationOrDefault,
      address: 'Ubicación actual',
    );
    transportProvider.setDropoff(point, address: 'Destino seleccionado');

    _openSearchScreen();
  }

  void _openSearchScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LocationSearchScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final locationProvider = context.watch<LocationProvider>();
    final transportProvider = context.watch<TransportProvider>();
    final isDark = themeProvider.isDark;
    final userLocation = locationProvider.locationOrDefault;

    final addressProvider = context.watch<AddressProvider>();

    // Show a top banner if GPS permission is missing or service is off
    final locationError = locationProvider.error;

    return Scaffold(
      drawer: const ClientDrawer(),
      body: Stack(
        children: [
          // Full-screen map with user location marker
          MapWidget(
            isDark: isDark,
            mapController: _mapController,
            center: userLocation,
            zoom: AppConstants.defaultZoom,
            onTap: _onMapTap,
            markers: [
              // User location
              Marker(
                point: userLocation,
                width: 40,
                height: 40,
                child: _PulsingDot(animation: _pulseAnimation),
              ),
              // Nearby online drivers
              ..._nearbyDrivers.map((d) {
                final lat = (d['latitude'] as num?)?.toDouble();
                final lon = (d['longitude'] as num?)?.toDouble();
                if (lat == null || lon == null) return null;
                final driver =
                    d['drivers'] as Map<String, dynamic>?;
                final name =
                    driver?['name'] as String? ?? 'Conductor';
                final image = driver?['image'] as String?;
                return Marker(
                  point: LatLng(lat, lon),
                  width: 48,
                  height: 48,
                  child: Tooltip(
                    message: name,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor
                                .withValues(alpha: 0.4),
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
                            : const Icon(
                                Icons.directions_car,
                                color: Colors.white,
                                size: 22,
                              ),
                      ),
                    ),
                  ),
                );
              }).whereType<Marker>(),
            ],
          ),

          // GPS error banner
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

          // Top bar overlay
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search bar row
                  Row(
                    children: [
                      // Hamburger menu
                      Builder(
                        builder: (scaffoldContext) => _buildCircleButton(
                          icon: Icons.menu,
                          onPressed: () {
                            Scaffold.of(scaffoldContext).openDrawer();
                          },
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Search bar
                      Expanded(
                        child: GestureDetector(
                          onTap: _openSearchScreen,
                          child: Container(
                            height: 48,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
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
                                  Icons.search,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.grey[600],
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '\u00bfA donde vas?',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 15,
                                      color: isDark
                                          ? Colors.white54
                                          : Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Notification bell
                      _buildCircleButton(
                        icon: Icons.notifications_outlined,
                        onPressed: () {},
                        isDark: isDark,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Quick destination chips — saved addresses + add button
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // One chip per saved address (max 5)
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
                              final addr = addressProvider.addresses[i];
                              final tp =
                                  context.read<TransportProvider>();
                              final lp =
                                  context.read<LocationProvider>();
                              final nav = Navigator.of(context);
                              tp.setPickup(
                                lp.locationOrDefault,
                                address: 'Ubicación actual',
                              );
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
                        // "+ Agregar" chip always visible at the end
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

          // Right side floating buttons
          Positioned(
            right: 16,
            bottom: 280,
            child: Column(
              children: [
                _buildCircleButton(
                  icon: Icons.my_location,
                  onPressed: _centerOnUser,
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _buildCircleButton(
                  icon: Icons.layers_outlined,
                  onPressed: () {
                    context.read<ThemeProvider>().toggleTheme();
                  },
                  isDark: isDark,
                ),
              ],
            ),
          ),

          // Bottom draggable sheet
          DraggableScrollableSheet(
            initialChildSize: 0.35,
            minChildSize: 0.08,
            maxChildSize: 0.55,
            snap: true,
            snapSizes: const [0.08, 0.35, 0.55],
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
                    const SizedBox(height: 20),
                    // Header
                    Text(
                      'Elige tu transporte',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Vehicle types loaded from DB
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
                            eta: '${vt.tiempoMinPorKm.toStringAsFixed(1)} min/km',
                            isSelected: isSelected,
                            onTap: () => context
                                .read<TransportProvider>()
                                .setVehicleType(vt),
                          ),
                        );
                      }),
                    const SizedBox(height: 16),
                    // Payment method row
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppTheme.darkCard
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? AppTheme.darkBorder
                              : Colors.grey[300]!,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.payments_outlined,
                            color: AppTheme.success,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Efectivo',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color:
                                  isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.chevron_right,
                            color:
                                isDark ? Colors.white38 : Colors.grey,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              );
            },
          ),
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
              Navigator.pushNamed(context, '/client/request-history');
              break;
            case 2:
              Navigator.pushNamed(context, '/client/wallet');
              break;
            case 3:
              Navigator.pushNamed(context, '/client/profile');
              break;
          }
          // Reset index so tapping the same tab again still navigates
          Future.microtask(() {
            if (mounted) setState(() => _currentNavIndex = 0);
          });
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        selectedItemColor: AppTheme.primaryColor,
        unselectedItemColor: isDark ? Colors.white54 : Colors.grey,
        selectedLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            activeIcon: Icon(Icons.receipt_long),
            label: 'Actividad',
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
            Icon(
              icon,
              size: 18,
              color: AppTheme.primaryColor,
            ),
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

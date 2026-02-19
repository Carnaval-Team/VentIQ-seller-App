import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_theme.dart';
import '../../providers/location_provider.dart';
import '../../providers/transport_provider.dart';
import '../../providers/theme_provider.dart';
import '../../utils/constants.dart';
import '../../widgets/map_widget.dart';
import '../../widgets/transport_type_card.dart';
import 'route_preview_screen.dart';

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
      if (locationProvider.currentLocation == null) {
        locationProvider.initLocation();
      }
    });
  }

  @override
  void dispose() {
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
    final transportProvider = context.read<TransportProvider>();
    final locationProvider = context.read<LocationProvider>();

    transportProvider.setPickup(
      locationProvider.locationOrDefault,
      address: 'Ubicacion actual',
    );
    transportProvider.setDropoff(point, address: 'Destino seleccionado');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const RoutePreviewScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final locationProvider = context.watch<LocationProvider>();
    final transportProvider = context.watch<TransportProvider>();
    final isDark = themeProvider.isDark;
    final userLocation = locationProvider.locationOrDefault;

    return Scaffold(
      body: Stack(
        children: [
          // Full-screen map with user location marker
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, _) {
              return MapWidget(
                isDark: isDark,
                mapController: _mapController,
                center: userLocation,
                zoom: AppConstants.defaultZoom,
                onTap: _onMapTap,
                markers: [
                  // Pulsing blue dot for user location
                  Marker(
                    point: userLocation,
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.primaryColor
                            .withValues(alpha: _pulseAnimation.value * 0.3),
                      ),
                      child: Center(
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.primaryColor,
                            border: Border.all(
                              color: Colors.white,
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryColor
                                    .withValues(alpha: 0.4),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
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
                      _buildCircleButton(
                        icon: Icons.menu,
                        onPressed: () {
                          Scaffold.of(context).openDrawer();
                        },
                        isDark: isDark,
                      ),
                      const SizedBox(width: 12),
                      // Search bar
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            // Navigate to search screen
                          },
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
                  // Quick destination pills
                  Row(
                    children: [
                      _buildQuickDestinationPill(
                        icon: Icons.work_outlined,
                        label: 'Trabajo',
                        isDark: isDark,
                        onTap: () {},
                      ),
                      const SizedBox(width: 10),
                      _buildQuickDestinationPill(
                        icon: Icons.home_outlined,
                        label: 'Casa',
                        isDark: isDark,
                        onTap: () {},
                      ),
                    ],
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
            minChildSize: 0.15,
            maxChildSize: 0.55,
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
                    // Transport type cards using factory constructors
                    TransportTypeCard.moto(
                      price: 5.20,
                      eta: '3 min',
                      isSelected:
                          transportProvider.selectedVehicleType ==
                              AppConstants.vehicleMoto,
                      onTap: () {
                        context
                            .read<TransportProvider>()
                            .setVehicleType(AppConstants.vehicleMoto);
                      },
                    ),
                    const SizedBox(height: 10),
                    TransportTypeCard.auto(
                      price: 10.50,
                      eta: '5 min',
                      isSelected:
                          transportProvider.selectedVehicleType ==
                              AppConstants.vehicleAuto,
                      onTap: () {
                        context
                            .read<TransportProvider>()
                            .setVehicleType(AppConstants.vehicleAuto);
                      },
                    ),
                    const SizedBox(height: 10),
                    TransportTypeCard.microbus(
                      price: 4.00,
                      eta: '8 min',
                      isSelected:
                          transportProvider.selectedVehicleType ==
                              AppConstants.vehicleMicrobus,
                      onTap: () {
                        context
                            .read<TransportProvider>()
                            .setVehicleType(AppConstants.vehicleMicrobus);
                      },
                    ),
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
          setState(() {
            _currentNavIndex = index;
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

/// AnimatedBuilder that wraps AnimatedWidget for pulse animation.
class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;

  const AnimatedBuilder({
    super.key,
    required Animation<double> animation,
    required this.builder,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    return builder(context, null);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_theme.dart';
import '../../models/driver_offer_model.dart';
import '../../providers/location_provider.dart';
import '../../providers/transport_provider.dart';
import '../../providers/theme_provider.dart';
import '../../utils/constants.dart';
import '../../widgets/map_widget.dart';
import '../../widgets/driver_offer_card.dart';
import 'ride_confirmed_screen.dart';

class DriverOffersScreen extends StatefulWidget {
  const DriverOffersScreen({super.key});

  @override
  State<DriverOffersScreen> createState() => _DriverOffersScreenState();
}

class _DriverOffersScreenState extends State<DriverOffersScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  String _selectedFilter = 'Mejor';
  late AnimationController _pulseAnimController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseAnimController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseAnimController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  List<DriverOfferModel> _filterOffers(List<DriverOfferModel> offers) {
    final sorted = List<DriverOfferModel>.from(offers);
    switch (_selectedFilter) {
      case 'Menor Precio':
        sorted
            .sort((a, b) => (a.precio ?? 0).compareTo(b.precio ?? 0));
        break;
      case 'Mas Rapido':
        sorted.sort((a, b) =>
            (a.tiempoEstimado ?? 0).compareTo(b.tiempoEstimado ?? 0));
        break;
      case 'Mejor':
      default:
        // Keep default order (best match first)
        break;
    }
    return sorted;
  }

  void _onAcceptOffer(DriverOfferModel offer) async {
    final transportProvider = context.read<TransportProvider>();
    await transportProvider.acceptOffer(offer);

    if (mounted &&
        transportProvider.state == TransportState.rideConfirmed) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const RideConfirmedScreen(),
        ),
      );
    }
  }

  void _onCancelTrip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final isDark = context.read<ThemeProvider>().isDark;
        return AlertDialog(
          backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Cancelar viaje',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          content: Text(
            '\u00bfEstas seguro que deseas cancelar la solicitud?',
            style: GoogleFonts.plusJakartaSans(
              color: isDark ? Colors.white70 : Colors.grey[700],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                'No',
                style: GoogleFonts.plusJakartaSans(
                  color: isDark ? Colors.white70 : Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                'Si, cancelar',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      await context.read<TransportProvider>().cancelRequest();
      if (mounted) {
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final transportProvider = context.watch<TransportProvider>();
    final locationProvider = context.watch<LocationProvider>();
    final isDark = themeProvider.isDark;
    final userLocation = locationProvider.locationOrDefault;
    final offers = _filterOffers(transportProvider.driverOffers);

    return Scaffold(
      body: Stack(
        children: [
          // Map background with user location avatar marker
          MapWidget(
            isDark: isDark,
            mapController: _mapController,
            center: userLocation,
            zoom: AppConstants.defaultZoom,
            markers: [
              Marker(
                point: userLocation,
                width: 50,
                height: 50,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primaryColor,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color:
                            AppTheme.primaryColor.withValues(alpha: 0.4),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),

          // "Negociando..." status badge at top
          SafeArea(
            child: Center(
              heightFactor: 1,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _NegotiatingBadge(
                  animation: _pulseAnim,
                  isDark: isDark,
                ),
              ),
            ),
          ),

          // DraggableScrollableSheet with offers
          DraggableScrollableSheet(
            initialChildSize: 0.65,
            minChildSize: 0.3,
            maxChildSize: 0.85,
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
                    const SizedBox(height: 16),
                    // Header with count and cancel button
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${offers.length} Conductores encontrados',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color:
                                  isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _onCancelTrip,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                          ),
                          child: Text(
                            'Cancelar Viaje',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Filter chips
                    SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _buildFilterChip('Mejor', isDark),
                          const SizedBox(width: 8),
                          _buildFilterChip('Menor Precio', isDark),
                          const SizedBox(width: 8),
                          _buildFilterChip('Mas Rapido', isDark),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Offer cards
                    if (offers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          children: [
                            Icon(
                              Icons.hourglass_empty,
                              size: 48,
                              color: isDark
                                  ? Colors.white38
                                  : Colors.grey[400],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Esperando ofertas de conductores...',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                color: isDark
                                    ? Colors.white54
                                    : Colors.grey[600],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    else
                      ...List.generate(offers.length, (index) {
                        final offer = offers[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: DriverOfferCard(
                            offer: offer,
                            driverRating: 4.8,
                            onAccept: () => _onAcceptOffer(offer),
                            onDecline: () {
                              // Handle decline - remove from local view
                            },
                          ),
                        );
                      }),
                    const SizedBox(height: 20),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        onTap: (index) {},
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
            label: 'Inicio',
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
            label: 'Cuenta',
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isDark) {
    final isSelected = _selectedFilter == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = label;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor
              : isDark
                  ? AppTheme.darkCard
                  : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryColor
                : isDark
                    ? AppTheme.darkBorder
                    : Colors.grey[300]!,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected
                ? Colors.white
                : isDark
                    ? Colors.white70
                    : Colors.grey[700],
          ),
        ),
      ),
    );
  }
}

/// Animated "Negociando..." badge at the top of the screen.
class _NegotiatingBadge extends AnimatedWidget {
  final bool isDark;

  const _NegotiatingBadge({
    required Animation<double> animation,
    required this.isDark,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    final anim = listenable as Animation<double>;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.darkSurface.withValues(alpha: 0.95)
            : Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor
                .withValues(alpha: anim.value * 0.3),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Negociando...',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

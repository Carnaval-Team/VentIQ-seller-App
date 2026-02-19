import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_theme.dart';
import '../../providers/transport_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';
import '../../widgets/map_widget.dart';
import 'driver_offers_screen.dart';

class RoutePreviewScreen extends StatefulWidget {
  const RoutePreviewScreen({super.key});

  @override
  State<RoutePreviewScreen> createState() => _RoutePreviewScreenState();
}

class _RoutePreviewScreenState extends State<RoutePreviewScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _offerController = TextEditingController();
  String _selectedPaymentMethod = 'Efectivo';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final transportProvider = context.read<TransportProvider>();
      transportProvider.calculateRoute();
      _offerController.text = transportProvider.offerPrice.toStringAsFixed(2);
    });
  }

  @override
  void dispose() {
    _offerController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onSendRequest() async {
    final transportProvider = context.read<TransportProvider>();
    final authProvider = context.read<AuthProvider>();

    // Update offer price from text field
    final price = double.tryParse(_offerController.text);
    if (price != null) {
      transportProvider.setOfferPrice(price);
    }

    final userId = authProvider.user?.id ?? '';
    await transportProvider.sendRequest(userId);

    if (mounted && transportProvider.state == TransportState.waitingOffers) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const DriverOffersScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final transportProvider = context.watch<TransportProvider>();
    final isDark = themeProvider.isDark;

    final pickup = transportProvider.pickupLocation;
    final dropoff = transportProvider.dropoffLocation;
    final polyline = transportProvider.routePolyline;

    // Update offer controller when price changes externally
    if (_offerController.text.isEmpty && transportProvider.offerPrice > 0) {
      _offerController.text = transportProvider.offerPrice.toStringAsFixed(2);
    }

    // Build markers list
    final markers = <Marker>[];
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
              boxShadow: [
                BoxShadow(
                  color: AppTheme.success.withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.my_location, color: Colors.white, size: 18),
          ),
        ),
      );
    }
    if (dropoff != null) {
      markers.add(
        Marker(
          point: dropoff,
          width: 60,
          height: 70,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Text(
                  '${transportProvider.routeDurationMin.round()} min',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              const Icon(Icons.location_on, color: AppTheme.error, size: 30),
            ],
          ),
        ),
      );
    }

    // Build polylines list
    final polylines = <Polyline>[];
    if (polyline != null && polyline.isNotEmpty) {
      polylines.addAll([
        // White border
        Polyline(points: polyline, strokeWidth: 7.0, color: Colors.white),
        // Blue line
        Polyline(
            points: polyline, strokeWidth: 4.0, color: AppTheme.primaryColor),
      ]);
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkBg : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.success,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'En linea',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.success,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Route info card
          _buildRouteInfoCard(isDark, transportProvider),

          // Map
          Expanded(
            child: Stack(
              children: [
                MapWidget(
                  isDark: isDark,
                  mapController: _mapController,
                  center: pickup ??
                      LatLng(AppConstants.defaultLat, AppConstants.defaultLon),
                  zoom: 14.0,
                  markers: markers,
                  polylines: polylines,
                ),
                // Loading indicator
                if (transportProvider.state ==
                    TransportState.calculatingRoute)
                  const Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryColor,
                    ),
                  ),
              ],
            ),
          ),

          // Bottom sheet
          _buildBottomSheet(isDark, transportProvider),
        ],
      ),
    );
  }

  Widget _buildRouteInfoCard(
      bool isDark, TransportProvider transportProvider) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Dots and dashed line
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.success,
                ),
              ),
              Container(
                width: 2,
                height: 30,
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: CustomPaint(
                  painter: _DashedLinePainter(
                    color: isDark ? Colors.white24 : Colors.grey[400]!,
                  ),
                ),
              ),
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          // Addresses
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transportProvider.pickupAddress ?? 'Ubicacion actual',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 20),
                Text(
                  transportProvider.dropoffAddress ?? 'Destino seleccionado',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Edit button
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.edit_outlined,
              color: AppTheme.primaryColor,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSheet(
      bool isDark, TransportProvider transportProvider) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 15,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
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
            const SizedBox(height: 16),
            // Header
            Text(
              'Selecciona transporte',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 14),
            // Vehicle options horizontal scrollable
            SizedBox(
              height: 90,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildVehicleOption(
                    isDark: isDark,
                    icon: Icons.two_wheeler,
                    label: 'Moto',
                    price: '\$5.00',
                    isSelected: transportProvider.selectedVehicleType ==
                        AppConstants.vehicleMoto,
                    badgeText: null,
                    onTap: () => context
                        .read<TransportProvider>()
                        .setVehicleType(AppConstants.vehicleMoto),
                  ),
                  const SizedBox(width: 10),
                  _buildVehicleOption(
                    isDark: isDark,
                    icon: Icons.directions_car,
                    label: 'Auto',
                    price: '\$12.00',
                    isSelected: transportProvider.selectedVehicleType ==
                        AppConstants.vehicleAuto,
                    badgeText: 'Mejor',
                    onTap: () => context
                        .read<TransportProvider>()
                        .setVehicleType(AppConstants.vehicleAuto),
                  ),
                  const SizedBox(width: 10),
                  _buildVehicleOption(
                    isDark: isDark,
                    icon: Icons.directions_bus,
                    label: 'Microbus',
                    price: '\$3.00',
                    isSelected: transportProvider.selectedVehicleType ==
                        AppConstants.vehicleMicrobus,
                    badgeText: null,
                    onTap: () => context
                        .read<TransportProvider>()
                        .setVehicleType(AppConstants.vehicleMicrobus),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Offer price input
            Text(
              'Tu Oferta',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _offerController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                prefixText: '\$ ',
                prefixStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryColor,
                ),
                filled: true,
                fillColor: isDark ? AppTheme.darkCard : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? AppTheme.darkBorder : Colors.grey[300]!,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? AppTheme.darkBorder : Colors.grey[300]!,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppTheme.primaryColor,
                    width: 2,
                  ),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onChanged: (value) {
                final price = double.tryParse(value);
                if (price != null) {
                  context.read<TransportProvider>().setOfferPrice(price);
                }
              },
            ),
            const SizedBox(height: 8),
            // Average rates link
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  // Show average rates
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Ver tarifas promedio',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.primaryColor,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Payment method row
            GestureDetector(
              onTap: () {
                // Show payment method picker
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkCard : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? AppTheme.darkBorder : Colors.grey[300]!,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _selectedPaymentMethod == 'Efectivo'
                          ? Icons.payments_outlined
                          : Icons.credit_card,
                      color: AppTheme.primaryColor,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _selectedPaymentMethod == 'Efectivo'
                          ? 'Efectivo'
                          : 'Visa *4242',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right,
                      color: isDark ? Colors.white38 : Colors.grey,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // CTA Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: transportProvider.state ==
                        TransportState.requesting
                    ? null
                    : _onSendRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: transportProvider.state ==
                        TransportState.requesting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        'Solicitar ${transportProvider.selectedVehicleType}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleOption({
    required bool isDark,
    required IconData icon,
    required String label,
    required String price,
    required bool isSelected,
    required String? badgeText,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.15)
              : isDark
                  ? AppTheme.darkCard
                  : Colors.grey[100],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.transparent,
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 28,
                  color: isSelected
                      ? AppTheme.primaryColor
                      : isDark
                          ? Colors.white70
                          : Colors.grey[700],
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? AppTheme.primaryColor
                        : isDark
                            ? Colors.white
                            : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  price,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? AppTheme.primaryColor
                        : isDark
                            ? Colors.white70
                            : Colors.grey[700],
                  ),
                ),
              ],
            ),
            if (badgeText != null)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.success,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badgeText,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for dashed vertical line between pickup and dropoff dots.
class _DashedLinePainter extends CustomPainter {
  final Color color;

  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const dashHeight = 4.0;
    const dashSpace = 3.0;
    double startY = 0;

    while (startY < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, startY),
        Offset(size.width / 2, startY + dashHeight),
        paint,
      );
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

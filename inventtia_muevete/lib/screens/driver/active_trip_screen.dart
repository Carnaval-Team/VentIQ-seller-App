import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/driver_service.dart';
import '../../services/routing_service.dart';
import '../../utils/helpers.dart';
import '../../widgets/map_widget.dart';

/// Driver's active trip screen.
/// Shows:
///  - Live map with driver position, destination marker and recalculated route
///  - ETA and remaining distance (updated every time route is recalculated)
///  - Realtime subscription to the viaje row
///  - "Completar viaje" button
class ActiveTripScreen extends StatefulWidget {
  final int viajeId;
  final double destLat;
  final double destLon;
  final String? destAddress;
  final String? clientPhone;
  final String? clientName;

  const ActiveTripScreen({
    super.key,
    required this.viajeId,
    required this.destLat,
    required this.destLon,
    this.destAddress,
    this.clientPhone,
    this.clientName,
  });

  @override
  State<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends State<ActiveTripScreen> {
  final DriverService _driverService = DriverService();
  final RoutingService _routingService = RoutingService();
  final MapController _mapController = MapController();
  final SupabaseClient _supabase = Supabase.instance.client;

  // Route from driver → destination
  List<LatLng> _routePolyline = [];
  double _remainingDistanceKm = 0;
  double _remainingMinutes = 0;
  bool _isCalculatingRoute = false;
  bool _isCompleting = false;

  // Last driver position used for route calculation
  LatLng? _lastRouteCalcPosition;

  // Threshold: recalculate when driver moves > 150 m from last calc point
  static const double _recalcThresholdKm = 0.15;

  Timer? _locationTimer;
  RealtimeChannel? _viajeChannel;

  // Whether the viaje is still active (completado == false)
  bool _viajeActivo = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startTracking();
      _subscribeViajeRealtime();
    });
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    if (_viajeChannel != null) {
      try {
        _supabase.removeChannel(_viajeChannel!);
      } catch (_) {}
    }
    _mapController.dispose();
    super.dispose();
  }

  // ── Location tracking + route recalculation ───────────────────────────────

  void _startTracking() {
    // Immediate first calculation
    _onPositionUpdate();
    // Then every 8 s
    _locationTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) _onPositionUpdate();
    });
  }

  Future<void> _onPositionUpdate() async {
    if (!mounted) return;
    final loc = context.read<LocationProvider>().locationOrDefault;
    final driverPos = LatLng(loc.latitude, loc.longitude);

    // Update driver location in DB
    final authProvider = context.read<AuthProvider>();
    final rawId = authProvider.driverProfile?['id'];
    final driverId =
        rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
    final vehiculo =
        authProvider.driverProfile?['vehiculos'] as Map<String, dynamic>?;
    final vehicleId = vehiculo?['id'] as int?;

    if (driverId != null && vehicleId != null) {
      try {
        await _driverService.upsertDriverLocation(
          driverId: driverId,
          vehicleId: vehicleId,
          lat: loc.latitude,
          lon: loc.longitude,
          online: true,
        );
      } catch (_) {}
    }

    // Recalculate route if moved far enough (or first time)
    if (_lastRouteCalcPosition == null ||
        _haversine(
              _lastRouteCalcPosition!.latitude,
              _lastRouteCalcPosition!.longitude,
              driverPos.latitude,
              driverPos.longitude,
            ) >=
            _recalcThresholdKm) {
      await _calculateRoute(driverPos);
    }
  }

  Future<void> _calculateRoute(LatLng from) async {
    if (_isCalculatingRoute || !mounted) return;
    setState(() => _isCalculatingRoute = true);
    _lastRouteCalcPosition = from;
    final dest = LatLng(widget.destLat, widget.destLon);

    try {
      final result = await _routingService.getRoute(from, dest);
      if (!mounted) return;
      setState(() {
        _routePolyline = result.polyline;
        _remainingDistanceKm = result.totalDistance / 1000;
        _remainingMinutes = result.totalDuration / 60;
      });

      // Center map on midpoint between driver and destination
      final midLat = (from.latitude + dest.latitude) / 2;
      final midLon = (from.longitude + dest.longitude) / 2;
      try {
        _mapController.move(LatLng(midLat, midLon), 13.5);
      } catch (_) {}
    } catch (_) {
      // fallback: straight line
      if (mounted) {
        setState(() {
          _routePolyline = [from, dest];
          final distM = _haversine(
                from.latitude, from.longitude,
                dest.latitude, dest.longitude,
              ) *
              1000;
          _remainingDistanceKm = distM / 1000;
          _remainingMinutes = distM / 13.89 / 60; // ~50 km/h
        });
      }
    } finally {
      if (mounted) setState(() => _isCalculatingRoute = false);
    }
  }

  // ── Realtime subscription on viajes ──────────────────────────────────────

  void _subscribeViajeRealtime() {
    _viajeChannel = _driverService.subscribeToViaje(widget.viajeId, (row) {
      if (!mounted) return;
      final completado = row['completado'] as bool? ?? false;
      if (completado) {
        setState(() => _viajeActivo = false);
        // Auto-pop after 2 s so the driver sees the completion message
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
        });
      }
    });
  }

  // ── Complete ride ─────────────────────────────────────────────────────────

  Future<void> _completeTrip() async {
    if (_isCompleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2232),
        title: Text('Completar viaje',
            style: GoogleFonts.plusJakartaSans(
                color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text('¿Confirmas que llegaste al destino?',
            style: GoogleFonts.plusJakartaSans(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: GoogleFonts.plusJakartaSans(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            child: Text('Completar',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _isCompleting = true);

    try {
      // Mark viaje completado
      await _driverService.updateTripStatus(widget.viajeId, completado: true);

      // Also mark the solicitud completada if we have the id from provider
      final viajeId = widget.viajeId;
      // Find solicitud linked to this viaje via transport provider
      if (mounted) {
        // Mark solicitud completada via Supabase directly
        // (the viaje row has user field but not solicitud_id directly)
        // The solicitud will be updated by the client's "completar" flow.
        // Driver completing: we just mark viaje.completado = true + estado = false (done).
        await _supabase
            .schema('muevete')
            .from('viajes')
            .update({'completado': true, 'estado': false})
            .eq('id', viajeId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('¡Viaje completado!',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          backgroundColor: AppTheme.success,
        ));
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppTheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _isCompleting = false);
    }
  }

  // ── Contact ───────────────────────────────────────────────────────────────

  Future<void> _launchCall(String phone) async {
    final url = Uri.parse(Helpers.buildPhoneUrl(phone));
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  Future<void> _launchWhatsApp(String phone) async {
    final url = Uri.parse(
        Helpers.buildWhatsAppUrl(phone, message: 'Hola, soy tu conductor'));
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final loc = context.watch<LocationProvider>().locationOrDefault;
    final driverPos = LatLng(loc.latitude, loc.longitude);
    final dest = LatLng(widget.destLat, widget.destLon);

    // Markers: driver + destination
    final markers = [
      // Driver
      Marker(
        point: driverPos,
        width: 50,
        height: 50,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.primaryColor,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withValues(alpha: 0.4),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.directions_car, color: Colors.white, size: 24),
        ),
      ),
      // Destination
      Marker(
        point: dest,
        width: 52,
        height: 52,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.error,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: AppTheme.error.withValues(alpha: 0.4),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Icon(Icons.flag, color: Colors.white, size: 22),
        ),
      ),
    ];

    final polylines = _routePolyline.isNotEmpty
        ? [
            Polyline(
              points: _routePolyline,
              strokeWidth: 5.0,
              color: AppTheme.primaryColor,
            ),
          ]
        : <Polyline>[];

    final etaText = _remainingMinutes < 1
        ? '< 1 min'
        : '${_remainingMinutes.round()} min';
    final distText = _remainingDistanceKm < 1
        ? '${(_remainingDistanceKm * 1000).round()} m'
        : '${_remainingDistanceKm.toStringAsFixed(1)} km';

    return Scaffold(
      body: Stack(
        children: [
          // ── Map ──
          MapWidget(
            isDark: isDark,
            mapController: _mapController,
            center: driverPos,
            zoom: 14.0,
            markers: markers,
            polylines: polylines,
          ),

          // ── Top bar: back + ETA ──
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Back
                  Material(
                    color: isDark ? AppTheme.darkSurface : Colors.white,
                    shape: const CircleBorder(),
                    elevation: 4,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.pop(context),
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.arrow_back, size: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // ETA pill
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
                          if (_isCalculatingRoute)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.primaryColor,
                              ),
                            )
                          else
                            const Icon(Icons.navigation,
                                color: AppTheme.primaryColor, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            _routePolyline.isEmpty
                                ? 'Calculando ruta…'
                                : '$etaText · $distText',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Recalculate button
                  Material(
                    color: isDark ? AppTheme.darkSurface : Colors.white,
                    shape: const CircleBorder(),
                    elevation: 4,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _isCalculatingRoute
                          ? null
                          : () => _calculateRoute(driverPos),
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.refresh,
                            size: 22, color: AppTheme.primaryColor),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom card ──
          Positioned(
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
                    // Handle
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
                    const SizedBox(height: 14),

                    // Destination row
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.error.withValues(alpha: 0.12),
                          ),
                          child: const Icon(Icons.flag,
                              color: AppTheme.error, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Destino',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.grey[500],
                                ),
                              ),
                              Text(
                                widget.destAddress ??
                                    '${widget.destLat.toStringAsFixed(4)}, '
                                        '${widget.destLon.toStringAsFixed(4)}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // Distance chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            distText,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Client info row (if available)
                    if (widget.clientName != null ||
                        widget.clientPhone != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.primaryColor
                                  .withValues(alpha: 0.12),
                            ),
                            child: const Icon(Icons.person,
                                color: AppTheme.primaryColor, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.clientName ?? 'Cliente',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                          ),
                          if (widget.clientPhone != null &&
                              widget.clientPhone!.isNotEmpty) ...[
                            // Call
                            SizedBox(
                              height: 36,
                              child: ElevatedButton.icon(
                                onPressed: () =>
                                    _launchCall(widget.clientPhone!),
                                icon: const Icon(Icons.phone, size: 14),
                                label: Text('Llamar',
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(10)),
                                  elevation: 0,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // WhatsApp
                            SizedBox(
                              height: 36,
                              child: ElevatedButton.icon(
                                onPressed: () =>
                                    _launchWhatsApp(widget.clientPhone!),
                                icon: const Icon(Icons.chat, size: 14),
                                label: Text('WhatsApp',
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF25D366),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(10)),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],

                    const SizedBox(height: 14),

                    // Complete trip button
                    if (_viajeActivo)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _isCompleting ? null : _completeTrip,
                          icon: _isCompleting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_circle_outline,
                                  size: 22),
                          label: Text(
                            _isCompleting
                                ? 'Completando...'
                                : 'Completar viaje',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.success,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle,
                                color: AppTheme.success, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              '¡Viaje completado!',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

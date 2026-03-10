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
import '../../services/completion_sync_service.dart';
import '../../utils/helpers.dart';
import '../../utils/smooth_compass_mixin.dart';
import '../../widgets/map_widget.dart';
import '../../models/stop_model.dart';
import '../../services/stop_service.dart';
import '../../widgets/qr_scanner_dialog.dart';

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

class _ActiveTripScreenState extends State<ActiveTripScreen>
    with SmoothCompassMixin {
  final DriverService _driverService = DriverService();
  final RoutingService _routingService = RoutingService();
  final MapController _mapController = MapController();

  @override
  MapController get compassMapController => _mapController;
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

  // Navigation instructions
  List<RouteStep> _steps = [];
  String _nextInstruction = '';
  String _nextManeuverIcon = 'straight';
  double _nextStepDistanceM = 0;

  // Stop (parada) state
  final StopService _stopService = StopService();
  StopModel? _activeStop;
  Timer? _stopTimer;
  int _stopElapsedSeconds = 0;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startTracking();
      _subscribeViajeRealtime();
      _checkIfAlreadyCompleted();
    });
  }

  @override
  void dispose() {
    disposeCompass();
    _locationTimer?.cancel();
    _stopTimer?.cancel();
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
    } else {
      // Still update instruction even without recalculating route
      _updateNextInstruction(driverPos);
    }
  }

  void _updateNextInstruction(LatLng driverPos) {
    if (_steps.isEmpty) return;
    // Find the nearest upcoming step (skip 'depart')
    RouteStep? best;
    double bestDist = double.infinity;
    for (final step in _steps) {
      if (step.maneuverType == 'depart') continue;
      final d = _haversine(
            driverPos.latitude,
            driverPos.longitude,
            step.location.latitude,
            step.location.longitude,
          ) *
          1000; // km → m
      // Only show steps ahead (within 500m)
      if (d < bestDist && d < 500) {
        bestDist = d;
        best = step;
      }
    }
    if (best != null && mounted) {
      setState(() {
        _nextInstruction = best!.instruction;
        _nextStepDistanceM = bestDist;
        _nextManeuverIcon =
            RoutingService.maneuverIcon(best.maneuverType, best.modifier);
      });
    } else if (mounted && _nextInstruction.isNotEmpty) {
      setState(() {
        _nextInstruction = '';
        _nextStepDistanceM = 0;
      });
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
        _steps = result.steps;
      });
      _updateNextInstruction(from);

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

  // ── Check if viaje was already completed (e.g. by client) ───────────────

  Future<void> _checkIfAlreadyCompleted() async {
    try {
      final row = await _supabase
          .schema('muevete')
          .from('viajes')
          .select('completado')
          .eq('id', widget.viajeId)
          .maybeSingle();
      if (row != null && (row['completado'] as bool? ?? false) && mounted) {
        setState(() => _viajeActivo = false);
      }
    } catch (_) {}
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

  // ── Stop (parada) management ────────────────────────────────────────────

  Future<void> _toggleStop() async {
    if (_activeStop != null) {
      // End the current stop
      try {
        await _stopService.endStop(_activeStop!.id!);
        _stopTimer?.cancel();
        setState(() {
          _activeStop = null;
          _stopElapsedSeconds = 0;
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al salir de parada: $e'), backgroundColor: AppTheme.error),
          );
        }
      }
    } else {
      // Start a new stop
      final loc = context.read<LocationProvider>().locationOrDefault;
      final authProvider = context.read<AuthProvider>();
      final rawId = authProvider.driverProfile?['id'];
      final driverId = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
      if (driverId == null) return;

      try {
        final stop = await _stopService.createStop(
          widget.viajeId, driverId, loc.latitude, loc.longitude,
        );
        setState(() {
          _activeStop = stop;
          _stopElapsedSeconds = 0;
        });
        _stopTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _stopElapsedSeconds++);
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al agregar parada: $e'), backgroundColor: AppTheme.error),
          );
        }
      }
    }
  }

  String _formatStopTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _completeTrip() async {
    if (_isCompleting) return;

    // End active stop if any
    if (_activeStop != null) {
      try {
        await _stopService.endStop(_activeStop!.id!);
        _stopTimer?.cancel();
        setState(() {
          _activeStop = null;
          _stopElapsedSeconds = 0;
        });
      } catch (_) {}
    }

    // Get total wait time
    final totalWaitSeconds = await _stopService.getTotalWaitSeconds(widget.viajeId);

    // Fetch precio_espera_minuto from vehicle type
    double precioEsperaMinuto = 0;
    try {
      final viajeRow = await _supabase
          .schema('muevete')
          .from('viajes')
          .select('vehiculo')
          .eq('id', widget.viajeId)
          .maybeSingle();
      if (viajeRow != null && viajeRow['vehiculo'] != null) {
        final vtRow = await _supabase
            .schema('muevete')
            .from('vehicle_type')
            .select('precio_espera_minuto')
            .eq('tipo', viajeRow['vehiculo'])
            .maybeSingle();
        if (vtRow != null) {
          precioEsperaMinuto = (vtRow['precio_espera_minuto'] as num?)?.toDouble() ?? 0;
        }
      }
    } catch (_) {}

    final waitMinutes = (totalWaitSeconds / 60).ceil();
    final cobroEspera = waitMinutes * precioEsperaMinuto;

    if (!mounted) return;
    final isDark = context.read<ThemeProvider>().isDark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface(isDark),
        title: Text('Completar viaje',
            style: GoogleFonts.plusJakartaSans(
                color: AppTheme.textPrimary(isDark), fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Confirmas que llegaste al destino?',
                style: GoogleFonts.plusJakartaSans(color: AppTheme.textSecondary(isDark))),
            if (totalWaitSeconds > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tiempo de espera: $waitMinutes min',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, color: AppTheme.textPrimary(isDark), fontWeight: FontWeight.w600)),
                    if (precioEsperaMinuto > 0)
                      Text('Cobro espera: \$${cobroEspera.toStringAsFixed(2)}',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13, color: AppTheme.warning, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: GoogleFonts.plusJakartaSans(color: AppTheme.textTertiary(isDark))),
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

      final viajeId = widget.viajeId;
      if (mounted) {
        // Store wait charge in viaje and mark complete
        await _supabase
            .schema('muevete')
            .from('viajes')
            .update({
              'completado': true,
              'estado': false,
              'tiempo_espera_segundos': totalWaitSeconds,
              'cobro_espera': cobroEspera,
            })
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

  // ── QR scan for offline completion ──────────────────────────────────────

  Future<void> _scanQrCompletion() async {
    final data = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (_) => const QrScannerDialog(),
    );
    if (data == null || !mounted) return;

    // Validate the viaje matches
    final qrViajeId = data['viaje_id'] as int;
    if (qrViajeId != widget.viajeId) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Este QR no corresponde a este viaje',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.error,
      ));
      return;
    }

    setState(() => _isCompleting = true);
    try {
      // Try online first
      await _driverService.updateTripStatus(widget.viajeId, completado: true);
      await _supabase
          .schema('muevete')
          .from('viajes')
          .update({'completado': true, 'estado': false})
          .eq('id', widget.viajeId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('¡Viaje completado!',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          backgroundColor: AppTheme.success,
        ));
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } catch (_) {
      // Offline: enqueue for later sync
      await CompletionSyncService.enqueueCompletion(
        solicitudId: data['sol_id'] as int,
        viajeId: qrViajeId,
        driverId: data['driver_id'] as int,
        userId: data['user_id'] as String,
        precio: (data['precio'] as num).toDouble(),
        metodoPago: data['metodo'] as String,
        role: 'driver',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Viaje completado localmente. Se sincronizará al tener conexión.',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          backgroundColor: AppTheme.warning,
          duration: const Duration(seconds: 4),
        ));
        Navigator.of(context).popUntil((r) => r.isFirst);
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


  IconData _maneuverIconData(String key) {
    switch (key) {
      case 'left':
        return Icons.turn_left;
      case 'right':
        return Icons.turn_right;
      case 'slight_left':
        return Icons.turn_slight_left;
      case 'slight_right':
        return Icons.turn_slight_right;
      case 'sharp_left':
        return Icons.turn_sharp_left;
      case 'sharp_right':
        return Icons.turn_sharp_right;
      case 'uturn':
        return Icons.u_turn_left;
      case 'roundabout':
        return Icons.roundabout_left;
      case 'arrive':
        return Icons.flag;
      case 'merge':
        return Icons.merge;
      case 'straight':
      default:
        return Icons.straight;
    }
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
      // Driver — clean navigation arrow
      Marker(
        point: driverPos,
        width: 24,
        height: 24,
        rotate: autoRotate,
        child: Icon(
          Icons.navigation,
          color: AppTheme.primaryColor,
          size: 22,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
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

          // ── Compass toggle button ──
          Positioned(
            right: 16,
            top: MediaQuery.of(context).padding.top + 70,
            child: FloatingActionButton.small(
              heroTag: 'autorotate_trip',
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
          ),

          // ── Next maneuver banner ──
          if (_nextInstruction.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 114,
              left: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.surface(isDark).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      _maneuverIconData(_nextManeuverIcon),
                      color: AppTheme.primaryColor,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _nextStepDistanceM < 1000
                                ? 'En ${_nextStepDistanceM.round()} m'
                                : 'En ${(_nextStepDistanceM / 1000).toStringAsFixed(1)} km',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          Text(
                            _nextInstruction,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary(isDark),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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
                    color: AppTheme.surface(isDark),
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
                        color: AppTheme.surface(isDark).withValues(alpha: 0.95),
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
                              color: AppTheme.textPrimary(isDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Recalculate button
                  Material(
                    color: AppTheme.surface(isDark),
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
                color: AppTheme.surface(isDark),
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
                          color: AppTheme.border(isDark),
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
                                  color: AppTheme.textTertiary(isDark),
                                ),
                              ),
                              Text(
                                widget.destAddress ??
                                    '${widget.destLat.toStringAsFixed(4)}, '
                                        '${widget.destLon.toStringAsFixed(4)}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary(isDark),
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
                                color: AppTheme.textPrimary(isDark),
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
                                  backgroundColor: AppTheme.whatsappGreen,
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

                    // Stop (parada) button + timer
                    if (_viajeActivo)
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: ElevatedButton.icon(
                                onPressed: _isCompleting ? null : _toggleStop,
                                icon: Icon(
                                  _activeStop != null ? Icons.play_arrow : Icons.pause,
                                  size: 20,
                                ),
                                label: Text(
                                  _activeStop != null
                                      ? 'Salir de parada  ${_formatStopTime(_stopElapsedSeconds)}'
                                      : 'Agregar parada',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _activeStop != null
                                      ? AppTheme.warning
                                      : AppTheme.textSecondary(isDark).withValues(alpha: 0.15),
                                  foregroundColor: _activeStop != null
                                      ? Colors.white
                                      : AppTheme.textPrimary(isDark),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                    if (_viajeActivo) const SizedBox(height: 10),

                    // Complete trip button
                    if (_viajeActivo)
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
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
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            height: 52,
                            width: 52,
                            child: ElevatedButton(
                              onPressed: _isCompleting ? null : _scanQrCompletion,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                                padding: EdgeInsets.zero,
                                elevation: 0,
                              ),
                              child: const Icon(Icons.qr_code_scanner, size: 24),
                            ),
                          ),
                        ],
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

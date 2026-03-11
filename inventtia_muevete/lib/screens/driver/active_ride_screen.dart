import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import '../../utils/smooth_compass_mixin.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_theme.dart';
import '../../models/notification_model.dart';
import '../../models/stop_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/completion_sync_service.dart';
import '../../services/driver_service.dart';
import '../../services/notification_service.dart';
import '../../services/routing_service.dart';
import '../../services/stop_service.dart';
import '../../utils/helpers.dart';
import '../../widgets/map_widget.dart';
import '../../widgets/qr_scanner_dialog.dart';

enum _RidePhase { goingToPickup, waitingAtPickup, inProgress, completed }

class ActiveRideScreen extends StatefulWidget {
  final Map<String, dynamic>? tripData;

  const ActiveRideScreen({super.key, this.tripData});

  @override
  State<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends State<ActiveRideScreen>
    with SingleTickerProviderStateMixin, SmoothCompassMixin {
  @override
  MapController get compassMapController => _mapController;
  @override
  bool get compassDrivesRotation => false; // _animateCamera handles rotation

  final MapController _mapController = MapController();
  final RoutingService _routingService = RoutingService();
  final DriverService _driverService = DriverService();

  _RidePhase _currentPhase = _RidePhase.goingToPickup;
  List<LatLng> _routePolyline = [];
  bool _isLoadingRoute = false;

  AnimationController? _pulseController;
  Animation<double>? _pulseAnimation;

  // Client data from tripData
  late String _clientName;
  late String _clientPhone;
  String? _clientImage;
  late String _pickupAddress;
  late String _dropoffAddress;
  late double _tripPrice;
  LatLng? _pickupLocation;
  LatLng? _dropoffLocation;
  int? _viajeId;
  int? _solicitudId;
  String? _clientUuid;

  // Real-time tracking
  List<LatLng> _breadcrumbTrail = [];
  LatLng? _lastTrailPosition;
  bool _isRecalculating = false;
  Timer? _routeRefreshTimer;
  double _distanceToTargetM = double.infinity;
  bool _isCompletingAction = false;

  static const double _completionThresholdM = 30.0;
  bool _clientCompletedEarly = false;
  RealtimeChannel? _solicitudChannel;

  // Turn-by-turn navigation
  List<RouteStep> _steps = [];
  String _nextInstruction = '';
  String _nextManeuverIcon = 'straight';
  double _nextStepDistanceM = 0;

  // Stop (parada) state
  final StopService _stopService = StopService();
  StopModel? _activeStop;
  Timer? _stopTimer;
  int _stopElapsedSeconds = 0;

  // Navigation mode state
  bool _tilt3D = false;
  double _currentTilt = 0.0; // animated 0→1

  // Speed-based zoom smoothing
  double _smoothedZoom = 17.0;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController!, curve: Curves.easeInOut),
    );

    // Extract trip data
    final data = widget.tripData ?? {};
    _clientName = data['client_name'] as String? ?? 'Pasajero';
    _clientPhone = data['client_phone'] as String? ?? '';
    _clientImage = data['client_image'] as String?;
    _pickupAddress =
        data['direccion_origen'] as String? ?? 'Punto de recogida';
    _dropoffAddress =
        data['direccion_destino'] as String? ?? 'Destino del viaje';
    _tripPrice = (data['precio'] as num?)?.toDouble() ?? 0.0;
    _viajeId = data['viaje_id'] as int?;
    _solicitudId = data['solicitud_id'] as int?;
    _clientUuid = data['user_id'] as String?;

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

    // Restore phase from DB: estado=true means trip was already started
    final viajeEstado = data['estado'] as bool? ?? false;
    if (viajeEstado) {
      _currentPhase = _RidePhase.inProgress;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startTracking();
      _loadRoute();
      _subscribeSolicitudChanges();
      _checkIfAlreadyCompleted();
    });
  }

  // ── Real-time tracking ──────────────────────────────────────────────────

  void _startTracking() {
    final locationProvider = context.read<LocationProvider>();

    // Seed trail + initial distance
    final loc =
        locationProvider.currentLocation ?? locationProvider.locationOrDefault;
    _lastTrailPosition = loc;
    _breadcrumbTrail = [loc];
    _updateDistanceAndBearing(loc);

    // Listen to GPS updates
    locationProvider.addListener(_onLocationUpdate);

    // Periodic fallback every 10s — recalculate route AND distance
    _routeRefreshTimer?.cancel();
    _routeRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      final current = context.read<LocationProvider>().currentLocation ??
          context.read<LocationProvider>().locationOrDefault;
      _updateDistanceAndBearing(current);
      _recalculateRoute(current);
    });
  }

  // ── Listen for client completing ride early ─────────────────────────────
  void _subscribeSolicitudChanges() {
    if (_solicitudId == null) return;
    _solicitudChannel = Supabase.instance.client
        .channel('solicitud_driver_$_solicitudId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'muevete',
          table: 'solicitudes_transporte',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: _solicitudId.toString(),
          ),
          callback: (payload) {
            final newEstado = payload.newRecord['estado'] as String?;
            if (newEstado == 'completada' &&
                _currentPhase == _RidePhase.inProgress &&
                !_clientCompletedEarly &&
                mounted) {
              setState(() => _clientCompletedEarly = true);
              // Show notification to driver
              NotificationService().pushLocal(
                tipo: NotificationType.viajeCompletado,
                titulo: 'Cliente completó el viaje',
                mensaje:
                    'El pasajero marcó el viaje como completado antes de llegar al destino.',
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'El pasajero completó el viaje. Puedes finalizar ahora.',
                    style: GoogleFonts.plusJakartaSans(),
                  ),
                  backgroundColor: AppTheme.warning,
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          },
        )
        .subscribe();
  }

  void _onLocationUpdate() {
    if (!mounted) return;
    final loc = context.read<LocationProvider>().currentLocation;
    if (loc == null) return;

    // Update driver location in DB
    _upsertDriverLocation(loc);

    // Skip tiny movements (< 2m)
    if (_lastTrailPosition != null &&
        _haversineMeters(_lastTrailPosition!, loc) < 2) {
      _updateDistanceAndBearing(loc);
      return;
    }

    _lastTrailPosition = loc;

    setState(() {
      _breadcrumbTrail.add(loc);
      if (_breadcrumbTrail.length > 500) _breadcrumbTrail.removeAt(0);
    });

    // Smooth animated camera move (with rotation if auto-rotate is on)
    _animateCamera(loc);

    _updateDistanceAndBearing(loc);

    if (!_isRecalculating) {
      _recalculateRoute(loc);
    } else if (_currentPhase == _RidePhase.inProgress) {
      _updateNextInstruction(loc);
    }
  }

  /// Upsert driver location in DB (ported from active_trip_screen)
  Future<void> _upsertDriverLocation(LatLng loc) async {
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
  }

  void _updateDistanceAndBearing(LatLng loc) {
    final target = _currentTarget;
    if (target == null) return;
    final dist = _haversineMeters(loc, target);
    if (mounted) setState(() => _distanceToTargetM = dist);
  }

  LatLng? get _currentTarget {
    if (_currentPhase == _RidePhase.goingToPickup ||
        _currentPhase == _RidePhase.waitingAtPickup) {
      return _pickupLocation;
    } else if (_currentPhase == _RidePhase.inProgress) {
      return _dropoffLocation;
    }
    return null;
  }

  Future<void> _recalculateRoute(LatLng from) async {
    final end = _currentTarget;
    if (end == null) return;
    _isRecalculating = true;
    try {
      final result = await _routingService.getRoute(from, end);
      if (mounted) {
        setState(() {
          _routePolyline = result.polyline;
          if (_currentPhase == _RidePhase.inProgress) {
            _steps = result.steps;
          }
        });
        if (_currentPhase == _RidePhase.inProgress) {
          _updateNextInstruction(from);
        }
      }
    } catch (_) {}
    _isRecalculating = false;
  }

  Future<void> _loadRoute() async {
    final locationProvider = context.read<LocationProvider>();
    final driverLocation = locationProvider.locationOrDefault;

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

    setState(() => _isLoadingRoute = true);

    try {
      final result = await _routingService.getRoute(start, end);
      if (mounted) {
        setState(() {
          _routePolyline = result.polyline;
          _isLoadingRoute = false;
          if (_currentPhase == _RidePhase.inProgress) {
            _steps = result.steps;
          }
        });
        if (_currentPhase == _RidePhase.inProgress) {
          final loc = context.read<LocationProvider>().locationOrDefault;
          _updateNextInstruction(loc);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _routePolyline = [start, end!];
          _isLoadingRoute = false;
        });
      }
    }
  }

  // ── Phase actions ───────────────────────────────────────────────────────

  Future<void> _advancePhase() async {
    if (_isCompletingAction) return;

    switch (_currentPhase) {
      case _RidePhase.goingToPickup:
        setState(() => _currentPhase = _RidePhase.waitingAtPickup);
        if (_clientUuid != null) {
          NotificationService().createNotification(
            userUuid: _clientUuid!,
            tipo: NotificationType.driverEsperando,
            titulo: 'Conductor esperando',
            mensaje: 'Tu conductor llegó al punto de recogida.',
            data: {'viaje_id': _viajeId, 'solicitud_id': _solicitudId},
          );
        }
        break;

      case _RidePhase.waitingAtPickup:
        // "Iniciar Viaje" — mark viaje as started
        setState(() => _isCompletingAction = true);
        try {
          if (_viajeId != null) {
            await _driverService.updateTripStatus(_viajeId!, estado: true);
          }
          if (mounted) {
            setState(() {
              _currentPhase = _RidePhase.inProgress;
              _isCompletingAction = false;
              _breadcrumbTrail.clear(); // reset trail for trip phase
              _steps = [];
              _nextInstruction = '';
              _nextManeuverIcon = 'straight';
              _nextStepDistanceM = 0;
            });
            // Immediately recalculate distance to new target (dropoff)
            final loc = context.read<LocationProvider>().locationOrDefault;
            _updateDistanceAndBearing(loc);
            _loadRoute(); // Recalculate route pickup -> dropoff
            if (_clientUuid != null) {
              NotificationService().createNotification(
                userUuid: _clientUuid!,
                tipo: NotificationType.viajeIniciado,
                titulo: 'Viaje iniciado',
                mensaje: 'Tu viaje ha comenzado. Disfruta el trayecto.',
                data: {'viaje_id': _viajeId, 'solicitud_id': _solicitudId},
              );
            }
          }
        } catch (e) {
          if (mounted) {
            setState(() => _isCompletingAction = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e')),
            );
          }
        }
        break;

      case _RidePhase.inProgress:
        // "Completar Viaje" — within 30m OR client completed early
        if (_distanceToTargetM > _completionThresholdM &&
            !_clientCompletedEarly) return;
        setState(() => _isCompletingAction = true);
        try {
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

          // Calculate wait time and charge
          int totalWaitSeconds = 0;
          double cobroEspera = 0;
          double precioEsperaMinuto = 0;
          int waitMinutes = 0;
          if (_viajeId != null) {
            totalWaitSeconds =
                await _stopService.getTotalWaitSeconds(_viajeId!);
            if (totalWaitSeconds > 0 && _solicitudId != null) {
              try {
                final solRow = await Supabase.instance.client
                    .schema('muevete')
                    .from('solicitudes_transporte')
                    .select('tipo_vehiculo')
                    .eq('id', _solicitudId!)
                    .maybeSingle();
                final tipoVehiculo = solRow?['tipo_vehiculo'] as String?;
                if (tipoVehiculo != null) {
                  final vtRow = await Supabase.instance.client
                      .schema('muevete')
                      .from('vehicle_type')
                      .select('precio_espera_minuto')
                      .eq('tipo', tipoVehiculo)
                      .maybeSingle();
                  if (vtRow != null) {
                    precioEsperaMinuto =
                        (vtRow['precio_espera_minuto'] as num?)?.toDouble() ??
                            0;
                    waitMinutes = (totalWaitSeconds / 60).ceil();
                    cobroEspera = waitMinutes * precioEsperaMinuto;
                  }
                }
              } catch (_) {}
            }
          }

          // Show confirmation dialog before completing
          if (!mounted) return;
          final isDark = context.read<ThemeProvider>().isDark;
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppTheme.surface(isDark),
              title: Text('Completar viaje',
                  style: GoogleFonts.plusJakartaSans(
                      color: AppTheme.textPrimary(isDark),
                      fontWeight: FontWeight.w700)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('¿Confirmas que llegaste al destino?',
                      style: GoogleFonts.plusJakartaSans(
                          color: AppTheme.textSecondary(isDark))),
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
                                  fontSize: 13,
                                  color: AppTheme.textPrimary(isDark),
                                  fontWeight: FontWeight.w600)),
                          if (precioEsperaMinuto > 0)
                            Text(
                                'Cobro espera: \$${cobroEspera.toStringAsFixed(2)}',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    color: AppTheme.warning,
                                    fontWeight: FontWeight.w700)),
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
                      style: GoogleFonts.plusJakartaSans(
                          color: AppTheme.textTertiary(isDark))),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success),
                  child: Text('Completar',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          );

          if (confirmed != true) {
            if (mounted) setState(() => _isCompletingAction = false);
            return;
          }

          if (_viajeId != null) {
            await Supabase.instance.client
                .schema('muevete')
                .from('viajes')
                .update({
                  'completado': true,
                  'estado': false,
                  'tiempo_espera_segundos': totalWaitSeconds,
                  'cobro_espera': cobroEspera,
                })
                .eq('id', _viajeId!);
          }
          if (_solicitudId != null) {
            await _driverService.updateSolicitudEstado(
                _solicitudId!, 'completada');
          }
          if (mounted) {
            setState(() {
              _currentPhase = _RidePhase.completed;
              _isCompletingAction = false;
            });
            if (_clientUuid != null) {
              NotificationService().createNotification(
                userUuid: _clientUuid!,
                tipo: NotificationType.viajeCompletado,
                titulo: 'Viaje completado',
                mensaje: 'Has llegado a tu destino. Gracias por usar Muevete.',
                data: {'viaje_id': _viajeId, 'solicitud_id': _solicitudId},
              );
            }
            // Local notification for driver
            NotificationService().pushLocal(
              tipo: NotificationType.viajeCompletado,
              titulo: 'Viaje completado',
              mensaje: 'El viaje ha finalizado correctamente.',
            );
            _showCompletionDialog();
          }
        } catch (e) {
          if (mounted) {
            setState(() => _isCompletingAction = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e')),
            );
          }
        }
        break;

      case _RidePhase.completed:
        break;
    }
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
        return 'Llegué al punto';
      case _RidePhase.waitingAtPickup:
        return 'Iniciar Viaje';
      case _RidePhase.inProgress:
        if (_clientCompletedEarly) {
          return 'Completar Viaje (cliente finalizó)';
        }
        if (_distanceToTargetM > _completionThresholdM) {
          if (_distanceToTargetM == double.infinity) {
            return 'Calculando distancia...';
          }
          final distStr = _distanceToTargetM < 1000
              ? '${_distanceToTargetM.toStringAsFixed(0)} m'
              : '${(_distanceToTargetM / 1000).toStringAsFixed(1)} km';
          return 'Faltan $distStr';
        }
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
        return _clientCompletedEarly ? AppTheme.warning : AppTheme.success;
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

  bool get _canComplete =>
      _currentPhase == _RidePhase.inProgress &&
      (_distanceToTargetM <= _completionThresholdM || _clientCompletedEarly);

  bool get _actionEnabled {
    if (_isCompletingAction) return false;
    if (_currentPhase == _RidePhase.completed) return false;
    if (_currentPhase == _RidePhase.inProgress && !_canComplete) return false;
    return true;
  }

  // ── Completion dialog ───────────────────────────────────────────────────

  void _showCompletionDialog() {
    final isDark = context.read<ThemeProvider>().isDark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppTheme.surface(isDark),
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
                  color: AppTheme.textPrimary(isDark),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Has completado el viaje exitosamente.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: AppTheme.textSecondary(isDark),
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

  // ── Helpers ─────────────────────────────────────────────────────────────

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

  // ── Check if viaje was already completed by client ─────────────────────
  Future<void> _checkIfAlreadyCompleted() async {
    if (_viajeId == null) return;
    try {
      final row = await Supabase.instance.client
          .schema('muevete')
          .from('viajes')
          .select('completado')
          .eq('id', _viajeId!)
          .maybeSingle();
      if (row != null && (row['completado'] as bool? ?? false) && mounted) {
        setState(() => _clientCompletedEarly = true);
      }
    } catch (_) {}
  }

  // ── Turn-by-turn navigation ──────────────────────────────────────────
  void _updateNextInstruction(LatLng driverPos) {
    if (_steps.isEmpty) return;
    RouteStep? best;
    double bestDist = double.infinity;
    for (final step in _steps) {
      if (step.maneuverType == 'depart') continue;
      final d = _haversineMeters(driverPos, step.location);
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

  // ── Stop (parada) management ──────────────────────────────────────────
  Future<void> _toggleStop() async {
    if (_activeStop != null) {
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
            SnackBar(
              content: Text('Error al salir de parada: $e'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      }
    } else {
      final loc = context.read<LocationProvider>().locationOrDefault;
      final authProvider = context.read<AuthProvider>();
      final rawId = authProvider.driverProfile?['id'];
      final driverId =
          rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
      if (driverId == null || _viajeId == null) return;

      try {
        final stop = await _stopService.createStop(
          _viajeId!, driverId, loc.latitude, loc.longitude,
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
            SnackBar(
              content: Text('Error al agregar parada: $e'),
              backgroundColor: AppTheme.error,
            ),
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

  // ── QR scan for offline completion ─────────────────────────────────────
  Future<void> _scanQrCompletion() async {
    final data = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (_) => const QrScannerDialog(),
    );
    if (data == null || !mounted) return;

    final qrViajeId = data['viaje_id'] as int;
    if (qrViajeId != _viajeId) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Este QR no corresponde a este viaje',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.error,
      ));
      return;
    }

    setState(() => _isCompletingAction = true);
    try {
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

      // Try online first
      if (_viajeId != null) {
        await _driverService.updateTripStatus(_viajeId!, completado: true);
        await Supabase.instance.client
            .schema('muevete')
            .from('viajes')
            .update({'completado': true, 'estado': false})
            .eq('id', _viajeId!);
      }
      if (_solicitudId != null) {
        await _driverService.updateSolicitudEstado(_solicitudId!, 'completada');
      }

      if (mounted) {
        setState(() {
          _currentPhase = _RidePhase.completed;
          _isCompletingAction = false;
        });
        if (_clientUuid != null) {
          NotificationService().createNotification(
            userUuid: _clientUuid!,
            tipo: NotificationType.viajeCompletado,
            titulo: 'Viaje completado',
            mensaje: 'Has llegado a tu destino. Gracias por usar Muevete.',
            data: {'viaje_id': _viajeId, 'solicitud_id': _solicitudId},
          );
        }
        _showCompletionDialog();
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
        setState(() {
          _currentPhase = _RidePhase.completed;
          _isCompletingAction = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Viaje completado localmente. Se sincronizará al tener conexión.',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppTheme.warning,
          duration: const Duration(seconds: 4),
        ));
        _showCompletionDialog();
      }
    }
  }

  // ── Navigation mode helpers ───────────────────────────────────────────

  /// Calculates target zoom based on speed AND distance to destination.
  ///
  /// Speed-based zoom (driver navigation experience):
  ///   Stopped/walking  (< 5 km/h)  → 18.0 (street-level detail)
  ///   Slow urban       (5–20 km/h) → 17.5
  ///   Normal urban     (20–40 km/h)→ 17.0
  ///   Fast urban       (40–60 km/h)→ 16.0
  ///   Highway approach (60–80 km/h)→ 15.0
  ///   Highway          (> 80 km/h) → 14.0
  ///
  /// The result is smoothed (low-pass) so the map doesn't jump between levels.
  double _zoomForSpeedAndDistance(double distanceMeters, double speedMs) {
    final speedKmh = speedMs * 3.6; // m/s → km/h

    // Speed-based target zoom
    double speedZoom;
    if (speedKmh < 5) {
      speedZoom = 18.0;
    } else if (speedKmh < 20) {
      // Interpolate 18.0 → 17.5
      speedZoom = 18.0 - (speedKmh - 5) / 15 * 0.5;
    } else if (speedKmh < 40) {
      // Interpolate 17.5 → 17.0
      speedZoom = 17.5 - (speedKmh - 20) / 20 * 0.5;
    } else if (speedKmh < 60) {
      // Interpolate 17.0 → 16.0
      speedZoom = 17.0 - (speedKmh - 40) / 20 * 1.0;
    } else if (speedKmh < 80) {
      // Interpolate 16.0 → 15.0
      speedZoom = 16.0 - (speedKmh - 60) / 20 * 1.0;
    } else {
      speedZoom = 14.0;
    }

    // Distance-based cap: don't zoom in too much when far from target
    double distanceCap;
    if (distanceMeters > 5000) {
      distanceCap = 13.0;
    } else if (distanceMeters > 2000) {
      distanceCap = 14.0;
    } else {
      distanceCap = 19.0; // no cap — let speed rule
    }

    final targetZoom = min(speedZoom, distanceCap);

    // Smooth the zoom: low-pass filter to avoid jarring jumps
    // alpha 0.15 = gradual transition over several GPS updates
    _smoothedZoom = _smoothedZoom * 0.85 + targetZoom * 0.15;

    return _smoothedZoom;
  }

  void _animateCamera(LatLng target) {
    try {
      final cam = _mapController.camera;
      final startCenter = cam.center;
      final startZoom = cam.zoom;
      final startRotation = cam.rotation;

      final targetRotation = autoRotate ? -smoothHeading : 0.0;
      final speed = context.read<LocationProvider>().currentSpeed;
      final targetZoom =
          _zoomForSpeedAndDistance(_distanceToTargetM, speed);

      // Use ticker-based animation for smooth transitions
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

        // Ease-out cubic curve
        final t = step / steps;
        final ease = 1 - pow(1 - t, 3).toDouble();

        final lat = startCenter.latitude +
            (target.latitude - startCenter.latitude) * ease;
        final lon = startCenter.longitude +
            (target.longitude - startCenter.longitude) * ease;
        final zoom = startZoom + (targetZoom - startZoom) * ease;

        double rot = startRotation;
        if (autoRotate) {
          // Shortest path rotation
          var diff = targetRotation - startRotation;
          while (diff > 180) diff -= 360;
          while (diff < -180) diff += 360;
          rot = startRotation + diff * ease;
        }

        try {
          _mapController.moveAndRotate(
            LatLng(lat, lon),
            zoom,
            rot,
          );
        } catch (_) {}
      });

    } catch (_) {
      // Fallback: snap move
      try {
        _mapController.move(target, _mapController.camera.zoom);
      } catch (_) {}
    }
  }

  void _toggle3DTilt() {
    setState(() {
      _tilt3D = !_tilt3D;
    });
    // Animate tilt
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

  @override
  void dispose() {
    disposeCompass();
    _pulseController?.dispose();
    _mapController.dispose();
    _routeRefreshTimer?.cancel();
    _stopTimer?.cancel();
    _solicitudChannel?.unsubscribe();
    try {
      context.read<LocationProvider>().removeListener(_onLocationUpdate);
    } catch (_) {}
    super.dispose();
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final locationProvider = context.watch<LocationProvider>();
    final isDark = themeProvider.isDark;

    final driverLocation = locationProvider.locationOrDefault;
    final phaseColor = _getPhaseColor();

    // Build markers
    final markers = <Marker>[];

    // Driver marker — navigation arrow when auto-rotate, car otherwise
    markers.add(
      Marker(
        point: driverLocation,
        width: 30,
        height: 30,
        rotate: autoRotate,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.primaryColor,
            border: Border.all(color: AppTheme.markerBorder(isDark), width: 2),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withValues(alpha: 0.4),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(
            autoRotate ? Icons.navigation : Icons.directions_car,
            color: Colors.white,
            size: 16,
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

    // Grey breadcrumb trail
    if (_breadcrumbTrail.length >= 2) {
      polylines.add(
        Polyline(
          points: List.from(_breadcrumbTrail),
          strokeWidth: 4.0,
          color: Colors.grey.withValues(alpha: 0.6),
        ),
      );
    }

    // Animated route — glow layer underneath
    if (_routePolyline.isNotEmpty) {
      polylines.add(
        Polyline(
          points: _routePolyline,
          strokeWidth: 10.0,
          color: phaseColor.withValues(alpha: 0.2),
        ),
      );
      // Solid route on top
      polylines.add(
        Polyline(
          points: _routePolyline,
          strokeWidth: 4.5,
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
            perspectiveTilt: _currentTilt,
          ),

          // Navigation mode FABs
          Positioned(
            right: 16,
            bottom: 320,
            child: Column(
              children: [
                _buildNavModeButton(
                  icon: autoRotate
                      ? Icons.explore
                      : Icons.explore_off,
                  label: 'Rotación',
                  isActive: autoRotate,
                  onPressed: toggleAutoRotate,
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
                _buildNavModeButton(
                  icon: Icons.view_in_ar,
                  label: '3D',
                  isActive: _tilt3D,
                  onPressed: _toggle3DTilt,
                  isDark: isDark,
                ),
              ],
            ),
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
                    color: AppTheme.surface(isDark).withValues(alpha: 0.9),
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
                          color: AppTheme.textSecondary(isDark),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Turn-by-turn navigation banner
          if (_currentPhase == _RidePhase.inProgress &&
              _nextInstruction.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 70,
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

          // Top status bar
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
              child: Row(
                children: [
                  _buildTopButton(
                    icon: Icons.arrow_back,
                    isDark: isDark,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
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
                          _AnimatedPulseDot(
                            animation: _pulseAnimation ?? const AlwaysStoppedAnimation(0.8),
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
                                    AppTheme.textPrimary(isDark),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_currentPhase == _RidePhase.inProgress) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 1,
                              height: 16,
                              color: AppTheme.shimmer(isDark),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              (_distanceToTargetM == double.infinity ||
                                      _distanceToTargetM.isNaN)
                                  ? '—'
                                  : _distanceToTargetM < 1000
                                      ? '${_distanceToTargetM.toStringAsFixed(0)} m'
                                      : '${(_distanceToTargetM / 1000).toStringAsFixed(1)} km',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _canComplete
                                    ? AppTheme.success
                                    : AppTheme.textSecondary(isDark),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildTopButton(
                    icon: _getPhaseIcon(),
                    isDark: isDark,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),

          // Bottom draggable card with client info and actions
          DraggableScrollableSheet(
            initialChildSize: 0.38,
            minChildSize: 0.06,
            maxChildSize: 0.58,
            snap: true,
            snapSizes: const [0.06, 0.38, 0.58],
            builder: (context, scrollController) => Container(
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
              child: SingleChildScrollView(
                controller: scrollController,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
                              color: AppTheme.shimmer(isDark),
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
                            image: _clientImage != null &&
                                    _clientImage!.isNotEmpty
                                ? DecorationImage(
                                    image:
                                        NetworkImage(_clientImage!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: (_clientImage == null ||
                                  _clientImage!.isEmpty)
                              ? const Icon(
                                  Icons.person,
                                  color: AppTheme.primaryColor,
                                  size: 26,
                                )
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _clientName,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary(isDark),
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
                                  color: AppTheme.textSecondary(isDark),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
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
                            AppTheme.card(isDark),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppTheme.border(isDark),
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
                                    color: AppTheme.textPrimary(isDark),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                                left: 4, top: 4, bottom: 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                width: 1,
                                height: 16,
                                color: AppTheme.shimmer(isDark),
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
                                    color: AppTheme.textPrimary(isDark),
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
                    const SizedBox(height: 12),

                    // Stop (parada) button — only during inProgress
                    if (_currentPhase == _RidePhase.inProgress)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: _isCompletingAction ? null : _toggleStop,
                            icon: Icon(
                              _activeStop != null
                                  ? Icons.play_arrow
                                  : Icons.pause,
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
                                  : AppTheme.textSecondary(isDark)
                                      .withValues(alpha: 0.15),
                              foregroundColor: _activeStop != null
                                  ? Colors.white
                                  : AppTheme.textPrimary(isDark),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ),

                    // Communication buttons + Action button + QR
                    Row(
                      children: [
                        // Call button
                        SizedBox(
                          height: 50,
                          width: 50,
                          child: ElevatedButton(
                            onPressed: _clientPhone.isNotEmpty
                                ? () => _launchCall(_clientPhone)
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.card(isDark),
                              foregroundColor: AppTheme.textPrimary(isDark),
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
                            onPressed: _clientPhone.isNotEmpty
                                ? () => _launchWhatsApp(_clientPhone)
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.whatsappGreen,
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
                            child: ElevatedButton.icon(
                              onPressed:
                                  _actionEnabled ? _advancePhase : null,
                              icon: _isCompletingAction
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Icon(
                                      _currentPhase ==
                                                  _RidePhase.inProgress &&
                                              !_canComplete
                                          ? Icons.lock_outline
                                          : null,
                                      size: 18,
                                    ),
                              label: Text(
                                _getActionButtonLabel(),
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _actionEnabled
                                    ? phaseColor
                                    : Colors.grey[400],
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: Colors.grey[400],
                                disabledForegroundColor:
                                    Colors.white.withValues(alpha: 0.7),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ),
                        // QR scan button — only during inProgress
                        if (_currentPhase == _RidePhase.inProgress) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 50,
                            width: 50,
                            child: ElevatedButton(
                              onPressed:
                                  _isCompletingAction ? null : _scanQrCompletion,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: EdgeInsets.zero,
                                elevation: 0,
                              ),
                              child:
                                  const Icon(Icons.qr_code_scanner, size: 22),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavModeButton({
    required IconData icon,
    required String label,
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
            : AppTheme.surface(isDark),
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
            width: 46,
            height: 46,
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: isActive
                  ? Colors.white
                  : AppTheme.iconColor(isDark),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopButton({
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppTheme.surface(isDark),
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
            color: AppTheme.textPrimary(isDark),
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

import 'dart:async';
import 'dart:io';
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
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/transport_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/driver_service.dart';
import '../../services/notification_service.dart';
import '../../services/routing_service.dart';
import '../../utils/helpers.dart';
import '../../utils/app_error.dart';
import '../../services/completion_sync_service.dart';
import '../../services/offline_queue_service.dart';
import '../../widgets/map_widget.dart';
import '../../widgets/ficha_contraparte_sheet.dart';
import '../../widgets/panic_button.dart';
import '../../widgets/qr_completion_dialog.dart';
import '../../widgets/rating_dialog.dart';
import '../../widgets/share_trip_sheet.dart';
import '../../services/stop_service.dart';

class RideConfirmedScreen extends StatefulWidget {
  const RideConfirmedScreen({super.key});

  @override
  State<RideConfirmedScreen> createState() => _RideConfirmedScreenState();
}

class _RideConfirmedScreenState extends State<RideConfirmedScreen>
    with SingleTickerProviderStateMixin, SmoothCompassMixin {
  final MapController _mapController = MapController();
  @override
  MapController get compassMapController => _mapController;
  @override
  bool get compassDrivesRotation => true;
  AnimationController? _pulseController;
  Animation<double>? _pulseAnimation;

  // Real driver position polled from muevete.place
  LatLng? _driverPosition;
  Timer? _locationPollTimer;
  bool _isCompleting = false;
  double _precioEsperaMinuto = 0;
  final StopService _stopService = StopService();

  // Real-time client tracking
  List<LatLng> _clientTrail = []; // breadcrumb trail (grey)
  List<LatLng> _currentRoute = []; // current optimal route to destination
  double _distanceToDestinationM = double.infinity;
  static const double _completeThresholdM = 30.0;
  bool _isRecalculating = false;
  Timer? _routeRefreshTimer; // periodic fallback every 10s

  final RoutingService _routingService = RoutingService();
  List<LatLng> _walkingSegment = [];

  LatLng? _lastClientPosition;
  // Whether the driver has started the trip (hide driver marker from map)
  bool _tripStarted = false;
  bool _tilt3D = false;
  double _currentTilt = 0.0;
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
      CurvedAnimation(parent: _pulseController!, curve: Curves.easeInOut),
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
      _checkIfTripAlreadyStarted();
      _startDriverTracking();
      _startClientTracking();
      _fetchPrecioEspera();
      // Periodic fallback: recalculate route every 10s regardless of movement
      _routeRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (!mounted) return;
        final loc = context.read<LocationProvider>().currentLocation ??
            context.read<LocationProvider>().locationOrDefault;
        _forceRecalculateRoute(loc);
      });
    });
  }

  Future<void> _fetchPrecioEspera() async {
    try {
      final tp = context.read<TransportProvider>();
      final idTipoVehiculo = tp.activeRequest?.idTipoVehiculo;
      final tipoVehiculo = tp.activeRequest?.tipoVehiculo;

      PostgrestFilterBuilder<List<Map<String, dynamic>>> query = Supabase.instance.client
          .schema('muevete')
          .from('vehicle_type')
          .select('precio_espera_min');

      if (idTipoVehiculo != null) {
        query = query.eq('id', idTipoVehiculo);
      } else if (tipoVehiculo != null) {
        query = query.eq('tipo', tipoVehiculo);
      } else {
        return;
      }

      final row = await query.maybeSingle();
      if (row != null && mounted) {
        setState(() {
          _precioEsperaMinuto =
              (row['precio_espera_min'] as num?)?.toDouble() ?? 0;
        });
      }
    } catch (_) {}
  }

  /// Check if the viaje was already started (estado=true) so we restore
  /// _tripStarted on reopen.
  ///
  /// El viaje lo asigna `fn_tomar_viaje`; el provider lo resuelve desde la
  /// solicitud (`activeViajeId`). Ya no se consultan ofertas.
  Future<void> _checkIfTripAlreadyStarted() async {
    try {
      final tp = context.read<TransportProvider>();
      final viajeId = tp.activeViajeId;
      if (viajeId == null) return;

      final viaje = await Supabase.instance.client
          .schema('muevete')
          .from('viajes')
          .select('id, estado')
          .eq('id', viajeId)
          .maybeSingle();

      if (viaje == null) {
        debugPrint('[RideConfirmed] No se encontró el viaje $viajeId');
        return;
      }

      if (mounted && viaje['estado'] == true) {
        setState(() {
          _tripStarted = true;
          _driverToClientRoute = [];
          _driverEtaSeconds = 0;
        });
      }
    } catch (e) {
      debugPrint('[RideConfirmed] _checkIfTripAlreadyStarted error: $e');
    }
  }

  // ─── Driver tracking (poll every 8s) ────────────────────────────────────
  Future<void> _startDriverTracking() async {
    final driverId =
        context.read<TransportProvider>().conductorAsignado?.driverId;
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
    _lastClientPosition = loc;

    setState(() {
      _clientTrail.add(loc);
      if (_clientTrail.length > 500) _clientTrail.removeAt(0);
    });

    // Smooth animated camera follow (with rotation if enabled)
    _animateCamera(loc);

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
        _fetchWalkingSegment();
      }
    } catch (_) {
      // Keep previous route on error
    }
    // Always reset — even if catch fires
    _isRecalculating = false;
  }

  Future<void> _fetchWalkingSegment() async {
    if (_currentRoute.isEmpty) return;
    final dest = context.read<TransportProvider>().dropoffLocation;
    if (dest == null) return;
    final distToEnd =
        const Distance().as(LengthUnit.Meter, _currentRoute.last, dest);
    if (distToEnd <= 30) {
      if (_walkingSegment.isNotEmpty && mounted) {
        setState(() => _walkingSegment = []);
      }
      return;
    }
    try {
      final result =
          await _routingService.getWalkingRoute(_currentRoute.last, dest);
      if (mounted) setState(() => _walkingSegment = result.polyline);
    } catch (_) {
      if (mounted) {
        setState(() => _walkingSegment = [_currentRoute.last, dest]);
      }
    }
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


  // ─── Early complete confirmation ────────────────────────────────────────
  void _confirmEarlyComplete(String distStr) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Completar viaje antes de llegar',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Aún faltan $distStr para llegar al destino. '
          '¿Estás seguro de que deseas completar el viaje ahora?',
          style: GoogleFonts.plusJakartaSans(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _completeRide();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.warning,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sí, completar'),
          ),
        ],
      ),
    );
  }

  // ─── Complete ride ───────────────────────────────────────────────────────
  Future<void> _completeRide() async {
    final tp = context.read<TransportProvider>();
    final requestId = tp.activeRequest?.id;
    if (requestId == null || _isCompleting) return;

    // Capture IDs before any reset
    final viajeId = tp.activeViajeId;
    final driverId = tp.conductorAsignado?.driverId;
    final userId = context.read<AuthProvider>().user?.id;

    // 1. Check and end any active stop if client is completing the ride
    if (viajeId == null) {
      debugPrint('[RideConfirmed] ALERTA: viajeId es NULO en _completeRide');
    }

    if (viajeId != null) {
      try {
        final activeStop = await _stopService.getActiveStop(viajeId);
        if (activeStop != null) {
          debugPrint('[RideConfirmed] Cerrando parada activa antes de completar: ${activeStop.id}');
          await _stopService.endStop(activeStop.id!);
          // Briefly wait for DB to settle
          await Future.delayed(const Duration(milliseconds: 600));
        }
      } catch (e) {
        debugPrint('[RideConfirmed] Error cerrando parada activa: $e');
      }
    }

    // 2. Fetch total wait time (now including the one we just ended)
    int totalWaitSeconds = 0;
    double cobroEspera = 0;
    if (viajeId != null) {
      try {
        totalWaitSeconds = await _stopService.getTotalWaitSeconds(viajeId);
        debugPrint('[RideConfirmed] Tiempo de espera obtenido: $totalWaitSeconds seg');
      } catch (e) {
        debugPrint('[RideConfirmed] Error obteniendo tiempo de espera: $e');
      }
    }

    debugPrint('[RideConfirmed] _precioEsperaMinuto: $_precioEsperaMinuto');

    // 3. Show confirmation dialog if there are extra charges
    if (totalWaitSeconds > 0 && _precioEsperaMinuto > 0) {
      final waitMinutes = (totalWaitSeconds / 60).ceil();
      cobroEspera = waitMinutes * _precioEsperaMinuto;
      final isDark = context.read<ThemeProvider>().isDark;

      if (!mounted) return;
      final confirmWait = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface(isDark),
          title: Text('Cargos adicionales',
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary(isDark))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Se han detectado paradas durante el viaje que generan un cargo por tiempo de espera.',
                style: GoogleFonts.plusJakartaSans(
                    color: AppTheme.textSecondary(isDark)),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Tiempo total:',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: AppTheme.textSecondary(isDark))),
                        Text('$waitMinutes min',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary(isDark))),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Costo extra:',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: AppTheme.textSecondary(isDark))),
                        Text('\$${cobroEspera.toStringAsFixed(2)}',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.warning)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Este monto se sumará al total del viaje.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: AppTheme.textTertiary(isDark)),
              ),
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
                  backgroundColor: AppTheme.primaryColor),
              child: Text('Aceptar y Completar',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

      if (confirmWait != true) return;
    }

    // Try online completion first; fall back to QR only on real network failures.
    setState(() => _isCompleting = true);
    try {
      // Cierre por RPC: el servidor calcula total, comisión y neto. No se
      // envía ningún precio y la llamada es idempotente.
      final resultado = await tp.completarViaje(
        viajeId: viajeId,
        esperaMin:
            cobroEspera > 0 ? (totalWaitSeconds / 60).ceil() : null,
      );
      if (resultado == null) {
        throw Exception(tp.error ?? 'No se pudo completar el viaje');
      }

      // Recibo con el desglose congelado del servidor. Al cliente no se le
      // muestra la comisión del chofer.
      if (mounted) {
        await _showReceipt(resultado: resultado, pendiente: false);
      }

      if (mounted && viajeId != null && driverId != null && userId != null) {
        final result = await showDialog<Map<String, dynamic>?>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const RatingDialog(),
        );
        if (result != null && mounted) {
          try {
            await DriverService().submitRating(
              viajeId: viajeId,
              driverId: driverId,
              userId: userId,
              rating: result['rating'] as int,
              comentario: result['comentario'] as String?,
            );
          } catch (_) {}
        }
      }

      if (mounted) {
        tp.resetTrip();
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/client/home',
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('[RideConfirmed] Online completion failed: $e');
      if (!mounted) return;

      final canTryOffline = _isNetworkError(e) ||
          !await OfflineQueueService.hasInternetConnection();
      if (canTryOffline && viajeId != null) {
        await _completeRideOffline(
          requestId: requestId,
          viajeId: viajeId,
          esperaMin:
              cobroEspera > 0 ? (totalWaitSeconds / 60).ceil() : null,
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppError.message(e)), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isCompleting = false);
    }
  }

  bool _isNetworkError(Object e) {
    final msg = e.toString().toLowerCase();
    return e is SocketException ||
        e is TimeoutException ||
        msg.contains('socket') ||
        msg.contains('network') ||
        msg.contains('connection') ||
        msg.contains('timeout') ||
        msg.contains('failed host lookup') ||
        msg.contains('clientexception');
  }

  /// Cierre sin conexión: QR de identificación del viaje (sin precios) y
  /// encolado del cierre en la cola v2.
  Future<void> _completeRideOffline({
    required int requestId,
    required int viajeId,
    int? esperaMin,
  }) async {
    final tp = context.read<TransportProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => QrCompletionDialog(
        solicitudId: requestId,
        viajeId: viajeId,
      ),
    );
    if (confirmed != true || !mounted) return;

    // Cola v2: sólo el id del viaje (y la espera si se conoce). El servidor
    // recalcula el monto en `fn_completar_viaje`, que es idempotente.
    await CompletionSyncService.enqueueCompletion(
      viajeId: viajeId,
      esperaMin: esperaMin,
      role: 'client',
    );

    if (!mounted) return;

    // Recibo provisional: el total definitivo lo confirma el servidor.
    await _showReceipt(pendiente: true);

    if (!mounted) return;
    tp.resetTrip();
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/client/home',
      (route) => false,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Viaje pendiente de sincronización',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.warning,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ─── Recibo del cliente (desglose congelado) ────────────────────────────
  //
  // Reglas de H7:
  //  - No se calcula ningún precio en Dart. Se pintan los valores que ya
  //    devolvió el servidor: `tarifa_detalle` (snapshot de la solicitud) y el
  //    jsonb del cierre (`fn_completar_viaje`).
  //  - Al cliente NO se le muestra la comisión del chofer: sólo el total y el
  //    modo de tarifa.
  //  - Si falta el desglose se muestra únicamente el total.
  //  - Si el cierre viene de la cola offline se avisa de que está pendiente.
  Future<void> _showReceipt({
    Map<String, dynamic>? resultado,
    required bool pendiente,
  }) async {
    if (!mounted) return;

    final tp = context.read<TransportProvider>();
    final isDark = context.read<ThemeProvider>().isDark;
    final solicitud = tp.activeRequest;
    final detalleSolicitud = solicitud?.tarifaDetalle;

    // Desglose interno del snapshot de cotización (`fn_cotizar_viaje`).
    final desglose = detalleSolicitud?['detalle'] is Map
        ? Map<String, dynamic>.from(detalleSolicitud!['detalle'] as Map)
        : const <String, dynamic>{};

    final total = (resultado?['precio_plataforma'] as num?)?.toDouble() ??
        solicitud?.precioPlataforma;
    final esperaMonto = (resultado?['espera_monto'] as num?)?.toDouble();
    final esperaMin = (resultado?['espera_cobrada_min'] as num?)?.toDouble() ??
        (resultado?['espera_min'] as num?)?.toDouble();
    final metodo =
        (resultado?['metodo_pago'] as String?) ?? solicitud?.metodoPago;
    final modo = (detalleSolicitud?['tarifa_modo'] as String?) ??
        (desglose['modo'] as String?) ??
        solicitud?.tarifaModo;

    final filas = <Widget>[];
    if (modo != null && modo.isNotEmpty) {
      filas.add(_filaRecibo(isDark, 'Modo de tarifa', _etiquetaModoTarifa(modo)));
    }
    final base = (desglose['base'] as num?)?.toDouble() ??
        (desglose['monto_fijo'] as num?)?.toDouble();
    if (base != null && base > 0) {
      filas.add(_filaRecibo(isDark, 'Tarifa base', Helpers.formatCup(base)));
    }
    final nocturno = (desglose['recargo_nocturno'] as num?)?.toDouble();
    if (nocturno != null && nocturno > 0) {
      filas.add(_filaRecibo(
          isDark, 'Recargo nocturno', Helpers.formatCupSigned(nocturno)));
    }
    final prima = (desglose['recargo_prima_distancia'] as num?)?.toDouble();
    if (prima != null && prima > 0) {
      filas.add(_filaRecibo(
          isDark, 'Prima por distancia', Helpers.formatCupSigned(prima)));
    }
    if (esperaMonto != null && esperaMonto > 0) {
      filas.add(_filaRecibo(
        isDark,
        'Espera (${(esperaMin ?? 0).toStringAsFixed(0)} min)',
        Helpers.formatCupSigned(esperaMonto),
      ));
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: !pendiente,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface(isDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (pendiente ? AppTheme.warning : AppTheme.success)
                        .withValues(alpha: 0.15),
                  ),
                  child: Icon(
                    pendiente ? Icons.sync_problem : Icons.check_circle,
                    color: pendiente ? AppTheme.warning : AppTheme.success,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  pendiente ? 'Recibo pendiente' : 'Recibo del viaje',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary(isDark),
                  ),
                ),
              ),
              if (metodo != null) ...[
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    metodo == 'wallet' ? 'Pago con wallet' : 'Pago en efectivo',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: AppTheme.textTertiary(isDark),
                    ),
                  ),
                ),
              ],
              if (pendiente) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Pendiente de confirmar con el servidor. El monto final '
                    'se ajusta al sincronizar, incluida la espera si aplica.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.warning,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ...filas,
              if (filas.isNotEmpty) const Divider(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Total',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary(isDark),
                      ),
                    ),
                  ),
                  Text(
                    total == null ? '—' : Helpers.formatCup(total),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Listo',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filaRecibo(
    bool isDark,
    String etiqueta,
    String valor, {
    bool destacado = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              etiqueta,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppTheme.textSecondary(isDark),
              ),
            ),
          ),
          Text(
            valor,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: destacado ? FontWeight.w800 : FontWeight.w600,
              color: AppTheme.textPrimary(isDark),
            ),
          ),
        ],
      ),
    );
  }

  /// Etiqueta legible del modo tarifario que guardó el servidor.
  String _etiquetaModoTarifa(String modo) {
    switch (modo) {
      case 'fijo':
        return 'Fija';
      case 'fijo_mas_km':
        return 'Fija + por km';
      case 'por_km':
        return 'Por kilómetro';
      default:
        return modo;
    }
  }

  @override
  void dispose() {
    disposeCompass();
    _notifSubscription?.cancel();
    _pulseController?.dispose();
    _locationPollTimer?.cancel();
    _routeRefreshTimer?.cancel();
    _mapController.dispose();
    try {
      context.read<LocationProvider>().removeListener(_onClientPositionUpdate);
    } catch (_) {}
    super.dispose();
  }

  // ── Seguridad del viaje (H2) ─────────────────────────────────────────────

  /// Verificación mutua antes de subir: `fn_ficha_contraparte` con foto,
  /// nombre, tipo de vehículo, chapa y CI parcial del chofer.
  Future<void> _abrirFichaChofer() async {
    final solicitudId = context.read<TransportProvider>().activeRequest?.id;
    if (solicitudId == null) return;
    await FichaContraparteSheet.mostrar(
      context,
      solicitudId: solicitudId,
      rolPropio: 'cliente',
      viajeId: context.read<TransportProvider>().activeViajeId,
    );
  }

  Future<void> _abrirCompartirViaje() async {
    final tp = context.read<TransportProvider>();
    final solicitudId = tp.activeRequest?.id;
    if (solicitudId == null) return;
    final conductor = tp.conductorAsignado;
    await CompartirViajeSheet.mostrar(
      context,
      solicitudId: solicitudId,
      conductor: conductor?.driverName,
      chapa: conductor?.vehicleChapa,
      posicion: context.read<LocationProvider>().locationOrDefault,
    );
  }

  /// Hoja de seguridad: verificación, compartir y llamada al 106.
  Future<void> _abrirSeguridad() async {
    final isDark = context.read<ThemeProvider>().isDark;
    final textPrimary = AppTheme.textPrimary(isDark);
    final textSecondary = AppTheme.textSecondary(isDark);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppTheme.surface(isDark),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                Text(
                  'Seguridad del viaje',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _abrirFichaChofer();
                  },
                  icon: const Icon(Icons.badge_outlined, size: 20),
                  label: const Text('Verificar chofer y chapa'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    side: const BorderSide(color: AppTheme.primaryColor),
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _abrirCompartirViaje();
                  },
                  icon: const Icon(Icons.share_location_outlined, size: 20),
                  label: const Text('Compartir viaje'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: textPrimary,
                    side: BorderSide(color: AppTheme.border(isDark)),
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    PanicButton(
                      solicitudId:
                          context.read<TransportProvider>().activeRequest?.id,
                      posicion: context
                          .read<LocationProvider>()
                          .locationOrDefault,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            llamarAlPolicia(context);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.error,
                            side: const BorderSide(color: AppTheme.error),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Llamar al 106',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pushNamed(context, '/seguridad');
                  },
                  icon: const Icon(Icons.health_and_safety_outlined, size: 18),
                  label: const Text('Mi seguridad'),
                ),
                const SizedBox(height: 4),
                Text(
                  'Muevete no sustituye a la policía. Si estás en peligro, '
                  'llama al 106.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    height: 1.3,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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

    final acceptedOffer = transportProvider.conductorAsignado;
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

    // Client current position marker — navigation arrow when auto-rotate, pulsing dot otherwise
    markers.add(
      Marker(
        point: userLocation,
        width: 40,
        height: 40,
        rotate: autoRotate,
        child: autoRotate
            ? Container(
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
              )
            : _PulsingDot(animation: _pulseAnimation ?? const AlwaysStoppedAnimation(0.8)),
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
      final routePoints = [userLocation, ..._currentRoute];
      polylines.add(
        Polyline(
          points: routePoints,
          strokeWidth: 10.0,
          color: AppTheme.primaryColor.withValues(alpha: 0.2),
        ),
      );
      polylines.add(
        Polyline(
          points: routePoints,
          strokeWidth: 4.5,
          color: AppTheme.primaryColor,
        ),
      );

      // Walking segment: real walking route (or cached fallback)
      if (_walkingSegment.length >= 2) {
        polylines.add(
          Polyline(
            points: _walkingSegment,
            strokeWidth: 4.0,
            color: Colors.grey,
            pattern: const StrokePattern.dotted(spacingFactor: 3.0),
          ),
        );
      }
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
            perspectiveTilt: _currentTilt,
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
                              animation: _pulseAnimation ?? const AlwaysStoppedAnimation(0.8)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _tripStarted
                                  ? 'En curso'
                                  : 'Llega en $driverEtaMin min',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 1,
                            height: 16,
                            color: isDark ? Colors.white24 : Colors.grey[300],
                          ),
                          const SizedBox(width: 8),
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
                    onTap: _abrirSeguridad,
                  ),
                ],
              ),
            ),
          ),

          // Navigation mode FABs
          Positioned(
            right: 16,
            bottom: 320,
            child: Column(
              children: [
                _buildNavModeButton(
                  icon: autoRotate ? Icons.explore : Icons.explore_off,
                  isActive: autoRotate,
                  onPressed: toggleAutoRotate,
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
                _buildNavModeButton(
                  icon: Icons.view_in_ar,
                  isActive: _tilt3D,
                  onPressed: _toggle3DTilt,
                  isDark: isDark,
                ),
              ],
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
                                    acceptedOffer?.driverRating != null
                                        ? acceptedOffer!.driverRating!.toStringAsFixed(1)
                                        : '—',
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
                    if (_precioEsperaMinuto > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.timer_outlined,
                              size: 14,
                              color: isDark ? Colors.white54 : Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            'Espera: \$${_precioEsperaMinuto.toStringAsFixed(2)}/min',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: isDark ? Colors.white54 : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
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
                    // Seguridad del viaje (H2): emergencia siempre a un toque + compartir
                    Row(
                      children: [
                        PanicButton(
                          solicitudId:
                              transportProvider.activeRequest?.id,
                          posicion: userLocation,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: OutlinedButton.icon(
                              onPressed:
                                  transportProvider.activeRequest == null
                                      ? null
                                      : _abrirCompartirViaje,
                              icon: const Icon(
                                Icons.share_location_outlined,
                                size: 18,
                              ),
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Compartir viaje',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor:
                                    AppTheme.textSecondary(isDark),
                                side: BorderSide(
                                  color: AppTheme.border(isDark),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
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
                    // Complete ride button — always pressable when trip started
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _isCompleting
                            ? null
                            : () {
                                if (canComplete) {
                                  _completeRide();
                                } else {
                                  _confirmEarlyComplete(distStr);
                                }
                              },
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
                                    : Icons.warning_amber_rounded,
                                size: 20,
                              ),
                        label: Text(
                          _isCompleting
                              ? 'Completando...'
                              : canComplete
                                  ? 'Completar viaje'
                                  : 'Completar viaje · Faltan $distStr',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: canComplete
                              ? AppTheme.success
                              : AppTheme.warning,
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
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  void _toggle3DTilt() {
    setState(() => _tilt3D = !_tilt3D);
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

  double _zoomForDistance(double distanceMeters) {
    if (distanceMeters > 5000) return 13.0;
    if (distanceMeters > 2000) return 14.0;
    if (distanceMeters > 1000) return 15.0;
    if (distanceMeters > 500) return 16.0;
    if (distanceMeters > 200) return 17.0;
    return 17.5;
  }

  void _animateCamera(LatLng target) {
    try {
      final cam = _mapController.camera;
      final startCenter = cam.center;
      final startZoom = cam.zoom;
      final targetZoom = _zoomForDistance(_distanceToDestinationM);

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
        final t = step / steps;
        final ease = 1 - pow(1 - t, 3).toDouble();
        final lat = startCenter.latitude +
            (target.latitude - startCenter.latitude) * ease;
        final lon = startCenter.longitude +
            (target.longitude - startCenter.longitude) * ease;
        final zoom = startZoom + (targetZoom - startZoom) * ease;
        try {
          _mapController.move(LatLng(lat, lon), zoom);
        } catch (_) {}
      });
    } catch (_) {
      try {
        _mapController.move(target, _mapController.camera.zoom);
      } catch (_) {}
    }
  }

  Widget _buildNavModeButton({
    required IconData icon,
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
            : (isDark ? AppTheme.darkSurface : Colors.white),
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
            width: 44,
            height: 44,
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: isActive
                  ? Colors.white
                  : (isDark ? Colors.white70 : Colors.black54),
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

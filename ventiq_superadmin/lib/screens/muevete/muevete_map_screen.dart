import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_colors.dart';
import '../../services/muevete_service.dart';
import '../../services/routing_service.dart';
import '../../widgets/app_drawer.dart';

class MueveteMapScreen extends StatefulWidget {
  const MueveteMapScreen({super.key});
  @override
  State<MueveteMapScreen> createState() => _MueveteMapScreenState();
}

class _MueveteMapScreenState extends State<MueveteMapScreen> {
  final MapController _mapCtrl = MapController();
  final RoutingService _routingService = RoutingService();

  List<Map<String, dynamic>> _positions = [];
  bool _isLoading = true;
  bool _onlineOnly = true;
  Map<String, dynamic>? _selected;

  // Realtime
  RealtimeChannel? _placeChannel;
  Timer? _fallbackTimer;

  // Trip tracking state
  Map<String, dynamic>? _activeTripData;
  bool _isLoadingTrip = false;
  bool _isLoadingRoute = false;
  List<LatLng> _routePolyline = [];
  double _routeDistanceKm = 0;
  double _routeDurationMin = 0;

  // History trail (real route)
  List<LatLng> _historyTrailPolyline = [];
  bool _isLoadingTrail = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _subscribePlaceRealtime();
    _fallbackTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadInitialData(),
    );
  }

  @override
  void dispose() {
    _placeChannel?.unsubscribe();
    _fallbackTimer?.cancel();
    _mapCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final p = await MueveteService.getDriverPositions(onlineOnly: _onlineOnly);
      if (!mounted) return;
      setState(() {
        _positions = p;
        _isLoading = false;
      });
      // Sync selected driver if panel is open
      if (_selected != null) {
        final updated = p.firstWhere(
          (pos) => pos['id'] == _selected!['id'],
          orElse: () => _selected!,
        );
        if (updated['id'] == _selected!['id']) {
          setState(() => _selected = updated);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribePlaceRealtime() {
    _placeChannel = Supabase.instance.client
        .channel('admin_place_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'muevete',
          table: 'place',
          callback: _onPlaceUpdate,
        )
        .subscribe();
  }

  void _onPlaceUpdate(PostgresChangePayload payload) {
    if (!mounted) return;
    final newRecord = payload.newRecord;
    if (newRecord.isEmpty) return;

    final placeId = newRecord['id'];
    final lat = newRecord['latitude'];
    final lon = newRecord['longitude'];
    final estado = newRecord['estado'] as bool? ?? false;

    // Find existing position in the list
    final idx = _positions.indexWhere((p) => p['id'] == placeId);

    setState(() {
      if (idx >= 0) {
        // Update existing driver position in-place
        _positions[idx] = {..._positions[idx], ...newRecord};

        // If online-only filter is on and driver went offline, remove
        if (_onlineOnly && !estado) {
          _positions.removeAt(idx);
        }
      } else if (!_onlineOnly || estado) {
        // New driver appeared — need full data with joins, trigger a reload
        _loadInitialData();
        return;
      }
    });

    // Update selected driver if it's the one that changed
    if (_selected != null && _selected!['id'] == placeId && idx >= 0) {
      setState(() {
        _selected = _positions.firstWhere(
          (p) => p['id'] == placeId,
          orElse: () => _selected!,
        );
      });
      // Recalculate route if driver has active trip
      if (_activeTripData != null && lat != null && lon != null) {
        _calculateRoute();
      }
    }
  }

  // ─── TRIP PHASE HELPERS ─────────────────────────────────────────────

  String get _tripPhase {
    final viaje = _activeTripData?['viaje'] as Map<String, dynamic>?;
    if (viaje == null) return '';
    if (viaje['completado'] == true) return 'Completado';
    // estado is bool: false = heading to pickup, true = trip in progress
    final estado = viaje['estado'] as bool? ?? false;
    if (estado) return 'En marcha';
    return 'Hacia pickup';
  }

  Color get _tripPhaseColor {
    switch (_tripPhase) {
      case 'En marcha':
        return AppColors.secondary;
      case 'Completado':
        return AppColors.success;
      default:
        return AppColors.warning;
    }
  }

  IconData get _tripPhaseIcon {
    switch (_tripPhase) {
      case 'En marcha':
        return Icons.directions_car_rounded;
      case 'Completado':
        return Icons.check_circle_rounded;
      default:
        return Icons.directions_walk_rounded;
    }
  }

  // ─── DRIVER SELECTION & TRIP LOADING ────────────────────────────────

  void _onDriverSelected(Map<String, dynamic> p) {
    setState(() => _selected = p);
    _loadActiveTripForDriver(p);
    _loadHistoryTrail(p);
    final lat = (p['latitude'] as num?)?.toDouble();
    final lon = (p['longitude'] as num?)?.toDouble();
    if (lat != null && lon != null) _mapCtrl.move(LatLng(lat, lon), 15);
  }

  Future<void> _loadHistoryTrail(Map<String, dynamic> placeRow) async {
    final drv = placeRow['drivers'] as Map<String, dynamic>?;
    final driverId = drv?['id'] as int?;
    if (driverId == null) {
      setState(() => _historyTrailPolyline = []);
      return;
    }

    setState(() => _isLoadingTrail = true);
    try {
      final history = await MueveteService.getDriverHistory(driverId);
      if (!mounted) return;

      if (history.length < 2) {
        setState(() {
          _historyTrailPolyline = [];
          _isLoadingTrail = false;
        });
        return;
      }

      // Points from oldest to newest
      final points = history.reversed.map((h) {
        final lat = (h['latitude'] as num).toDouble();
        final lon = (h['longitude'] as num).toDouble();
        return LatLng(lat, lon);
      }).toList();

      final result = await _routingService.getRouteMultiplePointsWithDistance(points);
      if (!mounted) return;
      setState(() {
        _historyTrailPolyline = result.points;
        _isLoadingTrail = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _historyTrailPolyline = [];
          _isLoadingTrail = false;
        });
      }
    }
  }

  Future<void> _loadActiveTripForDriver(Map<String, dynamic> placeRow) async {
    final drv = placeRow['drivers'] as Map<String, dynamic>?;
    final driverId = drv?['id'] as int?;
    if (driverId == null) {
      setState(() {
        _activeTripData = null;
        _routePolyline = [];
      });
      return;
    }

    setState(() => _isLoadingTrip = true);
    try {
      final tripData = await MueveteService.getActiveTripForDriver(driverId);
      if (!mounted) return;
      setState(() {
        _activeTripData = tripData;
        _isLoadingTrip = false;
      });
      if (tripData != null) {
        _calculateRoute();
      } else {
        setState(() {
          _routePolyline = [];
          _routeDistanceKm = 0;
          _routeDurationMin = 0;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingTrip = false;
          _activeTripData = null;
          _routePolyline = [];
        });
      }
    }
  }

  // ─── ROUTE CALCULATION ──────────────────────────────────────────────

  Future<void> _calculateRoute() async {
    if (_selected == null || _activeTripData == null) return;

    final driverLat = (_selected!['latitude'] as num?)?.toDouble();
    final driverLon = (_selected!['longitude'] as num?)?.toDouble();
    if (driverLat == null || driverLon == null) return;

    final solicitud = _activeTripData!['solicitud'] as Map<String, dynamic>?;
    if (solicitud == null) return;

    final driverPos = LatLng(driverLat, driverLon);
    LatLng destination;

    if (_tripPhase == 'En marcha') {
      // Driver → destino
      final destLat = (solicitud['lat_destino'] as num?)?.toDouble();
      final destLon = (solicitud['lon_destino'] as num?)?.toDouble();
      if (destLat == null || destLon == null) return;
      destination = LatLng(destLat, destLon);
    } else {
      // Driver → pickup
      final pickLat = (solicitud['lat_origen'] as num?)?.toDouble();
      final pickLon = (solicitud['lon_origen'] as num?)?.toDouble();
      if (pickLat == null || pickLon == null) return;
      destination = LatLng(pickLat, pickLon);
    }

    setState(() => _isLoadingRoute = true);
    try {
      final result = await _routingService
          .getRouteMultiplePointsWithDistance([driverPos, destination]);
      if (!mounted) return;
      setState(() {
        _routePolyline = result.points;
        _routeDistanceKm = result.distanceKm;
        _routeDurationMin = result.durationSeconds / 60;
        _isLoadingRoute = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  // ─── CLEAR SELECTION ───────────────────────────────────────────────

  void _clearSelection() {
    setState(() {
      _selected = null;
      _activeTripData = null;
      _routePolyline = [];
      _routeDistanceKm = 0;
      _routeDurationMin = 0;
      _isLoadingTrip = false;
      _isLoadingRoute = false;
      _historyTrailPolyline = [];
      _isLoadingTrail = false;
    });
  }

  // ─── BUILD ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final online = _positions.where((p) => p['estado'] == true).length;
    final wide = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      body: Column(children: [
        // Header
        Container(
          color: Colors.white,
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              Builder(builder: (ctx) => IconButton(onPressed: () => Scaffold.of(ctx).openDrawer(), icon: Icon(Icons.menu_rounded, color: AppColors.textSecondary))),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.success, AppColors.success.withOpacity(0.7)]),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.gps_fixed_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Text('Mapa en Vivo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const Spacer(),
              // Online counter
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.success)),
                  const SizedBox(width: 6),
                  Text('$online en línea', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success)),
                ]),
              ),
              const SizedBox(width: 8),
              // Toggle
              Switch(
                value: _onlineOnly, onChanged: (v) { _onlineOnly = v; _loadInitialData(); },
                activeColor: AppColors.primary, activeTrackColor: AppColors.primary.withOpacity(0.3),
              ),
              Text(_onlineOnly ? 'Online' : 'Todos', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              IconButton(onPressed: _loadInitialData, icon: Icon(Icons.refresh_rounded, color: AppColors.textSecondary)),
            ]),
          ),
        ),
        Divider(height: 1, color: AppColors.divider),
        // Body
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Row(children: [
                  Expanded(flex: 3, child: _buildMap()),
                  if (wide) Container(width: 1, color: AppColors.divider),
                  if (wide) SizedBox(width: 340, child: _buildPanel()),
                ]),
        ),
      ]),
    );
  }

  // ─── MAP ───────────────────────────────────────────────────────────

  Widget _buildMap() {
    final driverMarkers = <Marker>[];
    for (final p in _positions) {
      final lat = (p['latitude'] as num?)?.toDouble();
      final lon = (p['longitude'] as num?)?.toDouble();
      if (lat == null || lon == null) continue;
      final on = p['estado'] as bool? ?? false;
      final isSel = _selected != null && _selected!['id'] == p['id'];

      driverMarkers.add(Marker(
        point: LatLng(lat, lon), width: 44, height: 44,
        child: GestureDetector(
          onTap: () => _onDriverSelected(p),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: on ? AppColors.primary : AppColors.textSecondary,
              shape: BoxShape.circle,
              border: Border.all(color: isSel ? AppColors.warning : Colors.white, width: isSel ? 3 : 2),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Center(child: Icon(Icons.directions_car_rounded, color: Colors.white, size: isSel ? 22 : 18)),
          ),
        ),
      ));
    }

    // Trip markers (pickup + destino)
    final tripMarkers = <Marker>[];
    if (_activeTripData != null && _selected != null) {
      final solicitud = _activeTripData!['solicitud'] as Map<String, dynamic>?;
      if (solicitud != null) {
        // Pickup marker (green)
        final pickLat = (solicitud['lat_origen'] as num?)?.toDouble();
        final pickLon = (solicitud['lon_origen'] as num?)?.toDouble();
        if (pickLat != null && pickLon != null) {
          tripMarkers.add(Marker(
            point: LatLng(pickLat, pickLon), width: 40, height: 40,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.success, shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: const Center(child: Icon(Icons.person_pin_circle_rounded, color: Colors.white, size: 22)),
            ),
          ));
        }
        // Destination marker (red)
        final destLat = (solicitud['lat_destino'] as num?)?.toDouble();
        final destLon = (solicitud['lon_destino'] as num?)?.toDouble();
        if (destLat != null && destLon != null) {
          tripMarkers.add(Marker(
            point: LatLng(destLat, destLon), width: 40, height: 40,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.error, shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: const Center(child: Icon(Icons.flag_rounded, color: Colors.white, size: 22)),
            ),
          ));
        }
      }
    }

    // History trail polyline for selected driver (real route via ORS)
    final polylines = <Polyline>[];
    if (_selected != null && _historyTrailPolyline.length >= 2) {
      // Shadow
      polylines.add(Polyline(
        points: _historyTrailPolyline,
        strokeWidth: 5,
        color: Colors.black.withOpacity(0.08),
      ));
      // Trail line
      polylines.add(Polyline(
        points: _historyTrailPolyline,
        strokeWidth: 3,
        color: AppColors.primary.withOpacity(0.5),
      ));
    }

    // Route polylines
    if (_routePolyline.isNotEmpty) {
      // Shadow polyline
      polylines.add(Polyline(
        points: _routePolyline,
        strokeWidth: 7,
        color: Colors.black.withOpacity(0.15),
      ));
      // Color polyline
      polylines.add(Polyline(
        points: _routePolyline,
        strokeWidth: 4,
        color: _tripPhaseColor,
      ));
    }

    return FlutterMap(
      mapController: _mapCtrl,
      options: const MapOptions(initialCenter: LatLng(22.4069, -79.9657), initialZoom: 7),
      children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.inventtia.superadmin'),
        if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
        if (tripMarkers.isNotEmpty) MarkerLayer(markers: tripMarkers),
        MarkerLayer(markers: driverMarkers),
      ],
    );
  }

  // ─── PANEL ─────────────────────────────────────────────────────────

  Widget _buildPanel() {
    if (_selected != null) return _buildDriverDetail();
    return Container(
      color: Colors.white,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.surfaceVariant))),
          child: Row(children: [
            Icon(Icons.list_rounded, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text('Conductores (${_positions.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ]),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _positions.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.surfaceVariant),
            itemBuilder: (_, i) {
              final p = _positions[i];
              final drv = p['drivers'] as Map<String, dynamic>?;
              final on = p['estado'] as bool? ?? false;
              return ListTile(
                dense: true,
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: on ? AppColors.success.withOpacity(0.1) : AppColors.surfaceVariant, shape: BoxShape.circle),
                  child: Center(child: Text(
                    (drv?['name'] as String? ?? '?')[0].toUpperCase(),
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: on ? AppColors.success : AppColors.textSecondary),
                  )),
                ),
                title: Text(drv?['name'] as String? ?? '—', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                subtitle: Text(on ? 'En línea' : 'Desconectado', style: TextStyle(fontSize: 11, color: on ? AppColors.success : AppColors.textSecondary)),
                trailing: Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textHint),
                onTap: () => _onDriverSelected(p),
              );
            },
          ),
        ),
      ]),
    );
  }

  // ─── DRIVER DETAIL PANEL ───────────────────────────────────────────

  Widget _buildDriverDetail() {
    final drv = _selected!['drivers'] as Map<String, dynamic>?;
    final on = _selected!['estado'] as bool? ?? false;
    final kyc = drv?['kyc'] as bool? ?? false;
    final veh = drv?['vehiculos'] as Map<String, dynamic>?;

    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header with close
          Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), shape: BoxShape.circle),
              child: Center(child: Text(
                (drv?['name'] as String? ?? '?')[0].toUpperCase(),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: AppColors.primary),
              )),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(drv?['name'] as String? ?? '—', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: on ? AppColors.success : AppColors.textSecondary)),
                const SizedBox(width: 6),
                Text(on ? 'En línea' : 'Desconectado', style: TextStyle(fontSize: 12, color: on ? AppColors.success : AppColors.textSecondary)),
              ]),
            ])),
            IconButton(onPressed: _clearSelection, icon: Icon(Icons.close_rounded, color: AppColors.textSecondary)),
          ]),
          const SizedBox(height: 20),
          _panelSection('Contacto', [
            _panelRow(Icons.email_rounded, drv?['email'] as String? ?? '—'),
            _panelRow(Icons.phone_rounded, drv?['telefono'] as String? ?? '—'),
          ]),
          _panelSection('Verificación', [
            _panelRow(Icons.verified_rounded, kyc ? 'Verificado' : 'No verificado'),
          ]),
          if (veh != null) _panelSection('Vehículo', [
            _panelRow(Icons.directions_car_rounded, '${veh['marca'] ?? ''} ${veh['modelo'] ?? ''}'),
            _panelRow(Icons.confirmation_number_rounded, veh['chapa'] as String? ?? '—'),
            _panelRow(Icons.palette_rounded, veh['color'] as String? ?? '—'),
          ]),
          _panelSection('Ubicación', [
            _panelRow(Icons.gps_fixed_rounded, '${_selected!['latitude']}, ${_selected!['longitude']}'),
          ]),

          // ─── TRIP INFO SECTION ────────────────────────────────────
          const SizedBox(height: 8),
          _buildTripSection(),

          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: () {
              final lat = (_selected!['latitude'] as num?)?.toDouble();
              final lon = (_selected!['longitude'] as num?)?.toDouble();
              if (lat != null && lon != null) _mapCtrl.move(LatLng(lat, lon), 17);
            },
            icon: const Icon(Icons.center_focus_strong_rounded, size: 18),
            label: const Text('Centrar en mapa'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          )),
        ]),
      ),
    );
  }

  // ─── TRIP INFO SECTION ─────────────────────────────────────────────

  Widget _buildTripSection() {
    if (_isLoadingTrip) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))),
      );
    }

    if (_activeTripData == null) {
      return _panelSection('Viaje Activo', [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('Sin viaje activo', style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontStyle: FontStyle.italic)),
        ),
      ]);
    }

    final solicitud = _activeTripData!['solicitud'] as Map<String, dynamic>?;
    final oferta = _activeTripData!['oferta'] as Map<String, dynamic>?;

    return _panelSection('Viaje Activo', [
      // Phase badge
      _tripChip(_tripPhase, _tripPhaseColor, _tripPhaseIcon),
      const SizedBox(height: 10),
      // Origin
      if (solicitud != null) ...[
        _tripInfoRow(Icons.trip_origin_rounded, 'Origen', solicitud['direccion_origen'] as String? ?? '—', AppColors.success),
        _tripInfoRow(Icons.flag_rounded, 'Destino', solicitud['direccion_destino'] as String? ?? '—', AppColors.error),
      ],
      // Offer info
      if (oferta != null) ...[
        _tripInfoRow(Icons.attach_money_rounded, 'Precio', '${_formatNumber(oferta['precio'])} CUP', AppColors.warning),
        if (oferta['tiempo_estimado'] != null)
          _tripInfoRow(Icons.timer_rounded, 'Estimado', '${oferta['tiempo_estimado']} min', AppColors.info),
      ],
      // Payment method from solicitud
      if (solicitud != null && solicitud['metodo_pago'] != null)
        _tripInfoRow(Icons.payment_rounded, 'Pago', solicitud['metodo_pago'] as String, AppColors.textSecondary),
      // Route metrics
      if (_routePolyline.isNotEmpty) ...[
        const Divider(height: 16),
        Row(children: [
          Expanded(child: _routeMetricChip(Icons.straighten_rounded, '${_routeDistanceKm.toStringAsFixed(1)} km')),
          const SizedBox(width: 8),
          Expanded(child: _routeMetricChip(Icons.schedule_rounded, '${_routeDurationMin.toStringAsFixed(0)} min')),
        ]),
      ],
      if (_isLoadingRoute)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textHint)),
            const SizedBox(width: 8),
            Text('Calculando ruta...', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
          ]),
        ),
    ]);
  }

  // ─── UI HELPERS ────────────────────────────────────────────────────

  Widget _tripChip(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }

  Widget _tripInfoRow(IconData icon, String label, String value, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 10),
        SizedBox(width: 60, child: Text(label, style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600))),
        Expanded(child: Text(value, style: TextStyle(fontSize: 13, color: AppColors.textPrimary))),
      ]),
    );
  }

  Widget _routeMetricChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      ]),
    );
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '—';
    final num n = value is num ? value : num.tryParse(value.toString()) ?? 0;
    if (n == n.toInt()) return n.toInt().toString();
    return n.toStringAsFixed(2);
  }

  Widget _panelSection(String title, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.5)),
      ),
      ...children,
    ]);
  }

  Widget _panelRow(IconData icon, String text) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
      Icon(icon, size: 16, color: AppColors.textHint),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: AppColors.textPrimary))),
    ]));
  }
}

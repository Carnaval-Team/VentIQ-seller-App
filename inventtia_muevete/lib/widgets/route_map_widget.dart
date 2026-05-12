import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/app_theme.dart';
import 'map_widget.dart';

/// Displays a route on the map between [latOrigen]/[lonOrigen] and
/// [latDestino]/[lonDestino]. The real road route is fetched from OSRM on
/// build; a straight-line fallback is shown while loading or on error.
///
/// Designed to be dropped in as a [height]-tall replacement for a plain
/// MapWidget + Polyline combo inside detail screens.
class RouteMapWidget extends StatefulWidget {
  final double latOrigen;
  final double lonOrigen;
  final double latDestino;
  final double lonDestino;
  final double height;
  final bool isDark;

  const RouteMapWidget({
    super.key,
    required this.latOrigen,
    required this.lonOrigen,
    required this.latDestino,
    required this.lonDestino,
    this.height = 220,
    required this.isDark,
  });

  @override
  State<RouteMapWidget> createState() => _RouteMapWidgetState();
}

class _RouteMapWidgetState extends State<RouteMapWidget> {
  final MapController _mapController = MapController();
  List<LatLng> _routePoints = [];
  bool _loading = true;

  LatLng get _origen => LatLng(widget.latOrigen, widget.lonOrigen);
  LatLng get _destino => LatLng(widget.latDestino, widget.lonDestino);
  LatLng get _center => LatLng(
        (widget.latOrigen + widget.latDestino) / 2,
        (widget.lonOrigen + widget.lonDestino) / 2,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchRoute());
  }

  @override
  void didUpdateWidget(RouteMapWidget old) {
    super.didUpdateWidget(old);
    final changed = old.latOrigen != widget.latOrigen ||
        old.lonOrigen != widget.lonOrigen ||
        old.latDestino != widget.latDestino ||
        old.lonDestino != widget.lonDestino;
    if (changed) _fetchRoute();
  }

  Future<void> _fetchRoute() async {
    if (widget.latOrigen == 0 || widget.latDestino == 0) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final url =
          'https://router.project-osrm.org/route/v1/driving/'
          '${widget.lonOrigen},${widget.latOrigen};'
          '${widget.lonDestino},${widget.latDestino}'
          '?overview=full&geometries=geojson';

      final response = await http
          .get(Uri.parse(url),
              headers: {'User-Agent': 'inventtia_muevete/1.0'})
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final geometry =
              (routes.first as Map<String, dynamic>)['geometry']
                  as Map<String, dynamic>;
          final coords = geometry['coordinates'] as List;
          final points = coords
              .map((c) => LatLng(
                  (c[1] as num).toDouble(), (c[0] as num).toDouble()))
              .toList();
          if (mounted) {
            setState(() {
              _routePoints = points;
              _loading = false;
            });
            _fitMap();
            return;
          }
        }
      }
    } catch (_) {}

    // fallback: straight line
    if (mounted) {
      setState(() {
        _routePoints = [_origen, _destino];
        _loading = false;
      });
      _fitMap();
    }
  }

  void _fitMap() {
    if (widget.latOrigen == 0 || widget.latDestino == 0) return;
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([_origen, _destino]),
          padding: const EdgeInsets.all(48),
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final hasPoints =
        widget.latOrigen != 0 && widget.latDestino != 0;

    return Stack(
      children: [
        SizedBox(
          height: widget.height,
          child: MapWidget(
            isDark: widget.isDark,
            mapController: _mapController,
            center: hasPoints ? _center : const LatLng(20, -100),
            zoom: 6.0,
            markers: [
              if (hasPoints) ...[
                Marker(
                  point: _origen,
                  width: 36,
                  height: 36,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.success,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.local_shipping,
                        color: Colors.white, size: 18),
                  ),
                ),
                Marker(
                  point: _destino,
                  width: 36,
                  height: 44,
                  alignment: Alignment.topCenter,
                  child: Icon(Icons.location_on,
                      color: AppTheme.error, size: 32),
                ),
              ],
            ],
            polylines: _routePoints.length >= 2
                ? [
                    Polyline(
                      points: _routePoints,
                      color: AppTheme.primaryColor.withValues(alpha: 0.80),
                      strokeWidth: 3.5,
                    ),
                  ]
                : const [],
          ),
        ),
        if (_loading)
          Positioned(
            bottom: 10,
            right: 10,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: Colors.white),
                  ),
                  SizedBox(width: 6),
                  Text('Calculando ruta…',
                      style:
                          TextStyle(color: Colors.white, fontSize: 11)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

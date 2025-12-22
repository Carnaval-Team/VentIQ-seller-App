import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import '../config/app_theme.dart';

class RoutePlanScreen extends StatefulWidget {
  final List<Map<String, dynamic>> stores;

  const RoutePlanScreen({super.key, required this.stores});

  @override
  State<RoutePlanScreen> createState() => _RoutePlanScreenState();
}

class _RoutePlanScreenState extends State<RoutePlanScreen> {
  final MapController _mapController = MapController();
  Position? _currentPosition;
  List<Map<String, dynamic>> _optimizedPath = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _calculateRoute();
  }

  Future<void> _calculateRoute() async {
    // 1. Get current location
    Position? position;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          position = await Geolocator.getCurrentPosition();
        }
      }
    } catch (e) {
      print('Error getting location: $e');
    }

    // Default position if null (Santa Clara)
    final startLat = position?.latitude ?? 22.40694;
    final startLng = position?.longitude ?? -79.96472;
    _currentPosition = position;

    // 2. Prepare points
    List<Map<String, dynamic>> pendingStores = List.from(widget.stores);
    List<Map<String, dynamic>> path = [];

    // Add user start point as the first item in rendering path (conceptually)
    // But we just need the stores in order.

    LatLng currentPoint = LatLng(startLat, startLng);

    // 3. Greedy Nearest Neighbor
    while (pendingStores.isNotEmpty) {
      double minDistance = double.infinity;
      int nearestIndex = -1;

      for (int i = 0; i < pendingStores.length; i++) {
        final store = pendingStores[i];
        final parts = (store['ubicacion'] as String).split(',');
        final lat = double.parse(parts[0].trim());
        final lng = double.parse(parts[1].trim());
        final storePoint = LatLng(lat, lng);

        final distance = const Distance().as(
          LengthUnit.Meter,
          currentPoint,
          storePoint,
        );

        if (distance < minDistance) {
          minDistance = distance;
          nearestIndex = i;
        }
      }

      if (nearestIndex != -1) {
        final nearestStore = pendingStores[nearestIndex];
        path.add(nearestStore);

        // Update current point to this store
        final parts = (nearestStore['ubicacion'] as String).split(',');
        final lat = double.parse(parts[0].trim());
        final lng = double.parse(parts[1].trim());
        currentPoint = LatLng(lat, lng);

        pendingStores.removeAt(nearestIndex);
      } else {
        break; // Should not happen
      }
    }

    if (mounted) {
      setState(() {
        _optimizedPath = path;
        _isLoading = false;
      });

      // Fit bounds
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fitBounds();
      });
    }
  }

  void _fitBounds() {
    if (_optimizedPath.isEmpty) return;

    final points = <LatLng>[];
    if (_currentPosition != null) {
      points.add(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      );
    }

    for (final store in _optimizedPath) {
      final parts = (store['ubicacion'] as String).split(',');
      points.add(
        LatLng(double.parse(parts[0].trim()), double.parse(parts[1].trim())),
      );
    }

    if (points.isNotEmpty) {
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.all(50),
          maxZoom: 15.0,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ruta de Compra'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _calculateRoute,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(22.40694, -79.96472), // Default center
                initialZoom: 13.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.ventiq.marketplace',
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _buildPolylinePoints(),
                      strokeWidth: 4.0,
                      color: AppTheme.primaryColor,
                    ),
                  ],
                ),
                MarkerLayer(markers: _buildMarkers()),
              ],
            ),
    );
  }

  List<LatLng> _buildPolylinePoints() {
    final points = <LatLng>[];

    // Start from user
    if (_currentPosition != null) {
      points.add(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      );
    }

    // Add path
    for (final store in _optimizedPath) {
      final parts = (store['ubicacion'] as String).split(',');
      points.add(
        LatLng(double.parse(parts[0].trim()), double.parse(parts[1].trim())),
      );
    }

    return points;
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // User marker
    if (_currentPosition != null) {
      markers.add(
        Marker(
          point: LatLng(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          ),
          width: 60,
          height: 60,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryColor.withOpacity(0.2),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.my_location, color: AppTheme.primaryColor),
          ),
        ),
      );
    }

    // Store markers with order number
    for (int i = 0; i < _optimizedPath.length; i++) {
      final store = _optimizedPath[i];
      final parts = (store['ubicacion'] as String).split(',');
      final point = LatLng(
        double.parse(parts[0].trim()),
        double.parse(parts[1].trim()),
      );

      markers.add(
        Marker(
          point: point,
          width: 70,
          height: 80,
          child: GestureDetector(
            onTap: () {
              // Optional: show info
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.primaryColor, width: 2),
                  ),
                  child: ClipOval(
                    child:
                        store['imagen_url'] != null &&
                            (store['imagen_url'] as String).startsWith('http')
                        ? Image.network(
                            store['imagen_url'],
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.store,
                              color: AppTheme.primaryColor,
                            ),
                          )
                        : const Icon(Icons.store, color: AppTheme.primaryColor),
                  ),
                ),
                ClipPath(
                  clipper: TriangleClipper(),
                  child: Container(
                    width: 14,
                    height: 10,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return markers;
  }
}

// Reusing TriangleClipper
class TriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width / 2, size.height);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

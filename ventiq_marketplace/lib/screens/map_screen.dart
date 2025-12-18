import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import '../config/app_theme.dart';
import 'store_detail_screen.dart';

class MapScreen extends StatefulWidget {
  final List<Map<String, dynamic>> stores;

  const MapScreen({super.key, required this.stores});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  Position? _currentPosition;
  Map<String, dynamic>? _selectedStore;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  StreamSubscription<Position>? _positionStreamSubscription;

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _mapController
        .dispose(); // Important if MapController needs disposal, though standard one might not strictly require it, good practice
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return;
    }

    // Get initial position
    final position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentPosition = position;
    });

    // Center map initially
    if (_mapController.mapEventStream.isBroadcast) {
      _mapController.move(LatLng(position.latitude, position.longitude), 15);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(LatLng(position.latitude, position.longitude), 15);
      });
    }

    // Subscribe to stream for updates
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Update every 10 meters
    );

    _positionStreamSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position? position) {
            if (position != null) {
              setState(() {
                _currentPosition = position;
              });
            }
          },
        );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // User location marker
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

    // Store markers
    for (final store in widget.stores) {
      final locationParts = (store['ubicacion'] as String).split(',');
      if (locationParts.length == 2) {
        try {
          final lat = double.parse(locationParts[0].trim());
          final lng = double.parse(locationParts[1].trim());

          markers.add(
            Marker(
              point: LatLng(lat, lng),
              width: 60,
              height: 70, // Increased height for pin effect
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedStore = store;
                  });
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      width: 45,
                      height: 45,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.primaryColor,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: store['imagen_url'] != null
                            ? Image.network(
                                store['imagen_url'],
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(
                                    Icons.store,
                                    color: AppTheme.primaryColor,
                                    size: 24,
                                  );
                                },
                              )
                            : const Icon(
                                Icons.store,
                                color: AppTheme.primaryColor,
                                size: 24,
                              ),
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
        } catch (e) {
          print('Error parsing location for store ${store['id']}: $e');
        }
      }
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    // Calcular centro inicial (promedio de tiendas o default)
    LatLng initialCenter = const LatLng(
      22.40694,
      -79.96472,
    ); // Default to Santa Clara based on user example
    if (widget.stores.isNotEmpty) {
      try {
        final firstStoreParts = (widget.stores.first['ubicacion'] as String)
            .split(',');
        initialCenter = LatLng(
          double.parse(firstStoreParts[0]),
          double.parse(firstStoreParts[1]),
        );
      } catch (_) {}
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: 13.0,
              onTap: (_, __) {
                if (_selectedStore != null) {
                  setState(() {
                    _selectedStore = null;
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName:
                    'com.ventiq.marketplace', // Replace with your app package
              ),
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),

          // Floating Close Button
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 16,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'close_map',
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.close, color: Colors.black),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'my_location',
                  backgroundColor: Colors.white,
                  child: const Icon(
                    Icons.my_location,
                    color: AppTheme.primaryColor,
                  ),
                  onPressed: () {
                    if (_currentPosition != null) {
                      _mapController.move(
                        LatLng(
                          _currentPosition!.latitude,
                          _currentPosition!.longitude,
                        ),
                        15,
                      );
                    } else {
                      _getCurrentLocation();
                    }
                  },
                ),
              ],
            ),
          ),

          // Store Details Sheet
          if (_selectedStore != null)
            DraggableScrollableSheet(
              controller: _sheetController,
              initialChildSize: 0.25,
              minChildSize: 0.15,
              maxChildSize: 0.4,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              image: _selectedStore!['imagen_url'] != null
                                  ? DecorationImage(
                                      image: NetworkImage(
                                        _selectedStore!['imagen_url'],
                                      ),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: _selectedStore!['imagen_url'] == null
                                ? const Icon(
                                    Icons.store,
                                    size: 30,
                                    color: AppTheme.primaryColor,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedStore!['denominacion'] ?? 'Tienda',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _selectedStore!['direccion'] ??
                                      'Sin dirección',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _selectedStore = null;
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Cerrar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => StoreDetailScreen(
                                      store: {
                                        'id': _selectedStore!['id'],
                                        'nombre':
                                            _selectedStore!['denominacion'],
                                        'logoUrl':
                                            _selectedStore!['imagen_url'],
                                        'ubicacion':
                                            _selectedStore!['ubicacion'] ??
                                            'Sin ubicación',
                                        // Default dummy data if missing from fetch, logic in StoreDetailScreen might need adjust if it expects these
                                        'provincia': 'Santo Domingo',
                                        'municipio': 'Santo Domingo Este',
                                        'direccion':
                                            _selectedStore!['direccion'] ??
                                            'Sin dirección',
                                        'productCount': 0, // Placeholder
                                        'latitude': 0, // Placeholder
                                        'longitude': 0, // Placeholder
                                      },
                                    ),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Ir a la tienda'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

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

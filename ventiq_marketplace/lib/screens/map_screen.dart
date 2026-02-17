import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import '../config/app_theme.dart';
import '../widgets/carnaval_fab.dart';
import '../widgets/supabase_image.dart';
import '../services/routing_service.dart';
import '../mixins/repartidor_map_mixin.dart';
import 'store_detail_screen.dart';

class MapScreen extends StatefulWidget {
  final List<Map<String, dynamic>> stores;
  final Map<String, dynamic>? initialStore;

  const MapScreen({super.key, required this.stores, this.initialStore});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with RepartidorMapMixin {
  final MapController _mapController = MapController();
  final RoutingService _routingService = RoutingService();
  Position? _currentPosition;
  Map<String, dynamic>? _selectedStore;
  List<LatLng>? _routePolyline;
  bool _isTracingRoute = false;
  String? _routedStoreId;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  LatLng? _parseUbicacion(dynamic ubicacion) {
    if (ubicacion == null) return null;
    final ubicacionStr = ubicacion.toString();
    if (!ubicacionStr.contains(',')) return null;
    final parts = ubicacionStr.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  String? _getStoreImageUrl(Map<String, dynamic> store) {
    final candidates = [
      store['imagen_url'],
      store['logoUrl'],
      store['imagem_url'],
      store['logo_url'],
      store['imageUrl'],
    ];

    for (final c in candidates) {
      final v = c?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  String _getStoreName(Map<String, dynamic> store) {
    return (store['denominacion'] ?? store['nombre'] ?? 'Tienda').toString();
  }

  String _getStoreAddress(Map<String, dynamic> store) {
    return (store['direccion'] ?? 'Sin dirección').toString();
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialStore != null) {
      _selectedStore = widget.initialStore;
    }
    _getCurrentLocation();
    initRepartidorTracking();
  }

  StreamSubscription<Position>? _positionStreamSubscription;

  @override
  void dispose() {
    disposeRepartidorTracking();
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

    // Center map initially only when no initialStore is provided
    if (widget.initialStore == null) {
      if (_mapController.mapEventStream.isBroadcast) {
        _mapController.move(LatLng(position.latitude, position.longitude), 15);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mapController.move(
            LatLng(position.latitude, position.longitude),
            15,
          );
        });
      }
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
      final storePoint = _parseUbicacion(store['ubicacion']);
      if (storePoint != null) {
        try {
          final imageUrl = _getStoreImageUrl(store);

          markers.add(
            Marker(
              point: storePoint,
              width: 60,
              height: 70, // Increased height for pin effect
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    final newStoreId = _getStoreIdKey(store);
                    final shouldClearRoute = _routedStoreId != newStoreId;

                    _selectedStore = store;

                    if (shouldClearRoute) {
                      _routePolyline = null;
                      _routedStoreId = null;
                    }
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
                        child: imageUrl != null
                            ? SupabaseImage(
                                imageUrl: imageUrl,
                                width: 45,
                                height: 45,
                                fit: BoxFit.cover,
                                errorWidgetOverride: const Icon(
                                  Icons.store,
                                  color: AppTheme.primaryColor,
                                  size: 24,
                                ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = AppTheme.getAccentColor(context);

    // Calcular centro inicial (promedio de tiendas o default)
    LatLng initialCenter = const LatLng(
      22.40694,
      -79.96472,
    ); // Default to Santa Clara based on user example

    if (widget.initialStore != null &&
        widget.initialStore!['ubicacion'] != null) {
      final initialPoint = _parseUbicacion(widget.initialStore!['ubicacion']);
      if (initialPoint != null) {
        initialCenter = initialPoint;
      }
    } else if (widget.stores.isNotEmpty) {
      final firstPoint = _parseUbicacion(widget.stores.first['ubicacion']);
      if (firstPoint != null) {
        initialCenter = firstPoint;
      }
    }

    // URL del mapa según tema
    final tileUrl = isDark
        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackgroundColor : Colors.white,
      floatingActionButton: const CarnavalFab(),
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
                urlTemplate: tileUrl,
                subdomains: isDark ? const ['a', 'b', 'c', 'd'] : const [],
                userAgentPackageName:
                    'com.ventiq.marketplace', // Replace with your app package
              ),
              PolylineLayer(
                polylines: [
                  if (_routePolyline != null && _routePolyline!.isNotEmpty)
                    Polyline(
                      points: _routePolyline!,
                      strokeWidth: 4.0,
                      color: AppTheme.primaryColor,
                      borderStrokeWidth: 2.0,
                      borderColor: Colors.white,
                    ),
                ],
              ),
              MarkerLayer(markers: [..._buildMarkers(), ...buildRepartidorMarkers()]),
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
                  backgroundColor: isDark ? AppTheme.darkCardBackground : Colors.white,
                  child: Icon(Icons.close, color: isDark ? Colors.white : Colors.black),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'my_location',
                  backgroundColor: isDark ? AppTheme.darkCardBackground : Colors.white,
                  child: Icon(
                    Icons.my_location,
                    color: accentColor,
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
                const SizedBox(height: 8),
                buildRepartidorToggleButton(),
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
                final cardColor = AppTheme.getCardColor(context);
                final textPrimary = AppTheme.getTextPrimaryColor(context);
                final textSecondary = AppTheme.getTextSecondaryColor(context);

                return Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.3 : 0.1),
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
                            color: isDark ? Colors.grey[700] : Colors.grey[300],
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
                              color: isDark ? AppTheme.darkSurfaceColor : Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: _getStoreImageUrl(_selectedStore!) != null
                                ? SupabaseImage(
                                    imageUrl: _getStoreImageUrl(
                                      _selectedStore!,
                                    )!,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    borderRadius: 12,
                                    errorWidgetOverride: Icon(
                                      Icons.store,
                                      size: 30,
                                      color: accentColor,
                                    ),
                                  )
                                : Icon(
                                    Icons.store,
                                    size: 30,
                                    color: accentColor,
                                  ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _getStoreName(_selectedStore!),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _getStoreAddress(_selectedStore!),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: textSecondary,
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
                      Column(
                        children: [
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
                                    foregroundColor: textSecondary,
                                    side: BorderSide(color: textSecondary.withOpacity(0.3)),
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
                                  onPressed: _isTracingRoute
                                      ? null
                                      : _traceRouteToSelectedStore,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: accentColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _isTracingRoute
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text('Ir a la tienda'),
                                ),
                              ),
                            ],
                          ),
                          if (_hasRouteForSelectedStore) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => StoreDetailScreen(
                                        store: {
                                          'id': _selectedStore!['id'],
                                          'nombre': _getStoreName(
                                            _selectedStore!,
                                          ),
                                          'logoUrl': _getStoreImageUrl(
                                            _selectedStore!,
                                          ),
                                          'ubicacion':
                                              _selectedStore!['ubicacion'] ??
                                              'Sin ubicación',
                                          'provincia': 'Santo Domingo',
                                          'municipio': 'Santo Domingo Este',
                                          'direccion': _getStoreAddress(
                                            _selectedStore!,
                                          ),
                                          'phone': _selectedStore!['phone'],
                                          'productCount': 0,
                                          'latitude': 0,
                                          'longitude': 0,
                                        },
                                      ),
                                    ),
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: accentColor,
                                  side: BorderSide(color: accentColor.withOpacity(0.3)),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text('Visitar tienda'),
                              ),
                            ),
                          ],
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

  String _getStoreIdKey(Map<String, dynamic> store) {
    final id = store['id'];
    if (id == null) return store.hashCode.toString();
    return id.toString();
  }

  bool get _hasRouteForSelectedStore {
    if (_selectedStore == null) return false;
    if (_routePolyline == null || _routePolyline!.isEmpty) return false;
    return _routedStoreId == _getStoreIdKey(_selectedStore!);
  }

  Future<void> _traceRouteToSelectedStore() async {
    final store = _selectedStore;
    if (store == null) return;

    final endPoint = _parseUbicacion(store['ubicacion']);
    if (endPoint == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esta tienda no tiene ubicación válida')),
      );
      return;
    }

    setState(() {
      _isTracingRoute = true;
    });

    LatLng startPoint;
    if (_currentPosition != null) {
      startPoint = LatLng(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );
    } else {
      try {
        final position = await Geolocator.getCurrentPosition();
        if (mounted) {
          setState(() {
            _currentPosition = position;
          });
        }
        startPoint = LatLng(position.latitude, position.longitude);
      } catch (_) {
        startPoint = const LatLng(22.40694, -79.96472);
      }
    }

    final polyline = await _routingService.getRouteBetweenPoints(
      startPoint,
      endPoint,
    );

    if (!mounted) return;

    setState(() {
      _routePolyline = polyline;
      _routedStoreId = _getStoreIdKey(store);
      _isTracingRoute = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fitRouteBounds(polyline);
    });
  }

  void _fitRouteBounds(List<LatLng> points) {
    if (points.isEmpty) return;
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.all(50),
        maxZoom: 16.0,
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

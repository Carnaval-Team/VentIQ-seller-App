import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import '../config/app_theme.dart';
import '../services/routing_service.dart';
import '../widgets/supabase_image.dart';

class RoutePlanScreen extends StatefulWidget {
  final List<Map<String, dynamic>> stores;

  const RoutePlanScreen({super.key, required this.stores});

  @override
  State<RoutePlanScreen> createState() => _RoutePlanScreenState();
}

class _RoutePlanScreenState extends State<RoutePlanScreen> {
  final MapController _mapController = MapController();
  final RoutingService _routingService = RoutingService();
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  List<Map<String, dynamic>> _optimizedPath = [];
  List<LatLng>? _routePolyline; // Polyline real de OSRM
  bool _isLoading = true;
  double? _totalDistance;
  double? _totalDuration;

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

  @override
  void initState() {
    super.initState();
    _startLocationTracking();
    _calculateRoute();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  /// Inicia el seguimiento de ubicación en tiempo real
  void _startLocationTracking() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        // Obtener posición inicial
        final position = await Geolocator.getCurrentPosition();
        setState(() {
          _currentPosition = position;
        });

        // Suscribirse a actualizaciones
        const locationSettings = LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5, // Actualizar cada 5 metros (más frecuente)
        );

        _positionStreamSubscription =
            Geolocator.getPositionStream(
              locationSettings: locationSettings,
            ).listen((Position position) {
              if (mounted) {
                setState(() {
                  _currentPosition = position;
                });
                print(
                  '📍 Ubicación actualizada: ${position.latitude}, ${position.longitude}',
                );
              }
            });
      }
    } catch (e) {
      print('❌ Error iniciando tracking: $e');
    }
  }

  Future<void> _calculateRoute() async {
    setState(() {
      _isLoading = true;
    });

    // 1. Obtener ubicación actual
    Position? position = _currentPosition;
    if (position == null) {
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
        print('❌ Error obteniendo ubicación: $e');
      }
    }

    // Ubicación por defecto si no se puede obtener
    final startLat = position?.latitude ?? 22.40694;
    final startLng = position?.longitude ?? -79.96472;
    final startPoint = LatLng(startLat, startLng);

    if (position != null) {
      setState(() {
        _currentPosition = position;
      });
    }

    // 2. Preparar puntos de tiendas
    final storePoints = <LatLng>[];
    for (final store in widget.stores) {
      try {
        final parts = (store['ubicacion'] as String).split(',');
        final lat = double.parse(parts[0].trim());
        final lng = double.parse(parts[1].trim());
        storePoints.add(LatLng(lat, lng));
      } catch (e) {
        print('⚠️ Error parseando ubicación de tienda: $e');
      }
    }

    if (storePoints.isEmpty) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    // 3. Obtener ruta optimizada de OSRM
    try {
      final routeResult = await _routingService.getOptimizedRoute(
        startPoint,
        storePoints,
      );

      // 4. Reordenar tiendas según el orden optimizado
      final optimizedStores = <Map<String, dynamic>>[];
      // routeResult.waypointOrder ahora contiene índices de entrada ordenados
      // por el orden de visita del trip (incluyendo el índice 0 = start).
      for (final inputIndex in routeResult.waypointOrder) {
        if (inputIndex == 0) continue; // 0 = ubicación actual
        final storeIndex = inputIndex - 1; // stores empiezan en 1
        if (storeIndex >= 0 && storeIndex < widget.stores.length) {
          optimizedStores.add(widget.stores[storeIndex]);
        }
      }

      if (mounted) {
        setState(() {
          _optimizedPath = optimizedStores;
          _routePolyline = routeResult.polyline;
          _totalDistance = routeResult.totalDistance;
          _totalDuration = routeResult.totalDuration;
          _isLoading = false;
        });

        // Ajustar vista del mapa
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _fitBounds();
        });
      }
    } catch (e) {
      print('❌ Error calculando ruta: $e');
      // Fallback: usar orden original
      if (mounted) {
        setState(() {
          _optimizedPath = widget.stores;
          _isLoading = false;
        });
      }
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
                MarkerLayer(
                  key: ValueKey(
                    '${_currentPosition?.latitude}_${_currentPosition?.longitude}',
                  ),
                  markers: _buildMarkers(),
                ),
              ],
            ),
    );
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
      final storeName = (store['denominacion'] ?? store['nombre'] ?? 'Tienda')
          .toString();
      final parts = (store['ubicacion'] as String).split(',');
      final point = LatLng(
        double.parse(parts[0].trim()),
        double.parse(parts[1].trim()),
      );

      markers.add(
        Marker(
          point: point,
          width: 180,
          height: 85,
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
                  constraints: const BoxConstraints(maxWidth: 180),
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
                    '$storeName (${i + 1})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.primaryColor, width: 2),
                  ),
                  child: ClipOval(
                    child: _getStoreImageUrl(store) != null
                        ? SupabaseImage(
                            imageUrl: _getStoreImageUrl(store)!,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorWidgetOverride: const Icon(
                              Icons.store,
                              color: AppTheme.primaryColor,
                              size: 20,
                            ),
                          )
                        : const Icon(
                            Icons.store,
                            color: AppTheme.primaryColor,
                            size: 20,
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

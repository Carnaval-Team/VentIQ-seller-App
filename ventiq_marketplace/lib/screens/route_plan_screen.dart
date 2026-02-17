import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import '../config/app_theme.dart';
import '../services/cart_service.dart';
import '../services/routing_service.dart';
import '../widgets/supabase_image.dart';

class RoutePlanScreen extends StatefulWidget {
  final List<Map<String, dynamic>> stores;
  final Map<int, List<CartItem>> itemsByStore;

  const RoutePlanScreen({
    super.key,
    required this.stores,
    required this.itemsByStore,
  });

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

  bool _isBottomPanelExpanded = true;
  bool _isStoreItemsPanelExpanded = true;

  bool _isTravelActive = false;
  int _currentStopIndex = 0;
  List<LatLng>? _currentLegPolyline;
  bool _isUpdatingLegRoute = false;
  DateTime? _lastLegRouteUpdateAt;
  double? _distanceToTargetMeters;
  String? _arrivalBannerText;
  Timer? _arrivalBannerTimer;
  Timer? _travelTickTimer;
  int? _lastArrivedStopIndex;

  final Set<int> _visitedStopIndices = <int>{};

  bool _isLegRouteFallback = false;
  bool _isLoadingStoreLegs = false;
  List<List<LatLng>?> _storeLegPolylines = [];

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
    _arrivalBannerTimer?.cancel();
    _travelTickTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

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

  LatLng? _getCurrentLatLng() {
    final pos = _currentPosition;
    if (pos == null) return null;
    return LatLng(pos.latitude, pos.longitude);
  }

  Map<String, dynamic>? _getCurrentTargetStore() {
    if (_optimizedPath.isEmpty) return null;
    if (_currentStopIndex < 0 || _currentStopIndex >= _optimizedPath.length) {
      return null;
    }
    return _optimizedPath[_currentStopIndex];
  }

  int? _getStoreId(Map<String, dynamic> store) {
    final raw = store['id'] ?? store['id_tienda'];
    if (raw is int) return raw;
    if (raw == null) return null;
    return int.tryParse(raw.toString());
  }

  List<CartItem> _getItemsForStore(Map<String, dynamic>? store) {
    if (store == null) return const [];
    final storeId = _getStoreId(store);
    if (storeId == null) return const [];
    return widget.itemsByStore[storeId] ?? const [];
  }

  double _getTotalForItems(List<CartItem> items) {
    return items.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  LatLng? _getCurrentTargetPoint() {
    final store = _getCurrentTargetStore();
    if (store == null) return null;
    return _parseUbicacion(store['ubicacion']);
  }

  String _getStoreName(Map<String, dynamic> store) {
    return (store['denominacion'] ?? store['nombre'] ?? 'Tienda').toString();
  }

  void _showArrivalBanner({required String storeName, required double meters}) {
    _arrivalBannerTimer?.cancel();

    final distanceText = meters >= 1000
        ? '${(meters / 1000).toStringAsFixed(1)} km'
        : '${meters.toStringAsFixed(0)} m';

    setState(() {
      _arrivalBannerText = 'Llegaste a $storeName • $distanceText';
    });

    _arrivalBannerTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      setState(() {
        _arrivalBannerText = null;
      });
    });
  }

  Future<void> _startTravel() async {
    if (_optimizedPath.isEmpty) return;

    setState(() {
      _isTravelActive = true;
      _currentStopIndex = 0;
      _lastArrivedStopIndex = null;
      _isLegRouteFallback = false;
      _visitedStopIndices.clear();
    });

    _travelTickTimer?.cancel();
    _travelTickTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      if (!_isTravelActive) return;
      _checkProximity();
    });

    unawaited(_precomputeStoreLegs());
    await _updateCurrentLegRoute(force: true);

    _checkProximity();

    final current = _getCurrentLatLng();
    if (current != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mapController.move(current, _mapController.camera.zoom);
      });
    }
  }

  void _stopTravel() {
    _travelTickTimer?.cancel();
    setState(() {
      _isTravelActive = false;
      _currentLegPolyline = null;
      _distanceToTargetMeters = null;
      _arrivalBannerText = null;
      _lastArrivedStopIndex = null;
      _isLegRouteFallback = false;
    });
  }

  Future<void> _precomputeStoreLegs() async {
    if (!_isTravelActive) return;
    if (_optimizedPath.length < 2) return;
    if (_isLoadingStoreLegs) return;

    const maxLegsToPrecompute = 12;
    final legsToCompute = math.min(
      _optimizedPath.length - 1,
      maxLegsToPrecompute,
    );

    setState(() {
      _isLoadingStoreLegs = true;
      _storeLegPolylines = List<List<LatLng>?>.filled(
        _optimizedPath.length - 1,
        null,
      );
    });

    for (int i = 0; i < legsToCompute; i++) {
      if (!_isTravelActive) break;
      final a = _parseUbicacion(_optimizedPath[i]['ubicacion']);
      final b = _parseUbicacion(_optimizedPath[i + 1]['ubicacion']);
      if (a == null || b == null) continue;

      try {
        final polyline = await _routingService.getRouteBetweenPoints(a, b);
        if (!mounted) return;
        setState(() {
          _storeLegPolylines[i] = polyline;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _storeLegPolylines[i] = [a, b];
        });
      }
    }

    if (!mounted) return;
    setState(() {
      _isLoadingStoreLegs = false;
    });
  }

  Future<void> _updateCurrentLegRoute({bool force = false}) async {
    if (!_isTravelActive) return;
    if (_isUpdatingLegRoute) return;

    final now = DateTime.now();
    final last = _lastLegRouteUpdateAt;
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(seconds: 15)) {
      return;
    }

    final start = _getCurrentLatLng();
    final end = _getCurrentTargetPoint();
    if (start == null || end == null) return;

    try {
      _isUpdatingLegRoute = true;
      _lastLegRouteUpdateAt = now;

      final polyline = await _routingService.getRouteBetweenPoints(start, end);
      if (!mounted) return;

      setState(() {
        _currentLegPolyline = polyline;
        _isLegRouteFallback = polyline.length <= 2;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _currentLegPolyline = [start, end];
        _isLegRouteFallback = true;
      });
    } finally {
      _isUpdatingLegRoute = false;
    }
  }

  void _checkProximity() {
    if (!_isTravelActive) return;
    final pos = _currentPosition;
    final target = _getCurrentTargetPoint();
    final store = _getCurrentTargetStore();
    if (pos == null || target == null || store == null) return;

    final meters = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      target.latitude,
      target.longitude,
    );

    setState(() {
      _distanceToTargetMeters = meters;
    });

    final hasArrived = meters <= 100;
    if (!hasArrived) return;

    if (_lastArrivedStopIndex == _currentStopIndex) return;

    _lastArrivedStopIndex = _currentStopIndex;
    _visitedStopIndices.add(_currentStopIndex);
    _showArrivalBanner(storeName: _getStoreName(store), meters: meters);

    if (_currentStopIndex >= _optimizedPath.length - 1) {
      _arrivalBannerTimer?.cancel();
      _arrivalBannerTimer = Timer(const Duration(seconds: 6), () {
        if (!mounted) return;
        _stopTravel();
      });
      return;
    }

    setState(() {
      _currentStopIndex += 1;
      _currentLegPolyline = null;
      _isLegRouteFallback = false;
      _distanceToTargetMeters = null;
    });

    unawaited(_updateCurrentLegRoute(force: true));
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

                if (_isTravelActive) {
                  final current = LatLng(position.latitude, position.longitude);
                  _mapController.move(current, _mapController.camera.zoom);
                  unawaited(_updateCurrentLegRoute());
                  _checkProximity();
                }
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
      _isTravelActive = false;
      _currentLegPolyline = null;
      _distanceToTargetMeters = null;
      _arrivalBannerText = null;
      _lastArrivedStopIndex = null;
      _visitedStopIndices.clear();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = AppTheme.getAccentColor(context);

    // URL del mapa según tema
    final tileUrl = isDark
        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackgroundColor : Colors.white,
      appBar: AppBar(
        title: const Text('Ruta de Compra'),
        backgroundColor: isDark ? AppTheme.darkSurfaceColor : AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _calculateRoute,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: accentColor))
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: LatLng(22.40694, -79.96472),
                    initialZoom: 13.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: tileUrl,
                      subdomains: isDark ? const ['a', 'b', 'c', 'd'] : const [],
                      userAgentPackageName: 'com.ventiq.marketplace',
                    ),
                    PolylineLayer(polylines: _buildPolylines()),
                    MarkerLayer(
                      key: ValueKey(
                        '${_currentPosition?.latitude}_${_currentPosition?.longitude}_${_isTravelActive ? 1 : 0}',
                      ),
                      markers: _buildMarkers(),
                    ),
                  ],
                ),
                if (_arrivalBannerText != null)
                  Positioned(
                    top: 12,
                    left: 16,
                    right: 16,
                    child: _buildArrivalBanner(_arrivalBannerText!),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildBottomControls(context),
                ),
              ],
            ),
    );
  }

  Widget _buildArrivalBanner(String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = AppTheme.getCardColor(context);
    final textPrimary = AppTheme.getTextPrimaryColor(context);
    final accentColor = AppTheme.getAccentColor(context);

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(14),
      color: cardColor,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accentColor.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle,
                color: accentColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls(BuildContext context) {
    final hasRoute = _optimizedPath.isNotEmpty;
    final targetStore = _getCurrentTargetStore();

    Map<String, dynamic>? productsStore;
    if (_isTravelActive && _lastArrivedStopIndex != null) {
      final pos = _getCurrentLatLng();
      final idx = _lastArrivedStopIndex!;
      if (pos != null && idx >= 0 && idx < _optimizedPath.length) {
        final arrivedStore = _optimizedPath[idx];
        final arrivedPoint = _parseUbicacion(arrivedStore['ubicacion']);
        if (arrivedPoint != null) {
          final meters = Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            arrivedPoint.latitude,
            arrivedPoint.longitude,
          );

          if (meters <= 200) {
            productsStore = arrivedStore;
          }
        }
      }
    }

    productsStore ??= targetStore;
    final storeItems = _getItemsForStore(productsStore);
    final storeTotal = _getTotalForItems(storeItems);

    final distanceText = (_distanceToTargetMeters == null)
        ? null
        : (_distanceToTargetMeters! >= 1000)
        ? '${(_distanceToTargetMeters! / 1000).toStringAsFixed(1)} km'
        : '${_distanceToTargetMeters!.toStringAsFixed(0)} m';

    if (!hasRoute) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = AppTheme.getCardColor(context);
    final textPrimary = AppTheme.getTextPrimaryColor(context);
    final textSecondary = AppTheme.getTextSecondaryColor(context);
    final accentColor = AppTheme.getAccentColor(context);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: BoxDecoration(
          color: cardColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  setState(() {
                    _isBottomPanelExpanded = !_isBottomPanelExpanded;
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _isTravelActive
                              ? (targetStore != null
                                    ? 'Próxima: ${_getStoreName(targetStore)}'
                                    : 'Ruta finalizada')
                              : 'Ruta optimizada lista',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      if (_isTravelActive && _isLoadingStoreLegs)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
                          ),
                        ),
                      if (_totalDistance != null &&
                          _totalDuration != null &&
                          !_isTravelActive)
                        Text(
                          '${(_totalDistance! / 1000).toStringAsFixed(1)} km • ${(_totalDuration! / 60).toStringAsFixed(0)} min',
                          style: TextStyle(
                            fontSize: 12,
                            color: textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (distanceText != null && _isTravelActive)
                        Text(
                          distanceText,
                          style: TextStyle(
                            fontSize: 12,
                            color: textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const SizedBox(width: 8),
                      Icon(
                        _isBottomPanelExpanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_up_rounded,
                        color: textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (storeItems.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _buildStoreItemsPanel(
                        store: productsStore,
                        items: storeItems,
                        total: storeTotal,
                      ),
                    ),
                  if (_isTravelActive && _isLegRouteFallback)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Mostrando línea directa (sin ruta por calles). Verifica conexión.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange[800],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (_isTravelActive)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _buildStoresDistanceList(),
                    ),
                  const SizedBox(height: 10),
                  if (!_isTravelActive)
                    ElevatedButton.icon(
                      onPressed: _startTravel,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text(
                        'Comenzar viaje',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _stopTravel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accentColor,
                        side: BorderSide(color: accentColor.withOpacity(0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text(
                        'Detener viaje',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
              secondChild: const SizedBox.shrink(),
              crossFadeState: _isBottomPanelExpanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 180),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoreItemsPanel({
    required Map<String, dynamic>? store,
    required List<CartItem> items,
    required double total,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = AppTheme.getTextPrimaryColor(context);
    final accentColor = AppTheme.getAccentColor(context);

    final storeName = store == null ? 'Tienda' : _getStoreName(store);

    final isExpanded = _isStoreItemsPanelExpanded;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceColor : Colors.grey[50],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppTheme.darkDividerColor : Colors.grey.withOpacity(0.18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _isStoreItemsPanelExpanded = !_isStoreItemsPanelExpanded;
                });
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.shopping_bag_rounded,
                        color: accentColor,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            storeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: textPrimary,
                            ),
                          ),
                          Text(
                            'Productos a comprar: ${items.length}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                              color: AppTheme.getTextSecondaryColor(context).withOpacity(0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.successColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppTheme.successColor.withOpacity(0.18),
                        ),
                      ),
                      child: Text(
                        '\$${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          color: AppTheme.successColor,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_up_rounded,
                        color: AppTheme.getTextSecondaryColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Divider(height: 1, color: isDark ? AppTheme.darkDividerColor : Colors.grey.withOpacity(0.15)),
          AnimatedCrossFade(
            firstChild: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkCardBackground : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? AppTheme.darkDividerColor : Colors.grey.withOpacity(0.10)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.productName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${item.variantName} • ${item.presentacion}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                  color: AppTheme.getTextSecondaryColor(context).withOpacity(
                                    0.9,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: accentColor.withOpacity(0.18),
                            ),
                          ),
                          child: Text(
                            'x${item.quantity}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              color: accentColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            secondChild: const SizedBox.shrink(),
            crossFadeState: isExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }

  List<Polyline> _buildPolylines() {
    final polylines = <Polyline>[];

    if (!_isTravelActive) {
      if (_routePolyline != null && _routePolyline!.isNotEmpty) {
        polylines.add(
          Polyline(
            points: _routePolyline!,
            strokeWidth: 4.0,
            color: AppTheme.primaryColor,
            borderStrokeWidth: 2.0,
            borderColor: Colors.white,
          ),
        );
      }
      return polylines;
    }

    if (_currentLegPolyline != null && _currentLegPolyline!.isNotEmpty) {
      polylines.add(
        Polyline(
          points: _currentLegPolyline!,
          strokeWidth: 6.0,
          color: AppTheme.primaryColor,
          borderStrokeWidth: 2.0,
          borderColor: Colors.white,
        ),
      );
    } else {
      if (_isLegRouteFallback && !_isUpdatingLegRoute) {
        final start = _getCurrentLatLng();
        final end = _getCurrentTargetPoint();
        if (start != null && end != null) {
          polylines.add(
            Polyline(
              points: [start, end],
              strokeWidth: 6.0,
              color: AppTheme.primaryColor,
              borderStrokeWidth: 2.0,
              borderColor: Colors.white,
            ),
          );
        }
      }
    }

    for (int i = _currentStopIndex; i < _optimizedPath.length - 1; i++) {
      final a = _parseUbicacion(_optimizedPath[i]['ubicacion']);
      final b = _parseUbicacion(_optimizedPath[i + 1]['ubicacion']);
      if (a == null || b == null) continue;

      final cached = (i < _storeLegPolylines.length)
          ? _storeLegPolylines[i]
          : null;
      if (cached != null && cached.length > 1) {
        polylines.addAll(
          _buildDashedPolyline(
            cached,
            strokeWidth: 3.0,
            color: AppTheme.primaryColor.withOpacity(0.85),
          ),
        );
      } else {
        polylines.addAll(
          _buildDashedSegment(
            a,
            b,
            strokeWidth: 3.0,
            color: AppTheme.primaryColor.withOpacity(0.85),
          ),
        );
      }
    }

    return polylines;
  }

  List<Polyline> _buildDashedPolyline(
    List<LatLng> points, {
    required double strokeWidth,
    required Color color,
  }) {
    final polylines = <Polyline>[];
    if (points.length < 2) return polylines;

    for (int i = 0; i < points.length - 1; i++) {
      polylines.addAll(
        _buildDashedSegment(
          points[i],
          points[i + 1],
          strokeWidth: strokeWidth,
          color: color,
        ),
      );
    }

    return polylines;
  }

  Widget _buildStoresDistanceList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = AppTheme.getTextPrimaryColor(context);
    final accentColor = AppTheme.getAccentColor(context);

    final pos = _currentPosition;
    if (pos == null) {
      return const SizedBox.shrink();
    }

    final items = <({int index, String name, double meters})>[];
    for (int i = 0; i < _optimizedPath.length; i++) {
      final store = _optimizedPath[i];
      final point = _parseUbicacion(store['ubicacion']);
      if (point == null) continue;
      final meters = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        point.latitude,
        point.longitude,
      );
      items.add((index: i, name: _getStoreName(store), meters: meters));
    }

    String fmt(double m) {
      if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km';
      return '${m.toStringAsFixed(0)} m';
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 170),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceColor : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? AppTheme.darkDividerColor : Colors.grey.withOpacity(0.2)),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        shrinkWrap: true,
        itemCount: items.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: isDark ? AppTheme.darkDividerColor : Colors.grey.withOpacity(0.2)),
        itemBuilder: (context, idx) {
          final item = items[idx];
          final isNext = _isTravelActive && item.index == _currentStopIndex;
          final isVisited = _visitedStopIndices.contains(item.index);
          final badgeColor = isVisited
              ? Colors.green.shade700
              : (isNext ? accentColor : accentColor);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (isVisited || isNext)
                        ? badgeColor
                        : accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${item.index + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: (isVisited || isNext)
                          ? Colors.white
                          : accentColor,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: (isNext || isVisited)
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: isVisited
                          ? Colors.green.shade800
                          : (isNext ? accentColor : textPrimary),
                    ),
                  ),
                ),
                if (isVisited)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade700.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.green.shade700.withOpacity(0.35),
                      ),
                    ),
                    child: Text(
                      'ARRIBADA',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Colors.green.shade800,
                      ),
                    ),
                  )
                else if (isNext)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: accentColor.withOpacity(0.30),
                      ),
                    ),
                    child: Text(
                      'SIGUIENTE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: accentColor,
                      ),
                    ),
                  ),
                const SizedBox(width: 10),
                Text(
                  fmt(item.meters),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: isVisited
                        ? Colors.green.shade800
                        : (isNext ? accentColor : textPrimary.withOpacity(0.7)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Polyline> _buildDashedSegment(
    LatLng start,
    LatLng end, {
    required double strokeWidth,
    required Color color,
  }) {
    const dashLengthMeters = 80.0;
    const gapLengthMeters = 60.0;
    final dist = const Distance();
    final segmentLength = dist.as(LengthUnit.Meter, start, end);
    if (segmentLength <= 0) return [];

    final polylines = <Polyline>[];
    double cursor = 0;

    while (cursor < segmentLength) {
      final dashStart = cursor;
      final dashEnd = math.min(cursor + dashLengthMeters, segmentLength);

      final startT = dashStart / segmentLength;
      final endT = dashEnd / segmentLength;

      final p1 = LatLng(
        start.latitude + (end.latitude - start.latitude) * startT,
        start.longitude + (end.longitude - start.longitude) * startT,
      );
      final p2 = LatLng(
        start.latitude + (end.latitude - start.latitude) * endT,
        start.longitude + (end.longitude - start.longitude) * endT,
      );

      polylines.add(
        Polyline(
          points: [p1, p2],
          strokeWidth: strokeWidth,
          color: color,
          borderStrokeWidth: 1.5,
          borderColor: Colors.white,
        ),
      );

      cursor += dashLengthMeters + gapLengthMeters;
    }

    return polylines;
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // User marker
    if (_currentPosition != null) {
      final headingDeg = _currentPosition!.heading;
      final safeHeadingDeg = (headingDeg.isFinite && headingDeg > 0)
          ? headingDeg
          : 0.0;
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
            child: _isTravelActive
                ? Transform.rotate(
                    angle: safeHeadingDeg * math.pi / 180,
                    child: const Icon(
                      Icons.navigation,
                      color: AppTheme.primaryColor,
                      size: 28,
                    ),
                  )
                : const Icon(Icons.my_location, color: AppTheme.primaryColor),
          ),
        ),
      );
    }

    // Store markers with order number
    for (int i = 0; i < _optimizedPath.length; i++) {
      final store = _optimizedPath[i];
      final storeName = _getStoreName(store);
      final parts = (store['ubicacion'] as String).split(',');
      final point = LatLng(
        double.parse(parts[0].trim()),
        double.parse(parts[1].trim()),
      );

      final isCurrentTarget = _isTravelActive && i == _currentStopIndex;
      final isVisited = _visitedStopIndices.contains(i);

      final headerColor = isVisited
          ? Colors.green.shade700
          : (isCurrentTarget ? AppTheme.primaryColor : AppTheme.primaryColor);
      final pinColor = isVisited
          ? Colors.green.shade700
          : (isCurrentTarget ? AppTheme.primaryColor : AppTheme.primaryColor);

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
                    color: headerColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
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
                      if (isVisited)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.25),
                            ),
                          ),
                          child: const Text(
                            'ARRIBADA',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 9,
                              letterSpacing: 0.2,
                            ),
                          ),
                        )
                      else if (isCurrentTarget)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.25),
                            ),
                          ),
                          child: const Text(
                            'SIGUIENTE',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 9,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: pinColor, width: 2),
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
                  child: Container(width: 14, height: 10, color: pinColor),
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

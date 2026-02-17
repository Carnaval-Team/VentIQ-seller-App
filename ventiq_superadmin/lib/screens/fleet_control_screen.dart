import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/app_colors.dart';
import '../models/fleet_models.dart';
import '../services/fleet_service.dart';
import '../services/routing_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/fleet_driver_panel.dart';
import '../widgets/fleet_map_widget.dart';

class FleetControlScreen extends StatefulWidget {
  const FleetControlScreen({super.key});

  @override
  State<FleetControlScreen> createState() => _FleetControlScreenState();
}

class _FleetControlScreenState extends State<FleetControlScreen> {
  final FleetService _fleetService = FleetService();
  final RoutingService _routingService = RoutingService();
  final MapController _mapController = MapController();

  List<RepartidorFlota> _repartidores = [];
  RepartidorFlota? _selectedRepartidor;
  List<LatLng>? _rutaSeleccionada;
  List<LatLng>? _checkpoints; // Puntos originales del historial (sin interpolación OSRM)
  double? _distanciaRutaKm; // Distancia total de la ruta en km
  double? _duracionRutaMin; // Duración total de la ruta en minutos
  Color _rutaColor = AppColors.chartColors[0];

  // Puntos acumulados localmente por repartidor (desde que se abrió la vista)
  final Map<int, List<LatLng>> _rutasLocales = {};
  // Posiciones previas para detectar movimiento
  final Map<int, LatLng> _posicionesPrevias = {};

  int _pointsLimit = 100;
  Timer? _refreshTimer;
  bool _isLoading = true;
  bool _isLoadingRoute = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshPositions(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final repartidores = await _fleetService.fetchRepartidoresConOrdenes();
      if (!mounted) return;

      // Inicializar posiciones previas
      for (final rep in repartidores) {
        if (rep.repartidorId != null) {
          _posicionesPrevias[rep.repartidorId!] =
              LatLng(rep.latitud, rep.longitud);
        }
      }

      setState(() {
        _repartidores = repartidores;
        _isLoading = false;
      });

      // Centrar el mapa después de que se renderice el primer frame
      if (repartidores.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _centerMapOnDrivers();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Error cargando datos: $e');
    }
  }

  Future<void> _refreshPositions() async {
    try {
      final repartidores = await _fleetService.fetchRepartidoresConOrdenes();
      if (!mounted) return;

      // Detectar movimiento y acumular puntos locales
      for (final rep in repartidores) {
        if (rep.repartidorId == null) continue;
        final id = rep.repartidorId!;
        final nuevaPos = LatLng(rep.latitud, rep.longitud);
        final prevPos = _posicionesPrevias[id];

        if (prevPos != null) {
          final dist = const Distance().as(
            LengthUnit.Meter,
            prevPos,
            nuevaPos,
          );
          // Solo registrar si se movió más de 10 metros
          if (dist > 10) {
            _rutasLocales.putIfAbsent(id, () => []);
            _rutasLocales[id]!.add(nuevaPos);
          }
        }
        _posicionesPrevias[id] = nuevaPos;
      }

      setState(() {
        _repartidores = repartidores;
      });

      // Si hay un chofer seleccionado, actualizar datos y acoplar nuevos puntos
      if (_selectedRepartidor != null) {
        final selId = _selectedRepartidor!.repartidorId;
        // Actualizar el objeto seleccionado con datos frescos
        final updated = repartidores.where(
          (r) => r.repartidorId == selId,
        );
        if (updated.isNotEmpty) {
          setState(() => _selectedRepartidor = updated.first);
        }

        // Acoplar solo los puntos locales NUEVOS al final de la ruta
        if (selId != null && _rutaSeleccionada != null) {
          final localPoints = _rutasLocales[selId];
          if (localPoints != null && localPoints.isNotEmpty) {
            // Tomar solo el último punto nuevo (el que se acaba de agregar)
            final lastPoint = localPoints.last;
            setState(() {
              _rutaSeleccionada = [..._rutaSeleccionada!, lastPoint];
            });
          }
        }
      }
    } catch (e) {
      // Silenciar errores de refresco para no molestar al usuario
      debugPrint('Error refrescando posiciones: $e');
    }
  }

  Future<void> _onDriverSelected(RepartidorFlota driver) async {
    // Si se toca el mismo chofer, deseleccionar
    if (_selectedRepartidor != null && _selectedRepartidor!.id == driver.id) {
      setState(() {
        _selectedRepartidor = null;
        _rutaSeleccionada = null;
        _checkpoints = null;
        _distanciaRutaKm = null;
        _duracionRutaMin = null;
      });
      return;
    }

    await _loadDriverRoute(driver);
  }

  Future<void> _loadDriverRoute(RepartidorFlota driver) async {
    setState(() {
      _selectedRepartidor = driver;
      _rutaSeleccionada = null;
      _checkpoints = null;
      _distanciaRutaKm = null;
      _duracionRutaMin = null;
      _isLoadingRoute = true;
    });

    // Centrar mapa en el chofer
    _mapController.move(
      LatLng(driver.latitud, driver.longitud),
      15,
    );

    // Colores de ruta altamente visibles sobre mapa
    const routeColors = [
      Color(0xFF2979FF), // Azul eléctrico
      Color(0xFFFF1744), // Rojo intenso
      Color(0xFFFF9100), // Naranja neón
      Color(0xFFD500F9), // Magenta
      Color(0xFF00E676), // Verde neón
      Color(0xFFFFEA00), // Amarillo intenso
      Color(0xFF00B0FF), // Cyan
      Color(0xFFFF3D00), // Rojo-naranja
    ];
    final idx = _repartidores.indexWhere((r) => r.id == driver.id);
    _rutaColor = routeColors[(idx >= 0 ? idx : 0) % routeColors.length];

    // Cargar historial de ruta
    print('[Fleet] _loadDriverRoute: nombre=${driver.nombre} repartidorId=${driver.repartidorId} id=${driver.id}');
    if (driver.repartidorId != null) {
      try {
        final historial = await _fleetService.fetchHistorialRuta(
          driver.repartidorId!,
          limit: _pointsLimit,
        );

        if (!mounted) return;

        print('[Fleet] historial recibido: ${historial.length} puntos');

        if (historial.isEmpty) {
          setState(() {
            _rutaSeleccionada = null;
            _isLoadingRoute = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${driver.nombre}: sin historial de ruta disponible'),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }

        // Convertir historial a LatLng (ya viene ordenado cronológicamente)
        final historyPoints = historial.map((h) {
          return LatLng(
            (h['latitud'] as num).toDouble(),
            (h['longitud'] as num).toDouble(),
          );
        }).toList();

        print('[Fleet] historyPoints convertidos: ${historyPoints.length} puntos');
        print('[Fleet]   primero: ${historyPoints.first}');
        print('[Fleet]   ultimo: ${historyPoints.last}');

        // Posición actual del chofer
        final posActual = LatLng(driver.latitud, driver.longitud);

        // Todos los puntos: posición actual + historial
        // Evitar duplicar si la posición actual ya está muy cerca del primer punto del historial
        final allPoints = <LatLng>[];
        allPoints.add(posActual);
        for (final p in historyPoints) {
          final d = const Distance().as(LengthUnit.Meter, allPoints.last, p);
          if (d >= 30) {
            allPoints.add(p);
          }
        }

        if (allPoints.length >= 2) {
          // UNA SOLA request a OpenRouteService (hasta 50 waypoints)
          // Devuelve geometría por calles + distancia + duración
          final routeResult =
              await _routingService.getRouteMultiplePointsWithDistance(allPoints);

          if (!mounted) return;

          print('[Fleet] ORS: ${routeResult.points.length} puntos ruta, '
              '${routeResult.distanceKm.toStringAsFixed(2)} km, '
              '${(routeResult.durationSeconds / 60).toStringAsFixed(0)} min');

          // Acoplar puntos locales acumulados
          final localPoints = _rutasLocales[driver.repartidorId] ?? [];
          final rutaFinal = [...routeResult.points, ...localPoints];

          print('[Fleet] rutaFinal: ${rutaFinal.length} puntos');
          if (rutaFinal.isNotEmpty) {
            print('[Fleet]   primer punto ruta: lat=${rutaFinal.first.latitude}, lng=${rutaFinal.first.longitude}');
            print('[Fleet]   ultimo punto ruta: lat=${rutaFinal.last.latitude}, lng=${rutaFinal.last.longitude}');
          }

          setState(() {
            _rutaSeleccionada = rutaFinal;
            _checkpoints = historyPoints;
            _distanciaRutaKm = routeResult.distanceKm;
            _duracionRutaMin = routeResult.durationSeconds / 60;
            _isLoadingRoute = false;
          });
        } else {
          // Solo 1 punto: línea recta
          final localPoints = _rutasLocales[driver.repartidorId] ?? [];
          setState(() {
            _rutaSeleccionada = [posActual, ...historyPoints, ...localPoints];
            _checkpoints = historyPoints;
            _distanciaRutaKm = 0;
            _duracionRutaMin = 0;
            _isLoadingRoute = false;
          });
        }
      } catch (e) {
        if (!mounted) return;
        print('[Fleet] ERROR cargando ruta: $e');
        setState(() => _isLoadingRoute = false);
        _showError('Error cargando ruta de ${driver.nombre}');
      }
    } else {
      print('[Fleet] driver.repartidorId es null, no se puede cargar historial');
      setState(() => _isLoadingRoute = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${driver.nombre}: sin ID de repartidor vinculado'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _onPointsLimitChanged(int newLimit) {
    setState(() => _pointsLimit = newLimit);
    // Recargar ruta si hay un chofer seleccionado (sin toggle)
    if (_selectedRepartidor != null) {
      _loadDriverRoute(_selectedRepartidor!);
    }
  }

  void _centerMapOnDrivers() {
    if (_repartidores.isEmpty) return;

    if (_repartidores.length == 1) {
      _mapController.move(
        LatLng(_repartidores[0].latitud, _repartidores[0].longitud),
        14,
      );
      return;
    }

    final bounds = LatLngBounds.fromPoints(
      _repartidores.map((r) => LatLng(r.latitud, r.longitud)).toList(),
    );

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Control de Flota'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          // Indicador de auto-refresh
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sync, size: 16, color: Colors.white70),
                SizedBox(width: 6),
                Text(
                  'Auto 30s',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
          // Botón centrar mapa
          IconButton(
            icon: const Icon(Icons.center_focus_strong),
            tooltip: 'Centrar mapa',
            onPressed: _centerMapOnDrivers,
          ),
          // Botón refrescar manual
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refrescar ahora',
            onPressed: () {
              _refreshPositions();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Posiciones actualizadas'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                // Panel lateral izquierdo
                FleetDriverPanel(
                  repartidores: _repartidores,
                  selected: _selectedRepartidor,
                  onDriverTap: _onDriverSelected,
                  pointsLimit: _pointsLimit,
                  onPointsLimitChanged: _onPointsLimitChanged,
                  isLoadingRoute: _isLoadingRoute,
                  distanciaRutaKm: _distanciaRutaKm,
                  duracionRutaMin: _duracionRutaMin,
                ),
                // Mapa
                Expanded(
                  child: Stack(
                    children: [
                      FleetMapWidget(
                        mapController: _mapController,
                        repartidores: _repartidores,
                        selected: _selectedRepartidor,
                        rutaSeleccionada: _rutaSeleccionada,
                        checkpoints: _checkpoints,
                        rutaColor: _rutaColor,
                        onMarkerTap: _onDriverSelected,
                      ),
                      // Status bar inferior
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: _buildStatusBar(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatusBar() {
    final total = _repartidores.length;
    final activos = _repartidores
        .where((r) => r.estado == EstadoRepartidor.activo)
        .length;
    final estacionados = _repartidores
        .where((r) => r.estado == EstadoRepartidor.estacionado)
        .length;
    final inactivos = _repartidores
        .where((r) => r.estado == EstadoRepartidor.inactivo)
        .length;
    final totalOrdenes = _repartidores.fold<int>(
        0, (sum, r) => sum + r.ordenesAsignadas.length);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatusItem(
            Icons.local_shipping,
            '$total',
            'Total',
            AppColors.textPrimary,
          ),
          _buildStatusDivider(),
          _buildStatusItem(
            Icons.local_shipping,
            '$activos',
            'Activos',
            const Color(0xFF4CAF50),
          ),
          _buildStatusDivider(),
          _buildStatusItem(
            Icons.local_parking,
            '$estacionados',
            'Estacionados',
            const Color(0xFFFF9800),
          ),
          _buildStatusDivider(),
          _buildStatusItem(
            Icons.power_settings_new,
            '$inactivos',
            'Inactivos',
            const Color(0xFFF44336),
          ),
          _buildStatusDivider(),
          _buildStatusItem(
            Icons.shopping_bag,
            '$totalOrdenes',
            'Ordenes',
            AppColors.secondary,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem(
      IconData icon, String value, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusDivider() {
    return Container(
      width: 1,
      height: 30,
      color: AppColors.divider,
    );
  }
}

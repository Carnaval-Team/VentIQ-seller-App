import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/app_theme.dart';
import '../services/repartidor_service.dart';

mixin RepartidorMapMixin<T extends StatefulWidget> on State<T> {
  bool _showRepartidores = false;
  List<Map<String, dynamic>> _repartidores = [];
  Timer? _repartidorTimer;
  final RepartidorService _repartidorService = RepartidorService();

  void initRepartidorTracking() {
    // No auto-fetch; user toggles on manually
  }

  void disposeRepartidorTracking() {
    _repartidorTimer?.cancel();
    _repartidorTimer = null;
  }

  Future<void> _fetchRepartidores() async {
    try {
      final data = await _repartidorService.getRepartidoresActivos();
      if (!mounted) return;
      setState(() {
        _repartidores = data;
      });
    } catch (e) {
      print('Error fetching repartidores: $e');
    }
  }

  void _toggleRepartidores() {
    setState(() {
      _showRepartidores = !_showRepartidores;
    });

    if (_showRepartidores) {
      _fetchRepartidores();
      _repartidorTimer?.cancel();
      _repartidorTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _fetchRepartidores(),
      );
    } else {
      _repartidorTimer?.cancel();
      _repartidorTimer = null;
      setState(() {
        _repartidores = [];
      });
    }
  }

  List<Marker> buildRepartidorMarkers() {
    if (!_showRepartidores) return const [];

    final markers = <Marker>[];
    for (final rep in _repartidores) {
      final lat = double.tryParse(rep['latitud']?.toString() ?? '');
      final lng = double.tryParse(rep['longitud']?.toString() ?? '');
      if (lat == null || lng == null) continue;

      final nombre = (rep['nombre'] ?? 'Repartidor').toString();

      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 50,
          height: 60,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF7C4DFF),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.delivery_dining,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return markers;
  }

  Widget buildRepartidorToggleButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FloatingActionButton.small(
      heroTag: 'toggle_repartidores',
      backgroundColor: _showRepartidores
          ? const Color(0xFF7C4DFF)
          : (isDark ? AppTheme.darkCardBackground : Colors.white),
      onPressed: _toggleRepartidores,
      child: Icon(
        Icons.delivery_dining,
        color: _showRepartidores
            ? Colors.white
            : (isDark ? Colors.white70 : Colors.grey),
      ),
    );
  }
}

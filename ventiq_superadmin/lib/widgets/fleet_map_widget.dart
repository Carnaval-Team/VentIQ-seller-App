import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/app_colors.dart';
import '../models/fleet_models.dart';

class FleetMapWidget extends StatelessWidget {
  final MapController mapController;
  final List<RepartidorFlota> repartidores;
  final RepartidorFlota? selected;
  final List<LatLng>? rutaSeleccionada;
  final List<CheckpointData>? checkpointData;
  final List<ParkedZone>? parkedZones;
  final Color rutaColor;
  final ValueChanged<RepartidorFlota> onMarkerTap;

  const FleetMapWidget({
    super.key,
    required this.mapController,
    required this.repartidores,
    required this.selected,
    required this.rutaSeleccionada,
    this.checkpointData,
    this.parkedZones,
    required this.rutaColor,
    required this.onMarkerTap,
  });

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: mapController,
      options: const MapOptions(
        initialCenter: LatLng(22.40694, -79.96472), // Cuba por defecto
        initialZoom: 13,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.ventiq.superadmin',
        ),
        // 1) Ruta del chofer seleccionado (polyline)
        if (rutaSeleccionada != null && rutaSeleccionada!.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: rutaSeleccionada!,
                color: Colors.black54,
                strokeWidth: 8.0,
              ),
              Polyline(
                points: rutaSeleccionada!,
                color: rutaColor,
                strokeWidth: 5.0,
              ),
            ],
          ),
        // 2) Todos los puntos GPS como bolitas pequeñas
        if (checkpointData != null && checkpointData!.isNotEmpty)
          MarkerLayer(
            markers: checkpointData!.map((cp) {
              return Marker(
                point: cp.point,
                width: 8,
                height: 8,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: rutaColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                ),
              );
            }).toList(),
          ),
        // 3) Zonas de estacionamiento (bolitas más grandes con tooltip de tiempo)
        if (parkedZones != null && parkedZones!.isNotEmpty)
          MarkerLayer(
            markers: parkedZones!.map((zone) {
              final mins = zone.duration.inMinutes;
              final label = mins < 60
                  ? '${mins}min'
                  : '${(mins / 60).floor()}h ${mins % 60}min';
              return Marker(
                point: zone.center,
                width: 20,
                height: 20,
                child: Tooltip(
                  message: 'Estacionado ~$label',
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9800),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.local_parking, size: 10, color: Colors.white),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        // 4) Inicio de ruta (grande con play)
        if (checkpointData != null && checkpointData!.isNotEmpty)
          MarkerLayer(
            markers: [
              Marker(
                point: checkpointData!.first.point,
                width: 28,
                height: 28,
                child: Tooltip(
                  message: 'Inicio de ruta',
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ),
              // Fin de ruta
              Marker(
                point: checkpointData!.last.point,
                width: 22,
                height: 22,
                child: Tooltip(
                  message: 'Fin de ruta',
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF44336),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.stop, size: 12, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        // 5) Markers de repartidores
        MarkerLayer(
          markers: repartidores.map((rep) => _buildMarker(rep)).toList(),
        ),
      ],
    );
  }

  Marker _buildMarker(RepartidorFlota rep) {
    final isSelected = selected != null && selected!.id == rep.id;
    final size = isSelected ? 56.0 : 46.0;

    return Marker(
      point: LatLng(rep.latitud, rep.longitud),
      width: size,
      height: size + 18,
      child: GestureDetector(
        onTap: () => onMarkerTap(rep),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Círculo del marker
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: size - 10,
              height: size - 10,
              decoration: BoxDecoration(
                color: rep.colorEstado,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.white : Colors.white70,
                  width: isSelected ? 3 : 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: rep.colorEstado.withOpacity(0.4),
                    blurRadius: isSelected ? 10 : 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.local_shipping,
                color: Colors.white,
                size: isSelected ? 22 : 18,
              ),
            ),
            const SizedBox(height: 2),
            // Nombre debajo
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary
                    : Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                rep.nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isSelected ? 10 : 8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

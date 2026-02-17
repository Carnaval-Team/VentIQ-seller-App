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
  final List<LatLng>? checkpoints;
  final Color rutaColor;
  final ValueChanged<RepartidorFlota> onMarkerTap;

  const FleetMapWidget({
    super.key,
    required this.mapController,
    required this.repartidores,
    required this.selected,
    required this.rutaSeleccionada,
    this.checkpoints,
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
        // Ruta del chofer seleccionado - borde oscuro para contraste
        if (rutaSeleccionada != null && rutaSeleccionada!.length >= 2)
          PolylineLayer(
            polylines: [
              // Borde/contorno oscuro debajo
              Polyline(
                points: rutaSeleccionada!,
                color: Colors.black54,
                strokeWidth: 8.0,
              ),
              // Línea principal encima con color llamativo
              Polyline(
                points: rutaSeleccionada!,
                color: rutaColor,
                strokeWidth: 5.0,
              ),
            ],
          ),
        // Checkpoints del historial (puntos intermedios)
        if (checkpoints != null && checkpoints!.length > 2)
          MarkerLayer(
            markers: [
              for (int i = 1; i < checkpoints!.length - 1; i++)
                Marker(
                  point: checkpoints![i],
                  width: 24,
                  height: 24,
                  child: Tooltip(
                    message: 'Checkpoint ${i}',
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: rutaColor, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          Icons.flag,
                          color: rutaColor,
                          size: 10,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        // Marcadores de inicio y fin de la ruta
        if (rutaSeleccionada != null && rutaSeleccionada!.length >= 2)
          MarkerLayer(
            markers: [
              // Inicio de la ruta (bandera verde)
              Marker(
                point: rutaSeleccionada!.first,
                width: 32,
                height: 32,
                child: const Icon(
                  Icons.flag_circle,
                  color: Color(0xFF4CAF50),
                  size: 28,
                ),
              ),
              // Fin de la ruta (bandera roja)
              Marker(
                point: rutaSeleccionada!.last,
                width: 32,
                height: 32,
                child: const Icon(
                  Icons.flag_circle,
                  color: Color(0xFFF44336),
                  size: 28,
                ),
              ),
            ],
          ),
        // Markers de repartidores
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
                Icons.delivery_dining,
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

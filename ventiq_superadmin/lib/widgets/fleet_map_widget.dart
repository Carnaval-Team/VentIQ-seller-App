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
        // 1) Checkpoints DEBAJO de la ruta (sombra)
        if (checkpoints != null && checkpoints!.length > 2)
          MarkerLayer(
            markers: [
              for (int i = 1; i < checkpoints!.length - 1; i++)
                Marker(
                  point: checkpoints![i],
                  width: 24,
                  height: 24,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        // 2) Ruta del chofer seleccionado - borde oscuro para contraste
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
        // 3) Checkpoints ENCIMA de la ruta (círculos numerados)
        if (checkpoints != null && checkpoints!.length > 2)
          MarkerLayer(
            markers: [
              for (int i = 1; i < checkpoints!.length - 1; i++)
                Marker(
                  point: checkpoints![i],
                  width: 22,
                  height: 22,
                  child: Tooltip(
                    message: 'Parada $i de ${checkpoints!.length - 1}',
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: rutaColor, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          '$i',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: rutaColor,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        // 4) Marcadores de inicio y fin de la ruta con número
        if (checkpoints != null && checkpoints!.isNotEmpty)
          MarkerLayer(
            markers: [
              // Inicio (primer checkpoint)
              Marker(
                point: checkpoints!.first,
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
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 4,
                          offset: const Offset(0, 1),
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
              // Fin (último checkpoint)
              Marker(
                point: checkpoints!.last,
                width: 28,
                height: 28,
                child: Tooltip(
                  message: 'Fin de ruta (parada ${checkpoints!.length})',
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF44336),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        '${checkpoints!.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1,
                        ),
                      ),
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

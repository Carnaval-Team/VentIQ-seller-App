import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Resultado de una ruta optimizada
class RouteResult {
  final List<LatLng> polyline;
  final List<int> waypointOrder;
  final double totalDistance; // en metros
  final double totalDuration; // en segundos

  RouteResult({
    required this.polyline,
    required this.waypointOrder,
    required this.totalDistance,
    required this.totalDuration,
  });
}

/// Servicio para calcular rutas reales usando OSRM (Open Source Routing Machine)
class RoutingService {
  static const String _osrmBaseUrl = 'https://router.project-osrm.org';

  /// Obtiene la ruta optimizada entre múltiples puntos usando OSRM Trip API
  ///
  /// [start] - Punto de inicio (ubicación actual del usuario)
  /// [waypoints] - Lista de puntos a visitar (tiendas)
  ///
  /// Retorna [RouteResult] con la polyline decodificada y el orden optimizado
  Future<RouteResult> getOptimizedRoute(
    LatLng start,
    List<LatLng> waypoints,
  ) async {
    try {
      // Construir coordenadas: start;waypoint1;waypoint2;...
      final coordinates = [
        start,
        ...waypoints,
      ].map((point) => '${point.longitude},${point.latitude}').join(';');

      // Llamar a OSRM Trip API
      // Importante:
      // - source=first fija el inicio en la ubicación actual
      // - destination=any permite que OSRM elija el mejor destino final
      //   (si usamos destination=last, con 2 tiendas siempre obliga start->A->B)
      final url = Uri.parse(
        '$_osrmBaseUrl/trip/v1/driving/$coordinates?source=first&destination=any&roundtrip=false&geometries=polyline',
      );

      print('🗺️ Llamando a OSRM Trip API: $url');

      final response = await http
          .get(url)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Timeout al obtener ruta de OSRM');
            },
          );

      if (response.statusCode != 200) {
        throw Exception(
          'Error en OSRM API: ${response.statusCode} - ${response.body}',
        );
      }

      final data = json.decode(response.body);

      if (data['code'] != 'Ok') {
        throw Exception('OSRM retornó código: ${data['code']}');
      }

      // Extraer la primera ruta (trip)
      final trip = data['trips'][0];
      final geometry = trip['geometry'] as String;
      final distance = (trip['distance'] as num).toDouble();
      final duration = (trip['duration'] as num).toDouble();

      // Decodificar polyline
      final polyline = _decodePolyline(geometry);

      // Extraer orden de visita real.
      // OSRM devuelve `waypoints` en el orden de entrada; cada waypoint trae
      // `waypoint_index` = posición dentro del trip optimizado.
      // Necesitamos retornar una lista ordenada por `waypoint_index`, pero con
      // el índice de entrada para poder mapearlo luego a stores.
      final waypointsData = data['waypoints'] as List;
      final orderedInputIndices =
          List<int>.generate(waypointsData.length, (i) => i)..sort((a, b) {
            final ai =
                (waypointsData[a] as Map<String, dynamic>)['waypoint_index']
                    as int;
            final bi =
                (waypointsData[b] as Map<String, dynamic>)['waypoint_index']
                    as int;
            return ai.compareTo(bi);
          });

      print(
        '✅ Ruta obtenida: ${polyline.length} puntos, ${distance.toStringAsFixed(0)}m, ${(duration / 60).toStringAsFixed(1)}min',
      );

      return RouteResult(
        polyline: polyline,
        waypointOrder: orderedInputIndices,
        totalDistance: distance,
        totalDuration: duration,
      );
    } catch (e) {
      print('❌ Error obteniendo ruta optimizada: $e');
      // Fallback: retornar ruta simple en línea recta
      return _getFallbackRoute(start, waypoints);
    }
  }

  /// Obtiene una ruta simple entre dos puntos
  Future<List<LatLng>> getRouteBetweenPoints(LatLng start, LatLng end) async {
    try {
      final coordinates =
          '${start.longitude},${start.latitude};${end.longitude},${end.latitude}';

      final url = Uri.parse(
        '$_osrmBaseUrl/route/v1/driving/$coordinates?geometries=polyline&overview=full&alternatives=false&steps=false',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('Error en OSRM API: ${response.statusCode}');
      }

      final data = json.decode(response.body);

      if (data['code'] != 'Ok') {
        throw Exception('OSRM retornó código: ${data['code']}');
      }

      final geometry = data['routes'][0]['geometry'] as String;
      return _decodePolyline(geometry);
    } catch (e) {
      print('❌ Error obteniendo ruta entre puntos: $e');
      // Fallback: línea recta
      return [start, end];
    }
  }

  /// Decodifica una polyline codificada (Google Polyline Algorithm)
  ///
  /// Formato usado por OSRM para comprimir coordenadas
  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int shift = 0;
      int result = 0;
      int byte;

      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;

      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }

  /// Ruta de fallback cuando OSRM falla
  /// Retorna una ruta simple conectando puntos en línea recta
  RouteResult _getFallbackRoute(LatLng start, List<LatLng> waypoints) {
    print('⚠️ Usando ruta de fallback (línea recta)');

    final polyline = [start, ...waypoints];
    final waypointOrder = List.generate(waypoints.length + 1, (i) => i);

    // Calcular distancia aproximada
    double totalDistance = 0;
    for (int i = 0; i < polyline.length - 1; i++) {
      totalDistance += const Distance().as(
        LengthUnit.Meter,
        polyline[i],
        polyline[i + 1],
      );
    }

    return RouteResult(
      polyline: polyline,
      waypointOrder: waypointOrder,
      totalDistance: totalDistance,
      totalDuration: totalDistance / 10, // Estimación: 10 m/s
    );
  }
}

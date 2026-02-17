import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Servicio para calcular rutas reales usando OSRM (Open Source Routing Machine).
class RoutingService {
  static const String _osrmBaseUrl = 'https://router.project-osrm.org';

  /// Obtiene una ruta real entre dos puntos usando OSRM.
  Future<List<LatLng>> getRouteBetweenPoints(LatLng start, LatLng end) async {
    try {
      final coordinates =
          '${start.longitude},${start.latitude};${end.longitude},${end.latitude}';

      final url = Uri.parse(
        '$_osrmBaseUrl/route/v1/driving/$coordinates'
        '?geometries=polyline&overview=full&alternatives=false&steps=false',
      );

      final response =
          await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('Error en OSRM API: ${response.statusCode}');
      }

      final data = json.decode(response.body);

      if (data['code'] != 'Ok') {
        throw Exception('OSRM retornó código: ${data['code']}');
      }

      final geometry = data['routes'][0]['geometry'] as String;
      return _decodePolyline(geometry);
    } catch (_) {
      return [start, end];
    }
  }

  /// Obtiene la ruta real pasando por múltiples puntos (máximo ~100 por request OSRM).
  /// Divide en chunks si hay demasiados puntos y concatena resultados.
  Future<List<LatLng>> getRouteMultiplePoints(List<LatLng> points) async {
    if (points.length < 2) return points;

    // OSRM tiene límite práctico de ~100 waypoints por request.
    // Dividimos en chunks solapados para mantener continuidad.
    const chunkSize = 80;
    final allRoutePoints = <LatLng>[];

    for (int i = 0; i < points.length - 1; i += chunkSize - 1) {
      final end = math.min(i + chunkSize, points.length);
      final chunk = points.sublist(i, end);

      if (chunk.length < 2) break;

      try {
        final routeChunk = await _getRouteChunk(chunk);
        // Evitar duplicar el punto de unión
        if (allRoutePoints.isNotEmpty && routeChunk.isNotEmpty) {
          allRoutePoints.addAll(routeChunk.sublist(1));
        } else {
          allRoutePoints.addAll(routeChunk);
        }
      } catch (_) {
        // Fallback: línea recta para este chunk
        if (allRoutePoints.isNotEmpty) {
          allRoutePoints.addAll(chunk.sublist(1));
        } else {
          allRoutePoints.addAll(chunk);
        }
      }
    }

    return allRoutePoints.isEmpty ? points : allRoutePoints;
  }

  Future<List<LatLng>> _getRouteChunk(List<LatLng> points) async {
    final coordinates =
        points.map((p) => '${p.longitude},${p.latitude}').join(';');

    final url = Uri.parse(
      '$_osrmBaseUrl/route/v1/driving/$coordinates'
      '?geometries=polyline&overview=full&alternatives=false&steps=false',
    );

    print('[RoutingService] OSRM request: ${points.length} waypoints');
    print('[RoutingService] URL: $url');

    final response = await http.get(url).timeout(const Duration(seconds: 20));

    print('[RoutingService] OSRM response status: ${response.statusCode}');

    if (response.statusCode != 200) {
      throw Exception('Error en OSRM API: ${response.statusCode}');
    }

    final data = json.decode(response.body);

    if (data['code'] != 'Ok') {
      print('[RoutingService] OSRM code: ${data['code']} message: ${data['message']}');
      throw Exception('OSRM retornó código: ${data['code']}');
    }

    final geometry = data['routes'][0]['geometry'] as String;
    final decoded = _decodePolyline(geometry);
    print('[RoutingService] OSRM decoded polyline: ${decoded.length} puntos');
    return decoded;
  }

  /// Decodifica una polyline codificada (Google Polyline Algorithm Format).
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
}

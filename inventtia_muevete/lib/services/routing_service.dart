import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Holds the result of a route calculation.
class RouteResult {
  /// The list of points forming the route polyline.
  final List<LatLng> polyline;

  /// Total distance of the route in meters.
  final double totalDistance;

  /// Total duration of the route in seconds.
  final double totalDuration;

  RouteResult({
    required this.polyline,
    required this.totalDistance,
    required this.totalDuration,
  });
}

class RoutingService {
  static const String _baseUrl = 'https://router.project-osrm.org';

  /// Fetches a driving route between [start] and [end] using OSRM.
  /// Falls back to a straight line on error.
  Future<RouteResult> getRoute(LatLng start, LatLng end) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${end.longitude},${end.latitude}'
        '?geometries=polyline&overview=full',
      );

      final response = await http.get(url);

      if (response.statusCode != 200) {
        throw Exception('OSRM API error: ${response.statusCode}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List<dynamic>;

      if (routes.isEmpty) {
        throw Exception('No routes found');
      }

      final route = routes[0] as Map<String, dynamic>;
      final geometry = route['geometry'] as String;
      final distance = (route['distance'] as num).toDouble();
      final duration = (route['duration'] as num).toDouble();

      final polyline = _decodePolyline(geometry);

      return RouteResult(
        polyline: polyline,
        totalDistance: distance,
        totalDuration: duration,
      );
    } catch (e) {
      // Fallback: return a straight line between start and end
      const distanceCalc = Distance();
      final meters = distanceCalc.as(LengthUnit.Meter, start, end);

      return RouteResult(
        polyline: [start, end],
        totalDistance: meters,
        totalDuration: meters / 13.89, // ~50 km/h average speed estimate
      );
    }
  }

  /// Decodes an encoded polyline string into a list of LatLng points.
  ///
  /// IMPORTANT: Uses `-((result >> 1) + 1)` instead of `~(result >> 1)`
  /// for the negative case. The bitwise NOT operator ~ produces incorrect
  /// values on Dart Web because JavaScript uses 32-bit for bitwise ops.
  /// The fix `-((result >> 1) + 1)` is mathematically identical and works
  /// on all platforms.
  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    int lat = 0;
    int lon = 0;

    while (index < encoded.length) {
      // Decode latitude
      int result = 0;
      int shift = 0;
      int byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1F) << shift;
        shift += 5;
      } while (byte >= 0x20);
      // CRITICAL: Do NOT use ~(result >> 1). Use -((result >> 1) + 1) instead.
      final int deltaLat =
          (result & 1) != 0 ? -((result >> 1) + 1) : (result >> 1);
      lat += deltaLat;

      // Decode longitude
      result = 0;
      shift = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1F) << shift;
        shift += 5;
      } while (byte >= 0x20);
      // CRITICAL: Do NOT use ~(result >> 1). Use -((result >> 1) + 1) instead.
      final int deltaLon =
          (result & 1) != 0 ? -((result >> 1) + 1) : (result >> 1);
      lon += deltaLon;

      points.add(LatLng(lat / 1e5, lon / 1e5));
    }

    return points;
  }
}

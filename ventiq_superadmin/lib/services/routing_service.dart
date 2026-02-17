import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Resultado de una ruta OSRM con geometría y distancia.
class RouteResult {
  final List<LatLng> points;
  final double distanceMeters; // distancia total en metros

  RouteResult({required this.points, required this.distanceMeters});

  double get distanceKm => distanceMeters / 1000;
}

/// Servicio para calcular rutas reales usando OSRM (Open Source Routing Machine).
class RoutingService {
  static const String _osrmBaseUrl = 'https://router.project-osrm.org';

  /// Obtiene la ruta óptima usando Trip API de OSRM.
  /// [start] = posición actual del chofer (source=first)
  /// [end] = punto más antiguo del historial (destination=last)
  /// [waypoints] = puntos intermedios del historial (sampleados)
  /// Retorna la polyline de la ruta trazada por las calles.
  Future<List<LatLng>> getTripRoute(
    LatLng start,
    LatLng end,
    List<LatLng> waypoints,
  ) async {
    try {
      // Construir coordenadas: start;waypoints...;end
      final allPoints = [start, ...waypoints, end];
      final coordinates =
          allPoints.map((p) => '${p.longitude},${p.latitude}').join(';');

      final url = Uri.parse(
        '$_osrmBaseUrl/trip/v1/driving/$coordinates'
        '?source=first&destination=last&roundtrip=false&geometries=polyline',
      );

      print('[RoutingService] Trip API: ${allPoints.length} puntos');

      final response =
          await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('Trip API error: ${response.statusCode}');
      }

      final data = json.decode(response.body);

      if (data['code'] != 'Ok') {
        print('[RoutingService] Trip API code: ${data['code']} message: ${data['message']}');
        throw Exception('Trip API retornó: ${data['code']}');
      }

      final trip = data['trips'][0];
      final geometry = trip['geometry'] as String;
      final polyline = _decodePolyline(geometry);

      print('[RoutingService] Trip API OK: ${polyline.length} puntos de ruta');
      return polyline;
    } catch (e) {
      print('[RoutingService] Trip API falló: $e, usando fallback par a par');
      // Fallback: línea recta entre los puntos
      return [start, ...waypoints, end];
    }
  }

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

  /// Obtiene la ruta real pasando por múltiples puntos.
  /// Samplea a ~20 puntos representativos y traza OSRM par a par entre ellos.
  Future<RouteResult> getRouteMultiplePointsWithDistance(
      List<LatLng> points) async {
    if (points.length < 2) {
      return RouteResult(points: points, distanceMeters: 0);
    }

    // Samplear para no hacer cientos de llamadas a OSRM.
    // Con 20 puntos = 19 llamadas par a par, rápido y fiable.
    final sampled = _samplePoints(points, maxWaypoints: 20);

    print('[RoutingService] Original: ${points.length} puntos -> Sampled: ${sampled.length} -> ${sampled.length - 1} segmentos OSRM');

    final allRoutePoints = <LatLng>[];
    double totalDistance = 0;

    for (int i = 0; i < sampled.length - 1; i++) {
      final start = sampled[i];
      final end = sampled[i + 1];

      try {
        final segmentResult = await _getRouteChunkWithDistance([start, end]);

        // Evitar duplicar el punto de unión entre segmentos
        if (allRoutePoints.isNotEmpty && segmentResult.points.isNotEmpty) {
          allRoutePoints.addAll(segmentResult.points.sublist(1));
        } else {
          allRoutePoints.addAll(segmentResult.points);
        }
        totalDistance += segmentResult.distanceMeters;
      } catch (e) {
        print('[RoutingService] Segmento $i→${i + 1} falló: $e');
        // Fallback: línea recta para este segmento
        if (allRoutePoints.isEmpty) {
          allRoutePoints.add(start);
        }
        allRoutePoints.add(end);
        totalDistance += _straightLineDistance([start, end]);
      }
    }

    if (allRoutePoints.isEmpty) {
      return RouteResult(
        points: points,
        distanceMeters: _straightLineDistance(points),
      );
    }

    print('[RoutingService] Ruta completa: ${allRoutePoints.length} puntos, ${(totalDistance / 1000).toStringAsFixed(2)} km');

    return RouteResult(points: allRoutePoints, distanceMeters: totalDistance);
  }

  /// Samplea puntos uniformemente conservando primero y último.
  List<LatLng> _samplePoints(List<LatLng> points, {int maxWaypoints = 20}) {
    if (points.length <= maxWaypoints) return points;

    final sampled = <LatLng>[points.first];
    final step = (points.length - 1) / (maxWaypoints - 1);

    for (int i = 1; i < maxWaypoints - 1; i++) {
      final idx = (i * step).round();
      if (idx > 0 && idx < points.length - 1) {
        sampled.add(points[idx]);
      }
    }

    sampled.add(points.last);
    return sampled;
  }

  /// Wrapper legacy que retorna solo los puntos.
  Future<List<LatLng>> getRouteMultiplePoints(List<LatLng> points) async {
    final result = await getRouteMultiplePointsWithDistance(points);
    return result.points;
  }

  Future<RouteResult> _getRouteChunkWithDistance(List<LatLng> points) async {
    final coordinates =
        points.map((p) => '${p.longitude},${p.latitude}').join(';');

    final url = Uri.parse(
      '$_osrmBaseUrl/route/v1/driving/$coordinates'
      '?geometries=polyline&overview=full&alternatives=false&steps=false',
    );

    print('[RoutingService] OSRM request: ${points.length} waypoints');

    final response =
        await http.get(url).timeout(const Duration(seconds: 20));

    print('[RoutingService] OSRM response status: ${response.statusCode}');

    if (response.statusCode != 200) {
      throw Exception('Error en OSRM API: ${response.statusCode}');
    }

    final data = json.decode(response.body);

    if (data['code'] != 'Ok') {
      print(
          '[RoutingService] OSRM code: ${data['code']} message: ${data['message']}');
      throw Exception('OSRM retornó código: ${data['code']}');
    }

    final route = data['routes'][0];
    final geometry = route['geometry'] as String;
    final distance = (route['distance'] as num).toDouble();
    final decoded = _decodePolyline(geometry);

    print(
        '[RoutingService] OSRM decoded: ${decoded.length} puntos, distance: ${(distance / 1000).toStringAsFixed(2)} km');

    return RouteResult(points: decoded, distanceMeters: distance);
  }

  /// Calcula distancia en línea recta entre puntos consecutivos (fallback).
  double _straightLineDistance(List<LatLng> points) {
    double total = 0;
    const dist = Distance();
    for (int i = 0; i < points.length - 1; i++) {
      total += dist.as(LengthUnit.Meter, points[i], points[i + 1]);
    }
    return total;
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

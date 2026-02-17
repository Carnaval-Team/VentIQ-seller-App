import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Resultado de una ruta con geometría y distancia.
class RouteResult {
  final List<LatLng> points;
  final double distanceMeters; // distancia total en metros
  final double durationSeconds; // duración total en segundos

  RouteResult({
    required this.points,
    required this.distanceMeters,
    this.durationSeconds = 0,
  });

  double get distanceKm => distanceMeters / 1000;
}

/// Servicio para calcular rutas reales usando OpenRouteService (ORS).
/// Usa el endpoint Directions con GeoJSON para obtener rutas por calles
/// con hasta 50 waypoints en una sola request.
class RoutingService {
  static const String _orsBaseUrl = 'https://api.openrouteservice.org';
  static const String _apiKey =
      'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6ImZjNDMyNWE5NmI3NjQxZjM5NDQyNzM3MzJkYTA1MGM4IiwiaCI6Im11cm11cjY0In0=';

  /// Headers comunes para todas las requests a ORS.
  Map<String, String> get _headers => {
        'Authorization': _apiKey,
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
      };

  /// Obtiene la ruta trazada por calles usando ORS Directions API.
  /// [start] = posición actual del chofer
  /// [end] = punto más antiguo del historial
  /// [waypoints] = puntos intermedios del historial
  /// Retorna la polyline de la ruta trazada por las calles.
  ///
  /// ORS soporta hasta 50 waypoints en una sola request,
  /// así que mandamos todos los puntos de una vez.
  Future<List<LatLng>> getTripRoute(
    LatLng start,
    LatLng end,
    List<LatLng> waypoints,
  ) async {
    try {
      final allPoints = [start, ...waypoints, end];
      final result = await _getOrsDirections(allPoints);

      print(
          '[RoutingService] ORS Trip OK: ${result.points.length} puntos de ruta');
      return result.points;
    } catch (e) {
      print('[RoutingService] ORS Trip falló: $e, usando fallback');
      return [start, ...waypoints, end];
    }
  }

  /// Obtiene una ruta real entre dos puntos usando ORS.
  Future<List<LatLng>> getRouteBetweenPoints(
      LatLng start, LatLng end) async {
    try {
      final result = await _getOrsDirections([start, end]);
      return result.points;
    } catch (_) {
      return [start, end];
    }
  }

  /// Obtiene la ruta real pasando por múltiples puntos con distancia.
  /// Usa una SOLA request a ORS con hasta 50 waypoints.
  /// Si hay más de 50 puntos, los samplea inteligentemente.
  Future<RouteResult> getRouteMultiplePointsWithDistance(
      List<LatLng> points) async {
    if (points.length < 2) {
      return RouteResult(points: points, distanceMeters: 0);
    }

    try {
      // ORS soporta hasta 50 waypoints por request.
      // Si hay más, sampleamos a 50 (conservando primero y último).
      final sampled = _samplePoints(points, maxWaypoints: 50);

      print(
          '[RoutingService] ORS: ${points.length} puntos originales -> ${sampled.length} enviados');

      final result = await _getOrsDirections(sampled);

      print(
          '[RoutingService] ORS OK: ${result.points.length} puntos ruta, '
          '${result.distanceKm.toStringAsFixed(2)} km, '
          '${(result.durationSeconds / 60).toStringAsFixed(0)} min');

      return result;
    } catch (e) {
      print('[RoutingService] ORS falló: $e, usando líneas rectas');
      return RouteResult(
        points: points,
        distanceMeters: _straightLineDistance(points),
      );
    }
  }

  /// Wrapper legacy que retorna solo los puntos.
  Future<List<LatLng>> getRouteMultiplePoints(List<LatLng> points) async {
    final result = await getRouteMultiplePointsWithDistance(points);
    return result.points;
  }

  /// Llama a ORS Directions API (POST con JSON response + encoded polyline).
  Future<RouteResult> _getOrsDirections(List<LatLng> points) async {
    // Coordenadas en formato [longitude, latitude] (convención GeoJSON)
    final coordinates =
        points.map((p) => [p.longitude, p.latitude]).toList();

    final url = Uri.parse(
      '$_orsBaseUrl/v2/directions/driving-car',
    );

    final body = json.encode({
      'coordinates': coordinates,
    });

    print('[RoutingService] ORS request: ${points.length} waypoints');

    final response = await http
        .post(url, headers: _headers, body: body)
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      final errorBody = response.body;
      print('[RoutingService] ORS error ${response.statusCode}: $errorBody');
      throw Exception('ORS API error: ${response.statusCode}');
    }

    final data = json.decode(response.body);

    final routes = data['routes'] as List;
    if (routes.isEmpty) {
      throw Exception('ORS: sin rutas en respuesta');
    }

    final route = routes[0];
    final geometry = route['geometry'] as String;
    final summary = route['summary'];

    // Decodificar polyline (Google Polyline Algorithm, precisión 1e-5)
    final routePoints = _decodePolyline(geometry);

    final distanceMeters = (summary['distance'] as num).toDouble();
    final durationSeconds = (summary['duration'] as num).toDouble();

    print('[RoutingService] ORS decoded: ${routePoints.length} puntos, '
        '${(distanceMeters / 1000).toStringAsFixed(2)} km');

    return RouteResult(
      points: routePoints,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
    );
  }

  /// Decodifica una polyline codificada (Google Polyline Algorithm Format, precisión 1e-5).
  /// Compatible con Dart Web (evita bitwise NOT que falla con enteros grandes en JS).
  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      // Decodificar latitud
      int shift = 0;
      int result = 0;
      int byte;

      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      // Usar aritmética en vez de bitwise NOT (~) para compatibilidad web
      lat += (result & 1) != 0 ? -((result >> 1) + 1) : (result >> 1);

      // Decodificar longitud
      shift = 0;
      result = 0;

      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      lng += (result & 1) != 0 ? -((result >> 1) + 1) : (result >> 1);

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }

  /// Elimina puntos duplicados o demasiado cercanos (< minDistanceMeters).
  /// Siempre conserva el primer y último punto.
  List<LatLng> _deduplicatePoints(List<LatLng> points,
      {double minDistanceMeters = 50}) {
    if (points.length <= 2) return points;

    final result = <LatLng>[points.first];
    const dist = Distance();

    for (int i = 1; i < points.length - 1; i++) {
      final d = dist.as(LengthUnit.Meter, result.last, points[i]);
      if (d >= minDistanceMeters) {
        result.add(points[i]);
      }
    }

    // Siempre agregar el último punto si es distinto al último agregado
    final dLast = dist.as(LengthUnit.Meter, result.last, points.last);
    if (dLast >= 1) {
      result.add(points.last);
    }

    return result;
  }

  /// Samplea puntos uniformemente conservando primero y último.
  List<LatLng> _samplePoints(List<LatLng> points, {int maxWaypoints = 50}) {
    // Primero deduplicar para eliminar puntos cercanos/estacionados
    final deduped = _deduplicatePoints(points);

    print('[RoutingService] Dedup: ${points.length} -> ${deduped.length} puntos');

    if (deduped.length <= maxWaypoints) return deduped;

    final sampled = <LatLng>[deduped.first];
    final step = (deduped.length - 1) / (maxWaypoints - 1);

    for (int i = 1; i < maxWaypoints - 1; i++) {
      final idx = (i * step).round();
      if (idx > 0 && idx < deduped.length - 1) {
        sampled.add(deduped[idx]);
      }
    }

    sampled.add(deduped.last);
    return sampled;
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
}

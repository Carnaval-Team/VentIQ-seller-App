import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// A single navigation instruction (turn, merge, etc.).
class RouteStep {
  /// Human-readable instruction in Spanish.
  final String instruction;

  /// Distance in meters from the start of this step to the maneuver point.
  final double distanceM;

  /// The maneuver location.
  final LatLng location;

  /// Icon hint: 'straight', 'left', 'right', 'slight_left', 'slight_right',
  /// 'sharp_left', 'sharp_right', 'uturn', 'arrive', 'depart', 'roundabout', 'merge'.
  final String maneuverType;

  /// Optional modifier ('left', 'right', 'slight left', etc.)
  final String? modifier;

  RouteStep({
    required this.instruction,
    required this.distanceM,
    required this.location,
    required this.maneuverType,
    this.modifier,
  });
}

/// Holds the result of a route calculation.
class RouteResult {
  /// The list of points forming the route polyline.
  final List<LatLng> polyline;

  /// Total distance of the route in meters.
  final double totalDistance;

  /// Total duration of the route in seconds.
  final double totalDuration;

  /// Turn-by-turn navigation steps (empty if unavailable).
  final List<RouteStep> steps;

  RouteResult({
    required this.polyline,
    required this.totalDistance,
    required this.totalDuration,
    this.steps = const [],
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
        '?geometries=polyline&overview=full&steps=true',
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

      // Parse turn-by-turn steps
      final steps = <RouteStep>[];
      final legs = route['legs'] as List<dynamic>?;
      if (legs != null && legs.isNotEmpty) {
        final rawSteps =
            (legs[0] as Map<String, dynamic>)['steps'] as List<dynamic>?;
        if (rawSteps != null) {
          for (final s in rawSteps) {
            final step = s as Map<String, dynamic>;
            final maneuver = step['maneuver'] as Map<String, dynamic>;
            final loc = maneuver['location'] as List<dynamic>;
            final type = maneuver['type'] as String? ?? '';
            final mod = maneuver['modifier'] as String?;
            final name = step['name'] as String? ?? '';
            final dist = (step['distance'] as num?)?.toDouble() ?? 0;

            final instruction = _buildSpanishInstruction(type, mod, name, dist);
            if (instruction.isEmpty) continue;

            steps.add(RouteStep(
              instruction: instruction,
              distanceM: dist,
              location: LatLng(
                (loc[1] as num).toDouble(),
                (loc[0] as num).toDouble(),
              ),
              maneuverType: type,
              modifier: mod,
            ));
          }
        }
      }

      return RouteResult(
        polyline: polyline,
        totalDistance: distance,
        totalDuration: duration,
        steps: steps,
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

  /// Builds a Spanish navigation instruction from OSRM maneuver data.
  String _buildSpanishInstruction(
      String type, String? modifier, String name, double distanceM) {
    final street = name.isNotEmpty ? ' en $name' : '';
    final distStr = distanceM >= 1000
        ? '${(distanceM / 1000).toStringAsFixed(1)} km'
        : '${distanceM.round()} m';

    switch (type) {
      case 'depart':
        return 'Inicia el recorrido$street';
      case 'arrive':
        return 'Llegaste a tu destino$street';
      case 'turn':
        return '${_modifierToSpanish(modifier)}$street en $distStr';
      case 'new name':
      case 'continue':
        if (modifier == 'straight' || modifier == null) {
          return 'Continúa recto$street por $distStr';
        }
        return '${_modifierToSpanish(modifier)}$street en $distStr';
      case 'merge':
        return 'Incorpórate$street en $distStr';
      case 'fork':
        final dir = modifier == 'left'
            ? 'Toma la bifurcación izquierda'
            : modifier == 'right'
                ? 'Toma la bifurcación derecha'
                : 'Toma la bifurcación';
        return '$dir$street en $distStr';
      case 'end of road':
        return '${_modifierToSpanish(modifier)}$street al final de la calle';
      case 'roundabout':
      case 'rotary':
        return 'Entra a la rotonda$street';
      case 'exit roundabout':
      case 'exit rotary':
        return 'Sal de la rotonda$street';
      case 'off ramp':
        return 'Toma la salida$street en $distStr';
      case 'on ramp':
        return 'Toma la rampa de acceso$street';
      default:
        if (modifier != null && modifier != 'straight') {
          return '${_modifierToSpanish(modifier)}$street en $distStr';
        }
        return '';
    }
  }

  String _modifierToSpanish(String? modifier) {
    switch (modifier) {
      case 'left':
        return 'Dobla a la izquierda';
      case 'right':
        return 'Dobla a la derecha';
      case 'slight left':
        return 'Gira levemente a la izquierda';
      case 'slight right':
        return 'Gira levemente a la derecha';
      case 'sharp left':
        return 'Gira fuerte a la izquierda';
      case 'sharp right':
        return 'Gira fuerte a la derecha';
      case 'uturn':
        return 'Haz un cambio de sentido';
      case 'straight':
        return 'Continúa recto';
      default:
        return 'Continúa';
    }
  }

  /// Returns an icon-friendly maneuver key.
  static String maneuverIcon(String type, String? modifier) {
    if (type == 'arrive') return 'arrive';
    if (type == 'depart') return 'depart';
    if (type == 'roundabout' || type == 'rotary') return 'roundabout';
    switch (modifier) {
      case 'left':
        return 'left';
      case 'right':
        return 'right';
      case 'slight left':
        return 'slight_left';
      case 'slight right':
        return 'slight_right';
      case 'sharp left':
        return 'sharp_left';
      case 'sharp right':
        return 'sharp_right';
      case 'uturn':
        return 'uturn';
      default:
        return 'straight';
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

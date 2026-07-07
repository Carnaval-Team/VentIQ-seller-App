import 'package:http/http.dart' as http;
import 'dart:convert';

/// Servicio para consultar países, estados y ciudades desde GeoNames.
/// Username gratuito 'inventtia' (registrado en geonames.org).
class GeonamesService {
  static const String _geonamesUsername = 'inventtia';
  static const String _baseUrl = 'https://secure.geonames.org';

  /// Lista de países: {geonameId, countryName, countryCode, isoNumeric, ...}
  static Future<List<Map<String, dynamic>>> getCountries() async {
    try {
      final url = Uri.parse(
        '$_baseUrl/countryInfoJSON?username=$_geonamesUsername',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 120),
        onTimeout: () => throw Exception('Timeout al conectar con GeoNames'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['geonames'] == null) {
          throw Exception('Respuesta inválida de GeoNames');
        }

        final countries = (data['geonames'] as List)
            .map((country) => {
                  'geonameId': country['geonameId'],
                  'countryName': country['countryName'] as String,
                  'countryCode': country['countryCode'] as String,
                  'isoNumeric': country['isoNumeric'],
                  'continent': country['continent'],
                  'currency': country['currencyCode'],
                  'population': country['population'],
                })
            .toList();

        countries.sort((a, b) =>
            (a['countryName'] as String).compareTo(b['countryName'] as String));
        return countries;
      } else {
        throw Exception('Error al obtener países: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error obteniendo países: $e');
      rethrow;
    }
  }

  /// Estados/provincias para [countryCode] (ISO).
  static Future<List<Map<String, dynamic>>> getStates(
    String countryCode,
  ) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/searchJSON?country=$countryCode&featureCode=ADM1&maxRows=500&username=$_geonamesUsername',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 120),
        onTimeout: () => throw Exception('Timeout al conectar con GeoNames'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['geonames'] == null || (data['geonames'] as List).isEmpty) {
          return [];
        }

        final states = (data['geonames'] as List)
            .map((state) => {
                  'geonameId': state['geonameId'],
                  'name': state['name'] as String,
                  'adminCode1': state['adminCode1'] as String? ??
                      state['adminCode2'] as String? ??
                      '',
                  'countryCode': state['countryCode'],
                  'adminName1': state['adminName1'] ?? state['name'],
                  'population': state['population'] ?? 0,
                  'lat': state['lat'],
                  'lng': state['lng'],
                })
            .toList();

        states.sort(
            (a, b) => (a['name'] as String).compareTo(b['name'] as String));
        return states;
      } else {
        throw Exception('Error al obtener estados: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error obteniendo estados: $e');
      rethrow;
    }
  }

  /// Ciudades para [countryCode] + [adminCode] (estado).
  static Future<List<Map<String, dynamic>>> getCities(
    String countryCode,
    String adminCode,
  ) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/searchJSON?country=$countryCode&adminCode1=$adminCode&featureClass=P&maxRows=500&lang=es&username=$_geonamesUsername',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 120),
        onTimeout: () => throw Exception('Timeout al conectar con GeoNames'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['geonames'] == null || (data['geonames'] as List).isEmpty) {
          return [];
        }

        final cities = (data['geonames'] as List)
            .map((city) => {
                  'geonameId': city['geonameId'],
                  'name': city['name'] as String,
                  'asciiName': city['asciiName'] ?? city['name'],
                  'adminCode1': city['adminCode1'] ?? '',
                  'countryCode': city['countryCode'],
                  'population': city['population'] ?? 0,
                  'lat': city['lat'],
                  'lng': city['lng'],
                })
            .toList();

        cities.sort((a, b) =>
            (b['population'] as int).compareTo(a['population'] as int));
        return cities;
      } else {
        throw Exception('Error al obtener ciudades: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error obteniendo ciudades: $e');
      rethrow;
    }
  }
}

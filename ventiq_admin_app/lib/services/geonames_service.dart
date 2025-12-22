import 'package:http/http.dart' as http;
import 'dart:convert';

class GeonamesService {
  // API de GeoNames - Username gratuito (necesitas registrarte en geonames.org)
  // Para desarrollo, usamos 'demo' pero es limitado
  // Registrate en: https://www.geonames.org/login y crea tu username
  static const String _geonamesUsername = 'inventtia'; // CAMBIAR POR TU USERNAME
  static const String _baseUrl = 'https://secure.geonames.org';

  /// Obtiene lista de países desde GeoNames
  /// Retorna lista de mapas con: {geonameId, countryName, countryCode, ...}
  static Future<List<Map<String, dynamic>>> getCountries() async {
    try {
      print('🌍 Obteniendo países desde GeoNames...');

      final url = Uri.parse(
        '$_baseUrl/countryInfoJSON?username=$_geonamesUsername',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
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
                  'tld': country['tld'],
                  'currency': country['currencyCode'],
                  'languages': country['languages'],
                  'population': country['population'],
                })
            .toList();

        print('✅ ${countries.length} países obtenidos');
        return countries;
      } else {
        throw Exception(
          'Error al obtener países: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('❌ Error obteniendo países: $e');
      rethrow;
    }
  }

  /// Obtiene lista de estados/provincias para un país específico
  /// [countryCode]: Código ISO del país (ej: 'CU' para Cuba)
  /// Retorna lista de mapas con: {geonameId, name, adminCode1, ...}
  static Future<List<Map<String, dynamic>>> getStates(
    String countryCode,
  ) async {
    try {
      print('🏙️ Obteniendo estados para país: $countryCode');

      // Usar searchJSON con featureCode=ADM1 para obtener divisiones administrativas (estados)
      final url = Uri.parse(
        '$_baseUrl/searchJSON?country=$countryCode&featureCode=ADM1&maxRows=500&username=$_geonamesUsername',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Timeout al conectar con GeoNames'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['geonames'] == null || (data['geonames'] as List).isEmpty) {
          print('⚠️ No hay estados para el país: $countryCode');
          return [];
        }

        final states = (data['geonames'] as List)
            .map((state) => {
                  'geonameId': state['geonameId'],
                  'name': state['name'] as String,
                  'adminCode1': state['adminCode1'] as String? ?? state['adminCode2'] as String? ?? '',
                  'countryCode': state['countryCode'],
                  'adminName1': state['adminName1'] ?? state['name'],
                  'population': state['population'] ?? 0,
                  'lat': state['lat'],
                  'lng': state['lng'],
                })
            .toList();

        print('✅ ${states.length} estados obtenidos para $countryCode');
        return states;
      } else {
        throw Exception(
          'Error al obtener estados: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('❌ Error obteniendo estados: $e');
      rethrow;
    }
  }

  /// Obtiene ciudades para un estado específico
  /// [countryCode]: Código ISO del país (ej: 'CU')
  /// [adminCode]: Código del estado (ej: '01')
  /// Retorna nombres en español cuando sea posible
  static Future<List<Map<String, dynamic>>> getCities(
    String countryCode,
    String adminCode,
  ) async {
    try {
      print('🏘️ Obteniendo ciudades para $countryCode - $adminCode');

      // Usar lang=es para obtener nombres en español
      final url = Uri.parse(
        '$_baseUrl/searchJSON?country=$countryCode&adminCode1=$adminCode&featureClass=P&maxRows=500&lang=es&username=$_geonamesUsername',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Timeout al conectar con GeoNames'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['geonames'] == null || (data['geonames'] as List).isEmpty) {
          print('⚠️ No hay ciudades para $countryCode - $adminCode');
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

        // Ordenar por población descendente (ciudades más grandes primero)
        cities.sort((a, b) => (b['population'] as int).compareTo(a['population'] as int));

        print('✅ ${cities.length} ciudades obtenidas para $countryCode - $adminCode');
        return cities;
      } else {
        throw Exception(
          'Error al obtener ciudades: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('❌ Error obteniendo ciudades: $e');
      rethrow;
    }
  }

  /// Busca un país por nombre o código
  static Future<Map<String, dynamic>?> searchCountry(String query) async {
    try {
      print('🔍 Buscando país: $query');

      final url = Uri.parse(
        '$_baseUrl/searchJSON?q=$query&featureClass=A&featureCode=PCLI&maxRows=1&username=$_geonamesUsername',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Timeout al conectar con GeoNames'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['geonames'] == null || (data['geonames'] as List).isEmpty) {
          print('⚠️ País no encontrado: $query');
          return null;
        }

        final country = (data['geonames'] as List).first;
        print('✅ País encontrado: ${country['name']}');

        return {
          'geonameId': country['geonameId'],
          'name': country['name'],
          'countryCode': country['countryCode'],
          'countryName': country['countryName'],
        };
      } else {
        throw Exception(
          'Error al buscar país: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('❌ Error buscando país: $e');
      rethrow;
    }
  }

  /// Obtiene información completa de un país por código ISO
  static Future<Map<String, dynamic>?> getCountryByCode(
    String countryCode,
  ) async {
    try {
      print('🔍 Obteniendo información del país: $countryCode');

      final url = Uri.parse(
        '$_baseUrl/countryInfoJSON?country=$countryCode&username=$_geonamesUsername',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Timeout al conectar con GeoNames'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['geonames'] == null || (data['geonames'] as List).isEmpty) {
          print('⚠️ País no encontrado: $countryCode');
          return null;
        }

        final country = (data['geonames'] as List).first;
        print('✅ Información del país obtenida: ${country['countryName']}');

        return {
          'geonameId': country['geonameId'],
          'countryName': country['countryName'],
          'countryCode': country['countryCode'],
          'isoNumeric': country['isoNumeric'],
          'continent': country['continent'],
          'tld': country['tld'],
          'currency': country['currencyCode'],
          'languages': country['languages'],
          'population': country['population'],
          'area': country['areaInSqKm'],
          'capital': country['capital'],
        };
      } else {
        throw Exception(
          'Error al obtener información del país: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('❌ Error obteniendo información del país: $e');
      rethrow;
    }
  }
}

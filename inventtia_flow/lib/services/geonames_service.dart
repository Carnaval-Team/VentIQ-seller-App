import 'package:http/http.dart' as http;
import 'dart:convert';

class GeonamesService {
  static const String _geonamesUsername = 'inventtia';
  static const String _baseUrl = 'https://secure.geonames.org';

  static Future<List<Map<String, dynamic>>> getCountries() async {
    final url = Uri.parse(
      '$_baseUrl/countryInfoJSON?username=$_geonamesUsername',
    );
    final response = await http.get(url).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw Exception('Timeout al conectar con GeoNames'),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['geonames'] == null) throw Exception('Respuesta inválida');
      final countries = (data['geonames'] as List)
          .map((c) => {
                'geonameId': c['geonameId'],
                'countryName': c['countryName'] as String,
                'countryCode': c['countryCode'] as String,
              })
          .toList();
      countries.sort((a, b) =>
          (a['countryName'] as String).compareTo(b['countryName'] as String));
      return countries;
    }
    throw Exception('Error GeoNames: ${response.statusCode}');
  }

  static Future<List<Map<String, dynamic>>> getStates(
      String countryCode) async {
    final url = Uri.parse(
      '$_baseUrl/searchJSON?country=$countryCode&featureCode=ADM1&maxRows=500&username=$_geonamesUsername',
    );
    final response = await http.get(url).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw Exception('Timeout al conectar con GeoNames'),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['geonames'] == null) return [];
      final states = (data['geonames'] as List)
          .map((s) => {
                'geonameId': s['geonameId'],
                'name': s['name'] as String,
                'adminCode1': s['adminCode1'] as String? ?? '',
                'countryCode': s['countryCode'],
              })
          .toList();
      states.sort(
          (a, b) => (a['name'] as String).compareTo(b['name'] as String));
      return states;
    }
    throw Exception('Error GeoNames estados: ${response.statusCode}');
  }
}

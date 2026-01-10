import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/usuario.dart';

class UserService {
  final _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> getUsersCountSummary() async {
    try {
      final response = await _supabase.rpc('get_users_count_summary');
      if (response != null && (response as List).isNotEmpty) {
        return response[0] as Map<String, dynamic>;
      }
      return {
        'total_usuarios': 0,
        'total_inventtia': 0,
        'total_carnaval': 0,
        'total_catalogo': 0,
      };
    } catch (e) {
      print('Error fetching users count summary: $e');
      return {
        'total_usuarios': 0,
        'total_inventtia': 0,
        'total_carnaval': 0,
        'total_catalogo': 0,
      };
    }
  }

  Future<Map<String, dynamic>> getPaginatedUsersSummary({
    required int limit,
    required int offset,
    String search = '',
    String category = 'todos',
  }) async {
    try {
      final response = await _supabase.rpc(
        'get_paginated_users_summary',
        params: {
          'p_limit': limit,
          'p_offset': offset,
          'p_search': search,
          'p_category': category,
        },
      );

      if (response == null) return {'users': [], 'total': 0};

      final List<dynamic> data = response as List<dynamic>;
      final List<Usuario> users =
          data.map((json) => Usuario.fromJson(json)).toList();

      int total = 0;
      if (data.isNotEmpty) {
        total = data[0]['total_count'] ?? 0;
      }

      return {'users': users, 'total': total};
    } catch (e) {
      print('Error fetching paginated users: $e');
      return {'users': [], 'total': 0};
    }
  }
}

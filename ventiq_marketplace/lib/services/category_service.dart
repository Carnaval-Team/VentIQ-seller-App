import 'package:supabase_flutter/supabase_flutter.dart';

/// Servicio para gestionar categorías del marketplace
class CategoryService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Obtiene todas las categorías disponibles
  Future<List<Map<String, dynamic>>> getAllCategories() async {
    try {
      print('📂 Obteniendo categorías...');

      final response = await _supabase
          .from('app_dat_categoria')
          .select('id, denominacion, descripcion, image')
          .order('denominacion', ascending: true);

      final categories = List<Map<String, dynamic>>.from(response);
      print('✅ ${categories.length} categorías obtenidas');

      return categories;
    } catch (e) {
      print('❌ Error obteniendo categorías: $e');
      rethrow;
    }
  }

  /// Obtiene una categoría por ID
  Future<Map<String, dynamic>?> getCategoryById(int categoryId) async {
    try {
      print('📂 Obteniendo categoría ID: $categoryId');

      final response = await _supabase
          .from('app_dat_categoria')
          .select('id, denominacion, descripcion, imagen')
          .eq('id', categoryId)
          .single();

      print('✅ Categoría obtenida: ${response['denominacion']}');

      return response;
    } catch (e) {
      print('❌ Error obteniendo categoría: $e');
      return null;
    }
  }
}

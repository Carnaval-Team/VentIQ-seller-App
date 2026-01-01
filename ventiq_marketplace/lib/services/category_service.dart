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
          .select('''
            id, 
            denominacion, 
            descripcion, 
            image,
            app_dat_categoria_tienda!inner(
              app_dat_tienda!inner(
                mostrar_en_catalogo
              )
            )
          ''')
          .eq(
            'app_dat_categoria_tienda.app_dat_tienda.mostrar_en_catalogo',
            true,
          )
          .order('denominacion', ascending: true);

      // Eliminar duplicados (una categoría puede estar en múltiples tiendas)
      final categoriesMap = <int, Map<String, dynamic>>{};
      for (var item in response) {
        final id = item['id'] as int;
        if (!categoriesMap.containsKey(id)) {
          // Remover el campo de relación antes de agregar al mapa
          final category = {
            'id': item['id'],
            'denominacion': item['denominacion'],
            'descripcion': item['descripcion'],
            'image': item['image'],
          };
          categoriesMap[id] = category;
        }
      }

      final categories = categoriesMap.values.toList();
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

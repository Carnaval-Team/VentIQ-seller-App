import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';

class CategoryService {
  static final CategoryService _instance = CategoryService._internal();
  factory CategoryService() => _instance;
  CategoryService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final UserPreferencesService _preferencesService = UserPreferencesService();

  /// Fetch categories from Supabase using the RPC function
  Future<List<Category>> getCategories() async {
    try {
      // Get store ID from preferences
      final workerProfile = await _preferencesService.getWorkerProfile();
      final idTienda = workerProfile['idTienda'] as int?;
      
      if (idTienda == null) {
        throw Exception('No se encontró el ID de la tienda en las preferencias');
      }

      debugPrint('🏪 Obteniendo categorías para tienda ID: $idTienda');

      // Call the RPC function to get categories by store
      final response = await _supabase.rpc(
        'get_categorias_by_tienda',
        params: {
          'p_tienda_id': idTienda
        },
      );

      if (response == null) {
        throw Exception('No se recibieron datos de categorías');
      }

      debugPrint('📦 Respuesta de categorías: ${response.length} categorías encontradas');

      // Convert response to Category objects
      final List<Category> categories = [];
      for (final item in response) {
        final category = Category.fromJson(item as Map<String, dynamic>);
        print("${category}");
        categories.add(category);
      }

      debugPrint('✅ Categorías procesadas exitosamente: ${categories.length}');
      return categories;

    } catch (e) {
      debugPrint('❌ Error obteniendo categorías: $e');
      rethrow;
    }
  }

  /// Generate a random color based on category name
  /// This provides consistent colors for the same category name
  Color _generateCategoryColor(String categoryName) {
    final colors = [
      const Color(0xFFE53E3E), // Vibrant red
      const Color(0xFF6B46C1), // Vibrant purple
      const Color(0xFF059669), // Vibrant green
      const Color(0xFFEA580C), // Vibrant orange
      const Color(0xFF0891B2), // Vibrant cyan
      const Color(0xFFDC2626), // Vibrant red variant
      const Color(0xFF7C3AED), // Vibrant indigo
      const Color(0xFF0F766E), // Vibrant teal
      const Color(0xFFB91C1C), // Vibrant red dark
      const Color(0xFF9333EA), // Vibrant violet
    ];

    // Use category name hash to get consistent color
    final hash = categoryName.toLowerCase().hashCode;
    final colorIndex = hash.abs() % colors.length;
    return colors[colorIndex];
  }
}

/// Category model class
class Category {
  final int id;
  final String name;
  final String? description;
  final String? imageUrl;
  final Color color;
  final bool isActive;

  Category({
    required this.id,
    required this.name,
    this.description,
    required this.imageUrl,
    required this.color,
    this.isActive = true,
  });

  /// Create Category from JSON response
  factory Category.fromJson(Map<String, dynamic> json) {
    final categoryService = CategoryService();
    final name = json['nombre'] as String? ?? 'Sin nombre';
    
    return Category(
      id: json['id'] as int? ?? 0,
      name: name,
      description: json['descripcion'] as String?,
      imageUrl: json['imagen'] as String?,
      color: categoryService._generateCategoryColor(name),
      isActive: json['activo'] as bool? ?? true,
    );
  }

  /// Convert Category to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': name,
      'descripcion': description,
      'image': imageUrl,
      'activo': isActive,
    };
  }

  @override
  String toString() {
    return 'Category(id: $id, name: $name, description: $description, isActive: $isActive, imageUrl: $imageUrl)';
  }
}

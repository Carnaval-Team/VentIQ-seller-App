import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/category.dart';
import 'user_preferences_service.dart';

class CategoryService {
  static final CategoryService _instance = CategoryService._internal();
  factory CategoryService() => _instance;
  CategoryService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final UserPreferencesService _userPrefs = UserPreferencesService();

  /// Obtiene todas las categorías de una tienda usando el RPC get_categorias_by_tienda_complete
  Future<List<Category>> getCategoriesByStore() async {
    try {
      print('🏪 Iniciando carga de categorías desde Supabase...');
      
      // Obtener ID de tienda desde preferencias
      final idTienda = await _userPrefs.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda en preferencias');
      }
      
      print('🏪 ID Tienda: $idTienda');
      
      // Llamar al RPC get_categorias_by_tienda_complete
      final response = await _supabase.rpc(
        'get_categorias_by_tienda_complete',
        params: {
          'p_id_tienda': idTienda,
        },
      );

      print('📦 Respuesta RPC recibida: ${response?.length ?? 0} categorías');
      
      if (response == null) {
        print('⚠️ Respuesta nula del RPC');
        return [];
      }

      // Convertir respuesta a lista de categorías
      final List<Category> categories = [];
      for (final item in response) {
        try {
          print('📝 Procesando categoría: ${item['denominacion']} (ID: ${item['id']})');
          
          // Generar color basado en el nombre para consistencia visual
          final color = _generateColorFromName(item['denominacion'] ?? '');
          
          final category = Category.fromJson({
            ...item,
            'color': color,
            'icon': _getIconFromName(item['denominacion'] ?? ''),
          });
          
          categories.add(category);
        } catch (e) {
          print('❌ Error procesando categoría ${item['id']}: $e');
        }
      }

      print('✅ Categorías procesadas exitosamente: ${categories.length}');
      return categories;
      
    } catch (e) {
      print('❌ Error obteniendo categorías: $e');
      
      // Fallback a datos mock en caso de error
      print('🔄 Usando datos mock como fallback');
      return _getMockCategories();
    }
  }

  /// Genera un color consistente basado en el nombre de la categoría
  String _generateColorFromName(String name) {
    final colors = [
      '#4A90E2', // Azul VentIQ
      '#10B981', // Verde
      '#F59E0B', // Amarillo
      '#EF4444', // Rojo
      '#8B5CF6', // Púrpura
      '#06B6D4', // Cyan
      '#F97316', // Naranja
      '#84CC16', // Lima
      '#EC4899', // Rosa
      '#6B7280', // Gris
    ];
    
    final hash = name.hashCode.abs();
    return colors[hash % colors.length];
  }

  /// Obtiene un ícono basado en el nombre de la categoría
  String _getIconFromName(String name) {
    final lowerName = name.toLowerCase();
    
    if (lowerName.contains('alimento') || lowerName.contains('comida')) {
      return 'restaurant';
    } else if (lowerName.contains('bebida')) {
      return 'local_drink';
    } else if (lowerName.contains('electr')) {
      return 'devices';
    } else if (lowerName.contains('hogar') || lowerName.contains('casa')) {
      return 'home';
    } else if (lowerName.contains('limpieza')) {
      return 'cleaning_services';
    } else if (lowerName.contains('cuidado') || lowerName.contains('personal')) {
      return 'face';
    } else if (lowerName.contains('juguete')) {
      return 'toys';
    } else if (lowerName.contains('textil') || lowerName.contains('ropa')) {
      return 'checkroom';
    } else if (lowerName.contains('ferretería') || lowerName.contains('herramienta')) {
      return 'build';
    } else if (lowerName.contains('jardín')) {
      return 'local_florist';
    } else {
      return 'category';
    }
  }

  /// Datos mock como fallback
  List<Category> _getMockCategories() {
    return [
      Category(
        id: 1,
        name: 'Alimentos',
        description: 'Productos de alimentación y bebidas no alcohólicas',
        color: '#4A90E2',
        icon: 'restaurant',
        skuCodigo: 'ALIM',
        createdAt: DateTime.now(),
        productCount: 45,
      ),
      Category(
        id: 2,
        name: 'Bebidas',
        description: 'Bebidas y refrescos no alcohólicos',
        color: '#10B981',
        icon: 'local_drink',
        skuCodigo: 'BEB',
        createdAt: DateTime.now(),
        productCount: 23,
      ),
      Category(
        id: 3,
        name: 'Electrónica',
        description: 'Dispositivos electrónicos y accesorios tecnológicos',
        color: '#F59E0B',
        icon: 'devices',
        skuCodigo: 'ELEC',
        createdAt: DateTime.now(),
        productCount: 18,
      ),
    ];
  }

  /// Buscar categorías por texto
  Future<List<Category>> searchCategories(String query) async {
    final allCategories = await getCategoriesByStore();
    
    if (query.isEmpty) return allCategories;
    
    return allCategories.where((category) {
      return category.name.toLowerCase().contains(query.toLowerCase()) ||
             category.description.toLowerCase().contains(query.toLowerCase()) ||
             category.skuCodigo.toLowerCase().contains(query.toLowerCase());
    }).toList();
  }

  /// Obtener categoría por ID
  Future<Category?> getCategoryById(int id) async {
    final categories = await getCategoriesByStore();
    try {
      return categories.firstWhere((category) => category.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Refrescar caché de categorías (para pull-to-refresh)
  Future<List<Category>> refreshCategories() async {
    print('🔄 Refrescando categorías...');
    return await getCategoriesByStore();
  }

  /// Sube una imagen al bucket de Supabase Storage
  Future<String?> _uploadCategoryImage(Uint8List imageBytes, String fileName) async {
    try {
      print('📤 Subiendo imagen: $fileName');
      
      // Generar nombre único para evitar conflictos
      final uniqueFileName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
      
      // Subir imagen al bucket 'images_back' con opciones específicas
      final response = await _supabase.storage
          .from('images_back')
          .uploadBinary(
            uniqueFileName, 
            imageBytes,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: true, // Permite sobrescribir si existe
            ),
          );

      if (response.isEmpty) {
        throw Exception('Error al subir imagen');
      }

      // Obtener URL pública de la imagen
      final imageUrl = _supabase.storage
          .from('images_back')
          .getPublicUrl(uniqueFileName);

      print('✅ Imagen subida exitosamente: $imageUrl');
      return imageUrl;
    } catch (e) {
      print('❌ Error al subir imagen: $e');
      
      // Si falla con RLS, intentar crear la categoría sin imagen
      if (e.toString().contains('row-level security policy')) {
        print('⚠️ Error de permisos RLS - continuando sin imagen');
        return null;
      }
      
      return null;
    }
  }

  /// Crea una nueva categoría en la base de datos
  Future<bool> createCategory({
    required String denominacion,
    required String descripcion,
    required String skuCodigo,
    Uint8List? imageBytes,
    String? imageFileName,
  }) async {
    try {
      print('🆕 Creando nueva categoría: $denominacion');
      
      // Obtener ID de tienda
      final idTienda = await _userPrefs.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda');
      }

      String? imageUrl;
      
      // Subir imagen si se proporciona
      if (imageBytes != null && imageFileName != null) {
        imageUrl = await _uploadCategoryImage(imageBytes, imageFileName);
        // Continuar aunque falle la subida de imagen (RLS policy issue)
        if (imageUrl == null) {
          print('⚠️ Continuando sin imagen debido a restricciones de permisos');
        }
      }

      // Insertar categoría en app_dat_categoria
      final categoryResponse = await _supabase
          .from('app_dat_categoria')
          .insert({
            'denominacion': denominacion,
            'descripcion': descripcion,
            'sku_codigo': skuCodigo,
            'image': imageUrl,
          })
          .select()
          .single();

      print('✅ Categoría creada con ID: ${categoryResponse['id']}');

      // Insertar relación categoría-tienda en app_dat_categoria_tienda
      await _supabase
          .from('app_dat_categoria_tienda')
          .insert({
            'id_categoria': categoryResponse['id'],
            'id_tienda': idTienda,
          });

      print('✅ Relación categoría-tienda creada exitosamente');
      return true;
    } catch (e) {
      print('❌ Error al crear categoría: $e');
      return false;
    }
  }

  /// Actualiza una categoría existente
  Future<bool> updateCategory({
    required int categoryId,
    required String denominacion,
    required String descripcion,
    required String skuCodigo,
    Uint8List? imageBytes,
    String? imageFileName,
  }) async {
    try {
      print('✏️ Actualizando categoría ID: $categoryId');
      
      String? imageUrl;
      
      // Subir nueva imagen si se proporciona
      if (imageBytes != null && imageFileName != null) {
        imageUrl = await _uploadCategoryImage(imageBytes, imageFileName);
        if (imageUrl == null) {
          throw Exception('Error al subir la nueva imagen');
        }
      }

      // Preparar datos para actualizar
      final updateData = {
        'denominacion': denominacion,
        'descripcion': descripcion,
        'sku_codigo': skuCodigo,
      };

      // Agregar URL de imagen solo si se subió una nueva
      if (imageUrl != null) {
        updateData['image'] = imageUrl;
      }

      // Actualizar categoría
      await _supabase
          .from('app_dat_categoria')
          .update(updateData)
          .eq('id', categoryId);

      print('✅ Categoría actualizada exitosamente');
      return true;
    } catch (e) {
      print('❌ Error al actualizar categoría: $e');
      return false;
    }
  }

  /// Verifica si una categoría tiene subcategorías
  Future<bool> categoryHasSubcategories(int categoryId) async {
    try {
      final subcategories = await _supabase
          .rpc('get_subcategorias_by_categoria', params: {
        'p_id_categoria': categoryId,
      });
      
      return subcategories != null && subcategories.isNotEmpty;
    } catch (e) {
      print('❌ Error verificando subcategorías: $e');
      return false;
    }
  }

  /// Elimina una categoría y su relación con la tienda
  Future<Map<String, dynamic>> deleteCategory(int categoryId) async {
    try {
      print('🗑️ Eliminando categoría ID: $categoryId');
      
      // Verificar si tiene subcategorías
      final hasSubcategories = await categoryHasSubcategories(categoryId);
      if (hasSubcategories) {
        return {
          'success': false,
          'error': 'subcategories_exist',
          'message': 'No se puede eliminar la categoría porque tiene subcategorías asociadas. Elimine primero las subcategorías.'
        };
      }
      
      // Obtener ID de tienda
      final idTienda = await _userPrefs.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda');
      }

      // Eliminar relación categoría-tienda
      await _supabase
          .from('app_dat_categoria_tienda')
          .delete()
          .eq('id_categoria', categoryId)
          .eq('id_tienda', idTienda);

      // Verificar si la categoría tiene otras relaciones con tiendas
      final otherRelations = await _supabase
          .from('app_dat_categoria_tienda')
          .select('id')
          .eq('id_categoria', categoryId);

      // Si no tiene otras relaciones, eliminar la categoría completamente
      if (otherRelations.isEmpty) {
        await _supabase
            .from('app_dat_categoria')
            .delete()
            .eq('id', categoryId);
        print('✅ Categoría eliminada completamente');
      } else {
        print('✅ Relación categoría-tienda eliminada (categoría mantiene otras relaciones)');
      }

      return {
        'success': true,
        'message': 'Categoría eliminada exitosamente'
      };
    } catch (e) {
      print('❌ Error al eliminar categoría: $e');
      return {
        'success': false,
        'error': 'database_error',
        'message': 'Error al eliminar la categoría: $e'
      };
    }
  }
}
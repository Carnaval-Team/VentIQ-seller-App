import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/subcategory.dart';
import 'user_preferences_service.dart';

class SubcategoryService {
  static final SubcategoryService _instance = SubcategoryService._internal();
  factory SubcategoryService() => _instance;
  SubcategoryService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final UserPreferencesService _userPrefs = UserPreferencesService();

  /// Obtiene las subcategorías de una categoría específica usando el RPC de Supabase.
  ///
  /// [soloVisibles] descarta las subcategorías que crea el sistema para las
  /// categorías especiales (la «General» con `oculta = true`): existen para que
  /// la categoría siempre tenga una subcategoría válida, pero no se muestran
  /// para no ensuciar la gestión. Pasa `false` solo para **resolver** una
  /// subcategoría ya asignada a un producto o a una variante.
  Future<List<Subcategory>> getSubcategoriesByCategory(
    int categoryId, {
    bool soloVisibles = true,
  }) async {
    try {
      final response = await _supabase.rpc(
        'get_subcategorias_by_categoria',
        params: {'p_id_categoria': categoryId},
      );

      if (response == null) {
        return [];
      }

      // El RPC vive en la base y no expone la columna `oculta`, así que las
      // ocultas se resuelven aparte y se descartan al mapear.
      final ocultas =
          soloVisibles ? await _ocultasDeCategoria(categoryId) : const <int>{};

      final List<Subcategory> subcategories = [];
      for (final item in response) {
        final id = item is Map ? int.tryParse('${item['id']}') : null;
        if (id != null && ocultas.contains(id)) {
          continue; // Subcategoría del sistema: no se lista.
        }

        try {
          final subcategory = Subcategory.fromJson({
            ...item,
            'idcategoria': categoryId, // Asegurar que el ID de categoría esté presente
          });
          subcategories.add(subcategory);
        } catch (e) {
          print('Error parsing subcategory: $e');
          print('Item data: $item');
        }
      }

      return subcategories;
    } catch (e) {
      print('Error fetching subcategories: $e');
      // Retornar lista vacía en caso de error
      return [];
    }
  }

  /// IDs de las subcategorías **ocultas** de una categoría.
  ///
  /// Las crea el trigger de categorías especiales («General») para que la
  /// categoría nunca se quede sin subcategoría válida. Se consultan aparte
  /// porque el RPC `get_subcategorias_by_categoria` no devuelve `oculta`.
  Future<Set<int>> _ocultasDeCategoria(int categoryId) async {
    try {
      final rows = await _supabase
          .from('app_dat_subcategorias')
          .select('id')
          .eq('idcategoria', categoryId)
          .eq('oculta', true);

      return rows.map((row) => (row['id'] as num).toInt()).toSet();
    } catch (e) {
      print('Error fetching hidden subcategories: $e');
      return const <int>{};
    }
  }

  /// Busca subcategorías por nombre
  Future<List<Subcategory>> searchSubcategories(int categoryId, String query) async {
    try {
      final allSubcategories = await getSubcategoriesByCategory(categoryId);
      
      if (query.isEmpty) {
        return allSubcategories;
      }

      return allSubcategories.where((subcategory) {
        return subcategory.denominacion.toLowerCase().contains(query.toLowerCase()) ||
               subcategory.skuCodigo.toLowerCase().contains(query.toLowerCase());
      }).toList();
    } catch (e) {
      print('Error searching subcategories: $e');
      return [];
    }
  }

  /// Obtiene una subcategoría por ID
  ///
  /// Aquí **no** se excluyen las ocultas: es una resolución por id, no un
  /// listado. Si un producto está en la «General» que creó el sistema, su
  /// nombre debe seguir resolviéndose.
  Future<Subcategory?> getSubcategoryById(int subcategoryId) async {
    try {
      final response = await _supabase
          .from('app_dat_subcategorias')
          .select('*, total_productos:app_dat_productos_subcategorias(count)')
          .eq('id', subcategoryId)
          .single();

      if (response == null) {
        return null;
      }

      return Subcategory.fromJson(response);
    } catch (e) {
      print('Error fetching subcategory by ID: $e');
      return null;
    }
  }

  /// Refresca las subcategorías (útil para pull-to-refresh)
  Future<List<Subcategory>> refreshSubcategories(int categoryId) async {
    return await getSubcategoriesByCategory(categoryId);
  }

  /// Crea una nueva subcategoría en la base de datos
  Future<bool> createSubcategory({
    required int categoryId,
    required String denominacion,
    required String skuCodigo,
  }) async {
    try {
      print('🆕 Creando subcategoría: $denominacion para categoría $categoryId');
      
      // Insertar subcategoría en app_dat_subcategorias
      await _supabase
          .from('app_dat_subcategorias')
          .insert({
            'idcategoria': categoryId,
            'denominacion': denominacion,
            'sku_codigo': skuCodigo,
          });

      print('✅ Subcategoría creada exitosamente');
      return true;
    } catch (e) {
      print('❌ Error al crear subcategoría: $e');
      return false;
    }
  }

  /// Actualiza una subcategoría existente
  Future<bool> updateSubcategory({
    required int subcategoryId,
    required String denominacion,
    required String skuCodigo,
  }) async {
    try {
      print('✏️ Actualizando subcategoría ID: $subcategoryId');
      
      // Actualizar subcategoría en app_dat_subcategorias
      await _supabase
          .from('app_dat_subcategorias')
          .update({
            'denominacion': denominacion,
            'sku_codigo': skuCodigo,
          })
          .eq('id', subcategoryId);

      print('✅ Subcategoría actualizada exitosamente');
      return true;
    } catch (e) {
      print('❌ Error al actualizar subcategoría: $e');
      return false;
    }
  }

  /// Verifica si una subcategoría tiene productos asociados
  Future<bool> subcategoryHasProducts(int subcategoryId) async {
    try {
      // Verificar en la tabla de productos si hay productos con esta subcategoría
      final products = await _supabase
          .from('app_dat_productos')
          .select('id')
          .eq('id_subcategoria', subcategoryId)
          .limit(1);
      
      return products.isNotEmpty;
    } catch (e) {
      print('❌ Error verificando productos: $e');
      return false;
    }
  }

  /// Elimina una subcategoría después de verificar que no tenga productos
  Future<Map<String, dynamic>> deleteSubcategory(int subcategoryId) async {
    try {
      print('🗑️ Eliminando subcategoría ID: $subcategoryId');
      
      // Verificar si tiene productos asociados
      final hasProducts = await subcategoryHasProducts(subcategoryId);
      if (hasProducts) {
        return {
          'success': false,
          'error': 'products_exist',
          'message': 'Esta subcategoría tiene aún productos configurados. Elimine primero los productos asociados.'
        };
      }
      
      // Eliminar subcategoría.
      // Sin filtro `oculta`: esto borra por id, no lista. Filtrar aquí
      // convertiría el borrado de una subcategoría del sistema en un "éxito"
      // que no borra nada (PostgREST no devuelve error si no hay filas).
      await _supabase
          .from('app_dat_subcategorias')
          .delete()
          .eq('id', subcategoryId);

      print('✅ Subcategoría eliminada exitosamente');
      return {
        'success': true,
        'message': 'Subcategoría eliminada exitosamente'
      };
    } catch (e) {
      print('❌ Error al eliminar subcategoría: $e');
      return {
        'success': false,
        'error': 'database_error',
        'message': 'Error al eliminar la subcategoría: $e'
      };
    }
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';

class ConsignacionCategoriaService {
  static final _supabase = Supabase.instance.client;

  /// Obtener productos de consignación sin categoría mapeada en la tienda actual
  static Future<List<Map<String, dynamic>>> getProductosSinMapeo() async {
    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      
      if (idTienda == null) {
        debugPrint('❌ No se encontró ID de tienda');
        return [];
      }

      debugPrint('🔍 Obteniendo productos de consignación sin mapeo para tienda: $idTienda');

      final response = await _supabase.rpc(
        'get_productos_consignacion_sin_mapeo',
        params: {'p_id_tienda_destino': idTienda},
      ) as List;

      debugPrint('✅ Productos sin mapeo obtenidos: ${response.length}');
      return response.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (e) {
      debugPrint('❌ Error obteniendo productos sin mapeo: $e');
      return [];
    }
  }

  /// Obtener categorías disponibles en la tienda actual
  static Future<List<Map<String, dynamic>>> getCategoriasTienda() async {
    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      
      if (idTienda == null) {
        debugPrint('❌ No se encontró ID de tienda');
        return [];
      }

      debugPrint('🔍 Obteniendo categorías de tienda: $idTienda');

      final response = await _supabase
          .from('app_dat_categoria_tienda')
          .select('id_categoria, app_dat_categoria(id, denominacion)')
          .eq('id_tienda', idTienda)
          .order('app_dat_categoria.denominacion');

      debugPrint('✅ Categorías obtenidas: ${response.length}');

      return response.map((item) {
        final categoria = item['app_dat_categoria'] as Map<String, dynamic>;
        return {
          'id': categoria['id'],
          'denominacion': categoria['denominacion'],
        };
      }).toList();
    } catch (e) {
      debugPrint('❌ Error obteniendo categorías: $e');
      return [];
    }
  }

  /// Obtener subcategorías de una categoría
  static Future<List<Map<String, dynamic>>> getSubcategorias(int idCategoria) async {
    try {
      debugPrint('🔍 Obteniendo subcategorías para categoría: $idCategoria');

      final response = await _supabase
          .from('app_dat_subcategorias')
          .select('id, denominacion')
          .eq('idcategoria', idCategoria)
          .order('denominacion');

      debugPrint('✅ Subcategorías obtenidas: ${response.length}');
      return response.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (e) {
      debugPrint('❌ Error obteniendo subcategorías: $e');
      return [];
    }
  }

  /// Asignar categoría a producto de consignación
  static Future<bool> asignarCategoriaProducto({
    required int idProductoConsignacion,
    required int idCategoria,
    int? idSubcategoria,
  }) async {
    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      
      if (idTienda == null) {
        debugPrint('❌ No se encontró ID de tienda');
        return false;
      }

      debugPrint('📝 Asignando categoría $idCategoria a producto $idProductoConsignacion');

      final response = await _supabase.rpc(
        'asignar_categoria_producto_consignacion',
        params: {
          'p_id_producto_consignacion': idProductoConsignacion,
          'p_id_tienda_destino': idTienda,
          'p_id_categoria_destino': idCategoria,
          'p_id_subcategoria_destino': idSubcategoria,
        },
      );

      debugPrint('✅ Categoría asignada exitosamente');
      return true;
    } catch (e) {
      debugPrint('❌ Error asignando categoría: $e');
      return false;
    }
  }

  /// Obtener productos de consignación para venta (con categoría asignada)
  static Future<List<Map<String, dynamic>>> getProductosParaVenta({
    int? idCategoria,
  }) async {
    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      
      if (idTienda == null) {
        debugPrint('❌ No se encontró ID de tienda');
        return [];
      }

      debugPrint('🔍 Obteniendo productos de consignación para venta');

      final response = await _supabase.rpc(
        'get_productos_consignacion_para_venta',
        params: {
          'p_id_tienda_destino': idTienda,
          'p_id_categoria_destino': idCategoria,
        },
      ) as List;

      debugPrint('✅ Productos para venta obtenidos: ${response.length}');
      return response.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (e) {
      debugPrint('❌ Error obteniendo productos para venta: $e');
      return [];
    }
  }

  /// Obtener mapeo de categorías entre tiendas
  static Future<List<Map<String, dynamic>>> getMapeosCategorias({
    int? idTiendaOrigen,
  }) async {
    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      
      if (idTienda == null) {
        debugPrint('❌ No se encontró ID de tienda');
        return [];
      }

      debugPrint('🔍 Obteniendo mapeos de categorías');

      var query = _supabase
          .from('app_dat_mapeo_categoria_tienda')
          .select('*')
          .eq('id_tienda_destino', idTienda)
          .eq('activo', true);

      if (idTiendaOrigen != null) {
        query = query.eq('id_tienda_origen', idTiendaOrigen);
      }

      final response = await query.order('id_tienda_origen');

      debugPrint('✅ Mapeos obtenidos: ${response.length}');
      return response.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (e) {
      debugPrint('❌ Error obteniendo mapeos: $e');
      return [];
    }
  }

  /// Crear mapeo de categoría entre tiendas
  static Future<bool> crearMapeoCategoria({
    required int idTiendaOrigen,
    required int idCategoriaOrigen,
    required int idTiendaDestino,
    required int idCategoriaDestino,
    int? idSubcategoriaOrigen,
    int? idSubcategoriaDestino,
  }) async {
    try {
      debugPrint('📝 Creando mapeo de categoría');

      await _supabase
          .from('app_dat_mapeo_categoria_tienda')
          .insert({
            'id_tienda_origen': idTiendaOrigen,
            'id_categoria_origen': idCategoriaOrigen,
            'id_tienda_destino': idTiendaDestino,
            'id_categoria_destino': idCategoriaDestino,
            'id_subcategoria_origen': idSubcategoriaOrigen,
            'id_subcategoria_destino': idSubcategoriaDestino,
            'activo': true,
          });

      debugPrint('✅ Mapeo creado exitosamente');
      return true;
    } catch (e) {
      debugPrint('❌ Error creando mapeo: $e');
      return false;
    }
  }

  /// Obtener categoría mapeada para un producto
  static Future<Map<String, dynamic>?> getCategoriaMapeada({
    required int idTiendaOrigen,
    required int idCategoriaOrigen,
    int? idSubcategoriaOrigen,
  }) async {
    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      
      if (idTienda == null) {
        debugPrint('❌ No se encontró ID de tienda');
        return null;
      }

      debugPrint('🔍 Obteniendo categoría mapeada');

      final response = await _supabase.rpc(
        'get_categoria_mapeada',
        params: {
          'p_id_tienda_origen': idTiendaOrigen,
          'p_id_categoria_origen': idCategoriaOrigen,
          'p_id_subcategoria_origen': idSubcategoriaOrigen,
          'p_id_tienda_destino': idTienda,
        },
      ) as List;

      if (response.isEmpty) {
        debugPrint('⚠️ No se encontró mapeo');
        return null;
      }

      debugPrint('✅ Categoría mapeada obtenida');
      return Map<String, dynamic>.from(response.first as Map);
    } catch (e) {
      debugPrint('❌ Error obteniendo categoría mapeada: $e');
      return null;
    }
  }
}

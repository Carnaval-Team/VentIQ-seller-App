import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';

class MarginService {
  static final _supabase = Supabase.instance.client;
  static final _prefs = UserPreferencesService();

  /// Obtiene todos los márgenes comerciales de la tienda del usuario
  static Future<List<Map<String, dynamic>>> getMargenesComerciales() async {
    try {
      final idTienda = await _prefs.getIdTienda();
      if (idTienda == null) throw Exception('No se encontró ID de tienda');

      final response = await _supabase.rpc(
        'get_margenes_comerciales_by_tienda',
        params: {'p_id_tienda': idTienda},
      );

      return List<Map<String, dynamic>>.from(response ?? []);
    } catch (e) {
      print('❌ Error obteniendo márgenes comerciales: $e');
      rethrow;
    }
  }

  /// Crea un nuevo margen comercial
  /// [tipoMargen]: 1 = porcentaje, 2 = monto fijo (CUP)
  static Future<Map<String, dynamic>> crearMargen({
    required int idProducto,
    int? idVariante,
    required double margenDeseado,
    required int tipoMargen,
    required DateTime fechaDesde,
    DateTime? fechaHasta,
  }) async {
    try {
      final idTienda = await _prefs.getIdTienda();
      if (idTienda == null) throw Exception('No se encontró ID de tienda');

      final data = {
        'id_producto': idProducto,
        'id_tienda': idTienda,
        'margen_deseado': margenDeseado,
        'tipo_margen': tipoMargen,
        'fecha_desde': fechaDesde.toIso8601String().split('T')[0],
      };

      if (idVariante != null) {
        data['id_variante'] = idVariante;
      }
      if (fechaHasta != null) {
        data['fecha_hasta'] = fechaHasta.toIso8601String().split('T')[0];
      }

      final response = await _supabase
          .from('app_cont_margen_comercial')
          .insert(data)
          .select()
          .single();

      print('✅ Margen comercial creado: ${response['id']}');
      return response;
    } catch (e) {
      print('❌ Error creando margen comercial: $e');
      rethrow;
    }
  }

  /// Actualiza un margen comercial existente
  static Future<Map<String, dynamic>> actualizarMargen({
    required int idMargen,
    double? margenDeseado,
    int? tipoMargen,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
    bool limpiarFechaHasta = false,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (margenDeseado != null) updateData['margen_deseado'] = margenDeseado;
      if (tipoMargen != null) updateData['tipo_margen'] = tipoMargen;
      if (fechaDesde != null) {
        updateData['fecha_desde'] = fechaDesde.toIso8601String().split('T')[0];
      }
      if (fechaHasta != null) {
        updateData['fecha_hasta'] = fechaHasta.toIso8601String().split('T')[0];
      } else if (limpiarFechaHasta) {
        updateData['fecha_hasta'] = null;
      }

      final response = await _supabase
          .from('app_cont_margen_comercial')
          .update(updateData)
          .eq('id', idMargen)
          .select()
          .single();

      print('✅ Margen comercial actualizado: $idMargen');
      return response;
    } catch (e) {
      print('❌ Error actualizando margen comercial: $e');
      rethrow;
    }
  }

  /// Elimina un margen comercial
  static Future<void> eliminarMargen(int idMargen) async {
    try {
      await _supabase
          .from('app_cont_margen_comercial')
          .delete()
          .eq('id', idMargen);

      print('✅ Margen comercial eliminado: $idMargen');
    } catch (e) {
      print('❌ Error eliminando margen comercial: $e');
      rethrow;
    }
  }

  /// Busca productos de la tienda para el selector
  /// Filtra por denominacion, sku y descripcion
  static Future<List<Map<String, dynamic>>> buscarProductos(String query) async {
    try {
      final idTienda = await _prefs.getIdTienda();
      if (idTienda == null) throw Exception('No se encontró ID de tienda');

      final response = await _supabase
          .from('app_dat_producto')
          .select('id, denominacion, sku, descripcion, imagen')
          .eq('id_tienda', idTienda)
          .isFilter('deleted_at', null)
          .or('denominacion.ilike.%$query%,sku.ilike.%$query%,descripcion.ilike.%$query%')
          .order('denominacion')
          .limit(20);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error buscando productos: $e');
      return [];
    }
  }

  /// Obtiene el margen activo para un producto específico
  /// Usado al completar recepciones para verificar si se debe ajustar el precio
  static Future<Map<String, dynamic>?> getMargenActivoProducto(int idProducto) async {
    try {
      final idTienda = await _prefs.getIdTienda();
      if (idTienda == null) return null;

      final response = await _supabase
          .from('app_cont_margen_comercial')
          .select('id, margen_deseado, tipo_margen')
          .eq('id_producto', idProducto)
          .eq('id_tienda', idTienda)
          .lte('fecha_desde', DateTime.now().toIso8601String().split('T')[0])
          .or('fecha_hasta.is.null,fecha_hasta.gte.${DateTime.now().toIso8601String().split('T')[0]}')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      return response;
    } catch (e) {
      print('❌ Error obteniendo margen activo: $e');
      return null;
    }
  }
}

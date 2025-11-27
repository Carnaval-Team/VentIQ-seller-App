import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';

class ConsignacionDuplicacionService {
  static final _supabase = Supabase.instance.client;

  /// Duplicar producto SOLO si no existe en tienda destino (Bajo Demanda)
  /// Si ya existe, retorna el ID del producto existente
  /// Si no existe, lo duplica completamente
  static Future<int?> duplicarProductoSiNecesario({
    required int idProductoOriginal,
    required int idTiendaDestino,
    required int idContratoConsignacion,
    required int idTiendaOrigen,
  }) async {
    try {
      final userPrefs = UserPreferencesService();
      final userId = await userPrefs.getUserId();

      debugPrint(
          '🔄 Verificando si producto $idProductoOriginal existe en tienda $idTiendaDestino');

      final response = await _supabase.rpc(
        'duplicar_producto_si_necesario',
        params: {
          'p_id_producto_original': idProductoOriginal,
          'p_id_tienda_destino': idTiendaDestino,
          'p_id_contrato_consignacion': idContratoConsignacion,
          'p_id_tienda_origen': idTiendaOrigen,
          'p_uuid_usuario': userId,
        },
      ) as List;

      if (response.isNotEmpty) {
        final result = response.first as Map<String, dynamic>;
        if (result['success'] == true) {
          final idProducto = result['id_producto_resultado'] as int;
          final fueDuplicado = result['fue_duplicado'] as bool;

          if (fueDuplicado) {
            debugPrint('✅ Producto duplicado: $idProducto');
            debugPrint('   Producto original: $idProductoOriginal');
            debugPrint('   Tienda destino: $idTiendaDestino');
          } else {
            debugPrint('♻️ Producto reutilizado (ya existía en tienda destino)');
            debugPrint('   ID del producto encontrado: $idProducto');
            debugPrint('   Producto original: $idProductoOriginal');
            debugPrint('   Tienda destino: $idTiendaDestino');
            
            // Obtener detalles del producto encontrado
            try {
              final productoEncontrado = await _supabase
                  .from('app_dat_producto')
                  .select('id, denominacion, sku, id_categoria')
                  .eq('id', idProducto)
                  .single();
              
              debugPrint('   Nombre: ${productoEncontrado['denominacion']}');
              debugPrint('   SKU: ${productoEncontrado['sku']}');
              debugPrint('   Categoría ID: ${productoEncontrado['id_categoria']}');
            } catch (e) {
              debugPrint('   ⚠️ No se pudieron obtener detalles del producto: $e');
            }
          }

          debugPrint('   Mensaje: ${result['message']}');
          return idProducto;
        } else {
          debugPrint('❌ Error: ${result['message']}');
        }
      }

      debugPrint('❌ Error: respuesta vacía');
      return null;
    } catch (e) {
      debugPrint('❌ Error: $e');
      return null;
    }
  }

  /// Duplicar un producto completo de consignación en tienda destino
  /// Copia: producto base, subcategorías, presentaciones, multimedias, etiquetas, unidades, garantía
  static Future<int?> duplicarProductoConsignacion({
    required int idProductoOriginal,
    required int idTiendaDestino,
    required int idContratoConsignacion,
    required int idTiendaOrigen,
  }) async {
    try {
      final userPrefs = UserPreferencesService();
      final userId = await userPrefs.getUserId();

      debugPrint(
          '🔄 Duplicando producto $idProductoOriginal en tienda $idTiendaDestino');

      final response = await _supabase.rpc(
        'duplicar_producto_consignacion',
        params: {
          'p_id_producto_original': idProductoOriginal,
          'p_id_tienda_destino': idTiendaDestino,
          'p_id_contrato_consignacion': idContratoConsignacion,
          'p_id_tienda_origen': idTiendaOrigen,
          'p_uuid_usuario': userId,
        },
      ) as List;

      if (response.isNotEmpty) {
        final result = response.first as Map<String, dynamic>;
        if (result['success'] == true) {
          final idProductoNuevo = result['id_producto_nuevo'] as int;
          debugPrint('✅ Producto duplicado: $idProductoNuevo');
          debugPrint('   Mensaje: ${result['message']}');
          return idProductoNuevo;
        } else {
          debugPrint('❌ Error: ${result['message']}');
        }
      }

      debugPrint('❌ Error duplicando producto: respuesta vacía');
      return null;
    } catch (e) {
      debugPrint('❌ Error duplicando producto: $e');
      return null;
    }
  }

  /// Duplicar múltiples productos de un contrato de consignación
  static Future<Map<String, dynamic>?> duplicarProductosContrato({
    required int idContrato,
    required int idTiendaDestino,
    required int idTiendaOrigen,
  }) async {
    try {
      final userPrefs = UserPreferencesService();
      final userId = await userPrefs.getUserId();

      debugPrint('🔄 Duplicando productos del contrato $idContrato');

      final response = await _supabase.rpc(
        'duplicar_productos_contrato_consignacion',
        params: {
          'p_id_contrato': idContrato,
          'p_id_tienda_destino': idTiendaDestino,
          'p_id_tienda_origen': idTiendaOrigen,
          'p_uuid_usuario': userId,
        },
      ) as List;

      if (response.isNotEmpty) {
        final result = response.first as Map<String, dynamic>;
        debugPrint('✅ Duplicación completada');
        debugPrint('   Total: ${result['total_productos']}');
        debugPrint('   Exitosos: ${result['productos_duplicados']}');
        debugPrint('   Fallidos: ${result['productos_fallidos']}');
        debugPrint('   Mensaje: ${result['message']}');
        return result;
      }

      debugPrint('❌ Error duplicando productos: respuesta vacía');
      return null;
    } catch (e) {
      debugPrint('❌ Error duplicando productos: $e');
      return null;
    }
  }

  /// Obtener registro de duplicación de un producto
  static Future<Map<String, dynamic>?> obtenerDuplicacion({
    required int idProductoOriginal,
    required int idTiendaDestino,
  }) async {
    try {
      debugPrint(
          '🔍 Obteniendo duplicación de producto $idProductoOriginal en tienda $idTiendaDestino');

      final response = await _supabase.rpc(
        'get_producto_duplicado',
        params: {
          'p_id_producto_original': idProductoOriginal,
          'p_id_tienda_destino': idTiendaDestino,
        },
      ) as List;

      if (response.isNotEmpty) {
        final result = response.first as Map<String, dynamic>;
        debugPrint('✅ Duplicación encontrada: ${result['id_producto_duplicado']}');
        return result;
      }

      debugPrint('⚠️ No se encontró duplicación');
      return null;
    } catch (e) {
      debugPrint('❌ Error obteniendo duplicación: $e');
      return null;
    }
  }

  /// Obtener historial de duplicaciones de un contrato
  static Future<List<Map<String, dynamic>>> obtenerHistorialDuplicaciones(
    int idContrato,
  ) async {
    try {
      debugPrint('🔍 Obteniendo historial de duplicaciones del contrato $idContrato');

      final response = await _supabase.rpc(
        'get_historial_duplicaciones_contrato',
        params: {
          'p_id_contrato': idContrato,
        },
      ) as List;

      final historial = response
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      debugPrint('✅ Historial obtenido: ${historial.length} registros');
      return historial;
    } catch (e) {
      debugPrint('❌ Error obteniendo historial: $e');
      return [];
    }
  }

  /// Verificar si un producto ya fue duplicado en una tienda
  static Future<bool> yaFueDuplicado({
    required int idProductoOriginal,
    required int idTiendaDestino,
  }) async {
    try {
      final duplicacion = await obtenerDuplicacion(
        idProductoOriginal: idProductoOriginal,
        idTiendaDestino: idTiendaDestino,
      );

      return duplicacion != null;
    } catch (e) {
      debugPrint('❌ Error verificando duplicación: $e');
      return false;
    }
  }

  /// Obtener información del producto duplicado
  static Future<Map<String, dynamic>?> obtenerProductoDuplicado({
    required int idProductoOriginal,
    required int idTiendaDestino,
  }) async {
    try {
      final duplicacion = await obtenerDuplicacion(
        idProductoOriginal: idProductoOriginal,
        idTiendaDestino: idTiendaDestino,
      );

      if (duplicacion == null) {
        return null;
      }

      final idProductoDuplicado = duplicacion['id_producto_duplicado'] as int;

      // Obtener datos del producto duplicado
      final response = await _supabase
          .from('app_dat_producto')
          .select('*')
          .eq('id', idProductoDuplicado)
          .single();

      return response as Map<String, dynamic>;
    } catch (e) {
      debugPrint('❌ Error obteniendo producto duplicado: $e');
      return null;
    }
  }

  /// Obtener estadísticas de duplicación de un contrato
  static Future<Map<String, dynamic>?> obtenerEstadisticasDuplicacion(
    int idContrato,
  ) async {
    try {
      final historial = await obtenerHistorialDuplicaciones(idContrato);

      final estadisticas = {
        'total_productos': historial.length,
        'fecha_primera_duplicacion': historial.isNotEmpty
            ? historial.last['fecha_duplicacion']
            : null,
        'fecha_ultima_duplicacion': historial.isNotEmpty
            ? historial.first['fecha_duplicacion']
            : null,
        'tiendas_destino': <int>{
          for (final item in historial) item['id_tienda_destino'] as int
        }.length,
      };

      debugPrint('📊 Estadísticas: $estadisticas');
      return estadisticas;
    } catch (e) {
      debugPrint('❌ Error obteniendo estadísticas: $e');
      return null;
    }
  }
}

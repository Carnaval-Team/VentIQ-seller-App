import 'package:supabase_flutter/supabase_flutter.dart';

class ProductMovementsService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Obtiene movimientos de un producto con paginado usando RPC optimizado
  static Future<Map<String, dynamic>> getProductMovements({
    required int productId,
    DateTime? dateFrom,
    DateTime? dateTo,
    int? operationTypeId,
    int? warehouseId,
    int offset = 0,
    int limit = 20,
  }) async {
    try {
      print('Obteniendo movimientos del producto $productId (offset: $offset, limit: $limit)');
      print('Filtros: desde=$dateFrom, hasta=$dateTo, tipoOp=$operationTypeId, almacen=$warehouseId');

      final response = await _supabase.rpc(
        'get_product_movements_v3',
        params: {
          'p_id_producto': productId,
          'p_fecha_desde': dateFrom == null
              ? null
              : '${dateFrom.year.toString().padLeft(4, '0')}-${dateFrom.month.toString().padLeft(2, '0')}-${dateFrom.day.toString().padLeft(2, '0')}',
          'p_fecha_hasta': dateTo == null
              ? null
              : '${dateTo.year.toString().padLeft(4, '0')}-${dateTo.month.toString().padLeft(2, '0')}-${dateTo.day.toString().padLeft(2, '0')}',
          'p_tipo_operacion_id': operationTypeId,
          'p_id_almacen': warehouseId,
          'p_offset': offset,
          'p_limit': limit,
        },
      );

      final rawMovements = List<Map<String, dynamic>>.from(response ?? []);
      final totalCount = rawMovements.isNotEmpty
          ? (rawMovements[0]['total_count'] as int?) ?? 0
          : 0;
      final movements = rawMovements.map((m) {
        return {
          ...m,
          'almacen': m['almacen_nombre'] ?? m['almacen'],
          'ubicacion': m['ubicacion_nombre'] ?? m['ubicacion'],
          'zona': m['ubicacion_nombre'] ?? m['zona'],
          'proveedor': m['proveedor_nombre'] ?? m['proveedor'],
        };
      }).toList();

      print('Movimientos obtenidos: ' + movements.toString());

      print('[ProductMovements] Total: ${movements.length} filas (total_count=$totalCount, offset=$offset, limit=$limit)');
      for (int i = 0; i < movements.length; i++) {
        final m = movements[i];
        print(
          '[ProductMovements] #${i + 1} '
          'inv_id=${m["id"]} '
          'id_op=${m["id_operacion"]} '
          'tipo_mov=${m["tipo_movimiento"]} '
          'tipo_op=${m["tipo_operacion"]} '
          'cantidad=${m["cantidad"]} '
          'fecha=${m["fecha"]} '
          'almacen=${m["almacen"]} '
          'estado=${m["estado_operacion_nombre"]}',
        );
      }
      return {
        'movements': movements,
        'total_count': totalCount,
        'offset': offset,
        'limit': limit,
      };
    } catch (e) {
      print('Error al obtener movimientos: $e');
      rethrow;
    }
  }

  /// Obtiene todos los tipos de operacion disponibles
  static Future<List<Map<String, dynamic>>> getOperationTypes() async {
    try {
      final response = await _supabase
          .from('app_nom_tipo_operacion')
          .select('id, denominacion, descripcion')
          .order('denominacion');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error al obtener tipos de operacion: $e');
      return [];
    }
  }
}

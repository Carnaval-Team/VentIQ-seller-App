import 'package:supabase_flutter/supabase_flutter.dart';

class ProductMovementsService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Orden estable por fecha de creación ASC (desempate por id de movimiento).
  /// Necesario porque el RPC en servidor puede estar en DESC / id_op y el
  /// paginado solo es coherente si ordenamos el conjunto completo.
  static List<Map<String, dynamic>> sortMovementsByFecha(
    List<Map<String, dynamic>> source,
  ) {
    final list = List<Map<String, dynamic>>.from(source);
    list.sort((a, b) {
      final fa = DateTime.tryParse('${a['fecha'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final fb = DateTime.tryParse('${b['fecha'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final byFecha = fa.compareTo(fb);
      if (byFecha != 0) return byFecha;
      final idA = (a['id'] as num?)?.toInt() ?? 0;
      final idB = (b['id'] as num?)?.toInt() ?? 0;
      return idA.compareTo(idB);
    });
    return list;
  }

  /// Cancelaciones de stock: sin id_operacion. En UI/auditoría se muestran
  /// como tipo_movimiento=Reajuste, estado=Reajuste, tipo_operacion=
  /// "Reajuste de cancelación".
  static bool isCancelacionReajuste(Map<String, dynamic> m) {
    // FASE 2/3 presentaciones: una conversión (abrir/empaquetar) también llega
    // sin id_operacion, así que caía en esta rama y se etiquetaba como
    // "Reajuste de cancelación" — un movimiento deliberado disfrazado de
    // corrección de error. La v4 la marca con es_conversion.
    if (m['es_conversion'] == true) return false;

    final tipoMov = (m['tipo_movimiento'] as String?)?.toLowerCase().trim() ?? '';
    if (tipoMov != 'reajuste') return false;

    final tipoOp = (m['tipo_operacion'] as String?)?.toLowerCase().trim() ?? '';
    if (tipoOp.contains('cancelacion') || tipoOp.contains('cancelación')) {
      return true;
    }

    // Sin operación padre = cancelación (los "Ajuste" sí traen id_operacion).
    final opId = m['id_operacion'];
    final hasOp = opId != null && '$opId'.trim().isNotEmpty && '$opId' != 'null';
    if (hasOp) return false;

    final estado =
        (m['estado_operacion_nombre'] as String?)?.toLowerCase().trim() ?? '';
    return estado.isEmpty ||
        estado == 'reajuste' ||
        estado == 'desconocido' ||
        tipoOp.isEmpty ||
        tipoOp == 'reajuste';
  }

  static Map<String, dynamic> normalizeCancelReajusteLabels(
    Map<String, dynamic> m,
  ) {
    if (!isCancelacionReajuste(m)) return m;
    final out = Map<String, dynamic>.from(m);
    out['tipo_movimiento'] = 'Reajuste';
    final tipoOp = (out['tipo_operacion'] as String?)?.trim() ?? '';
    if (tipoOp.isEmpty ||
        tipoOp.toLowerCase() == 'reajuste' ||
        tipoOp == '-') {
      out['tipo_operacion'] = 'Reajuste de cancelación';
    }
    out['estado_operacion_nombre'] = 'Reajuste';
    out['id_operacion'] = null;
    return out;
  }

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
        // FASE 3 presentaciones: la v4 añade id_presentacion,
        // presentacion_nombre, presentacion_factor, cantidad_formateada
        // ("21 Bultos"), id_conversion y es_conversion. Las 28 columnas de la v3
        // no se movieron (verificado fila por fila contra producción), así que
        // el resto de la pantalla sigue leyendo lo mismo.
        // Ver presentaciones_inventario/17_kardex_con_presentacion.sql
        'get_product_movements_v4',
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
        final normalized = Map<String, dynamic>.from({
          ...m,
          'almacen': m['almacen_nombre'] ?? m['almacen'],
          'ubicacion': m['ubicacion_nombre'] ?? m['ubicacion'],
          'zona': m['ubicacion_nombre'] ?? m['zona'],
          'proveedor': m['proveedor_nombre'] ?? m['proveedor'],
        });
        return normalizeCancelReajusteLabels(normalized);
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

  /// Obtiene **todas** las páginas de movimientos según los filtros.
  /// Usa el mismo RPC paginado y recorre hasta cubrir [total_count].
  static Future<List<Map<String, dynamic>>> getAllProductMovements({
    required int productId,
    DateTime? dateFrom,
    DateTime? dateTo,
    int? operationTypeId,
    int? warehouseId,
    int pageSize = 500,
  }) async {
    final all = <Map<String, dynamic>>[];
    var offset = 0;
    var totalCount = 0;

    do {
      final result = await getProductMovements(
        productId: productId,
        dateFrom: dateFrom,
        dateTo: dateTo,
        operationTypeId: operationTypeId,
        warehouseId: warehouseId,
        offset: offset,
        limit: pageSize,
      );

      final batch =
          List<Map<String, dynamic>>.from(result['movements'] ?? const []);
      totalCount = (result['total_count'] as int?) ?? 0;
      all.addAll(batch);

      if (batch.isEmpty) break;
      offset += pageSize;
    } while (all.length < totalCount);

    final sorted = sortMovementsByFecha(all);
    print(
      '[ProductMovements] Export completo: ${sorted.length} filas '
      '(total_count=$totalCount, orden=fecha ASC)',
    );
    return sorted;
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

import 'package:supabase_flutter/supabase_flutter.dart';

/// CRUD de costos adicionales por producto (`app_dat_producto_costo`).
class CostosAdicionalesService {
  CostosAdicionalesService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<List<Map<String, dynamic>>> listarPorProducto(int idProducto) async {
    final response = await _supabase
        .from('app_dat_producto_costo')
        .select('''
          id,
          id_producto,
          id_tipo_costo,
          monto_usd,
          monto_promedio_usd,
          activo,
          created_at,
          app_cont_tipo_costo ( id, denominacion, descripcion )
        ''')
        .eq('id_producto', idProducto)
        .order('id');

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> listarActivosPorProducto(
    int idProducto,
  ) async {
    final all = await listarPorProducto(idProducto);
    return all.where((c) => c['activo'] == true).toList();
  }

  Future<List<Map<String, dynamic>>> listarActivosPorProductos(
    List<int> idsProducto,
  ) async {
    if (idsProducto.isEmpty) return [];
    final response = await _supabase
        .from('app_dat_producto_costo')
        .select('''
          id,
          id_producto,
          id_tipo_costo,
          monto_usd,
          monto_promedio_usd,
          activo,
          app_cont_tipo_costo ( id, denominacion )
        ''')
        .inFilter('id_producto', idsProducto)
        .eq('activo', true);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> crear({
    required int idProducto,
    required int idTipoCosto,
    required double montoUsd,
  }) async {
    final response = await _supabase
        .from('app_dat_producto_costo')
        .insert({
          'id_producto': idProducto,
          'id_tipo_costo': idTipoCosto,
          'monto_usd': montoUsd,
          'monto_promedio_usd': montoUsd,
          'activo': true,
        })
        .select('''
          id,
          id_producto,
          id_tipo_costo,
          monto_usd,
          monto_promedio_usd,
          activo,
          created_at,
          app_cont_tipo_costo ( id, denominacion, descripcion )
        ''')
        .single();

    return Map<String, dynamic>.from(response);
  }

  Future<void> actualizarMonto({
    required int id,
    required double montoUsd,
  }) async {
    await _supabase
        .from('app_dat_producto_costo')
        .update({'monto_usd': montoUsd})
        .eq('id', id);
  }

  Future<void> setActivo({required int id, required bool activo}) async {
    await _supabase
        .from('app_dat_producto_costo')
        .update({'activo': activo})
        .eq('id', id);
  }

  Future<void> eliminar(int id) async {
    await _supabase.from('app_dat_producto_costo').delete().eq('id', id);
  }

  /// Persiste costos aplicados en líneas de una recepción ya insertada.
  Future<void> persistirCostosRecepcion({
    required int idOperacion,
    required List<Map<String, dynamic>> productos,
  }) async {
    final lineas = await _supabase
        .from('app_dat_recepcion_productos')
        .select('id, id_producto, id_presentacion')
        .eq('id_operacion', idOperacion);

    for (final producto in productos) {
      final costos = producto['costos'];
      if (costos is! List || costos.isEmpty) continue;

      final idProducto = _asInt(producto['id_producto'] ?? producto['id']);
      final idPresentacion = _asInt(producto['id_presentacion']);

      Map<String, dynamic>? linea;
      for (final l in lineas) {
        final lPres = _asInt(l['id_presentacion']);
        final lProd = _asInt(l['id_producto']);
        final samePres =
            idPresentacion != null && lPres != null && lPres == idPresentacion;
        final sameProd = lProd != null && lProd == idProducto;
        if (samePres || (idPresentacion == null && sameProd)) {
          linea = Map<String, dynamic>.from(l as Map);
          if (samePres) break;
        }
      }
      if (linea == null) continue;

      final idRp = linea['id'] as int;
      final idProd = linea['id_producto'] as int;

      for (final raw in costos) {
        final c = Map<String, dynamic>.from(raw as Map);
        final idTipo = c['id_tipo_costo'];
        final monto = (c['monto_usd'] as num?)?.toDouble();
        if (idTipo == null || monto == null) continue;

        final prev = await _supabase
            .from('app_dat_producto_costo')
            .select('monto_promedio_usd')
            .eq('id_producto', idProd)
            .eq('id_tipo_costo', idTipo)
            .maybeSingle();

        final prevAvg =
            (prev?['monto_promedio_usd'] as num?)?.toDouble() ?? 0.0;

        final existing = await _supabase
            .from('app_dat_recepcion_producto_costo')
            .select('id')
            .eq('id_recepcion_producto', idRp)
            .eq('id_tipo_costo', idTipo)
            .maybeSingle();

        if (existing != null) {
          await _supabase
              .from('app_dat_recepcion_producto_costo')
              .update({'monto_usd': monto})
              .eq('id', existing['id']);
        } else {
          await _supabase.from('app_dat_recepcion_producto_costo').insert({
            'id_recepcion_producto': idRp,
            'id_tipo_costo': idTipo,
            'monto_usd': monto,
            'monto_promedio_anterior': prevAvg,
          });
        }
      }
    }
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  Future<Map<int, List<Map<String, dynamic>>>> costosPorRecepcionProductos(
    List<int> idsRecepcionProducto,
  ) async {
    if (idsRecepcionProducto.isEmpty) return {};
    final response = await _supabase
        .from('app_dat_recepcion_producto_costo')
        .select('id_recepcion_producto, id_tipo_costo, monto_usd')
        .inFilter('id_recepcion_producto', idsRecepcionProducto);

    final map = <int, List<Map<String, dynamic>>>{};
    for (final row in response) {
      final idRp = row['id_recepcion_producto'] as int;
      map.putIfAbsent(idRp, () => []).add({
        'id_tipo_costo': row['id_tipo_costo'],
        'monto_usd': row['monto_usd'],
      });
    }
    return map;
  }
}

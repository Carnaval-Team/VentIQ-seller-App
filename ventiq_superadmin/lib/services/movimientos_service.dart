import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/movimiento_models.dart';

class MovimientosService {
  static final _supabase = Supabase.instance.client;

  static Future<List<InventarioMovimiento>> getInventarioTiempoReal({
    required int idTienda,
    int pagina = 1,
    int limite = 200,
  }) async {
    try {
      final res = await _supabase.rpc(
        'fn_get_inventario_movimientos_tiempo_real',
        params: {
          'p_id_tienda': idTienda,
          'p_pagina': pagina,
          'p_limite': limite,
        },
      );
      if (res == null) return [];
      final list = (res as List)
          .map((e) => InventarioMovimiento.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList();
      return list;
    } catch (e) {
      debugPrint('❌ Error inventario tiempo real: $e');
      return [];
    }
  }

  static Future<List<HistorialProductoDia>> getHistorialProductoDia({
    required int idTienda,
    required int idProducto,
    int? idUbicacion,
  }) async {
    try {
      final res = await _supabase.rpc(
        'fn_get_historial_producto_dia',
        params: {
          'p_id_tienda': idTienda,
          'p_id_producto': idProducto,
          'p_id_ubicacion': idUbicacion,
        },
      );
      if (res == null) return [];
      return (res as List)
          .map((e) => HistorialProductoDia.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList();
    } catch (e) {
      debugPrint('❌ Error historial producto día: $e');
      return [];
    }
  }

  static Future<List<OperacionTR>> getOperacionesTiempoReal({
    required int idTienda,
    int pagina = 1,
    int limite = 100,
  }) async {
    try {
      final res = await _supabase.rpc(
        'fn_get_operaciones_dia_tiempo_real',
        params: {
          'p_id_tienda': idTienda,
          'p_pagina': pagina,
          'p_limite': limite,
        },
      );
      if (res == null) return [];
      return (res as List)
          .map((e) => OperacionTR.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList();
    } catch (e) {
      debugPrint('❌ Error operaciones tiempo real: $e');
      return [];
    }
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cumplimiento_fisico.dart';

export '../models/cumplimiento_fisico.dart';

/// Consulta el cumplimiento físico sin reservar ni modificar inventario.
class CumplimientoFisicoService {
  CumplimientoFisicoService({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<PlanCumplimiento> preview({
    required int idProducto,
    required int idUbicacion,
    int? idPresentacion,
    required num cantidad,
    int? idVariante,
    int? idOpcionVariante,
  }) async {
    final response = await _supabase.rpc(
      'fn_preview_cumplimiento_v2',
      params: {
        'p_id_producto': idProducto,
        'p_id_ubicacion': idUbicacion,
        'p_id_presentacion': idPresentacion,
        'p_cantidad': cantidad,
        'p_id_variante': idVariante,
        'p_id_opcion_variante': idOpcionVariante,
      },
    );

    if (response is! Map) {
      throw const CumplimientoFisicoException(
        'La vista previa devolvió una respuesta inválida.',
      );
    }

    return PlanCumplimiento.fromJson(Map<String, dynamic>.from(response));
  }
}

class CumplimientoFisicoException implements Exception {
  final String mensaje;
  final Object? causa;

  const CumplimientoFisicoException(this.mensaje, [this.causa]);

  @override
  String toString() => causa == null ? mensaje : '$mensaje: $causa';
}

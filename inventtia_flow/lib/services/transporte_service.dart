import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/transporte.dart';

class TransporteService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  static Future<DisponibilidadTransporte> getDisponibilidad({
    required int idLocalServicio,
    required DateTime fecha,
    required String tipoTrayecto,
  }) async {
    final response = await _supabase
        .schema(_schema)
        .rpc(
          'cliente_obtener_disponibilidad_transporte',
          params: {
            'p_id_local_servicio': idLocalServicio,
            'p_fecha': fecha.toIso8601String().substring(0, 10),
            'p_tipo_trayecto': tipoTrayecto,
          },
        );
    final json = Map<String, dynamic>.from(response as Map);
    if (json['ok'] != true) {
      throw Exception(
        json['error'] ?? 'No se pudo consultar la disponibilidad',
      );
    }
    return DisponibilidadTransporte.fromJson(json);
  }

  static Future<List<DateTime>> getFechasDisponibles({
    required int idLocalServicio,
    required String tipoTrayecto,
  }) async {
    final response = await _supabase
        .schema(_schema)
        .rpc(
          'cliente_obtener_fechas_disponibles_transporte',
          params: {
            'p_id_local_servicio': idLocalServicio,
            'p_tipo_trayecto': tipoTrayecto,
          },
        );
    return (response as List)
        .map((value) => DateTime.parse(value.toString()))
        .toList();
  }

  static Future<Map<String, dynamic>> reservarPasaje({
    required String uuidUsuario,
    required int idLocalServicio,
    required String tipoViaje,
    DateTime? fechaIda,
    int? idTurnoIda,
    DateTime? fechaVuelta,
    int? idTurnoVuelta,
    int cantidad = 1,
    Map<String, dynamic>? datosAdicionales,
    String? moneda,
    bool paraTercero = false,
    String? nombreTercero,
    String? apellidosTercero,
    String? ciTercero,
    String? telefonoTercero,
  }) async {
    final response = await _supabase
        .schema(_schema)
        .rpc(
          'cliente_reservar_pasaje_omnibus',
          params: {
            'p_uuid_usuario': uuidUsuario,
            'p_id_local_servicio': idLocalServicio,
            'p_tipo_viaje': tipoViaje,
            if (fechaIda != null)
              'p_fecha_ida': fechaIda.toIso8601String().substring(0, 10),
            if (idTurnoIda != null) 'p_id_turno_ida': idTurnoIda,
            if (fechaVuelta != null)
              'p_fecha_vuelta': fechaVuelta.toIso8601String().substring(0, 10),
            if (idTurnoVuelta != null) 'p_id_turno_vuelta': idTurnoVuelta,
            'p_cantidad': cantidad,
            'p_datos_adicionales': datosAdicionales ?? const {},
            if (moneda != null) 'p_moneda': moneda,
            'p_para_tercero': paraTercero,
            if (paraTercero) 'p_t_nombre': nombreTercero,
            if (paraTercero) 'p_t_apellidos': apellidosTercero,
            if (paraTercero) 'p_t_ci': ciTercero,
            if (paraTercero) 'p_t_telefono': telefonoTercero,
          },
        );
    final json = Map<String, dynamic>.from(response as Map);
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo reservar el pasaje');
    }
    return Map<String, dynamic>.from(json['data'] as Map? ?? const {});
  }
}

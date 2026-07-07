import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/agenda.dart';
import 'auth_service.dart';

class AgendaAdminService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  static Future<List<Agenda>> listarAgendas({
    required String uuidUsuario,
    int? idEntidad,
    int? idLocal,
    int? idLocalServicio,
    int? idEstado,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final res = await _supabase.schema(_schema).rpc(
      'admin_listar_agendas',
      params: {
        'p_uuid_usuario': uuidUsuario,
        if (idEntidad != null) 'p_id_entidad': idEntidad,
        if (idLocal != null) 'p_id_local': idLocal,
        if (idLocalServicio != null) 'p_id_local_servicio': idLocalServicio,
        if (idEstado != null) 'p_id_estado': idEstado,
        if (desde != null) 'p_desde': desde.toIso8601String(),
        if (hasta != null) 'p_hasta': hasta.toIso8601String(),
      },
    );
    final list = res as List;
    return list.map((e) => Agenda.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> crearReservaDirecta({
    required int idLocalServicio,
    required DateTime fecha,
    int? cantidad,
    Map<String, dynamic>? datosAdicionales,
  }) async {
    try {
      // Usar método robusto con fallback para obtener UUID
      final uuid = await AuthService.getCurrentUserId();
      if (uuid == null) {
        throw Exception('No se pudo obtener el usuario autenticado');
      }
      
      final res = await _supabase.schema(_schema).rpc(
        'admin_crear_reserva_directa',
        params: {
          'p_id_local_servicio': idLocalServicio,
          'p_fecha': fecha.toIso8601String().substring(0, 10),
          if (cantidad != null) 'p_cantidad': cantidad,
          if (datosAdicionales != null) 'p_datos_adicionales': datosAdicionales,
          'p_uuid_admin': uuid, // Siempre enviar el UUID
        },
      );
      final json = res as Map<String, dynamic>;
      if (json['ok'] != true) {
        throw Exception(json['error'] ?? 'No se pudo crear la reserva');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception(e.toString());
    }
  }

  static Future<void> actualizarDatosReserva({
    required int idAgenda,
    required Map<String, dynamic> datosAdicionales,
  }) async {
    await _supabase
        .schema(_schema)
        .from('agenda')
        .update({'datos_adicionales': datosAdicionales})
        .eq('id', idAgenda);
  }

  static Future<List<Agenda>> listarAgendasVendedor({
    required String uuidUsuario,
    int? idEntidad,
    int? idLocal,
    int? idLocalServicio,
    int? idEstado,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    try {
      final params = {
        'p_uuid_usuario': uuidUsuario,
        if (idEntidad != null) 'p_id_entidad': idEntidad,
        if (idLocal != null) 'p_id_local': idLocal,
        if (idLocalServicio != null) 'p_id_local_servicio': idLocalServicio,
        if (idEstado != null) 'p_id_estado': idEstado,
        if (desde != null) 'p_desde': desde.toIso8601String(),
        if (hasta != null) 'p_hasta': hasta.toIso8601String(),
      };
      print('[vendedor] listarAgendasVendedor params=$params');
      final res = await _supabase.schema(_schema).rpc(
        'vendedor_listar_agendas',
        params: params,
      );
      print('[vendedor] listarAgendasVendedor res=${res?.runtimeType} len=${res is List ? (res as List).length : res}');
      final list = res as List;
      return list.map((e) => Agenda.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e, st) {
      print('[vendedor] listarAgendasVendedor ERROR: $e\n$st');
      rethrow;
    }
  }
}

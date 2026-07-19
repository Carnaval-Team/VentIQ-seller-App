import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/agenda.dart';
import 'auth_service.dart';

class AgendaAdminService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  /// Timestamp sin zona horaria para columnas `timestamp without time zone` en PG.
  static String? _tsParam(DateTime? dt) {
    if (dt == null) return null;
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} '
        '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }

  static List<dynamic> _parseJsonbList(dynamic res) {
    if (res == null) return [];
    if (res is List) return res;
    if (res is String) {
      final decoded = jsonDecode(res);
      if (decoded is List) return decoded;
    }
    throw Exception(
      'Respuesta inesperada al listar reservas (${res.runtimeType})',
    );
  }

  static List<Agenda> _mapAgendas(List<dynamic> raw) {
    final out = <Agenda>[];
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        out.add(Agenda.fromJson(Map<String, dynamic>.from(item)));
      } catch (e) {
        // No abortar todo el listado por un registro mal formado.
        print('[flow] AgendaAdminService: omitiendo reserva id=${item['id']}: $e');
      }
    }
    return out;
  }

  static Future<List<Agenda>> listarAgendas({
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
        if (desde != null) 'p_desde': _tsParam(desde),
        if (hasta != null) 'p_hasta': _tsParam(hasta),
      };
      print('[flow] listarAgendas params=$params');
      final res = await _supabase.schema(_schema).rpc(
        'admin_listar_agendas',
        params: params,
      );
      final raw = _parseJsonbList(res);
      final mapped = _mapAgendas(raw);
      print('[flow] listarAgendas raw=${raw.length} parsed=${mapped.length}');
      if (raw.isNotEmpty && mapped.isEmpty) {
        print('[flow] listarAgendas: la RPC devolvió datos pero ninguno parseó');
      }
      return mapped;
    } catch (e, st) {
      print('[flow] listarAgendas ERROR: $e\n$st');
      rethrow;
    }
  }

  static Future<void> crearReservaDirecta({
    required int idLocalServicio,
    required DateTime fecha,
    int? cantidad,
    Map<String, dynamic>? datosAdicionales,
    int? idTurno,
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
          if (idTurno != null) 'p_id_turno': idTurno,
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

  /// Marca una agenda como Completado (id 3) o Cancelado (id 2) desde el
  /// listado de reservas (admin o vendedor). La RPC valida permisos, libera
  /// capacidad al cancelar y sella la atención al completar.
  static Future<Agenda> marcarEstadoAgenda({
    required int idAgenda,
    required int idEstado,
  }) async {
    final res = await _supabase.schema(_schema).rpc(
      'staff_marcar_estado_agenda',
      params: {
        'p_id_agenda': idAgenda,
        'p_id_estado': idEstado,
      },
    );
    return Agenda.fromJson(res as Map<String, dynamic>);
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
        if (desde != null) 'p_desde': _tsParam(desde),
        if (hasta != null) 'p_hasta': _tsParam(hasta),
      };
      print('[vendedor] listarAgendasVendedor params=$params');
      final res = await _supabase.schema(_schema).rpc(
        'vendedor_listar_agendas',
        params: params,
      );
      print('[vendedor] listarAgendasVendedor res=${res?.runtimeType} len=${res is List ? (res as List).length : res}');
      return _mapAgendas(_parseJsonbList(res));
    } catch (e, st) {
      print('[vendedor] listarAgendasVendedor ERROR: $e\n$st');
      rethrow;
    }
  }
}

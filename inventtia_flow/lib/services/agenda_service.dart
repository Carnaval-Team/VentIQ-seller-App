import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/agenda.dart';
import '../models/disponibilidad_dia.dart';

class AgendaService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  /// Días con disponibilidad para reserva directa de un local_servicio.
  static Future<List<DisponibilidadDia>> getDisponibilidad(
      int idLocalServicio) async {
    final res = await _supabase.schema(_schema).rpc(
      'cliente_obtener_disponibilidad',
      params: {'p_id_local_servicio': idLocalServicio},
    );
    if (res == null) return [];
    return (res as List)
        .map((e) => DisponibilidadDia.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Reserva directa (sin cola) para una fecha con cupo. Lanza si falla.
  /// Permite cantidad (1..disponibles), datos adicionales y reservar para tercero.
  static Future<void> reservarDirecto({
    required String uuidUsuario,
    required int idLocalServicio,
    required DateTime fecha,
    int? cantidad,
    Map<String, dynamic>? datosAdicionales,
    bool paraTercero = false,
    String? terceroNombre,
    String? terceroApellidos,
    String? terceroCi,
    String? terceroTelefono,
  }) async {
    final res = await _supabase.schema(_schema).rpc(
      'cliente_reservar_directo',
      params: {
        'p_uuid_usuario': uuidUsuario,
        'p_id_local_servicio': idLocalServicio,
        'p_fecha': fecha.toIso8601String().substring(0, 10),
        if (cantidad != null) 'p_cantidad': cantidad,
        if (datosAdicionales != null) 'p_datos_adicionales': datosAdicionales,
        'p_para_tercero': paraTercero,
        if (paraTercero) 'p_t_nombre': terceroNombre,
        if (paraTercero) 'p_t_apellidos': terceroApellidos,
        if (paraTercero) 'p_t_ci': terceroCi,
        if (paraTercero) 'p_t_telefono': terceroTelefono,
      },
    );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo reservar');
    }
  }

  static Future<List<Agenda>> getMisTickets(String uuidUsuario,
      {int? idEstado}) async {
    final res = await _supabase.schema(_schema).rpc('cliente_obtener_agendas', params: {
      'p_uuid_usuario': uuidUsuario,
      if (idEstado != null) 'p_id_estado': idEstado,
    });
    if (res == null) return [];
    final list = res as List;
    return list.map((e) => Agenda.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<Agenda> crearTicket({
    required String uuidUsuario,
    required int idLocalServicio,
    required DateTime fechaHoraReserva,
  }) async {
    // Estado 'reservado' = id 1
    final estadoRes = await _supabase
        .schema(_schema)
        .from('nom_estado_agenda')
        .select('id')
        .eq('nombre', 'reservado')
        .single();
    final idEstado = estadoRes['id'] as int;

    final res = await _supabase
        .schema(_schema)
        .from('agenda')
        .insert({
          'uuid_usuario': uuidUsuario,
          'id_local_servicio': idLocalServicio,
          'id_estado': idEstado,
          'fecha_hora_reserva': fechaHoraReserva.toIso8601String(),
        })
        .select(
          '*, nom_estado_agenda(*), local_servicio(*, app_dat_locales(*), app_dat_servicios(*))',
        )
        .single();
    return Agenda.fromJson(res);
  }

  static Future<Agenda> cancelarTicket(int idAgenda) async {
    final estadoRes = await _supabase
        .schema(_schema)
        .from('nom_estado_agenda')
        .select('id')
        .eq('nombre', 'cancelado')
        .single();
    final idEstado = estadoRes['id'] as int;

    final res = await _supabase
        .schema(_schema)
        .from('agenda')
        .update({'id_estado': idEstado})
        .eq('id', idAgenda)
        .select(
          '*, nom_estado_agenda(*), local_servicio(*, app_dat_locales(*), app_dat_servicios(*))',
        )
        .single();
    return Agenda.fromJson(res);
  }

  /// Cancela una reserva como cliente. Si la entidad configuró horas de
  /// anticipación, valida el plazo; de lo contrario permite cancelar en cualquier momento.
  static Future<void> cancelarTicketCliente({
    required String uuidUsuario,
    required int idAgenda,
  }) async {
    final res = await _supabase.schema(_schema).rpc(
      'cliente_cancelar_reserva',
      params: {
        'p_uuid_usuario': uuidUsuario,
        'p_id_agenda': idAgenda,
      },
    );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo cancelar la reserva');
    }
  }

  static Future<List<EstadoAgenda>> getEstados() async {
    final res = await _supabase
        .schema(_schema)
        .from('nom_estado_agenda')
        .select()
        .order('id');
    return (res as List).map((e) => EstadoAgenda.fromJson(e)).toList();
  }
}

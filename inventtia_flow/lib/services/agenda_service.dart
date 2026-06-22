import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/agenda.dart';

class AgendaService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  static Future<List<Agenda>> getMisTickets(String uuidUsuario,
      {int? idEstado}) async {
    final res = await _supabase.schema(_schema).rpc('cliente_obtener_agendas', params: {
      'p_uuid_usuario': uuidUsuario,
      if (idEstado != null) 'p_id_estado': idEstado,
    });
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

  static Future<List<EstadoAgenda>> getEstados() async {
    final res = await _supabase
        .schema(_schema)
        .from('nom_estado_agenda')
        .select()
        .order('id');
    return (res as List).map((e) => EstadoAgenda.fromJson(e)).toList();
  }
}

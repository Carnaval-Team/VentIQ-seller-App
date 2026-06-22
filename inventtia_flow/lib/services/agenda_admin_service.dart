import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/agenda.dart';

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
}

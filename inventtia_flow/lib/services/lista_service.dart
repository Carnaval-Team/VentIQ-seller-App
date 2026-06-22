import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sala_espera.dart';

class ListaService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  /// Anota al usuario en la cola del servicio-local. Obtiene y asigna
  /// el siguiente número de turno de forma atómica usando ultimo_numero.
  static Future<SalaEspera> anotarseEnLista({
    required String uuidUsuario,
    required int idLocalServicio,
  }) async {
    // Obtener o crear el registro de ultimo_numero
    final ultimoRes = await _supabase
        .schema(_schema)
        .from('ultimo_numero')
        .select()
        .eq('id_local_servicio', idLocalServicio)
        .maybeSingle();

    int siguienteNumero;
    if (ultimoRes == null) {
      // Primera vez: insertar con número 1
      await _supabase.schema(_schema).from('ultimo_numero').insert({
        'id_local_servicio': idLocalServicio,
        'ultimo_otorgado': 1,
      });
      siguienteNumero = 1;
    } else {
      siguienteNumero = (ultimoRes['ultimo_otorgado'] as int) + 1;
      await _supabase
          .schema(_schema)
          .from('ultimo_numero')
          .update({'ultimo_otorgado': siguienteNumero})
          .eq('id_local_servicio', idLocalServicio);
    }

    // Insertar en sala_espera
    final res = await _supabase
        .schema(_schema)
        .from('sala_espera')
        .insert({
          'uuid_usuario': uuidUsuario,
          'id_local_servicio': idLocalServicio,
          'numero_cola': siguienteNumero,
        })
        .select('*, local_servicio(*, app_dat_locales(*), app_dat_servicios(*))')
        .single();

    return SalaEspera.fromJson(res);
  }

  /// Mis entradas en sala de espera activas
  static Future<List<SalaEspera>> getMisListas(String uuidUsuario) async {
    final res = await _supabase
        .schema(_schema)
        .from('sala_espera')
        .select('*, local_servicio(*, app_dat_locales(*), app_dat_servicios(*))')
        .eq('uuid_usuario', uuidUsuario)
        .order('fecha_regla');
    return (res as List).map((e) => SalaEspera.fromJson(e)).toList();
  }

  /// Lista completa de una cola por local-servicio (para ver posición)
  static Future<List<SalaEspera>> getListaCompleta(int idLocalServicio) async {
    final res = await _supabase
        .schema(_schema)
        .from('sala_espera')
        .select('*, local_servicio(*, app_dat_locales(*), app_dat_servicios(*))')
        .eq('id_local_servicio', idLocalServicio)
        .order('numero_cola');
    return (res as List).map((e) => SalaEspera.fromJson(e)).toList();
  }

  /// Salir de la cola
  static Future<void> salirDeLista({
    required String uuidUsuario,
    required int idLocalServicio,
  }) async {
    await _supabase
        .schema(_schema)
        .from('sala_espera')
        .delete()
        .eq('uuid_usuario', uuidUsuario)
        .eq('id_local_servicio', idLocalServicio);
  }

  /// Último número otorgado para un local-servicio
  static Future<int> getUltimoNumero(int idLocalServicio) async {
    final res = await _supabase
        .schema(_schema)
        .from('ultimo_numero')
        .select('ultimo_otorgado')
        .eq('id_local_servicio', idLocalServicio)
        .maybeSingle();
    return res != null ? (res['ultimo_otorgado'] as int) : 0;
  }

  /// Stream en tiempo real de la cola
  static Stream<List<Map<String, dynamic>>> watchLista(int idLocalServicio) {
    return _supabase
        .schema(_schema)
        .from('sala_espera')
        .stream(primaryKey: ['id'])
        .eq('id_local_servicio', idLocalServicio)
        .order('numero_cola');
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sala_espera.dart';

class ListaService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  /// Entra a la sala de espera usando el RPC seguro (con advisory lock + antifraude)
  static Future<void> entrarSalaEspera({
    required String uuidUsuario,
    required int idLocalServicio,
    required DateTime fechaRegla,
  }) async {
    final res = await _supabase.schema(_schema).rpc(
      'cliente_entrar_sala_espera',
      params: {
        'p_uuid_usuario': uuidUsuario,
        'p_id_local_servicio': idLocalServicio,
        'p_fecha_regla': fechaRegla.toIso8601String(),
      },
    );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Error al entrar en la sala de espera');
    }
  }

  /// Sale de la sala de espera usando el RPC (compacta la cola)
  static Future<void> salirSalaEspera({
    required String uuidUsuario,
    required int idLocalServicio,
  }) async {
    final res = await _supabase.schema(_schema).rpc(
      'cliente_salir_sala_espera',
      params: {
        'p_uuid_usuario': uuidUsuario,
        'p_id_local_servicio': idLocalServicio,
      },
    );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Error al salir de la sala de espera');
    }
  }

  /// [Deprecado] Anota al usuario en la cola del servicio-local.
  static Future<SalaEspera> anotarseEnLista({
    required String uuidUsuario,
    required int idLocalServicio,
    required DateTime fechaRegla,
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
          'fecha_regla': fechaRegla.toIso8601String(),
        })
        .select('*, local_servicio(*, app_dat_locales(*), app_dat_servicios(*))')
        .single();

    return SalaEspera.fromJson(res);
  }

  /// Mis entradas en sala de espera activas
  static Future<List<SalaEspera>> getMisListas(String uuidUsuario) async {
    final res = await _supabase.schema(_schema).rpc(
      'cliente_obtener_salas_espera',
      params: {'p_uuid_usuario': uuidUsuario},
    );
    final list = res as List;
    return list.map((e) => SalaEspera.fromJson(e as Map<String, dynamic>)).toList();
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

  /// [Deprecado] Salir de la cola directamente sin RPC
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

  /// Devuelve {ultimo_otorgado, ultimo_en_anotarse} para un local-servicio
  static Future<({int ultimoOtorgado, int ultimoEnAnotarse})>
      getContadoresCola(int idLocalServicio) async {
    final res = await _supabase
        .schema(_schema)
        .from('ultimo_numero')
        .select('ultimo_otorgado, ultimo_en_anotarse')
        .eq('id_local_servicio', idLocalServicio)
        .maybeSingle();
    return (
      ultimoOtorgado: res != null ? (res['ultimo_otorgado'] as int? ?? 0) : 0,
      ultimoEnAnotarse:
          res != null ? (res['ultimo_en_anotarse'] as int? ?? 0) : 0,
    );
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

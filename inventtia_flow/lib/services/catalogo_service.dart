import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/servicio.dart';

class CatalogoService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  static Future<List<Servicio>> getServicios() async {
    final res = await _supabase
        .schema(_schema)
        .from('app_dat_servicios')
        .select()
        .order('nombre');
    return (res as List).map((e) => Servicio.fromJson(e)).toList();
  }

  static Future<List<Servicio>> getServiciosByEntidad(int idEntidad) async {
    final res = await _supabase
        .schema(_schema)
        .from('app_dat_servicios')
        .select()
        .eq('id_entidad', idEntidad)
        .order('nombre');
    return (res as List).map((e) => Servicio.fromJson(e)).toList();
  }

  static Future<Servicio> createServicio({
    required String nombre,
    String? descripcion,
    String? foto,
    required int idEntidad,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .from('app_dat_servicios')
        .insert({
          'nombre': nombre,
          'descripcion': descripcion,
          'foto': foto,
          'id_entidad': idEntidad,
        })
        .select()
        .single();
    return Servicio.fromJson(res);
  }

  static Future<Servicio> updateServicio({
    required int id,
    required String nombre,
    String? descripcion,
    String? foto,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .from('app_dat_servicios')
        .update({'nombre': nombre, 'descripcion': descripcion, if (foto != null) 'foto': foto})
        .eq('id', id)
        .select()
        .single();
    return Servicio.fromJson(res);
  }

  static Future<void> deleteServicio(int id) async {
    await _supabase.schema(_schema).from('app_dat_servicios').delete().eq('id', id);
  }

  static Future<List<Local>> getLocales() async {
    final res = await _supabase
        .schema(_schema)
        .from('app_dat_locales')
        .select()
        .order('nombre');
    return (res as List).map((e) => Local.fromJson(e)).toList();
  }

  static Future<List<Local>> getLocalesByEntidad(int idEntidad) async {
    final res = await _supabase
        .schema(_schema)
        .from('app_dat_locales')
        .select()
        .eq('id_entidad', idEntidad)
        .order('nombre');
    return (res as List).map((e) => Local.fromJson(e)).toList();
  }

  static Future<Local> createLocal({
    required String nombre,
    String? descripcion,
    String? direccion,
    String? horarioAtencion,
    String? pais,
    String? provincia,
    String? foto,
    required int idEntidad,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .from('app_dat_locales')
        .insert({
          'nombre': nombre,
          'descripcion': descripcion,
          'direccion': direccion,
          'horario_atencion': horarioAtencion,
          'pais': pais,
          'provincia': provincia,
          'foto': foto,
          'id_entidad': idEntidad,
        })
        .select()
        .single();
    return Local.fromJson(res);
  }

  static Future<Local> updateLocal({
    required int id,
    required String nombre,
    String? descripcion,
    String? direccion,
    String? horarioAtencion,
    String? pais,
    String? provincia,
    String? foto,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .from('app_dat_locales')
        .update({
          'nombre': nombre,
          'descripcion': descripcion,
          'direccion': direccion,
          'horario_atencion': horarioAtencion,
          'pais': pais,
          'provincia': provincia,
          if (foto != null) 'foto': foto,
        })
        .eq('id', id)
        .select()
        .single();
    return Local.fromJson(res);
  }

  static Future<void> deleteLocal(int id) async {
    await _supabase.schema(_schema).from('app_dat_locales').delete().eq('id', id);
  }

  static Future<List<LocalServicio>> getLocalServicios({
    int? idServicio,
    int? idLocal,
    int? idEntidad,
    String? nombreServicio,
    String? nombreLocal,
    String? pais,
    String? provincia,
  }) async {
    final res = await _supabase.schema(_schema).rpc('cliente_obtener_servicios', params: {
      if (idLocal != null) 'p_id_local': idLocal,
      if (idServicio != null) 'p_id_servicio': idServicio,
      if (idEntidad != null) 'p_id_entidad': idEntidad,
      if (nombreLocal != null) 'p_nombre_local': nombreLocal,
      if (nombreServicio != null) 'p_nombre_servicio': nombreServicio,
      if (pais != null) 'p_pais': pais,
      if (provincia != null) 'p_provincia': provincia,
    });
    final list = res as List;
    return list.map((e) => LocalServicio.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<LocalServicio> getLocalServicio(int id) async {
    final res = await _supabase
        .schema(_schema)
        .from('local_servicio')
        .select('*, app_dat_locales(*), app_dat_servicios(*)')
        .eq('id', id)
        .single();
    return LocalServicio.fromJson(res);
  }

  static Future<List<LocalServicio>> getLocalServiciosByEntidad(
      int idEntidad) async {
    final res = await _supabase
        .schema(_schema)
        .from('local_servicio')
        .select('*, app_dat_locales(*), app_dat_servicios(*)')
        .eq('app_dat_locales.id_entidad', idEntidad);
    return (res as List)
        .where((e) => e['app_dat_locales'] != null)
        .map((e) => LocalServicio.fromJson(e))
        .toList();
  }

  static Future<LocalServicio> createLocalServicio({
    required int idLocal,
    required int idServicio,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .from('local_servicio')
        .insert({'id_local': idLocal, 'id_servicio': idServicio})
        .select('*, app_dat_locales(*), app_dat_servicios(*)')
        .single();
    return LocalServicio.fromJson(res);
  }

  static Future<void> deleteLocalServicio(int id) async {
    await _supabase
        .schema(_schema)
        .from('local_servicio')
        .delete()
        .eq('id', id);
  }

  static Future<bool> existeLocalServicio({
    required int idLocal,
    required int idServicio,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .from('local_servicio')
        .select('id')
        .eq('id_local', idLocal)
        .eq('id_servicio', idServicio);
    return (res as List).isNotEmpty;
  }
}

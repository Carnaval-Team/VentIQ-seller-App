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
    required int idEntidad,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .from('app_dat_servicios')
        .insert({'nombre': nombre, 'descripcion': descripcion, 'id_entidad': idEntidad})
        .select()
        .single();
    return Servicio.fromJson(res);
  }

  static Future<Servicio> updateServicio({
    required int id,
    required String nombre,
    String? descripcion,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .from('app_dat_servicios')
        .update({'nombre': nombre, 'descripcion': descripcion})
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
  }) async {
    var query = _supabase
        .schema(_schema)
        .from('local_servicio')
        .select('*, app_dat_locales(*), app_dat_servicios(*)');

    if (idServicio != null) {
      query = query.eq('id_servicio', idServicio) as dynamic;
    }
    if (idLocal != null) {
      query = query.eq('id_local', idLocal) as dynamic;
    }

    final res = await query;
    return (res as List).map((e) => LocalServicio.fromJson(e)).toList();
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
}

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/entidad.dart';

class EntidadService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  // ── Entidades ──────────────────────────────────────────────

  static Future<List<Entidad>> getEntidades() async {
    final res = await _supabase
        .schema(_schema)
        .from('entidad')
        .select()
        .order('denominacion');
    return (res as List).map((e) => Entidad.fromJson(e)).toList();
  }

  static Future<List<Entidad>> getMisEntidades(String uuidUsuario) async {
    final owned = await _supabase
        .schema(_schema)
        .from('entidad')
        .select()
        .eq('owner_uuid', uuidUsuario)
        .order('denominacion');

    final adminOf = await _supabase
        .schema(_schema)
        .from('entidad_admin')
        .select('id_entidad, entidad(*)')
        .eq('uuid_usuario', uuidUsuario);

    final Set<int> ids = {};
    final List<Entidad> result = [];

    for (final row in owned as List) {
      final e = Entidad.fromJson(row);
      if (ids.add(e.id)) result.add(e);
    }
    for (final row in adminOf as List) {
      if (row['entidad'] != null) {
        final e = Entidad.fromJson(row['entidad'] as Map<String, dynamic>);
        if (ids.add(e.id)) result.add(e);
      }
    }
    result.sort((a, b) => a.denominacion.compareTo(b.denominacion));
    return result;
  }

  static Future<Entidad> createEntidad({
    required String denominacion,
    String? direccion,
    String? telefono,
    required String ownerUuid,
    int horasAnticipacionCancelacion = 0,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .from('entidad')
        .insert({
          'denominacion': denominacion,
          'direccion': direccion,
          'telefono': telefono,
          'owner_uuid': ownerUuid,
          'horas_anticipacion_cancelacion': horasAnticipacionCancelacion,
        })
        .select()
        .single();
    return Entidad.fromJson(res);
  }

  static Future<Entidad> updateEntidad({
    required int id,
    required String denominacion,
    String? direccion,
    String? telefono,
    int? horasAnticipacionCancelacion,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .from('entidad')
        .update({
          'denominacion': denominacion,
          'direccion': direccion,
          'telefono': telefono,
          if (horasAnticipacionCancelacion != null)
            'horas_anticipacion_cancelacion': horasAnticipacionCancelacion,
        })
        .eq('id', id)
        .select()
        .single();
    return Entidad.fromJson(res);
  }

  static Future<void> deleteEntidad(int id) async {
    await _supabase.schema(_schema).from('entidad').delete().eq('id', id);
  }

  // ── Administradores ────────────────────────────────────────

  static Future<List<EntidadAdmin>> getAdmins(int idEntidad) async {
    final res = await _supabase
        .schema(_schema)
        .from('entidad_admin')
        .select()
        .eq('id_entidad', idEntidad)
        .order('created_at');
    return (res as List).map((e) => EntidadAdmin.fromJson(e)).toList();
  }

  static Future<EntidadAdmin> addAdmin({
    required int idEntidad,
    required String uuidUsuario,
    required String asignadoPor,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .from('entidad_admin')
        .insert({
          'id_entidad': idEntidad,
          'uuid_usuario': uuidUsuario,
          'asignado_por': asignadoPor,
        })
        .select()
        .single();
    return EntidadAdmin.fromJson(res);
  }

  static Future<void> removeAdmin(int idEntidadAdmin) async {
    await _supabase
        .schema(_schema)
        .from('entidad_admin')
        .delete()
        .eq('id', idEntidadAdmin);
  }

  static Future<bool> isAdmin(int idEntidad, String uuidUsuario) async {
    final res = await _supabase
        .schema(_schema)
        .from('entidad_admin')
        .select('id')
        .eq('id_entidad', idEntidad)
        .eq('uuid_usuario', uuidUsuario)
        .maybeSingle();
    return res != null;
  }
}

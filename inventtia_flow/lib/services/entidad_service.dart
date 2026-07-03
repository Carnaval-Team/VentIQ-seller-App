import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/entidad.dart';

class EntidadService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  /// Handle schema permission errors with user-friendly messages
  static Exception handleSchemaPermissionError(Exception e) {
    if (e.toString().contains('permission denied') || e.toString().contains('42501')) {
      return Exception(
        'ERROR DE PERMISOS DE BASE DE DATOS\n\n'
        'No se puede acceder al esquema "flow" de la base de datos.\n\n'
        'SOLUCIÓN:\n'
        '1. Ve al panel de Supabase > SQL Editor\n'
        '2. Ejecuta los siguientes comandos:\n\n'
        'GRANT USAGE ON SCHEMA flow TO authenticated;\n'
        'GRANT USAGE ON SCHEMA flow TO anon;\n'
        'GRANT ALL ON ALL TABLES IN SCHEMA flow TO authenticated;\n'
        'GRANT ALL ON ALL TABLES IN SCHEMA flow TO anon;\n'
        'GRANT ALL ON ALL SEQUENCES IN SCHEMA flow TO authenticated;\n'
        'GRANT ALL ON ALL SEQUENCES IN SCHEMA flow TO anon;\n\n'
        'Error original: ${e.toString()}'
      );
    }
    return e;
  }

  // ── Entidades ──────────────────────────────────────────────

  static Future<List<Entidad>> getEntidades() async {
    try {
      final res = await _supabase
          .schema(_schema)
          .from('entidad')
          .select()
          .order('denominacion');
      return (res as List).map((e) => Entidad.fromJson(e)).toList();
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
  }

  static Future<List<Entidad>> getMisEntidades(String uuidUsuario) async {
    try {
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
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
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
    final res = await _supabase.schema(_schema).rpc(
      'admin_listar_admins',
      params: {'p_id_entidad': idEntidad},
    );
    if (res == null) return [];
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

  // ── Vendedores ──────────────────────────────────────────────

  static Future<List<EntidadVendedor>> getVendedores(int idEntidad) async {
    final res = await _supabase.schema(_schema).rpc(
      'admin_listar_vendedores',
      params: {'p_id_entidad': idEntidad},
    );
    if (res == null) return [];
    return (res as List).map((e) => EntidadVendedor.fromJson(e)).toList();
  }

  static Future<EntidadVendedor> addVendedor({
    required int idEntidad,
    required String uuidUsuario,
    required String asignadoPor,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .from('entidad_vendedor')
        .insert({
          'id_entidad': idEntidad,
          'uuid_usuario': uuidUsuario,
          'asignado_por': asignadoPor,
        })
        .select()
        .single();
    return EntidadVendedor.fromJson(res);
  }

  static Future<void> removeVendedor(int idEntidadVendedor) async {
    await _supabase
        .schema(_schema)
        .from('entidad_vendedor')
        .delete()
        .eq('id', idEntidadVendedor);
  }

  static Future<bool> isVendedor(int idEntidad, String uuidUsuario) async {
    final res = await _supabase
        .schema(_schema)
        .from('entidad_vendedor')
        .select('id')
        .eq('id_entidad', idEntidad)
        .eq('uuid_usuario', uuidUsuario)
        .maybeSingle();
    return res != null;
  }

  static Future<List<Entidad>> getMisEntidadesComoVendedor(
      String uuidUsuario) async {
    final rows = await _supabase
        .schema(_schema)
        .from('entidad_vendedor')
        .select('id_entidad, entidad(*)')
        .eq('uuid_usuario', uuidUsuario);

    final List<Entidad> result = [];
    for (final row in rows as List) {
      if (row['entidad'] != null) {
        result.add(Entidad.fromJson(row['entidad'] as Map<String, dynamic>));
      }
    }
    result.sort((a, b) => a.denominacion.compareTo(b.denominacion));
    return result;
  }
}

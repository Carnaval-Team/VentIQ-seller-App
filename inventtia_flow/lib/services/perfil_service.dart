import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/perfil.dart';

class PerfilService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';
  static const String _table = 'perfil';

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

  static Future<Perfil?> getPerfil(String uuidUsuario) async {
    try {
      final res = await _supabase
          .schema(_schema)
          .from(_table)
          .select()
          .eq('uuid_usuario', uuidUsuario)
          .maybeSingle();
      return res != null ? Perfil.fromJson(res) : null;
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
  }

  static Future<Perfil> createPerfil({
    required String uuidUsuario,
    required String nombre,
    required String apellidos,
    required String ci,
    String? telefono,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .from(_table)
        .insert({
          'uuid_usuario': uuidUsuario,
          'nombre': nombre,
          'apellidos': apellidos,
          'ci': ci,
          'telefono': telefono,
        })
        .select()
        .single();
    return Perfil.fromJson(res);
  }

  static Future<Perfil> updatePerfil({
    required String uuidUsuario,
    required String nombre,
    required String apellidos,
    required String ci,
    String? telefono,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .from(_table)
        .update({
          'nombre': nombre,
          'apellidos': apellidos,
          'ci': ci,
          'telefono': telefono,
        })
        .eq('uuid_usuario', uuidUsuario)
        .select()
        .single();
    return Perfil.fromJson(res);
  }

  static Future<String?> getUuidByEmail(String email) async {
    final res = await _supabase
        .rpc('get_uuid_by_email', params: {'p_email': email.toLowerCase().trim()});
    print('[flow] getUuidByEmail → res=$res (${res?.runtimeType})');
    if (res == null) return null;
    return res.toString();
  }

  static Future<Perfil?> getPerfilByEmail(String email) async {
    final uuid = await getUuidByEmail(email);
    if (uuid == null) return null;
    return getPerfil(uuid);
  }

  static Future<Perfil?> getPerfilByCi(String ci) async {
    final res = await _supabase
        .schema(_schema)
        .from(_table)
        .select()
        .eq('ci', ci)
        .maybeSingle();
    return res != null ? Perfil.fromJson(res) : null;
  }

  static Future<bool> existeCi(String ci, {String? excludeUuid}) async {
    var query = _supabase
        .schema(_schema)
        .from(_table)
        .select('id')
        .eq('ci', ci);
    final res = await query;
    if (excludeUuid != null) {
      return (res as List).any((r) => r['uuid_usuario'] != excludeUuid);
    }
    return (res as List).isNotEmpty;
  }
}

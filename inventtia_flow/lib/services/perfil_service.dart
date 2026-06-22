import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/perfil.dart';

class PerfilService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';
  static const String _table = 'perfil';

  static Future<Perfil?> getPerfil(String uuidUsuario) async {
    final res = await _supabase
        .schema(_schema)
        .from(_table)
        .select()
        .eq('uuid_usuario', uuidUsuario)
        .maybeSingle();
    return res != null ? Perfil.fromJson(res) : null;
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

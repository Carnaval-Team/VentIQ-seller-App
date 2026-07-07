import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/notificacion.dart';

class NotificacionService {
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

  /// Mis notificaciones, mas recientes primero.
  static Future<List<Notificacion>> getMisNotificaciones(
    String uuidUsuario, {
    int limit = 100,
  }) async {
    try {
      final res = await _supabase
          .schema(_schema)
          .from('notificaciones')
          .select()
          .eq('uuid_usuario', uuidUsuario)
          .order('id', ascending: false)
          .limit(limit);
      return (res as List)
          .map((e) => Notificacion.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
  }

  /// Cantidad de no leidas (para el badge).
  static Future<int> contarNoLeidas(String uuidUsuario) async {
    try {
      final res = await _supabase
          .schema(_schema)
          .from('notificaciones')
          .count(CountOption.exact)
          .eq('uuid_usuario', uuidUsuario)
          .eq('leida', false);
      return res;
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
  }

  /// Crea una notificacion para un usuario.
  static Future<void> crearNotificacion({
    required String uuidUsuario,
    required String tipo,
    required String titulo,
    required String mensaje,
    int? idLocalServicio,
    int? idReferencia,
    Map<String, dynamic>? data,
  }) async {
    try {
      await _supabase.schema(_schema).from('notificaciones').insert({
        'uuid_usuario': uuidUsuario,
        'tipo': tipo,
        'titulo': titulo,
        'mensaje': mensaje,
        'leida': false,
        if (idLocalServicio != null) 'id_local_servicio': idLocalServicio,
        if (idReferencia != null) 'id_referencia': idReferencia,
        if (data != null) 'data': data,
      });
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
  }

  /// Marca una notificacion como leida.
  static Future<void> marcarLeida(int id) async {
    await _supabase.schema(_schema).from('notificaciones').update({
      'leida': true,
      'leida_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  /// Marca todas las del usuario como leidas.
  static Future<void> marcarTodasLeidas(String uuidUsuario) async {
    await _supabase
        .schema(_schema)
        .from('notificaciones')
        .update({
          'leida': true,
          'leida_at': DateTime.now().toIso8601String(),
        })
        .eq('uuid_usuario', uuidUsuario)
        .eq('leida', false);
  }

  /// Stream en tiempo real de las notificaciones del usuario.
  /// Requiere que flow.notificaciones este en la publicacion supabase_realtime
  /// (migracion 07_realtime_notificaciones.sql).
  static Stream<List<Notificacion>> watch(String uuidUsuario) {
    return _supabase
        .schema(_schema)
        .from('notificaciones')
        .stream(primaryKey: ['id'])
        .eq('uuid_usuario', uuidUsuario)
        .order('id',ascending:false)
        .map((rows) =>
            rows.map((e) => Notificacion.fromJson(e)).toList());
  }
}

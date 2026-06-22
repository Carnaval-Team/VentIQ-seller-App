import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/notificacion.dart';

class NotificacionService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  /// Mis notificaciones, mas recientes primero.
  static Future<List<Notificacion>> getMisNotificaciones(
    String uuidUsuario, {
    int limit = 100,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .from('notificaciones')
        .select()
        .eq('uuid_usuario', uuidUsuario)
        .order('created_at', ascending: false)
        .limit(limit);
    return (res as List)
        .map((e) => Notificacion.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Cantidad de no leidas (para el badge).
  static Future<int> contarNoLeidas(String uuidUsuario) async {
    final res = await _supabase
        .schema(_schema)
        .from('notificaciones')
        .count(CountOption.exact)
        .eq('uuid_usuario', uuidUsuario)
        .eq('leida', false);
    return res;
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
        .order('created_at')
        .map((rows) =>
            rows.map((e) => Notificacion.fromJson(e)).toList());
  }
}

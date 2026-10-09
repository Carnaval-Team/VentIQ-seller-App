import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/coleccion.dart';

/// Operaciones sobre `flow.coleccion` (colecciones temáticas del Home).
///
/// Todas las escrituras son RPC que exigen `nivel_acceso = 1` en
/// `public.app_dat_superadmin`, comprobado en el servidor con `auth.uid()`. La
/// app no decide permisos: solo los refleja.
///
/// El esquema es `flow`, no `carnavalapp`: las colecciones las consume el Home
/// de `inventtia_flow`, y ambas apps apuntan al **mismo** proyecto Supabase.
class ColeccionService {
  static final _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  /// Listado completo para el panel (incluye las apagadas).
  ///
  /// Lanza si la migración `30_colecciones.sql` no está aplicada: es mejor un
  /// error claro que una lista vacía que parezca "no hay colecciones".
  static Future<List<Coleccion>> listar({required String uuidUsuario}) async {
    final res = await _supabase
        .schema(_schema)
        .rpc('admin_listar_colecciones', params: {'p_uuid_usuario': uuidUsuario});
    if (res is! Map) return const [];
    final json = Map<String, dynamic>.from(res);
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudieron leer las colecciones');
    }
    final lista = json['data'];
    if (lista is! List) return const [];
    return lista
        .whereType<Map>()
        .map((e) => Coleccion.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Alta (`id` nulo) o edición. `servicios` **reemplaza** el conjunto completo:
  /// el orden de la lista es el que se guarda.
  static Future<int> guardar({
    required String uuidUsuario,
    required String titulo,
    String? subtitulo,
    String? icono,
    String? colorInicio,
    String? colorFin,
    int orden = 0,
    bool activo = true,
    DateTime? desde,
    DateTime? hasta,
    List<int> servicios = const <int>[],
    int? id,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_guardar_coleccion',
          params: {
            'p_uuid_usuario': uuidUsuario,
            'p_titulo': titulo,
            if (subtitulo != null) 'p_subtitulo': subtitulo,
            if (icono != null) 'p_icono': icono,
            if (colorInicio != null) 'p_color_inicio': colorInicio,
            if (colorFin != null) 'p_color_fin': colorFin,
            'p_orden': orden,
            'p_activo': activo,
            if (desde != null) 'p_desde': desde.toUtc().toIso8601String(),
            if (hasta != null) 'p_hasta': hasta.toUtc().toIso8601String(),
            'p_servicios': servicios,
            if (id != null) 'p_id': id,
          },
        );
    final json = res is Map ? Map<String, dynamic>.from(res) : const {};
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo guardar la colección');
    }
    return ((json['data'] as Map<String, dynamic>)['id'] as num).toInt();
  }

  static Future<void> alternar({
    required String uuidUsuario,
    required int id,
    required bool activo,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_alternar_coleccion',
          params: {
            'p_uuid_usuario': uuidUsuario,
            'p_id': id,
            'p_activo': activo,
          },
        );
    final json = res is Map ? Map<String, dynamic>.from(res) : const {};
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo cambiar el estado');
    }
  }

  static Future<void> eliminar({
    required String uuidUsuario,
    required int id,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_eliminar_coleccion',
          params: {'p_uuid_usuario': uuidUsuario, 'p_id': id},
        );
    final json = res is Map ? Map<String, dynamic>.from(res) : const {};
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo eliminar la colección');
    }
  }
}

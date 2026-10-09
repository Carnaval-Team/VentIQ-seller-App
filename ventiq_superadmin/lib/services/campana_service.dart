import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/campana.dart';
import 'catalogo_destinos_service.dart';

/// Operaciones sobre `flow.campana` (campañas patrocinadas del Home).
///
/// Todas las escrituras son RPC `security invoker` que exigen
/// `nivel_acceso = 1` en `public.app_dat_superadmin`, comprobado en el servidor
/// con `auth.uid()`. La app no decide permisos: solo los refleja.
///
/// El esquema es `flow`, no `carnavalapp`: las campañas las consume el Home de
/// `inventtia_flow`, y ambas apps apuntan al **mismo** proyecto Supabase.
class CampanaService {
  static final _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  /// Listado completo para el panel.
  ///
  /// Lanza si la migración `28_patrocinados.sql` no está aplicada: es mejor un
  /// error claro que una lista vacía que parezca "no hay campañas".
  static Future<List<Campana>> listar({required String uuidUsuario}) async {
    final res = await _supabase
        .schema(_schema)
        .rpc('admin_listar_campanas', params: {'p_uuid_usuario': uuidUsuario});
    if (res is! Map) return const [];
    final json = Map<String, dynamic>.from(res);
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudieron leer las campañas');
    }
    final lista = json['data'];
    if (lista is! List) return const [];
    return lista
        .whereType<Map>()
        .map((e) => Campana.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<int> guardar({
    required String uuidUsuario,
    required String titulo,
    int? idLocalServicio,
    int? idEntidad,
    String? subtitulo,
    String? descripcion,
    String? colorInicio,
    String? colorFin,
    String? icono,
    String? imageUrl,
    DateTime? desde,
    DateTime? hasta,
    int prioridad = 0,
    bool activo = true,
    int? id,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_guardar_campana',
          params: {
            'p_uuid_usuario': uuidUsuario,
            'p_titulo': titulo,
            if (idLocalServicio != null)
              'p_id_local_servicio': idLocalServicio,
            if (idEntidad != null) 'p_id_entidad': idEntidad,
            if (subtitulo != null) 'p_subtitulo': subtitulo,
            if (descripcion != null) 'p_descripcion': descripcion,
            if (colorInicio != null) 'p_color_inicio': colorInicio,
            if (colorFin != null) 'p_color_fin': colorFin,
            if (icono != null) 'p_icono': icono,
            if (imageUrl != null) 'p_image_url': imageUrl,
            if (desde != null) 'p_desde': desde.toUtc().toIso8601String(),
            if (hasta != null) 'p_hasta': hasta.toUtc().toIso8601String(),
            'p_prioridad': prioridad,
            'p_activo': activo,
            if (id != null) 'p_id': id,
          },
        );
    final json = res is Map ? Map<String, dynamic>.from(res) : const {};
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo guardar la campaña');
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
          'admin_alternar_campana',
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
          'admin_eliminar_campana',
          params: {'p_uuid_usuario': uuidUsuario, 'p_id': id},
        );
    final json = res is Map ? Map<String, dynamic>.from(res) : const {};
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo eliminar la campaña');
    }
  }

  /// Servicios disponibles para elegir el destino de la campaña.
  ///
  /// Delega en [CatalogoDestinosService]: el catálogo lo comparten los
  /// patrocinados y las colecciones temáticas, así que se lee en un solo sitio.
  static Future<List<({int id, String etiqueta})>> destinosServicio() =>
      CatalogoDestinosService.servicios();
}
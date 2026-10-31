import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/precio_config.dart';

/// Lectura y escritura de la configuración de precios automáticos de una
/// entidad (`flow.precio_config`, migración 60).
///
/// Envuelve las RPC `flow.admin_precio_config_get/set`. La escritura va por RPC
/// porque la tabla tiene RLS de sólo lectura para el admin (el criterio del
/// esquema: leer por política, escribir por RPC `security definer`).
class PrecioConfigService {
  PrecioConfigService._();

  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  /// Configuración de la entidad. Lanza si la RPC no está aplicada o el
  /// usuario no tiene permisos sobre la entidad.
  static Future<PrecioConfig> get(int idEntidad) async {
    final res = await _supabase
        .schema(_schema)
        .rpc('admin_precio_config_get', params: {'p_id_entidad': idEntidad});
    final json = _mapa(res);
    if (json == null) {
      throw Exception('Respuesta inesperada al leer la configuración de precios');
    }
    if (json['ok'] != true) {
      throw Exception(
        json['error']?.toString() ??
            'No se pudo leer la configuración de precios',
      );
    }
    return PrecioConfig.fromJson(_mapa(json['data']));
  }

  /// Guarda [config] y devuelve lo que quedó guardado en la base.
  static Future<PrecioConfig> set({
    required int idEntidad,
    required PrecioConfig config,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_precio_config_set',
          params: {
            'p_id_entidad': idEntidad,
            'p_auto_activo': config.autoActivo,
            'p_moneda_origen': config.monedaOrigen,
            'p_redondeo_cup': config.redondeoCup,
            'p_redondeo_divisa': config.redondeoDivisa,
          },
        );
    final json = _mapa(res);
    if (json == null) {
      throw Exception('Respuesta inesperada al guardar la configuración de precios');
    }
    if (json['ok'] != true) {
      throw Exception(
        json['error']?.toString() ??
            'No se pudo guardar la configuración de precios',
      );
    }
    return PrecioConfig.fromJson(_mapa(json['data']));
  }

  /// Igual que [get], pero devuelve la configuración por defecto si falla.
  ///
  /// La usan las pantallas que no pueden bloquearse porque la migración 60
  /// todavía no esté aplicada: con los valores por defecto (`auto_activo=true`,
  /// `USD`, CUP 0, divisas 2) el formulario sigue funcionando.
  static Future<PrecioConfig> getSeguro(int idEntidad) async {
    try {
      return await get(idEntidad);
    } catch (e) {
      debugPrint('[flow] PrecioConfigService.getSeguro($idEntidad): $e');
      return const PrecioConfig();
    }
  }

  /// Configuración de precios de la entidad dueña de un servicio.
  ///
  /// La usan pantallas que sólo conocen el servicio (el formulario de turno),
  /// no la entidad. Si no se puede resolver, devuelve la configuración por
  /// defecto: nunca lanza.
  static Future<PrecioConfig> paraServicio(int idServicio) async {
    try {
      final fila = await _supabase
          .schema(_schema)
          .from('app_dat_servicios')
          .select('id_entidad')
          .eq('id', idServicio)
          .maybeSingle();
      final idEntidad = (fila?['id_entidad'] as num?)?.toInt();
      if (idEntidad == null) return const PrecioConfig();
      return await getSeguro(idEntidad);
    } catch (e) {
      debugPrint('[flow] PrecioConfigService.paraServicio($idServicio): $e');
      return const PrecioConfig();
    }
  }

  static Map<String, dynamic>? _mapa(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return {for (final e in raw.entries) e.key.toString(): e.value};
    }
    return null;
  }
}
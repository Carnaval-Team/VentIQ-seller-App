import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Error de negocio del módulo de tarifas.
///
/// Siempre trae un mensaje en español listo para mostrarse en un SnackBar o en
/// una tarjeta de error; nunca expone el JSON crudo de PostgREST.
class MueveteTarifasException implements Exception {
  final String mensaje;

  const MueveteTarifasException(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Servicio de configuración tarifaria del taxi (H6, primera mitad).
///
/// Todo el acceso va por el esquema `muevete`; la escritura depende de las
/// políticas RLS `superadmin_all_*` (lectura abierta a `authenticated`).
class MueveteTarifasService {
  static final _supabase = Supabase.instance.client;

  // ─── Constantes del modelo ────────────────────────────────────────────

  /// Modos de tarifa admitidos por el `CHECK` de `zonas_tarifa`/`tarifas_municipio`.
  static const List<String> modosTarifa = ['fijo', 'fijo_mas_km', 'por_km'];

  /// Valores admitidos por `configuracion_tarifas_redondeo_chk`.
  static const List<int> redondeosPermitidos = [0, 5, 25, 50, 100];

  /// Rango del `CHECK` de `vehicle_type.multiplicador_tarifa`.
  static const double multiplicadorMin = 0.1;
  static const double multiplicadorMax = 5.0;

  /// Centro de Santa Clara (punto de partida del simulador).
  static const double santaClaraLat = 22.40689;
  static const double santaClaraLon = -79.96450;

  static const String provinciaPorDefecto = 'Villa Clara';
  static const String municipioPorDefecto = 'Santa Clara';

  // ─── Zonas de tarifa ──────────────────────────────────────────────────

  /// Lista las zonas ordenadas por prioridad (mayor gana) y nombre.
  static Future<List<Map<String, dynamic>>> listarZonas({
    bool soloActivas = false,
  }) {
    return _guard('No se pudieron cargar las zonas de tarifa', () async {
      var query = _supabase.schema('muevete').from('zonas_tarifa').select();
      if (soloActivas) {
        query = query.eq('activo', true);
      }
      final rows = await query
          .order('prioridad', ascending: false)
          .order('nombre', ascending: true);
      return List<Map<String, dynamic>>.from(rows);
    });
  }

  /// Crea una zona y devuelve la fila creada.
  static Future<Map<String, dynamic>> crearZona(Map<String, dynamic> zona) {
    _validarZona(zona, exigirCompleta: true);
    return _guard('No se pudo crear la zona', () async {
      final row =
          await _supabase
              .schema('muevete')
              .from('zonas_tarifa')
              .insert(zona)
              .select()
              .single();
      return Map<String, dynamic>.from(row);
    });
  }

  /// Actualiza los campos indicados de una zona.
  static Future<void> actualizarZona(int id, Map<String, dynamic> cambios) {
    _validarZona(cambios);
    return _guard('No se pudo actualizar la zona', () async {
      final rows = await _supabase
          .schema('muevete')
          .from('zonas_tarifa')
          .update(cambios)
          .eq('id', id)
          .select('id');
      if ((rows as List).isEmpty) {
        throw const MueveteTarifasException(
          'La zona ya no existe o no tienes permisos para editarla.',
        );
      }
    });
  }

  /// Borrado lógico: la zona queda `activo = false` y deja de cotizar, pero
  /// conserva el historial de viajes que la referencian.
  static Future<void> eliminarZona(int id) {
    return toggleZona(id, false);
  }

  /// Activa o desactiva una zona.
  static Future<void> toggleZona(int id, bool activo) {
    return _guard(
      activo ? 'No se pudo activar la zona' : 'No se pudo desactivar la zona',
      () async {
        final rows = await _supabase
            .schema('muevete')
            .from('zonas_tarifa')
            .update({'activo': activo})
            .eq('id', id)
            .select('id');
        if ((rows as List).isEmpty) {
          throw const MueveteTarifasException(
            'La zona ya no existe o no tienes permisos para cambiarla.',
          );
        }
      },
    );
  }

  // ─── Tarifas municipales (fallback D4) ───────────────────────────────

  /// Lista las tarifas municipales de respaldo.
  static Future<List<Map<String, dynamic>>> listarMunicipios() {
    return _guard('No se pudieron cargar las tarifas municipales', () async {
      final rows = await _supabase
          .schema('muevete')
          .from('tarifas_municipio')
          .select()
          .order('provincia', ascending: true)
          .order('municipio', ascending: true);
      return List<Map<String, dynamic>>.from(rows);
    });
  }

  /// Crea o actualiza una tarifa municipal (clave `provincia + municipio`).
  ///
  /// Envía la fila sin `id` para que el upsert caiga siempre en la restricción
  /// `tarifas_municipio_unq` y no en la clave primaria.
  static Future<void> guardarMunicipio(Map<String, dynamic> tarifa) {
    final provincia = (tarifa['provincia'] as String?)?.trim() ?? '';
    final municipio = (tarifa['municipio'] as String?)?.trim() ?? '';
    if (provincia.isEmpty || municipio.isEmpty) {
      throw const MueveteTarifasException(
        'La provincia y el municipio son obligatorios.',
      );
    }

    final modo = (tarifa['modo'] as String?) ?? 'fijo';
    if (!modosTarifa.contains(modo)) {
      throw const MueveteTarifasException(
        'El modo de tarifa debe ser fijo, fijo_mas_km o por_km.',
      );
    }

    final montoFijo = _toDouble(tarifa['monto_fijo']);
    final precioKm = _toDouble(tarifa['precio_km']);
    if (montoFijo == null || montoFijo < 0) {
      throw const MueveteTarifasException(
        'El monto fijo debe ser un número mayor o igual a 0.',
      );
    }
    if (precioKm == null || precioKm < 0) {
      throw const MueveteTarifasException(
        'El precio por km debe ser un número mayor o igual a 0.',
      );
    }
    if (modo == 'por_km' && precioKm <= 0) {
      throw const MueveteTarifasException(
        'El modo "por km" exige un precio por km mayor que 0.',
      );
    }

    final payload = <String, dynamic>{
      'provincia': provincia,
      'municipio': municipio,
      'modo': modo,
      'monto_fijo': montoFijo,
      'precio_km': precioKm,
      'activo': tarifa['activo'] ?? true,
    };

    return _guard('No se pudo guardar la tarifa municipal', () async {
      await _supabase
          .schema('muevete')
          .from('tarifas_municipio')
          .upsert(payload, onConflict: 'provincia,municipio');
    });
  }

  // ─── Configuración global (singleton id = 1) ─────────────────────────

  /// Devuelve la fila única de `configuracion_tarifas`.
  static Future<Map<String, dynamic>> configuracion() {
    return _guard('No se pudo cargar la configuración tarifaria', () async {
      final row =
          await _supabase
              .schema('muevete')
              .from('configuracion_tarifas')
              .select()
              .eq('id', 1)
              .maybeSingle();
      if (row == null) {
        throw const MueveteTarifasException(
          'No existe la fila de configuración tarifaria (id = 1). '
          'Aplica el seed de tarifas antes de configurar.',
        );
      }
      return Map<String, dynamic>.from(row);
    });
  }

  /// Guarda los parámetros globales. `updated_at` lo pone el trigger.
  static Future<void> actualizarConfiguracion(Map<String, dynamic> cambios) {
    _validarConfiguracion(cambios);
    return _guard('No se pudo guardar la configuración tarifaria', () async {
      final rows = await _supabase
          .schema('muevete')
          .from('configuracion_tarifas')
          .update(cambios)
          .eq('id', 1)
          .select('id');
      if ((rows as List).isEmpty) {
        throw const MueveteTarifasException(
          'No tienes permisos de superadministrador para editar las tarifas.',
        );
      }
    });
  }

  // ─── Tipos de vehículo ───────────────────────────────────────────────

  /// Tipos de vehículo ordenados por `orden`.
  ///
  /// Por defecto sólo los activos (`status = true`): son los únicos que el
  /// simulador puede cotizar y los únicos editables.
  static Future<List<Map<String, dynamic>>> listarTiposVehiculo({
    bool soloActivos = true,
  }) {
    return _guard('No se pudieron cargar los tipos de vehículo', () async {
      var query = _supabase
          .schema('muevete')
          .from('vehicle_type')
          .select(
            'id, tipo, nombre_ui, orden, pasajeros_max, '
            'multiplicador_tarifa, status, categoria',
          );
      if (soloActivos) {
        query = query.eq('status', true);
      }
      final rows = await query.order('orden', ascending: true).order('id');
      return List<Map<String, dynamic>>.from(rows);
    });
  }

  /// Actualiza el multiplicador de un tipo activo.
  static Future<void> actualizarMultiplicador(int id, double mult) {
    if (mult < multiplicadorMin || mult > multiplicadorMax) {
      throw const MueveteTarifasException(
        'El multiplicador debe estar entre 0.10 y 5.00.',
      );
    }
    return _guard('No se pudo actualizar el multiplicador', () async {
      final rows = await _supabase
          .schema('muevete')
          .from('vehicle_type')
          .update({'multiplicador_tarifa': mult})
          .eq('id', id)
          .eq('status', true)
          .select('id');
      if ((rows as List).isEmpty) {
        throw const MueveteTarifasException(
          'El tipo de vehículo no existe o está inactivo.',
        );
      }
    });
  }

  /// Actualiza el orden de aparición de un tipo activo.
  static Future<void> actualizarOrden(int id, int orden) {
    if (orden < 0) {
      throw const MueveteTarifasException(
        'El orden debe ser un número entero mayor o igual a 0.',
      );
    }
    return _guard('No se pudo actualizar el orden', () async {
      final rows = await _supabase
          .schema('muevete')
          .from('vehicle_type')
          .update({'orden': orden})
          .eq('id', id)
          .eq('status', true)
          .select('id');
      if ((rows as List).isEmpty) {
        throw const MueveteTarifasException(
          'El tipo de vehículo no existe o está inactivo.',
        );
      }
    });
  }

  // ─── Simulador (RPC fn_cotizar_viaje) ────────────────────────────────

  /// Cotiza un viaje con la misma función que usa la app del cliente, así que
  /// el número del simulador es exactamente el que se cobraría.
  ///
  /// `fn_cotizar_viaje` vive en el esquema `muevete`, por eso el RPC se llama
  /// sobre `schema('muevete')`.
  static Future<Map<String, dynamic>> simular({
    required double latOrigen,
    required double lonOrigen,
    required double latDestino,
    required double lonDestino,
    required int idTipo,
    double? km,
    String? provincia,
    String? municipio,
    DateTime? at,
  }) {
    if (latOrigen.abs() > 90 || latDestino.abs() > 90) {
      throw const MueveteTarifasException(
        'La latitud debe estar entre -90 y 90.',
      );
    }
    if (lonOrigen.abs() > 180 || lonDestino.abs() > 180) {
      throw const MueveteTarifasException(
        'La longitud debe estar entre -180 y 180.',
      );
    }
    if (idTipo <= 0) {
      throw const MueveteTarifasException(
        'Selecciona un tipo de vehículo para simular.',
      );
    }
    if (km != null && km < 0) {
      throw const MueveteTarifasException(
        'Los kilómetros no pueden ser negativos.',
      );
    }

    return _guard('No se pudo simular la cotización', () async {
      final params = <String, dynamic>{
        'p_lat_o': latOrigen,
        'p_lon_o': lonOrigen,
        'p_lat_d': latDestino,
        'p_lon_d': lonDestino,
        'p_id_tipo': idTipo,
        'p_km': km,
        'p_provincia': _vacioANull(provincia),
        'p_municipio': _vacioANull(municipio),
      };
      // Sólo se envía `p_at` cuando el negocio quiere probar el nocturno: si se
      // manda null, se pisa el DEFAULT now() de la función.
      if (at != null) {
        params['p_at'] = at.toUtc().toIso8601String();
      }

      final res = await _supabase
          .schema('muevete')
          .rpc('fn_cotizar_viaje', params: params);
      if (res is! Map) {
        throw const MueveteTarifasException(
          'La cotización devolvió un formato inesperado.',
        );
      }
      return Map<String, dynamic>.from(res);
    });
  }

  // ─── Validaciones locales (además de los CHECK de la BD) ─────────────

  static void _validarZona(
    Map<String, dynamic> zona, {
    bool exigirCompleta = false,
  }) {
    if (exigirCompleta) {
      final nombre = (zona['nombre'] as String?)?.trim() ?? '';
      if (nombre.isEmpty) {
        throw const MueveteTarifasException(
          'El nombre de la zona es obligatorio.',
        );
      }
      if (zona['geometria'] == null) {
        throw const MueveteTarifasException(
          'La zona necesita una geometría (polígono GeoJSON).',
        );
      }
      if (zona['modo'] == null) {
        throw const MueveteTarifasException('Selecciona el modo de tarifa.');
      }
    }

    final modo = zona['modo'] as String?;
    if (modo != null) {
      if (!modosTarifa.contains(modo)) {
        throw const MueveteTarifasException(
          'El modo de tarifa debe ser fijo, fijo_mas_km o por_km.',
        );
      }
      final montoFijo = _toDouble(zona['monto_fijo']);
      final precioKm = _toDouble(zona['precio_km']);
      if (modo != 'por_km' && (montoFijo == null || montoFijo < 0)) {
        throw const MueveteTarifasException(
          'El modo elegido exige un monto fijo mayor o igual a 0.',
        );
      }
      if (modo != 'fijo' && (precioKm == null || precioKm < 0)) {
        throw const MueveteTarifasException(
          'El modo elegido exige un precio por km mayor o igual a 0.',
        );
      }
    } else {
      final montoFijo = _toDouble(zona['monto_fijo']);
      if (zona.containsKey('monto_fijo') &&
          (montoFijo == null || montoFijo < 0)) {
        throw const MueveteTarifasException(
          'El monto fijo debe ser un número mayor o igual a 0.',
        );
      }
      final precioKm = _toDouble(zona['precio_km']);
      if (zona.containsKey('precio_km') && (precioKm == null || precioKm < 0)) {
        throw const MueveteTarifasException(
          'El precio por km debe ser un número mayor o igual a 0.',
        );
      }
    }

    final prioridad = zona['prioridad'];
    if (prioridad != null && _toInt(prioridad) == null) {
      throw const MueveteTarifasException(
        'La prioridad debe ser un número entero.',
      );
    }
  }

  static void _validarConfiguracion(Map<String, dynamic> c) {
    void rango(String clave, num min, num max, String etiqueta) {
      if (!c.containsKey(clave)) return;
      final v = _toDouble(c[clave]);
      if (v == null || v < min || v > max) {
        throw MueveteTarifasException(
          '$etiqueta debe ser un número entre $min y $max.',
        );
      }
    }

    rango('comision_pct', 0, 30, 'La comisión');
    rango('recarga_pct', 0, 50, 'El recargo de recarga');
    rango('limite_deuda_efectivo', 0, 5000, 'El límite de deuda');
    rango('recargo_nocturno_pct', 0, 50, 'El recargo nocturno');
    rango(
      'descuento_pago_wallet_pct',
      0,
      100,
      'El descuento por pago con wallet',
    );
    rango(
      'monto_fijo_fallback_municipio',
      0,
      20000,
      'El monto fijo de respaldo',
    );
    rango('precio_km_fallback', 0, 5000, 'El precio por km de respaldo');
    rango('umbral_km_corto', 0, 999, 'El umbral de viaje corto');

    if (c.containsKey('redondeo_cup')) {
      final redondeo = _toInt(c['redondeo_cup']);
      if (redondeo == null || !redondeosPermitidos.contains(redondeo)) {
        throw MueveteTarifasException(
          'El redondeo debe ser uno de: ${redondeosPermitidos.join(', ')}.',
        );
      }
    }

    if (c.containsKey('gracia_espera_min')) {
      final gracia = _toInt(c['gracia_espera_min']);
      if (gracia == null || gracia < 0 || gracia > 30) {
        throw const MueveteTarifasException(
          'La gracia de espera debe ser un entero entre 0 y 30 minutos.',
        );
      }
    }

    if (c.containsKey('dias_max_deuda')) {
      final dias = _toInt(c['dias_max_deuda']);
      if (dias == null || dias < 0) {
        throw const MueveteTarifasException(
          'Los días máximos de deuda deben ser un entero mayor o igual a 0.',
        );
      }
    }
  }

  // ─── Infraestructura de errores / conversiones ───────────────────────

  /// Ejecuta una operación y traduce cualquier fallo a un mensaje en español.
  static Future<T> _guard<T>(String accion, Future<T> Function() cuerpo) async {
    try {
      return await cuerpo();
    } on MueveteTarifasException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint(
        '[MueveteTarifasService] $accion · code=${e.code} message=${e.message}',
      );
      throw MueveteTarifasException('$accion: ${_detallePostgrest(e)}.');
    } on AuthException catch (e) {
      debugPrint('[MueveteTarifasService] $accion · auth=${e.message}');
      throw MueveteTarifasException(
        '$accion: la sesión expiró o no es válida. Vuelve a iniciar sesión.',
      );
    } catch (e) {
      debugPrint('[MueveteTarifasService] $accion · $e');
      throw MueveteTarifasException('$accion: $e');
    }
  }

  static String _detallePostgrest(PostgrestException e) {
    switch (e.code) {
      case '42501':
        return 'no tienes permisos de superadministrador';
      case '23505':
        return 'ya existe un registro con esos valores';
      case '23514':
        return 'los valores están fuera del rango permitido por la base de datos';
      case '23503':
        return 'hay registros relacionados que impiden la operación';
      case '23502':
        return 'falta un campo obligatorio';
      case '22007':
      case '22008':
        return 'el formato de fecha u hora no es válido';
      case 'PGRST116':
        return 'no se encontró el registro esperado';
      case 'PGRST202':
        return 'la función no existe con esa firma en la base de datos';
      case '42P01':
        return 'la tabla no existe en el esquema muevete';
      default:
        return e.message;
    }
  }

  static double? _toDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.'));
  }

  static int? _toInt(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static String? _vacioANull(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}

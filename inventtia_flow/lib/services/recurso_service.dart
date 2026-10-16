import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/recurso.dart';

/// Resumen que devuelve `admin_config_modo_gestion` tras activar/desactivar los
/// modos simplificados. Se usa para avisar al admin de lo que el sistema hizo
/// por él ("se creó 1 recurso oculto y 3 tramos").
class ModoGestionResultado {
  const ModoGestionResultado({
    required this.soloTurnos,
    required this.sinTramos,
    required this.recursoCreado,
    required this.tramosCreados,
  });

  final bool soloTurnos;
  final bool sinTramos;
  final bool recursoCreado;
  final int tramosCreados;
}

/// Resultado de `guardarTurnoAuto`, con el recurso en el que quedó el turno.
class TurnoAutoResultado {
  const TurnoAutoResultado({
    required this.id,
    this.idRecurso,
    this.ignoroRecursoElegido = false,
  });

  /// Id del turno creado o editado.
  final int id;

  /// Recurso en el que quedó el turno (lo devuelve la RPC).
  final int? idRecurso;

  /// `true` si se pidió un recurso concreto y la base lo ignoró porque todavía
  /// no tiene aplicada la migración 52.
  final bool ignoroRecursoElegido;
}

/// CRUD de recursos / tramos / turnos de un local_servicio.
/// Envuelve las RPCs admin flow.admin_*_recurso / _tramo / _turno
/// (ver docs/flow_schema/rpc admin/25_admin_recursos.sql).
class RecursoService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  /// Lista los recursos del local_servicio con sus tramos y turnos anidados.
  static Future<List<Recurso>> listar({
    required String uuidUsuario,
    required int idLocalServicio,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_listar_recursos',
          params: {
            'p_uuid_usuario': uuidUsuario,
            'p_id_local_servicio': idLocalServicio,
          },
        );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudieron listar los recursos');
    }
    final data = (json['data'] as List?) ?? const [];
    return data
        .map((e) => Recurso.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Recurso ──────────────────────────────────────────────────────────────

  /// Crea (id == null) o actualiza un recurso. Devuelve su id.
  static Future<int> guardarRecurso({
    required String uuidUsuario,
    required int idLocalServicio,
    required String nombre,
    int capacidad = 1,
    int orden = 0,
    bool activo = true,
    int? id,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_guardar_recurso',
          params: {
            'p_uuid_usuario': uuidUsuario,
            'p_id_local_servicio': idLocalServicio,
            'p_nombre': nombre,
            'p_capacidad': capacidad,
            'p_orden': orden,
            'p_activo': activo,
            'p_id': id,
          },
        );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo guardar el recurso');
    }
    return (json['id'] as num).toInt();
  }

  static Future<void> eliminarRecurso({
    required String uuidUsuario,
    required int id,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_eliminar_recurso',
          params: {'p_uuid_usuario': uuidUsuario, 'p_id': id},
        );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo eliminar el recurso');
    }
  }

  // ── Tramo ────────────────────────────────────────────────────────────────

  /// Crea (id == null) o actualiza un tramo. [capacidad] null = hereda recurso.
  static Future<int> guardarTramo({
    required String uuidUsuario,
    required int idRecurso,
    required String nombre,
    int? capacidad,
    int orden = 0,
    bool activo = true,
    int? id,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_guardar_tramo',
          params: {
            'p_uuid_usuario': uuidUsuario,
            'p_id_recurso': idRecurso,
            'p_nombre': nombre,
            'p_capacidad': capacidad,
            'p_orden': orden,
            'p_activo': activo,
            'p_id': id,
          },
        );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo guardar el tramo');
    }
    return (json['id'] as num).toInt();
  }

  static Future<int> guardarTramoTransporte({
    required String uuidUsuario,
    required int idRecurso,
    required String nombre,
    required String tipoTrayecto,
    int? id,
    bool activo = true,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_guardar_tramo_transporte',
          params: {
            'p_uuid_usuario': uuidUsuario,
            'p_id_recurso': idRecurso,
            'p_nombre': nombre,
            'p_tipo_trayecto': tipoTrayecto,
            'p_id': id,
            'p_activo': activo,
          },
        );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo guardar el trayecto');
    }
    return (json['id'] as num).toInt();
  }

  static Future<void> eliminarTramo({
    required String uuidUsuario,
    required int id,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_eliminar_tramo',
          params: {'p_uuid_usuario': uuidUsuario, 'p_id': id},
        );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo eliminar el tramo');
    }
  }

  // ── Turno ────────────────────────────────────────────────────────────────

  /// Crea (id == null) o actualiza un turno. [tramosIds] reemplaza el set actual
  /// de tramos que el turno consume (deben pertenecer al mismo recurso).
  ///
  /// [horaInicio]/[horaFin] son `"HH:MM"` opcionales: sólo presentación.
  /// Pasar `null` **borra** la hora (la RPC las escribe siempre tal cual).
  static Future<int> guardarTurno({
    required String uuidUsuario,
    required int idRecurso,
    required String nombre,
    required List<int> tramosIds,
    int orden = 0,
    bool activo = true,
    Map<String, double>? precios,
    String? horaInicio,
    String? horaFin,
    int? id,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_guardar_turno',
          params: {
            'p_uuid_usuario': uuidUsuario,
            'p_id_recurso': idRecurso,
            'p_nombre': nombre,
            'p_tramos': tramosIds,
            'p_orden': orden,
            'p_activo': activo,
            'p_id': id,
            'p_precios': precios ?? const {},
            'p_hora_inicio': _horaNullable(horaInicio),
            'p_hora_fin': _horaNullable(horaFin),
          },
        );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo guardar el turno');
    }
    return (json['id'] as num).toInt();
  }

  /// Crea (id == null) o actualiza un turno en modo simplificado.
  ///
  /// La RPC hace en UNA transacción lo que en modo avanzado serían tres viajes:
  /// garantiza el recurso, crea el tramo propio del turno si aún no lo tiene y
  /// enlaza `turno_tramo`. Con esto la UI puede ofrecer "Solo configurar turnos"
  /// sin pedir tramos.
  ///
  /// [idRecurso] es el recurso al que debe ir el turno **nuevo**: con varios
  /// recursos la RPC elegía siempre el primero del local_servicio (migración 52).
  /// Si la base todavía no tiene esa migración el guardado **no se rompe**: se
  /// reintenta sin el parámetro (comportamiento anterior) y el resultado lo
  /// indica con [TurnoAutoResultado.ignoroRecursoElegido] para que la UI avise.
  static Future<TurnoAutoResultado> guardarTurnoAuto({
    required String uuidUsuario,
    required int idLocalServicio,
    required String nombre,
    int orden = 0,
    bool activo = true,
    Map<String, double>? precios,
    String? horaInicio,
    String? horaFin,
    int? id,
    int? idRecurso,
  }) async {
    final params = <String, dynamic>{
      'p_uuid_usuario': uuidUsuario,
      'p_id_local_servicio': idLocalServicio,
      'p_nombre': nombre,
      'p_orden': orden,
      'p_activo': activo,
      'p_precios': precios ?? const {},
      'p_hora_inicio': _horaNullable(horaInicio),
      'p_hora_fin': _horaNullable(horaFin),
      'p_id': id,
    };

    // Sin recurso elegido (modo "solo configurar turnos") no se manda el
    // parámetro: así funciona igual con la RPC de 9 o de 10 argumentos.
    if (idRecurso == null) {
      return _parsearTurnoAuto(await _rpcTurnoAuto(params));
    }

    try {
      final res = await _rpcTurnoAuto({...params, 'p_id_recurso': idRecurso});
      final guardado = _parsearTurnoAuto(res);
      // La RPC devuelve el recurso real: si no es el pedido, la base ignoró el
      // parámetro (migración 52 sin aplicar) y hay que avisar.
      return guardado.idRecurso == null
          ? TurnoAutoResultado(id: guardado.id, idRecurso: idRecurso)
          : guardado;
    } catch (e) {
      if (!_esFaltaParametroRecurso(e)) rethrow;
      // Base sin la migración 52: se guarda como antes para no bloquear al
      // admin. `ignoroRecursoElegido` hace que la pantalla se lo diga claro.
      final guardado = _parsearTurnoAuto(await _rpcTurnoAuto(params));
      return TurnoAutoResultado(
        id: guardado.id,
        idRecurso: guardado.idRecurso,
        ignoroRecursoElegido: true,
      );
    }
  }

  static Future<Object> _rpcTurnoAuto(Map<String, dynamic> params) =>
      _supabase.schema(_schema).rpc('admin_guardar_turno_auto', params: params);

  static TurnoAutoResultado _parsearTurnoAuto(Object res) {
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo guardar el turno');
    }
    return TurnoAutoResultado(
      id: (json['id'] as num).toInt(),
      idRecurso: (json['id_recurso'] as num?)?.toInt(),
    );
  }

  /// ¿El error es "esa función no existe con esos parámetros"?
  ///
  /// PostgREST responde `PGRST202` (con "schema cache" en el texto) cuando la
  /// base no conoce `p_id_recurso`: significa que falta la migración 52.
  static bool _esFaltaParametroRecurso(Object error) {
    final texto = error.toString().toLowerCase();
    return texto.contains('pgrst202') ||
        texto.contains('could not find the function') ||
        (texto.contains('schema cache') && texto.contains('p_id_recurso'));
  }

  /// Activa o desactiva los modos simplificados del local_servicio.
  ///
  /// Devuelve el resumen que reporta la RPC (cuántos tramos/recurso creó), para
  /// poder avisar al admin de lo que el sistema hizo por él.
  static Future<ModoGestionResultado> configurarModo({
    required String uuidUsuario,
    required int idLocalServicio,
    required bool soloTurnos,
    required bool sinTramos,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_config_modo_gestion',
          params: {
            'p_uuid_usuario': uuidUsuario,
            'p_id_local_servicio': idLocalServicio,
            'p_solo_turnos': soloTurnos,
            'p_sin_tramos': sinTramos,
          },
        );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo cambiar el modo de gestión');
    }
    return ModoGestionResultado(
      soloTurnos: (json['solo_turnos'] as bool?) ?? false,
      sinTramos: (json['sin_tramos'] as bool?) ?? false,
      recursoCreado: (json['recurso_creado'] as bool?) ?? false,
      tramosCreados: (json['tramos_creados'] as num?)?.toInt() ?? 0,
    );
  }

  /// `"9:00"` → `"09:00"`. La columna es `time`: Postgres acepta `"9:00"`, pero
  /// se normaliza para que lo que se guarda y lo que se pinta coincidan.
  static String? _horaNullable(String? hora) {
    if (hora == null) return null;
    final t = hora.trim();
    if (t.isEmpty) return null;
    final partes = t.split(':');
    final h = int.tryParse(partes.first);
    if (h == null || h < 0 || h > 23) return null;
    final m = partes.length > 1 ? int.tryParse(partes[1]) : 0;
    if (m == null || m < 0 || m > 59) return null;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  static Future<void> eliminarTurno({
    required String uuidUsuario,
    required int id,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_eliminar_turno',
          params: {'p_uuid_usuario': uuidUsuario, 'p_id': id},
        );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo eliminar el turno');
    }
  }
}

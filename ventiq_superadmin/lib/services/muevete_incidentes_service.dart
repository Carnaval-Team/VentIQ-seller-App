import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Error de negocio de incidentes, pánico y bloqueos.
class MueveteSeguridadException implements Exception {
  final String mensaje;

  const MueveteSeguridadException(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Seguridad del viaje desde la consola (H2).
///
/// * **Incidentes**: bandeja, resolución por RPC `fn_resolver_incidente` y
///   bloqueo manual del implicado (`bloqueos` / `emparejamientos_bloqueados`).
/// * **Pánico**: sólo lectura de `eventos_panico`.
/// * **Puerta de identidad**: `configuracion_identidad` y suspensión temporal
///   por RPC `fn_suspender_bloqueo_identidad`.
///
/// Aclaración que la pantalla repite y aquí se respeta: suspender la puerta de
/// identidad **no** toca `drivers.kyc` (el KYC de un chofer no se suspende
/// nunca); sólo deja de exigir perfil/consentimiento durante la ventana.
class MueveteIncidentesService {
  static final _supabase = Supabase.instance.client;

  static const int filasPorPagina = 20;
  static const int topeAgregado = 5000;

  /// Estados admitidos por `incidentes_estado_check`.
  static const List<String> estados = [
    'reportado',
    'en_revision',
    'confirmado',
    'descartado',
    'escalado',
  ];

  /// Estados que acepta `fn_resolver_incidente`.
  static const List<String> estadosResolucion = [
    'en_revision',
    'confirmado',
    'descartado',
    'escalado',
  ];

  /// Valores de `incidentes_severidad_check`.
  static const List<String> severidades = ['baja', 'media', 'alta', 'critica'];

  /// Valores de `incidentes_tipo_check`.
  static const List<String> tipos = [
    'robo_con_violencia',
    'robo_sin_violencia',
    'agresion_fisica',
    'amenaza',
    'acoso_sexual',
    'acoso_verbal',
    'suplantacion',
    'vehiculo_incorrecto',
    'no_show_pasajero',
    'cobro_abusivo',
    'extorsion',
    'otro',
  ];

  /// Valores de `bloqueos_tipo_bloqueo_check`.
  static const List<String> tiposBloqueo = [
    'administrativo',
    'permanente',
    'automatico_temporal',
    'restriccion_no_show',
  ];

  /// Límite superior de una suspensión (30 días, tal como valida la RPC).
  static const int minutosMaxSuspension = 43200;

  // ─── Incidentes ───────────────────────────────────────────────────────

  /// Página de incidentes (pide una fila de más para saber si hay siguiente).
  static Future<List<Map<String, dynamic>>> listarIncidentes({
    String? estado,
    String? severidad,
    int page = 0,
    int filas = filasPorPagina,
  }) {
    return _guard('No se pudieron cargar los incidentes', () async {
      var query = _supabase.schema('muevete').from('incidentes').select();
      if (estado != null && estado.isNotEmpty) {
        query = query.eq('estado', estado);
      }
      if (severidad != null && severidad.isNotEmpty) {
        query = query.eq('severidad', severidad);
      }
      final desde = page * filas;
      final rows =
          await query
              .order('created_at', ascending: false)
              .order('id', ascending: false)
              .range(desde, desde + filas);
      return List<Map<String, dynamic>>.from(rows);
    });
  }

  /// Reincidencia: cuántos incidentes **confirmados** acumula cada implicado.
  ///
  /// Clave `u:<uuid>` para clientes y `d:<id>` para choferes. Con esto la
  /// pantalla marca visualmente a quien acumula >= 2 (el mismo umbral que usa
  /// `fn_resolver_incidente` para bloquear por reincidencia).
  static Future<Map<String, int>> reincidencia() {
    return _guard('No se pudo calcular la reincidencia', () async {
      final rows = await _supabase
          .schema('muevete')
          .from('incidentes')
          .select('contraparte_uuid, contraparte_driver_id')
          .eq('estado', 'confirmado')
          .limit(topeAgregado);
      final conteo = <String, int>{};
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final uuid = r['contraparte_uuid'] as String?;
        final driver = r['contraparte_driver_id'];
        if (uuid != null && uuid.isNotEmpty) {
          conteo['u:$uuid'] = (conteo['u:$uuid'] ?? 0) + 1;
        }
        if (driver != null) {
          conteo['d:$driver'] = (conteo['d:$driver'] ?? 0) + 1;
        }
      }
      return conteo;
    });
  }

  /// Resuelve un incidente por RPC.
  ///
  /// La RPC exige superadmin y, si el estado pasa a `confirmado`, puede crear
  /// sola el bloqueo (severidad crítica o reincidencia) y el bloqueo de
  /// emparejamiento cuando `solicita_no_emparejar = true`.
  static Future<Map<String, dynamic>> resolverIncidente({
    required int id,
    required String estado,
    required String resolucion,
  }) {
    if (!estadosResolucion.contains(estado)) {
      throw const MueveteSeguridadException(
        'El estado debe ser en_revision, confirmado, descartado o escalado.',
      );
    }
    if (resolucion.trim().length < 5) {
      throw const MueveteSeguridadException(
        'Escribe una resolución de al menos 5 caracteres.',
      );
    }
    return _guard('No se pudo resolver el incidente', () async {
      final res = await _supabase
          .schema('muevete')
          .rpc(
            'fn_resolver_incidente',
            params: {
              'p_incidente_id': id,
              'p_estado': estado,
              'p_resolucion': resolucion.trim(),
            },
          );
      return res is Map
          ? Map<String, dynamic>.from(res)
          : <String, dynamic>{'success': true};
    });
  }

  // ─── Bloqueos ─────────────────────────────────────────────────────────

  /// Bloquea al implicado de un incidente.
  ///
  /// `bloqueos_un_solo_sujeto` exige **exactamente uno** de `user_uuid` /
  /// `driver_id`, así que aquí se elige según quién sea la contraparte.
  static Future<void> bloquear({
    required String motivo,
    String? userUuid,
    int? driverId,
    String tipoBloqueo = 'administrativo',
    int? dias,
    int? incidenteId,
  }) {
    final tieneUuid = userUuid != null && userUuid.trim().isNotEmpty;
    final tieneDriver = driverId != null;
    if (tieneUuid == tieneDriver) {
      throw const MueveteSeguridadException(
        'Hay que indicar exactamente un implicado: usuario o chofer.',
      );
    }
    if (!tiposBloqueo.contains(tipoBloqueo)) {
      throw MueveteSeguridadException(
        'Tipo de bloqueo inválido: $tipoBloqueo.',
      );
    }
    if (motivo.trim().length < 5) {
      throw const MueveteSeguridadException(
        'El motivo del bloqueo debe tener al menos 5 caracteres.',
      );
    }
    if (dias != null && dias < 0) {
      throw const MueveteSeguridadException(
        'Los días de bloqueo no pueden ser negativos.',
      );
    }

    final payload = <String, dynamic>{
      'user_uuid': tieneUuid ? userUuid.trim() : null,
      'driver_id': tieneDriver ? driverId : null,
      'tipo_bloqueo': tipoBloqueo,
      'motivo': motivo.trim(),
      'creado_motivo': motivo.trim(),
      'incidente_id': incidenteId,
      'vigente_desde': DateTime.now().toUtc().toIso8601String(),
      'vigente_hasta':
          (dias != null && dias > 0)
              ? DateTime.now()
                  .toUtc()
                  .add(Duration(days: dias))
                  .toIso8601String()
              : null,
      'creado_por': _supabase.auth.currentUser?.id,
    };

    return _guard('No se pudo registrar el bloqueo', () async {
      await _supabase.schema('muevete').from('bloqueos').insert(payload);
    });
  }

  /// Añade el par víctima↔agresor a la lista de «no volver a emparejar».
  static Future<void> noVolverAEmparejar({
    required String motivo,
    required String userUuid,
    required int driverId,
    int? incidenteId,
  }) {
    return _guard('No se pudo registrar el bloqueo de emparejamiento', () async {
      await _supabase
          .schema('muevete')
          .from('emparejamientos_bloqueados')
          .upsert(
            {
              'user_uuid': userUuid.trim(),
              'driver_id': driverId,
              'motivo': motivo.trim(),
              'incidente_id': incidenteId,
            },
            onConflict: 'user_uuid,driver_id',
            ignoreDuplicates: true,
          );
    });
  }

  /// Últimos bloqueos registrados, con el nombre del sujeto ya resuelto.
  static Future<List<Map<String, dynamic>>> listarBloqueos({
    int limite = 50,
  }) {
    return _guard('No se pudieron cargar los bloqueos', () async {
      final rows = await _supabase
          .schema('muevete')
          .from('bloqueos')
          .select()
          .order('created_at', ascending: false)
          .limit(limite);
      return List<Map<String, dynamic>>.from(rows);
    });
  }

  /// Revoca un bloqueo vigente por RPC (`fn_revocar_bloqueo`).
  static Future<void> revocarBloqueo({
    required int bloqueoId,
    required String motivo,
  }) {
    if (motivo.trim().length < 5) {
      throw const MueveteSeguridadException(
        'El motivo de la revocación debe tener al menos 5 caracteres.',
      );
    }
    return _guard('No se pudo revocar el bloqueo', () async {
      await _supabase.schema('muevete').rpc(
        'fn_revocar_bloqueo',
        params: {'p_bloqueo_id': bloqueoId, 'p_motivo': motivo.trim()},
      );
    });
  }

  // ─── Pánico (sólo lectura) ────────────────────────────────────────────

  /// Últimos eventos de pánico. Sin escritura: la consola sólo observa.
  static Future<List<Map<String, dynamic>>> listarEventosPanico({
    int limite = 50,
  }) {
    return _guard('No se pudieron cargar los eventos de pánico', () async {
      final rows = await _supabase
          .schema('muevete')
          .from('eventos_panico')
          .select()
          .order('recibido_at', ascending: false)
          .limit(limite);
      return List<Map<String, dynamic>>.from(rows);
    });
  }

  // ─── Puerta de identidad ──────────────────────────────────────────────

  /// Fila única de `configuracion_identidad` (id = 1).
  static Future<Map<String, dynamic>?> configuracionIdentidad() {
    return _guard('No se pudo cargar la configuración de identidad', () async {
      final row =
          await _supabase
              .schema('muevete')
              .from('configuracion_identidad')
              .select()
              .eq('id', 1)
              .maybeSingle();
      return row == null ? null : Map<String, dynamic>.from(row);
    });
  }

  /// Suspende temporalmente la puerta de identidad.
  ///
  /// `p_minutos = 0` la reanuda (la RPC pone `bloqueo_suspendido_hasta = NULL`).
  static Future<Map<String, dynamic>> suspenderPuertaIdentidad({
    required int minutos,
    String? motivo,
  }) {
    if (minutos < 0 || minutos > minutosMaxSuspension) {
      throw const MueveteSeguridadException(
        'La suspensión debe estar entre 0 minutos y 30 días (43 200 minutos).',
      );
    }
    if (minutos > 0 && (motivo ?? '').trim().length < 5) {
      throw const MueveteSeguridadException(
        'Escribe el motivo de la suspensión (mínimo 5 caracteres).',
      );
    }
    return _guard('No se pudo suspender la puerta de identidad', () async {
      final res = await _supabase.schema('muevete').rpc(
        'fn_suspender_bloqueo_identidad',
        params: {
          'p_minutos': minutos,
          'p_motivo': (motivo ?? '').trim().isEmpty ? null : motivo!.trim(),
        },
      );
      return res is Map
          ? Map<String, dynamic>.from(res)
          : <String, dynamic>{'success': true};
    });
  }

  /// Reanuda la puerta de identidad de inmediato.
  static Future<Map<String, dynamic>> reanudarPuertaIdentidad() =>
      suspenderPuertaIdentidad(minutos: 0);

  /// `true` si hay una suspensión vigente ahora mismo.
  static bool suspensionVigente(Map<String, dynamic>? config) {
    final hasta = DateTime.tryParse(
      '${config?['bloqueo_suspendido_hasta'] ?? ''}',
    );
    if (hasta == null) return false;
    return hasta.toUtc().isAfter(DateTime.now().toUtc());
  }

  // ─── Nombres de los implicados ────────────────────────────────────────

  /// Nombres de usuarios (clientes) por uuid.
  static Future<Map<String, Map<String, dynamic>>> usuariosPorUuid(
    Iterable<String> uuids,
  ) {
    final lista = uuids.where((u) => u.isNotEmpty).toSet().toList();
    if (lista.isEmpty) return Future.value({});
    return _guard('No se pudieron resolver los usuarios', () async {
      final rows = await _supabase
          .schema('muevete')
          .from('users')
          .select('uuid, name, phone, email')
          .inFilter('uuid', lista);
      final mapa = <String, Map<String, dynamic>>{};
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        mapa['${r['uuid']}'] = r;
      }
      return mapa;
    });
  }

  /// Nombres de choferes por id.
  static Future<Map<String, Map<String, dynamic>>> choferesPorId(
    Iterable<int> ids,
  ) {
    final lista = ids.toSet().toList();
    if (lista.isEmpty) return Future.value({});
    return _guard('No se pudieron resolver los choferes', () async {
      final rows = await _supabase
          .schema('muevete')
          .from('drivers')
          .select('id, uuid, name, telefono, kyc')
          .inFilter('id', lista);
      final mapa = <String, Map<String, dynamic>>{};
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        mapa['${r['id']}'] = r;
      }
      return mapa;
    });
  }

  // ─── Etiquetas ────────────────────────────────────────────────────────

  static String etiquetaTipo(String? tipo) {
    switch (tipo) {
      case 'robo_con_violencia':
        return 'Robo con violencia';
      case 'robo_sin_violencia':
        return 'Robo sin violencia';
      case 'agresion_fisica':
        return 'Agresión física';
      case 'amenaza':
        return 'Amenaza';
      case 'acoso_sexual':
        return 'Acoso sexual';
      case 'acoso_verbal':
        return 'Acoso verbal';
      case 'suplantacion':
        return 'Suplantación';
      case 'vehiculo_incorrecto':
        return 'Vehículo incorrecto';
      case 'no_show_pasajero':
        return 'Pasajero no presentado';
      case 'cobro_abusivo':
        return 'Cobro abusivo';
      case 'extorsion':
        return 'Extorsión';
      case 'otro':
        return 'Otro';
      default:
        return tipo ?? '—';
    }
  }

  static String etiquetaEstado(String? estado) {
    switch (estado) {
      case 'reportado':
        return 'Reportado';
      case 'en_revision':
        return 'En revisión';
      case 'confirmado':
        return 'Confirmado';
      case 'descartado':
        return 'Descartado';
      case 'escalado':
        return 'Escalado';
      default:
        return estado ?? '—';
    }
  }

  static String etiquetaSeveridad(String? severidad) {
    switch (severidad) {
      case 'baja':
        return 'Baja';
      case 'media':
        return 'Media';
      case 'alta':
        return 'Alta';
      case 'critica':
        return 'Crítica';
      default:
        return severidad ?? '—';
    }
  }

  static String etiquetaTipoBloqueo(String? tipo) {
    switch (tipo) {
      case 'administrativo':
        return 'Administrativo';
      case 'permanente':
        return 'Permanente';
      case 'automatico_temporal':
        return 'Automático temporal';
      case 'restriccion_no_show':
        return 'Restricción por no-show';
      default:
        return tipo ?? '—';
    }
  }

  static String etiquetaEstadoPanico(String? estado) {
    switch (estado) {
      case 'activo':
        return 'Activo';
      case 'cancelado_falso':
        return 'Cancelado (falso)';
      case 'gestionado':
        return 'Gestionado';
      case 'cerrado':
        return 'Cerrado';
      default:
        return estado ?? '—';
    }
  }

  static String etiquetaEnvio(String? envio) {
    switch (envio) {
      case 'pendiente_envio':
        return 'Pendiente de envío';
      case 'enviado':
        return 'Enviado';
      case 'fallido':
        return 'Fallido';
      case 'no_aplica':
        return 'No aplica';
      default:
        return envio ?? '—';
    }
  }

  // ─── Infraestructura de errores ───────────────────────────────────────

  static Future<T> _guard<T>(String accion, Future<T> Function() cuerpo) async {
    try {
      return await cuerpo();
    } on MueveteSeguridadException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint(
        '[MueveteIncidentesService] $accion · code=${e.code} message=${e.message}',
      );
      throw MueveteSeguridadException('$accion: ${_detalle(e)}.');
    } on AuthException catch (e) {
      debugPrint('[MueveteIncidentesService] $accion · auth=${e.message}');
      throw const MueveteSeguridadException(
        'La sesión expiró o no es válida. Vuelve a iniciar sesión.',
      );
    } catch (e) {
      debugPrint('[MueveteIncidentesService] $accion · $e');
      throw MueveteSeguridadException('$accion: $e');
    }
  }

  static String _detalle(PostgrestException e) {
    final mensaje = e.message;
    if (mensaje.contains('no_autorizado')) {
      return 'no tienes permisos de superadministrador';
    }
    if (mensaje.contains('incidente_no_existe')) {
      return 'el incidente ya no existe';
    }
    if (mensaje.contains('estado_invalido')) {
      return 'el estado enviado no es válido';
    }
    if (mensaje.contains('motivo_requerido')) {
      return 'falta el motivo';
    }
    if (mensaje.contains('minutos_invalidos')) {
      return 'los minutos de suspensión están fuera de rango';
    }
    if (mensaje.contains('bloqueo_no_existe_o_ya_revocado')) {
      return 'el bloqueo no existe o ya estaba revocado';
    }
    switch (e.code) {
      case '42501':
        return 'no tienes permisos de superadministrador';
      case '23514':
        return 'los valores están fuera del rango permitido por la base de datos';
      case '23503':
        return 'hay registros relacionados que impiden la operación';
      case '42P01':
        return 'la tabla no existe en el esquema muevete';
      case 'PGRST202':
        return 'la función no existe con esa firma en la base de datos';
      default:
        return mensaje;
    }
  }
}
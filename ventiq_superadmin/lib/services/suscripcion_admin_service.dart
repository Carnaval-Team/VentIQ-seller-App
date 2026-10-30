import 'package:supabase_flutter/supabase_flutter.dart';

/// Acceso del panel a los RPC del módulo de suscripciones de Inventtia Flow.
///
/// Todo vive en el schema `flow` del **mismo** proyecto Supabase al que apunta
/// esta app (el panel y Flow comparten base). Las funciones `admin_*` exigen
/// `public.fn_is_superadmin_full_access()` **en el servidor**: que el panel
/// esconda un botón no protege nada, así que aquí no hay ninguna comprobación de
/// permisos que valga — solo se muestran los errores que devuelva el servidor.
///
/// Los RPC de Flow devuelven siempre `{ ok: bool, data | error }`, así que el
/// servicio desenvuelve esa forma una sola vez y expone el resultado ya listo.
class SuscripcionAdminService {
  const SuscripcionAdminService._();

  static const String _schema = 'flow';

  static SupabaseClient get _sb => Supabase.instance.client;

  /// Llamada genérica a un RPC `{ ok, data | error }`.
  ///
  /// Devuelve `data` (que puede ser un objeto o una lista) o lanza
  /// [SuscripcionAdminException] con el mensaje del servidor. Lanzar en vez de
  /// devolver `null` es lo correcto aquí: en un panel de administración, un
  /// fallo silencioso se interpreta como "no hay nada que verificar" y el
  /// superadmin se queda sin saber que el pago existe.
  static Future<dynamic> _rpc(
    String funcion, {
    Map<String, dynamic>? params,
  }) async {
    final res = await _sb.schema(_schema).rpc(funcion, params: params);

    if (res is! Map) {
      throw const SuscripcionAdminException(
        'Respuesta inesperada del servidor',
      );
    }

    final mapa = Map<String, dynamic>.from(res);
    if (mapa['ok'] == false) {
      throw SuscripcionAdminException(
        mapa['error'] as String? ?? 'La operación no se pudo completar',
      );
    }

    return mapa['data'];
  }

  // ── Bandeja y ficha ──────────────────────────────────────────────────────

  /// Entidades con su estado de suscripción.
  ///
  /// [filtro]: `todas` | `activas` | `por_vencer` | `en_gracia` | `vencidas` |
  /// `sin_plan` | `suspendidas` | `pagos_pendientes`.
  static Future<List<Map<String, dynamic>>> listar({
    String filtro = 'todas',
    String? buscar,
  }) async {
    final data = await _rpc(
      'admin_suscripcion_listar',
      params: {'p_filtro': filtro, 'p_buscar': buscar ?? ''},
    );
    return _listaDeMapas(data);
  }

  /// Ficha completa de una entidad (estado, historial, pagos, movimientos).
  static Future<Map<String, dynamic>> detalle(int idEntidad) async {
    final data = await _rpc(
      'admin_suscripcion_detalle',
      params: {'p_id_entidad': idEntidad},
    );
    return _mapaDe(data);
  }

  // ── Acciones sobre el pago ───────────────────────────────────────────────

  /// Verifica un pago reportado y acredita los días del plan.
  static Future<Map<String, dynamic>> aprobarPago(
    int idTransaccion, {
    String? observaciones,
  }) async {
    final data = await _rpc(
      'admin_suscripcion_aprobar_pago',
      params: {
        'p_id_transaccion': idTransaccion,
        'p_observaciones': observaciones ?? '',
      },
    );
    return _mapaDe(data);
  }

  /// Rechaza un pago reportado. El motivo es obligatorio en el servidor.
  static Future<Map<String, dynamic>> rechazarPago(
    int idTransaccion, {
    required String motivo,
  }) async {
    final data = await _rpc(
      'admin_suscripcion_rechazar_pago',
      params: {'p_id_transaccion': idTransaccion, 'p_motivo': motivo},
    );
    return _mapaDe(data);
  }

  /// Acredita días a mano (cortesía, compensación, corrección).
  ///
  /// El motivo es obligatorio y queda en el libro de movimientos: una
  /// acreditación sin motivo es indistinguible de un error.
  static Future<Map<String, dynamic>> acreditar({
    required int idEntidad,
    required int dias,
    int? idPlan,
    required String motivo,
  }) async {
    final data = await _rpc(
      'admin_suscripcion_acreditar',
      params: {
        'p_id_entidad': idEntidad,
        'p_dias': dias,
        'p_id_plan': idPlan,
        'p_motivo': motivo,
      },
    );
    return _mapaDe(data);
  }

  /// Crea la suscripción de las entidades que no tienen ninguna.
  ///
  /// Es el paso explícito que sustituye al backfill automático: sin esto las
  /// entidades anteriores siguen activas por *grandfathering*, pero no tienen
  /// fila ni se les cuenta el trial.
  static Future<int> inicializar({int? dias}) async {
    final data = await _rpc(
      'admin_suscripcion_inicializar',
      params: {'p_dias': dias},
    );
    return (_mapaDe(data)['entidades_inicializadas'] as num?)?.toInt() ?? 0;
  }

  static Future<void> suspender(int idEntidad, {required String motivo}) =>
      _rpc(
        'admin_suscripcion_suspender',
        params: {'p_id_entidad': idEntidad, 'p_motivo': motivo},
      );

  static Future<void> reactivar(int idEntidad, {String? motivo}) => _rpc(
    'admin_suscripcion_reactivar',
    params: {'p_id_entidad': idEntidad, 'p_motivo': motivo ?? ''},
  );

  // ── Planes ───────────────────────────────────────────────────────────────

  /// Todos los planes, activos e inactivos, con sus campos de catálogo.
  ///
  /// Desde la migración `72_planes_limites_privados.sql` cada plan trae además
  /// `id_entidad`, `entidad_denominacion`, `modalidad` y `etiqueta`, y `limites`
  /// con las claves `entidades`, `locales`, `servicios_por_local`,
  /// `servicios_catalogo` y `usuarios`. No se tipa aquí a propósito: la pantalla
  /// lee el mapa con helpers tolerantes (ver `planes_ui.dart`), así que un
  /// servidor sin la migración sigue funcionando con los campos que sí manda.
  static Future<List<Map<String, dynamic>>> planes() async {
    final data = await _rpc('admin_planes_listar');
    return _listaDeMapas(data);
  }

  /// Crea (`id` nulo) o actualiza un plan. Devuelve el id.
  ///
  /// Es el envoltorio de [guardarPlanDetallado] que conserva la firma antigua
  /// (`Future<int>`) para las pantallas que solo necesitan el id.
  static Future<int> guardarPlan({
    int? id,
    String? codigo,
    String? nombre,
    String? descripcion,
    int? duracionDias,
    double? precio,
    String? moneda,
    Map<String, dynamic>? limites,
    int? orden,
    bool? activo,
    String? modalidad,
    int? idEntidad,
    String? etiqueta,
  }) async {
    final data = await guardarPlanDetallado(
      id: id,
      codigo: codigo,
      nombre: nombre,
      descripcion: descripcion,
      duracionDias: duracionDias,
      precio: precio,
      moneda: moneda,
      limites: limites,
      orden: orden,
      activo: activo,
      modalidad: modalidad,
      idEntidad: idEntidad,
      etiqueta: etiqueta,
    );
    return (data['id'] as num?)?.toInt() ?? 0;
  }

  /// Crea (`id` nulo) o actualiza un plan y devuelve el `data` completo del RPC.
  ///
  /// Semántica del servidor (migración 72), importante para no cambiar campos
  /// sin querer:
  /// - [limites]: objeto jsonb con **solo** claves `> 0` (`entidades`,
  ///   `locales`, `servicios_por_local`, `servicios_catalogo`, `usuarios`).
  ///   `{}` **borra** los límites; `null` **conserva** los actuales.
  /// - [modalidad]: `pago` | `contacto`; `null` conserva.
  /// - [idEntidad]: entidad dueña del plan privado. `0` = plan **público**
  ///   (el RPC traduce 0 a `id_entidad = NULL`); `null` **conserva** el valor
  ///   actual, cosa que necesita el toggle de activar/desactivar para no
  ///   publicar sin querer un plan privado.
  /// - [etiqueta]: cinta de la tarjeta; cadena vacía la **quita**, `null`
  ///   conserva.
  ///
  /// El `data` devuelto incluye además:
  /// - `codigo`: el generado por el servidor cuando se crea un plan privado sin
  ///   código (`privado_<idEntidad>_<n>`).
  /// - `aviso`: texto cuando el plan queda activo de pago con precio 0 (no
  ///   bloquea; el editor lo muestra al superadmin).
  ///
  /// Tolerancia al despliegue: los parámetros nuevos llegan con la migración
  /// 72. Si el servidor todavía expone la firma vieja (10 argumentos), PostgREST
  /// responde `PGRST202` / `42883` y se reintenta **solo** con los campos
  /// antiguos para que el panel no se quede sin poder guardar planes mientras se
  /// pega la migración. En ese caso los campos nuevos se descartan (no hay dónde
  /// guardarlos) y la pantalla los sigue mostrando igual.
  static Future<Map<String, dynamic>> guardarPlanDetallado({
    int? id,
    String? codigo,
    String? nombre,
    String? descripcion,
    int? duracionDias,
    double? precio,
    String? moneda,
    Map<String, dynamic>? limites,
    int? orden,
    bool? activo,
    String? modalidad,
    int? idEntidad,
    String? etiqueta,
  }) async {
    final limitesLimpios = limites == null ? null : _limitesLimpios(limites);
    // `p_limites` ya existe en la firma antigua: se conserva incluso al
    // reintentar contra un servidor sin la migración 72.
    final basico = <String, dynamic>{
      'p_id': id,
      'p_codigo': codigo,
      'p_nombre': nombre,
      'p_descripcion': descripcion,
      'p_duracion_dias': duracionDias,
      'p_precio': precio,
      'p_moneda': moneda,
      'p_limites': limitesLimpios,
      'p_orden': orden,
      'p_activo': activo,
    };
    final completo = <String, dynamic>{
      ...basico,
      'p_modalidad':
          (modalidad == null || modalidad.trim().isEmpty)
              ? null
              : modalidad.trim(),
      'p_id_entidad': idEntidad,
      // Cadena vacía = quitar la cinta (null conservaría la anterior). La
      // pantalla pinta la cinta solo si el texto tiene contenido.
      'p_etiqueta': etiqueta?.trim(),
    };

    try {
      return _mapaDe(await _rpc('admin_plan_guardar', params: completo));
    } on PostgrestException catch (e) {
      if (!_funcionNoDesplegada(e)) rethrow;
      return _mapaDe(await _rpc('admin_plan_guardar', params: basico));
    }
  }

  /// Deja solo los límites válidos del contrato: `> 0` y claves conocidas.
  ///
  /// Se filtra también en el cliente para que un campo con 0 o con basura no
  /// viaje como "límite 0" y termine bloqueando la creación de recursos.
  static Map<String, int> _limitesLimpios(Map<String, dynamic> limites) {
    const claves = <String>{
      'entidades',
      'locales',
      'servicios_por_local',
      'servicios_catalogo',
      'usuarios',
    };
    final salida = <String, int>{};
    limites.forEach((clave, valor) {
      if (!claves.contains(clave)) return;
      final n =
          valor is num
              ? valor.toInt()
              : (valor is String ? int.tryParse(valor.trim()) : null);
      if (n != null && n > 0) salida[clave] = n;
    });
    return salida;
  }

  /// ¿El error es "esa función con esa firma no existe"?
  ///
  /// PostgREST devuelve `PGRST202` cuando no encuentra la función con los
  /// argumentos enviados (esquema viejo); Postgres devuelve `42883` para
  /// `undefined_function`. Ambos se tratan igual: reintentar sin los parámetros
  /// nuevos.
  static bool _funcionNoDesplegada(PostgrestException e) {
    if (e.code == 'PGRST202' || e.code == '42883') return true;
    final mensaje = e.message.toLowerCase();
    return mensaje.contains('could not find the function') ||
        mensaje.contains('no existe la función') ||
        mensaje.contains('schema cache');
  }

  /// Borra el plan si nadie lo usó; si tiene historia, el servidor lo desactiva
  /// en vez de romper el libro de movimientos.
  static Future<Map<String, dynamic>> eliminarPlan(int id) async {
    final data = await _rpc('admin_plan_eliminar', params: {'p_id': id});
    return _mapaDe(data);
  }

  // ── Configuración ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> config() async {
    final data = await _rpc('admin_config_obtener');
    return _mapaDe(data);
  }

  /// Guarda **solo** las claves presentes en [cambios].
  static Future<Map<String, dynamic>> guardarConfig(
    Map<String, dynamic> cambios,
  ) async {
    final data = await _rpc(
      'admin_config_guardar',
      params: {'p_config': cambios},
    );
    return _mapaDe(data);
  }

  // ── Utilidades ───────────────────────────────────────────────────────────

  static Map<String, dynamic> _mapaDe(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static List<Map<String, dynamic>> _listaDeMapas(dynamic v) {
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }
}

/// Error de un RPC de suscripciones con el mensaje que redactó el servidor.
///
/// Se propaga el texto del servidor tal cual porque esos mensajes están escritos
/// para leerse ("Ese pago ya fue procesado (estado: verificado)"), y traducirlos
/// aquí solo añadiría sitios donde equivocarse.
class SuscripcionAdminException implements Exception {
  const SuscripcionAdminException(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

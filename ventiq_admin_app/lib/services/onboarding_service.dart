import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/onboarding_tareas.dart';
import 'user_preferences_service.dart';

/// Acceso a los datos del alta progresiva de tienda (fase 2 del plan
/// `docs/plans/alta-tienda-progresiva-go-live.md`).
///
/// Dos responsabilidades, y nada más:
///
/// 1. Leer y escribir el **estado de onboarding** de la tienda
///    (`app_dat_tienda.estado_onboarding`, `tipo_negocio`, `activada_en`,
///    `onboarding_descartado_en`) y el estado por tarea
///    (`app_dat_tarea_onboarding`).
/// 2. Construir los `HechosTienda` que alimentan el checklist puro de
///    [construirTareas]. Aquí solo se consultan hechos; la decisión de qué
///    tarea está pendiente es del modelo, no de este servicio.
///
/// **Ojo con el nombre de la columna:** `app_dat_tienda.estado` NO es el estado
/// de la tienda, es el código de provincia geográfica (`'16'`, `'04'`, ...) que
/// escribe el alta con `GeoNameService`. Este servicio nunca la toca: el estado
/// de onboarding vive en `estado_onboarding`.
///
/// Patrón del repo: id de tienda activa vía [UserPreferencesService], igual que
/// `cocina_service._requireStoreId()`. Los errores de negocio salen como
/// [OnboardingException], espejo de `CocinaException`, para que la pantalla
/// pueda distinguir «no hay tienda» de «falló la red».
class OnboardingService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final UserPreferencesService _userPrefs = UserPreferencesService();

  /// Tienda activa del usuario.
  ///
  /// Si no se puede resolver se lanza [OnboardingException] con `NO_STORE`: sin
  /// tienda no hay nada que consultar y devolver hechos vacíos en silencio
  /// pintaría un checklist entero pendiente sobre una tienda que quizá ya está
  /// activa.
  static Future<int> _requireStoreId() async {
    final storeId = await _userPrefs.getIdTienda();
    if (storeId == null) {
      throw OnboardingException(
        'No se pudo determinar la tienda actual. Vuelve a iniciar sesión.',
        codigo: 'NO_STORE',
      );
    }
    return storeId;
  }

  /// `true` cuando la tienda puede vender (`estado_onboarding == 'activa'`).
  ///
  /// Se calcula aquí y no en cada pantalla para que el criterio viva en un solo
  /// sitio: el login enruta al dashboard con esta misma comparación.
  static bool estaActiva(String? estadoOnboarding) => estadoOnboarding == 'activa';

  /// `true` mientras la tienda siga en alta (borrador).
  static bool estaEnBorrador(String? estadoOnboarding) =>
      estadoOnboarding == 'borrador';

  // ══════════════════════════════════════════════════════════════════════
  // Estado de la tienda
  // ══════════════════════════════════════════════════════════════════════

  /// Estado de onboarding de la tienda activa.
  ///
  /// [descartadoEn] no estaba en el plan original, pero la pantalla de
  /// activación necesita saber si el checklist está descartado para ofrecer
  /// «recuperar»; sin él habría que repetir la consulta.
  ///
  /// Si la fila no se puede leer (RLS, tienda borrada) se devuelve `borrador`
  /// con todo nulo: es el valor seguro, porque nada se activa solo. Un error de
  /// red sí se propaga, para no confundir «sin datos» con «sin conexión».
  Future<
    ({
      String estadoOnboarding,
      String? tipoNegocio,
      DateTime? activadaEn,
      DateTime? descartadoEn,
    })
  >
  leerEstadoTienda() async {
    final storeId = await _requireStoreId();

    final fila = await _supabase
        .from('app_dat_tienda')
        .select(
          'estado_onboarding, tipo_negocio, activada_en, onboarding_descartado_en',
        )
        .eq('id', storeId)
        .maybeSingle();

    if (fila == null) {
      return (
        estadoOnboarding: 'borrador',
        tipoNegocio: null,
        activadaEn: null,
        descartadoEn: null,
      );
    }

    return (
      estadoOnboarding: (fila['estado_onboarding'] ?? 'borrador').toString(),
      tipoNegocio: _textoONulo(fila['tipo_negocio']),
      activadaEn: _fecha(fila['activada_en']),
      descartadoEn: _fecha(fila['onboarding_descartado_en']),
    );
  }

  /// Guarda el tipo de negocio **declarado**.
  ///
  /// Es una columna declarativa: solo elige qué tareas recomendar. No enciende
  /// `modo_restaurante`, `cocina_activa` ni `modo_servicentro`; la capacidad
  /// real la siguen decidiendo esos flags (decisión registrada en el plan, para
  /// no tener dos fuentes de verdad que se contradigan).
  ///
  /// [tipo] nulo o vacío limpia la columna. Un valor fuera de
  /// [tiposNegocioConocidos] se rechaza aquí con un mensaje claro en vez de
  /// dejar que reviente el CHECK de la tabla.
  Future<void> guardarTipoNegocio(String? tipo) async {
    final storeId = await _requireStoreId();
    final valor = tipo?.trim().toLowerCase();

    if (valor != null && valor.isNotEmpty && !tiposNegocioConocidos.contains(valor)) {
      throw OnboardingException(
        'Tipo de negocio no válido: "$tipo". '
        'Los admitidos son ${tiposNegocioConocidos.join(', ')}.',
        codigo: 'TIPO_INVALIDO',
      );
    }

    await _supabase
        .from('app_dat_tienda')
        .update({'tipo_negocio': (valor == null || valor.isEmpty) ? null : valor})
        .eq('id', storeId);
  }

  /// Marca el checklist como descartado (se puede recuperar).
  ///
  /// No borra las tareas ni cambia el estado de la tienda: descartar es dejar de
  /// molestar, no renunciar al alta.
  Future<void> descartarOnboarding() async {
    final storeId = await _requireStoreId();
    await _supabase
        .from('app_dat_tienda')
        .update({
          'onboarding_descartado_en': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', storeId);
  }

  /// Vuelve a mostrar el checklist que se había descartado.
  Future<void> restaurarOnboarding() async {
    final storeId = await _requireStoreId();
    await _supabase
        .from('app_dat_tienda')
        .update({'onboarding_descartado_en': null})
        .eq('id', storeId);
  }

  // ══════════════════════════════════════════════════════════════════════
  // Hechos reales
  // ══════════════════════════════════════════════════════════════════════

  /// Consulta los hechos de la tienda activa y los empaqueta en [HechosTienda].
  ///
  /// Todo sale de filas reales; nada se marca a mano. Las consultas
  /// independientes van en paralelo y las dos que dependen de otra (zonas
  /// necesita los ids de almacén, vendedores los del TPV) van después: son 7
  /// viajes que en serie se notan al abrir la pantalla.
  ///
  /// Detalles que importan y no son obvios:
  ///
  /// - `app_dat_configuracion_tienda` **puede no existir**: 3 de 8 tiendas de
  ///   newa no tienen fila. Por eso `maybeSingle()` y nulo = `false`, en vez de
  ///   asumir una fila o reventar.
  /// - Las zonas se leen por `id_almacen` y no por `id_tienda`: la tabla no
  ///   tiene `id_tienda`.
  /// - `app_dat_vendedor` tampoco tiene `id_tienda`: el vínculo con la tienda
  ///   pasa por `app_dat_tpv`. Se exige además que el trabajador sea de la
  ///   tienda, para no contar un vendedor colgando de un TPV ajeno.
  Future<HechosTienda> leerHechos() async {
    final storeId = await _requireStoreId();

    // ── Consultas independientes, en paralelo ────────────────────────────
    final respuestas = await Future.wait<Object?>([
      // Almacenes vivos de la tienda.
      _supabase
          .from('app_dat_almacen')
          .select('id, denominacion, es_cocina')
          .eq('id_tienda', storeId)
          .isFilter('deleted_at', null),
      // Cajas de la tienda.
      _supabase.from('app_dat_tpv').select('id, id_almacen').eq('id_tienda', storeId),
      // Catálogo: basta con saber si hay al menos uno.
      _supabase
          .from('app_dat_producto')
          .select('id')
          .eq('id_tienda', storeId)
          .isFilter('deleted_at', null)
          .limit(1),
      // Equipo: sin los borrados lógicamente.
      _supabase
          .from('app_dat_trabajadores')
          .select('id')
          .eq('id_tienda', storeId)
          .isFilter('deleted_at', null),
      // Cocinas. Ojo: la tabla tiene `deleted_at`, el flag rápido está en
      // `app_dat_almacen.es_cocina`; se miran los dos.
      _supabase
          .from('app_dat_cocina')
          .select('id, id_almacen, activa')
          .eq('id_tienda', storeId)
          .isFilter('deleted_at', null),
      // Flags de restaurante/cocina. Puede no haber fila: null = false.
      _supabase
          .from('app_dat_configuracion_tienda')
          .select('modo_restaurante, cocina_activa')
          .eq('id_tienda', storeId)
          .maybeSingle(),
      // Mesas: se crean desde ventiq_app, aquí solo se cuentan.
      _supabase.from('app_dat_mesas').select('id').eq('id_tienda', storeId).limit(1),
      // Datos de la tienda del paso 2 del asistente. `denominacion` es NOT NULL,
      // así que lo que se mira es si sigue siendo el provisional del alta.
      _supabase
          .from('app_dat_tienda')
          .select('denominacion, direccion, ubicacion, latitude')
          .eq('id', storeId)
          .maybeSingle(),
    ]);

    final almacenes = _filas(respuestas[0]);
    final tpvs = _filas(respuestas[1]);
    final productos = _filas(respuestas[2]);
    final trabajadores = _filas(respuestas[3]);
    final cocinas = _filas(respuestas[4]);
    final config = respuestas[5] is Map
        ? Map<String, dynamic>.from(respuestas[5] as Map)
        : const <String, dynamic>{};
    final mesas = _filas(respuestas[6]);
    final tienda = respuestas[7] is Map
        ? Map<String, dynamic>.from(respuestas[7] as Map)
        : const <String, dynamic>{};

    final idsAlmacenes = almacenes
        .map((a) => _entero(a['id']))
        .whereType<int>()
        .toList();
    final idsTpvs = tpvs.map((t) => _entero(t['id'])).whereType<int>().toList();
    final idsTrabajadores = trabajadores
        .map((t) => _entero(t['id']))
        .whereType<int>()
        .toList();

    // ── Consultas dependientes ───────────────────────────────────────────
    // Zonas: `app_dat_layout_almacen` cuelga del almacén, no de la tienda.
    final zonas = idsAlmacenes.isEmpty
        ? const <Map<String, dynamic>>[]
        : _filas(
            await _supabase
                .from('app_dat_layout_almacen')
                .select('id, id_almacen')
                .inFilter('id_almacen', idsAlmacenes)
                .isFilter('deleted_at', null)
                .limit(1),
          );

    // Vendedores asignados a una caja de esta tienda: es lo que permite abrir
    // turno y, por tanto, cobrar. `app_nom_medio_pago` es un catálogo global,
    // así que medir «medios de pago» no diría nada de esta tienda.
    final vendedores = idsTpvs.isEmpty
        ? const <Map<String, dynamic>>[]
        : _filas(
            await _supabase
                .from('app_dat_vendedor')
                .select('id, id_tpv, id_trabajador')
                .inFilter('id_tpv', idsTpvs)
                .limit(1),
          );

    final tieneVendedorAsignado = vendedores.any((v) {
      final idTrabajador = _entero(v['id_trabajador']);
      // Un vendedor sin trabajador de la tienda no cuenta: sería una fila
      // huérfana apuntando a un TPV de aquí.
      return idTrabajador == null || idsTrabajadores.contains(idTrabajador);
    });

    return HechosTienda(
      tieneAlmacen: almacenes.isNotEmpty,
      tieneZona: zonas.isNotEmpty,
      tieneTpv: tpvs.isNotEmpty,
      tieneProducto: productos.isNotEmpty,
      tieneVendedorAsignado: tieneVendedorAsignado,
      tienePersonal: trabajadores.isNotEmpty,
      tieneCocina: cocinas.isNotEmpty || almacenes.any((a) => a['es_cocina'] == true),
      tieneMesa: mesas.isNotEmpty,
      // Sin fila de configuración los dos flags son false: la tienda no está en
      // modo restaurante porque nadie lo encendió.
      modoRestaurante: config['modo_restaurante'] == true,
      cocinaActiva: config['cocina_activa'] == true,
      almacenesConvertiblesACocina: _contarAlmacenesConvertibles(almacenes, tpvs),
      tieneNombreTienda: !_esNombreProvisional(_textoONulo(tienda['denominacion'])),
      tieneDireccion: _textoONulo(tienda['direccion']) != null,
      tieneUbicacion:
          _textoONulo(tienda['ubicacion']) != null ||
          _textoONulo(tienda['latitude']) != null,
    );
  }

  /// El alta progresiva nombra la tienda `Tienda de <nombre>` (o `Mi tienda`) en
  /// el paso 1, porque `denominacion` es NOT NULL y el nombre real se pregunta
  /// en el paso 2. Mientras siga con ese texto, la tarea de nombre está
  /// pendiente: si no, el cliente vería «Tienda de Ana» para siempre como si la
  /// hubiera elegido él.
  static bool _esNombreProvisional(String? nombre) {
    if (nombre == null) return true;
    final n = nombre.trim();
    if (n.isEmpty) return true;
    if (n == 'Mi tienda') return true;
    return n.startsWith('Tienda de ');
  }

  /// Réplica de `CocinaService.listarAlmacenesConvertibles()`
  /// (`cocina_service.dart:549-572`): almacenes vivos, que no sean ya cocina y
  /// que **no** abastezcan a ningún TPV.
  ///
  /// Se replica en vez de llamar al servicio de cocina para no hacer otra
  /// ronda de consultas con los mismos datos ya en la mano. Si esa regla
  /// cambia, hay que cambiar las dos: el número alimenta el bloqueo de la tarea
  /// `cocina`, y `fn_crear_cocina` falla con `ALMACEN_ES_DE_TPV` cuando sale 0.
  int _contarAlmacenesConvertibles(
    List<Map<String, dynamic>> almacenes,
    List<Map<String, dynamic>> tpvs,
  ) {
    final almacenesDeTpv = tpvs
        .map((t) => _entero(t['id_almacen']))
        .whereType<int>()
        .toSet();

    return almacenes.where((a) {
      final id = _entero(a['id']);
      return a['es_cocina'] != true && !almacenesDeTpv.contains(id);
    }).length;
  }

  // ══════════════════════════════════════════════════════════════════════
  // Checklist
  // ══════════════════════════════════════════════════════════════════════

  /// El checklist de la tienda activa, ya resuelto.
  ///
  /// Combina los tres ingredientes de [construirTareas] (tipo declarado, hechos
  /// reales y estados guardados) y devuelve la lista con el estado final de
  /// cada tarea. La pantalla no tiene que volver a calcular nada: solo pintar y
  /// llamar a `puedeActivar`/`progreso`.
  Future<List<TareaOnboarding>> listarTareas() async {
    final estado = await leerEstadoTienda();
    final hechos = await leerHechos();
    final guardadas = await _leerEstadosGuardados();

    return construirTareas(
      tipoNegocio: estado.tipoNegocio,
      hechos: hechos,
      estadosGuardados: guardadas,
    );
  }

  /// Estados que la pantalla ya persistió, por clave de tarea.
  ///
  /// Solo hacen falta para las tareas sin hecho propio (`servicentro_tpv`,
  /// `inventario`, `moneda`) y para las que el usuario omitió: en las demás
  /// manda el hecho, que es el criterio del modelo Stripe.
  Future<Map<String, EstadoTarea>> _leerEstadosGuardados() async {
    final storeId = await _requireStoreId();

    final filas = await _supabase
        .from('app_dat_tarea_onboarding')
        .select('clave, estado')
        .eq('id_tienda', storeId);

    return {
      for (final fila in _filas(filas))
        if (_textoONulo(fila['clave']) != null)
          fila['clave'].toString(): EstadoTarea.desdeValor(
            _textoONulo(fila['estado']),
          ),
    };
  }

  /// Guarda el estado de una tarea concreta (upsert por `(id_tienda, clave)`).
  ///
  /// `completada_en` se rellena solo al pasar a `completada` y se limpia al
  /// volver atrás: una fecha de finalización en una tarea pendiente sería una
  /// mentira en los reportes. `updated_at` lo pone el trigger
  /// `trg_tarea_onboarding_touch` de la fase 1, no el cliente.
  Future<void> marcarTarea(String clave, EstadoTarea estado) async {
    final storeId = await _requireStoreId();
    final claveLimpia = clave.trim();
    if (claveLimpia.isEmpty) {
      throw OnboardingException(
        'La tarea no tiene clave: no se puede guardar.',
        codigo: 'CLAVE_VACIA',
      );
    }

    await _supabase.from('app_dat_tarea_onboarding').upsert({
      'id_tienda': storeId,
      'clave': claveLimpia,
      'estado': estado.valor,
      'completada_en': estado == EstadoTarea.completada
          ? DateTime.now().toUtc().toIso8601String()
          : null,
    }, onConflict: 'id_tienda,clave');
  }

  // ══════════════════════════════════════════════════════════════════════
  // Go Live (fase 4)
  // ══════════════════════════════════════════════════════════════════════

  /// Activa la tienda llamando a `fn_m01_activar_tienda`.
  ///
  /// La validación de los cuatro esenciales vive **en el servidor**, no aquí:
  /// si dependiera del cliente, una versión vieja de la app podría activar una
  /// tienda sin almacén. La RPC devuelve el resumen que ya calculó, así que
  /// cliente y servidor no pueden discrepar sobre qué conteos hay.
  ///
  /// Lanza [OnboardingException] con el mensaje accionable del servidor cuando
  /// falta algo (`codigo: 'ESENCIALES_FALTANTES'`) o cuando la tienda está
  /// suspendida (`codigo: 'TIENDA_SUSPENDIDA'`).
  Future<Map<String, dynamic>> activarTienda() async {
    final storeId = await _requireStoreId();

    try {
      final respuesta = await _supabase.rpc(
        'fn_m01_activar_tienda',
        params: {'p_id_tienda': storeId},
      );

      return respuesta is Map
          ? Map<String, dynamic>.from(respuesta)
          : <String, dynamic>{};
    } catch (e) {
      final texto = e.toString();
      final faltan = texto.contains('22023');
      final suspendida = texto.contains('suspendida');

      throw OnboardingException(
        _mensajeDeErrorPostgres(texto),
        codigo: suspendida
            ? 'TIENDA_SUSPENDIDA'
            : faltan
            ? 'ESENCIALES_FALTANTES'
            : 'ACTIVACION_FALLIDA',
        datos: {'detalle': texto},
      );
    }
  }

  /// PostgREST envuelve el `RAISE EXCEPTION` en un texto largo
  /// (`PostgrestException(message: ..., code: 22023, details: ...)`). Se queda
  /// el mensaje útil y se le quitan los prefijos, para que la UI no enseñe
  /// `PostgrestException(...)` al cliente.
  static String _mensajeDeErrorPostgres(String crudo) {
    final coincidencia = RegExp(
      r'message:\s*(.+?)(?:,\s*code:|,\s*details:|\))',
      dotAll: true,
    ).firstMatch(crudo);
    final mensaje = (coincidencia?.group(1) ?? crudo).trim();
    return mensaje
        .replaceAll(RegExp(r'^Exception:\s*'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  // ══════════════════════════════════════════════════════════════════════
  // Datos de la tienda (paso 2 del asistente)
  // ══════════════════════════════════════════════════════════════════════

  /// Guarda los datos de la tienda que el panel pide en línea.
  ///
  /// Mismo camino que `_guardarAvanceParcial` del asistente: `update` directo a
  /// `app_dat_tienda`. Necesita `GRANT UPDATE ... TO authenticated`, que es el
  /// H15 del registro de hallazgos; sin él Postgres responde 42501 antes de
  /// mirar la RLS.
  ///
  /// **Nunca escribe `estado`**: esa columna es el código de provincia.
  Future<void> guardarDatosTienda({
    String? nombre,
    String? direccion,
    String? ubicacion,
  }) async {
    final storeId = await _requireStoreId();

    final cambios = <String, dynamic>{};
    final n = nombre?.trim();
    final d = direccion?.trim();
    final u = ubicacion?.trim();
    if (n != null && n.isNotEmpty) cambios['denominacion'] = n;
    if (d != null && d.isNotEmpty) cambios['direccion'] = d;
    if (u != null && u.isNotEmpty) cambios['ubicacion'] = u;

    if (cambios.isEmpty) return;

    try {
      await _supabase
          .from('app_dat_tienda')
          .update(cambios)
          .eq('id', storeId);
    } catch (e) {
      throw OnboardingException(
        'No se pudieron guardar los datos de la tienda: '
        '${_mensajeDeErrorPostgres(e.toString())}',
        codigo: e.toString().contains('42501') ? 'PERMISO' : 'GUARDADO',
        datos: {'detalle': e.toString()},
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // Utilidades
  // ══════════════════════════════════════════════════════════════════════

  /// Normaliza la respuesta de un `select`: PostgREST devuelve una lista, pero
  /// el tipo estático de `dynamic` no lo garantiza.
  static List<Map<String, dynamic>> _filas(Object? respuesta) {
    if (respuesta is! List) return const [];
    return respuesta.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  static int? _entero(Object? valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    if (valor is String) return int.tryParse(valor);
    return null;
  }

  static String? _textoONulo(Object? valor) {
    final texto = valor?.toString().trim();
    return (texto == null || texto.isEmpty) ? null : texto;
  }

  /// Postgres devuelve `timestamptz` como ISO-8601 con offset; se conserva el
  /// instante tal cual (UTC) y que la UI lo formatee en local.
  static DateTime? _fecha(Object? valor) {
    if (valor == null) return null;
    if (valor is DateTime) return valor;
    return DateTime.tryParse(valor.toString());
  }
}

/// Error de negocio del alta progresiva.
///
/// [codigo] es estable (`NO_STORE`, `TIPO_INVALIDO`, `CLAVE_VACIA`) para que la
/// UI reaccione distinto según el caso en vez de mostrar un texto genérico.
class OnboardingException implements Exception {
  OnboardingException(this.mensaje, {this.codigo, this.datos});

  final String mensaje;
  final String? codigo;
  final Map<String, dynamic>? datos;

  @override
  String toString() => mensaje;
}

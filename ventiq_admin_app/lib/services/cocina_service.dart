import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cocina.dart';
import 'user_preferences_service.dart';

/// Acceso a las RPC de cocinas (Fase 1 del plan restaurante/cocina).
///
/// Todas las RPC del backend validan el acceso a la tienda con
/// `check_user_has_access_to_tienda`, así que un error de permisos llega como
/// excepción de Postgres y se traduce a [CocinaException].
///
/// Convención del backend: cada RPC devuelve jsonb con `status` =
/// 'success' | 'error'. Aquí se comprueba ese campo y se lanza
/// [CocinaException] con el `error_code` para que la UI pueda distinguir casos
/// (nombre duplicado, cocina con productos, etc.) en vez de mostrar un texto
/// genérico.
class CocinaService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final UserPreferencesService _userPrefs = UserPreferencesService();

  /// Tienda activa del usuario.
  static Future<int> _requireStoreId() async {
    final storeId = await _userPrefs.getIdTienda();
    if (storeId == null) {
      throw CocinaException(
        'No se pudo determinar la tienda actual. Vuelve a iniciar sesión.',
        codigo: 'NO_STORE',
      );
    }
    return storeId;
  }

  /// Valida la envoltura `{status, ...}` que devuelven las RPC.
  static Map<String, dynamic> _unwrap(dynamic response, String operacion) {
    if (response is! Map) {
      throw CocinaException('Respuesta inesperada al $operacion');
    }
    final mapa = Map<String, dynamic>.from(response);
    if (mapa['status'] == 'error') {
      throw CocinaException(
        mapa['message']?.toString() ?? 'Error al $operacion',
        codigo: mapa['error_code']?.toString(),
        datos: mapa,
      );
    }
    return mapa;
  }

  // ══════════════════════════════════════════════════════════════════════
  // Cocinas
  // ══════════════════════════════════════════════════════════════════════

  /// Cocinas de la tienda activa, con contadores y TPVs ligados.
  static Future<List<Cocina>> listarCocinas({bool soloActivas = false}) async {
    final storeId = await _requireStoreId();

    final response = await _supabase.rpc(
      'fn_listar_cocinas',
      params: {'p_id_tienda': storeId, 'p_solo_activas': soloActivas},
    );

    if (response is! List) return const [];

    return response
        .whereType<Map<String, dynamic>>()
        .map(Cocina.fromJson)
        .toList();
  }

  /// Crea una cocina. El backend crea el almacén (con `es_cocina = true`) y un
  /// layout inicial, salvo que se pase [idAlmacenExistente] para convertir un
  /// almacén que ya existe.
  ///
  /// Devuelve el id de la cocina creada.
  static Future<int> crearCocina({
    required String denominacion,
    String? descripcion,
    String? impresora,
    int orden = 0,
    int? idAlmacenExistente,
    String? denominacionLayout,
    int? idTipoLayout,
  }) async {
    final storeId = await _requireStoreId();

    final response = await _supabase.rpc(
      'fn_crear_cocina',
      params: {
        'p_id_tienda': storeId,
        'p_denominacion': denominacion.trim(),
        'p_descripcion': descripcion?.trim(),
        'p_impresora': impresora?.trim(),
        'p_orden': orden,
        'p_id_almacen_existente': idAlmacenExistente,
        if (denominacionLayout != null && denominacionLayout.trim().isNotEmpty)
          'p_denominacion_layout': denominacionLayout.trim(),
        if (idTipoLayout != null) 'p_id_tipo_layout': idTipoLayout,
      },
    );

    final mapa = _unwrap(response, 'crear la cocina');
    return (mapa['id_cocina'] as num).toInt();
  }

  /// Actualiza los datos de una cocina. Solo se envían los campos no nulos.
  ///
  /// No permite cambiar el almacén: mover una cocina a otro almacén dejaría su
  /// inventario y sus tandas huérfanos.
  static Future<void> actualizarCocina({
    required int idCocina,
    String? denominacion,
    String? descripcion,
    String? impresora,
    int? orden,
    bool? activa,
  }) async {
    final response = await _supabase.rpc(
      'fn_actualizar_cocina',
      params: {
        'p_id_cocina': idCocina,
        'p_denominacion': denominacion?.trim(),
        'p_descripcion': descripcion?.trim(),
        'p_impresora': impresora?.trim(),
        'p_orden': orden,
        'p_activa': activa,
      },
    );

    _unwrap(response, 'actualizar la cocina');
  }

  /// Activa o desactiva una cocina. Una cocina inactiva no recibe comandas
  /// aunque siga ligada a sus TPVs.
  static Future<void> cambiarEstadoCocina({
    required int idCocina,
    required bool activa,
  }) {
    return actualizarCocina(idCocina: idCocina, activa: activa);
  }

  /// Elimina una cocina (soft-delete).
  ///
  /// Si tiene productos asignados falla con `COCINA_CON_PRODUCTOS`, salvo que
  /// [forzar] sea true, en cuyo caso los desasigna. El almacén y su inventario
  /// se conservan siempre.
  ///
  /// Devuelve el detalle de lo liberado para poder informar al usuario.
  static Future<Map<String, dynamic>> eliminarCocina({
    required int idCocina,
    bool forzar = false,
  }) async {
    final response = await _supabase.rpc(
      'fn_eliminar_cocina',
      params: {'p_id_cocina': idCocina, 'p_forzar': forzar},
    );

    return _unwrap(response, 'eliminar la cocina');
  }

  // ══════════════════════════════════════════════════════════════════════
  // TPV ↔ cocina
  // ══════════════════════════════════════════════════════════════════════

  /// Liga un TPV a una cocina. Es idempotente: ligar dos veces no falla.
  ///
  /// Devuelve true si el vínculo se creó ahora, false si ya existía.
  static Future<bool> asignarTpvCocina({
    required int idTpv,
    required int idCocina,
  }) async {
    final response = await _supabase.rpc(
      'fn_asignar_tpv_cocina',
      params: {'p_id_tpv': idTpv, 'p_id_cocina': idCocina},
    );

    final mapa = _unwrap(response, 'ligar el TPV con la cocina');
    return mapa['ya_existia'] != true;
  }

  /// Desliga un TPV de una cocina.
  ///
  /// Devuelve cuántos platos deja de ver ese TPV, para poder avisar.
  static Future<int> desasignarTpvCocina({
    required int idTpv,
    required int idCocina,
  }) async {
    final response = await _supabase.rpc(
      'fn_desasignar_tpv_cocina',
      params: {'p_id_tpv': idTpv, 'p_id_cocina': idCocina},
    );

    final mapa = _unwrap(response, 'desligar el TPV de la cocina');
    return (mapa['productos_afectados'] as num?)?.toInt() ?? 0;
  }

  /// Sincroniza el conjunto de cocinas de un TPV con [idsCocinasDeseadas].
  ///
  /// Calcula el diff contra lo que ya está ligado para no borrar y recrear
  /// vínculos que no cambian. Lo usa el diálogo de "ligar TPV ↔ cocinas", donde
  /// el usuario marca y desmarca varias antes de guardar.
  static Future<void> sincronizarCocinasDeTpv({
    required int idTpv,
    required Set<int> idsCocinasDeseadas,
  }) async {
    final actuales = (await listarCocinasDeTpv(idTpv)).map((c) => c.id).toSet();

    final aAgregar = idsCocinasDeseadas.difference(actuales);
    final aQuitar = actuales.difference(idsCocinasDeseadas);

    for (final idCocina in aAgregar) {
      await asignarTpvCocina(idTpv: idTpv, idCocina: idCocina);
    }
    for (final idCocina in aQuitar) {
      await desasignarTpvCocina(idTpv: idTpv, idCocina: idCocina);
    }
  }

  /// Sincroniza el conjunto de TPVs de UNA cocina (la vista inversa).
  ///
  /// Se usa desde la tarjeta de la cocina, donde el usuario marca qué TPVs le
  /// envían pedidos. Recibe [idsTpvsActuales] porque quien llama ya los tiene
  /// cargados (vienen en `fn_listar_cocinas`), y así se evita una consulta.
  static Future<void> sincronizarCocinasDeTpvPorCocina({
    required int idCocina,
    required Set<int> idsTpvsDeseados,
    required Set<int> idsTpvsActuales,
  }) async {
    final aAgregar = idsTpvsDeseados.difference(idsTpvsActuales);
    final aQuitar = idsTpvsActuales.difference(idsTpvsDeseados);

    for (final idTpv in aAgregar) {
      await asignarTpvCocina(idTpv: idTpv, idCocina: idCocina);
    }
    for (final idTpv in aQuitar) {
      await desasignarTpvCocina(idTpv: idTpv, idCocina: idCocina);
    }
  }

  /// Cocinas ACTIVAS que puede usar un TPV.
  ///
  /// Devuelve la forma reducida que expone `fn_listar_cocinas_tpv` (sin
  /// contadores), envuelta en [Cocina] para reutilizar el modelo.
  static Future<List<Cocina>> listarCocinasDeTpv(int idTpv) async {
    final response = await _supabase.rpc(
      'fn_listar_cocinas_tpv',
      params: {'p_id_tpv': idTpv},
    );

    final mapa = _unwrap(response, 'consultar las cocinas del TPV');
    final cocinas = mapa['cocinas'];
    if (cocinas is! List) return const [];

    return cocinas.whereType<Map<String, dynamic>>().map((json) {
      // fn_listar_cocinas_tpv no trae contadores ni almacén con nombre.
      return Cocina(
        id: (json['id_cocina'] as num?)?.toInt() ?? 0,
        denominacion: json['denominacion']?.toString() ?? 'Sin nombre',
        idAlmacen: (json['id_almacen'] as num?)?.toInt() ?? 0,
        almacen: '',
        impresora: json['impresora']?.toString(),
        orden: (json['orden'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  // ══════════════════════════════════════════════════════════════════════
  // Disponibilidad
  // ══════════════════════════════════════════════════════════════════════

  /// Cuántas unidades de [idProducto] se pueden servir ahora desde [idTpv].
  ///
  /// Distingue producto de barra, `por_tanda` (stock terminado) y `al_pedido`
  /// (límite según la materia prima de la cocina), y valida el enrutamiento:
  /// si el TPV no está ligado a la cocina del plato devuelve `vendibleAqui`
  /// false con `errorCode` `COCINA_NO_LIGADA`.
  static Future<DisponibilidadPlato> disponibilidadPlato({
    required int idProducto,
    required int idTpv,
  }) async {
    final response = await _supabase.rpc(
      'fn_disponibilidad_plato',
      params: {'p_id_producto': idProducto, 'p_id_tpv': idTpv},
    );

    if (response is! Map) {
      throw CocinaException('Respuesta inesperada al consultar disponibilidad');
    }
    final mapa = Map<String, dynamic>.from(response);

    // Los casos "no vendible aquí" llegan con status success y disponible 0:
    // son respuestas válidas, no errores. Solo un status error es fallo real.
    if (mapa['status'] == 'error') {
      throw CocinaException(
        mapa['message']?.toString() ?? 'Error al consultar disponibilidad',
        codigo: mapa['error_code']?.toString(),
        datos: mapa,
      );
    }

    return DisponibilidadPlato.fromJson(mapa);
  }

  // ══════════════════════════════════════════════════════════════════════
  // Producto ↔ cocina
  // ══════════════════════════════════════════════════════════════════════

  /// Asigna cocina y modo de elaboración a un producto.
  ///
  /// Pasar [idCocina] null desasigna el producto de toda cocina (vuelve a ser
  /// producto de barra). El trigger `trg_validar_producto_cocina` del backend
  /// impide asignar una cocina de otra tienda.
  static Future<void> asignarCocinaAProducto({
    required int idProducto,
    required int? idCocina,
    ModoElaboracion? modoElaboracion,
  }) async {
    final storeId = await _requireStoreId();

    final datos = <String, dynamic>{'id_cocina': idCocina};
    if (modoElaboracion != null) {
      datos['modo_elaboracion'] = modoElaboracion.valor;
    }

    await _supabase
        .from('app_dat_producto')
        .update(datos)
        .eq('id', idProducto)
        .eq('id_tienda', storeId);
  }

  /// Productos asignados a una cocina, para la pantalla de detalle.
  static Future<List<Map<String, dynamic>>> listarProductosDeCocina(
    int idCocina,
  ) async {
    final response = await _supabase
        .from('app_dat_producto')
        .select(
          'id, denominacion, sku, um, es_elaborado, es_vendible, modo_elaboracion, imagen',
        )
        .eq('id_cocina', idCocina)
        .isFilter('deleted_at', null)
        .order('denominacion');

    return List<Map<String, dynamic>>.from(response);
  }

  /// Elaborados de la tienda que todavía no tienen cocina asignada.
  ///
  /// Es la lista que se ofrece al asignar platos a una cocina recién creada.
  static Future<List<Map<String, dynamic>>> listarElaboradosSinCocina() async {
    final storeId = await _requireStoreId();

    final response = await _supabase
        .from('app_dat_producto')
        .select('id, denominacion, sku, um, modo_elaboracion')
        .eq('id_tienda', storeId)
        .eq('es_elaborado', true)
        .isFilter('id_cocina', null)
        .isFilter('deleted_at', null)
        .order('denominacion');

    return List<Map<String, dynamic>>.from(response);
  }

  // ══════════════════════════════════════════════════════════════════════
  // Personal de cocina (jefe / cocinero)
  // ══════════════════════════════════════════════════════════════════════

  /// Personal asignado a una cocina, con su grado (jefe o cocinero).
  static Future<List<Map<String, dynamic>>> listarPersonalCocina(
    int idCocina,
  ) async {
    final response = await _supabase.rpc(
      'fn_listar_personal_cocina',
      params: {'p_id_cocina': idCocina},
    );

    final mapa = _unwrap(response, 'listar el personal de la cocina');

    final lista = mapa['personal'];
    if (lista is! List) return const [];

    return lista
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Cocinas donde está asignado un trabajador (por su uuid de usuario).
  ///
  /// Se consulta directo a la tabla porque `fn_cocinas_del_usuario` resuelve el
  /// alcance del usuario AUTENTICADO, y aquí el admin pregunta por OTRO.
  static Future<List<Map<String, dynamic>>> cocinasDeTrabajador(
    String uuidUsuario,
  ) async {
    final response = await _supabase
        .from('app_dat_jefe_cocina')
        .select('id, id_cocina, es_jefe, app_dat_cocina(denominacion, id_tienda)')
        .eq('uuid', uuidUsuario);

    return List<Map<String, dynamic>>.from(response);
  }

  // ══════════════════════════════════════════════════════════════════════
  // Cocina por defecto de una categoría
  // ══════════════════════════════════════════════════════════════════════

  /// Define (o quita con [idCocina] null) la cocina por defecto de una categoría.
  ///
  /// Es una SUGERENCIA: los platos que ya tienen cocina propia no se tocan, ni
  /// aquí ni en el bulk.
  static Future<Map<String, dynamic>> asignarCocinaACategoria({
    required int idCategoria,
    int? idCocina,
  }) async {
    final storeId = await _requireStoreId();

    final response = await _supabase.rpc(
      'fn_asignar_cocina_categoria',
      params: {
        'p_id_tienda': storeId,
        'p_id_categoria': idCategoria,
        'p_id_cocina': idCocina,
      },
    );

    return _unwrap(response, 'asignar la cocina a la categoría');
  }

  /// Manda a la cocina de la categoría todos sus platos que NO tengan cocina.
  ///
  /// Devuelve cuántos tocó y cuántos respetó por tener asignación propia.
  static Future<Map<String, dynamic>> aplicarCocinaCategoriaAPlatos({
    required int idCategoria,
    ModoElaboracion? modoElaboracion,
    bool soloElaborados = true,
  }) async {
    final storeId = await _requireStoreId();

    final response = await _supabase.rpc(
      'fn_aplicar_cocina_categoria_a_platos',
      params: {
        'p_id_tienda': storeId,
        'p_id_categoria': idCategoria,
        'p_modo_elaboracion': modoElaboracion?.valor,
        'p_solo_elaborados': soloElaborados,
      },
    );

    return _unwrap(response, 'aplicar la cocina de la categoría');
  }

  /// Categorías de la tienda con su cocina por defecto (si tienen).
  static Future<List<Map<String, dynamic>>> listarCategoriasConCocina() async {
    final storeId = await _requireStoreId();

    final response = await _supabase
        .from('app_dat_categoria_tienda')
        .select('id, id_categoria, id_cocina, app_dat_categoria(denominacion)')
        .eq('id_tienda', storeId);

    return List<Map<String, dynamic>>.from(response);
  }

  /// Qué cocina le correspondería a un producto por sus categorías.
  ///
  /// `ambiguo: true` significa que el producto está en varias categorías con
  /// cocinas distintas y la UI debería decirlo en vez de elegir en silencio.
  static Future<Map<String, dynamic>?> cocinaPorDefectoDeProducto(
    int idProducto,
  ) async {
    final response = await _supabase.rpc(
      'fn_cocina_por_defecto_producto',
      params: {'p_id_producto': idProducto},
    );

    if (response is! Map) return null;
    final mapa = Map<String, dynamic>.from(response);
    if (mapa['status'] != 'success') return null;
    return mapa;
  }

  // ══════════════════════════════════════════════════════════════════════
  // Configuración de tienda
  // ══════════════════════════════════════════════════════════════════════

  /// Lee los flags de restaurante/cocina de la tienda activa.
  ///
  /// `cocina_activa` requiere `modo_restaurante`: sin mesas no hay comandas.
  static Future<({bool modoRestaurante, bool cocinaActiva})>
  leerConfigCocina() async {
    final storeId = await _requireStoreId();

    final response = await _supabase
        .from('app_dat_configuracion_tienda')
        .select('modo_restaurante, cocina_activa')
        .eq('id_tienda', storeId)
        .maybeSingle();

    return (
      modoRestaurante: response?['modo_restaurante'] == true,
      cocinaActiva: response?['cocina_activa'] == true,
    );
  }

  /// Activa o desactiva el módulo de cocina para la tienda activa.
  ///
  /// Al ACTIVAR, si la tienda todavía no está en modo restaurante se activa
  /// también: las comandas salen de las cuentas de mesa, así que sin mesas el
  /// módulo quedaría a medias. Se hace en el mismo update para que no queden
  /// estados intermedios si algo falla.
  ///
  /// Al DESACTIVAR no se toca `modo_restaurante`: una tienda puede seguir
  /// operando con mesas sin usar cocinas.
  ///
  /// Devuelve true si además hubo que activar el modo restaurante, para que la
  /// UI pueda avisarlo.
  static Future<bool> cambiarCocinaActiva(bool activa) async {
    final storeId = await _requireStoreId();

    if (!activa) {
      await _supabase
          .from('app_dat_configuracion_tienda')
          .update({'cocina_activa': false})
          .eq('id_tienda', storeId);
      return false;
    }

    final config = await leerConfigCocina();
    final activarRestaurante = !config.modoRestaurante;

    await _supabase
        .from('app_dat_configuracion_tienda')
        .update({
          'cocina_activa': true,
          if (activarRestaurante) 'modo_restaurante': true,
        })
        .eq('id_tienda', storeId);

    return activarRestaurante;
  }

  /// Almacenes de la tienda que podrían convertirse en cocina.
  ///
  /// Excluye los que ya son cocina y los que abastecen a un TPV: si el TPV
  /// vendiera del mismo almacén que produce, se pierde la separación
  /// barra/cocina. El backend rechaza esos casos, pero filtrarlos aquí evita
  /// ofrecer opciones que van a fallar.
  static Future<List<Map<String, dynamic>>> listarAlmacenesConvertibles() async {
    final storeId = await _requireStoreId();

    final almacenes = await _supabase
        .from('app_dat_almacen')
        .select('id, denominacion, es_cocina')
        .eq('id_tienda', storeId)
        .isFilter('deleted_at', null)
        .order('denominacion');

    final tpvs = await _supabase
        .from('app_dat_tpv')
        .select('id_almacen')
        .eq('id_tienda', storeId);

    final almacenesDeTpv = {
      for (final t in tpvs) (t['id_almacen'] as num?)?.toInt(),
    };

    return List<Map<String, dynamic>>.from(almacenes).where((a) {
      final id = (a['id'] as num?)?.toInt();
      return a['es_cocina'] != true && !almacenesDeTpv.contains(id);
    }).toList();
  }
}

/// Error de negocio devuelto por una RPC de cocinas.
///
/// [codigo] es el `error_code` estable del backend (`DUPLICATE_COCINA`,
/// `COCINA_CON_PRODUCTOS`, `ALMACEN_ES_DE_TPV`, ...), pensado para que la UI
/// reaccione distinto según el caso.
class CocinaException implements Exception {
  CocinaException(this.mensaje, {this.codigo, this.datos});

  final String mensaje;
  final String? codigo;
  final Map<String, dynamic>? datos;

  /// Cuántos productos bloquean el borrado (solo con `COCINA_CON_PRODUCTOS`).
  int get productosBloqueando =>
      (datos?['productos'] as num?)?.toInt() ?? 0;

  @override
  String toString() => mensaje;
}

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/comanda.dart';
import '../models/tanda.dart';
import '../utils/uuid_generator.dart';
import 'cocina_offline_queue.dart';

/// Servicio del KDS (Kitchen Display System).
///
/// Todas las RPC resuelven el alcance en el servidor a partir del usuario
/// autenticado (`fn_cocinas_del_usuario`), así que aquí NO hay que filtrar por
/// cocina ni confiar en un id que venga de la UI: un jefe de cocina que pida
/// una estación ajena recibe "Acceso denegado" desde Postgres.
class ComandaService {
  static final ComandaService _instance = ComandaService._internal();
  factory ComandaService() => _instance;
  ComandaService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Misma clave si se vuelve a marcar el mismo plato al mismo estado.
  final Map<String, String> _uuidEstadoItem = {};

  /// Cocinas que el usuario puede operar. Vacío = no tiene ninguna asignada,
  /// que es distinto de un error: la UI debe explicarlo en vez de fallar.
  Future<List<CocinaAsignada>> listarMisCocinas() async {
    final response = await _supabase.rpc('fn_cocinas_del_usuario');

    if (response is! List) return const [];

    return response
        .whereType<Map>()
        .map((e) => CocinaAsignada.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Rol de cocina del usuario para decidir el home de la sesión.
  ///
  /// Devuelve `'jefe_cocina'`, `'cocinero'` o `''` (ninguno).
  ///
  /// Se filtra por `via`, no por tener cocinas: un gerente ve TODAS las cocinas
  /// de su tienda con `via = 'gerente'` / `'supervisor'` (medido: 2 cocinas), y
  /// mandarlo al KDS al entrar sería un error — su trabajo es la gestión de la
  /// tienda. Solo cuenta quien accede *por* su rol de cocina.
  ///
  /// Nunca lanza: si la consulta falla se devuelve `''` y la sesión se comporta
  /// como siempre. Un fallo de red no debe impedir entrar a la app.
  Future<String> rolDeCocina() async {
    try {
      final cocinas = await listarMisCocinas();

      final propias = cocinas
          .where((c) => c.via == 'jefe_cocina' || c.via == 'cocinero')
          .toList();

      if (propias.isEmpty) return '';
      return propias.any((c) => c.esJefe) ? 'jefe_cocina' : 'cocinero';
    } catch (e) {
      return '';
    }
  }

  /// Comandas de la cocina indicada, o de todas las del usuario si es `null`.
  ///
  /// Por defecto solo lo vivo (pendiente / preparando / listo). Para el
  /// historial pasar [EstadoComanda.cerrados].
  Future<List<Comanda>> listarComandas({
    int? idCocina,
    List<int>? estados,
    int limite = 100,
  }) async {
    final response = await _supabase.rpc(
      'fn_listar_comandas_cocina',
      params: {
        'p_id_cocina': idCocina,
        'p_estados': estados ?? EstadoComanda.vivos,
        'p_limite': limite,
      },
    );

    final mapa = _comoMapa(response);
    if (mapa == null) return const [];

    if (mapa['status'] != 'success') {
      throw ComandaException(
        mapa['error_code'] as String? ?? 'UNKNOWN',
        mapa['message'] as String? ?? 'No se pudieron cargar las comandas',
      );
    }

    final lista = mapa['comandas'];
    if (lista is! List) return const [];

    return lista
        .whereType<Map>()
        .map((e) => Comanda.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Cambia el estado de un plato suelto.
  ///
  /// El servidor valida la transición: cualquier avance vale, el retroceso solo
  /// un paso, y entregado/cancelado son terminales.
  Future<String> cambiarEstadoItem({
    required int idItem,
    required int nuevoEstado,
    String? clientUuid,
  }) async {
    final uuid =
        (clientUuid != null && clientUuid.isNotEmpty)
            ? clientUuid
            : UuidGenerator.v4();
    dynamic response;
    try {
      response = await _supabase.rpc(
        'fn_cambiar_estado_comanda_item_offline',
        params: {
          'p_client_uuid': uuid,
          'p_id_item': idItem,
          'p_nuevo_estado': nuevoEstado,
        },
      );
    } catch (e) {
      if (_rpcAusente(e, 'fn_cambiar_estado_comanda_item_offline')) {
        throw ComandaException(
          'RPC_AUSENTE',
          'fn_cambiar_estado_comanda_item_offline no está disponible. '
          'No se cambió el plato.',
        );
      }
      return _encolarEstadoSiEsRed(
        e,
        idItem: idItem,
        nuevoEstado: nuevoEstado,
        clientUuid: uuid,
      );
    }

    final mapa = _comoMapa(response);
    if (mapa == null) {
      throw ComandaException('FORMATO', 'Respuesta inesperada del servidor');
    }

    if (mapa['status'] != 'success') {
      throw ComandaException(
        mapa['error_code'] as String? ?? 'UNKNOWN',
        mapa['message'] as String? ?? 'No se pudo cambiar el estado',
      );
    }

    return mapa['message'] as String? ?? 'Estado actualizado';
  }

  /// Cambia el estado del ticket completo ("marchando todo").
  ///
  /// Cada plato sale por la RPC con clave. Entregado, cancelado o ya en ese
  /// estado se salta. Sin platos no hay una RPC de ticket con clave.
  Future<String> cambiarEstadoComanda({
    required int idComanda,
    required int nuevoEstado,
    List<int> idsItems = const [],
  }) async {
    if (idsItems.isEmpty) {
      throw ComandaException(
        'SIN_ITEMS',
        'El ticket $idComanda no tiene platos para marcar',
      );
    }
    return _cambiarEstadoPorPlatos(idsItems, nuevoEstado);
  }

  Future<String> _cambiarEstadoPorPlatos(List<int> idsItems, int nuevoEstado) async {
    var saltados = 0;
    var encolados = 0;
    for (final id in idsItems) {
      final clave = _uuidEstadoItem.putIfAbsent(
        '$id:$nuevoEstado',
        UuidGenerator.v4,
      );
      try {
        final msg = await cambiarEstadoItem(
          idItem: id,
          nuevoEstado: nuevoEstado,
          clientUuid: clave,
        );
        if (msg.startsWith('Sin conexión')) {
          encolados++;
        } else if (_estadoYaAplicado(msg)) {
          saltados++;
        }
      } on ComandaException {
        saltados++;
      }
    }
    if (encolados == idsItems.length) {
      return 'Sin conexión: el cambio quedó guardado y se enviará al recuperar la red';
    }
    if (saltados == 0 && encolados == 0) return 'Comanda actualizada';
    final notas = <String>[
      if (saltados > 0) '$saltados sin cambiar',
      if (encolados > 0) '$encolados pendientes de red',
    ];
    return 'Comanda actualizada (${notas.join(', ')})';
  }

  bool _estadoYaAplicado(String message) {
    final text = message.toLowerCase();
    return text.contains('ya estaba') || text.contains('ya se habia');
  }

  // ══════════════════════════════════════════════════════════════════════
  // Fase 4 · produccion por tandas
  //
  // Producir, cerrar y anular exigen ser JEFE de la cocina (lo valida el
  // backend con fn_usuario_puede_operar_cocina(id, true)). Los listados los
  // puede leer cualquier cocinero asignado.
  // ══════════════════════════════════════════════════════════════════════

  /// Catalogo de platos por tanda de una cocina: porciones hechas, cuantas mas
  /// se podrian producir y que ingrediente limita.
  Future<List<PlatoPorTanda>> listarPlatosPorTanda(int idCocina) async {
    final response = await _supabase.rpc(
      'fn_platos_por_tanda_cocina',
      params: {'p_id_cocina': idCocina},
    );

    final mapa = _comoMapa(response);
    if (mapa == null) return const [];

    if (mapa['status'] != 'success') {
      throw TandaException.fromJson(mapa);
    }

    final lista = mapa['platos'];
    if (lista is! List) return const [];

    return lista
        .whereType<Map>()
        .map((e) => PlatoPorTanda.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Lotes de produccion. Sin [idCocina] devuelve los de todas las cocinas del
  /// usuario. Por defecto solo los vivos.
  Future<List<Tanda>> listarTandas({
    int? idCocina,
    List<int>? estados,
    int dias = 2,
    int limite = 100,
  }) async {
    final response = await _supabase.rpc(
      'fn_listar_tandas_cocina',
      params: {
        'p_id_cocina': idCocina,
        'p_estados': estados ?? EstadoTanda.vivos,
        'p_dias': dias,
        'p_limite': limite,
      },
    );

    final mapa = _comoMapa(response);
    if (mapa == null) return const [];

    if (mapa['status'] != 'success') {
      throw TandaException.fromJson(mapa);
    }

    final lista = mapa['tandas'];
    if (lista is! List) return const [];

    return lista
        .whereType<Map>()
        .map((e) => Tanda.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Produce N porciones: consume la materia prima y mete el producto terminado.
  ///
  /// [ajusteMp] multiplica el consumo teorico de la receta, para cuando el
  /// cocinero echo mas o menos de lo que dice la ficha. 1.0 = lo que dice.
  Future<ProduccionResultado> producirTanda({
    required int idCocina,
    required int idProducto,
    required double porciones,
    String? notas,
    double ajusteMp = 1.0,
  }) async {
    final response = await _supabase.rpc(
      'fn_producir_tanda',
      params: {
        'p_id_cocina': idCocina,
        'p_id_producto': idProducto,
        'p_porciones': porciones,
        'p_notas': notas,
        'p_ajuste_mp': ajusteMp,
      },
    );

    final mapa = _comoMapa(response);
    if (mapa == null) {
      throw const TandaException('FORMATO', 'Respuesta inesperada del servidor');
    }

    if (mapa['status'] != 'success') {
      throw TandaException.fromJson(mapa);
    }

    return ProduccionResultado.fromJson(mapa);
  }

  /// Cierra el lote declarando la merma. [descartadas] > 0 exige [motivo].
  ///
  /// Devuelve el mensaje del servidor; el costo real por porcion servida viene
  /// en la respuesta y lo muestra la UI.
  Future<Map<String, dynamic>> cerrarTanda({
    required int idTanda,
    double descartadas = 0,
    String? motivo,
  }) async {
    final response = await _supabase.rpc(
      'fn_cerrar_tanda',
      params: {
        'p_id_tanda': idTanda,
        'p_descartadas': descartadas,
        'p_motivo': motivo,
      },
    );

    final mapa = _comoMapa(response);
    if (mapa == null) {
      throw const TandaException('FORMATO', 'Respuesta inesperada del servidor');
    }

    if (mapa['status'] != 'success') {
      throw TandaException.fromJson(mapa);
    }

    return mapa;
  }

  /// Deshace una produccion: devuelve la MP y retira las porciones.
  ///
  /// Solo si no ha salido ninguna porcion desde que se creo el lote. Si ya se
  /// sirvio algo el backend responde TANDA_YA_CONSUMIDA y hay que cerrar con
  /// merma en su lugar.
  Future<Map<String, dynamic>> anularTanda({
    required int idTanda,
    String? motivo,
  }) async {
    final response = await _supabase.rpc(
      'fn_anular_tanda',
      params: {'p_id_tanda': idTanda, 'p_motivo': motivo},
    );

    final mapa = _comoMapa(response);
    if (mapa == null) {
      throw const TandaException('FORMATO', 'Respuesta inesperada del servidor');
    }

    if (mapa['status'] != 'success') {
      throw TandaException.fromJson(mapa);
    }

    return mapa;
  }

  /// Una denegación no abre la función sin clave. «Schema cache» sí cuenta
  /// como ausente cuando el mensaje no es un 42501.
  bool _rpcAusente(Object error, String functionName) {
    final text = error.toString().toLowerCase();
    if (text.contains('42501') ||
        text.contains('insufficient_privilege') ||
        text.contains('permission denied') ||
        text.contains('acceso denegado')) {
      return false;
    }
    final fn = functionName.toLowerCase();
    return text.contains('pgrst202') ||
        text.contains('could not find the function') ||
        text.contains('schema cache') ||
        (text.contains('does not exist') && text.contains(fn));
  }

  bool _esErrorDeRed(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('socket') ||
        msg.contains('timeout') ||
        msg.contains('failed host lookup') ||
        msg.contains('connection') ||
        msg.contains('network');
  }

  /// Si la red se cortó, la cola conserva el mismo `client_uuid`. Una
  /// denegación o un rechazo de negocio se propaga.
  Future<String> _encolarEstadoSiEsRed(
    Object error, {
    required int idItem,
    required int nuevoEstado,
    required String clientUuid,
  }) async {
    if (!_esErrorDeRed(error)) throw error;
    await CocinaOfflineQueue().encolarCambioEstado(
      idComandaItem: idItem,
      nuevoEstado: nuevoEstado,
      clientUuid: clientUuid,
    );
    return 'Sin conexión: el cambio quedó guardado y se enviará al recuperar la red';
  }

  Map<String, dynamic>? _comoMapa(dynamic response) {
    if (response is Map) return Map<String, dynamic>.from(response);
    if (response is List && response.isNotEmpty && response.first is Map) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    return null;
  }
}

/// Error de negocio del KDS. `errorCode` permite distinguir un problema de
/// permisos (no debería reintentarse) de una transición inválida (la UI está
/// desincronizada y conviene recargar).
class ComandaException implements Exception {
  final String errorCode;
  final String mensaje;

  const ComandaException(this.errorCode, this.mensaje);

  /// La UI muestra un estado que ya no es el real: recargar.
  bool get requiereRecarga => errorCode == 'TRANSICION_INVALIDA';

  bool get esPermisos => mensaje.contains('Acceso denegado');

  @override
  String toString() => mensaje;
}

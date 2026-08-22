import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/comanda.dart';
import '../models/tanda.dart';

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
  }) async {
    final response = await _supabase.rpc(
      'fn_cambiar_estado_comanda_item',
      params: {'p_id_item': idItem, 'p_nuevo_estado': nuevoEstado},
    );

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
  /// Los platos ya entregados o cancelados se saltan sin fallar; el mensaje
  /// devuelto lo indica entre paréntesis.
  Future<String> cambiarEstadoComanda({
    required int idComanda,
    required int nuevoEstado,
  }) async {
    final response = await _supabase.rpc(
      'fn_cambiar_estado_comanda',
      params: {'p_id_comanda': idComanda, 'p_nuevo_estado': nuevoEstado},
    );

    final mapa = _comoMapa(response);
    if (mapa == null) {
      throw ComandaException('FORMATO', 'Respuesta inesperada del servidor');
    }

    if (mapa['status'] != 'success') {
      throw ComandaException(
        mapa['error_code'] as String? ?? 'UNKNOWN',
        mapa['message'] as String? ?? 'No se pudo cambiar la comanda',
      );
    }

    return mapa['message'] as String? ?? 'Comanda actualizada';
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

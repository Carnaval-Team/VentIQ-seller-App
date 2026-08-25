import 'package:supabase_flutter/supabase_flutter.dart';

/// Alcance de almacenes del usuario, para acotar las pantallas de inventario.
///
/// PARA QUÉ
/// --------
/// Un jefe de cocina tiene acceso a la tienda (lo da el guard
/// `check_user_has_access_to_tienda`), pero operativamente solo le corresponde
/// **el almacén de su cocina**. Sin esto, la recepción, el conteo y las
/// transferencias le ofrecen todos los almacenes de la tienda y puede mover
/// mercancía del almacén principal por error.
///
/// ESTO ES ACOTADO DE UI, NO SEGURIDAD
/// -----------------------------------
/// La seguridad real vive en las RPC (`fn_usuario_puede_operar_cocina`,
/// `check_user_has_access_to_tienda`). Aquí solo se decide qué ofrecer en un
/// desplegable. Por eso, si la consulta falla o devuelve vacío, se **degrada a
/// no filtrar**: preferir que un almacenero siga trabajando antes que dejar la
/// pantalla en blanco por un problema de red.
class AlmacenScopeService {
  static final AlmacenScopeService _instance =
      AlmacenScopeService._internal();
  factory AlmacenScopeService() => _instance;
  AlmacenScopeService._internal();

  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Cache por sesión: estas pantallas piden el alcance varias veces al abrir y
  /// el rol de un usuario no cambia a mitad de sesión.
  static List<AlmacenPermitido>? _cache;

  static void invalidarCache() => _cache = null;

  /// Almacenes que el usuario puede ver, con su origen y si puede operarlos.
  static Future<List<AlmacenPermitido>> almacenesPermitidos({
    int? idTienda,
    bool forzarRecarga = false,
  }) async {
    if (!forzarRecarga && _cache != null) return _cache!;

    try {
      final response = await _supabase.rpc(
        'fn_almacenes_del_usuario',
        params: {'p_id_tienda': idTienda},
      );

      if (response is! List) return const [];

      final lista = response
          .whereType<Map>()
          .map((e) => AlmacenPermitido.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      _cache = lista;
      return lista;
    } catch (e) {
      // Degradar sin filtrar: ver el comentario de la clase.
      return const [];
    }
  }

  /// ¿Hay que acotar las pantallas de inventario para este usuario?
  ///
  /// Gerente y supervisor ven todos los almacenes de su tienda: para ellos no se
  /// filtra nada y el comportamiento es el histórico. Solo se acota cuando el
  /// alcance del usuario viene **exclusivamente** de cocina o almacén.
  static Future<bool> debeAcotar({int? idTienda}) async {
    final permitidos = await almacenesPermitidos(idTienda: idTienda);
    if (permitidos.isEmpty) return false;
    return !permitidos.any((a) => a.esMandoDeTienda);
  }

  /// Ids permitidos, o `null` si no hay que acotar (ver [debeAcotar]).
  ///
  /// `null` significa "no filtres", que no es lo mismo que una lista vacía
  /// ("no tienes ninguno"). Los llamadores dependen de esa distinción.
  static Future<Set<int>?> idsPermitidos({int? idTienda}) async {
    if (!await debeAcotar(idTienda: idTienda)) return null;
    final permitidos = await almacenesPermitidos(idTienda: idTienda);
    return permitidos.map((a) => a.idAlmacen).toSet();
  }

  /// Ids donde además puede MOVER inventario.
  ///
  /// Un cocinero (`es_jefe = false`) ve el almacén de su cocina pero no puede
  /// operarlo: consulta sí, recepción y transferencias no.
  static Future<Set<int>?> idsOperables({int? idTienda}) async {
    if (!await debeAcotar(idTienda: idTienda)) return null;
    final permitidos = await almacenesPermitidos(idTienda: idTienda);
    return permitidos.where((a) => a.puedeOperar).map((a) => a.idAlmacen).toSet();
  }

  /// Filtra una lista cualquiera de almacenes por el alcance del usuario.
  ///
  /// [idDe] extrae el id de cada elemento. Se usa así porque cada pantalla
  /// maneja su propio modelo (`Warehouse`, `Map`, ...).
  static Future<List<T>> filtrar<T>(
    List<T> items,
    int? Function(T) idDe, {
    int? idTienda,
    bool soloOperables = false,
  }) async {
    final ids = soloOperables
        ? await idsOperables(idTienda: idTienda)
        : await idsPermitidos(idTienda: idTienda);

    if (ids == null) return items;

    return items.where((it) {
      final id = idDe(it);
      return id != null && ids.contains(id);
    }).toList();
  }

  /// La cocina del usuario, si su alcance viene de ahí. Sirve para titular las
  /// pantallas con "Cocina caliente" en vez del nombre técnico del almacén.
  static Future<AlmacenPermitido?> cocinaDelUsuario({int? idTienda}) async {
    final permitidos = await almacenesPermitidos(idTienda: idTienda);
    for (final a in permitidos) {
      if (a.esDeCocina) return a;
    }
    return null;
  }
}

class AlmacenPermitido {
  final int idAlmacen;
  final String denominacion;
  final int idTienda;
  final bool esCocina;
  final int? idCocina;
  final String? cocina;

  /// De qué rol viene el acceso: gerente, supervisor, almacenero, jefe_cocina,
  /// cocinero.
  final String origen;

  /// Si puede mover inventario. Un cocinero lo ve pero no lo mueve.
  final bool puedeOperar;

  const AlmacenPermitido({
    required this.idAlmacen,
    required this.denominacion,
    required this.idTienda,
    required this.esCocina,
    this.idCocina,
    this.cocina,
    required this.origen,
    required this.puedeOperar,
  });

  bool get esMandoDeTienda =>
      origen == 'gerente' || origen == 'supervisor';

  bool get esDeCocina => origen == 'jefe_cocina' || origen == 'cocinero';

  /// Nombre a mostrar: para una cocina, el nombre de la cocina dice más que el
  /// del almacén que la respalda.
  String get etiqueta => cocina ?? denominacion;

  factory AlmacenPermitido.fromJson(Map<String, dynamic> json) {
    return AlmacenPermitido(
      idAlmacen: (json['id_almacen'] as num).toInt(),
      denominacion: json['denominacion'] as String? ?? 'Almacén',
      idTienda: (json['id_tienda'] as num?)?.toInt() ?? 0,
      esCocina: json['es_cocina'] == true,
      idCocina: (json['id_cocina'] as num?)?.toInt(),
      cocina: json['cocina'] as String?,
      origen: json['origen'] as String? ?? 'desconocido',
      puedeOperar: json['puede_operar'] == true,
    );
  }
}

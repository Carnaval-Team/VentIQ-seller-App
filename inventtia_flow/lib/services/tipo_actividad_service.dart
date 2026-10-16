import 'package:supabase_flutter/supabase_flutter.dart';

/// Nodo de la taxonomía de servicios: `flow.nom_tipo_actividad_servicio`.
///
/// Desde la migración `47_categorias_reales_subcategorias.sql` la tabla tiene
/// **dos niveles** con una auto-referencia:
///
///   * [idPadre] `null` → **categoría** (nivel 1).
///   * [idPadre] con valor → **subcategoría** (nivel 2).
///
/// `app_dat_servicios.id_tipo_actividad` apunta SIEMPRE a la hoja: si el
/// servicio está en una subcategoría, esa fila es la subcategoría y su categoría
/// es la del padre. Por eso [codigo] de una subcategoría puede ser un código que
/// antes era de categoría (`transporte_omnibus`): es lo que mantiene funcionando
/// el flujo de pasajes sin tocar `LocalServicio.esTransporteOmnibus`.
class TipoActividad {
  const TipoActividad({
    required this.id,
    required this.codigo,
    required this.nombre,
    this.activo = true,
    this.idPadre,
    this.orden = 0,
  });

  final int id;

  /// Clave estable (`belleza`, `unas`, `transporte_omnibus`…). Viaja al cliente
  /// dentro de `cliente_obtener_servicios` y de `cliente_home_feed`, y la usan
  /// los detectores de transporte. **No cambia** al editar.
  final String codigo;

  final String nombre;
  final bool activo;

  /// `null` = categoría raíz. Con valor = subcategoría de esa categoría.
  final int? idPadre;

  /// Orden en el riel del Home y en la pantalla de gestión. Menor = antes.
  final int orden;

  bool get esSubcategoria => idPadre != null;

  TipoActividad copyWith({
    String? codigo,
    String? nombre,
    bool? activo,
    Object? idPadre = _sinCambio,
    int? orden,
  }) {
    return TipoActividad(
      id: id,
      codigo: codigo ?? this.codigo,
      nombre: nombre ?? this.nombre,
      activo: activo ?? this.activo,
      idPadre: identical(idPadre, _sinCambio) ? this.idPadre : idPadre as int?,
      orden: orden ?? this.orden,
    );
  }

  static const Object _sinCambio = Object();

  factory TipoActividad.fromJson(Map<String, dynamic> json) => TipoActividad(
    id: (json['id'] as num).toInt(),
    codigo: json['codigo'] as String? ?? '',
    nombre: json['nombre'] as String? ?? '',
    activo: (json['activo'] as bool?) ?? true,
    idPadre: (json['id_padre'] as num?)?.toInt(),
    orden: (json['orden'] as num?)?.toInt() ?? 0,
  );

  /// Código propuesto a partir del nombre: minúsculas, sin acentos y con `_`.
  ///
  /// Replica exactamente la normalización de `admin_guardar_tipo_actividad`
  /// (`translate` de acentos → `regexp_replace` de no alfanuméricos → `trim` de
  /// guiones bajos), para que lo que ve el usuario sea lo que se guarda.
  static String codigoDesdeNombre(String nombre) {
    const reemplazos = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    var valor = nombre.trim().toLowerCase();
    reemplazos.forEach((k, v) => valor = valor.replaceAll(k, v));
    valor = valor.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    valor = valor.replaceAll(RegExp(r'^_+|_+$'), '');
    return valor;
  }

  /// Mismo formato que valida `flow.admin_guardar_tipo_actividad`.
  static bool codigoValido(String codigo) =>
      RegExp(r'^[a-z0-9_]{3,64}$').hasMatch(codigo);
}

/// La taxonomía completa, ya ordenada e indexada.
///
/// Se construye en el cliente a partir de la única lectura de la tabla. Existe
/// para no repetir en cada pantalla la misma pregunta: "¿de qué categoría es
/// este servicio, y cómo se llama su subcategoría?".
class Taxonomia {
  Taxonomia(List<TipoActividad> todas)
    : todas = List<TipoActividad>.unmodifiable(todas) {
    for (final t in this.todas) {
      _porId[t.id] = t;
    }
  }

  static final Taxonomia vacia = Taxonomia(const <TipoActividad>[]);

  final List<TipoActividad> todas;
  final Map<int, TipoActividad> _porId = <int, TipoActividad>{};

  bool get estaVacia => todas.isEmpty;

  /// `true` cuando la lectura no trajo `id_padre` (migración 47 sin aplicar):
  /// todo es raíz y no hay subcategorías. La UI debe seguir siendo usable.
  bool get sinJerarquia => todas.isNotEmpty && todas.every((t) => !t.esSubcategoria);

  /// Categorías (nivel 1), ordenadas por `orden` y luego por nombre.
  List<TipoActividad> get raices {
    final lista = todas.where((t) => !t.esSubcategoria).toList()..sort(_porOrden);
    return List<TipoActividad>.unmodifiable(lista);
  }

  /// Subcategorías de una categoría, ordenadas igual que el Home.
  List<TipoActividad> subcategoriasDe(int? idCategoria) {
    if (idCategoria == null) return const <TipoActividad>[];
    final lista = todas.where((t) => t.idPadre == idCategoria).toList()
      ..sort(_porOrden);
    return List<TipoActividad>.unmodifiable(lista);
  }

  TipoActividad? porId(int? id) => id == null ? null : _porId[id];

  /// Categoría de una hoja: el padre si es subcategoría, la propia hoja si es
  /// raíz. `null` si el id no existe en la taxonomía leída.
  TipoActividad? categoriaDe(int? idHoja) {
    final hoja = porId(idHoja);
    if (hoja == null) return null;
    return hoja.esSubcategoria ? porId(hoja.idPadre) : hoja;
  }

  /// Nombre de la categoría de una hoja, o `null` si no se puede resolver.
  String? categoriaNombre(int? idHoja) =>
      _nombreNoVacio(categoriaDe(idHoja)?.nombre);

  /// Nombre de la subcategoría de una hoja, o `null` si la hoja es una raíz.
  String? subcategoriaNombre(int? idHoja) {
    final hoja = porId(idHoja);
    if (hoja == null || !hoja.esSubcategoria) return null;
    return _nombreNoVacio(hoja.nombre);
  }

  /// `"Belleza › Uñas / Manicure"`, o solo la categoría si no hay subcategoría.
  String etiquetaCompleta(int? idHoja) {
    final hoja = porId(idHoja);
    if (hoja == null) return '';
    if (!hoja.esSubcategoria) return hoja.nombre;
    final padre = porId(hoja.idPadre);
    if (padre == null) return hoja.nombre;
    return '${padre.nombre} › ${hoja.nombre}';
  }

  /// Todas las hojas a las que se puede asignar un servicio: las raíces sin
  /// hijas y todas las subcategorías. Un servicio puede quedar en la categoría
  /// sin subcategoría, por eso las raíces sin hijas también son asignables.
  List<TipoActividad> get asignables {
    final conHijas = todas
        .where((t) => t.esSubcategoria)
        .map((t) => t.idPadre)
        .whereType<int>()
        .toSet();
    final lista = todas
        .where((t) => t.esSubcategoria || !conHijas.contains(t.id))
        .toList()
      ..sort((a, b) {
        final ca = categoriaDe(a.id) ?? a;
        final cb = categoriaDe(b.id) ?? b;
        final porCategoria = _porOrden(ca, cb);
        if (porCategoria != 0) return porCategoria;
        return _porOrden(a, b);
      });
    return List<TipoActividad>.unmodifiable(lista);
  }

  static int _porOrden(TipoActividad a, TipoActividad b) {
    final porOrden = a.orden.compareTo(b.orden);
    if (porOrden != 0) return porOrden;
    return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
  }

  static String? _nombreNoVacio(String? valor) {
    final v = valor?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }
}

/// Lectura de la taxonomía de servicios y visibilidad por entidad.
///
/// La lectura va directo a la tabla (RLS `nom_tipo_actividad_select_all` es
/// pública).
///
/// **Este servicio NO gestiona la taxonomía.** Crear, editar, eliminar y
/// desactivar categorías es exclusivo del superadmin (`ventiq_superadmin`, que
/// tiene su propio `categoria_admin_service.dart`).
///
/// Lo único que puede hacer el admin de entidad es **ocultar** una categoría
/// para sus propios servicios ([ocultarParaEntidad]): la categoría sigue activa y
/// sigue pintada en el riel de filtros del Home, pero los servicios/locales de
/// esa entidad en esa categoría dejan de aparecer en el catálogo del cliente.
///
/// Los RPC **no** reciben el uuid del usuario: la autorización la resuelve
/// `auth.uid()` en el servidor. Aun así hace falta estar autenticado, así que las
/// pantallas comprueban la sesión antes.
class TipoActividadService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  /// Columnas de la taxonomía de dos niveles (migración 47).
  static const String _columnas = 'id, codigo, nombre, activo, id_padre, orden';

  /// Columnas previas a la migración 47: sin jerarquía ni orden.
  static const String _columnasLegado = 'id, codigo, nombre, activo';

  /// Filas crudas, tal cual las devuelve PostgREST.
  ///
  /// Si la migración `47_categorias_reales_subcategorias.sql` todavía no está
  /// aplicada, la lectura de `id_padre`/`orden` falla con "column does not
  /// exist". En ese caso se reintenta sin ellas y la taxonomía se comporta como
  /// plana: es mejor una pantalla de categorías usable que un error de columna.
  static Future<List<Map<String, dynamic>>> listarMapas({
    bool soloActivos = false,
  }) async {
    Future<List<dynamic>> consulta(String columnas) async {
      var query = _supabase
          .schema(_schema)
          .from('nom_tipo_actividad_servicio')
          .select(columnas);
      if (soloActivos) query = query.eq('activo', true);
      return await query.order('nombre') as List<dynamic>;
    }

    List<dynamic> res;
    try {
      res = await consulta(_columnas);
    } catch (e) {
      if (!_esColumnaInexistente(e)) rethrow;
      res = await consulta(_columnasLegado);
    }

    return res
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  /// Nodos de la taxonomía. `soloActivos` es lo que debe ver el cliente.
  static Future<List<TipoActividad>> listar({bool soloActivos = false}) async {
    final filas = await listarMapas(soloActivos: soloActivos);
    return filas.map(TipoActividad.fromJson).toList(growable: false);
  }

  /// Igual que [listar] pero ya indexada y ordenada por niveles.
  static Future<Taxonomia> taxonomia({bool soloActivos = false}) async =>
      Taxonomia(await listar(soloActivos: soloActivos));

  /// Tabla donde cada entidad apunta las categorías que oculta para sí misma.
  static const String _tablaOcultas = 'entidad_categoria_oculta';

  /// Nodos que [idEntidad] tiene ocultos (`flow.entidad_categoria_oculta`).
  ///
  /// Devuelve ids del nomenclador, que pueden ser categorías raíz o
  /// subcategorías. La lectura va directo a la tabla: la política
  /// `entidad_categoria_oculta_select` deja ver solo las filas de las entidades
  /// que administra el usuario.
  ///
  /// Si la migración `55_categorias_ocultas_por_entidad.sql` todavía no está
  /// aplicada, la tabla no existe y esto lanza: el llamador decide si eso es un
  /// error o solo "no hay nada oculto".
  static Future<Set<int>> ocultasDeEntidad(int idEntidad) async {
    final res = await _supabase
        .schema(_schema)
        .from(_tablaOcultas)
        .select('id_tipo_actividad')
        .eq('id_entidad', idEntidad);
    return (res as List)
        .map(
          (e) =>
              (Map<String, dynamic>.from(e as Map)['id_tipo_actividad'] as num)
                  .toInt(),
        )
        .toSet();
  }

  /// Oculta ([oculto] = true) o vuelve a mostrar una categoría para los
  /// servicios de [idEntidad].
  ///
  /// No toca el nomenclador: el nodo sigue activo y sigue en el riel del Home.
  /// Solo hace desaparecer del catálogo del cliente los servicios de esa entidad
  /// en ese nodo (y en sus subcategorías, si [idNodo] es una categoría raíz).
  static Future<void> ocultarParaEntidad({
    required int idEntidad,
    required int idNodo,
    required bool oculto,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_ocultar_categoria_entidad',
          params: {
            'p_id_entidad': idEntidad,
            'p_id_tipo_actividad': idNodo,
            'p_oculto': oculto,
          },
        );
    final json = res is Map
        ? Map<String, dynamic>.from(res)
        : const <String, dynamic>{};
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo cambiar la visibilidad');
    }
  }

  /// `true` cuando el error es "esa columna no existe" (migración 47 sin aplicar).
  static bool _esColumnaInexistente(Object e) {
    final t = e.toString();
    return t.contains('42703') ||
        t.contains('PGRST204') ||
        t.contains('id_padre') ||
        t.contains('"orden"') ||
        (t.contains('column') && t.contains('does not exist'));
  }
}

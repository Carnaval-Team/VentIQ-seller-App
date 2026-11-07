import 'package:flutter/foundation.dart';

import 'product.dart';

/// Modelos del Home tipo cliente del TPV.
///
/// Se mantienen **planos y sin dependencias** (ni Supabase ni Flutter de UI)
/// por dos razones: se pueden probar sin red, y se pueden serializar tal cual
/// para el snapshot en disco (ver `HomeCatalogService`).
///
/// Nombres de campo: los del `RETURNS TABLE` de `get_home_catalogo_tpv` se
/// traducen a camelCase aquí, en un solo sitio, para que el resto de la app no
/// tenga que saber cómo se llaman las columnas.

/// Tienda y TPV activos. Es lo que necesitan todas las RPC del Home.
@immutable
class HomeContexto {
  const HomeContexto({required this.idTienda, required this.idTpv});

  final int idTienda;
  final int idTpv;

  @override
  bool operator ==(Object other) =>
      other is HomeContexto &&
      other.idTienda == idTienda &&
      other.idTpv == idTpv;

  @override
  int get hashCode => Object.hash(idTienda, idTpv);

  @override
  String toString() => 'HomeContexto(tienda: $idTienda, tpv: $idTpv)';
}

/// Una categoría del Home, **ya colapsada por denominación**.
///
/// El backend agrupa los duplicados del nomenclador (hay 1056 categorías para
/// 343 nombres, con tiendas que llegan a 208 "Alimentos"), así que `id` es el
/// `min(id)` del grupo y [grupoIds] trae **todos** los ids reales. Cualquier
/// consulta que siga desde aquí (subcategorías, productos) debe usar
/// [grupoIds], no [id], o dejará fuera productos del grupo.
@immutable
class HomeCategoria {
  const HomeCategoria({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.imagen,
    this.especial = false,
    this.ordenHome = 0,
    this.totalProductos = 0,
    this.totalSubcategorias = 0,
    this.miembros = 1,
    this.grupoIds = const <int>[],
  });

  final int id;
  final String nombre;
  final String? descripcion;
  final String? imagen;

  /// Marcada por el gerente en `app_dat_categoria_tienda.especial`.
  final bool especial;

  /// Orden manual de las tarjetas especiales. 0 = desempata por nombre.
  final int ordenHome;

  final int totalProductos;
  final int totalSubcategorias;

  /// Cuántas categorías reales se colapsaron en esta fila. `1` = sin duplicados.
  final int miembros;

  /// Ids reales del grupo. Nunca vacío cuando viene del backend.
  final List<int> grupoIds;

  /// Ids a usar para pedir subcategorías y productos. Si el backend no mandó
  /// el grupo (p. ej. una fila antigua en caché), cae al propio [id].
  List<int> get idsConsulta => grupoIds.isEmpty ? <int>[id] : grupoIds;

  /// Una categoría sin subcategorías se puede abrir directamente en productos.
  bool get tieneSubcategorias => totalSubcategorias > 0;

  bool get tieneImagen => imagen != null && imagen!.trim().isNotEmpty;

  factory HomeCategoria.fromJson(Map<String, dynamic> json) {
    return HomeCategoria(
      id: _entero(json['id']),
      nombre:
          (json['nombre'] ?? json['denominacion'] ?? 'Sin nombre') as String,
      descripcion: _texto(json['descripcion']),
      imagen: _texto(json['imagen'] ?? json['image']),
      especial: json['especial'] == true,
      ordenHome: _entero(json['orden_home']),
      totalProductos: _entero(json['total_productos']),
      totalSubcategorias: _entero(json['total_subcategorias']),
      miembros: _entero(json['miembros'], porDefecto: 1),
      grupoIds: _listaDeEnteros(json['grupo_ids']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'nombre': nombre,
    'descripcion': descripcion,
    'imagen': imagen,
    'especial': especial,
    'orden_home': ordenHome,
    'total_productos': totalProductos,
    'total_subcategorias': totalSubcategorias,
    'miembros': miembros,
    'grupo_ids': grupoIds,
  };

  HomeCategoria copyWith({
    String? nombre,
    String? descripcion,
    String? imagen,
    bool? especial,
    int? ordenHome,
    int? totalProductos,
    int? totalSubcategorias,
    int? miembros,
    List<int>? grupoIds,
  }) {
    return HomeCategoria(
      id: id,
      nombre: nombre ?? this.nombre,
      descripcion: descripcion ?? this.descripcion,
      imagen: imagen ?? this.imagen,
      especial: especial ?? this.especial,
      ordenHome: ordenHome ?? this.ordenHome,
      totalProductos: totalProductos ?? this.totalProductos,
      totalSubcategorias: totalSubcategorias ?? this.totalSubcategorias,
      miembros: miembros ?? this.miembros,
      grupoIds: grupoIds ?? this.grupoIds,
    );
  }

  /// La tarjeta virtual "Tienda": no existe en la base, la fabrica el Home
  /// para agrupar todo lo que no es especial. Se modela como una
  /// [HomeCategoria] normal para que la UI no tenga dos caminos.
  factory HomeCategoria.tienda({
    required int totalProductos,
    required int totalSubcategorias,
  }) {
    return HomeCategoria(
      id: kIdTiendaVirtual,
      nombre: kNombreTienda,
      descripcion: 'Todo lo demás',
      especial: false,
      totalProductos: totalProductos,
      totalSubcategorias: totalSubcategorias,
    );
  }

  bool get esTiendaVirtual => id == kIdTiendaVirtual;

  @override
  bool operator ==(Object other) =>
      other is HomeCategoria && other.id == id && other.nombre == nombre;

  @override
  int get hashCode => Object.hash(id, nombre);

  @override
  String toString() =>
      'HomeCategoria($id "$nombre" especial=$especial '
      'productos=$totalProductos subcategorias=$totalSubcategorias '
      'miembros=$miembros)';
}

/// Subcategoría de un grupo de categorías, con `total_productos` real de la
/// tienda (solo vendibles) — la RPC vieja no filtraba y daba números inflados.
///
/// Igual que [HomeCategoria], viene **colapsada por nombre**: el nomenclador
/// duplicado hace que un grupo como los 208 "Alimentos" de una tienda traiga 208
/// subcategorías homónimas, y el drawer no puede enseñar 208 entradas iguales.
/// [grupoIds] trae todos los ids reales para poder filtrar productos por
/// cualquiera de ellos.
@immutable
class HomeSubcategoria {
  const HomeSubcategoria({
    required this.id,
    required this.nombre,
    this.skuCodigo,
    this.totalProductos = 0,
    this.grupoIds = const <int>[],
  });

  final int id;
  final String nombre;
  final String? skuCodigo;
  final int totalProductos;

  /// Ids reales de las subcategorías colapsadas en esta fila.
  final List<int> grupoIds;

  List<int> get idsConsulta => grupoIds.isEmpty ? <int>[id] : grupoIds;

  factory HomeSubcategoria.fromJson(Map<String, dynamic> json) {
    return HomeSubcategoria(
      id: _entero(json['id']),
      nombre:
          (json['denominacion'] ?? json['nombre'] ?? 'Sin nombre') as String,
      skuCodigo: _texto(json['sku_codigo']),
      totalProductos: _entero(json['total_productos']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'denominacion': nombre,
    'sku_codigo': skuCodigo,
    'total_productos': totalProductos,
    'grupo_ids': grupoIds,
  };

  /// Colapsa por nombre y suma los conteos.
  ///
  /// Función pura: es la misma regla que aplica el backend con las categorías y
  /// tiene que poder probarse sin red.
  static List<HomeSubcategoria> agruparPorNombre(
    List<HomeSubcategoria> crudas,
  ) {
    final Map<String, List<HomeSubcategoria>> porNombre =
        <String, List<HomeSubcategoria>>{};

    for (final HomeSubcategoria s in crudas) {
      porNombre
          .putIfAbsent(claveNombre(s.nombre), () => <HomeSubcategoria>[])
          .add(s);
    }

    final List<HomeSubcategoria> salida =
        porNombre.values.map((List<HomeSubcategoria> grupo) {
            final List<HomeSubcategoria> ordenado = List<HomeSubcategoria>.of(
              grupo,
            )..sort(
              (HomeSubcategoria a, HomeSubcategoria b) => a.id.compareTo(b.id),
            );
            final HomeSubcategoria canonica = ordenado.first;

            return HomeSubcategoria(
              id: canonica.id,
              nombre: canonica.nombre,
              skuCodigo: canonica.skuCodigo,
              totalProductos: ordenado.fold<int>(
                0,
                (int suma, HomeSubcategoria s) => suma + s.totalProductos,
              ),
              grupoIds:
                  ordenado
                      .expand((HomeSubcategoria s) => s.idsConsulta)
                      .toSet()
                      .toList()
                    ..sort(),
            );
          }).toList()
          ..sort(
            (HomeSubcategoria a, HomeSubcategoria b) =>
                a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
          );

    return salida;
  }

  @override
  bool operator ==(Object other) => other is HomeSubcategoria && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'HomeSubcategoria($id "$nombre" $totalProductos)';
}

/// Clave de comparación de nombres: sin acentos, sin mayúsculas y con los
/// espacios colapsados.
///
/// Ojo: **no** une plurales ni singular. "Confituras" y "Confitura" son claves
/// distintas a propósito — en la tienda 174 son dos categorías reales con 53 y
/// 25 productos, y unirlas sería una decisión de negocio, no de código.
String claveNombre(String nombre) {
  final StringBuffer salida = StringBuffer();
  for (final int rune in nombre.toLowerCase().trim().runes) {
    final String c = String.fromCharCode(rune);
    salida.write(_sinTildeNombre[c] ?? c);
  }
  return salida.toString().replaceAll(RegExp(r'\s+'), ' ');
}

const Map<String, String> _sinTildeNombre = <String, String>{
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'â': 'a',
  'é': 'e',
  'è': 'e',
  'ë': 'e',
  'ê': 'e',
  'í': 'i',
  'ì': 'i',
  'ï': 'i',
  'î': 'i',
  'ó': 'o',
  'ò': 'o',
  'ö': 'o',
  'ô': 'o',
  'ú': 'u',
  'ù': 'u',
  'ü': 'u',
  'û': 'u',
  'ñ': 'n',
  'ç': 'c',
};

/// Producto tal y como lo devuelve `get_productos_by_categoria_tpv_search_meta_v3`.
///
/// Es una vista **ligera** a propósito: no es el `Product` completo del dominio
/// de venta (variantes, presentaciones, desglose de inventario), sino lo justo
/// para pintar una fila y decidir si se abre el detalle. El detalle sigue
/// cargando lo suyo.
///
/// Conserva [idSubcategoria] porque el drawer filtra por subcategoría **en el
/// cliente**: al reutilizar la RPC por categoría en vez de crear una RPC nueva,
/// el filtro por subcategoría es lo único que separa "todos los productos de la
/// categoría" de "los de esta subcategoría".
@immutable
class HomeProducto {
  const HomeProducto({
    required this.id,
    required this.nombre,
    this.sku,
    this.descripcion,
    this.imagen,
    this.precio = 0,
    this.stock = 0,
    this.tieneStock = false,
    this.esElaborado = false,
    this.esServicio = false,
    this.idCategoria,
    this.categoriaNombre,
    this.idSubcategoria,
    this.subcategoriaNombre,
  });

  final int id;
  final String nombre;
  final String? sku;
  final String? descripcion;
  final String? imagen;
  final double precio;
  final double stock;
  final bool tieneStock;
  final bool esElaborado;
  final bool esServicio;
  final int? idCategoria;
  final String? categoriaNombre;
  final int? idSubcategoria;
  final String? subcategoriaNombre;

  bool get tieneImagen => imagen != null && imagen!.trim().isNotEmpty;

  /// Un producto de servicio no necesita stock para poder venderse.
  bool get disponible => esServicio || esElaborado || tieneStock;

  /// Adapta un `Product` del dominio de venta (resultados de la búsqueda global,
  /// listados) a la fila ligera del Home. Así la búsqueda reutiliza el mismo
  /// `ProductoTile` y el mismo alta rápida que el drawer.
  factory HomeProducto.desdeProducto(Product p) => HomeProducto(
    id: p.id,
    nombre: p.denominacion,
    sku: p.sku,
    descripcion: p.descripcion,
    imagen: p.foto,
    precio: p.precio,
    stock: p.cantidadReal.toDouble(),
    tieneStock: p.cantidadReal > 0,
    esElaborado: p.esElaborado,
    esServicio: p.esServicio,
    categoriaNombre: p.categoria,
  );

  factory HomeProducto.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> meta =
        (json['metadata'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    return HomeProducto(
      id: _entero(json['id_producto'] ?? json['id']),
      nombre:
          (json['denominacion'] ?? json['nombre'] ?? 'Sin nombre') as String,
      sku: _texto(json['sku']),
      descripcion: _texto(json['descripcion']),
      imagen: _texto(json['imagen']),
      precio: _decimal(json['precio_venta']),
      stock: _decimal(json['stock_disponible']),
      tieneStock: json['tiene_stock'] == true,
      esElaborado: meta['es_elaborado'] == true,
      esServicio: meta['es_servicio'] == true,
      idCategoria: _enteroONulo(json['id_categoria']),
      categoriaNombre: _texto(json['categoria_nombre']),
      idSubcategoria: _enteroONulo(json['id_subcategoria']),
      subcategoriaNombre: _texto(json['subcategoria_nombre']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'nombre': nombre,
    'sku': sku,
    'descripcion': descripcion,
    'imagen': imagen,
    'precio': precio,
    'stock': stock,
    'tiene_stock': tieneStock,
    'es_elaborado': esElaborado,
    'es_servicio': esServicio,
    'id_categoria': idCategoria,
    'categoria_nombre': categoriaNombre,
    'id_subcategoria': idSubcategoria,
    'subcategoria_nombre': subcategoriaNombre,
  };

  /// Copia con el stock ajustado. La usa el Home para enseñar la
  /// **disponibilidad elaborable** de un plato (materia prima) en vez del stock
  /// propio del SKU.
  HomeProducto copyWith({double? stock, bool? tieneStock, double? precio}) {
    return HomeProducto(
      id: id,
      nombre: nombre,
      sku: sku,
      descripcion: descripcion,
      imagen: imagen,
      precio: precio ?? this.precio,
      stock: stock ?? this.stock,
      tieneStock: tieneStock ?? this.tieneStock,
      esElaborado: esElaborado,
      esServicio: esServicio,
      idCategoria: idCategoria,
      categoriaNombre: categoriaNombre,
      idSubcategoria: idSubcategoria,
      subcategoriaNombre: subcategoriaNombre,
    );
  }

  @override
  bool operator ==(Object other) => other is HomeProducto && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'HomeProducto($id "$nombre" ${precio.toStringAsFixed(2)} sub=$idSubcategoria)';
}

/// El catálogo del Home ya repartido: lo que se pinta como tarjeta destacada y
/// lo que se agrupa bajo "Tienda".
@immutable
class HomeCatalogo {
  const HomeCatalogo({
    this.especiales = const <HomeCategoria>[],
    this.tienda = const <HomeCategoria>[],
  });

  /// Categorías marcadas como especiales, en orden de Home.
  final List<HomeCategoria> especiales;

  /// Categorías no especiales. **No** incluye la tarjeta virtual "Tienda": esa
  /// la añade el controlador, porque su contador depende de este listado.
  final List<HomeCategoria> tienda;

  bool get vacio => especiales.isEmpty && tienda.isEmpty;

  /// La tarjeta "Tienda" solo tiene sentido si hay algo dentro.
  bool get mostrarTarjetaTienda => tienda.isNotEmpty;

  int get totalCategorias => especiales.length + tienda.length;

  /// Reparte una lista plana de categorías en especiales y "Tienda", y colapsa
  /// los homónimos.
  ///
  /// Es una **función pura** a propósito: es la regla de negocio central del
  /// Home (qué es tarjeta destacada y qué va bajo "Tienda") y tiene que poder
  /// probarse sin base de datos ni widgets.
  ///
  /// El colapso por nombre se hace **también aquí**, aunque el backend ya lo
  /// haga, y es deliberado: el backend puede cambiar, una caché vieja puede
  /// traer filas sin colapsar o alguien puede llamar a la RPC antigua. Sin esta
  /// red, una tienda con 208 "Alimentos" volvería a pintar 208 tarjetas. Un
  /// nomenclador con 1056 filas para 343 nombres no admite confiar en una sola
  /// capa. Colapsar es idempotente: si ya viene colapsado, no cambia nada.
  ///
  /// Orden:
  ///  * especiales → `ordenHome` ascendente y, a igualdad, nombre ascendente
  ///    (el backend ya ordena así, pero el snapshot en caché puede venir de una
  ///    versión anterior del orden, y el Home no debe cambiar de aspecto por
  ///    eso);
  ///  * tienda → nombre ascendente, como el catálogo.
  static HomeCatalogo agrupar(List<HomeCategoria> todas) {
    final List<HomeCategoria> especiales = <HomeCategoria>[];
    final List<HomeCategoria> tienda = <HomeCategoria>[];

    for (final HomeCategoria c in _colapsarPorNombre(todas)) {
      if (c.especial) {
        especiales.add(c);
      } else {
        tienda.add(c);
      }
    }

    especiales.sort((HomeCategoria a, HomeCategoria b) {
      final int porOrden = a.ordenHome.compareTo(b.ordenHome);
      if (porOrden != 0) return porOrden;
      return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    });

    tienda.sort(
      (HomeCategoria a, HomeCategoria b) =>
          a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
    );

    return HomeCatalogo(especiales: especiales, tienda: tienda);
  }

  /// Orden del grupo: el menor de los **no cero**; si todos son 0, 0.
  ///
  /// Ver el comentario en [_colapsarPorNombre].
  static int _ordenDeGrupo(List<HomeCategoria> grupo) {
    final List<int> puestos =
        grupo
            .map((HomeCategoria c) => c.ordenHome)
            .where((int o) => o != 0)
            .toList();
    if (puestos.isEmpty) return 0;
    return puestos.reduce((int a, int b) => a < b ? a : b);
  }

  /// Une las filas que comparten [claveNombre].
  ///
  /// Canónica = `min(id)`. Si alguna del grupo es especial, el grupo lo es
  /// (si el gerente marcó una de las copias, marca la tarjeta entera).
  /// `ordenHome` = el menor del grupo, para que la posición sea la que eligió
  /// el gerente y no la del duplicado de turno.
  static List<HomeCategoria> _colapsarPorNombre(List<HomeCategoria> todas) {
    final Map<String, List<HomeCategoria>> porNombre =
        <String, List<HomeCategoria>>{};

    for (final HomeCategoria c in todas) {
      // La tarjeta virtual nunca viene de la base; si alguien la colara, se
      // ignora para no acabar con dos "Tienda".
      if (c.esTiendaVirtual) continue;
      porNombre
          .putIfAbsent(claveNombre(c.nombre), () => <HomeCategoria>[])
          .add(c);
    }

    final List<HomeCategoria> salida =
        porNombre.values.map((List<HomeCategoria> grupo) {
          if (grupo.length == 1) {
            final HomeCategoria unica = grupo.single;
            return unica.grupoIds.isEmpty
                ? unica.copyWith(grupoIds: <int>[unica.id], miembros: 1)
                : unica;
          }

          final List<HomeCategoria> ordenado = List<HomeCategoria>.of(grupo)
            ..sort((HomeCategoria a, HomeCategoria b) => a.id.compareTo(b.id));

          return HomeCategoria(
            id: ordenado.first.id,
            nombre: ordenado.first.nombre,
            descripcion: ordenado
                .map((HomeCategoria c) => c.descripcion)
                .firstWhere(
                  (String? d) => d != null && d.trim().isNotEmpty,
                  orElse: () => null,
                ),
            imagen: ordenado
                .map((HomeCategoria c) => c.imagen)
                .firstWhere(
                  (String? i) => i != null && i.trim().isNotEmpty,
                  orElse: () => null,
                ),
            especial: ordenado.any((HomeCategoria c) => c.especial),
            // `ordenHome = 0` significa "sin orden manual", no "el primero".
            // Si el gerente le puso orden a UNA de las copias, ese es el orden
            // del grupo: quedarse con el mínimo daría 0 y perdería su elección.
            ordenHome: _ordenDeGrupo(ordenado),
            totalProductos: ordenado.fold<int>(
              0,
              (int suma, HomeCategoria c) => suma + c.totalProductos,
            ),
            totalSubcategorias: ordenado.fold<int>(
              0,
              (int suma, HomeCategoria c) => suma + c.totalSubcategorias,
            ),
            miembros: ordenado.length,
            grupoIds:
                ordenado
                    .expand((HomeCategoria c) => c.idsConsulta)
                    .toSet()
                    .toList()
                  ..sort(),
          );
        }).toList();

    return salida;
  }

  factory HomeCatalogo.fromJson(Map<String, dynamic> json) {
    List<HomeCategoria> leer(String clave) =>
        ((json[clave] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map(
              (Map<dynamic, dynamic> m) =>
                  HomeCategoria.fromJson(m.cast<String, dynamic>()),
            )
            .toList();

    return HomeCatalogo(especiales: leer('especiales'), tienda: leer('tienda'));
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'especiales': especiales.map((HomeCategoria c) => c.toJson()).toList(),
    'tienda': tienda.map((HomeCategoria c) => c.toJson()).toList(),
  };
}

/// Id reservado para la tarjeta virtual "Tienda".
///
/// Negativo a propósito: los ids reales de `app_dat_categoria` son positivos,
/// así que no puede colisionar nunca.
const int kIdTiendaVirtual = -1;

/// Nombre de la tarjeta agrupadora. Constante para que renombrarla sea un
/// cambio de una línea (decisión D2 del plan).
const String kNombreTienda = 'Tienda';

// ── Conversiones tolerantes ────────────────────────────────────────────────
//
// PostgREST devuelve `numeric` como String a veces y como num otras; un
// `as double` directo reventaría en producción con un dato legítimo.

int _entero(Object? valor, {int porDefecto = 0}) =>
    _enteroONulo(valor) ?? porDefecto;

int? _enteroONulo(Object? valor) {
  if (valor == null) return null;
  if (valor is int) return valor;
  if (valor is num) return valor.toInt();
  return int.tryParse(valor.toString());
}

double _decimal(Object? valor, {double porDefecto = 0}) {
  if (valor == null) return porDefecto;
  if (valor is num) return valor.toDouble();
  return double.tryParse(valor.toString()) ?? porDefecto;
}

String? _texto(Object? valor) {
  if (valor == null) return null;
  final String s = valor.toString().trim();
  return s.isEmpty ? null : s;
}

List<int> _listaDeEnteros(Object? valor) {
  if (valor is! List) return const <int>[];
  return valor.map(_enteroONulo).whereType<int>().toList();
}

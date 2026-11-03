/// Mapeo de la caché offline al modelo del Home.
///
/// Este archivo es **puro a propósito**: no importa Supabase, ni SQLite, ni
/// `SharedPreferences`. Solo transforma mapas que ya se leyeron del cache
/// (`offline_data['products']`) en [HomeSubcategoria] y [HomeProducto]. Así el
/// fallback offline del Home se puede probar sin red ni base de datos, que es
/// justo lo que no se podía hacer cuando el mapeo vivía dentro del servicio.
///
/// Forma de un producto cacheado (la que guarda
/// `auto_sync_service._syncProducts`):
///
/// ```json
/// {
///   "id": 10808,
///   "denominacion": "Jugo de Limón",
///   "precio": 12.0,
///   "foto": "https://...",
///   "categoria": "Alimentos",
///   "descripcion": "...",
///   "cantidad": 5,
///   "subcategoria": "Jugos",
///   "detalles_completos": {
///     "producto": {
///       "id": 10808,
///       "es_elaborado": false,
///       "categoria": {"id": 3, "denominacion": "Alimentos"},
///       "subcategorias": [{"id": 42, "denominacion": "Jugos"}],
///       "precio_actual": 12.0,
///       "multimedias": [{"url": "https://..."}]
///     },
///     "inventario": [{"cantidad_disponible": 5}]
///   }
/// }
/// ```
///
/// Ojo: el sync **no guarda todos** los campos que devuelve la RPC online.
/// * `id_subcategoria` no está a nivel de fila: solo el nombre en `subcategoria`.
///   Los ids reales viven en `detalles_completos.producto.subcategorias`.
/// * `es_servicio` tampoco se guarda a nivel de fila. En `detalles_completos` el
///   batch ya manda `es_elaborado = es_elaborado OR es_servicio`, así que un
///   servicio offline se ve como elaborado (limitación del sync, no del mapeo).
///
/// Para que el filtro por subcategoría del drawer siga funcionando aunque falten
/// los ids reales, cuando no hay id se usa uno **sintético y estable** derivado
/// del nombre ([idOfflineDeSubcategoria]). El mismo esquema se aplica a la
/// subcategoría y a sus productos, de modo que la comparación que hace
/// `HomeController` (`sub.idsConsulta.contains(p.idSubcategoria)`) nunca se
/// rompe por haber cargado del cache.
library;

import '../models/home_catalogo.dart';

/// Nombre que se le da a un producto cacheado sin subcategoría.
///
/// Es el mismo rótulo que usa el Home viejo al leer SQLite (`'General'`), para
/// que el drawer enseñe una entrada coherente en vez de dejar la fila suelta.
const String kSubcategoriaOfflineSinNombre = 'General';

/// Fuente de datos local que necesita el fallback offline del Home.
///
/// Es una interfaz (y no las clases reales) para que `HomeCatalogService` se
/// pueda probar con un doble: los tests inyectan datos de ejemplo y comprueban
/// el mapeo sin Supabase ni `sqflite`.
abstract class HomeOfflineSource {
  /// `true` si la app debe leer del cache local (modo offline o dispositivo
  /// full-offline).
  Future<bool> debeUsarDatosLocales();

  /// Productos cacheados agrupados por id de categoría.
  ///
  /// La clave es el `id` de `app_dat_categoria` (el `category_id` con el que el
  /// sync guardó la fila). Con [idsCategorias] vacío se devuelven todas las
  /// categorías cacheadas: es lo que necesita la búsqueda global.
  ///
  /// Nunca lanza: sin cache devuelve un mapa vacío.
  Future<Map<int, List<Map<String, dynamic>>>> productosPorCategoria({
    List<int> idsCategorias = const <int>[],
  });
}

// ── Puntos de entrada que usa `HomeCatalogService` ─────────────────────────

/// Subcategorías del drawer construidas desde el cache local.
///
/// Una categoría sin productos cacheados no aporta subcategorías (lista vacía);
/// el drawer enseña entonces su estado vacío en vez de reventar.
List<HomeSubcategoria> subcategoriasOfflineDesdeCache(
  Map<int, List<Map<String, dynamic>>> cache, {
  required List<int> idsCategorias,
}) {
  if (idsCategorias.isEmpty) return const <HomeSubcategoria>[];
  return construirSubcategoriasOffline(
    _crudosDeCategorias(cache, idsCategorias),
  );
}

/// Productos del drawer (o de la búsqueda global) construidos desde el cache.
///
/// * [idsCategorias] vacío ⇒ todo el cache (búsqueda global del Home).
/// * [texto] filtra por nombre, SKU, descripción y subcategoría, sin acentos ni
///   mayúsculas (misma tolerancia que la búsqueda online).
/// * [soloDisponibles] descarta lo que no se puede vender.
List<HomeProducto> productosOfflineDesdeCache(
  Map<int, List<Map<String, dynamic>>> cache, {
  List<int> idsCategorias = const <int>[],
  String? texto,
  bool soloDisponibles = false,
}) {
  List<HomeProducto> salida = mapearProductosOffline(
    _crudosDeCategorias(cache, idsCategorias),
  );

  final String? busqueda = _normalizarTexto(texto);
  if (busqueda != null) {
    salida =
        salida
            .where((HomeProducto p) => _coincideBusqueda(p, busqueda))
            .toList();
  }

  if (soloDisponibles) {
    salida = salida.where((HomeProducto p) => p.disponible).toList();
  }

  return salida;
}

// ── Mapeo producto a producto ──────────────────────────────────────────────

/// Convierte una fila cacheada en la vista ligera que pinta el Home.
///
/// Es tolerante: acepta filas antiguas/incompletas (solo `id` y
/// `denominacion`), `numeric` como texto y `detalles_completos` ausente.
HomeProducto mapearProductoOffline(Map<String, dynamic> crudo) {
  final Map<String, dynamic>? producto = _productoDetalle(crudo);
  final Map<String, dynamic>? categoria = _mapa(producto?['categoria']);
  final _SubcategoriaLeida subcategoria = _leerSubcategoria(crudo, producto);

  final double stock = _stockDe(crudo);
  final String? categoriaNombre =
      _texto(crudo['categoria']) ?? _texto(categoria?['denominacion']);

  return HomeProducto(
    id: _entero(crudo['id'] ?? crudo['id_producto']),
    nombre:
        _texto(crudo['denominacion']) ??
        _texto(crudo['nombre']) ??
        _texto(producto?['denominacion']) ??
        'Sin nombre',
    sku: _texto(crudo['sku']) ?? _texto(producto?['sku']),
    descripcion:
        _texto(crudo['descripcion']) ?? _texto(producto?['descripcion']),
    imagen: _imagenDe(crudo, producto),
    precio: _decimal(
      crudo['precio'] ?? crudo['precio_venta'] ?? producto?['precio_actual'],
    ),
    stock: stock,
    tieneStock: stock > 0,
    esElaborado: _bandera(crudo, producto, 'es_elaborado'),
    esServicio: _bandera(crudo, producto, 'es_servicio'),
    idCategoria:
        _enteroONulo(crudo['id_categoria']) ?? _enteroONulo(categoria?['id']),
    categoriaNombre: categoriaNombre,
    // El id elegido está siempre dentro de `subcategoria.idsConsulta` del mismo
    // cache: real si `detalles_completos` lo trae, sintético si no.
    idSubcategoria: subcategoria.id,
    subcategoriaNombre: subcategoria.nombre,
  );
}

/// Mapea filas cacheadas y **une por id** (un producto puede venir en dos
/// categorías del grupo colapsado y no debe pintarse dos veces).
List<HomeProducto> mapearProductosOffline(
  Iterable<Map<String, dynamic>> productos,
) {
  final Map<int, HomeProducto> porId = <int, HomeProducto>{};
  for (final Map<String, dynamic> crudo in productos) {
    final HomeProducto producto = mapearProductoOffline(crudo);
    if (producto.id <= 0) continue;
    porId.putIfAbsent(producto.id, () => producto);
  }
  return porId.values.toList();
}

// ── Mapeo de subcategorías ─────────────────────────────────────────────────

/// Construye el nivel de subcategorías del drawer desde los productos cacheados.
///
/// El cache no guarda una tabla de subcategorías (solo el nombre en cada
/// producto), así que el nivel se deriva de lo que hay:
///
/// * se agrupa por [claveNombre], igual que el backend y que
///   [HomeSubcategoria.agruparPorNombre] — homónimos con acentos/mayúsculas
///   distintas o ids de nomenclador distintos son **una** entrada;
/// * `totalProductos` cuenta los productos cacheados (distintos por id) de esa
///   entrada, que es exactamente lo que enseñará el nivel de productos;
/// * `grupoIds` lleva todos los ids reales vistos; si algún producto de ese
///   nombre no tenía id, se añade el sintético para que su filtro funcione.
List<HomeSubcategoria> construirSubcategoriasOffline(
  Iterable<Map<String, dynamic>> productos,
) {
  final List<HomeSubcategoria> crudas = <HomeSubcategoria>[];
  final Set<int> vistos = <int>{};

  for (final Map<String, dynamic> crudo in productos) {
    final int id = _entero(crudo['id'] ?? crudo['id_producto']);
    // Fila corrupta o de un formato desconocido: no aporta nada.
    if (id <= 0 || !vistos.add(id)) continue;

    final _SubcategoriaLeida subcategoria = _leerSubcategoria(
      crudo,
      _productoDetalle(crudo),
    );
    crudas.add(
      HomeSubcategoria(
        id: subcategoria.id,
        nombre: subcategoria.nombre,
        // Uno por producto: `agruparPorNombre` los suma al colapsar.
        totalProductos: 1,
        grupoIds: subcategoria.ids,
      ),
    );
  }

  return HomeSubcategoria.agruparPorNombre(crudas);
}

/// Id **sintético y estable** para una subcategoría sin id real en el cache.
///
/// Usa FNV-1a de 32 bits sobre [claveNombre] (sin acentos, sin mayúsculas) y lo
/// devuelve negativo para que no pueda colisionar con los ids reales de
/// `app_dat_subcategorias` (positivos) ni con [kIdTiendaVirtual] (-1).
///
/// Es determinista a propósito: el mismo nombre produce el mismo id en la
/// subcategoría y en sus productos, así el filtro del drawer funciona aunque el
/// dispositivo nunca haya sincronizado los ids.
int idOfflineDeSubcategoria(String nombre) {
  int hash = 0x811C9DC5; // offset basis FNV-1a 32
  for (final int unidad in claveNombre(nombre).codeUnits) {
    hash ^= unidad;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return -((hash & 0x3FFFFFFF) + 2);
}

// ── Lecturas tolerantes ────────────────────────────────────────────────────

/// Subcategoría leída de una fila cacheada.
class _SubcategoriaLeida {
  _SubcategoriaLeida({
    required this.nombre,
    required this.ids,
    required this.id,
  });

  /// Rótulo a pintar.
  final String nombre;

  /// Ids reales que comparten ese nombre (vacío si el cache no los guardó).
  final List<int> ids;

  /// Id con el que se etiqueta el producto: el primero real o, si no hay, el
  /// sintético estable del nombre.
  final int id;
}

_SubcategoriaLeida _leerSubcategoria(
  Map<String, dynamic> crudo,
  Map<String, dynamic>? producto,
) {
  final List<Map<String, dynamic>> delDetalle = <Map<String, dynamic>>[];
  final Object? subcategorias = producto?['subcategorias'];
  if (subcategorias is List) {
    for (final Object? cruda in subcategorias) {
      final Map<String, dynamic>? mapa = _mapa(cruda);
      if (mapa != null) delDetalle.add(mapa);
    }
  }

  String? nombreDelDetalle;
  for (final Map<String, dynamic> mapa in delDetalle) {
    nombreDelDetalle = _texto(mapa['denominacion']) ?? _texto(mapa['nombre']);
    if (nombreDelDetalle != null) break;
  }

  final String nombre =
      _texto(crudo['subcategoria']) ??
      _texto(crudo['subcategoria_nombre']) ??
      nombreDelDetalle ??
      kSubcategoriaOfflineSinNombre;

  // Solo los ids del detalle que comparten nombre con la subcategoría del
  // listado: el producto puede estar en varias subcategorías y el drawer pinta
  // la que traía la RPC.
  final String clave = claveNombre(nombre);
  final List<int> ids = <int>[];
  for (final Map<String, dynamic> mapa in delDetalle) {
    final int? id = _enteroONulo(mapa['id']);
    if (id == null) continue;
    final String nombreMapa =
        _texto(mapa['denominacion']) ?? _texto(mapa['nombre']) ?? '';
    if (claveNombre(nombreMapa) == clave && !ids.contains(id)) ids.add(id);
  }

  // Formatos de cache que sí guardaron el id a nivel de fila.
  final int? idSuelto = _enteroONulo(crudo['id_subcategoria']);
  if (ids.isEmpty && idSuelto != null) ids.add(idSuelto);

  return _SubcategoriaLeida(
    nombre: nombre,
    ids: ids,
    id: ids.isNotEmpty ? ids.first : idOfflineDeSubcategoria(nombre),
  );
}

Map<String, dynamic>? _productoDetalle(Map<String, dynamic> crudo) {
  final Map<String, dynamic>? detalle = _mapa(crudo['detalles_completos']);
  return _mapa(detalle?['producto']);
}

/// Stock vendible: el del listado (`cantidad`) o, si no vino, la suma del
/// inventario detallado. El sync ya alinea `cantidad` con ese inventario.
double _stockDe(Map<String, dynamic> crudo) {
  final double? cantidad = _decimalONulo(
    crudo['cantidad'] ?? crudo['stock_disponible'],
  );
  if (cantidad != null) return cantidad;

  final Map<String, dynamic>? detalle = _mapa(crudo['detalles_completos']);
  final Object? inventario = detalle?['inventario'];
  if (inventario is! List) return 0;

  double suma = 0;
  for (final Object? fila in inventario) {
    final Map<String, dynamic>? mapa = _mapa(fila);
    suma += _decimalONulo(mapa?['cantidad_disponible']) ?? 0;
  }
  return suma;
}

String? _imagenDe(Map<String, dynamic> crudo, Map<String, dynamic>? producto) {
  final String? directa =
      _texto(crudo['foto']) ??
      _texto(crudo['imagen']) ??
      _texto(producto?['imagen']) ??
      _texto(producto?['foto']);
  if (directa != null) return directa;

  final Object? multimedias = producto?['multimedias'];
  if (multimedias is List) {
    for (final Object? cruda in multimedias) {
      final String? url = _texto(_mapa(cruda)?['url']);
      if (url != null) return url;
    }
  }
  return null;
}

/// Lee una bandera de la fila o, si no está, del detalle.
bool _bandera(
  Map<String, dynamic> crudo,
  Map<String, dynamic>? producto,
  String clave,
) {
  final Object? directa = crudo[clave];
  if (directa is bool) return directa;
  final Object? detalle = producto?[clave];
  return detalle is bool && detalle;
}

// ── Búsqueda offline ───────────────────────────────────────────────────────

String? _normalizarTexto(String? texto) {
  if (texto == null) return null;
  final String limpio = claveNombre(texto);
  return limpio.isEmpty ? null : limpio;
}

bool _coincideBusqueda(HomeProducto producto, String consulta) {
  if (claveNombre(producto.nombre).contains(consulta)) return true;

  final String? sku = producto.sku?.toLowerCase();
  if (sku != null && sku.contains(consulta)) return true;

  final String? descripcion = producto.descripcion;
  if (descripcion != null && claveNombre(descripcion).contains(consulta)) {
    return true;
  }

  final String? subcategoria = producto.subcategoriaNombre;
  return subcategoria != null && claveNombre(subcategoria).contains(consulta);
}

Iterable<Map<String, dynamic>> _crudosDeCategorias(
  Map<int, List<Map<String, dynamic>>> cache,
  Iterable<int> idsCategorias,
) sync* {
  final Set<int> pedidas = idsCategorias.toSet();

  if (pedidas.isEmpty) {
    for (final List<Map<String, dynamic>> filas in cache.values) {
      yield* filas;
    }
    return;
  }

  for (final int id in pedidas) {
    final List<Map<String, dynamic>>? filas = cache[id];
    if (filas == null) continue;
    yield* filas;
  }
}

// ── Conversiones tolerantes ────────────────────────────────────────────────
//
// Los mapas offline vienen de JSON: un `numeric` puede ser num o texto y una
// fila antigua puede traer menos campos de los esperados. Ninguna conversión
// debe lanzar: el fallback offline existe justo para no romper la venta.

int _entero(Object? valor, {int porDefecto = 0}) =>
    _enteroONulo(valor) ?? porDefecto;

int? _enteroONulo(Object? valor) {
  if (valor == null) return null;
  if (valor is int) return valor;
  if (valor is num) return valor.toInt();
  return int.tryParse(valor.toString());
}

double _decimal(Object? valor, {double porDefecto = 0}) =>
    _decimalONulo(valor) ?? porDefecto;

double? _decimalONulo(Object? valor) {
  if (valor == null) return null;
  if (valor is num) return valor.toDouble();
  return double.tryParse(valor.toString());
}

String? _texto(Object? valor) {
  if (valor == null) return null;
  final String texto = valor.toString().trim();
  return texto.isEmpty ? null : texto;
}

Map<String, dynamic>? _mapa(Object? valor) {
  if (valor is! Map) return null;
  try {
    return valor.cast<String, dynamic>();
  } catch (_) {
    return null;
  }
}

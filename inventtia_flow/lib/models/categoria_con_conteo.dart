import '../services/home_catalog_service.dart';

/// Una subcategoría con cuánto hay dentro, según
/// `flow.cliente_categorias_resumen()` (migración 57).
///
/// Los conteos los calcula el servidor con la MISMA regla de visibilidad que el
/// feed (`flow._ls_disponible` + categorías ocultas por la entidad), así que el
/// número de la pantalla y el número de servicios que se ven al entrar coinciden.
class SubcategoriaConConteo {
  const SubcategoriaConConteo({
    required this.categoria,
    this.servicios = 0,
    this.establecimientos = 0,
  });

  final HomeCatalogCategory categoria;

  /// Pares local-servicio visibles en esta subcategoría.
  final int servicios;

  /// Locales distintos que ofrecen algo de esta subcategoría.
  final int establecimientos;

  factory SubcategoriaConConteo.fromJson(Map<String, dynamic> json) {
    return SubcategoriaConConteo(
      categoria: HomeCatalogCategory.fromJson(json),
      servicios: (json['servicios'] as num?)?.toInt() ?? 0,
      establecimientos: (json['establecimientos'] as num?)?.toInt() ?? 0,
    );
  }

  /// `"3 establecimientos"` / `"1 establecimiento"` / `"Todavía sin establecimientos"`.
  String get etiquetaEstablecimientos => etiquetaConteoEstablecimientos(
    establecimientos,
  );

  String get etiquetaServicios =>
      servicios == 1 ? '1 servicio' : '$servicios servicios';
}

/// Una categoría raíz con sus conteos y sus subcategorías.
///
/// `servicios`/`establecimientos` de una raíz **incluyen** los de sus
/// subcategorías (es la misma regla del filtro del servidor): si Belleza tiene 5
/// servicios y dos de ellos viven en «Uñas», la fila de Belleza dice 5.
class CategoriaConConteo {
  const CategoriaConConteo({
    required this.categoria,
    this.servicios = 0,
    this.establecimientos = 0,
    this.subcategorias = const <SubcategoriaConConteo>[],
  });

  final HomeCatalogCategory categoria;
  final int servicios;
  final int establecimientos;
  final List<SubcategoriaConConteo> subcategorias;

  bool get tieneSubcategorias => subcategorias.isNotEmpty;

  /// Un rubro sin establecimientos. Se pinta igual (el cliente pidió ver TODOS
  /// los rubros) pero se dice que está vacío, en vez de esconderlo o de mostrar
  /// un 0 pelado.
  ///
  /// La condición es «sin locales», **no** «sin locales y sin servicios»: el chip
  /// de la tarjeta dice «SIN LOCALES» en cuanto no hay establecimientos, así que
  /// el pie tiene que apagarse en ese mismo caso. Con los dos criterios distintos,
  /// un rubro con 0 locales y algún servicio (que la RPC no puede devolver, pero
  /// el modelo no lo impide) enseñaría «SIN LOCALES» con el pie activo llevando a
  /// una lista vacía.
  bool get vacia => establecimientos <= 0;

  String get etiquetaEstablecimientos => etiquetaConteoEstablecimientos(
    establecimientos,
  );

  String get etiquetaServicios =>
      servicios == 1 ? '1 servicio' : '$servicios servicios';

  /// `"3 establecimientos · 5 servicios"` — el resumen de la fila.
  String get resumen =>
      '${etiquetaEstablecimientos.toLowerCase()} · ${etiquetaServicios.toLowerCase()}';

  factory CategoriaConConteo.fromJson(Map<String, dynamic> json) {
    final hijas = (json['subcategorias'] as List?) ?? const <dynamic>[];
    return CategoriaConConteo(
      categoria: HomeCatalogCategory.fromJson(json),
      servicios: (json['servicios'] as num?)?.toInt() ?? 0,
      establecimientos: (json['establecimientos'] as num?)?.toInt() ?? 0,
      subcategorias: hijas
          .whereType<Map>()
          .map((h) => SubcategoriaConConteo.fromJson(Map<String, dynamic>.from(h)))
          .toList(growable: false),
    );
  }
}

/// Todo lo que devuelve `cliente_categorias_resumen()`: el nomenclador con
/// contadores más los totales globales (que NO son la suma de las categorías:
/// un local puede estar en dos rubros, así que el total se cuenta aparte).
class ResumenCategorias {
  const ResumenCategorias({
    this.categorias = const <CategoriaConConteo>[],
    this.totalServicios = 0,
    this.totalEstablecimientos = 0,
    this.otrosServicios = 0,
    this.otrosEstablecimientos = 0,
  });

  final List<CategoriaConConteo> categorias;

  /// Pares local-servicio visibles en todo el catálogo (sin duplicar).
  final int totalServicios;

  /// Locales distintos con algo visible.
  final int totalEstablecimientos;

  /// Visibles sin categoría asignada (taxonomía nula o apagada). Se enseña en
  /// una fila «Otras» solo si hay algo: esos servicios existen y el cliente
  /// puede reservarlos, así que no pueden desaparecer del recuento.
  final int otrosServicios;
  final int otrosEstablecimientos;

  static const ResumenCategorias vacio = ResumenCategorias();

  bool get hayOtros => otrosServicios > 0 || otrosEstablecimientos > 0;

  /// `true` cuando hay algo que contar. Lo usan la cabecera (para no pintar una
  /// pastilla «0 categorías · 0 establecimientos · 0 servicios», que es ruido) y
  /// el cuerpo (para elegir entre la rejilla y el estado vacío).
  bool get hayAlgo => categorias.isNotEmpty || hayOtros;

  /// Cuántas raíces activas tiene el nomenclador: es el número del chip
  /// «N ACTIVAS» de la rejilla del Home.
  int get categoriasActivas => categorias.length;

  factory ResumenCategorias.fromJson(Map<String, dynamic> json) {
    final lista = (json['categorias'] as List?) ?? const <dynamic>[];
    return ResumenCategorias(
      categorias: lista
          .whereType<Map>()
          .map((c) => CategoriaConConteo.fromJson(Map<String, dynamic>.from(c)))
          .toList(growable: false),
      totalServicios: (json['total_servicios'] as num?)?.toInt() ?? 0,
      totalEstablecimientos:
          (json['total_establecimientos'] as num?)?.toInt() ?? 0,
      otrosServicios: (json['otros_servicios'] as num?)?.toInt() ?? 0,
      otrosEstablecimientos:
          (json['otros_establecimientos'] as num?)?.toInt() ?? 0,
    );
  }
}

/// `"1 establecimiento"` / `"3 establecimientos"` / `"Todavía sin establecimientos"`.
///
/// Está aquí (y no en cada pantalla) porque lo usan la fila de categoría, la de
/// subcategoría, el CTA y la cabecera del listado.
String etiquetaConteoEstablecimientos(int total) {
  if (total <= 0) return 'Todavía sin establecimientos';
  return total == 1 ? '1 establecimiento' : '$total establecimientos';
}
/// Nodo de la taxonomía de servicios (`flow.nom_tipo_actividad_servicio`).
///
/// Son **dos niveles** (migración `47_categorias_reales_subcategorias.sql`):
/// * `idPadre == null` → **categoría** (lo que el Home pinta como filtro).
/// * `idPadre != null` → **subcategoría** de esa categoría.
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

  /// Clave estable. Ya viaja dentro de `cliente_home_feed` y de
  /// `cliente_obtener_servicios`, y de ella dependen los detectores de
  /// transporte (`transporte_omnibus`): no se cambia al editar.
  final String codigo;
  final String nombre;
  final bool activo;

  /// Categoría padre. `null` en una categoría.
  final int? idPadre;

  /// Menor número = aparece antes. Los empates se ordenan por nombre.
  final int orden;

  bool get esSubcategoria => idPadre != null;

  factory TipoActividad.fromJson(Map<String, dynamic> json) {
    return TipoActividad(
      id: (json['id'] as num).toInt(),
      codigo: json['codigo'] as String? ?? '',
      nombre: json['nombre'] as String? ?? '',
      activo: json['activo'] as bool? ?? true,
      idPadre: (json['id_padre'] as num?)?.toInt(),
      orden: (json['orden'] as num?)?.toInt() ?? 0,
    );
  }

  /// Normaliza un nombre a código, igual que el RPC del servidor: minúsculas,
  /// sin acentos y con `_` en lugar de cualquier otro separador.
  static String codigoDesdeNombre(String nombre) {
    const acentos = {
      'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n',
      'Á': 'A', 'É': 'E', 'Í': 'I', 'Ó': 'O', 'Ú': 'U', 'Ü': 'U', 'Ñ': 'N',
    };
    final buffer = StringBuffer();
    for (final rune in nombre.trim().toLowerCase().runes) {
      final caracter = String.fromCharCode(rune);
      buffer.write(acentos[caracter] ?? caracter);
      // Se normaliza a ASCII básico después de quitar acentos: lo que no sea
      // letra o dígito se convierte en `_`.
    }
    var texto = buffer.toString();
    texto = texto.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return texto.replaceAll(RegExp(r'^_+|_+$'), '');
  }

  static bool codigoValido(String codigo) =>
      RegExp(r'^[a-z0-9_]{3,64}$').hasMatch(codigo);
}

/// La taxonomía completa, indexada y ordenada por niveles.
class Taxonomia {
  Taxonomia(List<TipoActividad> nodos)
    : todas = List<TipoActividad>.unmodifiable(nodos) {
    for (final t in nodos) {
      _porId[t.id] = t;
    }
  }

  static final Taxonomia vacia = Taxonomia(const <TipoActividad>[]);

  final List<TipoActividad> todas;
  final Map<int, TipoActividad> _porId = <int, TipoActividad>{};

  bool get estaVacia => todas.isEmpty;

  /// Categorías (nivel 1) ordenadas por `orden` y luego por nombre.
  List<TipoActividad> get raices {
    final lista = todas.where((t) => !t.esSubcategoria).toList()
      ..sort(_porOrden);
    return List<TipoActividad>.unmodifiable(lista);
  }

  List<TipoActividad> subcategoriasDe(int? idCategoria) {
    if (idCategoria == null) return const <TipoActividad>[];
    final lista = todas.where((t) => t.idPadre == idCategoria).toList()
      ..sort(_porOrden);
    return List<TipoActividad>.unmodifiable(lista);
  }

  TipoActividad? porId(int? id) => id == null ? null : _porId[id];

  static int _porOrden(TipoActividad a, TipoActividad b) {
    final porOrden = a.orden.compareTo(b.orden);
    if (porOrden != 0) return porOrden;
    return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
  }
}

/// Expansión de recetas anidadas (espejo de
/// `fn_obtener_ingredientes_recursivos` en Postgres).
///
/// - Solo descompone ingredientes con [esElaborado] = true.
/// - Un servicio o producto físico como hoja no se descompone.
/// - Si un elaborado anidado no tiene receta en [recetas], el resultado
///   queda [RecipeExpandResult.incompleto] (no se inventa stock).
/// - Ciclos y profundidad > [maxNivel] también marcan incompleto.

class RecipeLeaf {
  final int idIngrediente;
  final double cantidad;
  final int nivel;
  final String? nombre;
  final String? unidad;

  const RecipeLeaf({
    required this.idIngrediente,
    required this.cantidad,
    required this.nivel,
    this.nombre,
    this.unidad,
  });
}

class RecipeExpandResult {
  final List<RecipeLeaf> hojas;
  final bool incompleto;
  final String? motivo;

  const RecipeExpandResult({
    required this.hojas,
    this.incompleto = false,
    this.motivo,
  });

  static RecipeExpandResult ok(List<RecipeLeaf> hojas) =>
      RecipeExpandResult(hojas: hojas);

  static RecipeExpandResult fail(String motivo) =>
      RecipeExpandResult(hojas: const [], incompleto: true, motivo: motivo);
}

/// [recetas]: id de elaborado/servicio → filas de ingredientes.
/// Cada fila admite `producto_id` / `id_ingrediente`, `cantidad_necesaria`,
/// y opcionales `producto_nombre` / `nombre_ingrediente` / `unidad_medida`.
///
/// [idsElaborados]: productos que son elaborados (solo esos se expanden).
RecipeExpandResult expandirReceta({
  required int idProducto,
  required double cantidad,
  required Map<int, List<Map<String, dynamic>>> recetas,
  required Set<int> idsElaborados,
  int maxNivel = 10,
}) {
  if (cantidad <= 0) {
    return RecipeExpandResult.ok(const []);
  }

  final acumulado = <int, _AccLeaf>{};
  final visitando = <int>{};

  String? incompleto;

  void walk(int productoId, double factor, int nivel, List<int> ruta) {
    if (incompleto != null) return;
    if (nivel > maxNivel) {
      incompleto =
          'La receta de $productoId supera el límite de anidación ($maxNivel)';
      return;
    }
    if (ruta.contains(productoId)) {
      incompleto = 'Ciclo en receta: ${[...ruta, productoId].join(' → ')}';
      return;
    }

    final filas = recetas[productoId];
    if (filas == null || filas.isEmpty) {
      // Solo exigimos receta si este nodo se trató como elaborado a expandir.
      // El producto raíz siempre exige receta (llamador).
      incompleto = 'Sin receta sincronizada para el producto $productoId';
      return;
    }

    visitando.add(productoId);
    final nuevaRuta = [...ruta, productoId];

    for (final raw in filas) {
      if (incompleto != null) break;
      final idIng = _idDe(raw);
      if (idIng == null) continue;
      final necesaria = (raw['cantidad_necesaria'] as num?)?.toDouble() ?? 0.0;
      if (necesaria <= 0) continue;
      final total = necesaria * factor;
      final nombre = _nombreDe(raw);
      final unidad = _unidadDe(raw);

      if (idsElaborados.contains(idIng)) {
        walk(idIng, total, nivel + 1, nuevaRuta);
      } else {
        final acc = acumulado.putIfAbsent(
          idIng,
          () => _AccLeaf(nombre: nombre, unidad: unidad),
        );
        acc.cantidad += total;
        if (nivel + 1 > acc.nivel) acc.nivel = nivel + 1;
        acc.nombre ??= nombre;
        acc.unidad ??= unidad;
      }
    }

    visitando.remove(productoId);
  }

  // El producto raíz se expandió aunque no esté en idsElaborados (sirve
  // para servicios con BOM). Si no hay receta → incompleto.
  if (!recetas.containsKey(idProducto) ||
      (recetas[idProducto]?.isEmpty ?? true)) {
    return RecipeExpandResult.fail(
      'Sin receta sincronizada para el producto $idProducto',
    );
  }

  walk(idProducto, cantidad, 0, const []);

  if (incompleto != null) {
    return RecipeExpandResult.fail(incompleto!);
  }

  final hojas =
      acumulado.entries
          .map(
            (e) => RecipeLeaf(
              idIngrediente: e.key,
              cantidad: e.value.cantidad,
              nivel: e.value.nivel,
              nombre: e.value.nombre,
              unidad: e.value.unidad,
            ),
          )
          .toList()
        ..sort((a, b) => a.idIngrediente.compareTo(b.idIngrediente));

  return RecipeExpandResult.ok(hojas);
}

int? _idDe(Map<String, dynamic> raw) {
  final a = raw['producto_id'] ?? raw['id_ingrediente'] ?? raw['id'];
  if (a is int) return a;
  if (a is num) return a.toInt();
  return int.tryParse(a?.toString() ?? '');
}

String? _nombreDe(Map<String, dynamic> raw) {
  final n =
      raw['producto_nombre'] ??
      raw['nombre_ingrediente'] ??
      raw['denominacion'];
  final s = n?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

String? _unidadDe(Map<String, dynamic> raw) {
  final u = raw['unidad_medida'] ?? raw['presentacion_base'];
  final s = u?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

class _AccLeaf {
  double cantidad = 0;
  int nivel = 1;
  String? nombre;
  String? unidad;

  _AccLeaf({this.nombre, this.unidad});
}

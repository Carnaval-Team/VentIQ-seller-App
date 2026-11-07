import '../models/order.dart';

/// Línea de consumo (gasto) de un ingrediente en el turno.
class IngredientConsumoLine {
  final String nombre;
  final String unidad;
  final double cantidad;

  const IngredientConsumoLine({
    required this.nombre,
    required this.unidad,
    required this.cantidad,
  });

  String get label {
    final u = unidad.trim();
    return u.isEmpty ? nombre : '$nombre ($u)';
  }
}

/// Desglose para el ticket de resumen de ventas.
class VentaPrintBreakdown {
  /// Cantidad vendida agrupada por nombre de producto (incluye elaborados).
  final Map<String, double> productosPorNombre;

  /// Gasto agregado de ingredientes de elaborados vendidos.
  final List<IngredientConsumoLine> ingredientesConsumo;

  const VentaPrintBreakdown({
    required this.productosPorNombre,
    required this.ingredientesConsumo,
  });
}

/// Agrupa productos vendidos y calcula el gasto de ingredientes de elaborados.
///
/// Fuentes de ingredientes (en orden):
/// 1. `OrderItem.ingredientes` (si la línea ya trae desglose)
/// 2. Recetas de [loadRecipes] para elaborados sin desglose en la línea
///
/// Las cantidades de receta están en unidades base; se multiplican por
/// [OrderItem.equivalenteBase] (cantidad × factor de presentación).
Future<VentaPrintBreakdown> buildVentaPrintBreakdown(
  List<OrderItem> items, {
  Future<Map<int, List<Map<String, dynamic>>>> Function(Set<int> elaboradoIds)?
      loadRecipes,
}) async {
  final productosPorNombre = <String, double>{};
  final consumo = <String, _Acc>{};

  final pendingRecipeItems = <OrderItem>[];
  final pendingIds = <int>{};

  for (final item in items) {
    productosPorNombre.update(
      item.nombre,
      (qty) => qty + item.cantidad,
      ifAbsent: () => item.cantidad,
    );

    final lineIngs = item.ingredientes;
    if (lineIngs != null && lineIngs.isNotEmpty) {
      for (final raw in lineIngs) {
        if (raw is! Map) continue;
        final ing = Map<String, dynamic>.from(raw);
        final nombre =
            (ing['nombre_ingrediente'] ??
                    ing['producto_nombre'] ??
                    ing['denominacion'] ??
                    'Ingrediente')
                .toString();
        final unidad = (ing['unidad_medida'] ?? 'unidades').toString();
        final qty = _qtyFromLineIngredient(ing, item);
        if (qty <= 0) continue;
        _accumulate(consumo, nombre, unidad, qty);
      }
      continue;
    }

    // Sin desglose en la línea: pedir receta. Cubre elaborados online
    // (listar trae es_elaborado pero no ingredientes) y pendientes offline
    // viejos sin flag; los no-elaborados simplemente no tendrán filas.
    pendingRecipeItems.add(item);
    pendingIds.add(item.producto.id);
  }

  if (pendingRecipeItems.isNotEmpty && loadRecipes != null) {
    final recipes = await loadRecipes(pendingIds);
    for (final item in pendingRecipeItems) {
      final rows = recipes[item.producto.id];
      if (rows == null || rows.isEmpty) continue;
      final factor = item.equivalenteBase;
      for (final row in rows) {
        final nombre =
            (row['nombre_ingrediente'] ??
                    row['producto_nombre'] ??
                    row['denominacion'] ??
                    'Ingrediente')
                .toString();
        final unidad = (row['unidad_medida'] ?? 'unidades').toString();
        final necesaria =
            (row['cantidad_necesaria'] as num?)?.toDouble() ?? 0.0;
        final qty = necesaria * factor;
        if (qty <= 0) continue;
        _accumulate(consumo, nombre, unidad, qty);
      }
    }
  }

  final ingredientes =
      consumo.entries.map((e) {
          final parts = e.key.split('\u0001');
          return IngredientConsumoLine(
            nombre: parts[0],
            unidad: parts.length > 1 ? parts[1] : '',
            cantidad: e.value.cantidad,
          );
        }).toList()
        ..sort(
          (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
        );

  return VentaPrintBreakdown(
    productosPorNombre: productosPorNombre,
    ingredientesConsumo: ingredientes,
  );
}

double _qtyFromLineIngredient(Map<String, dynamic> ing, OrderItem item) {
  final vendida = (ing['cantidad_vendida'] as num?)?.toDouble();
  if (vendida != null && vendida > 0) return vendida;

  final directa = (ing['cantidad'] as num?)?.toDouble();
  if (directa != null && directa > 0) {
    // Si ya viene el gasto total de la línea, no re-multiplicar.
    return directa;
  }

  final necesaria = (ing['cantidad_necesaria'] as num?)?.toDouble() ?? 0.0;
  if (necesaria > 0) return necesaria * item.equivalenteBase;
  return 0.0;
}

class _Acc {
  double cantidad = 0;
}

void _accumulate(
  Map<String, _Acc> map,
  String nombre,
  String unidad,
  double qty,
) {
  final key = '$nombre\u0001${unidad.trim()}';
  final acc = map.putIfAbsent(key, () => _Acc());
  acc.cantidad += qty;
}

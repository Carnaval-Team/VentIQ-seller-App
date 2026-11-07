import '../models/order.dart';
import '../utils/venta_ingredient_consumo.dart';

/// Implementación stub para plataformas no web
class WebSummaryPrinterServiceImpl {
  /// Imprime el resumen detallado de productos (stub)
  Future<bool> printDetailedSummary({
    required List<OrderItem> productosVendidos,
    required double totalVentas,
    required double totalProductos,
    required double totalEgresado,
    required double totalEfectivoReal,
    required Map<String, double> totalesPorMedioPago,
    Map<String, double>? productosAgrupados,
    List<IngredientConsumoLine>? ingredientesConsumo,
  }) async {
    print(
      '❌ Impresión web de resumen detallado no disponible en esta plataforma',
    );
    return false;
  }
}

import '../models/order.dart';

/// Implementación stub para plataformas no web
class WebSummaryPrinterServiceImpl {
  /// Imprime el resumen detallado de productos (stub)
  Future<bool> printDetailedSummary({
    required List<OrderItem> productosVendidos,
    required double totalVentas,
    required double totalProductos,
    required double totalEgresado,
    required double totalEfectivoReal,
  }) async {
    print(
      '❌ Impresión web de resumen detallado no disponible en esta plataforma',
    );
    return false;
  }
}

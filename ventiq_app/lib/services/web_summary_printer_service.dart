import '../models/order.dart';

// Importaciones condicionales
import 'web_summary_printer_service_stub.dart'
    if (dart.library.html) 'web_summary_printer_service_web.dart';

/// Servicio de impresión de resumen detallado específico para plataforma web
/// Permite imprimir resúmenes detallados en impresoras de red o USB en Windows
class WebSummaryPrinterService {
  final WebSummaryPrinterServiceImpl _impl = WebSummaryPrinterServiceImpl();

  /// Imprime el resumen detallado de productos usando la API de impresión del navegador
  Future<bool> printDetailedSummary({
    required List<OrderItem> productosVendidos,
    required double totalVentas,
    required int totalProductos,
    required double totalEgresado,
    required double totalEfectivoReal,
  }) async {
    return await _impl.printDetailedSummary(
      productosVendidos: productosVendidos,
      totalVentas: totalVentas,
      totalProductos: totalProductos,
      totalEgresado: totalEgresado,
      totalEfectivoReal: totalEfectivoReal,
    );
  }
}

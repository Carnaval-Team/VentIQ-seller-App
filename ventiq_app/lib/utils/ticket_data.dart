import '../models/order.dart';
import '../money/ticket_v1.dart';
import 'price_utils.dart';

/// Datos del ticket que comparten la impresión térmica (ESC/POS) y la web
/// (HTML). Sin dependencias de impresión: se puede probar sin impresora.
class TicketData {
  const TicketData._();

  /// Líneas de producto de una orden, ya con el subtotal formateado.
  ///
  /// [dineroLegacy] formatea un importe CUP para las órdenes anteriores a
  /// `producto-v1` (misma conversión que usaba el ticket).
  static List<({String cantidad, String nombre, String subtotal})> productos(
    Order order, {
    required String Function(double cup) dineroLegacy,
  }) {
    if (order.versionMonetaria == 'producto-v1') return TicketV1.detalle(order);
    return [
      for (final item in order.items)
        (
          cantidad: PriceUtils.formatQuantity(item.cantidad),
          nombre: item.producto.denominacion,
          subtotal: dineroLegacy(item.cantidad * item.precioUnitario),
        ),
    ];
  }

  /// Totales por moneda. Una orden `producto-v1` puede traer varias; una
  /// anterior trae una sola, en la moneda con que se mostró el cobro.
  static List<({String moneda, String monto})> totales(
    Order order, {
    required List<Map<String, dynamic>> pagos,
    double? usdRate,
  }) {
    if (order.versionMonetaria == 'producto-v1') {
      return TicketV1.totalesPorMoneda(order);
    }
    final moneda = PriceUtils.paymentDisplayCurrency(pagos);
    final monto = PriceUtils.cupToTicketAmount(
      order.total,
      pagos,
      fallbackRate: usdRate,
    );
    return [
      (
        moneda: moneda,
        monto: PriceUtils.formatAmount(
          monto,
          decimals: moneda == PriceUtils.baseCurrency ? 0 : 2,
          separator: ' ',
        ),
      ),
    ];
  }

  /// Pie de la guía de almacén: cuántos productos distintos, sin importes.
  static String almacenResumen(int productos) => 'TOT: $productos prod';
}

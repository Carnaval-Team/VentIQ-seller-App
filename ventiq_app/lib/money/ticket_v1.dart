import '../models/order.dart';
import 'venta_v1_envio.dart';

/// Ticket y caja de la venta nueva. CUP y USD no se suman.
class TicketV1 {
  /// Totales nativos por moneda para la UI (preorden, paneles de orden).
  /// No mezcla divisas ni descuenta líneas pendientes: es lo que la orden
  /// debe en cada moneda. Las líneas legacy cuentan como CUP.
  static Map<String, double> totalesNativos(Order order) {
    final grupos = <String, double>{};
    for (final item in order.items) {
      final moneda = item.seleccion?.monedaVenta ?? 'CUP';
      grupos[moneda] = (grupos[moneda] ?? 0.0) + item.subtotal;
    }
    return grupos;
  }

  /// Equivalente CUP de una línea según la tasa de su snapshot (arqueo,
  /// contar billetes, total escalar en contabilidad CUP).
  static double equivalenteCupItem(OrderItem item) {
    final seleccion = item.seleccion;
    if (seleccion == null) return item.subtotal;
    final cobro = VentaV1Lineas.desdeMapa(seleccion.toJson());
    if (cobro == null) return item.subtotal;
    return double.tryParse(cobro.cup) ?? item.subtotal;
  }

  /// Equivalente CUP de toda la orden.
  static double equivalenteCupOrden(Order order) {
    return order.items.fold(0.0, (sum, item) => sum + equivalenteCupItem(item));
  }

  static List<String> lineas(Order order) {
    if (order.versionMonetaria != 'producto-v1') return const [];
    final salida = <String>[];
    for (final item in order.items) {
      final seleccion = item.seleccion;
      if (seleccion == null) {
        throw StateError('La linea nueva no tiene moneda');
      }
      final cobro = VentaV1Lineas.desdeMapa(seleccion.toJson());
      if (cobro == null || !cobro.tasaDisponible) {
        throw StateError('Falta la tasa de la linea');
      }
      final nombre = item.producto.denominacion;
      final marca = cobro.pendiente ? ' pendiente' : '';
      salida.add('${seleccion.cantidad}x $nombre  ${cobro.neto} ${cobro.moneda}$marca');
    }
    return salida;
  }

  static List<String> totales(Order order) {
    final grupos = <String, String>{};
    for (final item in order.items) {
      final cobro = item.seleccion == null
          ? null
          : VentaV1Lineas.desdeMapa(item.seleccion!.toJson());
      if (cobro == null || cobro.pendiente || cobro.neto == '0.00') continue;
      grupos[cobro.moneda] = _sumar(grupos[cobro.moneda], cobro.neto);
    }
    return [
      for (final moneda in grupos.keys) 'TOTAL $moneda ${grupos[moneda]}',
    ];
  }

  static String _sumar(String? actual, String neto) {
    final lineas = [
      if (actual != null)
        LineaCobro(
          idLinea: 'a',
          moneda: 'CUP',
          medio: null,
          pendiente: false,
          neto: actual,
          cup: actual,
          tasaDisponible: true,
        ),
      LineaCobro(
        idLinea: 'b',
        moneda: 'CUP',
        medio: null,
        pendiente: false,
        neto: neto,
        cup: neto,
        tasaDisponible: true,
      ),
    ];
    return CheckoutV1.agrupar(lineas).single.neto;
  }
}

class CajaV1 {
  static String sumar(String? actual, String neto) => _sumar(actual, neto);

  /// El total escalar de una orden nueva no entra en el cuadre CUP.
  static Map<String, String> porMoneda(Map<String, dynamic> order) {
    if (order['version_monetaria'] != 'producto-v1') return const {};
    final items = order['items'];
    if (items is! List) return const {};
    final grupos = <String, String>{};
    for (final raw in items) {
      if (raw is! Map || raw['seleccion'] is! Map) continue;
      final cobro = VentaV1Lineas.desdeMapa(
        Map<String, dynamic>.from(raw['seleccion'] as Map),
      );
      if (cobro == null || cobro.pendiente || !cobro.tasaDisponible) continue;
      if (cobro.neto == '0.00') continue;
      grupos[cobro.moneda] = _sumar(grupos[cobro.moneda], cobro.neto);
    }
    return grupos;
  }

  static String _sumar(String? actual, String neto) {
    if (actual == null) return neto;
    final grupos = CheckoutV1.agrupar([
      LineaCobro(
        idLinea: 'a',
        moneda: 'CUP',
        medio: 1,
        pendiente: false,
        neto: actual,
        cup: actual,
        tasaDisponible: true,
      ),
      LineaCobro(
        idLinea: 'b',
        moneda: 'CUP',
        medio: 1,
        pendiente: false,
        neto: neto,
        cup: neto,
        tasaDisponible: true,
      ),
    ]);
    return grupos.single.neto;
  }
}

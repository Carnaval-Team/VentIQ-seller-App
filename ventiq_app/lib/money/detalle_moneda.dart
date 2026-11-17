import '../models/payment_method.dart';
import '../utils/uuid_generator.dart';
import 'product_currency_order.dart';

class DetalleMonedaException implements Exception {
  final String message;
  DetalleMonedaException(this.message);
  @override
  String toString() => message;
}

/// El precio de la moneda elegida sale de la configuración. Si no está, no se vende.
class DetalleMoneda {
  static String? precioConfigurado({
    required String moneda,
    required double precioCup,
    required double? precioUsd,
    required String? origenUsd,
    required double factor,
    required bool esVariante,
  }) {
    if (factor <= 0 || factor.isNaN || factor.isInfinite) return null;
    final double? base;
    if (moneda == 'CUP') {
      base = precioCup > 0 ? precioCup : null;
    } else if (moneda == 'USD') {
      if (origenUsd == 'no_disponible') return null;
      if (esVariante && (precioUsd == null || precioUsd <= 0)) return null;
      base = precioUsd != null && precioUsd > 0 ? precioUsd : null;
    } else {
      return null;
    }
    if (base == null) return null;
    final unitario = base * factor;
    if (unitario <= 0 || unitario.isNaN || unitario.isInfinite) return null;
    return unitario.toStringAsFixed(2);
  }

  static PaymentMethod? medioReal(List<PaymentMethod> medios) {
    for (final medio in medios) {
      if (medio.esActivo && medio.esEfectivo && !medio.esPagoPendiente) {
        return medio;
      }
    }
    for (final medio in medios) {
      if (medio.esActivo && !medio.esPagoPendiente) return medio;
    }
    return null;
  }

  static ProductCurrencySeleccion seleccion({
    required int idProducto,
    required double cantidad,
    required String moneda,
    required String precio,
    required String tasa,
    required int idMedioPago,
  }) {
    if (cantidad <= 0) {
      throw DetalleMonedaException('La cantidad tiene que ser mayor que cero');
    }
    if (moneda == 'USD' && (tasa.isEmpty || tasa == '0' || tasa == '0.00')) {
      throw DetalleMonedaException('Falta la tasa configurada de USD');
    }
    final tasaEfectiva = moneda == 'CUP' ? '1.00' : tasa;
    return ProductCurrencySeleccion(
      idLineaCliente: UuidGenerator.v4(),
      idProducto: '$idProducto',
      cantidad: _cantidad(cantidad),
      monedaVenta: moneda,
      tipoCobro: 'medio_pago',
      idMedioPago: idMedioPago,
      precioUnitarioNativo: precio,
      descuentoManualUnitario: '0.00',
      snapshotPrecio: {'valor_publicado': precio},
      snapshotTasa: {
        'valor_publicado': tasaEfectiva,
        'evidencia_publicacion': 'tasa-$moneda-$tasaEfectiva',
      },
      ajustesAutomaticos: const [],
    );
  }

  static String _cantidad(double cantidad) {
    var texto = cantidad.toStringAsFixed(3);
    texto = texto.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    return texto;
  }
}

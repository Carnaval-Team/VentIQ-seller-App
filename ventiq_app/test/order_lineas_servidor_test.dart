import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/services/order_service.dart';

void main() {
  group('OrderService.claveLineaServidor', () {
    test('mismo producto en CUP y en USD son dos líneas', () {
      final cup = {
        'id_extraccion': 501,
        'id_producto': 16,
        'id_linea_cliente': 'a',
        'moneda_venta': 'CUP',
      };
      final usd = {
        'id_extraccion': 502,
        'id_producto': 16,
        'id_linea_cliente': 'b',
        'moneda_venta': 'USD',
      };
      expect(
        OrderService.claveLineaServidor(cup),
        isNot(OrderService.claveLineaServidor(usd)),
      );
    });

    test('la misma extracción repetida por el join es una sola línea', () {
      final fila = {'id_extraccion': 501, 'id_producto': 16};
      expect(
        OrderService.claveLineaServidor({...fila, 'cantidad_inicial': 10}),
        OrderService.claveLineaServidor({...fila, 'cantidad_inicial': 4}),
      );
    });

    test('sin id_extraccion usa la línea del cliente', () {
      expect(
        OrderService.claveLineaServidor(
          {'id_producto': 16, 'id_linea_cliente': 'a'},
        ),
        isNot(
          OrderService.claveLineaServidor(
            {'id_producto': 16, 'id_linea_cliente': 'b'},
          ),
        ),
      );
    });

    test('respaldo legacy distingue moneda y ubicación', () {
      final base = {'id_producto': 16, 'id_ubicacion': 1, 'moneda_venta': 'CUP'};
      expect(
        OrderService.claveLineaServidor(base),
        isNot(OrderService.claveLineaServidor({...base, 'moneda_venta': 'USD'})),
      );
      expect(
        OrderService.claveLineaServidor(base),
        isNot(OrderService.claveLineaServidor({...base, 'id_ubicacion': 2})),
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/models/order.dart';
import 'package:ventiq_app/models/product.dart';
import 'package:ventiq_app/money/product_currency_order.dart';
import 'package:ventiq_app/money/ticket_v1.dart';
import 'package:ventiq_app/services/order_service.dart';

ProductCurrencySeleccion _seleccion({String cantidad = '1'}) {
  return ProductCurrencySeleccion(
    idLineaCliente: '00000000-0000-4000-8000-0000000000aa',
    idProducto: '15',
    cantidad: cantidad,
    monedaVenta: 'CUP',
    tipoCobro: 'medio_pago',
    idMedioPago: 1,
    precioUnitarioNativo: '100.00',
    descuentoManualUnitario: '0',
    snapshotPrecio: const {'tipo': 'general', 'valor_publicado': '100.00'},
    snapshotTasa: const {
      'valor_publicado': '1',
      'evidencia_publicacion': 'fixture-only',
    },
    ajustesAutomaticos: const [],
  );
}

OrderItem _diesel(double cantidad, ProductCurrencySeleccion sel) => OrderItem(
  id: 'item-15',
  producto: Product.fromJson({
    'id': 15,
    'denominacion': 'Diesel',
    'precio': 100,
  }),
  cantidad: cantidad,
  precioUnitario: 100,
  ubicacionAlmacen: 'test',
  seleccion: sel,
);

void main() {
  group('cantidad de la línea v1', () {
    test('cambiar la cantidad del ítem cambia la de su selección', () {
      final item = _diesel(1, _seleccion()).copyWith(cantidad: 5);

      expect(item.seleccion!.cantidad, '5');
      final order = Order(
        id: 'o1',
        fechaCreacion: DateTime(2026, 1, 1),
        items: [item],
        total: item.subtotal,
        status: OrderStatus.borrador,
        versionMonetaria: 'producto-v1',
      );
      final linea = TicketV1.detalle(order).single;
      expect(linea.cantidad, '5');
      expect(linea.subtotal, '500.00 CUP');
      expect(TicketV1.totalesPorMoneda(order).single.monto, '500.00');
    });

    test('cantidad fraccionada sin ceros de más', () {
      expect(_seleccion().conCantidad(2.5).cantidad, '2.5');
      expect(_seleccion().conCantidad(10).cantidad, '10');
    });

    test('un borrador guardado con la cantidad vieja se corrige al leerlo', () {
      final json = _diesel(5, _seleccion()).toJson();
      expect(OrderItem.fromJson(json).seleccion!.cantidad, '5');
    });
  });

  group('orden pendiente offline', () {
    Map<String, dynamic> pendiente({required bool v1}) => {
      'id': '1795200861678',
      'fecha_creacion': '2026-11-20T10:00:00.000Z',
      'total': 500.0,
      'estado': 'pendiente_sincronizacion',
      if (v1) 'version_monetaria': 'producto-v1',
      'items': [
        {
          'id_producto': 15,
          'denominacion': 'Diesel',
          'cantidad': 5.0,
          'precio_unitario': 100.0,
          'subtotal': 500.0,
          'id_medio_pago': 1,
          'metodo_pago': 'Efectivo',
          'medio_pago_es_efectivo': true,
          if (v1) 'seleccion': _seleccion(cantidad: '5').toJson(),
        },
      ],
      if (!v1)
        'desglose_pagos': [
          {
            'id_medio_pago': 1,
            'denominacion': 'Efectivo',
            'monto': 500.0,
            'moneda': 'CUP',
            'tasa_cambio': 1.0,
          },
        ],
    };

    test('conserva el medio de pago de la línea (legacy)', () {
      final service = OrderService()
        ..addPendingOrdersToList([pendiente(v1: false)]);
      final item = service.orders.last.items.single;
      expect(item.paymentMethod?.id, 1);
      expect(item.paymentMethod?.denominacion, 'Efectivo');
      expect(item.paymentMethod?.esEfectivo, isTrue);
      expect(item.subtotal, 500.0);
    });

    test('v1: el desglose usa el nombre guardado aunque el cache no lo tenga', () {
      final service = OrderService()
        ..addPendingOrdersToList([pendiente(v1: true)]);
      final order = service.orders.last;
      expect(order.pagos!.single['denominacion'], 'Efectivo');
      expect(order.items.single.paymentMethod?.id, 1);
      expect(TicketV1.detalle(order).single.cantidad, '5');
      expect(TicketV1.detalle(order).single.subtotal, '500.00 CUP');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/models/order.dart';
import 'package:ventiq_app/models/product.dart';
import 'package:ventiq_app/money/product_currency_order.dart';
import 'package:ventiq_app/money/ticket_v1.dart';
import 'package:ventiq_app/services/product_detail_service.dart';

ProductCurrencySeleccion seleccion({
  required String moneda,
  required String precio,
  String tasa = '1',
}) {
  return ProductCurrencySeleccion(
    idLineaCliente: '00000000-0000-4000-8000-0000000000aa',
    idProducto: '101',
    cantidad: '1',
    monedaVenta: moneda,
    tipoCobro: 'medio_pago',
    idMedioPago: 1,
    precioUnitarioNativo: precio,
    descuentoManualUnitario: '0',
    snapshotPrecio: const {'tipo': 'general', 'valor_publicado': '1'},
    snapshotTasa: {
      'valor_publicado': tasa,
      'evidencia_publicacion': 'fixture-only',
    },
    ajustesAutomaticos: const [],
  );
}

Product producto(int id, double precioCup) =>
    Product.fromJson({'id': id, 'denominacion': 'P$id', 'precio': precioCup});

OrderItem item({
  required int idProducto,
  required double precio,
  required double cantidad,
  ProductCurrencySeleccion? sel,
}) {
  return OrderItem(
    id: 'item-$idProducto',
    producto: producto(idProducto, precio),
    cantidad: cantidad,
    ubicacionAlmacen: 'test',
    precioUnitario: precio,
    seleccion: sel,
  );
}

Order orden({required List<OrderItem> items, String? version}) {
  return Order(
    id: 'o1',
    fechaCreacion: DateTime(2026, 1, 1),
    items: items,
    total: items.fold(0.0, (sum, i) => sum + i.subtotal),
    status: OrderStatus.borrador,
    versionMonetaria: version,
  );
}

void main() {
  group('TicketV1 totales por moneda', () {
    test('una orden v1 mezclada no suma CUP y USD en una sola cifra', () {
      final order = orden(
        version: 'producto-v1',
        items: [
          item(
            idProducto: 1,
            precio: 100,
            cantidad: 2,
            sel: seleccion(moneda: 'CUP', precio: '100'),
          ),
          item(
            idProducto: 2,
            precio: 1.05,
            cantidad: 3,
            sel: seleccion(moneda: 'USD', precio: '1.05', tasa: '400'),
          ),
        ],
      );

      final totales = TicketV1.totalesNativos(order);
      expect(totales, {'CUP': 200.0, 'USD': closeTo(3.15, 0.0001)});
    });

    test('una orden legacy cuenta todo como CUP', () {
      final order = orden(
        items: [
          item(idProducto: 1, precio: 50, cantidad: 2),
          item(idProducto: 2, precio: 25, cantidad: 1),
        ],
      );
      expect(TicketV1.totalesNativos(order), {'CUP': 125.0});
    });

    test('el equivalente CUP usa la tasa del snapshot de la línea', () {
      final usd = item(
        idProducto: 2,
        precio: 2.0,
        cantidad: 1,
        sel: seleccion(moneda: 'USD', precio: '2.00', tasa: '400'),
      );
      final cup = item(
        idProducto: 1,
        precio: 100,
        cantidad: 1,
        sel: seleccion(moneda: 'CUP', precio: '100'),
      );
      expect(TicketV1.equivalenteCupItem(usd), closeTo(800.0, 0.01));
      expect(TicketV1.equivalenteCupItem(cup), closeTo(100.0, 0.01));
      expect(
        TicketV1.equivalenteCupOrden(orden(items: [usd, cup])),
        closeTo(900.0, 0.01),
      );
    });
  });

  group('Precios vigentes cacheados (offline)', () {
    test('aplicarPreciosVigentes pobla precioUsd base y de variante', () {
      final base = producto(7, 100);
      final conPrecios = ProductDetailService.aplicarPreciosVigentes(base, [
        {
          'id_producto': 7,
          'id_variante': 0,
          'precio_venta_cup': 120,
          'precio_venta_usd': 0.35,
        },
      ]);
      expect(conPrecios.precio, 120);
      expect(conPrecios.precioUsd, 0.35);
      expect(conPrecios.origenPrecioUsd, 'general');
    });

    test('sin fila USD el producto queda sin precioUsd (sin inventarlo)', () {
      final base = producto(7, 100);
      final conPrecios = ProductDetailService.aplicarPreciosVigentes(base, [
        {'id_producto': 7, 'id_variante': 0, 'precio_venta_cup': 120},
      ]);
      expect(conPrecios.precio, 120);
      expect(conPrecios.precioUsd, isNull);
      expect(conPrecios.origenPrecioUsd, isNull);
    });

    test('el cache offline recupera el USD guardado junto al CUP', () {
      final filas = ProductDetailService.normalizarFilasPrecioVigente([
        {
          'id_producto': '7',
          'id_variante': null,
          'precio_venta_cup': '120',
          'precio_venta_usd': '0.35',
        },
      ]);
      expect(filas.single['precio_venta_usd'], 0.35);
      expect(
        ProductDetailService.precioUsdDeProductoCache({
          'precio': 120,
          'detalles_completos': {'precios_vigentes': filas},
        }),
        0.35,
      );
      expect(
        ProductDetailService.precioUsdDeProductoCache({
          'precio': 120,
          'precio_venta_usd': 0.35,
        }),
        0.35,
      );
    });
  });
}

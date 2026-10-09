import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/inventory.dart';

void main() {
  group('InventoryProduct from nuevo RPC obtener_reporte_inventario_export', () {
    test('parsea una fila con presentación y movimientos del periodo', () {
      final row = {
        'id_almacen': 352,
        'almacen': 'Almacen Casa matriz',
        'id_ubicacion': 378,
        'ubicacion': 'Casa',
        'id_producto': 11212,
        'nombre_producto': 'Producto A',
        'codigo': 'COD123',
        'categoria': 'Cat A',
        'sku': 'SKU123',
        'sku_producto': 'SKU123',
        'id_presentacion': 11482,
        'presentacion': 'Caja',
        'id_variante': null,
        'id_opcion_variante': null,
        'cantidad_inicial': 25.0,
        'entradas_periodo': 40.0,
        'extracciones_periodo': 0.0,
        'ventas_periodo': 21.0,
        'cantidad_reservada': 2.0,
        'cantidad_final': 2.0,
        'precio_venta': 150.0,
      };

      final product = InventoryProduct.fromMap(row);

      expect(product.idProducto, 11212);
      expect(product.nombreProducto, 'Producto A');
      expect(product.idPresentacion, 11482);
      expect(product.presentacion, 'Caja');
      expect(product.cantidadInicial, 25.0);
      expect(product.entradasPeriodo, 40.0);
      expect(product.extraccionesPeriodo, 0.0);
      expect(product.ventasPeriodo, 21.0);
      expect(product.stockReservado, 2.0);
      expect(product.cantidadFinal, 2.0);
    });

    test('parsea filas sin movimientos usando defaults', () {
      final row = {
        'id_producto': 11213,
        'nombre_producto': 'Producto B',
        'id_presentacion': 11483,
        'presentacion': 'Unidad',
        'cantidad_inicial': 0.0,
        'entradas_periodo': null,
        'extracciones_periodo': null,
        'ventas_periodo': null,
        'cantidad_reservada': null,
        'cantidad_final': 3.0,
      };

      final product = InventoryProduct.fromMap(row);

      expect(product.cantidadInicial, 0.0);
      expect(product.entradasPeriodo, isNull);
      expect(product.extraccionesPeriodo, isNull);
      expect(product.ventasPeriodo, isNull);
      expect(product.stockReservado, 0.0);
      expect(product.cantidadFinal, 3.0);
    });
  });
}

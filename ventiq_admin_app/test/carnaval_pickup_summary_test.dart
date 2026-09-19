import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/carnaval_pickup_summary.dart';

void main() {
  group('buildCarnavalPickupSummary', () {
    test(
      'excludes provider 177 and groups quantities by provider and product',
      () {
        final summary = buildCarnavalPickupSummary([
          {
            'order_id': 1001,
            'quantity': 2,
            'extra': 0.5,
            'Productos': {
              'id': 10,
              'name': 'Refresco',
              'proveedor': 201,
              'proveedores': {'id': 201, 'name': 'Bodega Centro'},
            },
          },
          {
            'order_id': 1002,
            'quantity': 3,
            'extra': 0,
            'Productos': {
              'id': 10,
              'name': 'Refresco',
              'proveedor': 201,
              'proveedores': {'id': 201, 'name': 'Bodega Centro'},
            },
          },
          {
            'order_id': 1003,
            'quantity': 4,
            'Productos': {
              'id': 11,
              'name': 'Pan',
              'proveedor': 177,
              'proveedores': {'id': 177, 'name': 'Tienda principal'},
            },
          },
        ], excludedProviderId: 177);

        expect(summary, hasLength(1));
        expect(summary.single.providerId, 201);
        expect(summary.single.providerName, 'Bodega Centro');
        expect(summary.single.products, hasLength(1));
        expect(summary.single.products.single.productName, 'Refresco');
        expect(summary.single.products.single.quantity, 5.5);
      },
    );

    test('builds one export row per provider and product', () {
      const summary = [
        CarnavalPickupProvider(
          providerId: 201,
          providerName: 'Bodega Centro',
          products: [
            CarnavalPickupProduct(
              productId: 10,
              productName: 'Refresco',
              quantity: 5.5,
              orders: [
                CarnavalPickupOrderQuantity(orderId: 1001, quantity: 2.5),
                CarnavalPickupOrderQuantity(orderId: 1002, quantity: 3),
              ],
            ),
          ],
        ),
      ];

      expect(buildCarnavalPickupExportRows(summary), [
        {
          'proveedor': 'Bodega Centro',
          'orden': 1001,
          'producto': 'Refresco',
          'cantidad': 2.5,
        },
        {
          'proveedor': 'Bodega Centro',
          'orden': 1002,
          'producto': 'Refresco',
          'cantidad': 3.0,
        },
      ]);
    });

    test('sorts providers and products by name and ignores invalid rows', () {
      final summary = buildCarnavalPickupSummary([
        {'order_id': 2000, 'quantity': 9, 'Productos': null},
        {
          'order_id': 2001,
          'quantity': 1,
          'Productos': {
            'id': 3,
            'name': 'Yogur',
            'proveedor': 300,
            'proveedores': {'id': 300, 'name': 'Mercado Z'},
          },
        },
        {
          'order_id': 2002,
          'quantity': 2,
          'Productos': {
            'id': 2,
            'name': 'Arroz',
            'proveedor': 200,
            'proveedores': {'id': 200, 'name': 'Almacén A'},
          },
        },
      ], excludedProviderId: 177);

      expect(summary.map((group) => group.providerName), [
        'Almacén A',
        'Mercado Z',
      ]);
      expect(summary.first.products.single.productName, 'Arroz');
    });
  });
}

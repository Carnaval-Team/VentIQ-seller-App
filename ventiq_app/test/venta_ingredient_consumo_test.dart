import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/models/order.dart';
import 'package:ventiq_app/models/product.dart';
import 'package:ventiq_app/utils/venta_ingredient_consumo.dart';

Product _product({
  required int id,
  required String nombre,
  bool elaborado = false,
}) {
  return Product(
    id: id,
    denominacion: nombre,
    precio: 10,
    cantidad: 0,
    esRefrigerado: false,
    esFragil: false,
    esPeligroso: false,
    esVendible: true,
    esComprable: false,
    esInventariable: true,
    esPorLotes: false,
    esElaborado: elaborado,
    esServicio: false,
    categoria: 'test',
  );
}

OrderItem _item({
  required Product producto,
  required double cantidad,
  List<dynamic>? ingredientes,
  double? presentacionFactor,
}) {
  return OrderItem(
    id: 'i-${producto.id}-$cantidad',
    producto: producto,
    cantidad: cantidad,
    precioUnitario: 10,
    ubicacionAlmacen: 'A1',
    ingredientes: ingredientes,
    presentacionFactor: presentacionFactor,
  );
}

void main() {
  test('agrupa productos y gasta ingredientes desde la línea', () async {
    final arrozMoro = _product(id: 1, nombre: 'Arroz Moro', elaborado: true);
    final agua = _product(id: 2, nombre: 'Agua');

    final breakdown = await buildVentaPrintBreakdown([
      _item(
        producto: arrozMoro,
        cantidad: 2,
        ingredientes: [
          {
            'nombre_ingrediente': 'Arroz',
            'unidad_medida': 'g',
            'cantidad_vendida': 400,
          },
          {
            'nombre_ingrediente': 'Frijoles',
            'unidad_medida': 'g',
            'cantidad_necesaria': 100,
          },
        ],
      ),
      _item(producto: agua, cantidad: 3),
    ]);

    expect(breakdown.productosPorNombre['Arroz Moro'], 2);
    expect(breakdown.productosPorNombre['Agua'], 3);
    expect(breakdown.ingredientesConsumo.length, 2);

    final arroz = breakdown.ingredientesConsumo.firstWhere(
      (e) => e.nombre == 'Arroz',
    );
    expect(arroz.cantidad, 400);
    expect(arroz.unidad, 'g');

    final frijoles = breakdown.ingredientesConsumo.firstWhere(
      (e) => e.nombre == 'Frijoles',
    );
    // cantidad_necesaria * equivalenteBase (2 * factor 1)
    expect(frijoles.cantidad, 200);
  });

  test('expande elaborados sin desglose usando receta', () async {
    final pizza = _product(id: 10, nombre: 'Pizza', elaborado: true);

    final breakdown = await buildVentaPrintBreakdown(
      [
        _item(producto: pizza, cantidad: 2, presentacionFactor: 1),
      ],
      loadRecipes: (ids) async {
        expect(ids, {10});
        return {
          10: [
            {
              'nombre_ingrediente': 'Harina',
              'unidad_medida': 'g',
              'cantidad_necesaria': 250,
            },
            {
              'nombre_ingrediente': 'Queso',
              'unidad_medida': 'g',
              'cantidad_necesaria': 100,
            },
          ],
        };
      },
    );

    expect(breakdown.productosPorNombre['Pizza'], 2);
    expect(breakdown.ingredientesConsumo.length, 2);
    expect(
      breakdown.ingredientesConsumo
          .firstWhere((e) => e.nombre == 'Harina')
          .cantidad,
      500,
    );
    expect(
      breakdown.ingredientesConsumo
          .firstWhere((e) => e.nombre == 'Queso')
          .cantidad,
      200,
    );
  });

  test('suma el mismo ingrediente de varios elaborados', () async {
    final a = _product(id: 1, nombre: 'Plato A', elaborado: true);
    final b = _product(id: 2, nombre: 'Plato B', elaborado: true);

    final breakdown = await buildVentaPrintBreakdown([
      _item(
        producto: a,
        cantidad: 1,
        ingredientes: [
          {
            'nombre_ingrediente': 'Aceite',
            'unidad_medida': 'ml',
            'cantidad_vendida': 10,
          },
        ],
      ),
      _item(
        producto: b,
        cantidad: 1,
        ingredientes: [
          {
            'nombre_ingrediente': 'Aceite',
            'unidad_medida': 'ml',
            'cantidad_vendida': 15,
          },
        ],
      ),
    ]);

    expect(breakdown.ingredientesConsumo.length, 1);
    expect(breakdown.ingredientesConsumo.first.cantidad, 25);
  });

  test(
    'pendiente sin es_elaborado aún gasta ingredientes si hay receta',
    () async {
      // Simula orden offline vieja: flag false, sin ingredientes en línea.
      final plato = _product(id: 77, nombre: 'Plato', elaborado: false);

      final breakdown = await buildVentaPrintBreakdown(
        [_item(producto: plato, cantidad: 3)],
        loadRecipes: (ids) async {
          expect(ids, {77});
          return {
            77: [
              {
                'nombre_ingrediente': 'Sal',
                'unidad_medida': 'g',
                'cantidad_necesaria': 5,
              },
            ],
          };
        },
      );

      expect(breakdown.ingredientesConsumo.single.nombre, 'Sal');
      expect(breakdown.ingredientesConsumo.single.cantidad, 15);
    },
  );
}

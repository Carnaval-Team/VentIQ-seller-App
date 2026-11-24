import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/utils/elaborado_recipe_expand.dart';

void main() {
  Map<String, dynamic> fila(
    int id,
    double cantidad, {
    String? nombre,
    String? unidad,
  }) => {
    'producto_id': id,
    'cantidad_necesaria': cantidad,
    if (nombre != null) 'producto_nombre': nombre,
    if (unidad != null) 'unidad_medida': unidad,
  };

  test('sin receta del producto raíz queda incompleto', () {
    final r = expandirReceta(
      idProducto: 1,
      cantidad: 1,
      recetas: {},
      idsElaborados: {1},
    );
    expect(r.incompleto, isTrue);
    expect(r.hojas, isEmpty);
    expect(r.motivo, contains('Sin receta'));
  });

  test('receta plana: hojas = ingredientes físicos', () {
    final r = expandirReceta(
      idProducto: 10,
      cantidad: 2,
      recetas: {
        10: [
          fila(100, 0.3, nombre: 'carne', unidad: 'Kilogramo'),
          fila(101, 2, nombre: 'jugo', unidad: 'Bolsa'),
        ],
      },
      idsElaborados: {10},
    );
    expect(r.incompleto, isFalse);
    expect(r.hojas, hasLength(2));
    expect(r.hojas[0].idIngrediente, 100);
    expect(r.hojas[0].cantidad, closeTo(0.6, 1e-9));
    expect(r.hojas[1].idIngrediente, 101);
    expect(r.hojas[1].cantidad, closeTo(4, 1e-9));
  });

  test('elaborado → elaborado: solo quedan hojas físicas multiplicadas', () {
    // Plato (1) = 2× Salsa (2); Salsa = 3× Tomate (3) + 1× Sal (4)
    final r = expandirReceta(
      idProducto: 1,
      cantidad: 2,
      recetas: {
        1: [fila(2, 2, nombre: 'Salsa')],
        2: [
          fila(3, 3, nombre: 'Tomate'),
          fila(4, 1, nombre: 'Sal'),
        ],
      },
      idsElaborados: {1, 2},
    );
    expect(r.incompleto, isFalse);
    expect(r.hojas, hasLength(2));
    // 2 platos × 2 salsa × 3 tomate = 12
    expect(
      r.hojas.firstWhere((h) => h.idIngrediente == 3).cantidad,
      closeTo(12, 1e-9),
    );
    // 2 × 2 × 1 sal = 4
    expect(
      r.hojas.firstWhere((h) => h.idIngrediente == 4).cantidad,
      closeTo(4, 1e-9),
    );
    // La salsa elaborada no aparece como hoja
    expect(r.hojas.any((h) => h.idIngrediente == 2), isFalse);
  });

  test('servicio → elaborado: el servicio raíz también se expande', () {
    // Servicio 50 (no en idsElaborados) usa elaborado 2
    final r = expandirReceta(
      idProducto: 50,
      cantidad: 1,
      recetas: {
        50: [fila(2, 1, nombre: 'Salsa')],
        2: [fila(3, 5, nombre: 'Tomate')],
      },
      idsElaborados: {2},
    );
    expect(r.incompleto, isFalse);
    expect(r.hojas.single.idIngrediente, 3);
    expect(r.hojas.single.cantidad, closeTo(5, 1e-9));
  });

  test('elaborado anidado sin receta marca incompleto', () {
    final r = expandirReceta(
      idProducto: 1,
      cantidad: 1,
      recetas: {
        1: [fila(2, 1, nombre: 'Salsa')],
        // falta receta de 2
      },
      idsElaborados: {1, 2},
    );
    expect(r.incompleto, isTrue);
    expect(r.motivo, contains('2'));
    expect(r.hojas, isEmpty);
  });

  test('ciclo en la receta marca incompleto', () {
    final r = expandirReceta(
      idProducto: 1,
      cantidad: 1,
      recetas: {
        1: [fila(2, 1)],
        2: [fila(1, 1)],
      },
      idsElaborados: {1, 2},
    );
    expect(r.incompleto, isTrue);
    expect(r.motivo!.toLowerCase(), contains('ciclo'));
  });

  test('agrega el mismo físico si aparece por dos ramas', () {
    final r = expandirReceta(
      idProducto: 1,
      cantidad: 1,
      recetas: {
        1: [
          fila(2, 1),
          fila(3, 2, nombre: 'Harina'),
        ],
        2: [fila(3, 4, nombre: 'Harina')],
      },
      idsElaborados: {1, 2},
    );
    expect(r.incompleto, isFalse);
    expect(r.hojas.single.idIngrediente, 3);
    expect(r.hojas.single.cantidad, closeTo(6, 1e-9)); // 4 + 2
  });
}

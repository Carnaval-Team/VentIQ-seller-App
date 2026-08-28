import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/utils/stock_mixto_formatter.dart';

/// Estos tests fijan la paridad con el SQL.
///
/// Los casos esperados salen de correr las funciones reales contra produccion
/// (`fn_plural_presentacion`, `fn_formatear_stock_mixto`, `fn_fmt_cantidad`) y de
/// los resultados canonicos que documenta
/// docs/PLAN_PRESENTACIONES_INVENTARIO.md. Si un test de estos falla, el cliente
/// y el servidor dejaron de decir lo mismo.
void main() {
  group('plural — replica fn_plural_presentacion', () {
    test('cantidad 1 no pluraliza', () {
      expect(StockMixtoFormatter.plural('Caja', 1), 'Caja');
      expect(StockMixtoFormatter.plural('Bulto', 1), 'Bulto');
    });

    test('termina en vocal → +s', () {
      expect(StockMixtoFormatter.plural('Caja', 4), 'Cajas');
      expect(StockMixtoFormatter.plural('Bolsa', 2), 'Bolsas');
      expect(StockMixtoFormatter.plural('Unidad', 1), 'Unidad');
    });

    test('termina en consonante → +es', () {
      expect(StockMixtoFormatter.plural('Unidad', 4), 'Unidades');
      expect(StockMixtoFormatter.plural('Pallet', 2), 'Palletes');
    });

    test('termina en -on/-ón → -ones', () {
      expect(StockMixtoFormatter.plural('Cartón', 3), 'Cartones');
      expect(StockMixtoFormatter.plural('Blister', 2), 'Blisteres');
    });

    test('ya termina en s: no se toca', () {
      expect(StockMixtoFormatter.plural('Bolsas', 5), 'Bolsas');
    });

    test('nombre vacio o nulo → cadena vacia', () {
      expect(StockMixtoFormatter.plural(null, 3), '');
      expect(StockMixtoFormatter.plural('   ', 3), '');
    });

    test('cantidad negativa usa el valor absoluto (ABS en el SQL)', () {
      expect(StockMixtoFormatter.plural('Caja', -1), 'Caja');
      expect(StockMixtoFormatter.plural('Caja', -4), 'Cajas');
    });
  });

  group('cantidad — replica fn_fmt_cantidad', () {
    test('enteros sin punto colgando (el bug original: "4. Cajas")', () {
      expect(StockMixtoFormatter.cantidad(4), '4');
      expect(StockMixtoFormatter.cantidad(4.0), '4');
      expect(StockMixtoFormatter.cantidad(100), '100');
    });

    test('decimales sin ceros de relleno', () {
      expect(StockMixtoFormatter.cantidad(1.5), '1.5');
      expect(StockMixtoFormatter.cantidad(0.25), '0.25');
      expect(StockMixtoFormatter.cantidad(2.125), '2.125');
    });

    test('cero', () {
      expect(StockMixtoFormatter.cantidad(0), '0');
    });

    // Los cuatro casos de abajo se contrastaron uno por uno con
    // fn_fmt_cantidad() vivo en produccion.
    test('negativos conservan el signo', () {
      expect(StockMixtoFormatter.cantidad(-4), '-4');
      expect(StockMixtoFormatter.cantidad(-1.5), '-1.5');
    });

    test('null → "0", igual que el SQL', () {
      expect(StockMixtoFormatter.cantidad(null), '0');
    });

    test('redondeo a 3 decimales', () {
      expect(StockMixtoFormatter.cantidad(0.0005), '0.001');
      expect(StockMixtoFormatter.cantidad(1.9999), '2');
      expect(StockMixtoFormatter.cantidad(2.0005), '2.001');
    });
  });

  group('mixto — replica fn_formatear_stock_mixto', () {
    test('el caso canonico del plan: 4 cajas + 4 unidades', () {
      final saldos = [
        {'nombre': 'Caja', 'cantidad': 4},
        {'nombre': 'Unidad', 'cantidad': 4},
      ];
      expect(StockMixtoFormatter.mixto(saldos), '4 Cajas + 4 Unidades');
    });

    test('omite las presentaciones con saldo 0', () {
      final saldos = [
        {'nombre': 'Caja', 'cantidad': 0},
        {'nombre': 'Unidad', 'cantidad': 11},
      ];
      expect(StockMixtoFormatter.mixto(saldos), '11 Unidades');
    });

    test('todo en cero → texto de vacio', () {
      final saldos = [
        {'nombre': 'Caja', 'cantidad': 0},
      ];
      expect(StockMixtoFormatter.mixto(saldos), 'Sin stock');
      expect(StockMixtoFormatter.mixto(saldos, vacio: '—'), '—');
    });

    test('lista vacia o nula → texto de vacio', () {
      expect(StockMixtoFormatter.mixto([]), 'Sin stock');
      expect(StockMixtoFormatter.mixto(null), 'Sin stock');
    });

    test('abreviar usa sku_codigo', () {
      final saldos = [
        {'nombre': 'Bolsa', 'cantidad': 100, 'sku_codigo': 'BOL'},
      ];
      // Verificado contra produccion con el producto 217: "100 BOL".
      expect(StockMixtoFormatter.mixto(saldos, abreviar: true), '100 BOL');
      expect(StockMixtoFormatter.mixto(saldos), '100 Bolsas');
    });

    test('abreviar sin sku cae al nombre pluralizado', () {
      final saldos = [
        {'nombre': 'Caja', 'cantidad': 3},
      ];
      expect(StockMixtoFormatter.mixto(saldos, abreviar: true), '3 Cajas');
    });

    test('respeta el orden del array, no lo reordena', () {
      final saldos = [
        {'nombre': 'Unidad', 'cantidad': 4},
        {'nombre': 'Caja', 'cantidad': 4},
      ];
      expect(StockMixtoFormatter.mixto(saldos), '4 Unidades + 4 Cajas');
    });

    test('el resultado de vender 1 unidad de 4 cajas + 12', () {
      // Del plan: 4 Cajas + 4 u = 52; vender 1 u → 3 Cajas + 11 u = 47.
      final saldos = [
        {'nombre': 'Caja', 'cantidad': 3},
        {'nombre': 'Unidad', 'cantidad': 11},
      ];
      expect(StockMixtoFormatter.mixto(saldos), '3 Cajas + 11 Unidades');
    });

    // Los cinco casos de abajo se contrastaron uno por uno con
    // fn_formatear_stock_mixto() vivo en produccion.
    test('saldo negativo se muestra con signo, no se filtra', () {
      final saldos = [
        {'nombre': 'Caja', 'cantidad': -2},
        {'nombre': 'Unidad', 'cantidad': 3},
      ];
      expect(StockMixtoFormatter.mixto(saldos), '-2 Cajas + 3 Unidades');
    });

    test('sin nombre cae a "Presentacion" y la pluraliza', () {
      final saldos = [
        {'cantidad': 5},
      ];
      expect(StockMixtoFormatter.mixto(saldos), '5 Presentaciones');
    });

    test('sin cantidad cuenta como 0 y se omite', () {
      final saldos = [
        {'nombre': 'Caja'},
      ];
      expect(StockMixtoFormatter.mixto(saldos), 'Sin stock');
    });

    test('cantidad 1.0 no pluraliza', () {
      final saldos = [
        {'nombre': 'Caja', 'cantidad': 1.0},
      ];
      expect(StockMixtoFormatter.mixto(saldos), '1 Caja');
    });

    test('sku_codigo vacio con abreviar cae al nombre', () {
      final saldos = [
        {'nombre': 'Bolsa', 'cantidad': 3, 'sku_codigo': ''},
      ];
      expect(StockMixtoFormatter.mixto(saldos, abreviar: true), '3 Bolsas');
    });
  });

  group('linea — una fila de operacion', () {
    test('con presentacion', () {
      expect(StockMixtoFormatter.linea(4, 'Caja'), '4 Cajas');
      expect(StockMixtoFormatter.linea(1, 'Bulto'), '1 Bulto');
    });

    test('sin presentacion no inventa "unidades"', () {
      // Las operaciones viejas tienen id_presentacion nulo: el ledger no sabe en
      // que estaba expresada esa fila, asi que no se le pone una etiqueta.
      expect(StockMixtoFormatter.linea(7, null), '7');
      expect(StockMixtoFormatter.linea(7, '  '), '7');
    });

    test('decimales', () {
      expect(StockMixtoFormatter.linea(1.5, 'Kilogramo'), '1.5 Kilogramos');
    });
  });

  group('mixtoConEquivalente', () {
    test('con dos presentaciones muestra mixto + equivalente', () {
      final saldos = [
        {'nombre': 'Caja', 'cantidad': 4},
        {'nombre': 'Unidad', 'cantidad': 4},
      ];
      expect(
        StockMixtoFormatter.mixtoConEquivalente(saldos, 52, 'Unidad'),
        '4 Cajas + 4 Unidades  ·  = 52 Unidades',
      );
    });

    test('con una sola presentacion omite el equivalente redundante', () {
      final saldos = [
        {'nombre': 'Bolsa', 'cantidad': 100},
      ];
      expect(
        StockMixtoFormatter.mixtoConEquivalente(saldos, 100, 'Bolsa'),
        '100 Bolsas',
      );
    });

    test('sin saldo devuelve el texto de vacio', () {
      expect(
        StockMixtoFormatter.mixtoConEquivalente([], 0, 'Unidad'),
        'Sin stock',
      );
    });
  });
}

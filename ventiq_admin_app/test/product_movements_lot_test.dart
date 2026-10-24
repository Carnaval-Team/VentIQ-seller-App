import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/services/product_movements_service.dart';

void main() {
  final movements = <Map<String, dynamic>>[
    {'id': 1, 'id_lote': 10, 'cantidad_final': 0},
    {'id': 2, 'id_lote': 20, 'cantidad_final': 8},
    {'id': 3, 'id_lote': '10', 'cantidad_final': 5},
    {'id': 4, 'id_lote': null},
    {'id': 5, 'id_lote': 0},
  ];

  test('Todos los lotes conserva registros y orden sin modificar el origen', () {
    final result = ProductMovementsService.filterMovementsByLot(movements, null);
    expect(result, movements);
    expect(identical(result, movements), isFalse);
    result.clear();
    expect(movements, hasLength(5));
  });

  test('filtra por lote incluyendo saldos cero y IDs serializados', () {
    final result = ProductMovementsService.filterMovementsByLot(movements, 10);
    expect(result.map((m) => m['id']), [1, 3]);
    expect(result.map((m) => m['cantidad_final']), [0, 5]);
  });

  test('Sin lote incluye nulos y el identificador cero', () {
    final result = ProductMovementsService.filterMovementsByLot(movements, 0);
    expect(result.map((m) => m['id']), [4, 5]);
  });

  test('un lote sin movimientos no muestra registros de otros lotes', () {
    expect(
      ProductMovementsService.filterMovementsByLot(movements, 99),
      isEmpty,
    );
  });
}

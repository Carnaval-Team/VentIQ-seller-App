import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Tiempo real: KPIs y tabla ocultan ganancia sin permiso', () {
    final src = File('lib/screens/sales_screen.dart').readAsStringSync();
    expect(src, contains('PermissionsService().canViewGanancias()'));
    expect(src, contains("'Ganancia'"));
    expect(src, contains('if (_canViewGanancias)'));
    // PDF de órdenes: columnas de costo/ganancia omitidas (no celdas vacías).
    expect(src, contains("if (verGanancia) _pdfHeaderCell('Ganancia')"));
    expect(
      src,
      isNot(contains("_pdfHeaderCell(_canViewGanancias ? 'Ganancia' : '')")),
    );
  });

  test('canViewGanancias queda solo para dueño', () {
    final src = File('lib/services/permissions_service.dart').readAsStringSync();
    expect(src, contains('Future<bool> canViewGanancias()'));
    expect(src, contains('return role == UserRole.dueno;'));
  });

  test('precios_productos muestra el estudio de % a todos los roles', () {
    final src =
        File('lib/screens/precios_productos_screen.dart').readAsStringSync();
    expect(src, contains('_canViewGanancias = true'));
    expect(src, isNot(contains('canViewGanancias()')));
    expect(src, contains('porcGanancia!.toStringAsFixed(1)'));
  });
}

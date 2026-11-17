import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/services/sales_service.dart';

Map<String, dynamic> filaReporte() => {
  'id_tienda': 4,
  'id_producto': 8,
  'nombre_producto': 'Refresco',
  'id_proveedor': 1,
  'nombre_proveedor': 'Prov',
  'precio_venta_cup': 8000,
  'precio_costo': 4,
  'valor_usd': 850,
  'precio_costo_cup': 3400,
  'total_vendido': 5,
  'ingresos_totales': 40000,
  'costo_total_vendido': 17000,
  'ganancia_unitaria': 4600,
  'ganancia_total': 23000,
};

void main() {
  group('ProductSalesReport.usaPreciosActuales (R03)', () {
    test('la rama histórica queda marcada como tal por defecto', () {
      final r = ProductSalesReport.fromJson(filaReporte());
      expect(r.usaPreciosActuales, isFalse);
    });

    test('la rama de análisis con precios vigentes declara su magnitud', () {
      final r = ProductSalesReport.fromJson(
        filaReporte(),
        usaPreciosActuales: true,
      );
      expect(r.usaPreciosActuales, isTrue);
      // La magnitud declarada no altera el parseo del resto del contrato.
      expect(r.ingresosTotales, 40000);
      expect(r.equivUnidadesBase, 5);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ventiq_superadmin/screens/pago_inventtia_resumen.dart';
import 'package:ventiq_superadmin/models/supplier_payment_model.dart';
import 'package:ventiq_superadmin/services/inventtia_reparto_service.dart';

void main() {
  testWidgets('separa resumen, licencias y Carnaval sin repetir la carga', (
    tester,
  ) async {
    await initializeDateFormatting('es_ES');
    var cargas = 0;
    final data = RepartoInventtia(
      cobros: [],
      personas: [],
      pagoProveedoresCup: 800,
      comisionCarnavalCup: 8,
      socios: 1,
      proveedores: [
        SupplierPaymentSummary.fromJson({
          'proveedor_id': 1,
          'proveedor_name': 'Tienda Carnaval',
          'total_cup': 1000,
          'excluido_cup': 200,
          'total_orders': 2,
        }),
      ],
      usoRenovaciones: true,
    );
    Future<void> mostrar(int seccion, {int revision = 0}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PagoInventtiaResumen(
              fechaInicio: DateTime(2026, 10),
              fechaFin: DateTime(2026, 10, 31),
              licenciaMes: DateTime(2026, 11),
              seccion: seccion,
              revision: revision,
              cargar: () async {
                cargas++;
                return data;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await mostrar(0);
    expect(find.text('Cobrado Licencia'), findsOneWidget);
    expect(find.text('1% de Carnaval Total'), findsOneWidget);
    expect(find.text('Total a pagar'), findsOneWidget);
    expect(find.text('A quién se le paga'), findsOneWidget);
    expect(find.text('Cliente'), findsNothing);
    await mostrar(1);
    expect(find.text('Cliente'), findsOneWidget);
    expect(find.text('A quién se le paga'), findsNothing);
    await mostrar(2);
    expect(find.text('Carnaval App'), findsOneWidget);
    expect(find.text('Total vendido (CUP)'), findsOneWidget);
    expect(find.text('1% (CUP)'), findsOneWidget);
    expect(find.text('800,00'), findsOneWidget);
    expect(find.text('8,00'), findsOneWidget);
    expect(
      find.textContaining('Total vendido 800,00 CUP · 1%: 8,00 CUP'),
      findsOneWidget,
    );
    expect(find.text('Cliente'), findsNothing);
    expect(cargas, 1);
    await mostrar(2, revision: 1);
    expect(cargas, 2);
  });
}

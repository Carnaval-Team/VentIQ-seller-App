import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/sales.dart';
import 'package:ventiq_admin_app/widgets/egresos_turno_dialog.dart';

CashDelivery _egreso(int id, double monto, String moneda, String motivo) =>
    CashDelivery(
      id: id,
      montoEntrega: monto,
      motivoEntrega: motivo,
      nombreRecibe: 'Persona que recibe con un nombre bastante largo',
      nombreAutoriza: 'Persona que autoriza con un nombre igual de largo',
      fechaEntrega: DateTime(2026, 11, 20, 14, 30),
      estado: 1,
      idTurno: 21,
      creadoPor: 'u',
      moneda: moneda,
    );

Future<void> _abrir(WidgetTester tester, List<CashDelivery> egresos) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showEgresosTurnoDialog(
            context: context,
            titulo: 'Egresos de Vendedor con un nombre completo muy largo',
            egresos: egresos,
            monedaBase: 'CUP',
            formatMonto: (m, c) => '${m.toStringAsFixed(2)} $c',
            formatFecha: (f) => '20/11/2026 14:30',
          ),
          child: const Text('abrir'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  for (final tamano in const [Size(320, 480), Size(360, 640), Size(800, 1200)]) {
    testWidgets('sin desbordes en ${tamano.width.toInt()}x${tamano.height.toInt()}',
        (tester) async {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _abrir(tester, [
        for (var i = 0; i < 8; i++)
          _egreso(i, 1000.0 + i, i.isEven ? 'CUP' : 'USD',
              'Motivo del egreso extenso que ocupa varias líneas en pantallas pequeñas $i'),
      ]);

      expect(tester.takeException(), isNull);
      expect(find.text('Total CUP'), findsOneWidget);
      expect(find.text('Total USD'), findsOneWidget);
      expect(find.text('Cerrar'), findsWidgets);
    });
  }

  testWidgets('sin egresos muestra el estado vacío', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _abrir(tester, const []);

    expect(tester.takeException(), isNull);
    expect(find.text('No hay egresos registrados en este turno'),
        findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/widgets/fdi_recepcion_fuentes.dart';
import 'package:ventiq_admin_app/models/fondo_inversion.dart';

FdiSaldo saldo(int id, String moneda, double monto) => FdiSaldo(
  idCuenta: id,
  cuenta: 'Cuenta $id',
  concepto: 'Fondo',
  idMedioPago: 1,
  medioPago: 'Efectivo',
  moneda: moneda,
  saldo: monto,
);

void main() {
  test('combina cuentas y monedas sin sobregirar ninguna fuente', () {
    final fuentes = [
      FdiFuenteRecepcion(saldo: saldo(1, 'USD', 30), monto: 30),
      FdiFuenteRecepcion(
        saldo: saldo(2, 'CUP', 8000),
        monto: 8000,
        tasaARef: 0.0025,
      ),
    ];
    expect(FdiFuenteRecepcion.validar(fuentes, 50, 'USD'), isNull);
    expect(fuentes.last.toJson()['monto'], '8000.00');
    expect(fuentes.last.equivalente, 20);
  });
  test('rechaza faltante, sobrante, tasa inválida y saldo insuficiente', () {
    final usd = saldo(1, 'USD', 30);
    expect(
      FdiFuenteRecepcion.validar(
        [FdiFuenteRecepcion(saldo: usd, monto: 30)],
        50,
        'USD',
      ),
      isNotNull,
    );
    expect(
      FdiFuenteRecepcion.validar(
        [FdiFuenteRecepcion(saldo: usd, monto: 30)],
        20,
        'USD',
      ),
      isNotNull,
    );
    expect(
      FdiFuenteRecepcion.validar(
        [FdiFuenteRecepcion(saldo: usd, monto: 31)],
        31,
        'USD',
      ),
      isNotNull,
    );
    expect(
      FdiFuenteRecepcion.validar(
        [
          FdiFuenteRecepcion(
            saldo: saldo(2, 'CUP', 100),
            monto: 100,
            tasaARef: 0,
          ),
        ],
        10,
        'USD',
      ),
      isNotNull,
    );
    expect(
      FdiFuenteRecepcion.validar(
        [FdiFuenteRecepcion(saldo: usd, monto: double.nan)],
        10,
        'USD',
      ),
      isNotNull,
    );
  });
  testWidgets(
    'reparte el faltante entre cuentas USD y permite usar otra moneda con tasa',
    (tester) async {
      List<FdiFuenteRecepcion> fuentes = [];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FdiRecepcionFuentes(
                saldos: [
                  saldo(1, 'USD', 30),
                  saldo(2, 'USD', 40),
                  saldo(3, 'CUP', 8000),
                ],
                total: 50,
                moneda: 'USD',
                onChanged: (value) => fuentes = value,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(CheckboxListTile).at(0));
      await tester.pump();
      await tester.tap(find.byType(CheckboxListTile).at(1));
      await tester.pump();
      expect(fuentes.map((f) => f.monto), [30, 20]);
      expect(FdiFuenteRecepcion.validar(fuentes, 50, 'USD'), isNull);
      await tester.tap(find.byType(CheckboxListTile).at(1));
      await tester.pump();
      await tester.ensureVisible(find.byType(CheckboxListTile).at(2));
      await tester.tap(find.byType(CheckboxListTile).at(2));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('fdi-monto-2')), '8000');
      await tester.enterText(
        find.byKey(const ValueKey('fdi-tasa-2')),
        '0,0025',
      );
      await tester.pump();
      expect(FdiFuenteRecepcion.validar(fuentes, 50, 'USD'), isNull);
      expect(fuentes.last.equivalente, 20);
      expect(tester.takeException(), isNull);
    },
  );

  test('no permite repetir la misma cuenta, medio y moneda', () {
    final fuente = FdiFuenteRecepcion(saldo: saldo(1, 'USD', 30), monto: 20);
    expect(FdiFuenteRecepcion.validar([fuente, fuente], 40, 'USD'), isNotNull);
  });
}

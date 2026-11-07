import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/fondo_inversion.dart';

FdiVentaMedioMoneda medio(int id, String moneda, double vendido) =>
    FdiVentaMedioMoneda(
      idMedioPago: id,
      medioPago: 'Medio $id',
      moneda: moneda,
      montoVendido: vendido,
      montoVendidoCup: vendido,
    );

FdiVentasPeriodo periodo(List<FdiVentaMedioMoneda> medios, double ganancia) =>
    FdiVentasPeriodo(
      ordenesElegibles: 1,
      ordenesExcluidas: 0,
      ventaTotalCup: 10000,
      costoTotalCup: 8000,
      gananciaCup: ganancia,
      medios: medios,
    );

void main() {
  test('varios medios y monedas no retiran ganancia por defecto', () {
    final medios = [
      medio(1, 'CUP', 5000),
      medio(2, 'CUP', 3000),
      medio(1, 'USD', 100),
    ];
    final seleccion = FdiSeleccionGanancia()
      ..inicializar(periodo(medios, 2000));
    expect(seleccion.origenes, isEmpty);
    expect(seleccion.detalle, isEmpty);
    for (final m in medios) {
      expect(m.montoGananciaRetirada, 0);
      expect(m.montoInversion, m.montoVendido);
    }
  });

  test('retira solo del medio y moneda elegidos, sin cambiar el resto', () {
    final efectivo = medio(1, 'CUP', 5000);
    final transferencia = medio(2, 'CUP', 3000);
    final usd = medio(1, 'USD', 100);
    final seleccion = FdiSeleccionGanancia()
      ..inicializar(periodo([efectivo, transferencia, usd], 2000));
    seleccion.seleccionar(transferencia, true, pendienteCup: 2000);
    expect(seleccion.detalle, [
      {'id_medio_pago': 2, 'moneda': 'CUP', 'monto_ganancia_retirada': 2000.0},
    ]);
    expect(transferencia.montoInversion, 1000);
    expect(efectivo.montoInversion, 5000);
    expect(usd.montoInversion, 100);
    seleccion.seleccionar(transferencia, false, pendienteCup: 0);
    expect(seleccion.detalle, isEmpty);
    expect(transferencia.montoInversion, 3000);
  });

  test(
    'permite completar la ganancia con varios orígenes sin exceder lo vendido',
    () {
      final a = medio(1, 'CUP', 500);
      final b = medio(2, 'CUP', 3000);
      final seleccion = FdiSeleccionGanancia()
        ..inicializar(periodo([a, b], 2000));
      seleccion.seleccionar(a, true, pendienteCup: 2000);
      seleccion.seleccionar(b, true, pendienteCup: 1500);
      expect(a.montoGananciaRetirada, 500);
      expect(b.montoGananciaRetirada, 1500);
      expect(seleccion.detalle.length, 2);
    },
  );

  test(
    'otra moneda mantiene su importe y medio; la tasa solo compara en CUP',
    () {
      final usd = medio(2, 'USD', 100);
      final seleccion = FdiSeleccionGanancia()
        ..inicializar(periodo([medio(1, 'CUP', 5000), usd], 850));
      seleccion.seleccionar(usd, true, pendienteCup: 850, tasaCup: 850);
      expect(usd.montoGananciaRetirada, 1);
      expect(seleccion.detalle.single['moneda'], 'USD');
      expect(seleccion.detalle.single['id_medio_pago'], 2);
      expect(usd.montoInversion, 99);
    },
  );

  test(
    'único origen CUP precarga la ganancia y recargar elimina selecciones anteriores',
    () {
      final cup = medio(1, 'CUP', 5000);
      final seleccion = FdiSeleccionGanancia()
        ..inicializar(periodo([cup], 2000));
      expect(cup.montoGananciaRetirada, 2000);
      seleccion.inicializar(periodo([cup, medio(2, 'USD', 100)], 2000));
      expect(seleccion.origenes, isEmpty);
      expect(cup.montoGananciaRetirada, 0);
    },
  );

  test(
    'sin tasa no inventa una retirada en otra moneda; sin ganancia no retira',
    () {
      final usd = medio(1, 'USD', 100);
      final seleccion = FdiSeleccionGanancia()
        ..inicializar(periodo([usd], 850));
      expect(usd.montoGananciaRetirada, 0);
      seleccion.inicializar(periodo([medio(1, 'CUP', 5000)], -100));
      expect(seleccion.detalle, isEmpty);
    },
  );
}

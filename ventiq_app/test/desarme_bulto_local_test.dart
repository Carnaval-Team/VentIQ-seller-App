import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/utils/desarme_bulto_local.dart';
import 'package:ventiq_app/utils/presentacion_cadena_local.dart';

/// Paridad del resolutor de desarme local con la SIMULACION 1 · ABRIR de
/// `fn_preview_rebalanceo`.
///
/// Casos del negocio acordados: pedir 5 Unidades cuando hay 4 y una Bolsa de 6
/// rompe la bolsa; pedir exacto a un bulto usa el bulto; si no alcanza ni
/// desarmando, es imposible.
void main() {
  /// Bulto de 6 / base Unidad (caso cerveza del vendedor).
  final cadena6 = PresentacionCadenaLocal.resolverDesdeCrudas([
    {
      'id': 100,
      'id_presentacion': 3,
      'cantidad': 6.0,
      'es_base': false,
      'presentacion': {'id': 3, 'denominacion': 'Caja'},
    },
    {
      'id': 101,
      'id_presentacion': 1,
      'cantidad': 1.0,
      'es_base': true,
      'presentacion': {'id': 1, 'denominacion': 'Unidad'},
    },
  ]);

  test('saldo propio alcanza: sin plan', () {
    final r = DesarmeBultoLocal.evaluar(
      cadena: cadena6,
      stocks: const {100: 2, 101: 10},
      idPresentacionPedida: 101,
      cantidadPedida: 5,
    );
    expect(r.alcanza, isTrue);
    expect(r.plan, isNull);
  });

  test('hay 4 unidades y una Caja de 6: desarmar 1 Caja, quedan 5', () {
    final r = DesarmeBultoLocal.evaluar(
      cadena: cadena6,
      stocks: const {100: 1, 101: 4},
      idPresentacionPedida: 101,
      cantidadPedida: 5,
    );
    expect(r.requiereDesarme, isTrue);
    final plan = r.plan!;
    expect(plan.origen.idPresentacion, 100); // la Caja
    expect(plan.cantidadOrigen, 1);
    expect(plan.cantidadDestino, 6);
    expect(plan.saldoPropio, 4);
    expect(plan.saldoDespuesConversion, 10);
    expect(plan.mensaje, contains('Se desarmará 1 Caja'));
    expect(plan.mensaje, contains('5 Unidades'));
  });

  test('el bulto cubre justo: se rompe y el sobrante queda disponible', () {
    // 0 unidades, 1 Caja de 6, pedir 6: se rompe la caja y quedan 0.
    final r = DesarmeBultoLocal.evaluar(
      cadena: cadena6,
      stocks: const {100: 1, 101: 0},
      idPresentacionPedida: 101,
      cantidadPedida: 6,
    );
    expect(r.requiereDesarme, isTrue);
    expect(r.plan!.cantidadOrigen, 1);
    expect(r.plan!.cantidadDestino, 6);
  });

  test('pedir 6 con 4 unidades: la Caja de 6 cubre, sobran 4', () {
    final r = DesarmeBultoLocal.evaluar(
      cadena: cadena6,
      stocks: const {100: 1, 101: 4},
      idPresentacionPedida: 101,
      cantidadPedida: 6,
    );
    expect(r.requiereDesarme, isTrue);
    expect(r.plan!.cantidadOrigen, 1);
    expect(r.plan!.cantidadDestino, 6);
    // 4 + 6 = 10, se venden 6, quedan 4.
    expect(r.plan!.saldoDespuesConversion, 10);
  });

  test('sin stock en ninguna parte: imposible con maximo 0', () {
    final r = DesarmeBultoLocal.evaluar(
      cadena: cadena6,
      stocks: const {100: 0, 101: 4},
      idPresentacionPedida: 101,
      cantidadPedida: 5,
    );
    expect(r.esImposible, isTrue);
    expect(r.maximoServible, 4);
  });

  test('sin cadena conocida: no bloquea la venta', () {
    final r = DesarmeBultoLocal.evaluar(
      cadena: const [],
      stocks: const {},
      idPresentacionPedida: 101,
      cantidadPedida: 999,
    );
    expect(r.alcanza, isTrue);
  });

  test('presentacion pedida fuera de la cadena: no bloquea', () {
    final r = DesarmeBultoLocal.evaluar(
      cadena: cadena6,
      stocks: const {100: 1},
      idPresentacionPedida: 999,
      cantidadPedida: 5,
    );
    expect(r.alcanza, isTrue);
  });

  test('maximoServible: base en 0 con 1 Caja de 6 habilita vender 6', () {
    final m = DesarmeBultoLocal.maximoServible(
      cadena: cadena6,
      stocks: const {100: 1, 101: 0},
      idPresentacionPedida: 101,
      saldoPropio: 0,
    );
    expect(m, 6);
  });

  test('maximoServible: sin cadena devuelve el saldo propio', () {
    final m = DesarmeBultoLocal.maximoServible(
      cadena: const [],
      stocks: const {},
      idPresentacionPedida: 101,
      saldoPropio: 3,
    );
    expect(m, 3);
  });

  test('cadena de 3 niveles: desarma el empaque mas pequeño que cubre', () {
    // Bulto 24 / Caja 6 / Unidad 1.
    final cadena = PresentacionCadenaLocal.resolverDesdeCrudas([
      {
        'id': 200,
        'id_presentacion': 9,
        'cantidad': 24.0,
        'es_base': false,
        'presentacion': {'id': 9, 'denominacion': 'Bulto'},
      },
      {
        'id': 201,
        'id_presentacion': 3,
        'cantidad': 6.0,
        'es_base': false,
        'presentacion': {'id': 3, 'denominacion': 'Caja'},
      },
      {
        'id': 202,
        'id_presentacion': 1,
        'cantidad': 1.0,
        'es_base': true,
        'presentacion': {'id': 1, 'denominacion': 'Unidad'},
      },
    ]);

    // Hay 2 Unidades y 2 Cajas. Pedir 5: falta 1, la Caja de 6 cubre.
    // El Bulto (24) NO se debe tocar.
    final r = DesarmeBultoLocal.evaluar(
      cadena: cadena,
      stocks: const {200: 5, 201: 2, 202: 2},
      idPresentacionPedida: 202,
      cantidadPedida: 5,
    );
    expect(r.requiereDesarme, isTrue);
    expect(r.plan!.origen.idPresentacion, 201); // Caja, no Bulto
    expect(r.plan!.cantidadOrigen, 1);
    expect(r.plan!.cantidadDestino, 6);
  });
}

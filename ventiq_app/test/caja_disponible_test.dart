import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/money/caja_disponible.dart';

CajaDisponible _caja({
  Map<String, double> inicial = const {},
  List<Map<String, dynamic>> pagos = const [],
  List<Map<String, dynamic>> egresos = const [],
}) => CajaDisponible.desdeMapas(
  inicialPorMoneda: inicial,
  pagos: pagos,
  egresos: egresos,
);

void main() {
  group('efectivo', () {
    test('inicial + cobros en efectivo - egresos, por moneda', () {
      final caja = _caja(
        inicial: {'CUP': 1000, 'USD': 20},
        pagos: [
          {'moneda': 'CUP', 'monto': 500, 'id_medio_pago': 1, 'es_efectivo': true},
          {'moneda': 'USD', 'monto': 10, 'id_medio_pago': 1, 'es_efectivo': true},
        ],
        egresos: [
          {'moneda': 'CUP', 'monto_entrega': 300, 'es_digital': false},
          {'moneda': 'USD', 'monto_entrega': 5, 'es_digital': null},
        ],
      );
      expect(caja.disponible(moneda: 'CUP', idMedio: 1, efectivo: true), 1200);
      expect(caja.disponible(moneda: 'USD', idMedio: 1, efectivo: true), 25);
    });

    test('el cajón es uno: el medio en efectivo elegido no importa', () {
      final caja = _caja(
        pagos: [
          {'moneda': 'CUP', 'monto': 100, 'id_medio_pago': 1, 'es_efectivo': true},
        ],
        egresos: [
          {'moneda': 'CUP', 'monto_entrega': 60, 'id_medio_pago': 7, 'es_digital': false},
        ],
      );
      expect(caja.disponible(moneda: 'CUP', idMedio: 1, efectivo: true), 40);
      expect(caja.disponible(moneda: 'CUP', idMedio: 7, efectivo: true), 40);
    });

    test('un sobrante en una moneda no cubre otra', () {
      final caja = _caja(inicial: {'USD': 500, 'CUP': 10});
      expect(
        caja.rechazo(monto: 50, moneda: 'CUP', idMedio: 1, efectivo: true),
        contains('disponible 10.00 CUP en efectivo'),
      );
    });

    test('moneda sin dinero disponible vale 0', () {
      final caja = _caja(inicial: {'CUP': 100});
      expect(caja.disponible(moneda: 'EUR', idMedio: 1, efectivo: true), 0);
    });

    test('permite sacar exactamente lo disponible, no un centavo más', () {
      final caja = _caja(inicial: {'CUP': 100});
      expect(
        caja.rechazo(monto: 100, moneda: 'CUP', idMedio: 1, efectivo: true),
        isNull,
      );
      expect(
        caja.rechazo(monto: 100.01, moneda: 'CUP', idMedio: 1, efectivo: true),
        isNotNull,
      );
    });

    test('los pagos pendientes no son dinero en caja', () {
      final caja = _caja(
        pagos: [
          {'moneda': 'CUP', 'monto': 900, 'id_medio_pago': 998, 'es_efectivo': false},
        ],
      );
      expect(caja.disponible(moneda: 'CUP', idMedio: 1, efectivo: true), 0);
    });
  });

  group('digital', () {
    test('solo cuenta lo cobrado con ese medio y moneda; sin efectivo inicial', () {
      final caja = _caja(
        inicial: {'CUP': 5000},
        pagos: [
          {'moneda': 'CUP', 'monto': 200, 'id_medio_pago': 2, 'es_efectivo': false},
          {'moneda': 'CUP', 'monto': 300, 'id_medio_pago': 3, 'es_efectivo': false},
        ],
        egresos: [
          {'moneda': 'CUP', 'monto_entrega': 50, 'id_medio_pago': 2, 'es_digital': true},
        ],
      );
      expect(caja.disponible(moneda: 'CUP', idMedio: 2, efectivo: false), 150);
      expect(caja.disponible(moneda: 'CUP', idMedio: 3, efectivo: false), 300);
      expect(caja.disponible(moneda: 'USD', idMedio: 2, efectivo: false), 0);
      expect(
        caja.rechazo(
          monto: 151,
          moneda: 'CUP',
          idMedio: 2,
          efectivo: false,
          nombreMedio: 'Transferencia',
        ),
        contains('en Transferencia'),
      );
    });
  });

  group('inicialDeMapa', () {
    test('prioriza efectivo_inicial_por_moneda', () {
      expect(
        CajaDisponible.inicialDeMapa({
          'efectivo_inicial_por_moneda': {'cup': 10, 'USD': 2},
          'efectivo_inicial': 999,
        }),
        {'CUP': 10.0, 'USD': 2.0},
      );
    });

    test('si no, base + efectivo_inicial_usd', () {
      expect(
        CajaDisponible.inicialDeMapa({
          'efectivo_inicial': 50,
          'efectivo_inicial_usd': 3,
        }),
        {'CUP': 50.0, 'USD': 3.0},
      );
      expect(CajaDisponible.inicialDeMapa(null), isEmpty);
    });
  });

  test('egreso_screen valida contra la caja y recalcula al registrar', () {
    final src = File('lib/screens/egreso_screen.dart').readAsStringSync();
    expect(src, contains('CajaDisponibleService.cargar'));
    expect(src, contains('_buildDisponibleCard()'));
    // Validador del campo y revalidación justo antes de registrar.
    expect(src, contains('return _rechazoPorSaldo(_caja, monto);'));
    expect(src, contains('final caja = await _cargarCaja();'));
    expect(src, contains('_rechazoPorSaldo(caja, monto)'));
  });

  test('el formulario pide moneda, luego medio de pago y al final el monto', () {
    final src = File('lib/screens/egreso_screen.dart').readAsStringSync();
    final build = src.indexOf('_buildOrigenCard(),');
    expect(build, greaterThan(0));
    expect(src.indexOf('_buildDisponibleCard(),'), greaterThan(build));
    expect(src.indexOf('_buildMontoCard(),'),
        greaterThan(src.indexOf('_buildDisponibleCard(),')));
    // Dentro del origen, la moneda va antes que el medio de pago.
    expect(src.indexOf("'1. Moneda'"), lessThan(src.indexOf("'2. Medio de pago'")));
    // El monto se valida mientras se escribe y al cambiar moneda o medio.
    expect(src, contains('AutovalidateMode.onUserInteraction'));
    expect(src, contains('_revalidarMonto();'));
    // Offline ofrece los mismos medios que online (solo efectivo).
    expect(src, contains('todos.where((m) => m.esEfectivo)'));
  });
}

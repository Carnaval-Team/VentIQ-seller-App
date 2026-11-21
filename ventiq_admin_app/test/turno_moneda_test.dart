import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/caja_turno.dart';

Map<String, dynamic> _fila(
  String moneda, {
  int ops = 3,
  Object ventas = 0,
  Object efectivo = 0,
  Object egresos = 0,
  Object esperado = 0,
  Object? real,
  Object? diferencia,
}) => {
  'id_turno': 21,
  'moneda': moneda,
  'operaciones': ops,
  'ventas_nativo': ventas,
  'efectivo_nativo': efectivo,
  'digital_nativo': 0,
  'egresos_nativo': egresos,
  'inicial_nativo': 0,
  'esperado_nativo': esperado,
  'real_nativo': real,
  'diferencia_nativo': diferencia,
};

void main() {
  test('el cuadre por moneda conserva cada importe en su moneda', () {
    final cup = TurnoMoneda.fromJson(
      _fila(
        'cup',
        ventas: '15200.00',
        efectivo: '15200.00',
        egresos: 750,
        esperado: '14450.00',
        real: 14450,
        diferencia: 0,
      ),
    );
    final usd = TurnoMoneda.fromJson(
      _fila('USD', ventas: 23.1, efectivo: 23.1, esperado: 23.1, real: 23.1),
    );

    expect(cup.moneda, 'CUP');
    expect(cup.esperado, 14450);
    expect(cup.ticketPromedio, closeTo(5066.67, 0.01));
    expect(usd.diferencia, isNull);

    final ventas = TurnoMoneda.sumarPorMoneda([usd, cup], (m) => m.ventas);
    expect(ventas.keys.toList(), ['CUP', 'USD']);
    expect(ventas['CUP'], 15200);
    expect(ventas['USD'], 23.1);
  });

  test('sin operaciones no hay ticket promedio', () {
    final m = TurnoMoneda.fromJson(_fila('USD', ops: 0, egresos: 5));
    expect(m.ticketPromedio, isNull);
  });

  test('el script SQL filtra completadas y no mezcla monedas', () {
    final sql = File(
      '../sql_updates/reportes_turno_completadas_y_por_moneda.sql',
    ).readAsStringSync();
    expect(sql, contains('fn_operacion_completada'));
    expect(sql, contains('fn_turnos_por_moneda'));
    expect(sql, contains('group by 1, 2'));
    expect(sql, contains('REVOKE ALL ON FUNCTION public.fn_turnos_por_moneda'));
    // Sin SECURITY DEFINER: las tablas de turno, operaciones y pagos tienen RLS.
    final cuerpo = sql.substring(sql.indexOf('FUNCTION public.fn_turnos_por_moneda'));
    expect(cuerpo.contains('SECURITY DEFINER'), isFalse);
  });
}

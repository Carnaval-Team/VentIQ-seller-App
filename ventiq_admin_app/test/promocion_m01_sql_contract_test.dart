import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contrato estático de los scripts aditivos `_m01` del pase newa -> main
/// (sql_updates/promocion_m01/). Inspecciona el texto: no ejecuta PL/pgSQL ni
/// sustituye aplicarlos en PostgreSQL (primero en newa, luego en main).
const _dir = '../sql_updates/promocion_m01';

String _leer(String archivo) =>
    File('$_dir/$archivo').readAsStringSync().replaceAll('\r\n', '\n');

/// Nombres antiguos que el script NO puede redefinir ni llamar.
String _sinComentarios(String sql) => sql
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('--'))
    .join('\n');

final _scripts = <String, List<String>>{
  '01_helpers_alineacion.sql': [
    'fn_turno_alinear_fecha_apertura',
    'fn_alinear_apertura_turno_offline',
    'fn_caja_disponible_para_egreso',
  ],
  '02_apertura_turno_m01.sql': [
    'fn_apertura_turno_offline_m01',
    'fn_apertura_turno_offline_usd_m01',
    'fn_apertura_turno_offline_monedas_m01',
  ],
  '03_cerrar_turno_m01.sql': [
    'fn_cerrar_turno_offline_m01',
    'fn_cerrar_turno_offline_usd_m01',
    'fn_cerrar_turno_offline_monedas_m01',
  ],
  '04_egreso_m01.sql': [
    'fn_registrar_egreso_offline_m01',
    'fn_registrar_egreso_offline_v2_m01',
  ],
  '05_venta_pago_estado_comanda_m01.sql': [
    'fn_registrar_venta_offline_v4_m01',
    'fn_registrar_pago_venta_offline_m01',
    'fn_registrar_cambio_estado_offline_m01',
    'fn_cambiar_estado_comanda_item_offline_m01',
  ],
  '06_listar_ordenes_precio_m01.sql': [
    'fn_listar_ordenes_m01',
    'fn_actualizar_precio_promedio_recepcion_v2_m01',
  ],
};

/// Los 14 nombres antiguos (cuerpo main) que estos scripts no deben tocar.
const _antiguos = <String>[
  'fn_apertura_turno_offline',
  'fn_apertura_turno_offline_usd',
  'fn_apertura_turno_offline_monedas',
  'fn_cerrar_turno_offline',
  'fn_cerrar_turno_offline_usd',
  'fn_cerrar_turno_offline_monedas',
  'fn_cambiar_estado_comanda_item_offline',
  'fn_registrar_cambio_estado_offline',
  'fn_registrar_egreso_offline',
  'fn_registrar_egreso_offline_v2',
  'fn_registrar_pago_venta_offline',
  'fn_registrar_venta_offline_v4',
  'fn_listar_ordenes',
  'fn_actualizar_precio_promedio_recepcion_v2',
];

void main() {
  test('existen README y los seis scripts', () {
    expect(File('$_dir/00_README.md').existsSync(), isTrue);
    for (final nombre in _scripts.keys) {
      expect(File('$_dir/$nombre').existsSync(), isTrue, reason: nombre);
    }
  });

  group('cada script define sus funciones', () {
    _scripts.forEach((archivo, funciones) {
      test(archivo, () {
        final sql = _leer(archivo);
        for (final f in funciones) {
          expect(
            sql,
            contains('FUNCTION public.$f('),
            reason: '$archivo debe crear $f',
          );
        }
        expect(sql, contains('SECURITY DEFINER'));
      });
    });
  });

  group('no reemplaza ni llama nombres antiguos', () {
    for (final archivo in _scripts.keys.where((a) => !a.startsWith('01_'))) {
      test(archivo, () {
        final sql = _sinComentarios(_leer(archivo));
        for (final viejo in _antiguos) {
          expect(
            RegExp('FUNCTION\\s+public\\.$viejo\\s*\\(').hasMatch(sql),
            isFalse,
            reason: '$archivo no debe crear/reemplazar $viejo(',
          );
          expect(
            RegExp('public\\.$viejo\\s*\\(').hasMatch(sql),
            isFalse,
            reason: '$archivo no debe llamar a $viejo( sin sufijo _m01',
          );
        }
      });
    }

    test('01 no redefine ningún nombre antiguo', () {
      final sql = _sinComentarios(_leer('01_helpers_alineacion.sql'));
      for (final viejo in _antiguos) {
        expect(
          RegExp('FUNCTION\\s+public\\.$viejo\\s*\\(').hasMatch(sql),
          isFalse,
          reason: viejo,
        );
      }
    });
  });

  group('permisos', () {
    _scripts.forEach((archivo, funciones) {
      test(archivo, () {
        final sql = _leer(archivo);
        expect(sql, contains('REVOKE ALL ON FUNCTION'));
        expect(sql, contains('FROM PUBLIC'));
        for (final f in funciones) {
          expect(
            RegExp('GRANT EXECUTE ON FUNCTION public\\.$f\\(').hasMatch(sql),
            isTrue,
            reason: '$archivo: GRANT para $f',
          );
        }
        expect(sql, contains('service_role'));
      });
    });
  });

  group('cadena de apertura', () {
    late String sql;
    setUpAll(() => sql = _leer('02_apertura_turno_m01.sql'));

    test('monedas_m01 llama a usd_m01 y nunca a la antigua', () {
      final monedas = sql.substring(
        sql.indexOf('FUNCTION public.fn_apertura_turno_offline_monedas_m01('),
      );
      expect(monedas, contains('public.fn_apertura_turno_offline_usd_m01('));
      expect(
        RegExp(r'public\.fn_apertura_turno_offline_usd\(').hasMatch(monedas),
        isFalse,
      );
    });

    test('usd_m01 llama a apertura_m01 y nunca a la antigua', () {
      final inicio = sql.indexOf(
        'FUNCTION public.fn_apertura_turno_offline_usd_m01(',
      );
      final fin = sql.indexOf(
        'FUNCTION public.fn_apertura_turno_offline_monedas_m01(',
      );
      final usd = sql.substring(inicio, fin);
      expect(usd, contains('public.fn_apertura_turno_offline_m01('));
      expect(
        RegExp(r'public\.fn_apertura_turno_offline\(').hasMatch(usd),
        isFalse,
      );
    });

    test('apertura_m01 conserva el arreglo H1 (id_turno)', () {
      expect(sql, contains("'id_turno', v_turno_resuelto"));
      expect(sql, contains('fn_turno_alinear_fecha_apertura'));
    });
  });

  group('cadena de cierre', () {
    late String sql;
    setUpAll(() => sql = _leer('03_cerrar_turno_m01.sql'));

    test('monedas_m01 -> usd_m01 -> cerrar_m01', () {
      final inicioUsd = sql.indexOf(
        'FUNCTION public.fn_cerrar_turno_offline_usd_m01(',
      );
      final inicioMonedas = sql.indexOf(
        'FUNCTION public.fn_cerrar_turno_offline_monedas_m01(',
      );
      final usd = sql.substring(inicioUsd, inicioMonedas);
      final monedas = sql.substring(inicioMonedas);
      expect(usd, contains('public.fn_cerrar_turno_offline_m01('));
      expect(monedas, contains('public.fn_cerrar_turno_offline_usd_m01('));
      expect(
        RegExp(r'public\.fn_cerrar_turno_offline\(').hasMatch(usd),
        isFalse,
      );
      expect(
        RegExp(r'public\.fn_cerrar_turno_offline_usd\(').hasMatch(monedas),
        isFalse,
      );
    });
  });

  group('egreso', () {
    test('v2_m01 valida saldo (C14)', () {
      final sql = _leer('04_egreso_m01.sql');
      final v2 = sql.substring(
        sql.indexOf('FUNCTION public.fn_registrar_egreso_offline_v2_m01('),
      );
      expect(v2, contains('EGRESO_SIN_SALDO'));
      expect(v2, contains('public.fn_caja_disponible_para_egreso('));
      expect(
        RegExp(r'public\.fn_registrar_egreso_offline\(').hasMatch(v2),
        isFalse,
      );
    });
  });

  group('preflight', () {
    for (final archivo in _scripts.keys.where((a) => !a.startsWith('01_'))) {
      test(archivo, () {
        expect(_leer(archivo), contains(r'DO $preflight$'));
      });
    }
  });
}

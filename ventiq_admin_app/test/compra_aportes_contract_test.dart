// Contrato de la fase 7 de Compras: aportes de inversores al 100 %.
//
// Dos mitades, ninguna toca la red:
//  1. el archivo SQL desplegado expone las tres RPC y `fn_fdi_compra_pagar`
//     tiene su rama de aportes;
//  2. `AportesResumen.fromJson` parsea el jsonb de `fn_fdi_compra_aportes` con
//     las cifras del contrato.
//
// No sustituye una ejecución real en PostgreSQL: la RPC decide el faltante.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/aportes_resumen.dart';

/// Redondeo a dos decimales, igual que `round(x, 2)` en PostgreSQL.
double _r2(double valor) => (valor * 100).round() / 100;

/// Bloque de una función del script, desde su `CREATE` hasta el siguiente.
String _cuerpoFuncion(String sql, String nombre) {
  final inicio = sql.indexOf('FUNCTION public.$nombre(');
  expect(inicio, greaterThan(-1), reason: 'falta $nombre en el script');
  final resto = sql.substring(inicio);
  final fin = resto.indexOf('CREATE OR REPLACE FUNCTION', 1);
  return fin == -1 ? resto : resto.substring(0, fin);
}

void main() {
  group('SQL desplegado', () {
    final sql = File(
      'lib/sql/compra/07_aportes_inversores.sql',
    ).readAsStringSync();

    test('expone las tres RPC de aportes a authenticated', () {
      expect(sql, contains('fn_fdi_compra_aportes(bigint)'));
      expect(sql, contains('fn_fdi_compra_aporte_registrar('));
      expect(sql, contains('fn_fdi_compra_aporte_devolver('));
      expect(
        sql,
        contains('GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_aportes'),
      );
    });

    test('fn_fdi_compra_pagar tiene la rama de aportes', () {
      final pagar = _cuerpoFuncion(sql, 'fn_fdi_compra_pagar');
      expect(
        pagar,
        anyOf(contains("'origen','aporte'"), contains("'aporte'")),
        reason: 'el pago en modo inversores debe marcar origen aporte',
      );
    });
  });

  group('AportesResumen.fromJson', () {
    // Ejemplo exacto del contrato de `fn_fdi_compra_aportes`.
    final resumen = AportesResumen.fromJson({
      'id_compra': 12,
      'modo_liquidacion': 'inversores',
      'estado': 'creada',
      'moneda': 'USD',
      'total': 2000.00,
      'aportado': 1500.00,
      'devuelto': 0.00,
      'faltante': 500.00,
      'pct': 75.00,
      'puede_registrar': false,
      'puede_pagar': false,
      'motivo_bloqueo': 'Faltan 500.00 USD',
      'aportes': [
        {
          'id': 3,
          'id_inversor': 4,
          'inversor': 'X Inversores',
          'porcentaje_inversor': 40.0,
          'naturaleza': 'anticipo',
          'moneda': 'USD',
          'monto': 800.00,
          'tasa_a_total': 1.0,
          'monto_eq_total': 800.00,
          'tasa_interes': null,
          'interes_estimado': 0.00,
          'comprobante': null,
          'observacion': null,
          'estado': 'aportado',
          'devuelto_at': null,
          'motivo_devolucion': null,
          'created_at': '2026-11-23T15:10:00Z',
        },
      ],
    });

    test('lee las cifras de cabecera', () {
      expect(resumen.idCompra, 12);
      expect(resumen.modoLiquidacion, 'inversores');
      expect(resumen.estado, 'creada');
      expect(resumen.moneda, 'USD');
      expect(resumen.total, 2000.00);
      expect(resumen.aportado, 1500.00);
      expect(resumen.devuelto, 0.00);
      expect(resumen.faltante, 500.00);
      expect(resumen.pct, 75.00);
      expect(resumen.puedePagar, isFalse);
      expect(resumen.puedeRegistrar, isFalse);
      expect(resumen.motivoBloqueo, 'Faltan 500.00 USD');
    });

    test('el faltante es el total menos lo aportado, a dos decimales', () {
      expect(_r2(resumen.total - resumen.aportado), resumen.faltante);
      expect(resumen.cubierto, isFalse);
      expect(resumen.pctPendiente, 25.00);
      expect(resumen.avisoPostPago, isFalse);
    });

    test('lee el aporte y su estado', () {
      expect(resumen.aportes, hasLength(1));
      final aporte = resumen.aportes.single;
      expect(aporte.id, 3);
      expect(aporte.idInversor, 4);
      expect(aporte.inversor, 'X Inversores');
      expect(aporte.porcentajeInversor, 40.0);
      expect(aporte.naturaleza, 'anticipo');
      expect(aporte.naturalezaLegible, 'Anticipo');
      expect(aporte.moneda, 'USD');
      expect(aporte.monto, 800.00);
      expect(aporte.tasaATotal, 1.0);
      expect(aporte.montoEqTotal, 800.00);
      expect(aporte.tasaInteres, isNull);
      expect(aporte.interesEstimado, 0.00);
      expect(aporte.estado, 'aportado');
      expect(aporte.estadoLegible, 'Aportado');
      expect(aporte.esDevuelto, isFalse);
      expect(aporte.devueltoAt, isNull);
      expect(aporte.motivoDevolucion, isNull);
      expect(aporte.createdAt, DateTime.utc(2026, 11, 23, 15, 10));
      // El `%` de la barra es el del aporte sobre el total, no el del inversor.
      expect(aporte.parteDelTotal(resumen.total), 40.00);
    });

    test('todos los aportes declaran un estado del contrato', () {
      for (final aporte in resumen.aportes) {
        expect(
          aporte.estado,
          anyOf(aporteEstadoAportado, aporteEstadoDevuelto),
          reason: 'estado inesperado: ${aporte.estado}',
        );
      }
      expect(resumen.aportesVigentes, hasLength(1));
      expect(resumen.aportesDevueltos, isEmpty);
      expect(resumen.sumaVigente, 800.00);
      expect(resumen.inversoresComprometidos, 1);
      expect(resumen.importeDeInversor(4), 800.00);
      expect(resumen.parteDeInversor(4), 40.00);
    });
  });

  group('cobertura incompleta posterior al pago', () {
    // Compras 07: si se devuelve un aporte de una compra ya pagada, el faltante
    // vuelve a ser > 0 y el motivo es «La compra ya está pagada». No es un
    // bloqueo nuevo: es un aviso.
    final resumen = AportesResumen.fromJson({
      'id_compra': 20,
      'modo_liquidacion': 'inversores',
      'estado': 'pagada',
      'moneda': 'CUP',
      'total': 1000.00,
      'aportado': 600.00,
      'devuelto': 400.00,
      'faltante': 400.00,
      'pct': 60.00,
      'puede_registrar': false,
      'puede_pagar': false,
      'motivo_bloqueo': 'La compra ya está pagada',
      'aportes': [
        {
          'id': 31,
          'id_inversor': 7,
          'inversor': 'Inversor Dos',
          'porcentaje_inversor': 60.0,
          'naturaleza': 'pasivo',
          'moneda': 'CUP',
          'monto': 600.00,
          'tasa_a_total': 1.0,
          'monto_eq_total': 600.00,
          'tasa_interes': 0.05,
          'interes_estimado': 30.00,
          'estado': 'aportado',
          'created_at': '2026-11-20T09:00:00Z',
        },
        {
          'id': 32,
          'id_inversor': 8,
          'inversor': 'Inversor Tres',
          'porcentaje_inversor': 40.0,
          'naturaleza': 'anticipo',
          'moneda': 'CUP',
          'monto': 400.00,
          'tasa_a_total': 1.0,
          'monto_eq_total': 400.00,
          'estado': 'devuelto',
          'devuelto_at': '2026-11-21T10:30:00Z',
          'motivo_devolucion': 'El inversor retiró el anticipo',
          'created_at': '2026-11-19T08:00:00Z',
        },
      ],
    });

    test('se marca como aviso, no como bloqueo nuevo', () {
      expect(resumen.avisoPostPago, isTrue);
      expect(resumen.puedePagar, isFalse);
      expect(resumen.motivoBloqueo, 'La compra ya está pagada');
    });

    test('separa vigentes de devueltos y conserva el motivo', () {
      expect(resumen.aportesVigentes, hasLength(1));
      expect(resumen.aportesDevueltos, hasLength(1));
      final devuelto = resumen.aportesDevueltos.single;
      expect(devuelto.esDevuelto, isTrue);
      expect(devuelto.estadoLegible, 'Devuelto');
      expect(devuelto.motivoDevolucion, 'El inversor retiró el anticipo');
      expect(devuelto.parteDelTotal(resumen.total), 40.00);
      expect(resumen.sumaVigente, 600.00);
      expect(resumen.sumaDevuelta, 400.00);
      expect(_r2(resumen.total - resumen.aportado), resumen.faltante);
      expect(resumen.pctPendiente, 40.00);
    });

    test('un pasivo conserva su tasa y su interés estimado', () {
      final pasivo = resumen.aportesVigentes.single;
      expect(pasivo.tasaInteres, 0.05);
      expect(pasivo.interesEstimado, 30.00);
      expect(pasivo.naturalezaLegible, 'Pasivo');
    });
  });
}
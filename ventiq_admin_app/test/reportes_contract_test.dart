// Contrato de la fase 8 de Reportes (Fondo de Inversión → Compras).
//
// Dos mitades, ninguna toca la red ni monta widgets:
//  1. los helpers de normalización de jsonb, la diferencia total de la
//     conciliación y los descuadres, con payloads del contrato pasados por
//     `jsonDecode` (importes como número **y** como texto);
//  2. los scripts SQL desplegados: existen y `08_reportes.sql` declara las 7
//     firmas `fn_fdi_reporte_*`, sin reescribir `fn_fdi_conciliacion` (R1).
//
// No sustituye una ejecución real en PostgreSQL.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/screens/reportes/reportes_calculos.dart';

Map<String, dynamic> _json(String fuente) =>
    jsonDecode(fuente) as Map<String, dynamic>;

void main() {
  // =========================================================================
  // Normalización
  // =========================================================================

  group('normalización de jsonb', () {
    final payload = _json('''
    {
      "numero": 148.3,
      "entero": 3,
      "texto": "484599.00",
      "negativo": "-0.01",
      "nulo": null,
      "vacio": "   ",
      "no_numerico": "n/d"
    }
    ''');

    test('numero acepta número y texto, y cae a 0 sin dato', () {
      expect(numero(payload['numero']), 148.3);
      expect(numero(payload['entero']), 3.0);
      expect(numero(payload['texto']), 484599.00);
      expect(numero(payload['negativo']), -0.01);
      expect(numero(payload['nulo']), 0);
      expect(numero(payload['vacio']), 0);
      expect(numero(payload['no_numerico']), 0);
    });

    test('numeroONulo conserva el null', () {
      expect(numeroONulo(null), isNull);
      expect(numeroONulo('  '), isNull);
      expect(numeroONulo('3.4'), 3.4);
      expect(numeroONulo(0), 0);
    });

    test('booleano, textoOGuion y listaDeMapas toleran la forma real', () {
      expect(booleano(true), isTrue);
      expect(booleano('true'), isTrue);
      expect(booleano(1), isTrue);
      expect(booleano(0), isFalse);
      expect(booleano(null), isFalse);
      expect(textoOGuion(null), '—');
      expect(textoOGuion('   '), '—');
      expect(textoOGuion('CUP'), 'CUP');
      expect(listaDeMapas(null), isEmpty);
      expect(listaDeMapas({'a': 1}), isEmpty);
      expect(
        listaDeMapas([
          {'a': 1},
          'x',
          2,
          null,
        ]).length,
        1,
      );
    });

    test('cifraPorcentaje usa un decimal', () {
      final texto = cifraPorcentaje(3.4);
      expect(texto.replaceAll(RegExp(r'[^0-9]'), ''), '34');
    });
  });

  // =========================================================================
  // Conciliación (R1)
  // =========================================================================

  group('conciliación', () {
    // Payload con la forma de `fn_fdi_conciliacion`: `claves` y `descuadres`
    // son escalares, no arrays. Una clave descuadrada con céntimos.
    final payload = _json('''
    {
      "id_tienda": 4,
      "claves": 3,
      "descuadres": 1,
      "filas": [
        {
          "id_cuenta": 1,
          "id_medio_pago": 1,
          "moneda": "CUP",
          "saldo": "148300.00",
          "suma_movimientos": "148300.00",
          "ultimo_saldo_nuevo": "148300.00",
          "dif_saldo_vs_mov": "0.00",
          "dif_saldo_vs_ultimo": "0.00",
          "n_movimientos": 12,
          "ok": true
        },
        {
          "id_cuenta": 2,
          "id_medio_pago": 2,
          "moneda": "CUP",
          "saldo": 612480.50,
          "suma_movimientos": 612480.49,
          "ultimo_saldo_nuevo": 612480.60,
          "dif_saldo_vs_mov": 0.01,
          "dif_saldo_vs_ultimo": -0.02,
          "n_movimientos": 9,
          "ok": false
        },
        {
          "id_cuenta": 3,
          "id_medio_pago": 3,
          "moneda": "USD",
          "saldo": 18420.00,
          "suma_movimientos": 18420.00,
          "ultimo_saldo_nuevo": 18420.00,
          "dif_saldo_vs_mov": 0,
          "dif_saldo_vs_ultimo": 0,
          "n_movimientos": 4,
          "ok": true
        }
      ]
    }
    ''');
    final filas = listaDeMapas(payload['filas']);

    test('claves y descuadres son escalares', () {
      expect(numero(payload['claves']).round(), 3);
      expect(numero(payload['descuadres']).round(), 1);
      expect(payload['claves'], isA<num>());
      expect(payload['descuadres'], isA<num>());
    });

    test(
      'diferencia total = Σ abs(vs movimientos) + abs(vs último), por moneda',
      () {
        final diferencias = diferenciaTotalConciliacion(filas);
        expect(diferencias.keys.toSet(), {'CUP', 'USD'});
        expect(diferencias['CUP'], closeTo(0.03, 1e-9));
        expect(diferencias['USD'], closeTo(0.0, 1e-9));
        // No se suma una moneda a la otra: no existe un total único.
        expect(diferencias.length, 2);
      },
    );

    test('descuadre por fila y umbral de céntimos', () {
      expect(descuadreFilaConciliacion(filas[1]), closeTo(0.03, 1e-9));
      expect(filaConciliacionOk(filas[1]), isFalse);
      expect(filaConciliacionOk(filas[0]), isTrue);

      // 0.004 + 0.004 = 0.008, por debajo del umbral del módulo (0.009).
      final redondeada = <String, dynamic>{
        'dif_saldo_vs_mov': '0.004',
        'dif_saldo_vs_ultimo': '-0.004',
        'ok': true,
      };
      expect(descuadreFilaConciliacion(redondeada), closeTo(0.008, 1e-9));
      expect(filaConciliacionOk(redondeada), isTrue);
    });

    test('descuadresEfectivos no miente a la baja', () {
      // El servidor dice 0 pero hay una fila con diferencias: manda el cálculo.
      expect(descuadresEfectivos(descuadres: 0, filas: filas), 1);
      // Si el servidor reporta más, se respeta su número.
      expect(descuadresEfectivos(descuadres: 2, filas: filas), 2);
      expect(descuadresEfectivos(descuadres: '2', filas: filas), 2);
      expect(descuadresEfectivos(descuadres: '0', filas: const []), 0);
    });

    test('totalesPorMoneda separa cada moneda', () {
      final texto = totalesPorMoneda({'CUP': 0, 'USD': 0});
      expect(texto, contains('CUP'));
      expect(texto, contains('USD'));
      expect(texto, contains(' · '));
      expect(totalesPorMoneda(const {}), '—');
      expect(totalesPorMoneda({'CUP': 12.5}), '${cifra(12.5)} CUP');
    });
  });

  // =========================================================================
  // Aging y descuadres declarados
  // =========================================================================

  group('aging y descuadres', () {
    final payload = _json('''
    {
      "id_tienda": 4,
      "reservas_activas": [
        {
          "id_reserva": 7,
          "id_compra": 11,
          "numero_compra": "A-1018",
          "numero_factura": "F-88",
          "id_cuenta": 3,
          "id_medio_pago": 3,
          "moneda": "USD",
          "monto": "12400.00",
          "dias_antiguedad": 41,
          "total_financiado": "12400.00",
          "estado_compra": "reservada"
        }
      ],
      "descuadres": [
        {
          "id_compra": 10,
          "numero_compra": "A-1041",
          "numero_factura": "F-71",
          "moneda": "USD",
          "estado_compra": "entrega_parcial",
          "total_financiado": "2000.00",
          "lineas": "1500.00",
          "ajustes_fondo": "0.00",
          "diferencia_financiado": "840.00",
          "pagado": "2000.00",
          "diferencia_pagos": "-240.00",
          "ultimo_motivo": "Pago parcial no aplicado"
        },
        {
          "id_compra": 12,
          "numero_compra": "A-1027",
          "numero_factura": null,
          "moneda": "CUP",
          "estado_compra": "completada",
          "total_financiado": "3400.00",
          "lineas": "3400.00",
          "ajustes_fondo": "0.00",
          "diferencia_financiado": "-120.00",
          "pagado": "3400.00",
          "diferencia_pagos": "0.00",
          "ultimo_motivo": null
        }
      ]
    }
    ''');
    final reservas = listaDeMapas(payload['reservas_activas']);
    final descuadres = listaDeMapas(payload['descuadres']);

    test('descuadre por compra = abs(dif financiado) + abs(dif pagos)', () {
      expect(descuadreFilaAging(descuadres[0]), closeTo(1080.0, 1e-9));
      expect(descuadreFilaAging(descuadres[1]), closeTo(120.0, 1e-9));
    });

    test('el descuadre declarado se agrega por moneda', () {
      final total = descuadreAging(descuadres);
      expect(total['USD'], closeTo(1080.0, 1e-9));
      expect(total['CUP'], closeTo(120.0, 1e-9));
    });

    test('la reserva trae días de antigüedad y su moneda nativa', () {
      expect(numero(reservas.first['dias_antiguedad']).round(), 41);
      expect(numero(reservas.first['monto']), 12400.00);
      expect(monedaDe(reservas.first), 'USD');
    });
  });

  // =========================================================================
  // Movimientos
  // =========================================================================

  group('movimientos', () {
    final payload = _json('''
    {
      "desde": "2026-11-22",
      "hasta": "2026-11-23",
      "por_dia_usuario": [
        {
          "dia": "2026-11-22",
          "usuario": "carlos@tienda",
          "moneda": "CUP",
          "n": 2,
          "entradas": "0.00",
          "salidas": "22400.00",
          "neto": "-22400.00"
        },
        {
          "dia": "2026-11-23",
          "usuario": "yamile@tienda",
          "moneda": "CUP",
          "n": 4,
          "entradas": "74320.00",
          "salidas": "12000.00",
          "neto": "62320.00"
        },
        {
          "dia": "2026-11-23",
          "usuario": "yamile@tienda",
          "moneda": "USD",
          "n": 2,
          "entradas": "2100.00",
          "salidas": "560.00",
          "neto": "1540.00"
        }
      ],
      "totales_por_moneda": [
        {"moneda": "CUP", "n": 6, "entradas": "74320.00", "salidas": "34400.00", "neto": "39920.00"},
        {"moneda": "USD", "n": 2, "entradas": "2100.00", "salidas": "560.00", "neto": "1540.00"}
      ]
    }
    ''');
    final filas = listaDeMapas(payload['por_dia_usuario']);

    test('se agrupa por día, del más reciente al más antiguo', () {
      final porDia = agruparMovimientosPorDia(filas);
      expect(porDia.length, 2);
      expect(porDia.keys.first, DateTime(2026, 11, 23));
      expect(porDia.keys.last, DateTime(2026, 11, 22));
      expect(porDia[DateTime(2026, 11, 23)]!.length, 2);
    });

    test('subtotal por moneda: entradas, salidas, neto y movimientos', () {
      final subtotales = subtotalesMoneda(filas);
      expect(subtotales['CUP']!.n, 6);
      expect(subtotales['CUP']!.entradas, closeTo(74320.0, 1e-9));
      expect(subtotales['CUP']!.salidas, closeTo(34400.0, 1e-9));
      expect(subtotales['CUP']!.neto, closeTo(39920.0, 1e-9));
      expect(subtotales['USD']!.neto, closeTo(1540.0, 1e-9));
    });

    test('etiqueta de día relativa a hoy', () {
      expect(
        etiquetaDia(
          DateTime(2026, 11, 23),
          hoy: DateTime(2026, 11, 23, 17, 42),
        ),
        'Hoy · 23 nov 2026',
      );
      expect(
        etiquetaDia(DateTime(2026, 11, 22), hoy: DateTime(2026, 11, 23)),
        'Ayer · 22 nov 2026',
      );
      expect(
        etiquetaDia(DateTime(2026, 10, 5), hoy: DateTime(2026, 11, 23)),
        '5 oct 2026',
      );
    });

    test('rango de la ventana y fechas', () {
      expect(
        rangoTexto(fechaDe(payload['desde']), fechaDe(payload['hasta'])),
        '22 nov – 23 nov 2026',
      );
      expect(rangoTexto(null, null), '—');
      expect(fechaNumerica(DateTime(2026, 1, 2)), '02/01/2026');
    });
  });

  // =========================================================================
  // SQL desplegado
  // =========================================================================

  group('SQL desplegado', () {
    const script = 'lib/sql/compra/08_reportes.sql';

    test('existen los scripts de la fase', () {
      for (final ruta in const [
        script,
        'lib/sql/compra/08_reportes_rollback.sql',
        'lib/sql/compra/verify/08_reportes.sql',
      ]) {
        expect(File(ruta).existsSync(), isTrue, reason: 'falta $ruta');
      }
    });

    test('08_reportes.sql declara las 7 firmas fn_fdi_reporte_*', () {
      final sql = File(script).readAsStringSync();
      const firmas = [
        'public.fn_fdi_reporte_caja(bigint)',
        'public.fn_fdi_reporte_compras(bigint,date,date)',
        'public.fn_fdi_reporte_costo(bigint,date,date)',
        'public.fn_fdi_reporte_cambiario(bigint,date,date)',
        'public.fn_fdi_reporte_movimientos(bigint,date,date)',
        'public.fn_fdi_reporte_inversores(bigint)',
        'public.fn_fdi_reporte_aging(bigint)',
      ];
      for (final firma in firmas) {
        expect(sql, contains(firma), reason: 'falta la firma $firma');
      }
      const nombres = [
        'fn_fdi_reporte_caja',
        'fn_fdi_reporte_compras',
        'fn_fdi_reporte_costo',
        'fn_fdi_reporte_cambiario',
        'fn_fdi_reporte_movimientos',
        'fn_fdi_reporte_inversores',
        'fn_fdi_reporte_aging',
      ];
      for (final nombre in nombres) {
        expect(
          sql,
          contains('CREATE OR REPLACE FUNCTION public.$nombre('),
          reason: 'falta el CREATE de $nombre',
        );
      }
    });

    test('08_reportes.sql no reescribe fn_fdi_conciliacion (R1)', () {
      final sql = File(script).readAsStringSync();
      expect(
        sql,
        isNot(
          contains('CREATE OR REPLACE FUNCTION public.fn_fdi_conciliacion'),
        ),
        reason: 'R1 se usa, no se reescribe',
      );
      // La sigue requiriendo, no la sustituye.
      expect(sql, contains('fn_fdi_conciliacion(bigint)'));
    });

    test('el servicio llama a las RPC del contrato', () {
      final servicio = File(
        'lib/services/reportes_service.dart',
      ).readAsStringSync();
      for (final rpc in const [
        'fn_fdi_reporte_caja',
        'fn_fdi_reporte_compras',
        'fn_fdi_reporte_costo',
        'fn_fdi_reporte_cambiario',
        'fn_fdi_reporte_movimientos',
        'fn_fdi_reporte_inversores',
        'fn_fdi_reporte_aging',
        'fn_fdi_conciliacion',
        'fn_fdi_conciliacion_ultima',
      ]) {
        expect(servicio, contains(rpc), reason: 'el servicio no usa $rpc');
      }
      // La tienda va siempre primero y las fechas son opcionales.
      expect(servicio, contains("'p_id_tienda': idTienda"));
      expect(servicio, contains("if (desde != null) 'p_desde'"));
    });
  });
}

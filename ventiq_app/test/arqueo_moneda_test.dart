import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/money/arqueo_moneda.dart';

void main() {
  test('cada moneda se verifica sola: lo que sobra no compensa lo que falta', () {
    final arqueos = ArqueoMoneda.lista(
      monedas: ['CUP', 'USD'],
      contado: {'CUP': 14450, 'USD': 25},
      esperado: {'CUP': 15200, 'USD': 23.10},
    );

    expect(arqueos[0].moneda, 'CUP');
    expect(arqueos[0].estado, EstadoArqueo.falta);
    expect(arqueos[0].diferencia, -750);
    expect(arqueos[1].moneda, 'USD');
    expect(arqueos[1].estado, EstadoArqueo.sobra);
    expect(arqueos[1].diferencia, closeTo(1.9, 1e-9));
  });

  test('cuadra dentro del medio centavo y sin esperado no hay veredicto', () {
    expect(
      const ArqueoMoneda(moneda: 'USD', contado: 23.1, esperado: 23.10)
          .estado,
      EstadoArqueo.cuadra,
    );
    expect(
      const ArqueoMoneda(moneda: 'USD', contado: 23.103, esperado: 23.1)
          .estado,
      EstadoArqueo.cuadra,
    );
    final sin = ArqueoMoneda.lista(
      monedas: ['CUP'],
      contado: {'CUP': 10},
    ).single;
    expect(sin.estado, EstadoArqueo.sinEsperado);
    expect(sin.diferencia, isNull);
  });

  test('una moneda sin conteo se reporta como cero, no desaparece', () {
    final usd = ArqueoMoneda.lista(
      monedas: ['CUP', 'USD'],
      contado: {'CUP': 100},
      esperado: {'CUP': 100, 'USD': 23.1},
    ).last;
    expect(usd.contado, 0);
    expect(usd.estado, EstadoArqueo.falta);
  });

  test('en el diálogo, Debe haber y Falta/Sobra van en filas distintas', () {
    final src = File('lib/widgets/cash_count_dialog.dart').readAsStringSync();
    final card = src.substring(src.indexOf('Widget _buildArqueoCard'));
    expect(card, contains("'Debe haber:"));
    expect(card, contains("'Contado:"));
    // Falta/Sobra es su propio bloque debajo de Debe haber, no un Row compartido.
    expect(card, contains('if (textoEstado.isNotEmpty)'));
    expect(card, isNot(contains('MainAxisAlignment.spaceBetween')));
  });
}

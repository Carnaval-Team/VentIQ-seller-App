import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/theme/ventiq_home_theme.dart';
import 'package:ventiq_app/utils/categoria_gradiente.dart';

void main() {
  group('gradienteCategoria', () {
    test('es determinista: el mismo id da siempre el mismo par', () {
      for (final int id in <int>[0, 1, 7, 12, 189, 846, 999999]) {
        final List<Color> a = gradienteCategoria(id);
        final List<Color> b = gradienteCategoria(id);
        expect(a, equals(b));
      }
    });

    test('devuelve siempre 2 colores', () {
      for (int id = 0; id < 40; id++) {
        expect(gradienteCategoria(id).length, 2);
      }
    });

    test('recorre toda la paleta', () {
      final Set<int> vistos = <int>{};
      for (int id = 0; id < VentiqHomeTheme.cardGradients.length; id++) {
        vistos.add(gradienteCategoria(id).first.toARGB32());
      }
      expect(vistos.length, VentiqHomeTheme.cardGradients.length);
    });

    test('un id negativo no rompe el índice', () {
      expect(gradienteCategoria(-5), equals(gradienteCategoria(5)));
    });

    test('ids consecutivos no dan el mismo color (categorías vecinas)', () {
      // En el catálogo real las categorías de una tienda suelen tener ids
      // consecutivos: si el degradado fuese por id/par, se verían todas iguales.
      expect(
        gradienteCategoria(10).first,
        isNot(equals(gradienteCategoria(11).first)),
      );
    });
  });

  group('gradienteCategoriaPorNombre (fallback)', () {
    test('es estable para el mismo nombre', () {
      expect(
        gradienteCategoriaPorNombre('Combustibles'),
        equals(gradienteCategoriaPorNombre('combustibles')),
      );
    });

    test('un nombre vacío no revienta', () {
      expect(gradienteCategoriaPorNombre('').length, 2);
    });
  });

  test('los degradados de la paleta tienen sus 2 colores definidos', () {
    for (final List<Color> par in paletaGradientesCategoria) {
      expect(par.length, 2);
      expect(par[0], isNot(equals(par[1])), reason: 'un degradado plano no aporta nada');
    }
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/services/moneda_venta_service.dart';
import 'package:ventiq_app/utils/price_utils.dart';

/// Formateo síncrono de precios según la moneda de venta activa.
///
/// Es la pieza que usan las pantallas dentro de `build()`: no puede ser async,
/// así que la moneda y sus tasas viven en memoria. Lo que se prueba aquí es que
/// nunca formatea en una divisa que no se puede convertir.
void main() {
  tearDown(() {
    // Dejar el estado limpio entre tests.
    MonedaVentaService.configurar(
      moneda: 'CUP',
      tasasDisponibles: const {'CUP': 1},
    );
  });

  group('formatearPrecio', () {
    test('moneda base: formatea en CUP', () {
      MonedaVentaService.configurar(
        moneda: 'CUP',
        tasasDisponibles: {'CUP': 1, 'USD': 900},
      );
      final texto = MonedaVentaService.formatearPrecio(45000);
      expect(texto, contains('CUP'));
      expect(texto, contains('45'));
    });

    test('divisa con tasa: convierte y rotula la divisa', () {
      MonedaVentaService.configurar(
        moneda: 'USD',
        tasasDisponibles: {'CUP': 1, 'USD': 900},
      );
      final texto = MonedaVentaService.formatearPrecio(45000);
      expect(texto, contains('USD'));
      expect(texto, contains('50'));
      expect(texto, isNot(contains('CUP')));
    });

    test('sin tasa para la moneda activa cae a CUP (no miente)', () {
      // Se configura USD sin tasa: debe caer a la base.
      MonedaVentaService.configurar(
        moneda: 'USD',
        tasasDisponibles: {'CUP': 1},
      );
      expect(MonedaVentaService.actual, 'CUP');
      expect(MonedaVentaService.formatearPrecio(45000), contains('CUP'));
    });

    test('código inválido cae a CUP', () {
      MonedaVentaService.configurar(
        moneda: 'eu',
        tasasDisponibles: {'CUP': 1, 'EUR': 990},
      );
      expect(MonedaVentaService.actual, 'CUP');
    });
  });

  group('formatearPrecio · conSimbolo (compatibilidad visual)', () {
    test('moneda base con símbolo: idéntico al formato anterior', () {
      MonedaVentaService.configurar(
        moneda: 'CUP',
        tasasDisponibles: {'CUP': 1, 'USD': 900},
      );
      // Lo que pintaban las pantallas antes: '\$${precio.toMoneyString(2)}'.
      expect(
        MonedaVentaService.formatearPrecio(45000, conSimbolo: true),
        '\$${45000.toMoneyString(2)}',
      );
    });

    test('divisa alternativa: rotula la divisa, sin símbolo de dólar', () {
      MonedaVentaService.configurar(
        moneda: 'EUR',
        tasasDisponibles: {'CUP': 1, 'EUR': 990},
      );
      final texto = MonedaVentaService.formatearPrecio(45000, conSimbolo: true);
      expect(texto, '45.45 EUR');
      expect(texto, contains('EUR'));
      expect(texto, isNot(startsWith('\$')));
    });

    test('respeta los decimales de cada pantalla', () {
      MonedaVentaService.configurar(
        moneda: 'CUP',
        tasasDisponibles: {'CUP': 1},
      );
      expect(
        MonedaVentaService.formatearPrecio(45000, decimales: 0, conSimbolo: true),
        '\$${45000.toMoneyString(0)}',
      );
    });

    test('enDivisaAlternativa solo con divisa con tasa', () {
      MonedaVentaService.configurar(
        moneda: 'CUP',
        tasasDisponibles: {'CUP': 1, 'EUR': 990},
      );
      expect(MonedaVentaService.enDivisaAlternativa, isFalse);

      MonedaVentaService.configurar(
        moneda: 'EUR',
        tasasDisponibles: {'CUP': 1, 'EUR': 990},
      );
      expect(MonedaVentaService.enDivisaAlternativa, isTrue);
    });
  });

  group('convertirPrecio y hayVariasDivisas', () {
    test('convierte dividiendo por la tasa', () {
      MonedaVentaService.configurar(
        moneda: 'EUR',
        tasasDisponibles: {'CUP': 1, 'EUR': 990},
      );
      expect(MonedaVentaService.convertirPrecio(45000), closeTo(45.4545, 0.001));
    });

    test('en moneda base no convierte', () {
      MonedaVentaService.configurar(
        moneda: 'CUP',
        tasasDisponibles: {'CUP': 1, 'EUR': 990},
      );
      expect(MonedaVentaService.convertirPrecio(45000), 45000);
    });

    test('hayVariasDivisas refleja las tasas cargadas', () {
      MonedaVentaService.configurar(
        moneda: 'CUP',
        tasasDisponibles: {'CUP': 1},
      );
      expect(MonedaVentaService.hayVariasDivisas, isFalse);

      MonedaVentaService.configurar(
        moneda: 'CUP',
        tasasDisponibles: {'CUP': 1, 'EUR': 990},
      );
      expect(MonedaVentaService.hayVariasDivisas, isTrue);
    });
  });
}
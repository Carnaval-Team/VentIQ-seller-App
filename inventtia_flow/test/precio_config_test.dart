import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/precio_config.dart';

/// Configuración de precios automáticos (`flow.precio_config`, migración 60).
/// Los valores por defecto son los de la base: auto activo, USD, CUP entero y
/// divisas con dos decimales.
void main() {
  group('PrecioConfig — valores por defecto', () {
    test('sin datos usa los de la base', () {
      const config = PrecioConfig();
      expect(config.autoActivo, isTrue);
      expect(config.monedaOrigen, 'USD');
      expect(config.redondeoCup, 0);
      expect(config.redondeoDivisa, 2);
    });

    test('un JSON vacío o null no cambia nada', () {
      expect(PrecioConfig.fromJson(null), const PrecioConfig());
      expect(PrecioConfig.fromJson(const {}), const PrecioConfig());
    });
  });

  group('PrecioConfig.fromJson', () {
    test('lee la respuesta de admin_precio_config_get', () {
      final config = PrecioConfig.fromJson({
        'id_entidad': 7,
        'auto_activo': false,
        'moneda_origen': 'eur',
        'redondeo_cup': 1,
        'redondeo_divisa': 0,
        'tiene_fila': true,
      });
      expect(config.autoActivo, isFalse);
      expect(config.monedaOrigen, 'EUR', reason: 'se normaliza a mayúsculas');
      expect(config.redondeoCup, 1);
      expect(config.redondeoDivisa, 0);
    });

    test('tolera redondeos fuera de rango o como texto', () {
      final config = PrecioConfig.fromJson({
        'redondeo_cup': 9,
        'redondeo_divisa': '1',
      });
      expect(config.redondeoCup, 0, reason: 'fuera de 0-2 cae al defecto');
      expect(config.redondeoDivisa, 1);
    });

    test('una moneda de origen vacía cae a USD', () {
      expect(
        PrecioConfig.fromJson({'moneda_origen': '   '}).monedaOrigen,
        'USD',
      );
    });
  });

  group('PrecioConfig.decimalesDe', () {
    const config = PrecioConfig(redondeoCup: 0, redondeoDivisa: 2);

    test('CUP usa su propio redondeo', () {
      expect(config.decimalesDe('CUP'), 0);
      expect(config.copyWith(redondeoCup: 2).decimalesDe('CUP'), 2);
    });

    test('las divisas usan el redondeo de divisas', () {
      expect(config.decimalesDe('USD'), 2);
      expect(config.decimalesDe('EUR'), 2);
      expect(config.decimalesDe('MLC'), 2);
    });

    test('normaliza mayúsculas y espacios', () {
      expect(config.decimalesDe(' cup '), 0);
      expect(config.decimalesDe('usd'), 2);
    });
  });

  test('toJson / copyWith / igualdad', () {
    const config = PrecioConfig(
      autoActivo: false,
      monedaOrigen: 'CUP',
      redondeoCup: 1,
      redondeoDivisa: 2,
    );
    expect(config.toJson(), {
      'auto_activo': false,
      'moneda_origen': 'CUP',
      'redondeo_cup': 1,
      'redondeo_divisa': 2,
    });
    expect(config.copyWith(monedaOrigen: 'MLC').monedaOrigen, 'MLC');
    expect(config.copyWith(redondeoCup: 2).redondeoCup, 2);
    expect(config.copyWith(), config);
    expect(
      config == const PrecioConfig(autoActivo: false, monedaOrigen: 'CUP'),
      isFalse,
    );
  });
}